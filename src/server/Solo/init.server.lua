--!strict
--[[
Party Dash: Solo Record (P10), server boot.

Survive as long as you can on a private copy of a minigame and beat your record.
	Runs.lua     private sessions (slots, countdown, ending, sending players back)
	Records.lua  personal bests + global TOP 10 (DataStores with an in-memory fallback)
	Board.lua    the TOP 10 SurfaceGui on the lobby's LeaderboardAnchor

Remotes (client -> server, validated + rate limited here):
	Solo_Start(minigameId: string)   -- a soloCapable id or "RANDOM"
	Solo_Quit()
Server -> client: Solo_State (see Runs.lua).
Player attributes: InSolo (true during a run), SoloBest_<id> (seconds), SoloLastSeconds.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Backdrop = require(script.Backdrop)
local Board = require(script.Board)
local Records = require(script.Records)
local Runs = require(script.Runs)

local Registry = require(script.Parent:WaitForChild("Core"):WaitForChild("Registry"))

local START_COOLDOWN = 1.5 -- seconds between Solo_Start requests per player
local QUIT_COOLDOWN = 0.5
local TOP_REFRESH_SECONDS = 60
local MAX_ID_LENGTH = 64

local startRemote = Net.event("Solo_Start")
local quitRemote = Net.event("Solo_Quit")
Net.event("Solo_State")

-- Rate limiting -----------------------------------------------------------------------------------------

local lastCall: { [Player]: { [string]: number } } = {}

local function allow(player: Player, what: string, cooldown: number): boolean
	local now = os.clock()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local last = calls[what]
	if last and now - last < cooldown then
		return false
	end
	calls[what] = now
	return true
end

-- Remotes -------------------------------------------------------------------------------------------

startRemote.OnServerEvent:Connect(function(player: Player, minigameId: any)
	if not allow(player, "start", START_COOLDOWN) then
		return
	end
	if type(minigameId) ~= "string" or #minigameId == 0 or #minigameId > MAX_ID_LENGTH then
		return
	end
	local ok, err = pcall(Runs.start, player, minigameId)
	if not ok then
		warn(("[Solo] start failed for %s: %s"):format(player.Name, tostring(err)))
	end
end)

quitRemote.OnServerEvent:Connect(function(player: Player)
	if not allow(player, "quit", QUIT_COOLDOWN) then
		return
	end
	Runs.quit(player)
end)

-- Players -------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player:SetAttribute("InSolo", false)
	Records.load(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerRemoving:Connect(function(player: Player)
	lastCall[player] = nil
	Runs.onPlayerRemoving(player)
end)

task.spawn(Backdrop.prewarm)

-- Global TOP 10 ---------------------------------------------------------------------------------------

local function displayName(id: string): string
	local def = Registry.minigames[id]
	return if def then def.displayName else string.upper(id)
end

Board.start(Runs.soloIds, Records.getTop, displayName)
Records.onTopChanged(function()
	Board.refresh()
end)

task.spawn(function()
	-- Core fills the Registry during boot; wait for it (bounded) before the first fetch.
	local deadline = os.clock() + 30
	while #Runs.soloIds() == 0 and os.clock() < deadline do
		task.wait(0.5)
	end
	while true do
		local ids = Runs.soloIds()
		for _, id in ids do
			Records.refreshTop(id)
			task.wait(1) -- spread the GetSortedAsync calls out
		end
		Board.refresh()
		task.wait(math.max(5, TOP_REFRESH_SECONDS - #ids))
	end
end)
