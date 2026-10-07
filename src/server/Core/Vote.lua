--[[
Party Dash Core: the lobby vote (three minigame cards, "choices" in the brief).

	Vote.init()                                -- remote Core_Vote(minigameId) + bookkeeping
	Vote.pickOptions(lastId, expectedPlayers)  -- Config.VOTE_OPTIONS distinct ids for this lobby
	Vote.open(options) / Vote.close()          -- GameState VoteOptions (CSV), VoteCounts (JSON { id = votes })
	Vote.resolve(participants) -> (id?, reelCandidates)

Only queued players vote (Player attribute Vote = id; leaving the square clears it). Resolution: Debug_ForceMinigame,
then Debug_ForceVote (Studio), else the eligible option (MinPlayers <= participants) with the most votes, ties and
"no votes" broken at random; if every option needs more players, a random eligible id from the whole pool.
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Net = require(Shared.Net)

local Debug = require(script.Parent.Debug)
local Join = require(script.Parent.Join)
local Registry = require(script.Parent.Registry)

local Vote = {}

local options: { string } = {}
local isOpen = false
local lastAccepted: { [Player]: number } = {}
local lastCountsJson = ""
local warned: { [string]: boolean } = {}

local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn("[Core] " .. message)
	end
end

local function shuffled(list: { string }): { string }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- Distinct ids, best first: fits the expected player count and was not just played, then games that need more
-- players, then last round's game (only when the pool is too small to avoid it).
function Vote.pickOptions(lastId: string?, expectedPlayers: number): { string }
	local fits, tooBig, repeated = {}, {}, {}
	for _, id in shuffled(Registry.votePool()) do
		if id == lastId then
			table.insert(repeated, id)
		elseif Registry.minPlayers(id) > expectedPlayers then
			table.insert(tooBig, id)
		else
			table.insert(fits, id)
		end
	end
	local picked = {}
	for _, bucket in { fits, tooBig, repeated } do
		for _, id in bucket do
			if #picked < Config.VOTE_OPTIONS then
				table.insert(picked, id)
			end
		end
	end
	return picked
end

local function counts(): { [string]: number }
	local out = {}
	for _, id in options do
		out[id] = 0
	end
	for _, p in Players:GetPlayers() do
		local v = p:GetAttribute("Vote")
		if p.Parent == Players and p:GetAttribute("Queued") == true and type(v) == "string" and out[v] then
			out[v] += 1
		end
	end
	return out
end

function Vote.recount()
	if not isOpen then
		return -- frozen once the lobby ends, so the roulette shows the final tally
	end
	local tally = counts()
	local json = if next(tally) == nil then "{}" else HttpService:JSONEncode(tally)
	if json ~= lastCountsJson then
		lastCountsJson = json
		GameState.write("VoteCounts", json)
	end
end

local function clearVote(player: Player)
	if player:GetAttribute("Vote") ~= "" then
		player:SetAttribute("Vote", "")
	end
end

function Vote.open(list: { string })
	options = table.clone(list)
	isOpen = true
	for _, p in Players:GetPlayers() do
		clearVote(p)
	end
	GameState.write("VoteOptions", table.concat(options, ","))
	Vote.recount()
end

function Vote.close()
	isOpen = false
end

-- Clears the offered cards (Waiting: nobody to vote).
function Vote.reset()
	Vote.close()
	options = {}
	lastCountsJson = "{}"
	GameState.write("VoteOptions", "")
	GameState.write("VoteCounts", "{}")
end

-- A Studio hook's id, if it names a loaded minigame (otherwise it is ignored with a warning).
local function loaded(hookName: string, id: string?): string?
	if id and not Registry.minigames[id] then
		warnOnce(("%s %q is not a loaded minigame; ignoring it"):format(hookName, id))
		return nil
	end
	return id
end

-- Returns the winning id (nil if no minigame is loaded) and the ids the roulette reel may show.
function Vote.resolve(participants: { Player }): (string?, { string })
	local candidates = table.clone(options)
	local function result(id: string): (string, { string })
		if not table.find(candidates, id) then
			table.insert(candidates, id)
		end
		return id, candidates
	end

	local forced = loaded("Debug_ForceMinigame", Debug.forceMinigame()) or loaded("Debug_ForceVote", Debug.forceVote())
	if forced then
		return result(forced)
	end

	local n = #participants
	local eligible = {}
	for _, id in options do
		if Registry.minigames[id] and Registry.minPlayers(id) <= n then
			table.insert(eligible, id)
		end
	end
	if #eligible == 0 then
		local pool = {}
		for _, id in Registry.votePool() do
			if Registry.minPlayers(id) <= n then
				table.insert(pool, id)
			end
		end
		if #pool == 0 then
			pool = Registry.votePool()
		end
		if #pool == 0 then
			return nil, candidates
		end
		return result(pool[math.random(1, #pool)])
	end

	local tally = {}
	for _, p in participants do
		local v = p:GetAttribute("Vote")
		if type(v) == "string" then
			tally[v] = (tally[v] or 0) + 1
		end
	end
	local best, top = -1, {}
	for _, id in eligible do
		local c = tally[id] or 0
		if c > best then
			best, top = c, { id }
		elseif c == best then
			table.insert(top, id)
		end
	end
	return result(top[math.random(1, #top)])
end

local function onVote(player: Player, id: any)
	if not isOpen or type(id) ~= "string" or not table.find(options, id) then
		return
	end
	if player:GetAttribute("Queued") ~= true then
		return
	end
	local now = os.clock()
	if now - (lastAccepted[player] or -math.huge) < Config.VOTE_RATE_LIMIT then
		return
	end
	lastAccepted[player] = now
	player:SetAttribute("Vote", id)
	Vote.recount()
end

function Vote.init()
	GameState.write("VoteOptions", "")
	GameState.write("VoteCounts", "{}")
	lastCountsJson = "{}"
	Net.event("Core_Vote").OnServerEvent:Connect(onVote)
	Join.onChanged(function(player: Player, queued: boolean)
		if not queued then
			clearVote(player)
		end
		Vote.recount()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAccepted[player] = nil
		task.delay(0.1, Vote.recount) -- once the player is gone
	end)
end

return Vote
