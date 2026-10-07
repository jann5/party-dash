--[[
Party Dash Core: Context, the `ctx` handed to minigames (see src/shared/Contracts/Minigame.lua).
One Context = one running copy of a minigame. Core builds one for the main arena; Solo Record builds private ones
at Config.SOLO_ORIGIN. A Context enforces elimination by itself (its own Heartbeat watcher), so every copy behaves
the same no matter who runs it. The running MAIN context is reachable through
`require(ServerScriptService.Server.Core.State).mainContext()` (nil outside Intro .. End).

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
		onEliminated = function(player, info) end,  -- optional (task.spawned); info = {
		                                 --   reason: string ("fell", "died", "left", "stuck" or what a minigame
		                                 --   passed to ctx.eliminate), placement: number, survivedSeconds: number,
		                                 --   [v2] killer: Player? (KO credit), participants: number,
		                                 --   aliveLeft: number, position: Vector3? (root position at the moment) }
		onRevived = function(player, info) end,     -- [v2] optional, called synchronously by ctx:_revive once the
		                                 --   player is alive again; info = { revives: number }
		onSuddenDeath = function() end,  -- [v2] optional; default: ctx.announce("SUDDEN DEATH!")
		suddenDeath = true,              -- [v2] optional, false disables sudden death for this copy
		onFinish = function(reason) end, -- optional; fired once when the end condition is reached:
		                                 --   "lastStanding" | "allOut" | "time" | "empty" | "finish" | "safety"
		onScores = function(scores) end, -- optional; { [Player]: number }, throttled to ~4x/s when changed
	})

	Methods for Core / Solo (underscore = not for minigames):
	local session = ctx:_build()       -- calls definition.create(ctx), validates the session, reads the map's
	                                   --   KillY attribute and Spawns, parents session.map. Errors propagate
	                                   --   (wrap it in pcall, then call ctx:_cleanup() on failure).
	ctx:_place(anchor: boolean)        -- puts every alive player on the map's Spawns round-robin; anchor = true
	                                   --   freezes their HumanoidRootParts (Intro/Countdown). Never touches JumpPower.
	ctx:_start()                       -- unfreezes, starts the clock + elimination watcher, calls session:start().
	ctx:_isOver(): (boolean, string?)  -- true once an end condition was reached (also see onFinish).
	ctx:_stop()                        -- idempotent; stops the watcher and calls session:stop(). After this,
	                                   --   knockback/eliminate/addScore are no-ops. The map stays (results).
	ctx:_results(): Results            -- see below; call after _stop().
	ctx:_cleanup()                     -- idempotent; _stop() if needed, destroys session.map, ctx.trove:clean().
	ctx:_aliveCount(): number
	ctx:_isParticipant(Player): boolean
	ctx:_isRunning(): boolean          -- between _start() and _stop()
	ctx:_isSuddenDeath(): boolean      -- [v2]
	ctx:_wantsCharacter(Player): boolean  -- true if this context will (re)place this player's new character.
	ctx:_respawnNow(Player)            -- puts an alive player back on a random spawn (frozen during Intro).
	ctx:_revive(Player): boolean       -- [v2] an eliminated participant re-enters the running round: alive again,
	                                   --   placement removed, placed at session:onRevive(player) (a floor CFrame)
	                                   --   or a random spawn, character ShieldUntil = now + Config.SPAWN_SHIELD,
	                                   --   then params.onRevived. False when the round is over, the player is
	                                   --   alive / not a participant / gone, or already used REVIVE_MAX_PER_ROUND.
	ctx:_revivesUsed(Player): number   -- [v2]
	ctx:_offerRevive(Player, endsAt)   -- [v2] Core.Revive bookkeeping: the revive window (server time)
	ctx:_reviveOffer(Player): number?  -- [v2]
	ctx:_holdEnd(untilServerTime)      -- [v2] Debug_FreeRevive grace: the round does not end before this time

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
		kos: { [Player]: number },          -- [v2] KO credits this round (players with >= 1)
		mvp: Player?,                       -- [v2] most KOs (>= 1), ties go to the better placement
	}

