--!strict
--[[
Solo Record runs: one private copy of a minigame per player, far away from the main arena.

	Runs.start(player, minigameId) -> (ok, reason?)   -- "RANDOM" picks any solo-capable minigame
	Runs.quit(player)                                  -- ends the player's run (time counts if it started)
	Runs.isActive(player) -> boolean
	Runs.soloIds() -> { string }                       -- visible solo-capable minigame ids (sorted)

Lifecycle of a run
	slot k allocated -> Context.new(isSolo = true) -> map built at SOLO_ORIGIN + k * SOLO_SPACING * Z
	-> Player.InSolo = true -> placed + frozen -> personal 3-2-1 -> ctx:_start() -> ... -> fall / death /
	leave / quit -> record submitted -> player sent back -> map destroyed -> slot freed.

Client messages on remote "Solo_State" (server -> owner):
	("intro",    { minigameId, displayName, best: number?, goAt: serverTime })
	("go",       { minigameId, startedAt: serverTime })
	("result",   { minigameId, displayName, seconds, best: number?, previous: number?, isRecord,
	               reason, rank: number?, started: boolean })
	("rejected", { reason: string })
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)

local Server = script.Parent.Parent
local Core = Server:WaitForChild("Core")
local Announce = require(Server.Announce)
local Signals = require(Server.Signals)
local Context = require(Core:WaitForChild("Context"))
local Places = require(Core:WaitForChild("Places"))
local Registry = require(Core:WaitForChild("Registry"))
local State = require(Core:WaitForChild("State"))
local Teleport = require(Core:WaitForChild("Teleport"))

local Backdrop = require(script.Parent.Backdrop)
local Records = require(script.Parent.Records)

local Runs = {}

Runs.MAX_SLOTS = Config.MAX_PLAYERS
Runs.COUNTDOWN = Config.COUNTDOWN_TIME

local Phase = GameState.Phase
-- Phases where the lobby island is up; any other phase sends a returning player to the spectator stands.
local LOBBY_PHASES = {
	[Phase.Waiting] = true,
	[Phase.Lobby] = true,
	[Phase.Roulette] = true,
	[Phase.ModifierRoulette] = true,
}
local COUNT_COLORS = { Theme.Colors.Yellow, Theme.Colors.Orange, Theme.Colors.Red }

type Run = {
	player: Player,
	minigameId: string,
	displayName: string,
	slot: number,
	ctx: any,
	started: boolean,
	finished: boolean,
	startedAt: number, -- workspace:GetServerTimeNow() at GO
}

local runs: { [Player]: Run } = {}
local slots: { [number]: Run } = {}
local lastPick: { [Player]: string } = {}

local stateRemote = Net.event("Solo_State")

-- Helpers -------------------------------------------------------------------------------------------

local function send(player: Player, kind: string, payload: { [string]: any })
	if player.Parent == Players then
		stateRemote:FireClient(player, kind, payload)
	end
end

local function reject(player: Player, reason: string): (boolean, string)
	Announce.toast(player, reason, Theme.Colors.Red)
	send(player, "rejected", { reason = reason })
	return false, reason
end

local function isSoloId(id: string): boolean
	local def = Registry.minigames[id]
	return def ~= nil and def.soloCapable == true and not Registry.isHidden(id)
end

function Runs.soloIds(): { string }
	local list = {}
	for _, id in Registry.minigameOrder do
		if isSoloId(id) then
			table.insert(list, id)
		end
	end
	return list
end

local function freeSlot(): number?
	for k = 0, Runs.MAX_SLOTS - 1 do
		if not slots[k] then
			return k
		end
	end
	return nil
end

local function slotCenter(k: number): CFrame
	return CFrame.new(Config.SOLO_ORIGIN + Vector3.new(0, 0, k * Config.SOLO_SPACING))
end

-- Back to the lobby island between rounds, otherwise onto the spectator stands.
local function sendBack(player: Player)
	if player.Parent ~= Players then
		return
	end
	Teleport.setAnchored(player, false)
	local phase = GameState.read("Phase")
	if LOBBY_PHASES[phase] and Places.hasLobby() and not State.arenaActive then
		player:SetAttribute("Spectating", false)
		Places.sendToLobby(player)
	else
		player:SetAttribute("Spectating", true)
		Places.sendToStands(player)
	end
	-- A dead character is placed by Core's CharacterAdded routing once InSolo is false.
end

local function seconds1(n: number): string
	return ("%.1fs"):format(n)
end

-- Ending ----------------------------------------------------------------------------------------------

local function finish(run: Run, reason: string, survived: number?)
	if run.finished then
		return
	end
	run.finished = true
	local player = run.player
	local ctx = run.ctx
	local seconds = 0
	if run.started then
		seconds = math.max(0, survived or ctx.elapsed())
	end
	ctx:_stop() -- hazards off right away

	-- Records first (memory is instant; DataStore writes run in the background).
	local isRecord, previous = false, Records.getBest(player, run.minigameId)
	if run.started and seconds > 0 then
		isRecord, previous = Records.submit(player, run.minigameId, seconds)
	end
	local best = Records.getBest(player, run.minigameId)
	local rank = if isRecord then Records.rankOf(run.minigameId, player.UserId) else nil

	-- Player out of the solo world before the map disappears under them.
	if player.Parent == Players then
		sendBack(player)
		player:SetAttribute("InSolo", false)
		player:SetAttribute("SoloLastSeconds", math.floor(seconds * 100 + 0.5) / 100)
	end
	ctx:_cleanup()
	if slots[run.slot] == run then
		slots[run.slot] = nil
	end
	if runs[player] == run then
		runs[player] = nil
	end

	if run.started then
		Signals.SoloFinished:Fire(player, {
			minigameId = run.minigameId,
			seconds = seconds,
			isRecord = isRecord,
		})
	end
	send(player, "result", {
		minigameId = run.minigameId,
		displayName = run.displayName,
		seconds = seconds,
		best = best,
		previous = previous,
		isRecord = isRecord,
		reason = reason,
		rank = rank,
		started = run.started,
	})
	if run.started and isRecord and rank and player.Parent == Players then
		local others = {}
		for _, p in Places.audience() do
			if p ~= player then
				table.insert(others, p)
			end
		end
		if #others > 0 then
			Announce.feed(
				others,
				("%s set a SOLO record in %s: %s (#%d)"):format(
					player.DisplayName,
					run.displayName,
					seconds1(seconds),
					rank
				)
			)
		end
	end
end

-- Starting --------------------------------------------------------------------------------------------

local function countdownAndGo(run: Run)
	local player = run.player
	for n = Runs.COUNTDOWN, 1, -1 do
		if run.finished then
			return
		end
		Announce.big(player, tostring(n), nil, COUNT_COLORS[math.clamp(n, 1, #COUNT_COLORS)])
		task.wait(1)
	end
	if run.finished then
		return
	end
	run.ctx:_start()
	run.started = true
	run.startedAt = workspace:GetServerTimeNow()
	Announce.big(player, "GO!", run.ctx.definition.rules, Theme.Colors.Green)
	send(player, "go", { minigameId = run.minigameId, startedAt = run.startedAt })
end

function Runs.isActive(player: Player): boolean
	return runs[player] ~= nil
end

function Runs.start(player: Player, requested: string): (boolean, string?)
	if runs[player] or player:GetAttribute("InSolo") == true then
		return reject(player, "You're already in a Solo run!")
	end
	if player:GetAttribute("InRound") == true or State.mainCtxOwns(player) then
		return reject(player, "Finish the round first!")
	end
	if not Teleport.parts(player) then
		return reject(player, "Wait until you respawn!")
	end

	local minigameId = requested
	if minigameId == "RANDOM" then
		local pool = Runs.soloIds()
		local last = lastPick[player]
		if #pool > 1 and last then
			local index = table.find(pool, last)
			if index then
				table.remove(pool, index)
			end
		end
		if #pool == 0 then
			return reject(player, "No Solo games are available right now.")
		end
		minigameId = pool[math.random(1, #pool)]
	end
	if not isSoloId(minigameId) then
		return reject(player, "That game can't be played solo.")
	end
	local slot = freeSlot()
	if not slot then
		return reject(player, "All Solo arenas are busy. Try again in a moment!")
	end
	local def = Registry.minigames[minigameId]

	-- Claim everything synchronously so a second request can never race this one.
	local run: Run = {
		player = player,
		minigameId = minigameId,
		displayName = def.displayName,
		slot = slot,
		ctx = nil,
		started = false,
		finished = false,
		startedAt = 0,
	}
	runs[player] = run
	slots[slot] = run
	lastPick[player] = minigameId
	player:SetAttribute("InSolo", true)
	player:SetAttribute("Spectating", false)

	local center = slotCenter(slot)
	Backdrop.ensure(slot, center.Position)

	local ctx
	ctx = Context.new({
		definition = def,
		center = center,
		players = { player },
		isSolo = true,
		parent = workspace,
		audience = function()
			return if player.Parent == Players then { player } else {}
		end,
		onEliminated = function(_p: Player, info)
			finish(run, info.reason, info.survivedSeconds)
		end,
		-- "safety" (Config.SAFETY_ROUND_LIMIT) is ignored on purpose: a solo run has no time limit.
		onFinish = function(reason: string)
			if reason ~= "safety" then
				finish(run, reason, nil)
			end
		end,
	})
	run.ctx = ctx

	local built, err = pcall(ctx._build, ctx)
	if not built then
		warn(("[Solo] %s failed to build for %s: %s"):format(minigameId, player.Name, tostring(err)))
		run.finished = true
		ctx:_cleanup()
		slots[slot] = nil
		runs[player] = nil
		player:SetAttribute("InSolo", false)
		return reject(player, "Oops! That arena broke. Try another game.")
	end
	local map = ctx.map :: Model
	map:SetAttribute("SoloOwner", player.UserId)
	map:SetAttribute("SoloSlot", slot)
	pcall(function()
		map.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	if workspace.StreamingEnabled then
		pcall(player.RequestStreamAroundAsync, player, ctx.center.Position, 5)
	end
	if run.finished then
		-- The player left while the map was building/streaming: finish() already cleaned up the context.
		map:Destroy()
		return false, "left"
	end

	ctx:_place(true)
	send(player, "intro", {
		minigameId = minigameId,
		displayName = def.displayName,
		best = Records.getBest(player, minigameId),
		goAt = workspace:GetServerTimeNow() + Runs.COUNTDOWN,
	})
	task.spawn(countdownAndGo, run)
	return true, nil
end

function Runs.quit(player: Player)
	local run = runs[player]
	if run then
		finish(run, "quit", nil)
	end
end

-- Safety net: a player who leaves during the countdown (the Context also handles it while running).
function Runs.onPlayerRemoving(player: Player)
	lastPick[player] = nil
	local run = runs[player]
	if run then
		finish(run, "left", nil)
	end
end

return Runs
