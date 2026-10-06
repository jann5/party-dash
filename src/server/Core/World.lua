-- Party Dash Core: the world backdrop. A bright tropical sea far below the arena, floating islands,
-- sandy islets and fluffy clouds, so falling (and spectating) always looks cheerful.
-- Everything here is decorative: no collisions, no touches, built once at boot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Build = require(script.Parent.Build)

local World = {}

local C = Theme.Colors
World.SEA_LEVEL = Config.ARENA_CENTER.Y - 62
World.SEA_HALF_SIZE = 1024

local GRASS = Color3.fromRGB(110, 215, 95)
local GRASS_DARK = Color3.fromRGB(80, 185, 80)
local DIRT = { Color3.fromRGB(176, 112, 70), Color3.fromRGB(150, 92, 58), Color3.fromRGB(122, 74, 48) }
local SAND = Color3.fromRGB(255, 226, 150)
local TRUNK = Color3.fromRGB(140, 90, 55)

local function removeDefaults()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	-- Loose default spawn pads would float in the sky without the baseplate; Core spawns people itself.
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
end

local function buildSea()
	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(35, 200, 235)
	terrain.WaterTransparency = 0.25
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 14
	local depth = 16
	local tile = 512
	local half = World.SEA_HALF_SIZE
	local y = World.SEA_LEVEL - depth / 2
	for x = -half + tile / 2, half - tile / 2, tile do
		for z = -half + tile / 2, half - tile / 2, tile do
			local center = Vector3.new(Config.ARENA_CENTER.X + x, y, Config.ARENA_CENTER.Z + z)
			terrain:FillBlock(CFrame.new(center), Vector3.new(tile, depth, tile), Enum.Material.Water)
		end
	end
end

local function tree(parent: Instance, groundPos: Vector3, scale: number, rng: Random)
	local h = 7 * scale
	Build.pillar(parent, "Trunk", groundPos + Vector3.new(0, h / 2, 0), h, 0.7 * scale, TRUNK)
	local top = groundPos + Vector3.new(0, h, 0)
	Build.ball(parent, "Leaves", top, 6 * scale, if rng:NextNumber() < 0.5 then GRASS else GRASS_DARK)
	Build.ball(parent, "Leaves", top + Vector3.new(2 * scale, -1 * scale, 0.8 * scale), 4.5 * scale, GRASS)
	Build.ball(parent, "Leaves", top + Vector3.new(-1.8 * scale, -0.8 * scale, -1 * scale), 4.2 * scale, GRASS_DARK)
end

local function palm(parent: Instance, groundPos: Vector3, scale: number)
	local segments = 5
	local pos = groundPos
	for i = 1, segments do
		local nextPos = pos + Vector3.new(0.5 * scale, 2 * scale, 0)
		Build.part({
			Name = "Trunk",
			Size = Vector3.new(1.1 * scale, 1.1 * scale, 2.3 * scale),
			CFrame = CFrame.lookAt((pos + nextPos) / 2, nextPos),
			Color = if i % 2 == 0 then TRUNK else Color3.fromRGB(165, 112, 70),
			Parent = parent,
		})
		pos = nextPos
	end
	for i = 0, 4 do
		local angle = i * math.pi * 2 / 5
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local leafCenter = pos + dir * 2.6 * scale - Vector3.new(0, 0.6 * scale, 0)
		Build.ellipsoid(
			parent,
			"Leaf",
			CFrame.lookAt(leafCenter, leafCenter + dir) * CFrame.Angles(math.rad(-18), 0, 0),
			Vector3.new(1.6 * scale, 0.4 * scale, 5.5 * scale),
			GRASS
		)
	end
	Build.ball(parent, "Coconut", pos - Vector3.new(0, 0.6 * scale, 0), 1.1 * scale, TRUNK)
end