Rules enforced here:
	- Falling below ctx.killY (= max(map attribute "KillY", center.Y - Config.KILL_DEPTH)), Humanoid death or
	  ctx.eliminate ELIMINATES. Only a definition with fallRule = "respawn" freezes the player and puts them back
	  on a spawn after Context.RESPAWN_DELAY (nothing in v2 uses it).
	- Debug_NoEliminate (Studio only): falls and eliminations put the player back on the map instead.
	- Debug_IntensityOverride (Studio only): replaces the ramp (sudden death still doubles it).
	- KO credit: ctx.knockback(..., attacker) / ctx.credit(victim, attacker) set the victim's Player attributes
	  LastHitBy (UserId) / LastHitAt (server time). An elimination within Config.KO_CREDIT_WINDOW of LastHitAt
	  credits that attacker (info.killer, Player attribute KOs += 1, Results.kos / mvp).
	- Shield: ctx.knockback ignores a player whose character ShieldUntil > now (and players not alive).
	- Sudden death: at Config.SUDDEN_DEATH_AT seconds (Debug_SuddenDeathAt in Studio) ctx.intensity() doubles.
	- A character that cannot be placed is retried every Context.RESPAWN_RETRY s and eliminated ("stuck") after
	  Context.RESPAWN_GIVE_UP s, so nobody can idle off-map as an "alive" player.
	- End: survival with >= 2 participants -> alive <= 1; with 1 participant -> alive == 0;
	  score -> definition.duration elapsed (or nobody left); any kind -> ctx.finish(); Config.SAFETY_ROUND_LIMIT fuse.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Knockback = require(Shared.Knockback)
local Theme = require(Shared.Theme)
local Trove = require(Shared.Util.Trove)

local Server = script.Parent.Parent
local Announce = require(Server.Announce)
local Debug = require(script.Parent.Debug)
local Teleport = require(script.Parent.Teleport)

local Context = {}
Context.__index = Context

Context.RESPAWN_DELAY = 2 -- fallRule "respawn": seconds frozen before going back on a spawn
Context.RESPAWN_RETRY = 1 -- seconds between attempts to place a character that could not be placed
Context.RESPAWN_GIVE_UP = 8 -- an alive player we could not place for this long is eliminated ("stuck")
Context.CHARACTER_WAIT = 5 -- seconds to wait for a new character's HumanoidRootPart
Context.SCORE_PUSH_INTERVAL = 0.25

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function isFinite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
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
	self._respawnAt = {} :: { [Player]: number } -- os.clock() of the next placement attempt
	self._respawnSince = {} :: { [Player]: number } -- os.clock() since the player has been waiting for a placement
	self._kos = {} :: { [Player]: number }
	self._revives = {} :: { [Player]: number }
	self._reviveOffers = {} :: { [Player]: number } -- server time the revive window closes
	self._shieldPending = {} :: { [Player]: boolean } -- revived, shield starts once the character is placed
	self._graceUntil = 0
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
	self._suddenDeath = false
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
		local value = Debug.intensityOverride()
			or (1 + self:_elapsed() / Config.INTENSITY_RAMP_SECONDS) * self._multiplier
		return if self._suddenDeath then value * 2 else value
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
	self.isShielded = function(p: Player): boolean
		if self._shieldPending[p] then
			return true
		end
		local character = isPlayer(p) and p.Character
		local shieldUntil = character and character:GetAttribute("ShieldUntil")
		return type(shieldUntil) == "number" and shieldUntil > serverNow()
	end
	self.credit = function(victim: Player, attacker: Player)
		if not isPlayer(victim) or not isPlayer(attacker) or attacker == victim then
			return
		end
		if self._stopped or not self._alive[victim] then
			return
		end
		victim:SetAttribute("LastHitBy", attacker.UserId)
		victim:SetAttribute("LastHitAt", serverNow())
	end
	self.knockback = function(p: Player, direction: Vector3, power: number, stun: number?, attacker: Player?): boolean
		if not self._running or not self._alive[p] or self.isShielded(p) then
			return false
		end
		if not Knockback.apply(p, direction, power, stun) then
			return false
		end
		if attacker then
			self.credit(p, attacker)
		end
		return true
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

-- Remembers that `p` needs a placement in `delay` seconds (fresh = restart the give-up timer).
function Context:_scheduleRespawn(p: Player, delay: number, fresh: boolean?)
	local clock = os.clock()
	if fresh or not self._respawnSince[p] then
		self._respawnSince[p] = clock
	end
	self._respawnAt[p] = clock + delay
end

function Context:_clearRespawn(p: Player)
	self._respawnAt[p] = nil
	self._respawnSince[p] = nil
end

