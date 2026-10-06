-- Party Dash Core: the phase machine.
-- Waiting -> Lobby -> Roulette -> (ModifierRoulette) -> Intro -> Countdown -> Round -> End -> Lobby ...
-- Writes ReplicatedStorage.GameState exactly as docs/ARCHITECTURE.md describes.
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
local Debug = require(script.Parent.Debug)
local Places = require(script.Parent.Places)
local Registry = require(script.Parent.Registry)
local Results = require(script.Parent.Results)
local State = require(script.Parent.State)
local Teleport = require(script.Parent.Teleport)

local Phase = GameState.Phase

local RoundLoop = {}

local lastMinigame: string? = nil
local lastModifier: string? = nil
local warned: { [string]: boolean } = {}

local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn("[Core] " .. message)
	end
end

-- Phases ------------------------------------------------------------------------------------------

local function setPhase(phase: string, duration: number?)
	GameState.write("PhaseEnd", if duration and duration > 0 then workspace:GetServerTimeNow() + duration else 0)
	GameState.write("Phase", phase)
end

-- Runs a timed phase. `fastable` phases shrink to ~2s with Debug_FastIntermission (even mid-phase).
-- Returns false if `abort` said so.
local function runPhase(phase: string, seconds: number, fastable: boolean, abort: (() -> boolean)?): boolean
	local duration = if fastable then Debug.phaseTime(seconds) else seconds
	setPhase(phase, duration)
	local finish = os.clock() + duration
	while os.clock() < finish do
		task.wait(0.1)
		if fastable and Debug.fast() and finish - os.clock() > Debug.FAST_PHASE_SECONDS then
			finish = os.clock() + Debug.FAST_PHASE_SECONDS
			GameState.write("PhaseEnd", workspace:GetServerTimeNow() + Debug.FAST_PHASE_SECONDS)
		end
		if abort and abort() then
			return false
		end
	end
	return true
end

-- Players -----------------------------------------------------------------------------------------

