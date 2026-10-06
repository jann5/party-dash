--!strict
-- King of the Hill: builds the arena, a three-tier frosted cake hill on a candy plate, with ramps that
-- spiral up to a summit holding the glowing golden zone. Everything is relative to `center`
-- (ctx.center), so the map works at any origin. Decorations never collide or block hit queries.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)
local Zone = require(script.Parent.Zone)

local Map = {}

local C = Theme.Colors
local GOLD = Color3.fromRGB(255, 205, 60)

Map.GROUND_RADIUS = 48
Map.TIER_HEIGHT = 5
Map.SPAWN_RADIUS = 40
Map.KILL_DEPTH = 25
Map.BEAM_HEIGHT = 40
Map.GOLD = GOLD

-- { radius, side color, frosting color, ramp angles (deg), ramp run } for each tier from the bottom up.
local TIERS = {
	{ radius = 32, side = Color3.fromRGB(255, 120, 170), frost = C.White, ramps = { 0, 120, 240 }, run = 11 },
	{ radius = 21, side = Color3.fromRGB(120, 200, 255), frost = C.White, ramps = { 60, 180, 300 }, run = 9 },
	{
		radius = 13,
		side = Color3.fromRGB(190, 150, 255),
		frost = Color3.fromRGB(255, 240, 200),
		ramps = { 30, 150, 270 },
		run = 7.5,
	},
}
local FROST_OVERHANG = 0.8
local RAMP_WIDTH = 9

export type Refs = {
	map: Model,
	summitY: number, -- absolute Y of the summit floor
	zoneCenter: Vector3, -- absolute summit center (floor level)
	fill: BasePart,
	rim: BasePart,
	beam: BasePart,
	core: BasePart,
	motes: BasePart,
	light: PointLight,
}

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

-- Decorative part: never collides, never blocks raycasts/touches.
local function decor(parent: Instance, props: { [string]: any }): Part
	local p = part(parent, props)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- CFrame of a vertical cylinder whose top face is at local (x, top, z).
local function cylinderCFrame(center: CFrame, x: number, top: number, z: number, height: number): CFrame
	return center * CFrame.new(x, top - height / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
end

local function disc(parent: Instance, name: string, center: CFrame, top: number, height: number, radius: number)
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = cylinderCFrame(center, 0, top, 0, height),
	})
end

local function polar(angleDeg: number, r: number): (number, number)
	local a = math.rad(angleDeg)
	return math.cos(a) * r, math.sin(a) * r
end

-- A walkable ramp: a tilted slab whose top face runs from the lower floor (outside) up to the tier edge.
local function ramp(parent: Instance, center: CFrame, angleDeg: number, rTop: number, run: number, yLow: number, color)
	local yHigh = yLow + Map.TIER_HEIGHT
	local lx, lz = polar(angleDeg, rTop + run)
	local hx, hz = polar(angleDeg, rTop)
	local low = (center * CFrame.new(lx, yLow, lz)).Position
	local high = (center * CFrame.new(hx, yHigh, hz)).Position
	local along = high - low
	local length = along.Magnitude + 1.5 -- extra length is buried below the lower floor
	local frame = CFrame.lookAt(low, high, center.UpVector)
	-- Shift down half the thickness and back so the top face passes exactly through low/high.
	local thickness = 1.2
	local cf = frame * CFrame.new(0, -thickness / 2, -(along.Magnitude - 1.5) / 2)
	local slab = part(parent, {
		Name = "Ramp",
		Size = Vector3.new(RAMP_WIDTH, thickness, length),
		CFrame = cf,
		Color = color,
	})
	-- White candy-stripe edges.
	for _, side in { -1, 1 } do
		decor(parent, {
			Name = "RampEdge",
			Size = Vector3.new(0.6, 0.5, length - 1),
			CFrame = cf * CFrame.new(side * (RAMP_WIDTH / 2 - 0.3), thickness / 2 + 0.2, 0),
			Color = C.White,
		})
	end
	-- Chevrons pointing uphill so the path reads at a glance.
	for i = 1, 3 do
		decor(parent, {
			Name = "RampArrow",
			Size = Vector3.new(RAMP_WIDTH * 0.45, 0.12, 0.9),
			CFrame = cf * CFrame.new(0, thickness / 2 + 0.06, (length / 2) - i * (length / 4)),
			Color = C.Yellow,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
	end
	return slab
end

local function lollipop(parent: Instance, center: CFrame, angleDeg: number, r: number, color: Color3)
	local x, z = polar(angleDeg, r)
	local base = center * CFrame.new(x, 0, z)
	decor(parent, {
		Name = "LollipopStick",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 0.7, 0.7),
		CFrame = base * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.White,
	})
	-- Candy disc faces the hill.
	local facing = CFrame.lookAt(base.Position + center.UpVector * 10.5, center.Position + center.UpVector * 10.5)
	decor(parent, {
		Name = "LollipopCandy",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 5.5, 5.5),
		CFrame = facing * CFrame.Angles(0, math.pi / 2, 0),
		Color = color,
	})
	decor(parent, {
		Name = "LollipopSwirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.1, 3, 3),
		CFrame = facing * CFrame.Angles(0, math.pi / 2, 0),
		Color = C.White,
	})
	decor(parent, {
		Name = "LollipopDot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 1.3, 1.3),
		CFrame = facing * CFrame.Angles(0, math.pi / 2, 0),
		Color = color,
	})
