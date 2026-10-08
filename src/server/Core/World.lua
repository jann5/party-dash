--[[
Party Dash Core: the world backdrop (docs/v2/ART_BIBLE.md section 5). Blocky islands IN one cartoon sea:
	* the sea: a 3 x 3 grid of non-collidable Art.water parts (2048 studs each, top at Config.SEA_LEVEL) centred
	  between the lobby and the arena. Nobody can swim: a fall is a splash, then the kill plane under the water.
	* 10 distant voxel islands (3 large terraced, 4 medium, 3 sand islets) and 6 sea rocks;
	* 14 blocky clouds (the World client drifts them) and 2 voxel hot-air balloons.
Everything here is decoration (no collisions, queries or touches) and nothing stands in the 70-stud corridor
between the lobby and the arena, so the arena is always visible from the PLAY pad. Built once at boot.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local World = {}

local C = Theme.Colors
local W = Theme.World

World.SEA_LEVEL = Config.SEA_LEVEL
-- Middle of the lobby -> arena line: the sea grid, islands and clouds are laid out around it.
World.CENTER = Vector3.new(
	(Config.LOBBY_CENTER.X + Config.ARENA_CENTER.X) / 2,
	Config.SEA_LEVEL,
	(Config.LOBBY_CENTER.Z + Config.ARENA_CENTER.Z) / 2
)

local SEA_TILE = 2048
local SAND = Color3.fromRGB(226, 186, 100) -- same saturated sand as the lobby beach

-- Islands: world X/Z, footprint, terrace tops (studs above the water), trees on top, palms on the beach.
-- Every one is 260-700 studs from World.CENTER and well clear of the lobby (radius 96) and the arena.
local ISLANDS = {
	{ x = -330, z = -540, w = 108, d = 88, tops = { 10, 18, 26 }, trees = 4, palms = 2 },
	{ x = 400, z = 110, w = 96, d = 120, tops = { 8, 16, 24 }, trees = 5, palms = 2 },
	{ x = -440, z = 70, w = 124, d = 96, tops = { 10, 20 }, trees = 3, palms = 2 },
	{ x = 290, z = -420, w = 60, d = 48, tops = { 8, 14 }, trees = 2, palms = 1 },
	{ x = -290, z = -160, w = 52, d = 64, tops = { 9 }, trees = 2, palms = 1 },
	{ x = 200, z = 330, w = 56, d = 44, tops = { 6, 12 }, trees = 1, palms = 1 },
	{ x = 310, z = -130, w = 44, d = 56, tops = { 8 }, trees = 1, palms = 1 },
	{ x = -170, z = 270, w = 30, d = 24, islet = true, palms = 2 },
	{ x = 160, z = -640, w = 26, d = 34, islet = true, palms = 1 },
	{ x = -260, z = -410, w = 22, d = 28, islet = true, palms = 1 },
}
local ROCKS = { { -120, -430 }, { 140, -280 }, { -90, -120 }, { 110, 90 }, { -360, -60 }, { 330, -480 } }
local BALLOONS = {
	{ pos = Vector3.new(-150, 88, -110), colors = { C.Red, C.Yellow } },
	{ pos = Vector3.new(190, 104, 70), colors = { C.Blue, C.Cyan } },
}

local function removeDefaults()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	-- Loose spawn pads would float in the sky; the lobby carries its own SpawnLocation.
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
end

local function buildSea(parent: Instance)
	local sea = Instance.new("Folder")
	sea.Name = "Sea"
	sea.Parent = parent
	for gx = -1, 1 do
		for gz = -1, 1 do
			local top = World.CENTER + Vector3.new(gx * SEA_TILE, 0, gz * SEA_TILE)
			Art.water(sea, top, Vector2.new(SEA_TILE, SEA_TILE))
		end
	end
end

-- One terrace: grass top, green lip (its top 0.05 under the grass) and a brick cliff down to `foot`.
local function terrace(parent: Instance, cx: number, cz: number, w: number, d: number, top: number, foot: number, cliff: string)
	local y = World.SEA_LEVEL + top
	Art.block(parent, "GrassTop", Vector3.new(w, 1, d), CFrame.new(cx, y - 0.5, cz), "grass_top")
	Art.block(parent, "GrassLip", Vector3.new(w + 0.6, 1.45, d + 0.6), CFrame.new(cx, y - 0.775, cz), "grass_lip")
	local bottom = World.SEA_LEVEL + foot
	local h = (y - 1.5) - bottom
	Art.block(parent, "Cliff", Vector3.new(w, h, d), CFrame.new(cx, bottom + h / 2, cz), cliff)
end

-- A random ground point inside a w x d footprint, `margin` studs from its edges.
local function spot(rng: Random, cx: number, cz: number, w: number, d: number, margin: number): (number, number)
	local hx, hz = math.max(0, w / 2 - margin), math.max(0, d / 2 - margin)
	return cx + rng:NextNumber(-hx, hx), cz + rng:NextNumber(-hz, hz)
end

-- Voxel island: sand beach ring with foam, then stepped grass terraces (each smaller and nudged off-centre),
-- block trees on the top terrace and palms on the beach.
local function island(parent: Instance, spec, rng: Random)
	local m = Instance.new("Model")
	m.Name = if spec.islet then "Islet" else "Island"
	m.Parent = parent
	local beachW, beachD = spec.w + (if spec.islet then 0 else 14), spec.d + (if spec.islet then 0 else 14)
	local beachTop = World.SEA_LEVEL + (if spec.islet then 2.5 else 1.5)
	Art.block(
		m,
		"Beach",
		Vector3.new(beachW, beachTop - World.SEA_LEVEL + 4, beachD),
		CFrame.new(spec.x, (beachTop + World.SEA_LEVEL - 4) / 2, spec.z),
		"sand",
		{ color = SAND }
	)
	Art.foam(m, Vector3.new(spec.x, 0, spec.z), beachW, beachD, World.SEA_LEVEL)

	local cx, cz, w, d = spec.x, spec.z, spec.w, spec.d
	if spec.islet then
		-- a little dune and an umbrella
		local dx, dz = spot(rng, cx, cz, w, d, 7)
		Art.block(m, "Dune", Vector3.new(8, 1.2, 6), CFrame.new(dx, beachTop + 0.6, dz), "sand", { color = SAND })
		local ux, uz = spot(rng, cx, cz, w, d, 5)
		Art.block(m, "UmbrellaPole", Vector3.new(0.5, 7, 0.5), CFrame.new(ux, beachTop + 3.5, uz), "plain", {
			color = C.White,
		})
		Art.block(m, "UmbrellaTop", Vector3.new(8, 0.7, 8), CFrame.new(ux, beachTop + 7, uz), "awning")
	else
		local foot = -2
		for i, top in spec.tops do
			terrace(m, cx, cz, w, d, top, foot, if i == 1 then "dirt_cliff_low" else "dirt_cliff")
			foot = top - 2
			if i < #spec.tops then
				-- the next terrace is ~30% smaller, nudged toward a random side (snapped to the 2-stud grid)
				local nw, nd = math.floor(w * 0.68 / 2) * 2, math.floor(d * 0.68 / 2) * 2
				cx += math.floor(rng:NextNumber(-(w - nw) / 2 + 4, (w - nw) / 2 - 4) / 2) * 2
				cz += math.floor(rng:NextNumber(-(d - nd) / 2 + 4, (d - nd) / 2 - 4) / 2) * 2
				w, d = nw, nd
			end
		end
		local topY = World.SEA_LEVEL + spec.tops[#spec.tops]
		for _ = 1, spec.trees do
			local tx, tz = spot(rng, cx, cz, w, d, 6)
			Art.tree(m, Vector3.new(tx, topY, tz), rng:NextNumber(1.3, 1.8), rng)
		end
	end
	-- palms on the beach ring (outside the first terrace)
	for i = 1, spec.palms do
		local side = if i % 2 == 1 then 1 else -1
		local px = spec.x + side * (spec.w / 2 + (if spec.islet then -6 else 3))
		local pz = spec.z + rng:NextNumber(-spec.d / 3, spec.d / 3)
		Art.palm(m, Vector3.new(px, beachTop, pz), rng:NextNumber(1.4, 1.8), rng)
	end
end

-- Voxel hot-air balloon: stacked rings in two alternating colours, ropes and a wooden basket.
local function balloon(parent: Instance, pos: Vector3, colors: { Color3 })
	local m = Instance.new("Model")
	m.Name = "HotAirBalloon"
	m.Parent = parent
	local layers = { { 6, 2 }, { 12, 3 }, { 16, 4 }, { 18, 6 }, { 16, 4 }, { 12, 3 }, { 6, 2 } }
	local y = pos.Y
	for i, layer in layers do
		local size, h = layer[1], layer[2]
		Art.block(m, "Envelope", Vector3.new(size, h, size), CFrame.new(pos.X, y + h / 2, pos.Z), "plain", {
			color = colors[(i - 1) % #colors + 1],
		})
		y += h
	end
	local basketTop = pos.Y - 8
	Art.block(m, "Basket", Vector3.new(5, 4, 5), CFrame.new(pos.X, basketTop - 2, pos.Z), "wood", { u = 4, v = 4 })
	for _, corner in { Vector2.new(2, 2), Vector2.new(-2, 2), Vector2.new(2, -2), Vector2.new(-2, -2) } do
		local a = Vector3.new(pos.X + corner.X, basketTop, pos.Z + corner.Y)
		local b = Vector3.new(pos.X + corner.X * 1.4, pos.Y, pos.Z + corner.Y * 1.4)
		Art.block(
			m,
			"Rope",
			Vector3.new(0.25, 0.25, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b),
			"plain",
			{ color = W.WoodDark }
		)
	end
end

-- Pure decoration: nobody collides with, raycasts against or touches the backdrop.
local function decorative(folder: Instance)
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

function World.init()
	local terrain = workspace.Terrain
	terrain:Clear() -- no terrain water, no leftover terrain
	-- The (now empty) Terrain still reports a 2044 x 252 x 2044 BasePart box at the origin; hide it so scene
	-- exports (tools/scene_export.luau) and any part-based tooling don't draw it over the sea.
	pcall(function()
		terrain.Transparency = 1
	end)
	removeDefaults()

	local backdrop = Instance.new("Folder")
	backdrop.Name = "Backdrop"
	local rng = Random.new(20261007)

	buildSea(backdrop)
	local islands = Instance.new("Folder")
	islands.Name = "Islands"
	islands.Parent = backdrop
	for _, spec in ISLANDS do
		island(islands, spec, rng)
	end
	for _, r in ROCKS do
		Art.rock(islands, Vector3.new(r[1], World.SEA_LEVEL, r[2]), rng:NextNumber(1.1, 1.6), rng)
	end

	-- Clouds: evenly spread around the centre (with jitter), high above the water.
	local clouds = Instance.new("Folder")
	clouds.Name = "Clouds"
	clouds.Parent = backdrop
	local count = 14
	for i = 1, count do
		local a = (i + rng:NextNumber(-0.3, 0.3)) * 2 * math.pi / count
		local dist = rng:NextNumber(380, 860)
		local pos = World.CENTER
			+ Vector3.new(math.cos(a) * dist, rng:NextNumber(110, 190), math.sin(a) * dist)
		Art.cloud(clouds, pos, rng:NextNumber(1.5, 2.4), rng)
	end
	for _, b in BALLOONS do
		balloon(backdrop, Vector3.new(b.pos.X, World.SEA_LEVEL + b.pos.Y, b.pos.Z), b.colors)
	end

	decorative(backdrop)
	backdrop.Parent = workspace
end

return World
