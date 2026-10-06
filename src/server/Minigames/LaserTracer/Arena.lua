--!strict
--[[
Laser Tracer: builds the arena Model around a center CFrame (platform top-center). Pure builder: every
call returns a fresh Model, nothing is kept at module level.

	Floor        collidable base disc + a ring of pastel tiles on top (visual, no collision)
	Rim          glowing yellow edge strip (no collision, so nothing catches a falling player)
	Hub          central pillar that fires the sweeping lasers (red ring = low beam height, cyan = high)
	Emitters     8 towers outside the platform; their "Lens" flashes while a laser is telegraphed
	Spawns       12 points in a ring
	Lasers       Folder filled at runtime (one Model per laser)
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Motion = require(script.Parent.MotionRef)

local Arena = {}

Arena.TAG = "LaserTracerMap"
Arena.EMITTER_COUNT = 8
Arena.EMITTER_RADIUS = 48
Arena.SPAWN_RADIUS = 21
Arena.HUB_HEIGHT = 13
Arena.LENS_DIM = Color3.fromRGB(70, 55, 120)
-- Floor look. The game's lighting is a bright sun (Brightness 3 + warm color shift), so pale tiles burn
-- out to white and swallow the beams. Mid-tone tiles + dark grout keep the floor colorful and let the
-- neon lasers (and their floor glow lines) pop.
Arena.GROUT = Color3.fromRGB(85, 65, 150)
Arena.TILE_SHADE = 0.22 -- odd tiles: palette color pulled this far toward Theme ink
Arena.TILE_DIM = 0.06 -- even tiles: a touch of ink so yellow/green do not clip

local RING_EDGES = { 3.4, 9, 14.5, 20, 25.5, 31, 36.5, 42 }
local TILE_LENGTH = 6.5 -- target tangential tile length
local RIM_SEGMENTS = 64

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

-- Decorative parts never collide, never get raycast-hit and never fire touches.
local function ghost(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Local floor position (angle a, radius r, height y above the floor) -> world CFrame facing outward
-- (the part's X axis points away from the center).
local function polar(center: CFrame, a: number, r: number, y: number): CFrame
	return center * CFrame.new(math.cos(a) * r, y, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
end

-- Vertical cylinder centered at local (x, y, z).
local function column(center: CFrame, x: number, y: number, z: number): CFrame
	return center * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
end

local function buildFloor(map: Model, center: CFrame): BasePart
	local floor = model(map, "Floor")
	local R = RING_EDGES[#RING_EDGES]
	local base = part(floor, {
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, R * 2, R * 2),
		CFrame = column(center, 0, -1.5, 0),
		Color = Arena.GROUT,
	})

	-- Pastel tiles: concentric rings, alternating a palette color and a deeper shade of it. Neighbours sit at
	-- slightly different heights so their overlapping inner corners never z-fight.
	local palette = Theme.MapPalette
	for k = 1, #RING_EDGES - 1 do
		local rIn, rOut = RING_EDGES[k], RING_EDGES[k + 1]
		local rMid = (rIn + rOut) / 2
		local n = math.max(6, math.ceil(2 * math.pi * rMid / TILE_LENGTH))
		n += n % 2
		local length = 2 * rMid * math.tan(math.pi / n) * 0.965
		local base = palette[(k - 1) % #palette + 1]
		local color = base:Lerp(Theme.Colors.Ink, Arena.TILE_DIM)
		local tint = base:Lerp(Theme.Colors.Ink, Arena.TILE_SHADE)
		local twist = if k % 2 == 0 then math.pi / n else 0
		for j = 0, n - 1 do
			local a = j * 2 * math.pi / n + twist
			local even = j % 2 == 0
			ghost(part(floor, {
				Name = "Tile",
				Size = Vector3.new(rOut - rIn - 0.3, 0.2, length),
				CFrame = polar(center, a, rMid, if even then -0.07 else -0.06),
				Color = if even then color else tint,
				CastShadow = false,
			}))
		end
	end

	-- Layered cartoon underside.
	local under = {
		{ R - 3, 5, -5.5, Theme.Colors.Purple },
		{ R - 13, 5, -10.5, Theme.Colors.Blue },
		{ R - 25, 5, -15.5, Theme.Colors.Cyan },
	}
	for i, u in under do
		part(floor, {
			Name = "Under" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(u[2], u[1] * 2, u[1] * 2),
			CFrame = column(center, 0, u[3], 0),
			Color = u[4],
			CanCollide = false,
			CastShadow = false,
		})
	end
	return base
end

local function buildRim(map: Model, center: CFrame)
	local rim = model(map, "Rim")
	local r = RING_EDGES[#RING_EDGES] + 0.55
	local length = 2 * math.pi * r / RIM_SEGMENTS * 1.04
	for i = 0, RIM_SEGMENTS - 1 do
		local a = i * 2 * math.pi / RIM_SEGMENTS
		ghost(part(rim, {
			Name = "Trim",
			Size = Vector3.new(1.3, 2.6, length),
			CFrame = polar(center, a, r, -1.2),
			Color = Theme.MinigameColors.LaserTracer,
			CastShadow = false,
		}))
		ghost(part(rim, {
			Name = "Glow",
			Size = Vector3.new(0.7, 0.35, length),
			CFrame = polar(center, a, r - 0.1, 0.2),
			Color = Theme.Colors.Yellow,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}))
	end
end

local function ring(parent: Instance, center: CFrame, x: number, y: number, z: number, radius: number, color: Color3)
	return ghost(part(parent, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, radius * 2, radius * 2),
		CFrame = column(center, x, y, z),
		Color = color,
		Material = Enum.Material.Neon,
		CastShadow = false,
	}))
end

local function buildHub(map: Model, center: CFrame)
	local hub = model(map, "Hub")
	local C = Theme.Colors
	local h = Arena.HUB_HEIGHT
	part(hub, {
		Name = "Column",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, 6.6, 6.6),
		CFrame = column(center, 0, h / 2, 0),
		Color = C.Panel,
	})
	-- The two beam heights, color coded like the lasers they fire.
	ring(hub, center, 0, Motion.HEIGHT.low, 0, 3.75, Motion.COLORS.low).Name = "LowRing"
	ring(hub, center, 0, Motion.HEIGHT.high, 0, 3.75, Motion.COLORS.high).Name = "HighRing"
	for _, y in { 8, 10.2 } do
		ghost(part(hub, {
			Name = "Stripe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9, 7.2, 7.2),
			CFrame = column(center, 0, y, 0),
			Color = Theme.MinigameColors.LaserTracer,
		}))
	end
	part(hub, {
		Name = "Dome",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 8,
		CFrame = center * CFrame.new(0, h + 0.5, 0),
		Color = Theme.MinigameColors.LaserTracer,
	})
	ghost(part(hub, {
		Name = "Beacon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.6,
		CFrame = center * CFrame.new(0, h + 4.6, 0),
		Color = C.Yellow,
		Material = Enum.Material.Neon,
	}))
end

local function buildEmitters(map: Model, center: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Emitters"
	folder.Parent = map
	local C = Theme.Colors
	for i = 1, Arena.EMITTER_COUNT do
		local a = (i - 1) * 2 * math.pi / Arena.EMITTER_COUNT + math.pi / Arena.EMITTER_COUNT
		local x, z = math.cos(a) * Arena.EMITTER_RADIUS, math.sin(a) * Arena.EMITTER_RADIUS
		local tower = model(folder, ("Emitter%02d"):format(i))
		tower:SetAttribute("Angle", a)
		ghost(part(tower, {
			Name = "Column",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(19, 3, 3),
			CFrame = column(center, x, -1.5, z),
			Color = C.Panel,
		}))
		ring(tower, center, x, Motion.HEIGHT.low, z, 1.75, Motion.COLORS.low).Name = "LowRing"
		ring(tower, center, x, Motion.HEIGHT.high, z, 1.75, Motion.COLORS.high).Name = "HighRing"
		ghost(part(tower, {
			Name = "Stripe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 3.6, 3.6),
			CFrame = column(center, x, 6.6, z),
			Color = Theme.MinigameColors.LaserTracer,
		}))
		-- The lens faces the arena and flashes while one of its lasers is telegraphed.
		local inward = Arena.EMITTER_RADIUS - 1.4
		ghost(part(tower, {
			Name = "Lens",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.6,
			CFrame = center * CFrame.new(math.cos(a) * inward, 3.1, math.sin(a) * inward),
			Color = Arena.LENS_DIM,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}))
		ghost(part(tower, {
			Name = "Cap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3.6,
			CFrame = center * CFrame.new(x, 8.6, z),
			Color = C.Yellow,
		}))
	end
end

local function buildSpawns(map: Model, center: CFrame)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	for i = 1, 12 do
		local a = (i - 1) * 2 * math.pi / 12
		local pos = center * Vector3.new(math.cos(a) * Arena.SPAWN_RADIUS, -0.4, math.sin(a) * Arena.SPAWN_RADIUS)
		ghost(part(spawns, {
			Name = ("Spawn%02d"):format(i),
			Size = Vector3.new(4, 1, 4),
			CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)),
			Transparency = 1,
		}))
	end
	spawns.Parent = map
end

function Arena.build(center: CFrame): Model
	local map = Instance.new("Model")
	map.Name = "LaserTracerArena"
	map.PrimaryPart = buildFloor(map, center)
	buildRim(map, center)
	buildHub(map, center)
	buildEmitters(map, center)
	buildSpawns(map, center)

	local lasers = Instance.new("Folder")
	lasers.Name = "Lasers"
	lasers.Parent = map

	map:SetAttribute("Minigame", "LaserTracer")
	map:SetAttribute("Center", center)
	map:SetAttribute("Hits", 0)
	map:SetAttribute("LaserSpeed", 0)
	map:SetAttribute("ActiveLasers", 0)
	map:SetAttribute("PowerDown", 0)
	CollectionService:AddTag(map, Arena.TAG)
	return map
end

return Arena