end

local function flag(parent: Instance, center: CFrame, angleDeg: number, r: number, y: number, color: Color3)
	local x, z = polar(angleDeg, r)
	local base = center * CFrame.new(x, y, z)
	decor(parent, {
		Name = "FlagPole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 0.4, 0.4),
		CFrame = base * CFrame.new(0, 3.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = C.White,
	})
	decor(parent, {
		Name = "FlagTop",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.9,
		CFrame = base * CFrame.new(0, 7.1, 0),
		Color = GOLD,
		Material = Enum.Material.Neon,
	})
	-- The pennant points along the ring (tangent) so it reads from below.
	local tangent = CFrame.Angles(0, -math.rad(angleDeg), 0)
	decor(parent, {
		Name = "Flag",
		Size = Vector3.new(0.15, 1.8, 2.6),
		CFrame = base * tangent * CFrame.new(0, 5.9, 1.4),
		Color = color,
	})
end

function Map.build(center: CFrame): Refs
	local map = Instance.new("Model")
	map.Name = "KingOfTheHill"
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = map

	-- Candy plate (the floor you get knocked off of) ------------------------------------------------
	local ground = disc(scenery, "Ground", center, 0, 4, Map.GROUND_RADIUS)
	ground.Color = Color3.fromRGB(140, 235, 140)
	ground.Material = Enum.Material.SmoothPlastic
	local lip = disc(scenery, "GroundLip", center, -0.6, 3, Map.GROUND_RADIUS + 1)
	lip.Color = C.White
	-- A slightly darker inner lawn for depth.
	local inner = disc(scenery, "GroundRing", center, 0.05, 0.4, Map.GROUND_RADIUS - 6)
	inner.Color = Color3.fromRGB(120, 215, 125)
	inner.CanCollide = false
	inner.CanQuery = false
	-- Layered underside so the island looks like a floating cake stand.
	local under = { { 42, 5, C.Purple }, { 32, 5, C.Blue }, { 20, 5, C.Cyan }, { 9, 4, C.Pink } }
	local y = -3.6
	for i, u in under do
		local d = disc(scenery, "Under" .. i, center, y, u[2], u[1])
		d.Color = u[3]
		d.CanQuery = false
		y -= u[2]
	end
	-- Rim beads.
	for i = 0, 35 do
		local x, z = polar(i * 10, Map.GROUND_RADIUS - 0.6)
		decor(scenery, {
			Name = "Bead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.8,
			CFrame = center * CFrame.new(x, 0.5, z),
			Color = if i % 2 == 0 then C.Yellow else C.Pink,
		})
	end

	-- Cake tiers -----------------------------------------------------------------------------------------
	local floorY = 0
	for t, tier in TIERS do
		local top = floorY + Map.TIER_HEIGHT
		local body = disc(scenery, "Tier" .. t, center, top - 0.9, Map.TIER_HEIGHT - 0.9 + 0.5, tier.radius)
		body.Color = tier.side
		local frost = disc(scenery, "Frosting" .. t, center, top, 1.2, tier.radius + FROST_OVERHANG)
		frost.Color = tier.frost
		-- Frosting drips around the edge.
		local count = math.floor(tier.radius * 1.4)
		for i = 0, count - 1 do
			local x, z = polar(i / count * 360, tier.radius + FROST_OVERHANG - 0.35)
			local big = i % 3 == 0
			decor(scenery, {
				Name = "Drip",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * (if big then 1.5 else 1.0),
				CFrame = center * CFrame.new(x, top - (if big then 1.6 else 1.25), z),
				Color = tier.frost,
			})
		end
		-- Sprinkles on the tier side.
		for i = 0, count - 1, 2 do
			local x, z = polar((i + 0.5) / count * 360, tier.radius + 0.05)
			decor(scenery, {
				Name = "Sprinkle",
				Size = Vector3.new(0.35, 0.35, 1.1),
				CFrame = CFrame.lookAt((center * CFrame.new(x, top - 3, z)).Position, center.Position)
					* CFrame.Angles(0, 0, math.rad((i * 47) % 180)),
				Color = Theme.MapPalette[(i // 2) % #Theme.MapPalette + 1],
			})
		end
		for r, angle in tier.ramps do
			local color = Theme.MapPalette[(t + r) % #Theme.MapPalette + 1]
			ramp(scenery, center, angle, tier.radius + FROST_OVERHANG, tier.run, floorY, color)
		end
		floorY = top
	end
	local summitLocalY = floorY

	-- Decorations: lollipops at the plate edge, pennants on the summit -----------------------------------
	for i = 0, 5 do
		lollipop(scenery, center, 45 + i * 60, Map.GROUND_RADIUS - 3, Theme.MapPalette[i % #Theme.MapPalette + 1])
	end
	local summitR = TIERS[#TIERS].radius
	for i = 0, 5 do
		flag(scenery, center, i * 60 + 15, summitR + 0.1, summitLocalY, if i % 2 == 0 then C.Pink else C.Cyan)
	end

	-- The golden zone ------------------------------------------------------------------------------------
	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = "Zone"
	zoneFolder.Parent = map
	local r0 = Zone.START_RADIUS
	local rim = decor(zoneFolder, {
		Name = "ZoneRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, (r0 + 0.8) * 2, (r0 + 0.8) * 2),
		CFrame = cylinderCFrame(center, 0, summitLocalY + 0.08, 0, 0.16),
		Color = C.White,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	local fill = decor(zoneFolder, {
		Name = "ZoneFill",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, r0 * 2, r0 * 2),
		CFrame = cylinderCFrame(center, 0, summitLocalY + 0.12, 0, 0.2),
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CastShadow = false,
	})
	local beam = decor(zoneFolder, {
		Name = "ZoneBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(Map.BEAM_HEIGHT, r0 * 2, r0 * 2),
		CFrame = cylinderCFrame(center, 0, summitLocalY + Map.BEAM_HEIGHT, 0, Map.BEAM_HEIGHT),
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.9,
		CastShadow = false,
	})
	local core = decor(zoneFolder, {
		Name = "ZoneCore",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(160, 1.6, 1.6),
		CFrame = cylinderCFrame(center, 0, summitLocalY + 160, 0, 160),
		Color = Color3.fromRGB(255, 240, 170),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CastShadow = false,
	})
	local motes = decor(zoneFolder, {
		Name = "ZoneMotes",
		Size = Vector3.new(r0 * 2, 0.2, r0 * 2),
		CFrame = center * CFrame.new(0, summitLocalY + 0.3, 0),
		Transparency = 1,
		CastShadow = false,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Shape = Enum.ParticleEmitterShape.Disc
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 245, 190), GOLD)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.3, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(1.6, 2.6)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.Rate = 26
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = motes
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 2.5
	light.Range = 34
	light.Shadows = false
	light.Parent = motes

	-- Spawns around the base, between the ramps ------------------------------------------------------
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	for i = 1, 12 do
		local angle = (i - 1) * 30 + 15
		local x, z = polar(angle, Map.SPAWN_RADIUS)
		local pos = (center * CFrame.new(x, 0.5, z)).Position
		part(spawns, {
			Name = ("Spawn%02d"):format(i),
			Size = Vector3.new(4, 1, 4),
			CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z), center.UpVector),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		-- Visible pad under each spawn.
		local px, pz = polar(angle, Map.SPAWN_RADIUS)
		decor(scenery, {
			Name = "SpawnPad",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 5, 5),
			CFrame = cylinderCFrame(center, px, 0.14, pz, 0.2),
			Color = Theme.MapPalette[(i - 1) % #Theme.MapPalette + 1],
			CastShadow = false,
		})
	end
	spawns.Parent = map

	local summitY = (center * CFrame.new(0, summitLocalY, 0)).Position.Y
	map:SetAttribute("Minigame", "KingOfTheHill")
	map:SetAttribute("KillY", center.Position.Y - Map.KILL_DEPTH)
	map:SetAttribute("ZoneRadius", r0)
	map:SetAttribute("SummitY", summitY)
	map:SetAttribute("Swings", 0)
	map:SetAttribute("LeaderId", 0)
	map:SetAttribute("InZone", "")

	return {
		map = map,
		summitY = summitY,
		zoneCenter = (center * CFrame.new(0, summitLocalY, 0)).Position,
		fill = fill,
		rim = rim,
		beam = beam,
		core = core,
		motes = motes,
		light = light,
	}
end

-- Resizes the zone visuals to `radius` (cheap; call a few times per second).
function Map.setZoneRadius(refs: Refs, radius: number)
	local d = radius * 2
	refs.fill.Size = Vector3.new(refs.fill.Size.X, d, d)
	refs.rim.Size = Vector3.new(refs.rim.Size.X, d + 1.6, d + 1.6)
	refs.beam.Size = Vector3.new(refs.beam.Size.X, d, d)
	refs.motes.Size = Vector3.new(d, refs.motes.Size.Y, d)
	refs.map:SetAttribute("ZoneRadius", radius)
end

return Map
