--[[
Party Dash: DODGEBALL (survival).
Ten cartoon cannons ring a floating court and lob bright balls at the players. Every shot is telegraphed
(the cannon turns, glows and shakes, a ring marks the landing spot), then flies on a deterministic arc.
A hit is a big knockback, and the court has no walls. Every ~12 s a golden ball appears: grab it and
throw it (click / THROW button) to bonk someone else off the court. Hazards escalate forever.

Server-authoritative design:
  * Balls are pure data (Ballistics segments planned from server time). The server checks hits against
    HumanoidRootParts every Heartbeat; clients render the very same arcs from the "shot" message.
  * Remotes: "Dodgeball_Fx" (server -> all clients: shot / pop / golden / grab / clear, keyed by the
    session id) and "Dodgeball_Throw" (client -> server: throw direction, validated + rate limited).
  * Map attributes for tests: ShotsFired, Hits, FireInterval, ActiveBalls, GoldenThrows, DodgeballSession.
  * No module-level mutable state: everything lives in the create() closure (main arena + Solo copies).
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)

local Ballistics = require(script.Ballistics)
local Hit = require(script.Hit)
local Map = require(script.Map)
local Tuning = require(script.Tuning)

local FX_REMOTE = "Dodgeball_Fx"
local THROW_REMOTE = "Dodgeball_Throw"
local HOLD_ATTRIBUTE = "HoldingGoldenBall"

-- Create the remotes when Core loads the minigame, so clients never wait for them.
Net.event(FX_REMOTE)
Net.event(THROW_REMOTE)

local BALL_COLORS = {
	Theme.Colors.Red,
	Theme.Colors.Blue,
	Theme.Colors.Pink,
	Theme.Colors.Green,
	Theme.Colors.Cyan,
	Theme.Colors.Purple,
}
local GIANT_COLOR = Color3.fromRGB(120, 60, 200)
local GOLD_COLOR = Color3.fromRGB(255, 208, 64)

type Ball = {
	id: number,
	kind: string, -- "ball" | "giant" | "gold"
	segments: { Ballistics.Segment },
	g: number,
	radius: number,
	launchAt: number,
	endAt: number,
	power: number,
	stun: number,
	owner: Player?, -- thrower of a golden ball (never hit by it)
	launched: boolean,
	lastPos: Vector3,
	hit: { [Player]: boolean },
}

local function isFiniteVector(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < math.huge
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local definition = {
	id = "Dodgeball",
	displayName = "DODGEBALL",
	rules = "Dodge the cannonballs! Grab the golden ball and throw it at someone!",
	keys = { "Dash", "Throw", "Jump" },
	kind = "survival",
	soloCapable = true,
}

function definition.create(ctx)
	local rng = Random.new()
	local built = Map.build(ctx.center, rng)
	local map = built.model
	local origin = ctx.center.Position
	local floorY = built.floorY
	local floor: Ballistics.Floor = { y = floorY, center = origin, radius = Tuning.ARENA_RADIUS }
	local sessionId = HttpService:GenerateGUID(false)
	local fx = Net.event(FX_REMOTE)
	local throwRemote = Net.event(THROW_REMOTE)

	map:SetAttribute("DodgeballSession", sessionId)
	map:SetAttribute("ArenaCenter", origin)
	map:SetAttribute("ArenaRadius", Tuning.ARENA_RADIUS)
	map:SetAttribute("ShotsFired", 0)
	map:SetAttribute("Hits", 0)
	map:SetAttribute("FireInterval", Tuning.fireInterval(1))
	map:SetAttribute("ActiveBalls", 0)
	map:SetAttribute("GoldenThrows", 0)

	-- Session state ----------------------------------------------------------------------------------
	local running = false
	local nextId = 0
	local balls: { Ball } = {}
	local ballPool: { Ball } = {}
	local cannonBusyUntil: { [number]: number } = {}
	local nextVolleyAt = math.huge
	local shotsFired = 0
	local hits = 0
	local goldenThrows = 0
	local lastActive = -1
	local lastIntervalWrite = 0
	local giantsAnnounced = false

	local goldenPart: BasePart? = nil
	local goldenPos: Vector3? = nil
	local nextGoldenAt = math.huge
	local holders: { [Player]: { character: Model, visual: BasePart? } } = {}
	local lastThrow: { [Player]: number } = {}

	local function now(): number
		return workspace:GetServerTimeNow()
	end

	local function broadcast(kind: string, ...)
		fx:FireAllClients(kind, sessionId, ...)
	end

	-- Balls ------------------------------------------------------------------------------------------

	local function acquireBall(): Ball
		local b = table.remove(ballPool)
		if b then
			table.clear(b.hit)
			return b
		end
		return {
			id = 0,
			kind = "ball",
			segments = {},
			g = 0,
			radius = 0,
			launchAt = 0,
			endAt = 0,
			power = 0,
			stun = 0,
			owner = nil,
			launched = false,
			lastPos = Vector3.zero,
			hit = {},
		}
	end

	local function releaseAt(index: number)
		local b = balls[index]
		balls[index] = balls[#balls]
		balls[#balls] = nil
		b.owner = nil
		b.segments = {}
		table.clear(b.hit)
		table.insert(ballPool, b)
	end

	-- Registers a planned ball and tells every client to render it.
	local function addBall(
		kind: string,
		from: Vector3,
		velocity: Vector3,
		launchAt: number,
		g: number,
		radius: number,
		maxBounces: number,
		maxLife: number,
		color: Color3,
		cannonIndex: number,
		target: Vector3?
	): Ball
		local plan = Ballistics.plan(from, velocity, launchAt, g, radius, floor, maxBounces, maxLife)
		nextId += 1
		local b = acquireBall()
		b.id = nextId
		b.kind = kind
		b.segments = plan.segments
		b.g = g
		b.radius = radius
		b.launchAt = launchAt
		b.endAt = plan.endAt
		b.launched = false
		b.lastPos = from
		table.insert(balls, b)
		broadcast(
			"shot",
			b.id,
			kind,
			cannonIndex,
			launchAt,
			plan.endAt,
			plan.fizzle,
			g,
			radius,
			color,
			Ballistics.pack(plan.segments),
			target
		)
		return b
	end

	-- Cannons ----------------------------------------------------------------------------------------

	-- Where a cannon should aim: usually a player (with a slight lead), sometimes a random spot.
	local function pickTarget(chargeTime: number, speed: number, cannon: Map.CannonInfo): Vector3
		local alive = ctx.players()
		local height = floorY + Tuning.TARGET_HEIGHT
		if #alive > 0 and rng:NextNumber() < Tuning.AIM_AT_PLAYER then
			local p = alive[rng:NextInteger(1, #alive)]
			local root = rootOf(p)
			if root and root.Position.Y > floorY - 4 then
				local pos = flat(root.Position)
				local travel = (pos - flat(cannon.trunnion)).Magnitude / speed
				local lead = flat(root.AssemblyLinearVelocity) * ((chargeTime + travel) * Tuning.LEAD_FACTOR)
				if lead.Magnitude > Tuning.MAX_LEAD then
					lead = lead.Unit * Tuning.MAX_LEAD
				end
				local target = pos + lead
				local offset = target - flat(origin)
				if offset.Magnitude > Tuning.ARENA_RADIUS - 1.5 then
					target = flat(origin) + offset.Unit * (Tuning.ARENA_RADIUS - 1.5)
				end
				return Vector3.new(target.X, height, target.Z)
			end
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = math.sqrt(rng:NextNumber()) * Tuning.ARENA_RADIUS * 0.85
		return Vector3.new(origin.X + math.cos(a) * d, height, origin.Z + math.sin(a) * d)
	end

	-- Muzzle position for a barrel aimed along `flatDir` with `pitch` (matches the client's barrel pose).
	local function muzzle(cannon: Map.CannonInfo, flatDir: Vector3, pitch: number): Vector3
		local aim = flatDir * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		return cannon.trunnion + aim * (Tuning.BARREL_FRONT * Tuning.CANNON_SCALE)
	end

	local function fireCannon(cannon: Map.CannonInfo, intensity: number, t: number)
		local chargeTime = Tuning.chargeTime(intensity)
		local giant = rng:NextNumber() < Tuning.giantChance(intensity)
		local speed = Tuning.ballSpeed(intensity) * (if giant then 0.78 else 1)
		local radius = if giant then Tuning.GIANT_RADIUS else Tuning.BALL_RADIUS
		local target = pickTarget(chargeTime, speed, cannon)
		if giant then
			target = Vector3.new(target.X, floorY + radius, target.Z)
		end
		local toward = flat(target - cannon.trunnion)
		if toward.Magnitude < 1 then
			return
		end
		local flatDir = toward.Unit
		-- Two passes: aim from the level muzzle, then from the pitched one.
		local launchAt = t + chargeTime
		local start = muzzle(cannon, flatDir, 0)
		local velocity = Ballistics.solve(start, target, speed, Tuning.GRAVITY)
		local pitch = math.clamp(math.atan2(velocity.Y, flat(velocity).Magnitude), Tuning.MIN_PITCH, Tuning.MAX_PITCH)
		start = muzzle(cannon, flatDir, pitch)
		velocity = Ballistics.solve(start, target, speed, Tuning.GRAVITY)

		local ball = addBall(
			if giant then "giant" else "ball",
			start,
			velocity,
			launchAt,
			Tuning.GRAVITY,
			radius,
			Tuning.MAX_BOUNCES,
			Tuning.MAX_LIFE,
			if giant then GIANT_COLOR else BALL_COLORS[rng:NextInteger(1, #BALL_COLORS)],
			cannon.index,
			target
		)
		ball.power = Tuning.knockPower(intensity, giant)
		ball.stun = Tuning.STUN
		ball.owner = nil
		cannonBusyUntil[cannon.index] = launchAt + Tuning.RECOIL_TIME
	end

	local function volley(t: number)
		local intensity = ctx.intensity()
		if not giantsAnnounced and Tuning.giantChance(intensity) > 0 then
			giantsAnnounced = true
			ctx.announce("GIANT BALLS!", "They plow through everyone in their way!", Theme.Colors.Purple)
		end
		local count = Tuning.volleySize(intensity, #ctx.players())
		local free = {}
		for _, cannon in built.cannons do
			if (cannonBusyUntil[cannon.index] or 0) <= t then
				table.insert(free, cannon)
			end
		end
		for _ = 1, count do
			if #free == 0 or #balls >= Tuning.MAX_ACTIVE then
				break
			end
			local cannon = table.remove(free, rng:NextInteger(1, #free)) :: Map.CannonInfo
			fireCannon(cannon, intensity, t)
		end
	end

	-- Golden ball ------------------------------------------------------------------------------------

	local function setHolding(character: Model?, holding: boolean)
		if character and character.Parent then
			character:SetAttribute(HOLD_ATTRIBUTE, if holding then true else false)
		end
	end

	local function dropHolding(player: Player)
		local h = holders[player]
		if not h then
			return
		end
		holders[player] = nil
		if h.visual then
			h.visual:Destroy()
		end
		setHolding(h.character, false)
	end

	local function spawnGolden()
		-- A random spot on the court, not right on top of somebody.
		local pos = origin
		for _ = 1, 10 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = math.sqrt(rng:NextNumber()) * Tuning.ARENA_RADIUS * 0.6
			pos = origin + Vector3.new(math.cos(a) * d, Tuning.GOLD_FLOOR_HEIGHT, math.sin(a) * d)
			local clear = true
			for _, p in ctx.players() do
				local root = rootOf(p)
				if root and (flat(root.Position) - flat(pos)).Magnitude < 8 then
					clear = false
					break
				end
			end
			if clear then
				break
			end
		end
		goldenPart = Map.goldenBall(built.golden, pos)
		goldenPos = pos
		broadcast("golden", pos)
		ctx.feed("A GOLDEN BALL appeared! Grab it!")
	end

	local function pickUp(player: Player, character: Model)
		if goldenPart then
			goldenPart:Destroy()
		end
		local pos = goldenPos or origin
		goldenPart = nil
		goldenPos = nil
		nextGoldenAt = now() + Tuning.GOLD_EVERY
		holders[player] = { character = character, visual = Map.heldBall(character) }
		setHolding(character, true)
		broadcast("grab", pos, player.UserId)
		ctx.feed(("%s grabbed the GOLDEN BALL!"):format(player.DisplayName))
	end

	-- Best other player inside the aim-assist cone around `dir`, or nil.
	local function assistTarget(thrower: Player, from: Vector3, dir: Vector3): BasePart?
		local best: BasePart? = nil
		local bestAngle = Tuning.GOLD_ASSIST_ANGLE
		for _, p in ctx.players() do
			if p ~= thrower then
				local root = rootOf(p)
				if root then
					local to = flat(root.Position - from)
					local dist = to.Magnitude
					if dist > 3 and dist < Tuning.GOLD_ASSIST_RANGE then
						local angle = math.acos(math.clamp(to.Unit:Dot(dir), -1, 1))
						if angle < bestAngle then
							bestAngle = angle
							best = root
						end
					end
				end
			end
		end
		return best
	end

	local function onThrow(player: Player, direction: any)
		if not running or not holders[player] then
			return
		end
		if typeof(direction) ~= "Vector3" or not isFiniteVector(direction) or direction.Magnitude < 1e-3 then
			return
		end
		local t = now()
		if t - (lastThrow[player] or -math.huge) < Tuning.THROW_COOLDOWN then
			return
		end
		local root = rootOf(player)
		if not root or player.Character ~= holders[player].character then
			return
		end
		lastThrow[player] = t
		local dir = direction.Unit
		local flatDir = flat(dir)
		if flatDir.Magnitude < 0.15 then
			flatDir = flat(root.CFrame.LookVector)
		end
		if flatDir.Magnitude < 1e-3 then
			flatDir = Vector3.zAxis
		end
		flatDir = flatDir.Unit
		local start = root.Position + Vector3.new(0, 2.6, 0) + flatDir * 2.5

		local velocity
		local target = assistTarget(player, start, flatDir)
		if target then
			local aim = target.Position
			local travel = flat(aim - start).Magnitude / Tuning.GOLD_SPEED
			aim += flat(target.AssemblyLinearVelocity) * travel * 0.5
			velocity = Ballistics.solve(start, aim, Tuning.GOLD_SPEED, Tuning.GOLD_GRAVITY)
		else
			-- Free throw: follow the camera (which looks slightly down at us), but keep the ball at about
			-- chest height instead of spiking it into the floor or lobbing it into the sky.
			local rise = math.clamp(dir.Y + 0.15, -0.06, 0.12)
			velocity = (flatDir + Vector3.new(0, rise, 0)).Unit * Tuning.GOLD_SPEED
		end

		dropHolding(player)
		local b = addBall(
			"gold",
			start,
			velocity,
			t,
			Tuning.GOLD_GRAVITY,
			Tuning.GOLD_RADIUS,
			1,
			Tuning.GOLD_MAX_LIFE,
			GOLD_COLOR,
			0,
			nil
		)
		b.owner = player
		b.power = Tuning.GOLD_POWER
		b.stun = Tuning.GOLD_STUN
		goldenThrows += 1
		map:SetAttribute("GoldenThrows", goldenThrows)
	end

	-- Per-frame simulation -------------------------------------------------------------------------

	local function applyHit(b: Ball, player: Player, root: BasePart, pos: Vector3, t: number)
		b.hit[player] = true
		hits += 1
		map:SetAttribute("Hits", hits)
		local dir = flat(Ballistics.velocity(b.segments, b.g, t))
		if dir.Magnitude < 1 then
			dir = flat(root.Position - pos)
		end
		if dir.Magnitude < 1e-3 then
			dir = Vector3.xAxis
		end
		ctx.knockback(player, dir.Unit, b.power, b.stun)
		if b.kind == "gold" and b.owner then
			ctx.feed(("%s BONKED %s with the golden ball!"):format(b.owner.DisplayName, player.DisplayName))
		end
	end

	local function stepBalls(t: number)
		local alive = ctx.players()
		local roots: { [Player]: BasePart } = {}
		for _, p in alive do
			local root = rootOf(p)
			if root then
				roots[p] = root
			end
		end
		local i = 1
		while i <= #balls do
			local b = balls[i]
			local removed = false
			if t >= b.launchAt then
				if not b.launched then
					b.launched = true
					if b.kind ~= "gold" then
						shotsFired += 1
						map:SetAttribute("ShotsFired", shotsFired)
					end
				end
				local pos = Ballistics.position(b.segments, b.g, math.min(t, b.endAt))
				for p, root in roots do
					if
						p ~= b.owner
						and not b.hit[p]
						and Hit.segmentHitsPlayer(b.lastPos, pos, b.radius, root.Position)
					then
						applyHit(b, p, root, pos, t)
						if b.kind ~= "giant" then
							-- Normal and golden balls pop on the first player they hit.
							broadcast("pop", b.id, pos, b.kind)
							releaseAt(i)
							removed = true
							break
						end
					end
				end
				if not removed then
					b.lastPos = pos
					if t >= b.endAt then
						releaseAt(i)
						removed = true
					end
				end
			end
			if not removed then
				i += 1
			end
		end
		if #balls ~= lastActive then
			lastActive = #balls
			map:SetAttribute("ActiveBalls", lastActive)
		end
	end

	local function stepGolden(t: number)
		-- Holders who fell, died or respawned lose the ball.
		for p, h in holders do
			if not ctx.isAlive(p) or p.Character ~= h.character or not h.character.Parent then
				dropHolding(p)
			end
		end
		if goldenPos then
			for _, p in ctx.players() do
				local root = rootOf(p)
				if
					root
					and not holders[p]
					and p.Character
					and (root.Position - goldenPos).Magnitude < Tuning.GOLD_PICKUP_RANGE
				then
					pickUp(p, p.Character)
					break
				end
			end
		elseif t >= nextGoldenAt then
			nextGoldenAt = math.huge
			spawnGolden()
		end
	end

	local function step()
		if not running then
			return
		end
		local t = now()
		if t >= nextVolleyAt then
			volley(t)
			local interval = Tuning.fireInterval(ctx.intensity())
			nextVolleyAt = t + interval
		end
		-- Keep FireInterval live (about 4x per second) so tests can read it at any intensity.
		if t - lastIntervalWrite > 0.25 then
			lastIntervalWrite = t
			map:SetAttribute("FireInterval", math.floor(Tuning.fireInterval(ctx.intensity()) * 1000 + 0.5) / 1000)
		end
		stepBalls(t)
		stepGolden(t)
	end

	-- Session ----------------------------------------------------------------------------------------

	local session = { map = map }

	function session.start(_self)
		running = true
		local t = now()
		nextVolleyAt = t + Tuning.GRACE
		nextGoldenAt = t + Tuning.GOLD_FIRST
		ctx.trove:connect(RunService.Heartbeat, step)
		ctx.trove:connect(throwRemote.OnServerEvent, onThrow)
	end

	function session.stop(_self)
		running = false
		for p in holders do
			dropHolding(p)
		end
		table.clear(balls)
		table.clear(ballPool)
		if goldenPart then
			goldenPart:Destroy()
			goldenPart = nil
		end
		goldenPos = nil
		map:SetAttribute("ActiveBalls", 0)
		broadcast("clear")
	end

	ctx.trove:connect(Players.PlayerRemoving, function(p: Player)
		holders[p] = nil
		lastThrow[p] = nil
	end)
	-- Safety net: never leave a held ball or the attribute behind, even if stop() was skipped.
	ctx.trove:add(function()
		running = false
		for p in holders do
			dropHolding(p)
		end
	end)

	return session
end

return definition
