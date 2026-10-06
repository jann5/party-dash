-- Dodgeball: builds the arena Model (pure builders; every position is relative to the given center).
--
-- Map layout (children of the returned Model):
--   Arena    floating cartoon dodgeball court (round, no walls) + decorations
--   Cannons  CannonNN Models, each with Carriage (yaws) and Barrel (yaws + pitches) sub-models and the
--            attributes Index, Pivot (CFrame) and BarrelPivot (CFrame) so clients can animate them
--   Spawns   12 invisible spawn pads in a ring
--   Golden   holds the golden ball while it waits on the floor
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)
local Tuning = require(script.Parent.Tuning)

local Map = {}

local C = Theme.Colors
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) -> Z
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cylinder axis (X) -> Y

local COURT_ORANGE = Color3.fromRGB(255, 160, 60)
local COURT_GOLD = Color3.fromRGB(255, 196, 92)
local HOLE = Color3.fromRGB(22, 16, 34)
local GOLD = Color3.fromRGB(255, 208, 64)

export type CannonInfo = {
	index: number,
	model: Model,
	pivot: CFrame,
	trunnion: Vector3, -- world position of the barrel pivot
}

export type Built = {
	model: Model,
	golden: Folder,
	cannons: { CannonInfo },
	floorY: number,
}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- Decoration: no collisions, touches or raycasts.
local function deco(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

-- Vertical cylinder whose TOP face is at `top`.
local function disc(parent: Instance, name: string, top: Vector3, height: number, radius: number, color: Color3): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)) * VERTICAL,
		Color = color,
	})
end

local function ball(parent: Instance, name: string, pos: Vector3, diameter: number, color: Color3): Part
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(pos),
		Color = color,
	})
end