-- A revived player's shield starts when their character actually stands on the map.
function Context:_startShield(p: Player)
	if not self._shieldPending[p] then
		return
	end
	local character = p.Character
	if character then
		self._shieldPending[p] = nil
		character:SetAttribute("ShieldUntil", serverNow() + Config.SPAWN_SHIELD)
	end
end

-- Places the character on `floor`; on failure (no live character yet) a retry is scheduled.
function Context:_placeAt(p: Player, floor: CFrame, anchor: boolean): boolean
	if Teleport.to(p, floor, anchor) then
		self:_clearRespawn(p)
		self:_startShield(p)
		return true
	end
	self:_scheduleRespawn(p, Context.RESPAWN_RETRY)
	return false
end

function Context:_respawnNow(p: Player)
	if not self._alive[p] or self._cleaned then
		return
	end
	self:_placeAt(p, self:_randomSpawnFloor(), self._frozen)
end

function Context:_onCharacter(p: Player, character: Model)
	if not self._alive[p] or self._stopped then
		return
	end
	-- Fallback retry in case the root never shows up; the thread below normally places it right away.
	self:_scheduleRespawn(p, Context.CHARACTER_WAIT + 0.5, true)
	task.spawn(function()
		character:WaitForChild("HumanoidRootPart", Context.CHARACTER_WAIT)
		task.wait() -- let the default spawn finish before we move it
		if p.Character == character and self._alive[p] and not self._stopped then
			self:_respawnNow(p)
		end
	end)
end

function Context:_onFall(p: Player, reason: string)
	if Debug.noEliminate() then
		self:_respawnNow(p)
	elseif self.definition.fallRule == "respawn" then
		if reason == "fell" then
			Teleport.setAnchored(p, true) -- hold them out of the way until the respawn
			Announce.toast(p, "Oops! Back in 2...")
		end
		self:_scheduleRespawn(p, Context.RESPAWN_DELAY, true)
	else
		self:_eliminate(p, reason)
	end
end

-- The attacker credited for knocking `p` out, if a recent player-caused hit qualifies.
function Context:_killerOf(p: Player): Player?
	local by = p:GetAttribute("LastHitBy")
	local at = p:GetAttribute("LastHitAt")
	if type(by) ~= "number" or by == 0 or type(at) ~= "number" then
		return nil
	end
	if serverNow() - at > Config.KO_CREDIT_WINDOW then
		return nil
	end
	local killer = Players:GetPlayerByUserId(by)
	if killer and killer ~= p and self._participant[killer] then
		return killer
	end
	return nil
end

function Context:_eliminate(p: Player, reason: string)
	if not self._alive[p] or self._stopped then
		return
	end
	if reason ~= "left" and reason ~= "stuck" and Debug.noEliminate() then
		self:_respawnNow(p)
		return
	end
	local killer = if reason ~= "left" then self:_killerOf(p) else nil
	self._alive[p] = nil
	self._alivePlayers -= 1
	self:_clearRespawn(p)
	self._shieldPending[p] = nil
	local placement = self._alivePlayers + 1
	local survived = self:_elapsed()
	self._placements[p] = placement
	self._survived[p] = survived
	if killer then
		self._kos[killer] = (self._kos[killer] or 0) + 1
		if killer.Parent == Players then
			killer:SetAttribute("KOs", (tonumber(killer:GetAttribute("KOs")) or 0) + 1)
		end
	end
	local position: Vector3? = nil
	if p.Parent == Players then
		p:SetAttribute("LastHitBy", 0)
		p:SetAttribute("LastHitAt", 0)
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			position = root.Position
			if root.Anchored then
				Teleport.setAnchored(p, false) -- release a frozen (Intro) or held (fallRule) character
			end
		end
	end
	local callback = self._params.onEliminated
	if type(callback) == "function" then
		task.spawn(callback, p, {
			reason = reason,
			placement = placement,
			survivedSeconds = survived,
			killer = killer,
			participants = #self._all,
			aliveLeft = self._alivePlayers,
			position = position,
		})
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
	local reason = nil
	if total >= 2 and self._alivePlayers <= 1 then
		reason = "lastStanding"
	elseif total < 2 and self._alivePlayers <= 0 then
		reason = "allOut"
	end
	if reason and serverNow() < self._graceUntil and Debug.freeRevive() then
		return nil -- a revive window is open (Debug_FreeRevive): let it be tested before the round ends
	end
	if reason then
		return reason
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

