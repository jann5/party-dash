--[[
Party Dash: _Sandbox, a tiny survival minigame used to test Core's round loop (hidden from the vote).
A square checker court over a stone cliff in the sea; colorful balls drop from the sky (a warning disc shows where),
faster and faster with ctx.intensity(). A ball that touches you knocks you back. Last one on the court wins.
Also a reference for minigame authors: no module-level mutable state, everything relative to ctx.center, the map is
built with Shared.Art, and it tolerates revived players (no per-player state that assumes "once out, always out").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local HALF = 32 -- the court is 64 x 64 studs
local DROP_HEIGHT = 45
local WARNING_TIME = 0.75
local BALL_LIFETIME = 7
local MAX_BALLS = 40
local HIT_COOLDOWN = 0.6

local FLOOR = Color3.fromRGB(226, 104, 52) -- warm coral: reads against both the sea and the sky
local CORNER_COLORS = { Theme.Colors.Red, Theme.Colors.Blue, Theme.Colors.Green, Theme.Colors.Yellow }

local function decor(parent: Instance, name: string, size: Vector3, cf: CFrame, recipe: string)
	return Art.block(parent, name, size, cf, recipe, {
		collide = false,
		canQuery = false,
		canTouch = false,
		castShadow = false,
	})
end

local function buildMap(center: CFrame): Model
	local map = Instance.new("Model")
	map.Name = "SandboxArena"
	local o = center.Position

	-- Court + a stone cliff down into the sea (non-collidable below the floor: no ledge to stand on).
	local floor = Art.block(
		map,
		"Floor",
		Vector3.new(HALF * 2, 2, HALF * 2),
		CFrame.new(o - Vector3.new(0, 1, 0)),
		"checker_pad",
		{ color = FLOOR }
	)
	Art.cliffUnder(map, floor, o.Y - Config.SEA_DROP, "stone")

	-- Hazard stripes flush on the rim (decoration only, so nobody trips on them).
	local rimY = o.Y + 0.06
	local long = HALF * 2
	decor(map, "RimN", Vector3.new(long, 0.1, 2), CFrame.new(o.X, rimY, o.Z + HALF - 1), "hazard_trim")
	decor(map, "RimS", Vector3.new(long, 0.1, 2), CFrame.new(o.X, rimY, o.Z - HALF + 1), "hazard_trim")
	decor(map, "RimE", Vector3.new(2, 0.1, long - 4), CFrame.new(o.X + HALF - 1, rimY, o.Z), "hazard_trim")
	decor(map, "RimW", Vector3.new(2, 0.1, long - 4), CFrame.new(o.X - HALF + 1, rimY, o.Z), "hazard_trim")

	-- Four toy blocks in the corners: something to hop on while dodging.
	for i, corner in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1) } do
		local pos = o + corner * (HALF - 6) + Vector3.new(0, 2, 0)
		Art.block(map, "ToyBlock", Vector3.new(4, 4, 4), CFrame.new(pos), "toy_block", { color = CORNER_COLORS[i] })
	end

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	for i = 1, 12 do
		local a = (i - 1) / 12 * math.pi * 2
		local pos = o + Vector3.new(math.cos(a) * 16, 0.5, math.sin(a) * 16)
		local spawnPart = Instance.new("Part")
		spawnPart.Name = ("Spawn%02d"):format(i)
		spawnPart.Size = Vector3.new(4, 1, 4)
		spawnPart.CFrame = CFrame.lookAt(pos, Vector3.new(o.X, pos.Y, o.Z))
		spawnPart.Anchored = true
		spawnPart.Transparency = 1
		spawnPart.CanCollide = false
		spawnPart.CanQuery = false
		spawnPart.CanTouch = false
		spawnPart.Parent = spawns
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
	rules = "Dodge the falling balls and stay on the court!",
	keys = { "Jump", "Dash", "Slide" },
	kind = "survival",
	soloCapable = true,
	icon = "mg_random",
	color = Theme.Colors.Orange,
}

function definition.create(ctx)
	local map = buildMap(ctx.center)
	local hazards = map:FindFirstChild("Hazards") :: Folder
	local origin = ctx.center.Position
	local rng = Random.new()
	local running = false
	local balls: { [BasePart]: { [Player]: number } } = {} -- ball -> last hit time per player
	local ballCount = 0

	local function onCourt(pos: Vector3, margin: number): boolean
		return math.abs(pos.X - origin.X) <= HALF - margin and math.abs(pos.Z - origin.Z) <= HALF - margin
	end

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
				if onCourt(flat, 2) then
					return flat
				end
			end
		end
		local reach = HALF - 3
		return origin + Vector3.new(rng:NextNumber(-reach, reach), 0, rng:NextNumber(-reach, reach))
	end

	local function dropBall()
		if ballCount >= MAX_BALLS then
			return
		end
		local target = randomTarget()
		local size = rng:NextNumber(4.5, 7.5)
		local color = Theme.MapPalette[rng:NextInteger(1, #Theme.MapPalette)]

		-- Telegraph: a flat disc that grows where the ball will land.
		local ring = Instance.new("Part")
		ring.Name = "Warning"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.2, 1, 1)
		ring.CFrame = CFrame.new(target + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Color = color
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.35
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Parent = hazards
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

	-- A revived player gets a clean slate (no hit cooldowns) and lands near the middle.
	function session.onRevive(_self, player: Player): CFrame?
		for _, hits in balls do
			hits[player] = nil
		end
		local a = rng:NextNumber(0, math.pi * 2)
		local pos = origin + Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8)
		return CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z))
	end

	ctx.trove:connect(Players.PlayerRemoving, function(p: Player)
		for _, hits in balls do
			hits[p] = nil
		end
	end)

	return session
end

return definition
