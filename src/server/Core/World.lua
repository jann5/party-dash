--[[
Party Dash Core: the world backdrop (docs/v2/ART_BIBLE.md 5). One cartoon sea made of Parts, ten distant voxel
islands, sea rocks, blocky clouds and two hot-air balloons, all from Shared.Art recipes. Built once at boot.

	World.init()   -- clears Terrain, builds workspace.Sea (9 PD_Water parts) and workspace.Backdrop (decor)

The sea is a 3 x 3 grid of 2048-stud Art.water tiles (top at Config.SEA_LEVEL) centred midway between the lobby and
the arena. It is not collidable: nobody can swim, you sink through it and Core eliminates or rescues you.
Layout rules: islands sit 260-700 studs from the sea centre, never within 120 studs of the lobby or arena edges and
outside the 60-degree view cone from the lobby toward the arena; nothing decorative enters the 70-stud corridor
between the lobby and the arena (clouds keep to bands north and south of it, so their client drift never crosses it).
Every Backdrop part is CanCollide / CanQuery / CanTouch false. The World client scrolls the water and drifts clouds.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local Lobby = require(Shared.Maps.Lobby)
local Theme = require(Shared.Theme)

local World = {}

local C = Theme.Colors
local V = Vector3.new

local SEA_Y = Config.SEA_LEVEL
local LOBBY = Config.LOBBY_CENTER
local ARENA = Config.ARENA_CENTER
local SEA_CENTER = V((LOBBY.X + ARENA.X) / 2, SEA_Y, (LOBBY.Z + ARENA.Z) / 2)
local SEA_TILE = 2048
local SAND = Lobby.Colors.Sand

local CORRIDOR_HALF_WIDTH = 35 -- nothing decorative within this XZ distance of the lobby -> arena segment
local LOBBY_CLEARANCE = Config.LOBBY_RADIUS + 120
local ARENA_CLEARANCE = 70 + 120 -- the biggest arena (Bomb Tag 96 x 96 + cliffs) reaches ~70 studs from its centre
local VIEW_HALF_ANGLE = math.rad(30) -- the arena stays framed by open sea and sky from the lobby

World.SEA_LEVEL = SEA_Y
World.SEA_CENTER = SEA_CENTER

-- Hand-placed islands (world X/Z of the centre, footprint w x d). The two front pairs frame the view from the spawn
-- toward the arena just outside the 30-degree cone; the rest ring the lobby's sides and back.
local ISLANDS = {
	{ kind = "large", x = 340, z = 60, w = 120, d = 100 },
	{ kind = "large", x = -400, z = 106, w = 112, d = 96 },
	{ kind = "large", x = -300, z = -650, w = 104, d = 92 },
	{ kind = "medium", x = 254, z = -6, w = 60, d = 50 },
	{ kind = "medium", x = -286, z = 30, w = 56, d = 62 },
	{ kind = "medium", x = 330, z = -560, w = 66, d = 54 },
	{ kind = "medium", x = 520, z = -300, w = 52, d = 60 },
	{ kind = "islet", x = 268, z = -100, w = 28, d = 24 },
	{ kind = "islet", x = -330, z = -330, w = 26, d = 32 },
	{ kind = "islet", x = 60, z = -700, w = 30, d = 24 },
}

-- Sea rocks (world X/Z), clear of the corridor and the islands.
local ROCKS = { { -150, -120 }, { 160, -200 }, { -180, -480 }, { 200, -430 }, { -440, -150 }, { 440, 160 } }

local BALLOONS = {
	{ pos = V(-150, SEA_Y + 90, -210), colors = { C.Red, C.Yellow } },
	{ pos = V(210, SEA_Y + 76, -60), colors = { C.Purple, C.Orange } },
}

local ISLAND_NAMES = { large = "LargeIsland", medium = "MediumIsland", islet = "Islet" }
local CLOUD_COUNT = 14

local built = false

-- ===== placement rules ===============================================================================

local function flat(v: Vector3): Vector3
	return V(v.X, 0, v.Z)
end

-- XZ distance from p to the lobby -> arena segment.
local function corridorDistance(p: Vector3): number
	local a, ab = flat(LOBBY), flat(ARENA - LOBBY)
	local t = math.clamp((flat(p) - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (flat(p) - (a + ab * t)).Magnitude
end

-- True when a footprint of `radius` around p cuts into the view cone from the lobby toward the arena.
local function blocksArenaView(p: Vector3, radius: number): boolean
	local dir = flat(ARENA - LOBBY).Unit
	local rel = flat(p - LOBBY)
	local along = rel:Dot(dir)
	if along <= 0 then
		return false
	end
	local angle = math.atan2((rel - dir * along).Magnitude, along)
	return angle - math.asin(math.min(1, radius / rel.Magnitude)) < VIEW_HALF_ANGLE
end

local function islandAllowed(p: Vector3, radius: number): boolean
	local fromSea = flat(p - SEA_CENTER).Magnitude
	return fromSea >= 260
		and fromSea <= 700
		and flat(p - LOBBY).Magnitude - radius >= LOBBY_CLEARANCE
		and flat(p - ARENA).Magnitude - radius >= ARENA_CLEARANCE
		and corridorDistance(p) - radius >= CORRIDOR_HALF_WIDTH
		and not blocksArenaView(p, radius)
end

-- ===== voxel island builder ==========================================================================

type Rect = { x0: number, x1: number, z0: number, z1: number }

local function snap(n: number): number
	return math.floor(n / 2 + 0.5) * 2
end

local function rect(cx: number, cz: number, w: number, d: number): Rect
	return { x0 = snap(cx - w / 2), x1 = snap(cx + w / 2), z0 = snap(cz - d / 2), z1 = snap(cz + d / 2) }
end

local function inset(r: Rect, dx: number, dz: number, shiftX: number, shiftZ: number): Rect
	return { x0 = r.x0 + dx + shiftX, x1 = r.x1 - dx + shiftX, z0 = r.z0 + dz + shiftZ, z1 = r.z1 - dz + shiftZ }
end

-- A main rect plus `n` bumps attached to random sides (strictly inside the side's span, so no coplanar faces):
-- the stair-stepped voxel silhouette of the references instead of a plain rectangle.
local function blob(main: Rect, n: number, depth: number, rng: Random): { Rect }
	local rects = { main }
	local sides = { "n", "s", "e", "w" }
	for _ = 1, n do
		local side = table.remove(sides, rng:NextInteger(1, #sides))
		local alongX = side == "n" or side == "s"
		local lo, hi = if alongX then main.x0 else main.z0, if alongX then main.x1 else main.z1
		local span = hi - lo
		local len = snap(span * rng:NextNumber(0.35, 0.6))
		local start = snap(lo + 2 + rng:NextNumber(0, math.max(0, span - len - 4)))
		local finish = math.min(start + len, hi - 2)
		local dd = snap(depth * rng:NextNumber(0.6, 1))
		if side == "n" then
			table.insert(rects, { x0 = start, x1 = finish, z0 = main.z1, z1 = main.z1 + dd })
		elseif side == "s" then
			table.insert(rects, { x0 = start, x1 = finish, z0 = main.z0 - dd, z1 = main.z0 })
		elseif side == "e" then
			table.insert(rects, { x0 = main.x1, x1 = main.x1 + dd, z0 = start, z1 = finish })
		else
			table.insert(rects, { x0 = main.x0 - dd, x1 = main.x0, z0 = start, z1 = finish })
		end
	end
	return rects
end

local function block(parent: Instance, name: string, r: Rect, y0: number, y1: number, recipe: string, opts: any?)
	local size = V(r.x1 - r.x0, y1 - y0, r.z1 - r.z0)
	local pos = V((r.x0 + r.x1) / 2, (y0 + y1) / 2, (r.z0 + r.z1) / 2)
	return Art.block(parent, name, size, CFrame.new(pos), recipe, opts)
end

local function grow(r: Rect, by: number): Rect
	return { x0 = r.x0 - by, x1 = r.x1 + by, z0 = r.z0 - by, z1 = r.z1 + by }
end

-- Sand beach slabs from just under the water to `top`, with a foam frame at the waterline.
local function beach(parent: Instance, rects: { Rect }, top: number)
	for _, r in rects do
		block(parent, "Beach", r, SEA_Y - 0.5, top, "sand", { color = SAND })
		Art.foam(parent, V((r.x0 + r.x1) / 2, SEA_Y, (r.z0 + r.z1) / 2), r.x1 - r.x0, r.z1 - r.z0, SEA_Y)
	end
end

-- One grass terrace: dark cliff body, 1.5-stud grass lip (overhang 0.3) and the textured grass top.
local function terrace(parent: Instance, rects: { Rect }, bottom: number, top: number, cliff: string)
	for _, r in rects do
		block(parent, "Cliff", r, bottom, top - 1.5, cliff)
		block(parent, "GrassLip", grow(r, 0.3), top - 1.55, top - 0.05, "grass_lip")
		block(parent, "Grass", r, top - 0.4, top, "grass_top")
	end
end

-- A random grid spot on a rect, `margin` studs inside its edge.
local function spotOn(r: Rect, margin: number, y: number, rng: Random): Vector3
	local x = snap(rng:NextNumber(r.x0 + margin, math.max(r.x0 + margin, r.x1 - margin)))
	local z = snap(rng:NextNumber(r.z0 + margin, math.max(r.z0 + margin, r.z1 - margin)))
	return V(x, y, z)
end

local function umbrella(parent: Instance, ground: Vector3)
	Art.block(parent, "UmbrellaPole", V(0.5, 8, 0.5), CFrame.new(ground + V(0, 4, 0)), "wood")
	for _, q in { { -2, -2, C.Red }, { 2, 2, C.Red }, { -2, 2, C.White }, { 2, -2, C.White } } do
		Art.block(parent, "UmbrellaTop", V(4, 0.6, 4), CFrame.new(ground + V(q[1], 8.2, q[2])), "awning", {
			color = q[3],
			u = 16,
			v = 16,
		})
	end
end

-- A spot on the beach ring along the south (side -1) or north (side 1) edge that no terrace covers.
local function beachSpot(main: Rect, covered: { Rect }, ring: number, side: number, rng: Random): Vector2?
	for _ = 1, 12 do
		local x = snap(rng:NextNumber(main.x0 + 4, main.x1 - 4))
		local z = if side < 0 then main.z0 + ring / 2 else main.z1 - ring / 2
		local free = true
		for _, r in covered do
			if x > r.x0 - 2 and x < r.x1 + 2 and z > r.z0 - 2 and z < r.z1 + 2 then
				free = false
				break
			end
		end
		if free then
			return Vector2.new(x, z)
		end
	end
	return nil
end

-- Large: blobby beach + 2-3 stepped grass terraces (top 18-30 above the water), 3-5 block trees, 2 palms.
-- Medium: beach + 1-2 terraces (top 8-16), 1-2 trees and a palm. Islet: a low sand bar, palms and an umbrella.
local function buildIsland(parent: Instance, spec, rng: Random)
	local island = Instance.new("Model")
	island.Name = ISLAND_NAMES[spec.kind]
	local main = rect(spec.x, spec.z, spec.w, spec.d)

	if spec.kind == "islet" then
		local top = SEA_Y + rng:NextNumber(2, 3)
		beach(island, blob(main, 1, 6, rng), top)
		for _ = 1, rng:NextInteger(1, 2) do
			Art.palm(island, spotOn(main, 5, top, rng), rng:NextNumber(1.1, 1.4), rng)
		end
		umbrella(island, spotOn(main, 5, top, rng))
		island.Parent = parent
		return
	end

	local large = spec.kind == "large"
	local beachTop = SEA_Y + 2
	beach(island, blob(main, if large then 3 else 2, if large then 10 else 6, rng), beachTop)

	local heights = if large then { 10, 20, 28 } else { rng:NextInteger(4, 6) * 2, 16 }
	local tiers = if large then rng:NextInteger(2, 3) else rng:NextInteger(1, 2)
	local ring = if large then 8 else 5
	local tier = inset(main, ring, ring, 0, 0)
	local bottom = beachTop - 1
	local topRect = tier
	local topY = beachTop
	local firstTier: { Rect } = {}
	for i = 1, tiers do
		local top = SEA_Y + heights[i]
		local cliff = if i == 1 then "dirt_cliff_low" else "dirt_cliff"
		local rects = blob(tier, if i < tiers then 2 else 1, if large then 4 else 3, rng)
		terrace(island, rects, bottom, top, cliff)
		if i == 1 then
			firstTier = rects
		end
		topRect, topY = tier, top
		local nextTier = inset(
			tier,
			if large then 12 else 8,
			if large then 11 else 7,
			snap(rng:NextNumber(-4, 4)),
			snap(rng:NextNumber(-4, 4))
		)
		if i == tiers or nextTier.x1 - nextTier.x0 < 14 or nextTier.z1 - nextTier.z0 < 14 then
			break
		end
		bottom = top - 1.6
		tier = nextTier
	end

	-- block trees on the top terrace, palms on the beach ring, a rock or two in the shallows
	for _ = 1, if large then rng:NextInteger(3, 5) else rng:NextInteger(1, 2) do
		Art.tree(island, spotOn(topRect, 5, topY, rng), rng:NextNumber(1, 1.4), rng)
	end
	for k = 1, if large then 2 else 1 do
		local spot = beachSpot(main, firstTier, ring, if k == 1 then -1 else 1, rng)
		if spot then
			Art.palm(island, V(spot.X, beachTop, spot.Y), 1.3, rng)
		end
	end
	if large then
		for _ = 1, 2 do
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = math.max(spec.w, spec.d) / 2 + rng:NextNumber(10, 20)
			Art.rock(
				island,
				V(spec.x + math.cos(a) * r, SEA_Y, spec.z + math.sin(a) * r),
				rng:NextNumber(0.8, 1.2),
				rng
			)
		end
	end
	island.Parent = parent
end

-- Blocky hot-air balloon: banded voxel envelope, ropes and a wood basket.
local function buildBalloon(parent: Instance, center: Vector3, colors: { Color3 })
	local balloon = Instance.new("Model")
	balloon.Name = "HotAirBalloon"
	local layers = { { -9, 8, 3 }, { -6, 14, 3 }, { -2.5, 18, 4 }, { 1.5, 18, 4 }, { 5, 14, 3 }, { 7.5, 8, 2 } }
	for i, layer in layers do
		local y, size, h = layer[1], layer[2], layer[3]
		Art.block(balloon, "Envelope", V(size, h, size), CFrame.new(center + V(0, y, 0)), "plain", {
			color = colors[(i - 1) % #colors + 1],
		})
	end
	Art.block(balloon, "Mouth", V(4, 1, 4), CFrame.new(center + V(0, -11, 0)), "plain", { color = C.InkSoft })
	for _, cx in { -1.8, 1.8 } do
		for _, cz in { -1.8, 1.8 } do
			Art.block(balloon, "Rope", V(0.2, 7, 0.2), CFrame.new(center + V(cx, -14.5, cz)), "plain", {
				color = Theme.World.WoodDark,
			})
		end
	end
	Art.block(balloon, "Basket", V(5, 4, 5), CFrame.new(center + V(0, -20, 0)), "wood")
	balloon.Parent = parent
end

-- Cloud spots: 350-900 studs from the sea centre, in two bands north and south of the lobby -> arena corridor so
-- the client-side +X drift (wrapping at +-1000) never carries a cloud over it.
local function cloudSpots(rng: Random): { Vector3 }
	local spots = {}
	local tries = 0
	while #spots < CLOUD_COUNT and tries < 1000 do
		tries += 1
		local side = if #spots % 2 == 0 then 1 else -1
		local x = rng:NextNumber(-850, 850)
		local z = side * rng:NextNumber(270, 720)
		local d = math.sqrt(x * x + z * z)
		if d >= 350 and d <= 900 then
			table.insert(spots, SEA_CENTER + V(x, rng:NextNumber(110, 190), z))
		end
	end
	return spots
end

-- ===== build =========================================================================================

local function buildSea()
	local sea = Instance.new("Folder")
	sea.Name = "Sea"
	for ix = -1, 1 do
		for iz = -1, 1 do
			Art.water(sea, SEA_CENTER + V(ix * SEA_TILE, 0, iz * SEA_TILE), Vector2.new(SEA_TILE, SEA_TILE))
		end
	end
	sea.Parent = workspace
end

local function buildBackdrop()
	local backdrop = Instance.new("Folder")
	backdrop.Name = "Backdrop"
	local rng = Random.new(20261007)

	local islands = Instance.new("Folder")
	islands.Name = "Islands"
	for _, spec in ISLANDS do
		local radius = math.sqrt(spec.w * spec.w + spec.d * spec.d) / 2 + 10 -- + the blob bumps
		if islandAllowed(V(spec.x, SEA_Y, spec.z), radius) then
			buildIsland(islands, spec, rng)
		else
			warn(
				("[World] skipped the %s island at (%d, %d): it breaks the layout rules"):format(
					spec.kind,
					spec.x,
					spec.z
				)
			)
		end
	end
	islands.Parent = backdrop

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	for _, p in ROCKS do
		Art.rock(rocks, V(p[1], SEA_Y, p[2]), rng:NextNumber(1, 1.5), rng)
	end
	rocks.Parent = backdrop

	local clouds = Instance.new("Folder")
	clouds.Name = "Clouds"
	for _, pos in cloudSpots(rng) do
		local cloud = Art.cloud(clouds, pos, rng:NextNumber(1.1, 1.7), rng)
		cloud.WorldPivot = CFrame.new(pos) -- a meaningful pivot: the client drifts clouds with PivotTo
	end
	clouds.Parent = backdrop

	for _, spec in BALLOONS do
		buildBalloon(backdrop, spec.pos, spec.colors)
	end

	-- Purely decorative: never collide, block raycasts or fire touches (Art helpers default some to true).
	for _, d in backdrop:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	backdrop.Parent = workspace
end

local function clearPlace()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	-- loose engine spawn pads would float over the sea; the lobby carries its own SpawnLocation
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") or child.Name == "Sea" or child.Name == "Backdrop" then
			child:Destroy()
		end
	end
	local terrain = workspace.Terrain
	terrain:Clear() -- no terrain water: the sea is Parts
	-- Terrain is also a BasePart; hide its (now empty) proxy box from part-based tools such as the scene exporter.
	pcall(function()
		terrain.Transparency = 1
	end)
	local terrainClouds = terrain:FindFirstChildOfClass("Clouds")
	if terrainClouds then
		terrainClouds:Destroy()
	end
end

function World.init()
	if built then
		return
	end
	built = true
	clearPlace()
	buildSea()
	buildBackdrop()
end

return World