-- Players who could join the next round: alive character, not in a Solo run.
local function eligible(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InSolo") ~= true and Teleport.parts(p) then
			table.insert(list, p)
		end
	end
	return list
end

-- Up to MAX_PLAYERS, longest-waiting first (ties random).
local function pickParticipants(): { Player }
	local list = eligible()
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
	local chosen = {}
	for i = 1, math.min(Config.MAX_PLAYERS, #list) do
		chosen[i] = list[i]
	end
	return chosen
end

-- Roulette ----------------------------------------------------------------------------------------

local function pickMinigame(): string?
	local forced = Debug.forceMinigame()
	if forced then
		if Registry.minigames[forced] then
			return forced
		end
		warnOnce(("Debug_ForceMinigame %q is not a loaded minigame; ignoring it"):format(forced))
	end
	local pool = Registry.visibleMinigames()
	if #pool == 0 then
		pool = table.clone(Registry.minigameOrder) -- only hidden test minigames exist (early development)
	end
	if #pool == 0 then
		return nil
	end
	if #pool > 1 and lastMinigame then
		local index = table.find(pool, lastMinigame)
		if index then
			table.remove(pool, index)
		end
	end
	return pool[math.random(1, #pool)]
end

-- A reel of `minLen..maxLen` ids from `candidates`, no immediate repeats, ending on `chosen`.
local function makeReel(chosen: string, candidates: { string }, minLen: number, maxLen: number): string
	if #candidates == 0 then
		candidates = { chosen }
	end
	local length = math.random(minLen, maxLen)
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

local function returnToLobby()
	local ctx = State.ctx
	State.ctx = nil
	State.arenaActive = false
	if ctx then
		ctx:_cleanup() -- destroys the arena map (same spot as the lobby) before the lobby comes back
	end
	Places.buildLobby()
	for _, p in Places.audience() do
		p:SetAttribute("InRound", false)
		p:SetAttribute("Spectating", false)
		Places.sendToLobby(p)
	end
	GameState.write("Alive", 0)
	GameState.write("ModifierId", "")
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

local function playRound()
	State.roundNumber += 1
	local roundNumber = State.roundNumber

	-- Roulette: everything the client animates toward is written at the START of the phase.
	local minigameId = pickMinigame()
	if not minigameId then
		warnOnce("no minigames loaded; staying in the lobby")
		runPhase(Phase.Lobby, Config.LOBBY_TIME, true)
		return
	end
	local def = Registry.minigames[minigameId]
	local reelPool = Registry.visibleMinigames()
	if #reelPool == 0 then
		reelPool = Registry.minigameOrder
	end
	GameState.write("RoundNumber", roundNumber)
	GameState.write("ModifierId", "")
	GameState.write("ModifierReel", "")
	GameState.write("MinigameId", minigameId)
	GameState.write("MinigameKind", def.kind)
	GameState.write("RouletteReel", makeReel(minigameId, reelPool, 15, 25))
	runPhase(Phase.Roulette, Config.ROULETTE_TIME, true)
	lastMinigame = minigameId

	-- Optional modifier roulette.
	local modifierId = pickModifier(roundNumber)
	local modifier = modifierId and Registry.modifiers[modifierId]
	if modifierId then
		GameState.write("ModifierId", modifierId)
		GameState.write("ModifierReel", makeReel(modifierId, Registry.modifierOrder, 10, 16))
		runPhase(Phase.ModifierRoulette, Config.MODIFIER_ROULETTE_TIME, true)
		lastModifier = modifierId
	end

	-- Intro: build the map, swap out the lobby, place and freeze participants.
	local participants = pickParticipants()
	if #participants == 0 then
		GameState.write("ModifierId", "")
		return
	end
	local ctx
	ctx = Context.new({
		definition = def,
		center = CFrame.new(Config.ARENA_CENTER),
		players = participants,
		isSolo = false,
		modifierId = modifierId,
		intensityMultiplier = if modifier and type(modifier.intensityMultiplier) == "number"
			then modifier.intensityMultiplier
			else 1,
		parent = workspace,
		audience = Places.audience,
		onScores = writeScores,
		onEliminated = function(p: Player, info)
			GameState.write("Alive", ctx:_aliveCount())
			p:SetAttribute("InRound", false)
			Signals.PlayerEliminated:Fire(p, {
				minigameId = minigameId,
				placement = info.placement,
				survivedSeconds = info.survivedSeconds,
			})
			local audience = Places.audience()
			if info.reason == "left" or p.Parent ~= Players then
				Announce.feed(audience, ("%s left the round"):format(p.DisplayName))
				return
			end
			p:SetAttribute("Spectating", true)
			Places.sendToStands(p)
			local total = #ctx.allPlayers()
			local lasted = ("%.1fs"):format(info.survivedSeconds)
			local sub = if total >= 2
				then ("You placed #%d of %d  -  lasted %s"):format(info.placement, total, lasted)
				else ("You lasted %s"):format(lasted)
			Announce.big(p, "YOU'RE OUT!", sub, Theme.Colors.Red)
			Announce.feed(audience, ("%s got knocked out! #%d"):format(p.DisplayName, info.placement))
		end,
	})
	local built, err = pcall(ctx._build, ctx)
	if not built then
		warn(("[Core] %s failed to build: %s"):format(minigameId, tostring(err)))
		ctx:_cleanup()
		if minigameId ~= Debug.forceMinigame() then
			Registry.disableMinigame(minigameId)
		end
		Announce.feed(Places.audience(), "Oops! That minigame broke. Rerolling...")
		GameState.write("ModifierId", "")
		return
	end

	State.ctx = ctx
	State.arenaActive = true
	Places.destroyLobby()
	ctx:_place(true)
	local isParticipant = {}
	for _, p in participants do
		isParticipant[p] = true
		State.lastPlayed[p] = roundNumber
		p:SetAttribute("InRound", true)
		p:SetAttribute("Spectating", false)
	end
	for _, p in Places.audience() do
		if not isParticipant[p] then
			p:SetAttribute("InRound", false)
			p:SetAttribute("Spectating", true)
			Places.sendToStands(p)
		end
	end
	GameState.write("Participants", #participants)
	GameState.write("Alive", ctx:_aliveCount())
	GameState.write("ScoresJson", "{}")
	GameState.write("WinnersCsv", "")
	GameState.write("ResultText", "")
	if modifier then
		local ok, applyErr = pcall(modifier.apply, ctx)
		if not ok then
			warn(("[Core] modifier %s apply failed: %s"):format(modifierId, tostring(applyErr)))
		end
	end
	runPhase(Phase.Intro, Config.INTRO_TIME, true)

	-- Countdown 3, 2, 1, GO!
	setPhase(Phase.Countdown, Config.COUNTDOWN_TIME)
	for n = Config.COUNTDOWN_TIME, 1, -1 do
		Announce.big(Places.audience(), tostring(n), nil, countdownColor(n))
		task.wait(1)
	end

	-- Round.
	ctx:_start()
	setPhase(Phase.Round, if def.kind == "score" then def.duration else 0)
	Announce.big(Places.audience(), "GO!", def.rules, Theme.Colors.Green)
	Signals.RoundStarted:Fire({
		roundNumber = roundNumber,
		minigameId = minigameId,
		modifierId = modifierId,
		participants = ctx.allPlayers(),
	})
	while not ctx:_isOver() do
		task.wait(0.1)
	end

	-- End: stop hazards, show results on the map, then back to the lobby.
	ctx:_stop()
	if modifier then
		local ok, clearErr = pcall(modifier.clear, ctx)
		if not ok then
			warn(("[Core] modifier %s clear failed: %s"):format(modifierId, tostring(clearErr)))
		end
	end
	GameState.write("Alive", ctx:_aliveCount())
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
end

function RoundLoop.run()
	initGameState()
	while true do
		-- Waiting for at least one player with a character.
		if #eligible() < Config.MIN_LOBBY_PLAYERS then
			setPhase(Phase.Waiting, 0)
			repeat
				task.wait(0.5)
			until #eligible() >= Config.MIN_LOBBY_PLAYERS
		end

		-- Lobby intermission (back to Waiting if everyone leaves).
		local stillHere = runPhase(Phase.Lobby, Config.LOBBY_TIME, true, function()
			return #eligible() < Config.MIN_LOBBY_PLAYERS
		end)
		if stillHere then
			local ok, err = xpcall(playRound, debug.traceback)
			if not ok then
				warn("[Core] round crashed, returning to the lobby:\n" .. tostring(err))
				for _, p in Players:GetPlayers() do
					Teleport.setAnchored(p, false)
				end
			end
			if State.arenaActive or State.ctx or not Places.hasLobby() then
				returnToLobby()
			end
		end
	end
end

return RoundLoop