local function cloud(parent: Instance, center: Vector3, scale: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Cloud"
	local puffs = rng:NextInteger(4, 6)
	for i = 1, puffs do
		local t = (i - 1) / (puffs - 1) - 0.5
		local d = scale * rng:NextNumber(0.75, 1.15) * (1 - math.abs(t) * 0.55)
		local offset =
			Vector3.new(t * scale * 2.3, rng:NextNumber(-0.1, 0.25) * scale, rng:NextNumber(-0.3, 0.3) * scale)
		local puff = deco(ball(model, "Puff", center + offset, d, C.White))
		puff.CastShadow = false
	end
	model.Parent = parent
end

---------------------------------------------------------------------------------------------------
-- Arena

local function buildCourt(arena: Instance, o: Vector3)
	local R = Tuning.ARENA_RADIUS
	local function up(h: number): Vector3
		return o + Vector3.new(0, h, 0)
	end

	-- Walkable slab (the only collidable floor), then painted layers a hair above it.
	disc(arena, "Floor", o, 3, R, C.White)
	local paint = Instance.new("Folder")
	paint.Name = "Paint"
	paint.Parent = arena
	deco(disc(paint, "OuterCourt", up(0.02), 0.4, R - 2.4, COURT_ORANGE))
	deco(disc(paint, "LineRing", up(0.04), 0.4, 21, C.White))
	deco(disc(paint, "InnerCourt", up(0.06), 0.4, 19.8, COURT_GOLD))
	local midline = part(paint, {
		Name = "MidLine",
		Size = Vector3.new(2 * (R - 2.4) - 0.4, 0.4, 1.1),
		CFrame = CFrame.new(up(0.07) - Vector3.new(0, 0.2, 0)),
		Color = C.White,
	})
	deco(midline)
	deco(disc(paint, "CenterRing", up(0.09), 0.4, 7.4, C.White))
	deco(disc(paint, "CenterSpot", up(0.11), 0.4, 6.2, C.Pink))
	deco(disc(paint, "CenterDot", up(0.13), 0.4, 2.4, C.White))
	-- Little "throw lines": short white dashes around the inner ring.
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local pos = up(0.05) + Vector3.new(math.cos(a), 0, math.sin(a)) * 28.5 - Vector3.new(0, 0.2, 0)
		local dash = part(paint, {
			Name = "Dash",
			Size = Vector3.new(0.4, 0.4, 3.2),
			CFrame = CFrame.lookAt(pos, Vector3.new(o.X, pos.Y, o.Z)),
			Color = C.White,
			Transparency = 0.15,
		})
		deco(dash)
	end

	-- Rim beads (decorative, non-colliding: getting hit can still push you off).
	for i = 0, 31 do
		local a = i / 32 * math.pi * 2
		local bead = ball(
			arena,
			"Bead",
			o + Vector3.new(math.cos(a) * (R - 0.9), 0.5, math.sin(a) * (R - 0.9)),
			1.9,
			if i % 2 == 0 then C.Pink else C.Yellow
		)
		deco(bead)
	end

	-- Layered candy underside.
	deco(disc(arena, "Under1", up(-3), 4, R - 3, COURT_ORANGE))
	deco(disc(arena, "Under2", up(-7), 4, R - 11, C.Yellow))
	deco(disc(arena, "Under3", up(-11), 4, R - 19, C.Pink))
	deco(disc(arena, "Under4", up(-15), 4, R - 27, C.Purple))
	deco(ball(arena, "UnderTip", up(-19.5), 9, C.Cyan))
end

local function buildDecor(arena: Instance, o: Vector3, rng: Random)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = arena
	-- Clouds drifting around and below the court.
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local dist = rng:NextNumber(95, 140)
		local pos = o + Vector3.new(math.cos(a) * dist, rng:NextNumber(-30, 18), math.sin(a) * dist)
		cloud(decor, pos, rng:NextNumber(7, 12), rng)
	end
	-- Giant floating dodgeballs (with a white seam) for that sports-day vibe.
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + 0.4
		local dist = rng:NextNumber(70, 92)
		local d = rng:NextNumber(8, 14)
		local pos = o + Vector3.new(math.cos(a) * dist, rng:NextNumber(-22, 10), math.sin(a) * dist)
		local color = Theme.MapPalette[(i - 1) % #Theme.MapPalette + 1]
		deco(ball(decor, "BigBall", pos, d, color))
		local seam = part(decor, {
			Name = "Seam",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(d * 0.12, d * 1.02, d * 1.02),
			CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			Color = C.White,
		})
		deco(seam)
	end
end

---------------------------------------------------------------------------------------------------
-- Cannons

local function buildCannon(parent: Instance, index: number, pivot: CFrame, color: Color3): CannonInfo
	local S = Tuning.CANNON_SCALE
	local model = Instance.new("Model")
	model.Name = ("Cannon%02d"):format(index)
	local carriage = Instance.new("Model")
	carriage.Name = "Carriage"
	carriage.Parent = model
	local barrel = Instance.new("Model")
	barrel.Name = "Barrel"
	barrel.Parent = model
	local barrelPivot = pivot * CFrame.new(Tuning.TRUNNION * S) * CFrame.Angles(Tuning.REST_PITCH, 0, 0)

	local function piece(
		into: Instance,
		base: CFrame,
		name: string,
		offset: Vector3,
		rot: CFrame,
		size: Vector3,
		col: Color3,
		shape: Enum.PartType?
	): Part
		local p = part(into, {
			Name = name,
			Shape = shape or Enum.PartType.Block,
			Size = size * S,
			CFrame = base * CFrame.new(offset * S) * rot,
			Color = col,
		})
		deco(p)
		return p
	end
	local I = CFrame.identity
	local CYL = Enum.PartType.Cylinder
	local BALL = Enum.PartType.Ball

	-- Floating pedestal (stays still).
	local pedestal = Instance.new("Model")
	pedestal.Name = "Pedestal"
	pedestal.Parent = model
	local top = pivot.Position
	deco(disc(pedestal, "Top", top, 1.2, 3.7 * S, C.Panel))
	deco(disc(pedestal, "Trim", top - Vector3.new(0, 1.1, 0), 0.7, 4.1 * S, color))
	deco(disc(pedestal, "Cone", top - Vector3.new(0, 1.8, 0), 1.6, 2.4 * S, C.Panel))
	deco(ball(pedestal, "Tip", top - Vector3.new(0, 3.6, 0), 2.2 * S, color))

	-- Carriage: body, cheeks and two big yellow wheels.
	piece(carriage, pivot, "Body", Vector3.new(0, 1.5, 0.4), I, Vector3.new(2.8, 1.4, 4), C.Panel)
	for _, side in { -1, 1 } do
		piece(carriage, pivot, "Cheek", Vector3.new(1.25 * side, 2.5, 0.4), I, Vector3.new(0.5, 2, 2.6), C.Panel)
		piece(carriage, pivot, "Wheel", Vector3.new(1.95 * side, 1.5, 0.4), I, Vector3.new(0.7, 3, 3), C.Yellow, CYL)
		piece(carriage, pivot, "Hub", Vector3.new(2.15 * side, 1.5, 0.4), I, Vector3.new(0.6, 1, 1), C.Ink, CYL)
	end

	-- Barrel (relative to its trunnion pivot; -Z is the muzzle direction).
	piece(barrel, barrelPivot, "Tube", Vector3.new(0, 0, -1.25), ALONG_Z, Vector3.new(6.8, 2.8, 2.8), color, CYL)
	piece(barrel, barrelPivot, "Cap", Vector3.new(0, 0, 2.1), I, Vector3.one * 2.8, color, BALL)
	piece(barrel, barrelPivot, "Band", Vector3.new(0, 0, -0.6), ALONG_Z, Vector3.new(0.6, 2.95, 2.95), C.White, CYL)
	piece(barrel, barrelPivot, "Muzzle", Vector3.new(0, 0, -4.2), ALONG_Z, Vector3.new(1.1, 3.5, 3.5), C.Ink, CYL)
	piece(barrel, barrelPivot, "Hole", Vector3.new(0, 0, -4.78), ALONG_Z, Vector3.new(0.15, 2.4, 2.4), HOLE, CYL)
	-- Cute googly eyes on top of the barrel.
	for _, side in { -1, 1 } do
		piece(barrel, barrelPivot, "Eye", Vector3.new(0.62 * side, 1.25, -2.5), I, Vector3.one * 1.15, C.White, BALL)
		piece(barrel, barrelPivot, "Pupil", Vector3.new(0.62 * side, 1.45, -2.95), I, Vector3.one * 0.55, C.Ink, BALL)
	end
	piece(barrel, barrelPivot, "Fuse", Vector3.new(0, 1.55, 2.3), VERTICAL, Vector3.new(0.9, 0.32, 0.32), C.Ink, CYL)
	local spark = piece(barrel, barrelPivot, "Spark", Vector3.new(0, 2.1, 2.3), I, Vector3.one * 0.6, C.Orange, BALL)
	spark.Material = Enum.Material.Neon
	-- Telegraph glow around the back of the barrel (clients fade it in while the cannon charges).
	local glow =
		piece(barrel, barrelPivot, "Glow", Vector3.new(0, 0, 0.8), ALONG_Z, Vector3.new(4.6, 3.3, 3.3), C.Yellow, CYL)
	glow.Material = Enum.Material.Neon
	glow.Transparency = 1
	glow.CastShadow = false

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "FuseSparks"
	sparkles.Enabled = false
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(C.Yellow, C.Orange)
	sparkles.LightEmission = 0.8
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.2, 0.4)
	sparkles.Speed = NumberRange.new(6, 12)
	sparkles.SpreadAngle = Vector2.new(60, 60)
	sparkles.Rate = 60
	sparkles.Parent = spark

	model:SetAttribute("Index", index)
	model:SetAttribute("Pivot", pivot)
	model:SetAttribute("BarrelPivot", barrelPivot)
	model.Parent = parent
	return { index = index, model = model, pivot = pivot, trunnion = barrelPivot.Position }
end

---------------------------------------------------------------------------------------------------
-- Public

function Map.build(center: CFrame, rng: Random): Built
	local o = center.Position
	local map = Instance.new("Model")
	map.Name = "DodgeballArena"
	-- Stream the whole arena as one unit so clients never see half a cannon.
	pcall(function()
		map.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)

	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = map
	buildCourt(arena, o)
	buildDecor(arena, o, rng)

	local cannonsFolder = Instance.new("Folder")
	cannonsFolder.Name = "Cannons"
	cannonsFolder.Parent = map
	local cannons = {}
	local barrelColors = { C.Red, C.Blue, C.Green, C.Purple, C.Pink, C.Cyan, C.Orange, C.Yellow }
	for i = 1, Tuning.CANNON_COUNT do
		local a = (i - 0.5) / Tuning.CANNON_COUNT * math.pi * 2
		local pos = o
			+ Vector3.new(math.cos(a) * Tuning.CANNON_RING, -Tuning.CANNON_DROP, math.sin(a) * Tuning.CANNON_RING)
		local pivot = CFrame.lookAt(pos, Vector3.new(o.X, pos.Y, o.Z))
		table.insert(cannons, buildCannon(cannonsFolder, i, pivot, barrelColors[(i - 1) % #barrelColors + 1]))
	end

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	for i = 1, Tuning.SPAWN_COUNT do
		local a = (i - 1) / Tuning.SPAWN_COUNT * math.pi * 2
		local pos = o + Vector3.new(math.cos(a) * Tuning.SPAWN_RADIUS, 0.5, math.sin(a) * Tuning.SPAWN_RADIUS)
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

	local golden = Instance.new("Folder")
	golden.Name = "Golden"
	golden.Parent = map

	return { model = map, golden = golden, cannons = cannons, floorY = o.Y }
end

local function goldSparkles(parent: Instance, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparkles"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(C.Yellow, C.White)
	e.LightEmission = 0.7
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = rate
	e.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 12
	light.Brightness = 2
	light.Parent = parent
end

-- The golden ball waiting on the floor (server checks pickups by distance; clients bob it locally).
function Map.goldenBall(folder: Instance, pos: Vector3): Part
	local p = deco(ball(folder, "GoldenBall", pos, Tuning.GOLD_RADIUS * 2, GOLD)) :: Part
	p.Material = Enum.Material.Neon
	p:SetAttribute("Base", pos)
	goldSparkles(p, 14)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromScale(6, 1.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 180
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.FontFace
	label.Text = "GRAB ME!"
	label.TextScaled = true
	label.TextColor3 = C.Yellow
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Ink
	stroke.Thickness = 3
	stroke.Parent = label
	gui.Parent = p

	-- Glowing landing pad under it so it reads from far away.
	local pad = part(p, {
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 6, 6),
		CFrame = CFrame.new(pos - Vector3.new(0, Tuning.GOLD_FLOOR_HEIGHT - 0.25, 0)) * VERTICAL,
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CastShadow = false,
	})
	deco(pad)
	return p
end

-- The golden ball shown above a holder's head (welded, massless, purely visual).
function Map.heldBall(character: Model): BasePart?
	local anchor = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not anchor or not anchor:IsA("BasePart") then
		return nil
	end
	local offset = if anchor.Name == "Head" then 2.6 else 4.6
	local p = Instance.new("Part")
	p.Name = "PD_HeldGoldenBall"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 2.4
	p.Color = GOLD
	p.Material = Enum.Material.Neon
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = anchor.CFrame * CFrame.new(0, offset, 0)
	goldSparkles(p, 10)
	local weld = Instance.new("Weld")
	weld.Part0 = anchor
	weld.Part1 = p
	weld.C0 = CFrame.new(0, offset, 0)
	weld.Parent = p
	p.Parent = character
	return p
end

return Map
