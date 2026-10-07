--[[
Party Dash Core: the phase machine (docs/ARCHITECTURE.md "Round flow").

	Waiting   nobody in the main game (everyone left or is in a Solo run)
	Lobby     Config.LOBBY_TIME s on the permanent lobby; PLAY square = queued, queued players vote. Timer over with
	          nobody queued: LobbyHold = true, PhaseEnd = 0 until someone steps in, then LOBBY_HOLD_RESTART s.
	Roulette  vote result -> MinigameId; RouletteReel cycles the vote options and lands on it
	(ModifierRoulette every Config.MODIFIER_EVERY-th round)
	Intro     map built at ARENA_CENTER, participants (queued at lobby end) placed and frozen
	Countdown 3-2-1, Round (survival until last one standing; sudden death later), End (results on the map)
	then survivors go back to the lobby spawns and everyone's round flags are cleared.
Every phase writes GameState Phase, PhaseStart and PhaseEnd.
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Theme = require(Shared.Theme)

local Server = script.Parent.Parent
local Announce = require(Server.Announce)
local Signals = require(Server.Signals)

local Context = require(script.Parent.Context)
local Death = require(script.Parent.Death)
local Debug = require(script.Parent.Debug)
local Join = require(script.Parent.Join)
local Places = require(script.Parent.Places)
local Registry = require(script.Parent.Registry)
local Results = require(script.Parent.Results)
local State = require(script.Parent.State)
local Teleport = require(script.Parent.Teleport)
local Vote = require(script.Parent.Vote)

local Phase = GameState.Phase

local RoundLoop = {}

RoundLoop.TICK = 0.1
RoundLoop.REEL_LENGTH = { 15, 20 }
RoundLoop.MODIFIER_REEL_LENGTH = { 10, 16 }

local lastMinigame: string? = nil
local lastModifier: string? = nil
local activeModifier: { def: any, ctx: any }? = nil -- applied and not cleared yet
local warned: { [string]: boolean } = {}

local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn("[Core] " .. message)
	end
end

-- Phases ------------------------------------------------------------------------------------------

local function setPhase(phase: string, duration: number?)
	local now = workspace:GetServerTimeNow()
	GameState.write("PhaseStart", now)
	GameState.write("PhaseEnd", if duration and duration > 0 then now + duration else 0)
	GameState.write("Phase", phase)
end

-- Runs a timed phase. `fastable` phases shrink to ~2 s with Debug_FastIntermission (even mid-phase).
local function runPhase(phase: string, seconds: number, fastable: boolean)
	local duration = if fastable then Debug.phaseTime(seconds) else seconds
	setPhase(phase, duration)
	local finish = os.clock() + duration
	while os.clock() < finish do
		task.wait(RoundLoop.TICK)
		if fastable and Debug.fast() and finish - os.clock() > Debug.FAST_PHASE_SECONDS then
			finish = os.clock() + Debug.FAST_PHASE_SECONDS
			GameState.write("PhaseEnd", workspace:GetServerTimeNow() + Debug.FAST_PHASE_SECONDS)
		end
	end
end

-- Lobby -------------------------------------------------------------------------------------------

-- The Lobby phase. Returns true when the round should start, false when the server emptied.
local function runLobby(): boolean
	Vote.open(Vote.pickOptions(lastMinigame, math.max(Join.count(), #Places.audience())))
	GameState.write("LobbyHold", false)
	local duration = Debug.phaseTime(Config.LOBBY_TIME)
	setPhase(Phase.Lobby, duration)
	local deadline = os.clock() + duration
	local holding = false
	local restarted = false
	while true do
		task.wait(RoundLoop.TICK)
		if #Places.audience() == 0 then
			GameState.write("LobbyHold", false)
			return false
		end
		local queued = Join.count()
		if holding then
			if queued > 0 then
				-- Someone stepped in: a short fresh countdown (never shortened, so it is readable).
				holding = false
				restarted = true
				deadline = os.clock() + Config.LOBBY_HOLD_RESTART
				local now = workspace:GetServerTimeNow()
				GameState.write("LobbyHold", false)
				GameState.write("PhaseStart", now)
				GameState.write("PhaseEnd", now + Config.LOBBY_HOLD_RESTART)
			end
		else
			if not restarted and Debug.fast() and deadline - os.clock() > Debug.FAST_PHASE_SECONDS then
				deadline = os.clock() + Debug.FAST_PHASE_SECONDS
				GameState.write("PhaseEnd", workspace:GetServerTimeNow() + Debug.FAST_PHASE_SECONDS)
			end
			if os.clock() >= deadline then
				if queued > 0 then
					return true
				end
				holding = true
				GameState.write("LobbyHold", true)
				GameState.write("PhaseEnd", 0)
			end
		end
	end
end

-- Players queued at lobby end: up to MAX_PLAYERS, longest-waiting first (ties random). Returns (chosen, overflow).
local function pickParticipants(): ({ Player }, { Player })
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Queued") == true and p:GetAttribute("InSolo") ~= true and Teleport.parts(p) then
			table.insert(list, p)
		end
	end
	local tiebreak = {}
	for _, p in list do
		tiebreak[p] = math.random()
	end
	table.sort(list, function(a, b)
		local la, lb = State.lastPlayed[a] or 0, State.lastPlayed[b] or 0
		if la ~= lb then
			return la < lb
		end
		return tiebreak[a] < tiebreak[b]
	end)
	local chosen, overflow = {}, {}
	for i, p in list do
		table.insert(if i <= Config.MAX_PLAYERS then chosen else overflow, p)
	end
	return chosen, overflow
end

-- Roulette ----------------------------------------------------------------------------------------

-- A reel of ids from `candidates` with no immediate repeats, ending on `chosen`.
local function makeReel(chosen: string, candidates: { string }, lengths: { number }): string
	if #candidates == 0 then
		candidates = { chosen }
	end
	local length = math.random(lengths[1], lengths[2])
	local reel = table.create(length)
	reel[length] = chosen
	-- Fill backwards so every slot differs from the one after it (and the reel ends on `chosen`).
	for i = length - 1, 1, -1 do
		local pick = candidates[math.random(1, #candidates)]
		if #candidates > 1 then
			while pick == reel[i + 1] do
				pick = candidates[math.random(1, #candidates)]
			end
		end
		reel[i] = pick
	end
	return table.concat(reel, ",")
end

local function pickModifier(roundNumber: number): string?
	local forced = Debug.forceModifier()
	if forced then
		if Registry.modifiers[forced] then
			return forced
		end
		warnOnce(("Debug_ForceModifier %q is not a loaded modifier; using the normal rule"):format(forced))
	end
	if roundNumber % Config.MODIFIER_EVERY ~= 0 or #Registry.modifierOrder == 0 then
		return nil
	end
	local pool = table.clone(Registry.modifierOrder)
	if #pool > 1 and lastModifier then
		local index = table.find(pool, lastModifier)
		if index then
			table.remove(pool, index)
		end
	end
	return pool[math.random(1, #pool)]
end

-- Round helpers -----------------------------------------------------------------------------------

local function clearModifier()
	local active = activeModifier
	activeModifier = nil
	if active then
		local ok, err = pcall(active.def.clear, active.ctx)
		if not ok then
			warn(("[Core] modifier %s clear failed: %s"):format(tostring(active.def.id), tostring(err)))
		end
	end
end

-- Back to the lobby: survivors are moved home, everyone's round flags are cleared, the arena is destroyed.
local function returnToLobby()
	local ctx = State.ctx
	clearModifier() -- before ctx:_cleanup(), which disconnects the modifier's listeners
	State.ctx = nil
	State.arenaActive = false
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InSolo") ~= true then
			local wasPlaying = p:GetAttribute("InRound") == true or (ctx ~= nil and ctx.isAlive(p))
			p:SetAttribute("InRound", false)
			p:SetAttribute("Eliminated", false)
			p:SetAttribute("Spectating", false)
			p:SetAttribute("ReviveUntil", 0)
			p.ReplicationFocus = nil
			if wasPlaying then
				Places.sendToLobby(p)
			end
		end
	end
	if ctx then
		ctx:_cleanup()
	end
	Places.ensureLobby()
	GameState.write("Alive", 0)
	GameState.write("ModifierId", "")
	GameState.write("SuddenDeath", false)
end

local function countdownColor(n: number): Color3
	if n >= 3 then
		return Theme.Colors.Red
	elseif n == 2 then
		return Theme.Colors.Orange
	end
	return Theme.Colors.Yellow
end

local function writeScores(scores: { [Player]: number })
	local out = {}
	for p, score in scores do
		out[tostring(p.UserId)] = score
	end
	GameState.write("ScoresJson", HttpService:JSONEncode(out))
end

local function playRound(participants: { Player }, overflow: { Player })
	-- Roulette: everything the client animates toward is written at the START of the phase.
	local minigameId, candidates = Vote.resolve(participants)
	if not minigameId then
		warnOnce("no minigames loaded; staying in the lobby")
		return
	end
	local def = Registry.minigames[minigameId]
	State.roundNumber += 1
	local roundNumber = State.roundNumber
	local round = { minigameId = minigameId, roundNumber = roundNumber }
	GameState.write("RoundNumber", roundNumber)
	GameState.write("ModifierId", "")
	GameState.write("ModifierReel", "")
	GameState.write("MinigameId", minigameId)
	GameState.write("MinigameKind", def.kind)
	GameState.write("RouletteReel", makeReel(minigameId, candidates, RoundLoop.REEL_LENGTH))
	GameState.write("Participants", #participants)
	GameState.write("SuddenDeath", false)
	for _, p in overflow do
		Announce.toast(p, "Round full! You're first next time", Theme.Colors.Orange)
	end
	runPhase(Phase.Roulette, Config.ROULETTE_TIME, true)
	lastMinigame = minigameId

	-- Optional modifier roulette.
	local modifierId = pickModifier(roundNumber)
	local modifier = modifierId and Registry.modifiers[modifierId]
	if modifierId then
		GameState.write("ModifierId", modifierId)
		GameState.write("ModifierReel", makeReel(modifierId, Registry.modifierOrder, RoundLoop.MODIFIER_REEL_LENGTH))
		runPhase(Phase.ModifierRoulette, Config.MODIFIER_ROULETTE_TIME, true)
		lastModifier = modifierId
	end

	-- Intro: build the map, place and freeze the participants still here.
	local playing = {}
	for _, p in participants do
		if p.Parent == Players and p:GetAttribute("InSolo") ~= true then
			table.insert(playing, p)
		end
	end
	if #playing == 0 then
		GameState.write("ModifierId", "")
		return
	end
	local ctx
	ctx = Context.new({
		definition = def,
		center = CFrame.new(Config.ARENA_CENTER),
		players = playing,
		isSolo = false,
		modifierId = modifierId,
		intensityMultiplier = if modifier and type(modifier.intensityMultiplier) == "number"
			then modifier.intensityMultiplier
			else 1,
		parent = workspace,
		audience = Places.roundAudience,
		onScores = writeScores,
		onEliminated = function(p: Player, info)
			Death.onEliminated(ctx, p, info, round)
		end,
		onRevived = function(p: Player)
			Death.onRevived(ctx, p, round)
		end,
		onSuddenDeath = function()
			GameState.write("SuddenDeath", true)
			Announce.big(Places.roundAudience(), "SUDDEN DEATH!", nil, Theme.Colors.Red)
		end,
	})
	local built, err = pcall(ctx._build, ctx)
	if not built then
		warn(("[Core] %s failed to build: %s"):format(minigameId, tostring(err)))
		ctx:_cleanup()
		if minigameId ~= Debug.forceMinigame() then
			Registry.reportBuild(minigameId, false)
		end
		Announce.feed(Places.audience(), "Oops! That game broke. Pick again!")
		GameState.write("ModifierId", "")
		return
	end
	Registry.reportBuild(minigameId, true)

	State.ctx = ctx
	State.arenaActive = true
	for _, p in Places.audience() do
		p:SetAttribute("KOs", 0)
	end
	for _, p in playing do
		State.lastPlayed[p] = roundNumber
		p:SetAttribute("InRound", true)
		p:SetAttribute("Eliminated", false)
		p:SetAttribute("Spectating", false)
		p:SetAttribute("ReviveUntil", 0)
		p:SetAttribute("LastHitBy", 0)
		p:SetAttribute("LastHitAt", 0)
	end
	ctx:_place(true)
	for _, p in Places.audience() do
		if p:GetAttribute("Spectating") == true then
			Places.setWatchFocus(p, true) -- lobby players who chose WATCH before the round started
		end
	end
	GameState.write("Participants", #playing)
	GameState.write("Alive", ctx:_aliveCount())
	GameState.write("ScoresJson", "{}")
	GameState.write("WinnersCsv", "")
	GameState.write("ResultText", "")
	if modifier then
		activeModifier = { def = modifier, ctx = ctx }
		local ok, applyErr = pcall(modifier.apply, ctx)
		if not ok then
			warn(("[Core] modifier %s apply failed: %s"):format(modifierId, tostring(applyErr)))
		end
	end
	runPhase(Phase.Intro, Config.INTRO_TIME, true)

	-- Countdown 3, 2, 1 (skipped if every participant left).
	setPhase(Phase.Countdown, Config.COUNTDOWN_TIME)
	for n = Config.COUNTDOWN_TIME, 1, -1 do
		if ctx:_aliveCount() == 0 then
			return
		end
		Announce.big(Places.roundAudience(), tostring(n), nil, countdownColor(n))
		task.wait(1)
	end

	-- Round.
	ctx:_start()
	setPhase(Phase.Round, if def.kind == "score" then def.duration else 0)
	Announce.big(Places.roundAudience(), "GO!", nil, Theme.Colors.Green)
	Signals.RoundStarted:Fire({
		roundNumber = roundNumber,
		minigameId = minigameId,
		modifierId = modifierId,
		participants = ctx.allPlayers(),
	})
	while not ctx:_isOver() do
		task.wait(RoundLoop.TICK)
	end

	-- End: stop hazards, show results on the map, then back to the lobby.
	ctx:_stop()
	clearModifier()
	GameState.write("Alive", ctx:_aliveCount())
	for _, p in ctx.allPlayers() do
		if p.Parent == Players then
			p:SetAttribute("ReviveUntil", 0)
		end
	end
	Results.apply(ctx, {
		roundNumber = roundNumber,
		minigameId = minigameId,
		modifierId = modifierId,
		displayName = def.displayName,
	})
	runPhase(Phase.End, Config.END_TIME, true)
end

local function initGameState()
	GameState.write("Phase", Phase.Waiting)
	GameState.write("PhaseStart", workspace:GetServerTimeNow())
	GameState.write("PhaseEnd", 0)
	GameState.write("RoundNumber", 0)
	GameState.write("MinigameId", "")
	GameState.write("RouletteReel", "")
	GameState.write("ModifierId", "")
	GameState.write("ModifierReel", "")
	GameState.write("MinigameKind", "")
	GameState.write("Alive", 0)
	GameState.write("Participants", 0)
	GameState.write("ScoresJson", "{}")
	GameState.write("WinnersCsv", "")
	GameState.write("ResultText", "")
	GameState.write("LobbyHold", false)
	GameState.write("SuddenDeath", false)
end

function RoundLoop.run()
	initGameState()
	while true do
		if #Places.audience() == 0 then
			Vote.reset()
			setPhase(Phase.Waiting, 0)
			repeat
				task.wait(0.5)
			until #Places.audience() > 0
		end

		local start = runLobby()
		Vote.close()
		if start then
			local participants, overflow = pickParticipants()
			if #participants > 0 then
				local ok, err = xpcall(playRound, debug.traceback, participants, overflow)
				if not ok then
					warn("[Core] round crashed, returning to the lobby:\n" .. tostring(err))
					for _, p in Players:GetPlayers() do
						if p:GetAttribute("InSolo") ~= true then
							Teleport.setAnchored(p, false)
						end
					end
				end
				returnToLobby()
			end
		end
	end
end

return RoundLoop
