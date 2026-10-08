--[[
Party Dash Core: the world backdrop (docs/v2/ART_BIBLE.md 5). One cartoon sea made of Parts, ten distant voxel
islands, sea rocks, blocky clouds and two hot-air balloons, all from Shared.Art recipes. Built once at boot.

	World.init()   -- clears Terrain, builds workspace.Sea (9 PD_Water parts) and workspace.Backdrop (decor)

The sea is a 3 x 3 grid of non-collidable Art.water tiles centred midway between the lobby and the arena (nobody can
swim: you sink through the water and Core eliminates/rescues you). Layout rules for the decor: islands sit 260-700
studs from the sea centre, never within 120 studs of the lobby or arena, outside the 60-degree view from the lobby
toward the arena, and nothing decorative enters the 70-stud corridor between the lobby and the arena.
Every Backdrop part is CanCollide / CanQuery / CanTouch false. The World client scrolls the water and drifts clouds.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local World = {}

local C = Theme.Colors
local V = Vector3.new

local SEA_Y = Config.SEA_LEVEL
local LOBBY = Config.LOBBY_CENTER
local ARENA = Config.ARENA_CENTER
local SEA_CENTER = V((LOBBY.X + ARENA.X) / 2, SEA_Y, (LOBBY.Z + ARENA.Z) / 2)
local SEA_TILE = 2048

local CORRIDOR_HALF_WIDTH = 35 -- nothing decorative within this XZ distance of the lobby -> arena segment
local LOBBY_CLEARANCE = Config.LOBBY_RADIUS + 120
local ARENA_CLEARANCE = 70 + 120 -- the biggest arena (Bomb Tag 96 x 96) reaches ~70 studs from its centre
local VIEW_HALF_ANGLE = math.rad(30) -- the arena must stay visible from the lobby

World.SEA_LEVEL = SEA_Y
World.SEA_CENTER = SEA_CENTER

-- Hand-placed islands (polar around the sea centre: angle in degrees from +X toward +Z, distance in studs).
local ISLANDS = {
	{ kind = "large", angle = 160, dist = 420, w = 112, d = 96 },
	{ kind = "large", angle = 25, dist = 480, w = 124, d = 100 },
	{ kind = "large", angle = 255, dist = 480, w = 96, d = 88 },
	{ kind = "medium", angle = 200, dist = 330, w = 60, d = 48 },
	{ kind = "medium", angle = 340, dist = 360, w = 52, d = 60 },
	{ kind = "medium", angle = 135, dist = 640, w = 68, d = 56 },
	{ kind = "medium", angle = 45, dist = 650, w = 56, d = 64 },
	{ kind = "islet", angle = 295, dist = 420, w = 32, d = 26 },
	{ kind = "islet", angle = 180, dist = 270, w = 24, d = 30 },
	{ kind = "islet", angle = 5, dist = 280, w = 30, d = 22 },
}

-- Sea rocks (offsets from the sea centre).
local ROCKS = { V(-200, 0, 110), V(230, 0, 130), V(-180, 0, -300), V(240, 0, -250), V(-340, 0, 290), V(330, 0, 330) }

local BALLOONS = {
	{ offset = V(-230, 85, -40), colors = { C.Red, C.Yellow } },
	{ offset = V(300, 100, 290), colors = { C.Purple, C.Orange } },
}

local DECOR = { collide = false, canQuery = false, canTouch = false }

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

-- True when a footprint of `radius` around p would cut into the view cone from the lobby toward the arena.
local function blocksArenaView(p: Vector3, radius: number): boolean
	local dir = flat(ARENA - LOBBY).Unit
	local rel = flat(p - LOBBY)
	local along = rel:Dot(dir)
	if along <= 0 then
		return false
	end
	return (rel - dir * along).Magnitude - radius < along * math.tan(VIEW_HALF_ANGLE)
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

-- ===== builders ======================================================================================

local function block(parent: Instance, name: string, size: Vector3, pos: Vector3, recipe: string, opts: any?)
	local o = table.clone(DECOR)
	if opts then
		for k, v in opts do
			o[k] = v
		end
	end
	return Art.block(parent, name, size, CFrame.new(pos), recipe, o)
end

-- One grass terrace: dark cliff body, a 1.5-stud grass lip (overhang 0.3) and the textured grass top.
local function terrace(parent: Instance, center: Vector3, w: number, d: number, top: number, bottom: number, cliff: string)
	local bodyTop = top - 1.5
	block(parent, "Cliff", V(w, bodyTop - bottom, d), V(center.X, (bodyTop + bottom) / 2, center.Z), cliff)
	block(parent, "GrassLip", V(w + 0.6, 1.5, d + 0.6), V(center.X, top - 0.8, center.Z), "grass_lip")
	block(parent, "Grass", V(w, 0.4, d), V(center.X, top - 0.2, center.Z), "grass_top")
end

local function beach(parent: Instance, center: Vector3, w: number, d: number, height: number)
	block(parent, "Beach", V(w, height + 0.5, d), V(center.X, SEA_Y + (height - 0.5) / 2, center.Z), "sand")
	Art.foam(parent, center, w, d, SEA_Y)
end

-- A random spot on a w x d footprint, `margin` studs inside its edge, snapped to the 2-stud grid.
local function spotOn(center: Vector3, w: number, d: number, margin: number, y: number, rng: Random): Vector3
	local hx, hz = math.max(0, w / 2 - margin), math.max(0, d / 2 - margin)
	local x = math.floor(rng:NextNumber(-hx, hx) / 2 + 0.5) * 2
	local z = math.floor(rng:NextNumber(-hz, hz) / 2 + 0.5) * 2
	return V(center.X + x, y, center.Z + z)
end

local function umbrella(parent: Instance, ground: Vector3)
	block(parent, "UmbrellaPole", V(0.5, 8, 0.5), ground + V(0, 4, 0), "wood")
	for _, q in { { -2, -2, C.Red }, { 2, 2, C.Red }, { -2, 2, C.White }, { 2, -2, C.White } } do
		block(parent, "UmbrellaTop", V(4, 0.6, 4), ground + V(q[1], 8.2, q[2]), "plain", { color = q[3] })
	end
end

-- Large: sand beach, 2-3 stepped grass terraces (top 18-30 above the water), block trees and palms.
-- Medium: beach plus 1-2 terraces (top 8-16). Islet: a low sand bar with palms and an umbrella.
local function buildIsland(parent: Instance, spec, center: Vector3, rng: Random)
	local island = Instance.new("Model")
	island.Name = "Island"
	local w, d = spec.w, spec.d
	local beachTop = SEA_Y + 2
	if spec.kind == "islet" then
		beach(island, center, w, d, 2.5)
		for _ = 1, rng:NextInteger(1, 2) do
			Art.palm(island, spotOn(center, w, d, 6, SEA_Y + 2.5, rng), rng:NextNumber(1.1, 1.4), rng)
		end
		umbrella(island, spotOn(center, w, d, 6, SEA_Y + 2.5, rng))
		island.Parent = parent
		return
	end

	local large = spec.kind == "large"
	beach(island, center, w, d, 2)
	local heights = if large then { 11, 20, 28 } else { rng:NextInteger(4, 6) * 2, 16 }
	local tierCount = if large then rng:NextInteger(2, 3) else rng:NextInteger(1, 2)
	local ring = if large then 6 else 4 -- width of the beach ring around the first terrace
	local shrinkX, shrinkZ = if large then 22 else 16, if large then 20 else 14

	local tier = { center = center, w = w - 2 * ring, d = d - 2 * ring, top = beachTop }
	local bottom = beachTop - 1
	for i = 1, tierCount do
		local top = SEA_Y + heights[i]
		local cliff = if i == 1 then "dirt_cliff_low" else "dirt_cliff"
		terrace(island, tier.center, tier.w, tier.d, top, bottom, cliff)
		if i == 1 and large then
			-- a lower outcrop on the beach ring breaks the rectangle into a voxel silhouette
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local oc = tier.center + V(side * (tier.w / 2 + 1), 0, rng:NextInteger(-2, 2) * 4)
			terrace(island, oc, 6, math.min(24, tier.d - 8), top - 4, bottom, cliff)
		end
		tier.top = top
		local nextW, nextD = tier.w - shrinkX, tier.d - shrinkZ
		if i == tierCount or nextW < 12 or nextD < 12 then
			break
		end
		bottom = top - 1.6
		tier = {
			center = tier.center + V(rng:NextInteger(-2, 2) * 2, 0, rng:NextInteger(-2, 2) * 2),
			w = nextW,
			d = nextD,
			top = top,
		}
	end

	-- block trees on the top terrace, palms on the north/south beach ring
	local trees = if large then rng:NextInteger(3, 5) else rng:NextInteger(1, 2)
	for _ = 1, trees do
		Art.tree(island, spotOn(tier.center, tier.w, tier.d, 6, tier.top, rng), rng:NextNumber(1, 1.4), rng)
	end
	local palms = if large then 2 else 1
	for k = 1, palms do
		local side = if k == 1 then -1 else 1
		local x = center.X + rng:NextInteger(-2, 2) * 4
		Art.palm(island, V(x, beachTop, center.Z + side * (d / 2 - ring / 2)), 1.3, rng)
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
		block(balloon, "Envelope", V(size, h, size), center + V(0, y, 0), "plain", {
			color = colors[(i - 1) % #colors + 1],
			castShadow = false,
		})
	end
	block(balloon, "Mouth", V(4, 1, 4), center + V(0, -11, 0), "plain", { color = C.InkSoft })
	for _, cx in { -1.8, 1.8 } do
		for _, cz in { -1.8, 1.8 } do
			block(balloon, "Rope", V(0.2, 7, 0.2), center + V(cx, -14.5, cz), "plain", { color = Theme.World.WoodDark })
		end
	end
	block(balloon, "Basket", V(5, 4, 5), center + V(0, -20, 0), "wood")
	balloon.Parent = parent
end

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
		local a = math.rad(spec.angle)
		local center = SEA_CENTER + V(math.cos(a), 0, math.sin(a)) * spec.dist
		center = V(math.floor(center.X / 2 + 0.5) * 2, SEA_Y, math.floor(center.Z / 2 + 0.5) * 2)
		local radius = math.sqrt(spec.w * spec.w + spec.d * spec.d) / 2
		if islandAllowed(center, radius) then
			buildIsland(islands, spec, center, rng)
		else
			warn(("[World] skipped a %s island at %s: too close to the lobby/arena view"):format(spec.kind, tostring(center)))
		end
	end
	islands.Parent = backdrop

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	for _, offset in ROCKS do
		local pos = SEA_CENTER + offset
		if corridorDistance(pos) > CORRIDOR_HALF_WIDTH + 12 then
			Art.rock(rocks, pos, rng:NextNumber(1, 1.4), rng)
		end
	end
	rocks.Parent = backdrop

	local clouds = Instance.new("Folder")
	clouds.Name = "Clouds"
	for i = 1, 14 do
		local a = math.rad((i - 1) * 360 / 14 + rng:NextNumber(-8, 8))
		local dist = rng:NextNumber(350, 900)
		local pos = SEA_CENTER + V(math.cos(a) * dist, rng:NextNumber(110, 190), math.sin(a) * dist)
		Art.cloud(clouds, pos, rng:NextNumber(1, 1.7), rng)
	end
	clouds.Parent = backdrop

	for _, spec in BALLOONS do
		buildBalloon(backdrop, SEA_CENTER + spec.offset, spec.colors)
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
