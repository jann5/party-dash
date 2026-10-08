--[[
Party Dash: the permanent lobby island "Sunny Isle" (docs/v2/ART_BIBLE.md section 6, GAME_DESIGN 1.7).

	local model = Lobby.build(center: Vector3)  -- a new, UNPARENTED Model named "Lobby" (Core parents it once)

Coordinates are studs from `center` (the grass top surface); +Z is north, toward the arena island 340 studs away.
Contract children (docs/ARCHITECTURE.md "Lobby model contract"), all direct children of the Model:
	Folder "Spawns"         12 invisible BaseParts on the spawn pad, all facing +Z (toward the PLAY pad)
	Part "PlayZone"         the 30 x 0.4 x 30 PLAY pad at center + (0, 0, 36). It SITS ON the grass: bottom at
	                        center.Y, TOP SURFACE AT center.Y + 0.4 (Lobby.PAD_HEIGHT). BillboardGui "ZoneBoard" on it
	                        (labels "Count" and "Timer", filled by the World client).
	Model "ZoneBorder"      1-stud Neon frame around the pad (World client colours it)
	anchor Parts            WheelAnchor, ShopAnchor, DailyChestAnchor, GroupChestAnchor, SoloPortalAnchor, WatchAnchor
	                        (live TV, SurfaceGui "Screen"), LeaderboardAnchor (TOP SOLO), WinsBoardAnchor (TOP WINS),
	                        LevelBoardAnchor (TOP LEVEL). The three board anchors are 16 x 10 faces whose Front face
	                        looks at the PLAY pad; the others are invisible 2-stud cubes at their station.
	ProximityPrompts        attribute PD_Action = Shop | Wheel | Daily | Group | Solo | Watch (in an Attachment
	                        "PromptPoint" under the matching anchor)
Other names the World client uses: "WheelDisc" (rotating wheel face) and "Bulb" parts in Model "Wheel", "ReadyRing"
parts and Model "Lid" (attribute Hinge) in Models "DailyChest" / "GroupChest", Parts "Trampoline" (attribute
LaunchY), the SurfaceGui gradient "Swirl" in Model "SoloPortal".

Walkable layout: grass plateau 128 x 112 (notched corners) -> 6 studs down: terrace ring 10 wide (sand S/E, grass N/W)
-> cliffs into the sea. An invisible wading shelf (top 1.6 under the water) fills the whole boundary circle
(Config.LOBBY_RADIUS) so a kid can splash around the island but never sink; invisible walls stand on that circle.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local Lobby = {}

Lobby.PLAY_ZONE = Vector3.new(0, 0, 36) -- PLAY pad centre (on the grass)
Lobby.PAD_HEIGHT = 0.4 -- the PlayZone top surface is this far above center.Y
Lobby.PAD_SIZE = 30
Lobby.SPAWN_PAD = Vector3.new(0, 0.2, -38) -- spawn pad top centre
Lobby.WALL_RADIUS = Config.LOBBY_RADIUS -- inner face of the invisible boundary walls

local C = Theme.Colors
local W = Theme.World

-- Saturated walkway colours: ART_BIBLE 4.3 rule 1 (S >= 0.45, V <= 0.90) rules out the pale Theme.World paver/sand.
local PAVER = Color3.fromRGB(214, 150, 88)
local PAVER_DARK = Color3.fromRGB(184, 118, 66)
local SAND = Color3.fromRGB(226, 186, 100)
local CREAM = Color3.fromRGB(255, 246, 222) -- "white" on red/white props (never a floor)
local SCREEN = Color3.fromRGB(20, 18, 30)

local TERRACE_Y = -6 -- terrace top, relative to the centre
local SHELF_DEPTH = 1.6 -- the wading shelf top is this far under the water (ART_BIBLE 5.2)
local CLIFF_FOOT = 2 -- cliff bands reach this far under the water
local LABEL_DISTANCE = 160

local PLATEAU = { -- { x0, x1, z0, z1 } grass plateau with 8 x 8 corner notches
	{ -56, 56, -56, 56 },
	{ 56, 64, -48, 48 },
	{ -64, -56, -48, 48 },
}
local TERRACE = { -- { x0, x1, z0, z1, surface } disjoint pieces of the ring around the plateau
	{ -66, 66, 56, 66, "grass" }, -- north
	{ -74, -64, -56, 56, "grass" }, -- west
	{ -64, -56, 48, 56, "grass" }, -- north-west notch
	{ 56, 64, 48, 56, "grass" }, -- north-east notch
	{ -66, 66, -66, -56, "sand" }, -- south
	{ 64, 74, -56, 56, "sand" }, -- east
	{ -64, -56, -56, -48, "sand" }, -- south-west notch
	{ 56, 64, -56, -48, "sand" }, -- south-east notch
}

type At = (x: number, y: number, z: number) -> Vector3

-- Helpers -------------------------------------------------------------------------------------------------------

-- Art.block options for decoration nobody should bump into or raycast against.
local function deco(opts: { [string]: any }?): { [string]: any }
	local o = if opts then table.clone(opts) else {}
	o.collide = false
	o.canQuery = false
	o.canTouch = false
	return o
end

local function neon(part: BasePart): BasePart
	part.Material = Enum.Material.Neon
	return part
end

-- Invisible, non-colliding helper part (anchors, spawn points).
local function marker(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	return Art.block(parent, name, size, cf, "plain", deco({ transparency = 1, castShadow = false }))
end

-- Station frame: origin on the grass at (x, z), LookVector (the station's front) toward `target`.
local function facing(at: At, x: number, z: number, target: Vector3): CFrame
	local p = at(x, 0, z)
	local flat = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
	return CFrame.lookAt(p, p + flat.Unit)
end

-- A segment-aligned block (beams, legs, ropes) from a to b.
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, thickness: number, recipe: string, opts)
	local mid = (a + b) / 2
	return Art.block(
		parent,
		name,
		Vector3.new(thickness, thickness, (b - a).Magnitude),
		CFrame.lookAt(mid, b),
		recipe,
		opts
	)
end

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or C.Ink
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function gradient(parent: Instance, colors: { Color3 }, rotation: number): UIGradient
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(keys)
	g.Rotation = rotation
	g.Parent = parent
	return g
end

-- Top-40% white gloss band on a sign face (ART_BIBLE 8.3 "Gloss").
local function gloss(parent: Instance)
	local g = Instance.new("Frame")
	g.Name = "Gloss"
	g.BackgroundColor3 = C.White
	g.BackgroundTransparency = 0.55
	g.BorderSizePixel = 0
	g.Position = UDim2.fromScale(0.02, 0.06)
	g.Size = UDim2.fromScale(0.96, 0.38)
	g.Parent = parent
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.2, 1)
	fade.Parent = g
end

local function textLabel(
	parent: Instance,
	name: string,
	text: string,
	font: Font,
	color: Color3,
	pos: UDim2,
	size: UDim2
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.FontFace = font
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Parent = parent
	return l
end

-- Chunky headline: ink-stroked text plus an ink "drop" copy behind it (ART_BIBLE 8.2). autoStroke marks labels on
-- BillboardGuis so the World client can scale the stroke with the on-screen text height.
local function headline(
	parent: Instance,
	name: string,
	text: string,
	font: Font,
	color: Color3,
	pos: UDim2,
	size: UDim2,
	strokeThickness: number,
	autoStroke: boolean?
): TextLabel
	local drop = textLabel(
		parent,
		name .. "Drop",
		text,
		font,
		C.Ink,
		pos + UDim2.fromScale(0, size.Y.Scale * 0.06),
		size
	)
	drop.ZIndex = 1
	stroke(drop, strokeThickness)
	local main = textLabel(parent, name, text, font, color, pos, size)
	main.ZIndex = 2
	stroke(main, strokeThickness)
	if autoStroke then
		drop:SetAttribute("PD_AutoStroke", true)
		main:SetAttribute("PD_AutoStroke", true)
	end
	return main
end

local function surfaceGui(part: BasePart, name: string, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Parent = part
	return gui
end

local function icon(parent: Instance, name: string, key: string, pos: UDim2, size: UDim2): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = Assets.icon(key)
	img.ScaleType = Enum.ScaleType.Fit
	img.Position = pos
	img.Size = size
	img.Parent = parent
	return img
end

-- Floating station label (ref1 style): BillboardGui 12 x 3 studs above the prop, ink-stroked FredokaOne.
-- opts: { rainbow: bool?, subtitle: string?, badge: bool? }
local function floatingLabel(
	adornee: BasePart,
	text: string,
	color: Color3,
	height: number,
	opts: { [string]: any }?
): BillboardGui
	local o = opts or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Size = UDim2.new(12, 0, if o.subtitle then 4.2 else 3, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = LABEL_DISTANCE
	gui.AlwaysOnTop = false
	gui.Adornee = adornee
	gui.Parent = adornee
	local titleHeight = if o.subtitle then 0.68 else 0.92
	local title =
		headline(gui, "Title", text, Theme.FontFace, color, UDim2.fromScale(0, 0), UDim2.fromScale(1, titleHeight), 3, true)
	if o.rainbow then
		title.TextColor3 = C.White
		gradient(title, { C.Red, C.Orange, C.Yellow, C.Green, C.Cyan, C.Purple }, 0)
	end
	if o.subtitle then
		local sub = textLabel(
			gui,
			"Subtitle",
			o.subtitle,
			Theme.FontBodyHeavy,
			C.White,
			UDim2.fromScale(0.05, 0.7),
			UDim2.fromScale(0.9, 0.28)
		)
		stroke(sub, 2)
		sub:SetAttribute("PD_AutoStroke", true)
	end
	if o.badge then
		-- red "!" bubble, shown by the World client while the reward is claimable
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.97, 0.12)
		badge.Size = UDim2.fromScale(0.22, 0.88)
		badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
		badge.BackgroundColor3 = C.Red
		badge.Rotation = -8
		badge.Visible = false
		badge.ZIndex = 3
		badge.Parent = gui
		corner(badge, UDim.new(0.5, 0))
		stroke(badge, 2.5).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local mark = textLabel(
			badge,
			"Mark",
			"!",
			Theme.FontHype,
			C.White,
			UDim2.fromScale(0.15, 0.12),
			UDim2.fromScale(0.7, 0.8)
		)
		mark.ZIndex = 4
	end
	return gui
end

-- ProximityPrompt on an Attachment "PromptPoint" under `anchor` (prompts sit at the station front, chest height).
local function prompt(anchor: BasePart, offset: Vector3, action: string, actionText: string, objectText: string)
	local point = Instance.new("Attachment")
	point.Name = "PromptPoint"
	point.Position = offset
	point.Parent = anchor
	local p = Instance.new("ProximityPrompt")
	p.Name = action .. "Prompt"
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p:SetAttribute("PD_Action", action)
	p.Parent = point
	return p
end

-- Stair-stepped round slab (ART_BIBLE 3.1 voxel disc), strips `cell` deep, widths rounded to the cell.
local function voxelRound(parent: Instance, name: string, center: Vector3, radius: number, cell: number, top: number, thickness: number, recipe: string, opts)
	local n = math.ceil(radius / cell)
	for k = -n, n - 1 do
		local zMid = (k + 0.5) * cell
		local reach = radius * radius - zMid * zMid
		if reach > 0 then
			local half = math.floor(math.sqrt(reach) / cell + 0.5) * cell
			if half >= cell then
				Art.block(
					parent,
					name,
					Vector3.new(half * 2, thickness, cell),
					CFrame.new(center.X, top - thickness / 2, center.Z + zMid),
					recipe,
					opts
				)
			end
		end
	end
end

-- Island ---------------------------------------------------------------------------------------------------------

-- A walkable slab with a grass top, a 1.5-stud green lip (0.3 overhang, its top 0.05 under the grass so it never
-- z-fights) and a textured cliff band down to `foot` (all Y relative to the centre).
local function lipAndCliff(parent: Instance, at: At, r: { any }, top: number, foot: number, cliff: string)
	local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	Art.block(parent, "GrassLip", Vector3.new(w + 0.6, 1.45, d + 0.6), CFrame.new(at(cx, top - 0.775, cz)), "grass_lip")
	local h = (top - 1.5) - foot
	Art.block(parent, "Cliff", Vector3.new(w, h, d), CFrame.new(at(cx, foot + h / 2, cz)), cliff)
end

local function grassBlock(parent: Instance, at: At, r: { any }, top: number, foot: number, cliff: string, grass: Color3)
	local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
	Art.block(
		parent,
		"GrassTop",
		Vector3.new(x1 - x0, 1, z1 - z0),
		CFrame.new(at((x0 + x1) / 2, top - 0.5, (z0 + z1) / 2)),
		"grass_top",
		{ color = grass }
	)
	lipAndCliff(parent, at, r, top, foot, cliff)
end

local function sandBlock(parent: Instance, at: At, r: { any }, top: number, foot: number)
	local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	Art.block(parent, "SandTop", Vector3.new(w, 2, d), CFrame.new(at(cx, top - 1, cz)), "sand", { color = SAND })
	local h = (top - 2) - foot
	Art.block(parent, "Cliff", Vector3.new(w, h, d), CFrame.new(at(cx, foot + h / 2, cz)), "dirt_cliff_low")
end

-- Shore foam just outside every edge of the terrace outline (bars along Z-facing edges cover the corners).
local function buildFoam(parent: Instance, at: At, seaY: number)
	local edges = { -- { x0, x1, z0, z1, outward normal }, outline of the terrace ring
		{ 74, 74, -56, 56, Vector3.xAxis },
		{ -74, -74, -56, 56, -Vector3.xAxis },
		{ 66, 66, 56, 66, Vector3.xAxis },
		{ -66, -66, 56, 66, -Vector3.xAxis },
		{ 66, 66, -66, -56, Vector3.xAxis },
		{ -66, -66, -66, -56, -Vector3.xAxis },
		{ -66, 66, 66, 66, Vector3.zAxis },
		{ -66, 66, -66, -66, -Vector3.zAxis },
		{ 66, 76, 56, 56, Vector3.zAxis },
		{ -76, -66, 56, 56, Vector3.zAxis },
		{ 66, 76, -56, -56, -Vector3.zAxis },
		{ -76, -66, -56, -56, -Vector3.zAxis },
	}
	for _, e in edges do
		local x0, x1, z0, z1, n = e[1], e[2], e[3], e[4], e[5]
		local alongX = z0 == z1
		local len = if alongX then (x1 - x0) + (if math.abs(x0) == 66 and math.abs(x1) == 66 then 4 else 0) else z1 - z0
		local size = if alongX then Vector3.new(len, 0.2, 2) else Vector3.new(2, 0.2, len)
		local pos = Vector3.new((x0 + x1) / 2, seaY + 0.05, (z0 + z1) / 2) + n
		Art.block(parent, "Foam", size, CFrame.new(at(pos.X, pos.Y, pos.Z)), "plain", deco({
			color = W.Foam,
			transparency = 0.25,
			castShadow = false,
		}))
	end
end

-- Block steps (1-stud rises, 1.6 deep) going OUTWARD from (x, z) along `dir`, from `fromTop` down `count` steps.
local function stairs(parent: Instance, at: At, x: number, z: number, dir: Vector3, fromTop: number, count: number, foot: number, recipe: string, color: Color3?)
	local side = Vector3.new(dir.Z, 0, -dir.X)
	for k = 0, count - 1 do
		local top = fromTop - k
		local h = top - foot
		local center = Vector3.new(x, 0, z) + dir * (1.6 * k + 0.8)
		local size = Vector3.new(8, h, 1.6)
		local cf = CFrame.fromMatrix(at(center.X, foot + h / 2, center.Z), side, Vector3.yAxis)
		Art.block(parent, "Step", size, cf, recipe, { color = color, faces = "topsides" })
	end
end

local function buildIsland(m: Model, at: At, seaLocal: number)
	local island = Instance.new("Model")
	island.Name = "Island"
	island.Parent = m
	local foot = seaLocal - CLIFF_FOOT

	-- Plateau: the grass is laid in 8-stud strips across the notched outline (seamless: the texture tile is 8 studs),
	-- over lip + brick dirt cliff blocks that run down to the terrace.
	for z0 = -56, 48, 8 do
		local half = if z0 >= -48 and z0 < 48 then 64 else 56
		Art.block(island, "GrassTop", Vector3.new(half * 2, 1, 8), CFrame.new(at(0, -0.5, z0 + 4)), "grass_top", {
			color = W.GrassTop,
		})
	end
	for _, r in PLATEAU do
		lipAndCliff(island, at, r, 0, TERRACE_Y - 1, "dirt_cliff")
	end
	-- Terrace ring (sand S/E, grass N/W), darker cliff into the sea.
	for _, r in TERRACE do
		if r[5] == "grass" then
			grassBlock(island, at, r, TERRACE_Y, foot, "dirt_cliff_low", W.GrassAlt)
		else
			sandBlock(island, at, r, TERRACE_Y, foot)
		end
	end
	buildFoam(island, at, seaLocal)

	-- Plateau -> terrace stairs (S, W, E): a landing flush with the grass, then five 1-stud steps.
	stairs(island, at, 0, -56, -Vector3.zAxis, 0, 6, TERRACE_Y - 1, "paver", PAVER)
	stairs(island, at, -64, 0, -Vector3.xAxis, 0, 6, TERRACE_Y - 1, "paver", PAVER)
	stairs(island, at, 64, 0, Vector3.xAxis, 0, 6, TERRACE_Y - 1, "paver", PAVER)
	-- Terrace -> water: beach steps on the east (they continue under the surface onto the wading shelf).
	stairs(island, at, 74, 0, Vector3.xAxis, TERRACE_Y - 1, 9, foot - 1, "sand", SAND)
end

-- Sea side: dock, wading shelf, boundary walls, buoys ---------------------------------------------------------------

local function buildDock(m: Model, at: At, seaLocal: number)
	local dock = Instance.new("Model")
	dock.Name = "Dock"
	dock.Parent = m
	local deckTop = seaLocal + 2
	stairs(dock, at, 0, -66, -Vector3.zAxis, TERRACE_Y - 1, 5, seaLocal - 3, "wood")
	Art.block(dock, "Deck", Vector3.new(8, 1, 18), CFrame.new(at(0, deckTop - 0.5, -83)), "wood", { u = 4, v = 8 })
	for _, z in { -75, -83, -91.4 } do
		for _, x in { -3.6, 3.6 } do
			local tall = z < -91
			local top = if tall then deckTop + 1.4 else deckTop - 1
			local h = top - (seaLocal - 3)
			Art.block(dock, "Post", Vector3.new(1.2, h, 1.2), CFrame.new(at(x, top - h / 2, z)), "wood", {
				color = W.WoodDark,
				u = 4,
				v = 4,
			})
		end
	end
end

local function buildBoundary(m: Model, at: At, seaLocal: number)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	folder.Parent = m
	local shelfLocal = seaLocal - SHELF_DEPTH

	-- Wading shelf: fills the whole wall circle (rounded UP to 8-stud cells) so there is no deep pocket anywhere
	-- inside the walls. Invisible: it lies under the opaque cartoon water anyway.
	local reach = Lobby.WALL_RADIUS + 2
	local cell = 8
	local n = math.ceil(reach / cell)
	for k = -n, n - 1 do
		local z0, z1 = k * cell, (k + 1) * cell
		local zNear = if z0 <= 0 and z1 >= 0 then 0 else math.min(math.abs(z0), math.abs(z1))
		if zNear < reach then
			local half = math.ceil(math.sqrt(reach * reach - zNear * zNear) / cell) * cell
			Art.block(
				folder,
				"Shelf",
				Vector3.new(half * 2, 2, cell),
				CFrame.new(at(0, shelfLocal - 1, z0 + cell / 2)),
				"plain",
				{ transparency = 1, castShadow = false, canTouch = false }
			)
		end
	end

	-- Invisible walls: a 24-gon whose inner faces sit exactly on WALL_RADIUS, tall enough that no trampoline or
	-- dash clears them.
	local sides = 24
	local thick = 2
	local bottom, top = shelfLocal - 1, 80
	local length = 2 * (Lobby.WALL_RADIUS + thick) * math.tan(math.pi / sides) + 1
	for i = 0, sides - 1 do
		local a = (i + 0.5) * 2 * math.pi / sides
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = at(0, (bottom + top) / 2, 0) + radial * (Lobby.WALL_RADIUS + thick / 2)
		Art.block(
			folder,
			"Wall",
			Vector3.new(length, top - bottom, thick),
			CFrame.lookAt(p, p + radial),
			"plain",
			{ transparency = 1, castShadow = false, canTouch = false }
		)
	end

	-- Red/white buoys just inside the walls show where the swimming area ends.
	local buoys = Instance.new("Model")
	buoys.Name = "Buoys"
	buoys.Parent = m
	for i = 0, 15 do
		local a = (i + 0.5) * 2 * math.pi / 16
		local p = Vector3.new(math.cos(a), 0, math.sin(a)) * (Lobby.WALL_RADIUS - 2)
		Art.block(buoys, "Buoy", Vector3.new(2.2, 2.2, 2.2), CFrame.new(at(p.X, seaLocal + 0.5, p.Z)), "plain", deco({
			shape = Enum.PartType.Ball,
			color = C.Red,
		}))
		Art.block(
			buoys,
			"BuoyBand",
			Vector3.new(0.6, 2.35, 2.35),
			CFrame.new(at(p.X, seaLocal + 0.6, p.Z)) * CFrame.Angles(0, 0, math.pi / 2),
			"plain",
			deco({ shape = Enum.PartType.Cylinder, color = CREAM })
		)
	end
end

-- Walkways, spawn pad ------------------------------------------------------------------------------------------

local function buildPaths(m: Model, at: At)
	local paths = Instance.new("Model")
	paths.Name = "Paths"
	paths.Parent = m
	local function path(x0: number, x1: number, z0: number, z1: number)
		Art.block(
			paths,
			"Paver",
			Vector3.new(x1 - x0, 0.3, z1 - z0),
			CFrame.new(at((x0 + x1) / 2, -0.05, (z0 + z1) / 2)),
			"paver",
			{ color = PAVER }
		)
	end
	path(-4, 4, -31, -14) -- spawn pad -> plaza
	path(-4, 4, 18, 21) -- plaza -> PLAY pad
	path(-41, -16, -2, 6) -- plaza -> shop
	path(16, 41, -2, 6) -- plaza -> wheel
	-- Plaza: a round paver court with a darker medallion in the middle.
	local plaza = at(0, 0, 2)
	voxelRound(paths, "PaverPlaza", plaza, 16, 4, 0.1, 0.3, "paver", { color = PAVER })
	voxelRound(paths, "PaverMedallion", plaza, 11, 4, 0.15, 0.3, "paver", { color = PAVER_DARK })
end

local function buildSpawn(m: Model, at: At)
	local pad = Instance.new("Model")
	pad.Name = "SpawnPad"
	pad.Parent = m
	local p = Lobby.SPAWN_PAD
	Art.block(pad, "PaverSpawn", Vector3.new(24, 0.4, 14), CFrame.new(at(p.X, p.Y - 0.2, p.Z)), "paver", {
		color = PAVER_DARK,
		faces = "topsides",
	})
	-- Logo lying on the pad: a flat part whose Front face points up, image top toward +Z (readable from the spawns).
	local logo = marker(
		pad,
		"Logo",
		Vector3.new(15, 10, 0.1),
		CFrame.new(at(p.X, p.Y + 0.05, p.Z)) * CFrame.Angles(math.pi / 2, 0, 0)
	)
	local decal = Instance.new("Decal")
	decal.Name = "LogoDecal"
	decal.Face = Enum.NormalId.Front
	decal.Texture = Assets.Art.logo
	decal.Parent = logo

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = m
	local i = 0
	for _, z in { -4, 3 } do
		for _, x in { -10, -6, -2, 2, 6, 10 } do
			i += 1
			local pos = at(p.X + x, p.Y - 0.1, p.Z + z)
			marker(spawns, "Spawn" .. i, Vector3.new(2, 0.2, 2), CFrame.lookAt(pos, pos + Vector3.zAxis))
		end
	end

	-- Default spawn for brand-new characters (Core moves people onto the Spawns right away).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	local sp = at(p.X, p.Y - 0.5, p.Z)
	spawn.CFrame = CFrame.lookAt(sp, sp + Vector3.zAxis)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.CastShadow = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = m
end

-- Stations -----------------------------------------------------------------------------------------------------

-- Daily / Group chest: pedestal with a Neon ready ring, banded chest with a hinged lid (Model "Lid", attribute Hinge).
local function buildChest(m: Model, at: At, x: number, z: number, kind: string)
	local isGroup = kind == "Group"
	local chest = Instance.new("Model")
	chest.Name = kind .. "Chest"
	chest.Parent = m
	local f = facing(at, x, z, at(0, 0, -38)) -- front toward the spawn pad
	local body = if isGroup then C.Gold else W.Wood
	local band = if isGroup then C.Blue else C.Gold

	Art.block(chest, "Pedestal", Vector3.new(9, 1, 9), f * CFrame.new(0, 0.5, 0), "stone_top", { faces = "topsides" })
	for _, bar in {
		{ Vector3.new(8.4, 0.16, 0.5), Vector3.new(0, 1.08, 4.05) },
		{ Vector3.new(8.4, 0.16, 0.5), Vector3.new(0, 1.08, -4.05) },
		{ Vector3.new(0.5, 0.16, 7.6), Vector3.new(4.05, 1.08, 0) },
		{ Vector3.new(0.5, 0.16, 7.6), Vector3.new(-4.05, 1.08, 0) },
	} do
		neon(Art.block(chest, "ReadyRing", bar[1], f * CFrame.new(bar[2]), "plain", deco({ color = C.Yellow, castShadow = false })))
	end
	Art.block(chest, "Body", Vector3.new(7, 3.4, 5), f * CFrame.new(0, 2.7, 0), "wood", { color = body, u = 4, v = 4 })
	for _, bx in { -2.2, 2.2 } do
		Art.block(chest, "Band", Vector3.new(0.7, 3.5, 5.1), f * CFrame.new(bx, 2.7, 0), "plain", { color = band })
	end
	local lid = Instance.new("Model")
	lid.Name = "Lid"
	lid.Parent = chest
	lid:SetAttribute("Hinge", f * CFrame.new(0, 4.4, 2.5)) -- rotate about its local X axis (+ = open)
	Art.block(lid, "LidTop", Vector3.new(7.1, 1.6, 5.1), f * CFrame.new(0, 5.2, 0), "wood", {
		color = if isGroup then C.Gold else W.WoodDark,
		u = 4,
		v = 4,
	})
	for _, bx in { -2.2, 2.2 } do
		Art.block(lid, "LidBand", Vector3.new(0.7, 1.7, 5.2), f * CFrame.new(bx, 5.2, 0), "plain", { color = band })
	end
	if isGroup then
		-- white diamond emblem (matches the chest_group icon's star)
		Art.block(
			chest,
			"Emblem",
			Vector3.new(1.5, 1.5, 0.3),
			f * CFrame.new(0, 2.8, -2.55) * CFrame.Angles(0, 0, math.pi / 4),
			"plain",
			{ color = C.White }
		)
	else
		Art.block(chest, "Lock", Vector3.new(1.2, 1.4, 0.4), f * CFrame.new(0, 4.3, -2.65), "plain", { color = C.Gold })
	end

	local anchor = marker(m, kind .. "ChestAnchor", Vector3.new(2, 2, 2), f * CFrame.new(0, 3, 0))
	prompt(anchor, Vector3.new(0, 0, -5), kind, "Open", kind .. " Chest")
	if isGroup then
		floatingLabel(anchor, "Group Chest", C.Cyan, 6.5, { subtitle = "Like + Join = FREE chest!", badge = true })
	else
		floatingLabel(anchor, "Daily Chest", C.Yellow, 6, { badge = true })
	end
end

-- Winners podium (1-2-3 blocks) facing the spawn pad from the south-west.
local function buildPodium(m: Model, at: At)
	local podium = Instance.new("Model")
	podium.Name = "Podium"
	podium.Parent = m
	local f = facing(at, -44, -30, at(0, 0, -30))
	Art.block(podium, "Plinth", Vector3.new(28, 0.6, 10), f * CFrame.new(0, 0.3, 0), "stone_top", { faces = "topsides" })
	-- viewer's left is the frame's +X: 2nd left, 1st centre, 3rd right
	for _, s in {
		{ 1, 0, 5, C.Gold },
		{ 2, 8, 3.5, C.Silver },
		{ 3, -8, 2.5, C.Bronze },
	} do
		local place, px, h, color = s[1], s[2], s[3], s[4]
		local block = Art.block(
			podium,
			"Podium" .. place,
			Vector3.new(8, h, 6),
			f * CFrame.new(px, 0.6 + h / 2, 0),
			"toy_block",
			{ color = color }
		)
		local gui = surfaceGui(block, "Place", Enum.NormalId.Front, 24)
		gui.LightInfluence = 0.4
		headline(
			gui,
			"Number",
			tostring(place),
			Theme.FontHype,
			C.White,
			UDim2.fromScale(0.3, 0.12),
			UDim2.fromScale(0.4, 0.76),
			4
		)
	end
end

local function buildShop(m: Model, at: At)
	local shop = Instance.new("Model")
	shop.Name = "Shop"
	shop.Parent = m
	local f = facing(at, -48, 2, at(0, 0, 2)) -- front faces the plaza (+X)
	local wood = { u = 4, v = 8 }

	Art.block(shop, "Deck", Vector3.new(16, 0.4, 10), f * CFrame.new(0, 0.2, 0), "wood", { u = 8, v = 8 })
	for _, p in { { -7, -4, 8.6 }, { 7, -4, 8.6 }, { -7, 4, 10.6 }, { 7, 4, 10.6 } } do
		Art.block(shop, "Post", Vector3.new(1.2, p[3], 1.2), f * CFrame.new(p[1], 0.4 + p[3] / 2, p[2]), "wood", wood)
	end
	Art.block(shop, "Counter", Vector3.new(14, 3.5, 2.4), f * CFrame.new(0, 2.15, -2.8), "wood", wood)
	Art.block(shop, "CounterTop", Vector3.new(14.6, 0.4, 3), f * CFrame.new(0, 4.1, -2.8), "plain", { color = C.Red })
	Art.block(shop, "BackWall", Vector3.new(13, 7, 0.6), f * CFrame.new(0, 3.9, 4), "wood", wood)
	Art.block(shop, "Shelf", Vector3.new(12, 0.4, 1.2), f * CFrame.new(0, 5.4, 3.2), "wood", { color = W.WoodDark })
	for i, color in { C.Red, C.Blue, C.Purple, C.Green } do
		Art.block(
			shop,
			"Goods",
			Vector3.new(1.4, 1.8, 1.2),
			f * CFrame.new(-4.5 + (i - 1) * 3, 6.5, 3.2),
			"toy_block",
			{ color = color }
		)
	end

	-- Red/cream striped awning, sloping 15 degrees down to the front, with a scalloped valance.
	local slope = CFrame.Angles(math.rad(-15), 0, 0)
	for i = 1, 8 do
		local x = -8 + (i - 0.5) * 2
		Art.block(
			shop,
			"Awning",
			Vector3.new(2, 0.4, 10.4),
			f * CFrame.new(x, 10.2, 0) * slope,
			"plain",
			{ color = if i % 2 == 1 then C.Red else CREAM }
		)
		Art.block(
			shop,
			"Valance",
			Vector3.new(2, 0.9, 0.3),
			f * CFrame.new(x, 8.35, -5.05),
			"plain",
			deco({ color = if i % 2 == 1 then CREAM else C.Red })
		)
	end

	-- Sign board above the awning: shop icon + "Shop".
	local board = Art.block(shop, "Sign", Vector3.new(14, 4, 0.8), f * CFrame.new(0, 11.4, -3.6), "plain", {
		color = C.GreenDark,
	})
	local gui = surfaceGui(board, "SignGui", Enum.NormalId.Front, 40)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = C.White
	face.Parent = gui
	gradient(face, { C.Green, C.GreenDark }, 90)
	stroke(face, 8).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gloss(face)
	icon(face, "Icon", "shop", UDim2.fromScale(0.06, -0.12), UDim2.fromScale(0.3, 1.24))
	headline(face, "Title", "Shop", Theme.FontFace, C.White, UDim2.fromScale(0.36, 0.1), UDim2.fromScale(0.58, 0.8), 6)

	-- Props: a pile of coin blocks and a bat on the counter.
	for _, c in { { -5, 4.8, -3.3 }, { -3.8, 4.8, -2.6 }, { -4.4, 5.8, -3 }, { -2.6, 4.8, -3.4 }, { -5.4, 4.8, -2.3 } } do
		Art.block(
			shop,
			"Coin",
			Vector3.new(1, 1, 1),
			f * CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(0, math.rad(c[1] * 20), 0),
			"plain",
			deco({ color = C.Gold })
		)
	end
	local bat = f * CFrame.new(3.2, 4.75, -2.9) * CFrame.Angles(0, math.rad(70), 0)
	Art.block(shop, "BatBarrel", Vector3.new(0.8, 0.8, 3.4), bat * CFrame.new(0, 0, -0.7), "wood", deco({ u = 2, v = 2 }))
	Art.block(shop, "BatGrip", Vector3.new(0.5, 0.5, 1.4), bat * CFrame.new(0, 0, 1.7), "plain", deco({ color = C.Red }))

	local anchor = marker(m, "ShopAnchor", Vector3.new(2, 2, 2), f * CFrame.new(0, 3, -2.8))
	prompt(anchor, Vector3.new(0, 0, -3.5), "Shop", "Shop", "Shop")
	floatingLabel(anchor, "Shop", C.Green, 14.5)
end

local function buildWheel(m: Model, at: At)
	local wheel = Instance.new("Model")
	wheel.Name = "Wheel"
	wheel.Parent = m
	local f = facing(at, 46, 2, at(0, 0, 2)) -- the wheel face looks at the plaza (-X)
	local hub = 13
	local axis = CFrame.Angles(0, math.pi / 2, 0) -- cylinder X axis -> along the frame's Z (the spin axis)

	Art.block(wheel, "Base", Vector3.new(10, 2, 6), f * CFrame.new(0, 1, 0), "toy_block", { color = C.Red })
	Art.block(wheel, "Post", Vector3.new(2, hub - 1, 2), f * CFrame.new(0, 2 + (hub - 2) / 2, 1.6), "wood", { u = 4, v = 4 })
	for _, side in { -1, 1 } do
		beam(
			wheel,
			"Leg",
			(f * CFrame.new(side * 4.2, 2, 1.6)).Position,
			(f * CFrame.new(0, hub, 1.6)).Position,
			1.2,
			"wood",
			{ u = 4, v = 4 }
		)
	end
	Art.block(wheel, "Rim", Vector3.new(0.8, 20.8, 20.8), f * CFrame.new(0, hub, 0.6) * axis, "plain", {
		shape = Enum.PartType.Cylinder,
		color = C.Gold,
	})
	local disc = Art.block(wheel, "WheelDisc", Vector3.new(1.2, 18, 18), f * CFrame.new(0, hub, -0.2) * axis, "plain", {
		shape = Enum.PartType.Cylinder,
		color = C.White,
		castShadow = false,
	})
	-- After the axis turn the cylinder's Right face looks out of the wheel's front.
	local gui = surfaceGui(disc, "Face", Enum.NormalId.Right, 30)
	local face = Instance.new("ImageLabel")
	face.Name = "WheelFace"
	face.BackgroundTransparency = 1
	face.Image = Assets.Art.wheel_face
	face.Size = UDim2.fromScale(1, 1)
	face.Parent = gui
	Art.block(wheel, "HubCap", Vector3.new(0.6, 3, 3), f * CFrame.new(0, hub, -1.1) * axis, "plain", {
		shape = Enum.PartType.Cylinder,
		color = C.Gold,
	})
	for i = 1, 16 do
		local a = (i - 1) * 2 * math.pi / 16
		local bulb = Art.block(
			wheel,
			"Bulb",
			Vector3.new(0.8, 0.8, 0.8),
			f * CFrame.new(math.sin(a) * 9.7, hub + math.cos(a) * 9.7, -0.2),
			"plain",
			deco({ shape = Enum.PartType.Ball, color = if i % 2 == 1 then C.Yellow else C.White, castShadow = false })
		)
		bulb:SetAttribute("Index", i)
		neon(bulb)
	end
	-- Red pixel-arrow pointer at 12 o'clock.
	for row, width in { 2.4, 1.6, 0.8 } do
		Art.block(
			wheel,
			"Pointer",
			Vector3.new(width, 0.9, 0.6),
			f * CFrame.new(0, hub + 10.9 - (row - 1) * 0.9, -1.1),
			"plain",
			{ color = C.Red }
		)
	end

	local anchor = marker(m, "WheelAnchor", Vector3.new(2, 2, 2), f * CFrame.new(0, hub, 0))
	prompt(anchor, Vector3.new(0, 3 - hub, -5), "Wheel", "Spin", "Lucky Wheel")
	floatingLabel(anchor, "Lucky Wheel", C.White, 13.5, { rainbow = true })
end

-- PLAY pad (join square), its Neon border, the PLAY arch and the ready board.
local function buildPlayZone(m: Model, at: At)
	local z = Lobby.PLAY_ZONE
	local size = Lobby.PAD_SIZE
	local h = Lobby.PAD_HEIGHT
	local pad = Art.block(m, "PlayZone", Vector3.new(size, h, size), CFrame.new(at(z.X, h / 2, z.Z)), "plain", {
		color = C.Yellow,
	})
	-- Yellow / cream checker in 5-stud squares, lit like the world.
	local checker = surfaceGui(pad, "Checker", Enum.NormalId.Top, 8)
	checker.LightInfluence = 1
	local cells = size / 5
	for gx = 0, cells - 1 do
		for gz = 0, cells - 1 do
			local cell = Instance.new("Frame")
			cell.Name = "Cell"
			cell.BorderSizePixel = 0
			cell.Position = UDim2.fromScale(gx / cells, gz / cells)
			cell.Size = UDim2.fromScale(1 / cells, 1 / cells)
			cell.BackgroundColor3 = if (gx + gz) % 2 == 0 then C.Yellow else CREAM
			cell.Parent = checker
		end
	end

	local border = Instance.new("Model")
	border.Name = "ZoneBorder"
	border.Parent = m
	local half = size / 2 - 0.5
	for _, e in {
		{ Vector3.new(size, 0.3, 1), Vector3.new(0, 0, half) },
		{ Vector3.new(size, 0.3, 1), Vector3.new(0, 0, -half) },
		{ Vector3.new(1, 0.3, size - 2), Vector3.new(half, 0, 0) },
		{ Vector3.new(1, 0.3, size - 2), Vector3.new(-half, 0, 0) },
	} do
		local edge = Art.block(
			border,
			"Border",
			e[1],
			CFrame.new(at(z.X + e[2].X, h + 0.15, z.Z + e[2].Z)),
			"plain",
			deco({ color = C.White, castShadow = false })
		)
		neon(edge)
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Enabled = false -- the World client switches it on while players are queued
		sparkles.EmissionDirection = Enum.NormalId.Top
		sparkles.Color = ColorSequence.new(Color3.fromRGB(120, 255, 140), Color3.fromRGB(60, 255, 90))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.7, 0)
		sparkles.Lifetime = NumberRange.new(0.9, 1.5)
		sparkles.Speed = NumberRange.new(5, 9)
		sparkles.SpreadAngle = Vector2.new(8, 8)
		sparkles.Rate = 6
		sparkles.Parent = edge
	end
	-- Corner beacons: green posts with Neon caps (coloured with the border) so the pad reads from the spawn.
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			local x, zz = z.X + cx * (half - 0.5), z.Z + cz * (half - 0.5)
			Art.block(border, "Beacon", Vector3.new(2, 4, 2), CFrame.new(at(x, h + 2, zz)), "toy_block", { color = C.Green })
			local cap = Art.block(
				border,
				"BeaconCap",
				Vector3.new(1.6, 1.6, 1.6),
				CFrame.new(at(x, h + 4.8, zz)),
				"plain",
				deco({ color = C.White, castShadow = false })
			)
			neon(cap)
		end
	end

	-- PLAY arch on the north edge: red/cream block pillars, yellow toy beam, the PLAY board facing the spawns.
	local arch = Instance.new("Model")
	arch.Name = "PlayArch"
	arch.Parent = m
	local az = z.Z + size / 2 + 2
	for _, side in { -1, 1 } do
		for j = 1, 10 do
			Art.block(
				arch,
				"Pillar",
				Vector3.new(3, 2, 3),
				CFrame.new(at(side * 13, h + (j - 0.5) * 2, az)),
				"toy_block",
				{ color = if j % 2 == 1 then C.Red else CREAM }
			)
		end
	end
	local beamTop = h + 20 + 3
	Art.block(arch, "Beam", Vector3.new(30, 3, 3), CFrame.new(at(0, beamTop - 1.5, az)), "toy_block", { color = C.Yellow })
	local boardPos = at(0, beamTop + 3.5, az - 0.4)
	local board = Art.block(
		arch,
		"PlayBoard",
		Vector3.new(24, 7, 1),
		CFrame.lookAt(boardPos, boardPos - Vector3.zAxis),
		"plain",
		{ color = C.GreenDark }
	)
	local gui = surfaceGui(board, "PlayGui", Enum.NormalId.Front, 40)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = C.White
	face.Parent = gui
	gradient(face, { C.Green, C.GreenDark }, 90)
	stroke(face, 10).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gloss(face)
	headline(face, "Title", "PLAY", Theme.FontFace, C.White, UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.84), 6)

	-- Ready board above the pad: "3/12 READY" + "0:14", written by the World client from GameState.
	local zoneBoard = Instance.new("BillboardGui")
	zoneBoard.Name = "ZoneBoard"
	zoneBoard.Size = UDim2.new(16, 0, 6, 0)
	zoneBoard.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	zoneBoard.LightInfluence = 0
	zoneBoard.MaxDistance = 220
	zoneBoard.AlwaysOnTop = false
	zoneBoard.Parent = pad
	headline(
		zoneBoard,
		"Count",
		("0/%d READY"):format(Config.MAX_PLAYERS),
		Theme.FontFace,
		C.White,
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 0.5),
		3,
		true
	)
	headline(zoneBoard, "Timer", "", Theme.FontHype, C.White, UDim2.fromScale(0.2, 0.52), UDim2.fromScale(0.6, 0.46), 3, true)
end

-- Leaderboard: a 16 x 10 anchor face (other pieces mount their SurfaceGui on its Front), wood frame, colored header
-- with an icon, and an optional topper.
local function buildBoard(
	m: Model,
	boards: Model,
	at: At,
	name: string,
	x: number,
	z: number,
	title: string,
	color: Color3,
	iconKey: string,
	topper: string?
)
	local f = facing(at, x, z, at(0, 0, 30))
	local anchor = Art.block(m, name, Vector3.new(16, 10, 1), f * CFrame.new(0, 9, 0), "plain", { color = C.Panel })
	Art.block(boards, "Frame", Vector3.new(17.6, 11.6, 0.8), f * CFrame.new(0, 9, 0.7), "wood", { u = 4, v = 4 })
	for _, px in { -8.4, 8.4 } do
		Art.block(boards, "BoardPost", Vector3.new(1.2, 17.6, 1.2), f * CFrame.new(px, 8.8, 0.7), "wood", { u = 4, v = 4 })
	end
	local header = Art.block(boards, "Header", Vector3.new(17.6, 3, 1.2), f * CFrame.new(0, 15.8, 0.4), "plain", {
		color = color,
	})
	local gui = surfaceGui(header, "HeaderGui", Enum.NormalId.Front, 30)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = C.White
	face.Parent = gui
	gradient(face, { color, color:Lerp(C.Ink, 0.3) }, 90)
	stroke(face, 6).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gloss(face)
	icon(face, "IconLeft", iconKey, UDim2.fromScale(0.03, -0.15), UDim2.fromScale(0.16, 1.3))
	icon(face, "IconRight", iconKey, UDim2.fromScale(0.81, -0.15), UDim2.fromScale(0.16, 1.3))
	headline(face, "Title", title, Theme.FontFace, C.White, UDim2.fromScale(0.2, 0.1), UDim2.fromScale(0.6, 0.8), 4)

	if topper == "crown" then
		local top = f * CFrame.new(0, 17.3, 0.4)
		Art.block(boards, "Crown", Vector3.new(5, 1.4, 1.6), top * CFrame.new(0, 0.7, 0), "plain", { color = C.Gold })
		for _, cx in { -1.9, 0, 1.9 } do
			Art.block(boards, "CrownSpike", Vector3.new(1.2, 1.4, 1.2), top * CFrame.new(cx, 2.1, 0), "plain", {
				color = C.Gold,
			})
		end
		Art.block(boards, "CrownJewel", Vector3.new(0.8, 0.8, 0.3), top * CFrame.new(0, 0.7, -0.85), "plain", {
			color = C.Red,
		})
	elseif topper == "trophy" then
		local top = f * CFrame.new(0, 17.3, 0.4)
		Art.block(boards, "TrophyBase", Vector3.new(2.6, 0.8, 1.6), top * CFrame.new(0, 0.4, 0), "plain", { color = C.Gold })
		Art.block(boards, "TrophyStem", Vector3.new(0.8, 1.2, 0.8), top * CFrame.new(0, 1.4, 0), "plain", { color = C.Gold })
		Art.block(boards, "TrophyCup", Vector3.new(2.8, 2.2, 2), top * CFrame.new(0, 3.1, 0), "plain", { color = C.Gold })
	end
	floatingLabel(anchor, title, color, 15.5)
	return anchor
end

local function buildSoloPortal(m: Model, at: At)
	local portal = Instance.new("Model")
	portal.Name = "SoloPortal"
	portal.Parent = m
	local f = facing(at, 44, 44, at(0, 0, 30))
	Art.block(portal, "Base", Vector3.new(12, 0.6, 5), f * CFrame.new(0, 0.3, 0), "stone_top", { faces = "topsides" })
	for _, px in { -5, 5 } do
		Art.block(portal, "Pillar", Vector3.new(2.4, 14, 2.4), f * CFrame.new(px, 7.6, 0), "toy_block", {
			color = C.Purple,
		})
	end
	Art.block(portal, "Lintel", Vector3.new(12.4, 2.4, 2.8), f * CFrame.new(0, 15.2, 0), "toy_block", { color = C.Gold })
	local door = Art.block(portal, "PortalFace", Vector3.new(7.6, 12.6, 0.4), f * CFrame.new(0, 6.9, 0), "plain", {
		color = C.Purple,
		castShadow = false,
	})
	for _, faceId in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = surfaceGui(door, "PortalGui", faceId, 20)
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = C.White
		glow.Parent = gui
		local swirl = gradient(glow, { C.Purple, C.Pink, C.Cyan, C.Purple }, 45)
		swirl.Name = "Swirl" -- the World client turns it
		for i, s in { 0.72, 0.46, 0.22 } do
			local ring = Instance.new("Frame")
			ring.Name = "Ring"
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(s, s)
			ring.SizeConstraint = Enum.SizeConstraint.RelativeXX
			ring.BackgroundTransparency = 1
			ring.Parent = glow
			corner(ring, UDim.new(0.5, 0))
			stroke(ring, 6 - i, C.White).Transparency = 0.25 + i * 0.15
		end
	end

	local anchor = marker(m, "SoloPortalAnchor", Vector3.new(2, 2, 2), f * CFrame.new(0, 7, 0))
	prompt(anchor, Vector3.new(0, -4, -3), "Solo", "Enter", "Solo Mode")
	floatingLabel(anchor, "Solo Mode", C.Purple, 12)
end

-- Live TV: a 24 x 13 screen (the WatchAnchor part, SurfaceGui "Screen" filled by the World client).
local function buildLiveTv(m: Model, at: At)
	local tv = Instance.new("Model")
	tv.Name = "LiveTv"
	tv.Parent = m
	local f = facing(at, 44, -30, at(0, 0, -30))
	Art.block(tv, "Base", Vector3.new(20, 0.6, 4), f * CFrame.new(0, 0.3, 0.4), "stone_top", { faces = "topsides" })
	for _, px in { -8, 8 } do
		Art.block(tv, "Leg", Vector3.new(1.6, 3.4, 1.6), f * CFrame.new(px, 2.3, 0.4), "plain", { color = C.InkSoft })
	end
	Art.block(tv, "Bezel", Vector3.new(25.6, 14.6, 1.2), f * CFrame.new(0, 10.5, 0.4), "plain", { color = C.Panel })
	Art.block(tv, "Trim", Vector3.new(25.6, 1, 1.6), f * CFrame.new(0, 18.3, 0.4), "plain", { color = C.Red })
	local screen = Art.block(m, "WatchAnchor", Vector3.new(24, 13, 1), f * CFrame.new(0, 10.5, 0), "plain", {
		color = SCREEN,
	})
	local gui = surfaceGui(screen, "Screen", Enum.NormalId.Front, 30)
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.White
	bg.Parent = gui
	gradient(bg, { C.PanelLight, C.Panel, C.PanelDeep }, 90)
	local pill = Instance.new("Frame")
	pill.Name = "LivePill"
	pill.Position = UDim2.fromScale(0.04, 0.07)
	pill.Size = UDim2.fromScale(0.2, 0.17)
	pill.BackgroundColor3 = C.Red
	pill.Parent = bg
	corner(pill, UDim.new(0.5, 0))
	stroke(pill, 4).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.fromScale(0.1, 0.5)
	dot.Size = UDim2.fromScale(0.5, 0.5)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = C.White
	dot.Parent = pill
	corner(dot, UDim.new(0.5, 0))
	textLabel(pill, "Text", "LIVE", Theme.FontFace, C.White, UDim2.fromScale(0.36, 0.12), UDim2.fromScale(0.58, 0.76))
	icon(bg, "Icon", "mg_random", UDim2.fromScale(0.04, 0.28), UDim2.fromScale(0.26, 0.5))
	headline(bg, "Title", "NEXT GAME", Theme.FontFace, C.White, UDim2.fromScale(0.32, 0.3), UDim2.fromScale(0.64, 0.4), 5)
	local hint = textLabel(
		bg,
		"Hint",
		"",
		Theme.FontBodyHeavy,
		C.Muted,
		UDim2.fromScale(0.32, 0.74),
		UDim2.fromScale(0.64, 0.14)
	)
	stroke(hint, 2)

	prompt(screen, Vector3.new(0, -7.5, -4), "Watch", "Watch", "Live TV")
	floatingLabel(screen, "Live TV", C.Red, 10.5)
end

local function buildTrampolines(m: Model, at: At)
	local folder = Instance.new("Model")
	folder.Name = "Trampolines"
	folder.Parent = m
	for _, p in { { -69, -34 }, { -69, -18 }, { -69, 18 } } do
		local base = CFrame.new(at(p[1], TERRACE_Y, p[2]))
		for _, bar in {
			{ Vector3.new(8, 1.2, 0.8), Vector3.new(0, 0.6, 3.6) },
			{ Vector3.new(8, 1.2, 0.8), Vector3.new(0, 0.6, -3.6) },
			{ Vector3.new(0.8, 1.2, 6.4), Vector3.new(3.6, 0.6, 0) },
			{ Vector3.new(0.8, 1.2, 6.4), Vector3.new(-3.6, 0.6, 0) },
		} do
			Art.block(folder, "TrampolineFrame", bar[1], base * CFrame.new(bar[2]), "toy_block", { color = C.Blue })
		end
		local mat = Art.block(folder, "Trampoline", Vector3.new(6.4, 0.4, 6.4), base * CFrame.new(0, 0.8, 0), "plain", {
			color = C.InkSoft,
		})
		mat:SetAttribute("LaunchY", 110)
		local spring = Instance.new("Decal")
		spring.Name = "Spring"
		spring.Face = Enum.NormalId.Top
		spring.Texture = Assets.icon("arrow_jump")
		spring.Parent = mat
	end
end

-- Decoration (edges only) ----------------------------------------------------------------------------------------

-- Post-and-rail fence along a polyline (posts at most 8 apart, two rails per straight run).
local function fence(parent: Instance, at: At, points: { Vector2 })
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		local n = math.max(1, math.ceil(len / 8))
		for k = (if i == 1 then 0 else 1), n do
			local p = a:Lerp(b, k / n)
			Art.block(parent, "FencePost", Vector3.new(1, 3, 1), CFrame.new(at(p.X, 1.5, p.Y)), "wood", { u = 4, v = 4 })
		end
		for _, y in { 1.3, 2.5 } do
			beam(parent, "FenceRail", at(a.X, y, a.Y), at(b.X, y, b.Y), 0.45, "wood_rail")
		end
	end
end

local function rock(parent: Instance, at: At, x: number, y: number, z: number, s: number, yaw: number)
	local base = CFrame.new(at(x, y, z)) * CFrame.Angles(0, yaw, 0)
	Art.block(parent, "Rock", Vector3.new(2.6, 1.8, 2.2) * s, base * CFrame.new(0, 0.9 * s, 0), "stone_all")
	Art.block(
		parent,
		"Rock",
		Vector3.new(1.6, 1.2, 1.4) * s,
		base * CFrame.new(0.6 * s, 2.1 * s, -0.3 * s) * CFrame.Angles(0, 0.6, 0),
		"stone_all",
		{ color = W.StoneDark }
	)
end

local function umbrella(parent: Instance, at: At, x: number, z: number, towel: Color3)
	local base = CFrame.new(at(x, TERRACE_Y, z))
	Art.block(parent, "UmbrellaPole", Vector3.new(0.4, 6.4, 0.4), base * CFrame.new(0, 3.2, 0), "plain", { color = CREAM })
	for qx = 0, 1 do
		for qz = 0, 1 do
			Art.block(
				parent,
				"UmbrellaTop",
				Vector3.new(4, 0.6, 4),
				base * CFrame.new(qx * 4 - 2, 6.4, qz * 4 - 2),
				"plain",
				deco({ color = if (qx + qz) % 2 == 0 then C.Red else CREAM })
			)
		end
	end
	Art.block(parent, "Towel", Vector3.new(3, 0.1, 5), base * CFrame.new(3.4, 0.05, 0.6), "plain", deco({ color = towel }))
end

local function buildDecor(m: Model, at: At)
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	decor.Parent = m
	local rng = Random.new(4242)

	-- Palms on the terraces, block trees near the plateau corners.
	for _, p in { { -46, -61 }, { -22, -62 }, { 24, -62 }, { 48, -61 }, { 69, -36 }, { 69, 34 }, { -50, 61 }, { 52, 61 } } do
		Art.palm(decor, at(p[1], TERRACE_Y, p[2]), 1.3, rng)
	end
	for _, p in { { -58, -40 }, { 58, -40 }, { -58, 36 }, { 58, 36 }, { -30, -50 }, { 30, -50 } } do
		Art.tree(decor, at(p[1], 0, p[2]), 1, rng)
	end

	-- Fence along the plateau edge, open at the stairs (S, W, E) and in front of the PLAY arch.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local gapX = if sz > 0 then 18 else 6
			fence(decor, at, {
				Vector2.new(sx * gapX, sz * 55.2),
				Vector2.new(sx * 55.2, sz * 55.2),
				Vector2.new(sx * 55.2, sz * 47.2),
				Vector2.new(sx * 63.2, sz * 47.2),
				Vector2.new(sx * 63.2, sz * 6),
			})
		end
	end

	-- Flower clusters (1-stud cubes) along the edges.
	local petals = { C.Red, C.Yellow, C.Pink, CREAM }
	for _, p in { { -36, -48 }, { 36, -48 }, { -26, 48 }, { 26, 48 }, { -60, 14 }, { 60, 16 }, { -14, -50 }, { 14, -50 } } do
		for i = 1, 6 do
			local ox, oz = rng:NextInteger(-2, 2), rng:NextInteger(-2, 2)
			Art.block(
				decor,
				"Flower",
				Vector3.new(1, 1, 1),
				CFrame.new(at(p[1] + ox, 0.5, p[2] + oz)),
				"plain",
				deco({ color = petals[(i - 1) % #petals + 1] })
			)
		end
	end

	-- Rocks and beach umbrellas on the terraces.
	for _, r in { { -69, -48 }, { 69, 46 }, { -40, 61 }, { 58, -62 }, { -69, 46 }, { 69, -48 } } do
		rock(decor, at, r[1], TERRACE_Y, r[2], rng:NextNumber(0.9, 1.3), rng:NextNumber(0, math.pi))
	end
	umbrella(decor, at, -34, -61, C.Cyan)
	umbrella(decor, at, 36, -61, C.Pink)
	umbrella(decor, at, 69, -14, C.Purple)
end

-- Build ----------------------------------------------------------------------------------------------------------

function Lobby.build(center: Vector3): Model
	local origin = center
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local seaLocal = Config.SEA_LEVEL - center.Y -- the water surface, relative to the centre

	local m = Instance.new("Model")
	m.Name = "Lobby"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- clients always have the whole lobby

	buildIsland(m, at, seaLocal)
	buildDock(m, at, seaLocal)
	buildBoundary(m, at, seaLocal)
	buildPaths(m, at)
	buildSpawn(m, at)
	buildChest(m, at, -20, -18, "Daily")
	buildChest(m, at, 20, -18, "Group")
	buildPodium(m, at)
	buildShop(m, at)
	buildWheel(m, at)
	buildPlayZone(m, at)
	local boards = Instance.new("Model")
	boards.Name = "Boards"
	boards.Parent = m
	buildBoard(m, boards, at, "WinsBoardAnchor", -46, 24, "Top Wins", C.Gold, "trophy", "crown")
	buildBoard(m, boards, at, "LevelBoardAnchor", -44, 44, "Top Level", C.Cyan, "xp_star", nil)
	buildBoard(m, boards, at, "LeaderboardAnchor", 46, 24, "Top Solo", C.Orange, "stopwatch", "trophy")
	buildSoloPortal(m, at)
	buildLiveTv(m, at)
	buildTrampolines(m, at)
	buildDecor(m, at)

	m.WorldPivot = CFrame.new(center)
	return m
end

return Lobby
