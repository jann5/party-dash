--!strict
--[[
Spin: builds the arena Model around a center CFrame (pillar tops at center.Y).
A polished take on the legacy hand-built arena (src/shared/Maps/SpinArenaData.lua): a ring of 12 slate
pillars with neon rims and candy tops, the dark axle hub with the neon bar on top, and a lava basin
glowing far below, on a floating rock island. The old spectator stands and force-field barrier are gone
(Core has its own spectator platform; falling is handled by the map's KillY).

	Arena.build(center) -> Model      children: Pillars (12 Models), Bars (Folder), Spawns (12 parts), ...
	Arena.addBar(map, name, angle, color, hidden) -> Model
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local function clientModule(name: string): ModuleScript
	local node: Instance? = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	for _, step in { "Client", "Minigames", "Spin", name } do
		node = node and node:FindFirstChild(step)
	end
	assert(node and node:IsA("ModuleScript"), "Spin: StarterPlayerScripts.Client.Minigames.Spin." .. name .. " missing")
	return node
end
local BarMath = require(clientModule("BarMath")) :: any

local Arena = {}

Arena.BarMath = BarMath

Arena.TAG = "SpinArena" -- CollectionService tag the client renderer looks for
Arena.KILL_DEPTH = 24 -- below the pillar tops (just under the lava surface)

local LAVA_TOP = -23.5
local BASIN_RADIUS = BarMath.RING_RADIUS + 18
local HUB_RADIUS = 3
local PILLAR_HEIGHT = 26
local BODY_RADIUS = 3.6

local C = Theme.Colors
local SLATE = Color3.fromRGB(88, 78, 128)
local SLATE_DARK = Color3.fromRGB(62, 54, 96)
local HUB = Color3.fromRGB(48, 44, 66)
local ROCK = { Color3.fromRGB(96, 70, 92), Color3.fromRGB(78, 56, 80), Color3.fromRGB(60, 44, 66) }
local LAVA = Color3.fromRGB(150, 50, 12)
local LAVA_GLOW = Color3.fromRGB(255, 96, 24)
local BAR_RED = Color3.fromRGB(255, 45, 70)
local TIP = Color3.fromRGB(255, 230, 80)

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CanTouch = false
	for key, value in props do
		(p :: any)[key] = value
	end
	if p.CanCollide == false then
		p.CanQuery = false
	end
	p.Parent = parent
	return p
end

-- Vertical cylinder in map space whose top face is at local `top`.
local function disc(
	parent: Instance,
	center: CFrame,
	name: string,
	top: Vector3,
	height: number,
	radius: number,
	color: Color3,
	extra: { [string]: any }?
): Part
	local props: { [string]: any } = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = center * CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return part(parent, props)
end

local function decor(): { [string]: any }
	return { CanCollide = false, CastShadow = false }
end

local function pillarColor(i: number): Color3
	return Color3.fromHSV(((i - 1) / BarMath.PILLAR_COUNT + 0.98) % 1, 0.72, 1)
end

local function buildPillar(folder: Instance, center: CFrame, i: number)
	local model = Instance.new("Model")
	model.Name = ("Pillar%02d"):format(i)
	local top = BarMath.pillarTop(i)
	local color = pillarColor(i)
	local r = BarMath.TOP_RADIUS

	disc(model, center, "Body", top - Vector3.new(0, 1, 0), PILLAR_HEIGHT, BODY_RADIUS, SLATE, {
		Material = Enum.Material.Slate,
	})
	disc(model, center, "Foot", top - Vector3.new(0, PILLAR_HEIGHT - 2, 0), 3, BODY_RADIUS + 1, SLATE_DARK, {
		Material = Enum.Material.Slate,
	})
	-- Neon bands down the column (the legacy "Glow" rim is right under the top).
	disc(model, center, "Band", top - Vector3.new(0, 9, 0), 0.6, BODY_RADIUS + 0.15, color, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	disc(model, center, "Band", top - Vector3.new(0, 17, 0), 0.6, BODY_RADIUS + 0.15, color, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	local glow = disc(model, center, "Glow", top - Vector3.new(0, 1, 0), 0.6, r + 0.25, color, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	glow:SetAttribute("BaseColor", color)
	-- Candy top: white disc with a colored bullseye (each a hair higher to avoid z-fighting).
	local topPart = disc(model, center, "Top", top, 1, r, C.White)
	disc(model, center, "Ring", top + Vector3.new(0, 0.02, 0), 0.2, r - 0.9, color, decor())
	disc(model, center, "Dot", top + Vector3.new(0, 0.04, 0), 0.2, 1.4, C.White, decor())

	model.PrimaryPart = topPart
	model:SetAttribute("Index", i)
	model:SetAttribute("Angle", BarMath.pillarAngle(i))
	model.Parent = folder
end

local function buildHub(map: Model, center: CFrame)
	disc(map, center, "Hub", Vector3.zero, 26, HUB_RADIUS, HUB, { Material = Enum.Material.DiamondPlate })
	disc(map, center, "HubRim", Vector3.new(0, 0.05, 0), 0.5, HUB_RADIUS + 0.35, C.Purple, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})
	for k = 1, 3 do
		disc(map, center, "HubBand", Vector3.new(0, -5 - k * 5, 0), 0.6, HUB_RADIUS + 0.2, C.Purple, {
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
		})
	end
end

local function buildLava(map: Model, center: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Lava"
	folder.Parent = map

	disc(folder, center, "Lava", Vector3.new(0, LAVA_TOP, 0), 3, BASIN_RADIUS, LAVA, {
		Material = Enum.Material.CrackedLava,
		Transparency = 0.3,
		CanCollide = false,
		CastShadow = false,
	})
	disc(folder, center, "LavaGlow", Vector3.new(0, LAVA_TOP - 0.6, 0), 3, BASIN_RADIUS - 0.5, LAVA_GLOW, {
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
	})

	-- Rocky island under the basin (floating above the sea, like the rest of the world).
	local y = LAVA_TOP - 3.6
	local radius = BASIN_RADIUS + 2
	for k, color in ROCK do
		local h = 5 + k
		disc(folder, center, "Rock", Vector3.new(0, y, 0), h, radius, color, {
			Material = Enum.Material.Rock,
			CanCollide = false,
		})
		y -= h
		radius *= 0.72
	end

	-- Chunky candy rim around the basin.
	local segments = 40
	local chord = 2 * math.pi * (BASIN_RADIUS + 1) / segments + 0.4
	for k = 0, segments - 1 do
		local a = k / segments * 2 * math.pi
		local pos = Vector3.new(math.cos(a), 0, math.sin(a)) * (BASIN_RADIUS + 1) + Vector3.new(0, LAVA_TOP + 0.6, 0)
		part(folder, {
			Name = "Rim",
			Size = Vector3.new(chord, 3, 2.4),
			CFrame = center * CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)),
			Color = Theme.MapPalette[k % #Theme.MapPalette + 1],
			CanCollide = false,
		})
	end

	-- Embers drifting up out of the lava.
	local emitterPart = part(folder, {
		Name = "Embers",
		Size = Vector3.new(BASIN_RADIUS * 1.6, 0.2, BASIN_RADIUS * 1.6),
		CFrame = center * CFrame.new(0, LAVA_TOP + 0.2, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Rate = 14
	embers.Lifetime = NumberRange.new(2.5, 4)
	embers.Speed = NumberRange.new(3, 7)
	embers.SpreadAngle = Vector2.new(18, 18)
	embers.Acceleration = Vector3.new(0, 1.5, 0)
	embers.LightEmission = 1
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 20))
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	embers.Parent = emitterPart

	local light = Instance.new("PointLight")
	light.Color = LAVA_GLOW
	light.Range = 60
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = emitterPart
end

local function tipTrail(tip: BasePart, color: Color3)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.9, 0)
	a0.Parent = tip
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -0.9, 0)
	a1.Parent = tip
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.MinLength = 0.05
	trail.LightEmission = 0.7
	trail.Color = ColorSequence.new(TIP, color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.FaceCamera = true
	trail.Parent = tip
end

-- A bar Model (pivot = its middle) resting at `angle`. `hidden` parks it inside the hub (it rises later).
function Arena.addBar(map: Model, name: string, angle: number, color: Color3, hidden: boolean): Model
	local center = map:GetAttribute("Center") :: CFrame
	local bars = map:FindFirstChild("Bars") :: Folder
	local model = Instance.new("Model")
	model.Name = name
	local pivot = CFrame.new()
	local len = BarMath.BAR_HALF_LEN * 2
	local thick = BarMath.BAR_THICK
	local core = part(model, {
		Name = "Core",
		Size = Vector3.new(len, thick, thick),
		CFrame = pivot,
		Color = color,
		Material = Enum.Material.Neon,
	})
	part(model, {
		Name = "Shell",
		Size = Vector3.new(len + 0.4, thick + 0.7, thick + 0.7),
		CFrame = pivot,
		Color = color:Lerp(C.White, 0.5),
		Material = Enum.Material.Glass,
		Transparency = 0.65,
	})
	for _, side in { -1, 1 } do
		local tip = part(model, {
			Name = "Tip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 2.8,
			CFrame = pivot * CFrame.new(side * BarMath.BAR_HALF_LEN, 0, 0),
			Color = TIP,
			Material = Enum.Material.Neon,
		})
		tipTrail(tip, color)
	end
	part(model, {
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 7, 7),
		CFrame = pivot * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(40, 36, 52),
		Material = Enum.Material.Metal,
	})
	part(model, {
		Name = "CapRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 7.6, 7.6),
		CFrame = pivot * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
	})
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			-- purely visual: hits are computed from the bar math, never from touches
			child.CanCollide = false
			child.CanQuery = false
			child.CastShadow = false
		end
	end

	model.PrimaryPart = core
	model:SetAttribute("Color", color)
	model:PivotTo(BarMath.barCFrame(center, angle, if hidden then -12 else 0))
	model.Parent = bars
	return model
end

function Arena.build(center: CFrame): Model
	local map = Instance.new("Model")
	map.Name = "SpinArena"
	map:SetAttribute("Center", center)
	map:SetAttribute("KillY", center.Position.Y - Arena.KILL_DEPTH)
	map:SetAttribute("Hits", 0)
	map:SetAttribute("BarSpeed", 0)
	map:SetAttribute("BarCount", 0)

	local pillars = Instance.new("Folder")
	pillars.Name = "Pillars"
	for i = 1, BarMath.PILLAR_COUNT do
		buildPillar(pillars, center, i)
	end
	pillars.Parent = map

	buildHub(map, center)
	buildLava(map, center)

	local bars = Instance.new("Folder")
	bars.Name = "Bars"
	bars.Parent = map

	-- One spawn per pillar top (top face flush with the pillar top, facing the hub).
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	for i = 1, BarMath.PILLAR_COUNT do
		local top = BarMath.pillarTop(i)
		local pos = top - Vector3.new(0, 0.5, 0)
		part(spawns, {
			Name = ("Spawn%02d"):format(i),
			Size = Vector3.new(4, 1, 4),
			CFrame = center * CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0)),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
		})
	end
	spawns.Parent = map

	map.WorldPivot = center
	map:AddTag(Arena.TAG)
	Arena.addBar(map, "Bar1", BarMath.START_ANGLE, BAR_RED, false)
	map:SetAttribute("BarCount", 1)
	return map
end

Arena.BAR_COLORS = { BAR_RED, Color3.fromRGB(60, 220, 255) }

return Arena