function Context:_checkSuddenDeath()
	if self._suddenDeath or self._params.suddenDeath == false then
		return
	end
	local at = Debug.suddenDeathAt() or Config.SUDDEN_DEATH_AT
	if self:_elapsed() < at then
		return
	end
	self._suddenDeath = true
	local callback = self._params.onSuddenDeath
	if type(callback) == "function" then
		task.spawn(callback)
	else
		self.announce("SUDDEN DEATH!", nil, Theme.Colors.Red)
	end
end

function Context:_step()
	if not self._running then
		return
	end
	local clock = os.clock()
	for _, p in self._all do
		if self._alive[p] then
			local retryAt = self._respawnAt[p]
			if retryAt then
				-- Waiting for a placement: never fall-checked (the new character may still be at its spawn point).
				if clock - (self._respawnSince[p] or clock) > Context.RESPAWN_GIVE_UP then
					self:_eliminate(p, "stuck")
				elseif clock >= retryAt then
					self:_respawnNow(p)
				end
			else
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
	end
	self:_checkSuddenDeath()
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

	-- A map may raise the kill plane, never lower it under the default (no swimming under the sea).
	local killY = map:GetAttribute("KillY")
	if type(killY) == "number" and isFinite(killY) then
		self.killY = math.max(killY, self.center.Position.Y - Config.KILL_DEPTH)
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
			self:_placeAt(p, self:_spawnFloor((i - 1 + offset) % n + 1, (i - 1) // n), anchor)
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
			Teleport.setAnchored(p, false) -- only unanchors: JumpPower/WalkSpeed stay Movement's business
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
	-- Release anyone still held for a placement (fallRule freeze, failed teleports).
	for p in self._respawnAt do
		if p.Parent then
			Teleport.setAnchored(p, false)
		end
	end
	table.clear(self._respawnAt)
	table.clear(self._respawnSince)
	table.clear(self._shieldPending)
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

	local kos = {}
	local mvp: Player? = nil
	for p, n in self._kos do
		if n >= 1 then
			kos[p] = n
			local best = mvp and kos[mvp] or 0
			if n > best or (n == best and (placements[p] or math.huge) < (placements[mvp :: Player] or math.huge)) then
				mvp = p
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
		kos = kos,
		mvp = mvp,
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

function Context:_revive(p: Player): boolean
	if self._stopped or not self._running or self._over then
		return false
	end
	if not isPlayer(p) or not self._participant[p] or self._alive[p] or p.Parent ~= Players then
		return false
	end
	if self:_revivesUsed(p) >= Config.REVIVE_MAX_PER_ROUND then
		return false
	end
	self._revives[p] = self:_revivesUsed(p) + 1
	self._reviveOffers[p] = nil
	self._alive[p] = true
	self._alivePlayers += 1
	self._placements[p] = nil
	self._survived[p] = nil
	self._shieldPending[p] = true
	p:SetAttribute("LastHitBy", 0)
	p:SetAttribute("LastHitAt", 0)

	-- Where to put them: the minigame decides (it also resets its per-player state), else a random spawn.
	local floor: CFrame? = nil
	local session = self.session
	if session and type(session.onRevive) == "function" then
		local ok, result = pcall(session.onRevive, session, p)
		if not ok then
			warn(("[Core] %s onRevive failed: %s"):format(self.definition.id, tostring(result)))
		elseif typeof(result) == "CFrame" then
			floor = result
		end
	end
	self:_placeAt(p, floor or self:_randomSpawnFloor(), false)

	local callback = self._params.onRevived
	if type(callback) == "function" then
		local ok, err = pcall(callback, p, { revives = self._revives[p] })
		if not ok then
			warn("[Core] onRevived failed: " .. tostring(err))
		end
	end
	return true
end

function Context:_revivesUsed(p: Player): number
	return self._revives[p] or 0
end

function Context:_offerRevive(p: Player, endsAt: number)
	self._reviveOffers[p] = endsAt
end

function Context:_reviveOffer(p: Player): number?
	return self._reviveOffers[p]
end

function Context:_holdEnd(untilServerTime: number)
	self._graceUntil = math.max(self._graceUntil, untilServerTime)
end

function Context:_aliveCount(): number
	return self._alivePlayers
end

function Context:_isParticipant(p: Player): boolean
	return self._participant[p] == true
end

function Context:_isRunning(): boolean
	return self._running
end

function Context:_isSuddenDeath(): boolean
	return self._suddenDeath
end

function Context:_wantsCharacter(p: Player): boolean
	return not self._stopped and self._alive[p] == true
end

return Context