-- Floating island: grass top with layered dirt underneath and a few trees.
local function floatingIsland(parent: Instance, top: Vector3, radius: number, rng: Random)
	local m = Instance.new("Model")
	m.Name = "FloatingIsland"
	Build.disc(m, "Grass", top, 2.5, radius, GRASS)
	local r = radius * 0.96
	local y = top.Y - 2.5
	for i, color in DIRT do
		local h = radius * (0.32 - i * 0.04)
		Build.disc(m, "Dirt", Vector3.new(top.X, y, top.Z), h, r, color)
		y -= h
		r *= 0.68
	end
	Build.disc(m, "Tip", Vector3.new(top.X, y, top.Z), radius * 0.2, r * 0.6, DIRT[3])
	local trees = rng:NextInteger(1, 3)
	for _ = 1, trees do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, radius * 0.55)
		tree(m, top + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), rng:NextNumber(0.8, 1.4) * radius / 14, rng)
	end
	if rng:NextNumber() < 0.6 then
		local a = rng:NextNumber(0, math.pi * 2)
		local flowerPos = top + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.7
		local colors = { C.Pink, C.Yellow, C.Purple, C.Red }
		Build.ball(m, "Flower", flowerPos + Vector3.new(0, 0.6, 0), 1.6, colors[rng:NextInteger(1, #colors)])
	end
	m.Parent = parent
end

-- Sandy islet sitting on the sea with a palm tree or two.
local function islet(parent: Instance, center: Vector3, radius: number, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Islet"
	local top = Vector3.new(center.X, World.SEA_LEVEL + 2.5, center.Z)
	Build.disc(m, "Sand", top, 8, radius, SAND)
	Build.disc(m, "Shore", top - Vector3.new(0, 1.8, 0), 4, radius * 1.15, Color3.fromRGB(255, 240, 200))
	Build.disc(m, "Grass", top + Vector3.new(0, 0.6, 0), 0.8, radius * 0.55, GRASS)
	for _ = 1, rng:NextInteger(1, 2) do
		local a = rng:NextNumber(0, math.pi * 2)
		palm(m, top + Vector3.new(0, 0.6, 0) + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.3, radius / 9)
	end
	m.Parent = parent
end

local function hotAirBalloon(parent: Instance, center: Vector3, color: Color3, trim: Color3)
	local m = Instance.new("Model")
	m.Name = "HotAirBalloon"
	Build.ellipsoid(m, "Envelope", CFrame.new(center), Vector3.new(22, 26, 22), color)
	Build.ellipsoid(m, "Band", CFrame.new(center), Vector3.new(22.4, 6, 22.4), trim)
	Build.pillar(m, "Mouth", center - Vector3.new(0, 13, 0), 3, 4, trim)
	Build.part({
		Name = "Basket",
		Size = Vector3.new(6, 4, 6),
		CFrame = CFrame.new(center - Vector3.new(0, 22, 0)),
		Color = TRUNK,
		Material = Enum.Material.WoodPlanks,
		Parent = m,
	})
	for _, corner in
		{ Vector3.new(2.6, 0, 2.6), Vector3.new(-2.6, 0, 2.6), Vector3.new(2.6, 0, -2.6), Vector3.new(-2.6, 0, -2.6) }
	do
		local from = center - Vector3.new(0, 20, 0) + corner
		local to = center - Vector3.new(0, 13.5, 0) + corner * 0.9
		Build.part({
			Name = "Rope",
			Size = Vector3.new(0.2, 0.2, (to - from).Magnitude),
			CFrame = CFrame.lookAt((from + to) / 2, to),
			Color = Color3.fromRGB(90, 60, 40),
			Parent = m,
		})
	end
	m.Parent = parent
end

function World.init()
	removeDefaults()
	buildSea()

	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	local rng = Random.new(20261006)
	local center = Config.ARENA_CENTER

	-- Floating islands around the arena (most of them in the background the cameras face).
	local islands = {
		{ angle = 70, dist = 230, height = 35, radius = 22 },
		{ angle = 100, dist = 330, height = 70, radius = 30 },
		{ angle = 125, dist = 250, height = 10, radius = 16 },
		{ angle = 45, dist = 380, height = 95, radius = 34 },
		{ angle = 150, dist = 420, height = 55, radius = 26 },
		{ angle = 15, dist = 300, height = 20, radius = 18 },
		{ angle = 175, dist = 300, height = 85, radius = 20 },
		{ angle = 5, dist = 450, height = 60, radius = 28 },
		{ angle = 205, dist = 340, height = 30, radius = 22 },
		{ angle = 330, dist = 360, height = 40, radius = 24 },
	}
	for _, info in islands do
		local a = math.rad(info.angle)
		local pos = center + Vector3.new(math.cos(a) * info.dist, info.height, math.sin(a) * info.dist)
		floatingIsland(folder, pos, info.radius, rng)
	end

	-- Sandy islets on the sea.
	for i = 1, 9 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(160, 520)
		islet(folder, center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), rng:NextNumber(12, 26), rng)
		if i % 3 == 0 then
			task.wait() -- spread the build over a few frames
		end
	end

	-- Clouds: a high layer plus a soft layer between the arena and the sea (seen while falling).
	for _ = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(180, 600)
		local h = rng:NextNumber(60, 170)
		Build.cloud(folder, center + Vector3.new(math.cos(a) * d, h, math.sin(a) * d), rng:NextNumber(14, 30), rng)
	end
	for _ = 1, 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(90, 300)
		local h = rng:NextNumber(-45, -25)
		Build.cloud(folder, center + Vector3.new(math.cos(a) * d, h, math.sin(a) * d), rng:NextNumber(10, 20), rng)
	end

	hotAirBalloon(folder, center + Vector3.new(-160, 70, 210), C.Red, C.Yellow)
	hotAirBalloon(folder, center + Vector3.new(190, 105, 300), C.Cyan, C.Pink)
	hotAirBalloon(folder, center + Vector3.new(-280, 40, -60), C.Purple, C.Green)

	Build.decorative(folder)
	folder.Parent = workspace
end

return World
