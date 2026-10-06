--[[
Party Dash: _Sandbox, a tiny survival minigame used to test Core's round loop (hidden from the roulette).
A round candy platform; colorful balls drop from the sky (a warning ring shows where), faster and faster
with ctx.intensity(). A ball that touches you knocks you back. Last one on the platform wins.
Also a reference for minigame authors: no module-level mutable state, everything relative to ctx.center.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local RADIUS = 40
local DROP_HEIGHT = 45
local WARNING_TIME = 0.75
local BALL_LIFETIME = 7
local MAX_BALLS = 40
local HIT_COOLDOWN = 0.6

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Vertical cylinder with its top face at `top`.
local function disc(parent: Instance, name: string, top: Vector3, height: number, radius: number, color: Color3): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
	})
end

local function buildMap(center: CFrame): Model
	local map = Instance.new("Model")
	map.Name = "SandboxArena"
	local o = center.Position
	local C = Theme.Colors

	-- Target-style candy platform: white rim, then colored rings (each a hair higher to avoid z-fighting).
	disc(map, "Platform", o, 3, RADIUS, C.White)
	disc(map, "Ring1", o + Vector3.new(0, 0.02, 0), 0.5, RADIUS - 3, C.Cyan)
	disc(map, "Ring2", o + Vector3.new(0, 0.04, 0), 0.5, RADIUS - 13, C.Pink)
	disc(map, "Ring3", o + Vector3.new(0, 0.06, 0), 0.5, RADIUS - 23, C.Yellow)
	disc(map, "Bullseye", o + Vector3.new(0, 0.08, 0), 0.5, 6, C.Purple)
	-- Layered underside.
	disc(map, "Under1", o - Vector3.new(0, 3, 0), 5, RADIUS - 4, C.Purple)
	disc(map, "Under2", o - Vector3.new(0, 8, 0), 5, RADIUS - 14, C.Blue)
	disc(map, "Under3", o - Vector3.new(0, 13, 0), 5, RADIUS - 26, C.Cyan)
	-- Rim bumpers (decorative).
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local bead = part(map, {
			Name = "Bead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.2,
			CFrame = CFrame.new(o + Vector3.new(math.cos(a) * (RADIUS - 1), 0.6, math.sin(a) * (RADIUS - 1))),
			Color = if i % 2 == 0 then C.Yellow else C.Pink,
			CanCollide = false,
		})
		bead.CanQuery = false
	end

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	for i = 1, 12 do
		local a = (i - 1) / 12 * math.pi * 2
		local pos = o + Vector3.new(math.cos(a) * 16, 0.5, math.sin(a) * 16)
		part(spawns, {
			Name = ("Spawn%02d"):format(i),
			Size = Vector3.new(4, 1, 4),
			CFrame = CFrame.lookAt(pos, Vector3.new(o.X, pos.Y, o.Z)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end
	spawns.Parent = map

	local hazards = Instance.new("Folder")
	hazards.Name = "Hazards"
	hazards.Parent = map
	return map
end

local definition = {
	id = "_Sandbox",
	displayName = "BALL DROP",
	rules = "Dodge the falling balls and stay on the platform!",
	keys = { "Jump", "Dash", "Slide" },
	kind = "survival",
	soloCapable = true,
}

function definition.create(ctx)
	local map = buildMap(ctx.center)
	local hazards = map:FindFirstChild("Hazards") :: Folder
	local origin = ctx.center.Position
	local rng = Random.new()
	local running = false
	local balls: { [BasePart]: { [Player]: number } } = {} -- ball -> last hit time per player
	local ballCount = 0

	local function randomTarget(): Vector3
		local alive = ctx.players()
		-- Aim a growing share of the balls at players so nobody can just stand still.
		local aimShare = math.clamp(0.15 * ctx.intensity(), 0, 0.5)
		if #alive > 0 and rng:NextNumber() < aimShare then
			local p = alive[rng:NextInteger(1, #alive)]
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local jitter = Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4))
				local flat = Vector3.new(root.Position.X, origin.Y, root.Position.Z) + jitter
				if (flat - origin).Magnitude < RADIUS - 2 then
					return flat
				end
			end
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local d = math.sqrt(rng:NextNumber()) * (RADIUS - 3)
		return origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
	end

	local function dropBall()
		if ballCount >= MAX_BALLS then
			return
		end
		local target = randomTarget()
		local size = rng:NextNumber(4.5, 7.5)
		local color = Theme.MapPalette[rng:NextInteger(1, #Theme.MapPalette)]

		-- Telegraph: a flat ring that grows where the ball will land.
		local ring = part(hazards, {
			Name = "Warning",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 1, 1),
			CFrame = CFrame.new(target + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		TweenService:Create(ring, TweenInfo.new(WARNING_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, size + 2, size + 2),
		}):Play()

		task.delay(WARNING_TIME, function()
			if not running or not hazards.Parent then
				ring:Destroy()
				return
			end
			local ball = Instance.new("Part")
			ball.Name = "Ball"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.one * size
			ball.Color = color
			ball.Material = Enum.Material.SmoothPlastic
			ball.CFrame = CFrame.new(target + Vector3.new(0, DROP_HEIGHT, 0))
			ball.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0.55, 1, 1)
			ball.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-8, 8), -70, rng:NextNumber(-8, 8))
			ball.Parent = hazards
			ball:SetNetworkOwner(nil)
			balls[ball] = {}
			ballCount += 1
			task.delay(0.45, function()
				ring:Destroy()
			end)
			task.delay(BALL_LIFETIME, function()
				if ball.Parent then
					TweenService:Create(ball, TweenInfo.new(0.3), { Size = Vector3.one * 0.2 }):Play()
					task.wait(0.3)
				end
				ball:Destroy()
				if balls[ball] then
					balls[ball] = nil
					ballCount -= 1
				end
			end)
		end)
	end

	-- Hit detection by distance (robust regardless of network ownership).
	local function checkHits()
		local now = os.clock()
		local power = math.min(85 + 15 * (ctx.intensity() - 1), 170)
		for ball, hits in balls do
			if ball.Parent then
				local reach = ball.Size.X / 2 + 2
				for _, p in ctx.players() do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if
						root
						and (root.Position - ball.Position).Magnitude <= reach
						and now - (hits[p] or 0) > HIT_COOLDOWN
					then
						hits[p] = now
						local away = root.Position - ball.Position
						local flat = Vector3.new(away.X, 0, away.Z)
						if flat.Magnitude < 0.2 then
							local v = ball.AssemblyLinearVelocity
							flat = Vector3.new(v.X, 0, v.Z)
						end
						if flat.Magnitude < 0.2 then
							flat = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
						end
						ctx.knockback(p, flat.Unit + Vector3.new(0, 0.15, 0), power, 0.6)
					end
				end
			end
		end
	end

	local session = { map = map }

	function session.start(_self)
		running = true
		ctx.trove:connect(RunService.Heartbeat, checkHits)
		ctx.trove:add(task.spawn(function()
			task.wait(1.5) -- a moment to breathe after GO!
			while running do
				dropBall()
				local rate = 0.8 * ctx.intensity() -- balls per second, grows forever
				task.wait(1 / math.max(rate, 0.1))
			end
		end))
	end

	function session.stop(_self)
		running = false
	end

	-- Unused in this tiny minigame, but shows that ctx.trove also owns player-related connections.
	ctx.trove:connect(Players.PlayerRemoving, function(p: Player)
		for _, hits in balls do
			hits[p] = nil
		end
	end)

	return session
end

return definition
