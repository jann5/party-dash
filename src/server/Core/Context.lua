--[[
Party Dash Core: Context, the `ctx` handed to minigames (see src/shared/Contracts/Minigame.lua).
One Context = one running copy of a minigame. Core builds one for the main arena; Solo Record (P10) builds
private ones at Config.SOLO_ORIGIN. A Context enforces elimination by itself (its own Heartbeat watcher),
so every copy behaves the same no matter who runs it.

API ----------------------------------------------------------------------------------------------------

	local Context = require(ServerScriptService.Server.Core.Context)
	local ctx = Context.new({
		definition = def,                -- REQUIRED validated minigame definition (Contracts/Minigame.validate)
		center = CFrame.new(pos),        -- REQUIRED origin of this copy (platform top-center)
		players = { Player },            -- REQUIRED participants; they become ctx.allPlayers()
		isSolo = false,                  -- optional, default false
		modifierId = "LowGravity",       -- optional active modifier id (nil or "" = none; never in Solo)
		intensityMultiplier = 1.5,       -- optional, the modifier's multiplier folded into ctx.intensity()
		parent = workspace,              -- optional, where session.map is parented (default workspace)
		audience = function() return {Player} end,  -- optional, who sees ctx.announce/ctx.feed
		                                 --   (default: ctx.allPlayers() still in the server)
		onEliminated = function(player, info) end,  -- optional; info = { reason: string,
		                                 --   placement: number, survivedSeconds: number }. Reasons: "fell",
		                                 --   "died", "left", or whatever a minigame passed to ctx.eliminate.
		onFinish = function(reason) end, -- optional; fired once when the end condition is reached:
		                                 --   "lastStanding" | "allOut" | "time" | "empty" | "finish" | "safety"
		onScores = function(scores) end, -- optional; { [Player]: number }, throttled to ~4x/s when changed
	})

	Methods for Core / Solo (underscore = not for minigames):
	local session = ctx:_build()       -- calls definition.create(ctx), validates the session, reads the map's
	                                   --   KillY attribute and Spawns, parents session.map. Errors propagate
	                                   --   (wrap it in pcall, then call ctx:_cleanup() on failure).
	ctx:_place(anchor: boolean)        -- puts every alive player on the map's Spawns round-robin; anchor = true
	                                   --   freezes their HumanoidRootParts (Intro/Countdown).
	ctx:_start()                       -- unfreezes, starts the clock + elimination watcher, calls session:start().
	ctx:_isOver(): (boolean, string?)  -- true once an end condition was reached (also see onFinish).
	ctx:_stop()                        -- idempotent; stops the watcher and calls session:stop(). After this,
	                                   --   knockback/eliminate/addScore are no-ops. The map stays (results).
	ctx:_results(): Results            -- see below; call after _stop().
	ctx:_cleanup()                     -- idempotent; _stop() if needed, destroys session.map, ctx.trove:clean().
	ctx:_aliveCount(): number
	ctx:_isParticipant(Player): boolean
	ctx:_wantsCharacter(Player): boolean  -- true if this context will (re)place this player's new character.

	Results = {
		kind: "survival" | "score",
		reason: string?,                    -- why it ended
		duration: number,                   -- seconds from _start() to _stop()
		participants: { Player },
		winners: { Player },                -- survival: alive at the end when >= 2 started (none when 1 started
		                                    --   and fell); score: top scorers with score > 0
		placements: { [Player]: number },   -- 1-based; last eliminated = 2nd, ...; score: by score (ties share)
		survived: { [Player]: number },     -- seconds alive
		scores: { [Player]: number }?,      -- score kind only
	}

Rules enforced here:
	- Falling below ctx.killY (map attribute "KillY", default center.Y - Config.KILL_DEPTH) or Humanoid death:
	  survival -> eliminated; score -> frozen, then put back on a spawn after 2 s (ctx.respawn).
	- Debug_NoEliminate (workspace attribute): survival falls/eliminations respawn the player on the map instead.
	- Debug_IntensityOverride: ctx.intensity() returns it.
	- End: survival with >= 2 participants -> alive <= 1; with 1 participant -> alive == 0;
	  score -> definition.duration elapsed (or nobody left); any kind -> ctx.finish(); Config.SAFETY_ROUND_LIMIT fuse.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Trove = require(Shared.Util.Trove)
local Knockback = require(Shared.Knockback)

local Server = script.Parent.Parent
local Announce = require(Server.Announce)
local Debug = require(script.Parent.Debug)
local Teleport = require(script.Parent.Teleport)

local Context = {}
Context.__index = Context

Context.SCORE_RESPAWN_DELAY = 2
Context.SCORE_PUSH_INTERVAL = 0.25

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function isFinite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

function Context.new(params: { [string]: any })
	assert(type(params) == "table", "Context.new: params table required")
	local definition = params.definition
	assert(type(definition) == "table" and type(definition.create) == "function", "Context.new: bad definition")
	assert(typeof(params.center) == "CFrame", "Context.new: center must be a CFrame")
	assert(type(params.players) == "table", "Context.new: players list required")

	local self = setmetatable({}, Context)
	local center: CFrame = params.center

	-- Public fields (Contracts/Minigame.lua) ------------------------------------------------------
	self.definition = definition
	self.center = center
	self.killY = center.Position.Y - Config.KILL_DEPTH
	self.isSolo = params.isSolo == true
	self.modifier = if type(params.modifierId) == "string" and params.modifierId ~= "" then params.modifierId else nil
	self.trove = Trove.new()
	self.map = nil :: Model?
	self.session = nil :: any

	-- Private state --------------------------------------------------------------------------------
	self._params = params
	self._kind = definition.kind
	self._multiplier = if type(params.intensityMultiplier) == "number" then params.intensityMultiplier else 1
	self._all = {} :: { Player }
	self._participant = {} :: { [Player]: boolean }
	self._alive = {} :: { [Player]: boolean }
	self._alivePlayers = 0
	self._scores = {} :: { [Player]: number }
	self._scoresDirty = false
	self._lastScorePush = 0
	self._placements = {} :: { [Player]: number }
	self._survived = {} :: { [Player]: number }
	self._respawning = {} :: { [Player]: boolean }
	self._spawns = {} :: { BasePart }
	self._frozen = true
	self._running = false
	self._stopped = false
	self._cleaned = false
	self._startClock = nil :: number?
	self._stopClock = nil :: number?
	self._over = false
	self._overReason = nil :: string?
	self._finishRequested = false
	self._conns = Trove.new() -- Context-owned connections (ctx.trove belongs to the minigame)

	for _, p in params.players do
		if isPlayer(p) and p.Parent == Players and not self._participant[p] then
			table.insert(self._all, p)
			self._participant[p] = true
			self._alive[p] = true
			self._alivePlayers += 1
			self._scores[p] = 0
		end
	end

	-- Public functions (called with a dot: ctx.players()) -----------------------------------------
	self.players = function(): { Player }
		local list = {}
		for _, p in self._all do
			if self._alive[p] then
				table.insert(list, p)
			end
		end
		return list
	end
	self.allPlayers = function(): { Player }
		return table.clone(self._all)
	end
	self.isAlive = function(p: Player): boolean
		return self._alive[p] == true
	end
	self.elapsed = function(): number
		return self:_elapsed()
	end
	self.intensity = function(): number
		local override = Debug.intensityOverride()
		if override then
			return override
		end
		return (1 + self:_elapsed() / Config.INTENSITY_RAMP_SECONDS) * self._multiplier
	end
	self.eliminate = function(p: Player, reason: string?)
		self:_eliminate(p, if type(reason) == "string" then reason else "eliminated")
	end
	self.addScore = function(p: Player, amount: number)
		if not self._running or not self._participant[p] then
			return
		end
		if type(amount) ~= "number" or not isFinite(amount) then
			return
		end
		self._scores[p] = (self._scores[p] or 0) + amount
		self._scoresDirty = true
	end
	self.getScore = function(p: Player): number
		return self._scores[p] or 0
	end
	self.knockback = function(p: Player, direction: Vector3, power: number, stun: number?)
		if not self._running or not self._alive[p] then
			return
		end
		Knockback.apply(p, direction, power, stun)
	end
	self.respawn = function(p: Player)
		self:_respawnNow(p)
	end
	self.finish = function()
		self._finishRequested = true
	end
	self.announce = function(text: string, sub: string?, color: Color3?)
		Announce.big(self:_audience(), text, sub, color)
	end
	self.feed = function(text: string)
		Announce.feed(self:_audience(), text)
	end

	-- Watch participants leaving / respawning -------------------------------------------------------
	self._conns:connect(Players.PlayerRemoving, function(p: Player)
		if self._participant[p] then
			self:_eliminate(p, "left")
		end
	end)
	for _, p in self._all do
		self._conns:connect(p.CharacterAdded, function(character: Model)
			self:_onCharacter(p, character)
		end)
	end

	return self
end

-- Internals -----------------------------------------------------------------------------------------

function Context:_elapsed(): number
	if not self._startClock then
		return 0
	end
	return (self._stopClock or os.clock()) - self._startClock
end

function Context:_audience(): { Player }
	local fn = self._params.audience
	if type(fn) == "function" then
		local ok, list = pcall(fn)
		if ok and type(list) == "table" then
			return list
		end
	end
	local list = {}
	for _, p in self._all do
		if p.Parent == Players then
			table.insert(list, p)
		end
	end
	return list
end

function Context:_spawnFloor(index: number, layer: number): CFrame
	local center = self.center.Position
	local n = #self._spawns
	if n > 0 then
		local part = self._spawns[(index - 1) % n + 1]
		if part.Parent then
			return Teleport.spawnFloor(part, layer, center)
		end
	end
	-- Fallback when the map has no usable spawns: a ring around the center.
	local angle = (index - 1) * (math.pi * 2 / 8) + layer * 0.4
	local pos = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (10 + layer * 3)
	return Teleport.facing(pos, center)
end

function Context:_randomSpawnFloor(): CFrame
	local n = math.max(#self._spawns, 8)
	return self:_spawnFloor(math.random(1, n), 0)
end

function Context:_respawnNow(p: Player)
	if not self._alive[p] or self._cleaned then
		return
	end
	if Teleport.to(p, self:_randomSpawnFloor(), self._frozen) then
		self._respawning[p] = nil
	else
		self._respawning[p] = true -- dead or no character yet: CharacterAdded will place them
	end
end

function Context:_onCharacter(p: Player, character: Model)
	if not self._alive[p] or self._stopped then
		return
	end
	self._respawning[p] = true
	task.spawn(function()
		character:WaitForChild("HumanoidRootPart", 5)
		task.wait() -- let the default spawn finish before we move it
		if p.Character == character and self._alive[p] and not self._stopped then
			self:_respawnNow(p)
		end
	end)
end

function Context:_onFall(p: Player, reason: string)
	if self._kind == "score" then
		self._respawning[p] = true
		if reason == "fell" then
			Teleport.setAnchored(p, true) -- hold them out of the way until the respawn
			Announce.toast(p, "Oops! Back in 2...")
		end
		task.delay(Context.SCORE_RESPAWN_DELAY, function()
			if self._alive[p] and not self._stopped then
				self:_respawnNow(p)
			end
		end)
	elseif Debug.noEliminate() then
		self:_respawnNow(p)
	else
		self:_eliminate(p, reason)
	end
end

function Context:_eliminate(p: Player, reason: string)
	if not self._alive[p] or self._stopped then
		return
	end
	if reason ~= "left" and Debug.noEliminate() then
		self:_respawnNow(p)
		return
	end
	self._alive[p] = nil
	self._alivePlayers -= 1
	self._respawning[p] = nil
	local placement = self._alivePlayers + 1
	local survived = self:_elapsed()
	self._placements[p] = placement
	self._survived[p] = survived
	if reason ~= "left" then
		Teleport.setAnchored(p, false)
	end
	local callback = self._params.onEliminated
	if type(callback) == "function" then
		task.spawn(callback, p, { reason = reason, placement = placement, survivedSeconds = survived })
	end
end

function Context:_endReason(): string?
	if self._finishRequested then
		return "finish"
	end
	local elapsed = self:_elapsed()
	local total = #self._all
	if self._kind == "score" then
		local duration = tonumber(self.definition.duration) or 60
		if elapsed >= duration then
			return "time"
		end
		if self._alivePlayers <= 0 then
			return "empty"
		end
		if elapsed >= math.max(Config.SAFETY_ROUND_LIMIT, duration + 5) then
			return "safety"
		end
		return nil
	end
	if total >= 2 and self._alivePlayers <= 1 then
		return "lastStanding"
	end
	if total < 2 and self._alivePlayers <= 0 then
		return "allOut"
	end
	if elapsed >= Config.SAFETY_ROUND_LIMIT then
		return "safety"
	end
	return nil
end

function Context:_pushScores(force: boolean?)
	local callback = self._params.onScores
	if self._kind ~= "score" or type(callback) ~= "function" or not self._scoresDirty then
		return
	end
	local now = os.clock()
	if not force and now - self._lastScorePush < Context.SCORE_PUSH_INTERVAL then
		return
	end
	self._lastScorePush = now
	self._scoresDirty = false
	task.spawn(callback, table.clone(self._scores))
end

function Context:_step()
	if not self._running then
		return
	end
	for _, p in self._all do
		if self._alive[p] and not self._respawning[p] then
			local character = p.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root then
				if humanoid.Health <= 0 then
					self:_onFall(p, "died")
				elseif (root :: BasePart).Position.Y < self.killY then
					self:_onFall(p, "fell")
				end
			end
		end
	end
	if not self._over then
		local reason = self:_endReason()
		if reason then
			self._over = true
			self._overReason = reason
			if reason == "safety" then
				warn(
					("[Core] %s hit the safety fuse after %ds"):format(self.definition.id, math.floor(self:_elapsed()))
				)
			end
			local callback = self._params.onFinish
			if type(callback) == "function" then
				task.spawn(callback, reason)
			end
		end
	end
	self:_pushScores(false)
end

-- Core / Solo API ----------------------------------------------------------------------------------

function Context:_build()
	assert(self.session == nil, "Context:_build called twice")
	local session = self.definition.create(self)
	if type(session) ~= "table" then
		error(("%s: create() must return a session table"):format(self.definition.id))
	end
	local map = session.map
	if typeof(map) ~= "Instance" or not map:IsA("Model") then
		error(("%s: session.map must be a Model"):format(self.definition.id))
	end
	if type(session.start) ~= "function" or type(session.stop) ~= "function" then
		error(("%s: session needs start() and stop()"):format(self.definition.id))
	end
	self.session = session
	self.map = map

	local killY = map:GetAttribute("KillY")
	if type(killY) == "number" and isFinite(killY) then
		self.killY = killY
	end
	local spawns = map:FindFirstChild("Spawns")
	if spawns then
		for _, child in spawns:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(self._spawns, child)
			end
		end
		table.sort(self._spawns, function(a, b)
			return a.Name < b.Name
		end)
	end
	if #self._spawns == 0 then
		warn(("[Core] %s map has no Spawns; using a ring around the center"):format(self.definition.id))
	end
	map.Parent = self._params.parent or workspace
	return session
end

function Context:_place(anchor: boolean)
	self._frozen = anchor
	local n = math.max(#self._spawns, 1)
	local offset = math.random(0, n - 1)
	local i = 0
	for _, p in self._all do
		if self._alive[p] then
			i += 1
			local floor = self:_spawnFloor((i - 1 + offset) % n + 1, (i - 1) // n)
			if Teleport.to(p, floor, anchor) then
				self._respawning[p] = nil
			else
				self._respawning[p] = true
			end
		end
	end
end

function Context:_start()
	if self._running or self._stopped then
		return
	end
	self._frozen = false
	self._running = true
	self._startClock = os.clock()
	for _, p in self._all do
		if self._alive[p] then
			Teleport.setAnchored(p, false)
		end
	end
	self._conns:connect(RunService.Heartbeat, function()
		self:_step()
	end)
	local session = self.session
	task.spawn(function()
		local ok, err = pcall(session.start, session)
		if not ok then
			warn(("[Core] %s start() failed: %s"):format(self.definition.id, tostring(err)))
		end
	end)
end

function Context:_isOver(): (boolean, string?)
	return self._over, self._overReason
end

function Context:_stop()
	if self._stopped then
		return
	end
	self._stopped = true
	self._running = false
	if self._startClock then
		self._stopClock = os.clock()
	end
	self._conns:clean()
	local session = self.session
	if session then
		local ok, err = pcall(session.stop, session)
		if not ok then
			warn(("[Core] %s stop() failed: %s"):format(self.definition.id, tostring(err)))
		end
	end
	-- Release anyone still frozen after a score-kind fall.
	for p in self._respawning do
		if p.Parent then
			Teleport.setAnchored(p, false)
		end
	end
	table.clear(self._respawning)
	self._scoresDirty = true
	self:_pushScores(true)
end

function Context:_results()
	local elapsed = self:_elapsed()
	local winners = {}
	local placements = table.clone(self._placements)
	local survived = table.clone(self._survived)
	local scores = nil

	for _, p in self._all do
		if self._alive[p] then
			survived[p] = elapsed
		end
	end

	if self._kind == "score" then
		scores = {}
		local ranked = {}
		for _, p in self._all do
			scores[p] = self._scores[p] or 0
			if p.Parent == Players then
				table.insert(ranked, p)
			end
		end
		table.sort(ranked, function(a, b)
			return scores[a] > scores[b]
		end)
		local place = 0
		local lastScore = nil
		for i, p in ranked do
			if scores[p] ~= lastScore then
				place = i
				lastScore = scores[p]
			end
			placements[p] = place
			if place == 1 and scores[p] > 0 then
				table.insert(winners, p)
			end
		end
	else
		local alive = self.players()
		if #self._all >= 2 or self._overReason == "safety" or self._overReason == "finish" then
			for _, p in alive do
				table.insert(winners, p)
				placements[p] = 1
			end
		end
	end

	return {
		kind = self._kind,
		reason = self._overReason,
		duration = elapsed,
		participants = table.clone(self._all),
		winners = winners,
		placements = placements,
		survived = survived,
		scores = scores,
	}
end

function Context:_cleanup()
	if self._cleaned then
		return
	end
	if not self._stopped then
		self:_stop()
	end
	self._cleaned = true
	if self.map then
		self.map:Destroy()
	end
	self.trove:clean()
end

function Context:_aliveCount(): number
	return self._alivePlayers
end

function Context:_isParticipant(p: Player): boolean
	return self._participant[p] == true
end

function Context:_wantsCharacter(p: Player): boolean
	return not self._stopped and self._alive[p] == true
end

return Context
