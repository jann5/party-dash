--[[
Party Dash: SPIN, the port of the legacy game. Everybody stands on a ring of 12 pillars while a neon bar
sweeps around the hub: jump over it or get knocked into the lava. The bar speeds up with ctx.intensity(),
a second counter-rotating bar joins past intensity 2.2 and, later on, bars reverse direction (telegraphed
by a flash). Last one standing wins.

Server: bar motion is a deterministic segment of server time (BarMath, shared with the client), hits are
checked here every frame with Hit.check and delivered with ctx.knockback. Clients render the bars smoothly
from the same math (src/client/Minigames/Spin). All state lives in create()'s closure (session-safe).

Map attributes: Hits (total bar hits), BarSpeed (nominal rad/s of the main bar), BarCount, Center, KillY.
Bar Model attributes: State (BarMath.encode), Color, AppearAt (server time a late bar starts rising).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)
local Arena = require(script.Arena)
local Hit = require(script.Hit)

local BarMath = Arena.BarMath

type State = {
	a0: number,
	t0: number,
	w0: number,
	w1: number,
	ramp: number,
	dir: number,
	rt: number,
}

type Bar = {
	model: Model,
	state: State,
	scale: number, -- speed relative to the main bar
	activeAt: number, -- server time from which it can hit
}

local UPDATE_INTERVAL = 0.25 -- how often the speed target is refreshed
local SPEED_RAMP = 0.5 -- seconds to blend into a new speed target
local START_RAMP = 1.5 -- spin-up after GO!
local IDLE_SPEED = 0.35 -- lazy spin during the results screen
local SECOND_BAR_INTENSITY = 2.2
local SECOND_BAR_SCALE = 0.8
local SECOND_BAR_MIN_ELAPSED = 2
local REVERSE_INTENSITY = 3
local HIT_POWER = 140
local HIT_STUN = 0.9
local HIT_COOLDOWN = 1
local OUTWARD_SHARE = 0.65 -- knockback = tangent (bar travel) + this much outward
local MAX_LAG = 0.2 -- lag compensation cap (seconds)
local SUBSTEP = 0.07 -- radians per swept sub-check

-- Bar speed (rad/s) for a given intensity: 1.0 at the start, +0.75 per intensity point, forever.
local function speedFor(intensity: number): number
	return math.max(0.5, 1 + 0.75 * (intensity - 1))
end

local function wrap(a: number): number
	return a % (2 * math.pi)
end

-- Feet height above the floor the humanoid stands on (works for R15/R6 and scaled characters).
local function standHeight(humanoid: Humanoid, root: BasePart, character: Model): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2 * character:GetScale()
end

local definition = {
	id = "Spin",
	displayName = "SPIN",
	rules = "Jump over the spinning bar! Stay on your pillar!",
	keys = { "Jump", "Dash" },
	kind = "survival",
	soloCapable = true,
}

function definition.create(ctx)
	local center: CFrame = ctx.center
	local map = Arena.build(center)
	local rng = Random.new()
	local running = false
	local bars: { Bar } = {}
	local lastHit: { [Player]: number } = {}
	local lastFrame = workspace:GetServerTimeNow()
	local hits = 0
	local reversals = 0
	local nextReverseAt = math.huge
	local level = 1

	-- Bars --------------------------------------------------------------------------------------------

	local function publish(bar: Bar)
		bar.model:SetAttribute("State", BarMath.encode(bar.state))
	end

	-- Starts a new segment at the bar's current angle/speed (continuous motion, no snapping).
	local function reanchor(bar: Bar, now: number, target: number, ramp: number, reverseAt: number?)
		local s = bar.state
		local angle = BarMath.angle(s, now)
		local velocity = BarMath.velocity(s, now)
		local dir = if math.abs(velocity) > 1e-3 then (if velocity > 0 then 1 else -1) else s.dir
		bar.state = {
			a0 = wrap(angle),
			t0 = math.max(now, s.t0),
			w0 = math.abs(velocity),
			w1 = target,
			ramp = ramp,
			dir = dir,
			rt = reverseAt or 0,
		}
		publish(bar)
	end

	local function addBar(name: string, angle: number, color: Color3, scale: number, dir: number, delay: number): Bar
		local now = workspace:GetServerTimeNow()
		local model = Arena.addBar(map, name, angle, color, delay > 0)
		if delay > 0 then
			model:SetAttribute("AppearAt", now)
		end
		local bar: Bar = {
			model = model,
			state = { a0 = angle, t0 = now + delay, w0 = 0, w1 = 0, ramp = 0, dir = dir, rt = 0 },
			scale = scale,
			activeAt = now + delay,
		}
		table.insert(bars, bar)
		map:SetAttribute("BarCount", #bars)
		publish(bar)
		return bar
	end

	-- The main bar exists from the start (resting between two pillars during the intro).
	local main: Bar = {
		model = (map:FindFirstChild("Bars") :: Folder):FindFirstChild("Bar1") :: Model,
		state = { a0 = BarMath.START_ANGLE, t0 = 0, w0 = 0, w1 = 0, ramp = 0, dir = 1, rt = 0 },
		scale = 1,
		activeAt = 0,
	}
	table.insert(bars, main)
	publish(main)

	local function spawnSecondBar(now: number)
		local angle = BarMath.angle(main.state, now) + math.pi / 2
		local bar = addBar("Bar2", angle, Arena.BAR_COLORS[2], SECOND_BAR_SCALE, -main.state.dir, BarMath.APPEAR_TIME)
		local target = speedFor(ctx.intensity()) * SECOND_BAR_SCALE
		bar.state.w1 = target
		bar.state.ramp = START_RAMP
		publish(bar)
		ctx.announce("DOUBLE TROUBLE!", "A second bar joins, spinning the other way!", Theme.Colors.Cyan)
	end

	local function scheduleReversal(now: number, intensity: number)
		local candidates = {}
		for _, bar in bars do
			if now >= bar.activeAt + START_RAMP and not BarMath.turning(bar.state, now) then
				table.insert(candidates, bar)
			end
		end
		if #candidates == 0 then
			return
		end
		local bar = candidates[rng:NextInteger(1, #candidates)]
		local speed = math.abs(BarMath.velocity(bar.state, now))
		-- Freeze the speed until the turn is done so every client predicts the same flip.
		reanchor(bar, now, speed, 0, now + BarMath.TELEGRAPH)
		reversals += 1
		if reversals == 1 then
			ctx.announce("REVERSE!", "Watch the flash: bars can switch direction now!", Theme.Colors.Yellow)
		end
		local gap = rng:NextNumber(4.5, 8) / (1 + 0.15 * (intensity - REVERSE_INTENSITY))
		nextReverseAt = now + math.max(gap, 2.5)
	end

	-- Speed / escalation loop (4x per second).
	local function updateSpeeds()
		local now = workspace:GetServerTimeNow()
		local intensity = ctx.intensity()
		local target = speedFor(intensity)
		for _, bar in bars do
			-- Leave a bar alone while it spins up or turns around (clients predict those segments).
			if now >= bar.activeAt + START_RAMP and not BarMath.turning(bar.state, now) then
				reanchor(bar, now, target * bar.scale, SPEED_RAMP)
			end
		end
		map:SetAttribute("BarSpeed", math.round(target * 1000) / 1000)

		-- (never in the first seconds, so its banner does not collide with GO!)
		if #bars < 2 and intensity > SECOND_BAR_INTENSITY and ctx.elapsed() >= SECOND_BAR_MIN_ELAPSED then
			spawnSecondBar(now)
		end
		if intensity >= REVERSE_INTENSITY then
			if nextReverseAt == math.huge then
				nextReverseAt = now + rng:NextNumber(1.5, 3)
			elseif now >= nextReverseAt then
				scheduleReversal(now, intensity)
			end
		end
		local newLevel = math.floor(intensity)
		if newLevel > level then
			level = newLevel
			ctx.feed(("The bar speeds up! Level %d"):format(level))
		end
	end

	-- Hits ----------------------------------------------------------------------------------------------

	local function knock(player: Player, playerAngle: number, velocity: number)
		local sign = if velocity >= 0 then 1 else -1
		local tangent = Vector3.new(-math.sin(playerAngle), 0, -math.cos(playerAngle)) * sign
		local outward = Vector3.new(math.cos(playerAngle), 0, -math.sin(playerAngle))
		local direction = center:VectorToWorldSpace(tangent + outward * OUTWARD_SHARE)
		hits += 1
		map:SetAttribute("Hits", hits)
		ctx.knockback(player, direction, HIT_POWER, HIT_STUN)
	end

	local function checkPlayer(player: Player, now: number, prev: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
			return
		end
		if root.Anchored or now - (lastHit[player] or -math.huge) < HIT_COOLDOWN then
			return
		end
		local localPos = center:PointToObjectSpace(root.Position)
		local radius = Vector2.new(localPos.X, localPos.Z).Magnitude
		if radius > BarMath.BAR_HALF_LEN + 2 then
			return
		end
		local height = localPos.Y - standHeight(humanoid, root, character)
		local playerAngle = BarMath.positionAngle(localPos)
		local halfWidth = Hit.HALF_WIDTH * math.max(character:GetScale(), 0.5)

		-- Lag compensation: the position we see left the client ~half a ping ago, when its bar was there.
		local okPing, ping = pcall(player.GetNetworkPing, player)
		local lag = if okPing and type(ping) == "number" then math.clamp(ping * 0.5, 0, MAX_LAG) else 0
		local t1, t0 = now - lag, prev - lag

		for _, bar in bars do
			if t1 >= bar.activeAt then
				local s = bar.state
				local a0 = BarMath.angle(s, math.max(t0, bar.activeAt))
				local a1 = BarMath.angle(s, t1)
				local velocity = BarMath.velocity(s, t1)
				-- Sweep the arc travelled since the last frame so a fast bar cannot skip a player.
				local steps = math.clamp(math.ceil(math.abs(a1 - a0) / SUBSTEP), 1, 8)
				for k = 1, steps do
					local a = a0 + (a1 - a0) * k / steps
					if Hit.check(a, playerAngle, height, velocity, radius, halfWidth) then
						lastHit[player] = now
						knock(player, playerAngle, velocity)
						return
					end
				end
			end
		end
	end

	local function step()
		local now = workspace:GetServerTimeNow()
		local prev = lastFrame
		lastFrame = now
		if not running then
			return
		end
		for _, player in ctx.players() do
			checkPlayer(player, now, prev)
		end
	end

	-- Session ---------------------------------------------------------------------------------------------

	local session = { map = map }

	function session.start(_self)
		running = true
		local now = workspace:GetServerTimeNow()
		lastFrame = now
		local target = speedFor(ctx.intensity())
		main.state = {
			a0 = BarMath.START_ANGLE,
			t0 = now,
			w0 = 0,
			w1 = target,
			ramp = START_RAMP,
			dir = if rng:NextNumber() < 0.5 then 1 else -1,
			rt = 0,
		}
		main.activeAt = now
		publish(main)
		map:SetAttribute("BarSpeed", math.round(target * 1000) / 1000)

		ctx.trove:connect(RunService.Heartbeat, step)
		ctx.trove:add(task.spawn(function()
			while running do
				task.wait(UPDATE_INTERVAL)
				if running then
					updateSpeeds()
				end
			end
		end))
	end

	function session.stop(_self)
		if not running then
			return
		end
		running = false
		-- Wind every bar down to a lazy idle spin for the results screen.
		local now = workspace:GetServerTimeNow()
		for _, bar in bars do
			if bar.model.Parent then
				reanchor(bar, now, IDLE_SPEED * bar.scale, START_RAMP)
			end
		end
		map:SetAttribute("BarSpeed", IDLE_SPEED)
	end

	ctx.trove:connect(Players.PlayerRemoving, function(player: Player)
		lastHit[player] = nil
	end)

	return session
end

return definition
