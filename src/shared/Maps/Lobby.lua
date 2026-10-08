--[[
Party Dash: the permanent lobby island "Sunny Isle" (docs/v2/ART_BIBLE.md 6, GAME_DESIGN 1.7, ARCHITECTURE
"Lobby model contract"). Built ONCE by Core; every part comes from Shared.Art recipes.

	local model = Lobby.build(Config.LOBBY_CENTER)  -- Model "Lobby", NOT parented (Core parents it)

Coordinates below are studs from `center` (the grass top), +Z = north = toward the arena. Layout: a notched
128 x 112 grass plateau with a dirt cliff, a 10-stud terrace ring (sand S/E, grass N/W) whose dark cliff runs into
the sea, an invisible wading shelf just under the (opaque) water and invisible boundary walls at
Config.LOBBY_RADIUS, so nobody can leave the island or sink.

Contract (exact names; all direct children of the Model unless noted):
	Spawns           Folder, 12 parts on the spawn pad, all facing +Z (the PLAY square)
	PlayZone         30 x 0.4 x 30 pad at center + (0, 0, 36). Its TOP surface is center.Y + 0.4 (it lies on the
	                 grass). Child BillboardGui "ZoneBoard" (TextLabels "Count", "Timer"; the World client fills them)
	ZoneBorder       Model of 1-stud Neon bars around the pad (the World client colours them)
	WheelAnchor ShopAnchor DailyChestAnchor GroupChestAnchor SoloPortalAnchor   station anchors with prompts
	WatchAnchor      the live TV screen (24 x 13), SurfaceGui "Screen" with TextLabel "Main"
	WinsBoardAnchor (TOP WINS) LeaderboardAnchor (TOP SOLO) LevelBoardAnchor (TOP LEVEL): 16 x 10 boards whose
	                 Front face looks at the PLAY square (mount SurfaceGuis on Enum.NormalId.Front)
	Wheel            Model: "WheelDisc" (the rotating disc) and 16 Neon "Bulb" parts (attribute Index 1..16)
	DailyChest / GroupChest   Models with Neon "ReadyRing" parts and a "Lid"
	Podium           Model with "Podium1" / "Podium2" / "Podium3" blocks (tops are free for the winners)
	Trampoline       parts (attribute LaunchY) on the beach terrace
Every interactive station has a ProximityPrompt (attribute PD_Action = Shop | Wheel | Daily | Group | Solo | Watch)
on an Attachment "PromptPoint" of its anchor.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local Lobby = {}

Lobby.RADIUS = Config.LOBBY_RADIUS
Lobby.PLAY_ZONE_OFFSET = Vector3.new(0, 0, 36)
Lobby.PLAY_ZONE_SIZE = Vector3.new(30, 0.4, 30)
Lobby.PLAY_ZONE_TOP = 0.4 -- the PlayZone top surface is this far above center.Y
Lobby.SPAWN_PAD_OFFSET = Vector3.new(0, 0, -38)
Lobby.SPAWN_PAD_TOP = 0.2
Lobby.LAUNCH_Y = 110 -- trampoline launch speed (about a 31-stud bounce)

local C = Theme.Colors
local W = Theme.World
local V = Vector3.new

-- Walkable colours tuned for ART_BIBLE 4.3 rule 1 (S >= 0.45, V <= 0.90): Theme's Paver/Sand are too pale for floors.
local PAVER = Color3.fromRGB(222, 168, 100)
local PAVER_ALT = Color3.fromRGB(204, 150, 84)
local SAND = Color3.fromRGB(226, 186, 92)
local PAD_GOLD = C.Gold:Lerp(C.Ink, 0.12)
local CHECKER_WHITE = Color3.fromRGB(255, 250, 230)
local FLOWER_COLORS = { C.Red, C.Yellow, C.Pink, C.White }

local TERRACE_Y = -6
local GHOST = { collide = false, canQuery = false, canTouch = false } -- props you walk through

local function with(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	local out = table.clone(base)
	if extra then
		for k, v in extra do
			out[k] = v
		end
	end
	return out
end

-- ===== geometry helpers ==============================================================================

-- Axis-aligned block between two corners given relative to the lobby center.
local function box(parent: Instance, o: Vector3, name: string, min: Vector3, max: Vector3, recipe: string, opts: any?)
	return Art.block(parent, name, max - min, CFrame.new(o + (min + max) / 2), recipe, opts)
end

-- A station's local frame on the ground at (x, z), its front (-Z) looking at (tx, tz).
local function facing(o: Vector3, x: number, z: number, tx: number, tz: number): CFrame
	return CFrame.lookAt(o + V(x, 0, z), o + V(tx, 0, tz))
end

local function neon(part: BasePart, color: Color3, transparency: number?)
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0
	part.CastShadow = false
end

-- Invisible reference part other systems look up by name.
local function anchorPart(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	return Art.block(parent, name, size, cf, "plain", with(GHOST, { transparency = 1, castShadow = false }))
end

local function addPrompt(anchor: BasePart, action: string, actionText: string, objectText: string, offset: Vector3)
	local point = Instance.new("Attachment")
	point.Name = "PromptPoint"
	point.Position = offset
	point.Parent = anchor
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = action .. "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PD_Action", action)
	prompt.Parent = point
end

-- ===== world GUI helpers (FredokaOne + ink stroke, ART_BIBLE 8.2) =======================================

local function stroke(gui: GuiObject, thickness: number, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = C.Ink
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = gui
end

local function corner(gui: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = gui
end

local function gradient(gui: GuiObject, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = gui
end

-- Outlined text label. props: color, font, position, size, stroke, drop (ink copy offset below, for static text).
local function inkText(parent: Instance, name: string, text: string, props: { [string]: any }): TextLabel
	local size = props.size or UDim2.fromScale(1, 1)
	local position = props.position or UDim2.new()
	local function make(labelName: string, color: Color3, zIndex: number, shift: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = labelName
		label.BackgroundTransparency = 1
		label.Size = size
		label.Position = position + UDim2.fromScale(0, shift)
		label.FontFace = props.font or Theme.FontFace
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = color
		label.ZIndex = zIndex
		stroke(label, props.stroke or 3)
		label.Parent = parent
		return label
	end
	if props.drop then
		make(name .. "Drop", C.Ink, 2, size.Y.Scale * 0.06)
	end
	return make(name, props.color or C.White, 3, 0)
end

local function surface(part: BasePart, face: Enum.NormalId, name: string, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	return gui
end

local function image(parent: Instance, id: string, size: UDim2, position: UDim2): ImageLabel
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = id
	img.ScaleType = Enum.ScaleType.Fit
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = size
	img.Position = position
	img.ZIndex = 4
	img.Parent = parent
	return img
end

-- Floating station label (ref1 style): 12-stud wide BillboardGui above the prop.
local function stationLabel(
	adornee: BasePart,
	title: string,
	color: Color3,
	height: number,
	extra: { subtitle: string?, rainbow: boolean? }?
)
	local e = extra or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Size = UDim2.fromScale(12, if e.subtitle then 4.2 else 3)
	gui.StudsOffsetWorldSpace = V(0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local titleSize = if e.subtitle then UDim2.fromScale(1, 0.7) else UDim2.fromScale(1, 1)
	local label = inkText(gui, "Title", title, { color = color, size = titleSize, drop = true })
	if e.rainbow then
		label.TextColor3 = C.White
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.Red),
			ColorSequenceKeypoint.new(0.2, C.Orange),
			ColorSequenceKeypoint.new(0.4, C.Yellow),
			ColorSequenceKeypoint.new(0.6, C.Green),
			ColorSequenceKeypoint.new(0.8, C.Cyan),
			ColorSequenceKeypoint.new(1, C.Purple),
		})
		g.Parent = label
	end
	if e.subtitle then
		inkText(gui, "Subtitle", e.subtitle, {
			font = Theme.FontBodyHeavy,
			position = UDim2.fromScale(0, 0.72),
			size = UDim2.fromScale(1, 0.28),
			stroke = 2,
		})
	end
	gui.Parent = adornee
	return gui
end

-- ===== island ========================================================================================

-- Walkable grass block: dirt cliff body, a 1.5-stud grass lip overhanging 0.3, and the grass top plate.
local function grassBlock(m: Model, o: Vector3, x0: number, x1: number, z0: number, z1: number, top: number, bottom: number)
	box(m, o, "Cliff", V(x0, bottom, z0), V(x1, top - 1.5, z1), "dirt_cliff")
	box(m, o, "GrassLip", V(x0 - 0.3, top - 1.55, z0 - 0.3), V(x1 + 0.3, top - 0.05, z1 + 0.3), "grass_lip")
	box(m, o, "Grass", V(x0, top - 0.4, z0), V(x1, top, z1), "grass_top")
end

local function buildGround(m: Model, o: Vector3, sea: number)
	local ground = Instance.new("Model")
	ground.Name = "Ground"

	-- Plateau 128 x 112 with 8 x 8 notches: a centre block and two side blocks (no overlapping tops).
	grassBlock(ground, o, -56, 56, -56, 56, 0, -7.5)
	grassBlock(ground, o, -64, -56, -48, 48, 0, -7.5)
	grassBlock(ground, o, 56, 64, -48, 48, 0, -7.5)

	-- Terrace ring (10 wide at y -6): one dark cliff body into the sea, then the walkable strips.
	box(ground, o, "TerraceCliff", V(-74, sea - 0.5, -66), V(74, TERRACE_Y - 1.5, 66), "dirt_cliff_low")
	local function grassStrip(x0, x1, z0, z1)
		box(ground, o, "TerraceLip", V(x0 - 0.3, -7.55, z0 - 0.3), V(x1 + 0.3, -6.05, z1 + 0.3), "grass_lip")
		box(ground, o, "TerraceGrass", V(x0, -6.4, z0), V(x1, TERRACE_Y, z1), "grass_top")
	end
	local function sandStrip(x0, x1, z0, z1)
		box(ground, o, "TerraceSand", V(x0, -7.5, z0), V(x1, TERRACE_Y, z1), "sand", { color = SAND })
	end
	grassStrip(-74, 74, 56, 66) -- north (toward the arena)
	grassStrip(-74, -64, -56, 56) -- west
	sandStrip(-74, 74, -66, -56) -- south beach
	sandStrip(64, 74, -56, 56) -- east beach
	-- the plateau notches show the terrace
	box(ground, o, "TerraceGrass", V(-64, -7.5, 48), V(-56, TERRACE_Y, 56), "grass_top")
	box(ground, o, "TerraceGrass", V(56, -7.5, 48), V(64, TERRACE_Y, 56), "grass_top")
	sandStrip(-64, -56, -56, -48)
	sandStrip(56, 64, -56, -48)

	Art.foam(ground, o, 148, 132, Config.SEA_LEVEL)

	-- Wading shelf: invisible (the sea is opaque), collidable, top 1.6 under the water, covers everything inside
	-- the boundary walls so a step off the terrace is a splash into the shallows, never a fall.
	local shelf = box(ground, o, "Shelf", V(-98, sea - 6, -98), V(98, sea - 1.6, 98), "plain", { color = SAND })
	shelf.Transparency = 1
	shelf.CastShadow = false

	ground.Parent = m
end

-- Block stairs. `from` is where the top step starts (relative XZ), `dir` the walking-down direction (unit X or Z),
-- `tops` the step top heights; every step is `depth` deep and 8 wide, standing on `bottom`.
local function stairs(parent: Instance, o: Vector3, from: Vector2, dir: Vector2, tops: { number }, depth: number, bottom: number)
	local side = Vector2.new(-dir.Y, dir.X) * 4
	for i, top in tops do
		local a = from + dir * (depth * (i - 1)) - side
		local b = from + dir * (depth * i) + side
		box(
			parent,
			o,
			"Step",
			V(math.min(a.X, b.X), bottom, math.min(a.Y, b.Y)),
			V(math.max(a.X, b.X), top, math.max(a.Y, b.Y)),
			"paver",
			{ color = if i % 2 == 0 then PAVER_ALT else PAVER }
		)
	end
end

local function buildStairs(m: Model, o: Vector3, sea: number)
	local folder = Instance.new("Model")
	folder.Name = "Stairs"
	-- plateau -> terrace (rise 1.5 per step)
	local down = { -1.5, -3, -4.5 }
	stairs(folder, o, Vector2.new(0, -56), Vector2.new(0, -1), down, 2.5, -7.5)
	stairs(folder, o, Vector2.new(-64, -24), Vector2.new(-1, 0), down, 2.5, -7.5)
	stairs(folder, o, Vector2.new(64, -24), Vector2.new(1, 0), down, 2.5, -7.5)
	-- terrace -> wading shelf (the last step sits just above the water line)
	local wade = { -8, -10, -12, sea + 0.4 }
	stairs(folder, o, Vector2.new(-74, 8), Vector2.new(-1, 0), wade, 2, sea - 0.5)
	stairs(folder, o, Vector2.new(74, 8), Vector2.new(1, 0), wade, 2, sea - 0.5)
	-- south beach -> dock
	stairs(folder, o, Vector2.new(0, -66), Vector2.new(0, -1), { -7.4, -8.8, -10.2, -11.6 }, 1.8, sea - 0.5)
	folder.Parent = m
end

local function buildDock(m: Model, o: Vector3, sea: number)
	local dock = Instance.new("Model")
	dock.Name = "DockPier"
	local deckTop = sea + 1.2
	box(dock, o, "Dock", V(-4, deckTop - 0.6, -94), V(4, deckTop, -73.2), "wood")
	for _, z in { -76, -85, -93 } do
		for _, x in { -3.6, 3.6 } do
			box(dock, o, "DockPost", V(x - 0.6, sea - 0.5, z - 0.6), V(x + 0.6, deckTop + 1, z + 0.6), "trunk")
		end
	end
	dock.Parent = m
end

-- Invisible walls on a 24-gon whose inner faces sit at Config.LOBBY_RADIUS, from under the shelf to well above
-- any trampoline bounce.
local function buildBoundary(m: Model, o: Vector3, sea: number)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	local sides = 24
	local apothem = Config.LOBBY_RADIUS + 1 -- walls are 2 thick
	local width = 2 * (apothem + 1) * math.tan(math.pi / sides) + 0.5
	local y0, y1 = sea - 6, 46
	for k = 0, sides - 1 do
		local a = k * 2 * math.pi / sides
		local dir = V(math.cos(a), 0, math.sin(a))
		local center = o + dir * apothem + V(0, (y0 + y1) / 2, 0)
		Art.block(folder, "Wall", V(width, y1 - y0, 2), CFrame.lookAt(center, center + dir), "plain", {
			transparency = 1,
			castShadow = false,
			canTouch = false,
		})
	end
	folder.Parent = m
end

-- ===== spawn, paths, plaza ===========================================================================

local function buildSpawnPad(m: Model, o: Vector3)
	local padModel = Instance.new("Model")
	padModel.Name = "SpawnPad"
	local c = Lobby.SPAWN_PAD_OFFSET
	local top = Lobby.SPAWN_PAD_TOP
	box(padModel, o, "SpawnPaver", V(c.X - 12, -0.2, c.Z - 7), V(c.X + 12, top, c.Z + 7), "paver", { color = PAVER })
	-- wood trim around the pad
	box(padModel, o, "Trim", V(c.X - 13, -0.2, c.Z + 7), V(c.X + 13, 0.3, c.Z + 8), "wood_rail")
	box(padModel, o, "Trim", V(c.X - 13, -0.2, c.Z - 8), V(c.X + 13, 0.3, c.Z - 7), "wood_rail")
	box(padModel, o, "Trim", V(c.X - 13, -0.2, c.Z - 7), V(c.X - 12, 0.3, c.Z + 7), "wood_rail")
	box(padModel, o, "Trim", V(c.X + 12, -0.2, c.Z - 7), V(c.X + 13, 0.3, c.Z + 7), "wood_rail")
	-- the logo lies on the pad, upright for players looking north
	local logo = box(padModel, o, "Logo", V(c.X - 8, top, c.Z - 5), V(c.X + 8, top + 0.05, c.Z + 5), "plain", GHOST)
	logo.Transparency = 1
	logo.CastShadow = false
	local decal = Instance.new("Decal")
	decal.Name = "LogoDecal"
	decal.Face = Enum.NormalId.Top
	decal.Texture = Assets.Art.logo or ""
	decal.Parent = logo
	padModel.Parent = m

	-- 12 spawn points in two rows (behind and in front of the logo), all facing the PLAY square (+Z).
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	local i = 0
	for _, z in { c.Z - 5.5, c.Z + 5.5 } do
		for _, x in { -10, -6, -2, 2, 6, 10 } do
			i += 1
			local pos = o + V(c.X + x, top - 0.5, z)
			local spawnPart = Art.block(
				folder,
				("Spawn%02d"):format(i),
				V(3, 1, 3),
				CFrame.lookAt(pos, pos + Vector3.zAxis),
				"plain",
				with(GHOST, { transparency = 1, castShadow = false })
			)
			spawnPart:SetAttribute("Index", i)
		end
	end
	folder.Parent = m

	-- Fallback engine spawn for brand-new characters (invisible, no force field); Core places players itself.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "LobbySpawnLocation"
	spawnLocation.Anchored = true
	spawnLocation.Size = V(8, 0.2, 4)
	spawnLocation.CFrame = CFrame.lookAt(o + V(c.X, top - 0.1, c.Z), o + V(c.X, top - 0.1, c.Z + 10))
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.CanQuery = false
	spawnLocation.CanTouch = false
	spawnLocation.CastShadow = false
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = m
end

local function buildPaths(m: Model, o: Vector3)
	local folder = Instance.new("Model")
	folder.Name = "Paths"
	local function path(x0, x1, z0, z1)
		box(folder, o, "Path", V(x0, -0.1, z0), V(x1, 0.1, z1), "paver", { color = PAVER_ALT })
	end
	path(-4, 4, -56, -45) -- south stairs -> spawn pad
	path(-4, 4, -31, -9) -- spawn pad -> plaza
	path(-4, 4, 16, 21) -- plaza -> PLAY square
	path(-40, -12, 0, 8) -- plaza -> shop
	path(12, 43, 0, 8) -- plaza -> lucky wheel
	folder.Parent = m
end

local function buildPlaza(m: Model, o: Vector3)
	local plaza = Instance.new("Model")
	plaza.Name = "Plaza"
	Art.voxelDisc(plaza, CFrame.new(o + V(0, 0.2, 4)), 14, 4, 0.4, "paver", { color = PAVER, altColor = PAVER_ALT })
	plaza.Parent = m

	-- Winners podium facing the spawn (-Z): 2nd on the viewer's left, 3rd on the right.
	local podium = Instance.new("Model")
	podium.Name = "Podium"
	local steps = {
		{ rank = 1, x = 0, h = 3, color = C.Gold },
		{ rank = 2, x = 6, h = 2.2, color = C.Silver },
		{ rank = 3, x = -6, h = 1.6, color = C.Bronze },
	}
	for _, s in steps do
		local block = box(
			podium,
			o,
			"Podium" .. s.rank,
			V(s.x - 3, 0.2, 1),
			V(s.x + 3, 0.2 + s.h, 7),
			"toy_block",
			{ color = s.color }
		)
		local gui = surface(block, Enum.NormalId.Front, "Rank", 40)
		inkText(gui, "Number", tostring(s.rank), {
			size = UDim2.fromScale(0.5, 0.8),
			position = UDim2.fromScale(0.25, 0.1),
			stroke = 4,
			drop = true,
		})
	end
	podium.Parent = m
end

-- ===== stations ======================================================================================

local function buildChest(m: Model, o: Vector3, kind: string, x: number, z: number)
	local isGroup = kind == "Group"
	local chest = Instance.new("Model")
	chest.Name = kind .. "Chest"
	local spawnPad = Lobby.SPAWN_PAD_OFFSET
	local base = facing(o, x, z, spawnPad.X, spawnPad.Z) -- the lock faces the spawn
	local function at(lx, ly, lz)
		return base * CFrame.new(lx, ly, lz)
	end

	Art.block(chest, "Pedestal", V(9, 1, 9), at(0, 0.5, 0), "stone_top")
	-- glow ring around the pedestal (World client pulses it while the chest is claimable)
	local ringOpts = with(GHOST, { castShadow = false })
	local rings = {
		{ V(11, 0.3, 0.8), at(0, 0.15, -5.1) },
		{ V(11, 0.3, 0.8), at(0, 0.15, 5.1) },
		{ V(0.8, 0.3, 9.4), at(-5.1, 0.15, 0) },
		{ V(0.8, 0.3, 9.4), at(5.1, 0.15, 0) },
	}
	for _, r in rings do
		neon(Art.block(chest, "ReadyRing", r[1], r[2], "plain", ringOpts), C.Yellow, 0.6)
	end

	local bodyColor = if isGroup then C.Gold else W.Wood
	local lidColor = if isGroup then C.Gold:Lerp(C.Ink, 0.15) else W.WoodDark
	local bandColor = if isGroup then C.Blue else C.Gold
	local bodyRecipe = if isGroup then "toy_block" else "wood"
	Art.block(chest, "Body", V(7, 3.4, 5), at(0, 2.7, 0), bodyRecipe, { color = bodyColor })
	Art.block(chest, "Lid", V(7.2, 1.6, 5.2), at(0, 5.2, 0), bodyRecipe, { color = lidColor })
	for _, bx in { -2.3, 2.3 } do
		Art.block(chest, "Band", V(0.6, 5.1, 5.4), at(bx, 3.55, 0), "plain", { color = bandColor })
	end
	if isGroup then
		-- white star-like emblem (a diamond) on a blue plate
		Art.block(chest, "EmblemPlate", V(2.4, 2.4, 0.3), at(0, 3.6, -2.6), "plain", { color = C.Blue })
		Art.block(
			chest,
			"Emblem",
			V(1.4, 1.4, 0.3),
			at(0, 3.6, -2.75) * CFrame.Angles(0, 0, math.rad(45)),
			"plain",
			{ color = C.White }
		)
	else
		Art.block(chest, "Lock", V(1.2, 1.4, 0.4), at(0, 4.3, -2.7), "plain", { color = C.Gold })
		Art.block(chest, "Keyhole", V(0.3, 0.5, 0.1), at(0, 4.2, -2.95), "plain", { color = C.Ink })
	end
	chest.Parent = m

	local anchor = anchorPart(m, kind .. "ChestAnchor", V(7, 6, 5), at(0, 3.5, 0))
	addPrompt(anchor, kind, "Open", kind .. " Chest", V(0, -0.5, -4.5))
	if isGroup then
		stationLabel(anchor, "Group Chest", C.Cyan, 6.5, { subtitle = "Like + Join = FREE chest!" })
	else
		stationLabel(anchor, "Daily Chest", C.Yellow, 6)
	end
end

local function buildShop(m: Model, o: Vector3)
	local stall = Instance.new("Model")
	stall.Name = "ShopStall"
	local base = facing(o, -46, 4, 0, 4) -- front (-Z) looks east at the plaza
	local function at(lx, ly, lz)
		return base * CFrame.new(lx, ly, lz)
	end

	-- Sloped awning (15 degrees, front edge lower): its centre line is AWNING_Y at the stall centre.
	local AWNING_Y = 10.6
	local tilt = math.tan(math.rad(15))
	local function awningUnderside(lz: number): number
		return AWNING_Y + lz * tilt - 0.26
	end

	Art.block(stall, "Deck", V(18, 0.3, 12), at(0, 0.15, 0), "wood")
	for _, lx in { -8.4, 8.4 } do
		for _, lz in { -5.4, 5.4 } do
			local h = awningUnderside(lz) - 0.3
			Art.block(stall, "Post", V(1.2, h, 1.2), at(lx, 0.3 + h / 2, lz), "wood")
		end
	end
	local wallH = awningUnderside(5.8) - 0.3
	Art.block(stall, "BackWall", V(18, wallH, 0.8), at(0, 0.3 + wallH / 2, 5.8), "wood", { color = W.WoodDark })
	Art.block(stall, "Counter", V(14, 3.5, 3), at(0, 2.05, -3.6), "wood")
	Art.block(stall, "CounterTop", V(15, 0.4, 3.6), at(0, 4, -3.6), "wood", { color = W.WoodDark })

	-- 2-stud red/white stripes plus a scalloped valance hanging straight down from the front edge.
	local slope = CFrame.Angles(math.rad(-15), 0, 0)
	for i = 1, 9 do
		local lx = -9 + (i - 0.5) * 2
		local color = if i % 2 == 1 then C.Red else C.White
		Art.block(stall, "Awning", V(2, 0.5, 13.6), at(lx, AWNING_Y, 0) * slope, "plain", { color = color })
		local edge = (at(lx, AWNING_Y, 0) * slope * CFrame.new(0, -0.6, -6.6)).Position
		Art.block(stall, "Valance", V(2, 1, 0.4), CFrame.new(edge) * base.Rotation, "plain", {
			color = if i % 2 == 1 then C.White else C.Red,
		})
	end

	-- Sign standing on the awning: shop icon + "Shop".
	local signLz = -3
	local signY = AWNING_Y + signLz * tilt + 0.25 + 2
	local sign = Art.block(stall, "Sign", V(14, 4, 0.6), at(0, signY, signLz), "plain", { color = C.GreenDark })
	local gui = surface(sign, Enum.NormalId.Front, "SignFace", 40)
	local face = Instance.new("Frame")
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = C.White
	face.Parent = gui
	gradient(face, C.Green, C.GreenDark)
	corner(face, 0.18)
	stroke(face, 8, true)
	image(face, Assets.icon("shop"), UDim2.fromScale(0.3, 1.1), UDim2.fromScale(0.2, 0.5))
	inkText(face, "Title", "Shop", {
		position = UDim2.fromScale(0.36, 0.12),
		size = UDim2.fromScale(0.58, 0.76),
		stroke = 6,
		drop = true,
	})

	-- Counter props: a little pyramid of coin blocks and a bat.
	local coins = { { -5.2, 0 }, { -4, 0 }, { -2.8, 0 }, { -4.6, 1 }, { -3.4, 1 }, { -4, 2 } }
	for _, c in coins do
		Art.block(stall, "CoinBlock", V(1.1, 0.45, 1.1), at(c[1], 4.425 + c[2] * 0.45, -3.6), "plain", {
			color = C.Gold,
			collide = false,
		})
	end
	local batCf = at(3.5, 4.5, -3.6) * CFrame.Angles(0, math.rad(80), math.rad(90))
	Art.block(stall, "BatHandle", V(0.6, 3.6, 0.6), batCf, "wood", { collide = false })
	Art.block(stall, "BatGrip", V(0.7, 1.1, 0.7), batCf * CFrame.new(0, -1.5, 0), "plain", {
		color = Theme.Maps.Spin.batGrip,
		collide = false,
	})
	stall.Parent = m

	local anchor = anchorPart(m, "ShopAnchor", V(14, 4, 2), at(0, 3, -6.2))
	addPrompt(anchor, "Shop", "Shop", "Boost Shop", V(0, 0, -1.5))
	stationLabel(anchor, "Shop", C.Green, 15)
end

local function buildWheel(m: Model, o: Vector3)
	local wheel = Instance.new("Model")
	wheel.Name = "Wheel"
	local hub = o + V(46, 13, 4) -- wheel centre; the face looks -X at the plaza
	Art.block(wheel, "Base", V(6, 2, 10), CFrame.new(o + V(46.6, 1, 4)), "toy_block", { color = C.Red })
	-- A-frame behind the disc
	for _, dz in { -4.2, 4.2 } do
		local foot = o + V(47.8, 2, 4 + dz)
		local top = V(hub.X + 1.8, hub.Y, hub.Z)
		Art.block(
			wheel,
			"Leg",
			V(1, 1, (top - foot).Magnitude),
			CFrame.lookAt((foot + top) / 2, top),
			"wood",
			{ color = W.WoodDark }
		)
	end
	Art.block(wheel, "Axle", V(2.4, 1.2, 1.2), CFrame.new(hub + V(1.2, 0, 0)), "stone_all")

	local cylinder = { shape = Enum.PartType.Cylinder }
	Art.block(wheel, "Rim", V(1, 20.4, 20.4), CFrame.new(hub + V(0.9, 0, 0)), "plain", with(cylinder, { color = C.Gold }))
	local disc = Art.block(wheel, "WheelDisc", V(1.5, 18, 18), CFrame.new(hub), "plain", with(cylinder, { color = C.White }))
	local gui = surface(disc, Enum.NormalId.Left, "WheelFace", 30)
	image(gui, Assets.Art.wheel_face or "", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
	Art.block(wheel, "HubCap", V(0.6, 2.6, 2.6), CFrame.new(hub - V(1.05, 0, 0)), "plain", with(cylinder, { color = C.Gold }))

	-- 16 Neon bulbs on the gold rim (the World client chases them).
	for i = 1, 16 do
		local a = (i - 1) / 16 * 2 * math.pi
		local pos = hub + V(0.2, math.cos(a) * 9.6, math.sin(a) * 9.6)
		local bulb = Art.block(wheel, "Bulb", V(0.8, 0.8, 0.8), CFrame.new(pos), "plain", {
			shape = Enum.PartType.Ball,
			collide = false,
			canQuery = false,
			canTouch = false,
		})
		neon(bulb, if i % 2 == 1 then C.Yellow else C.White)
		bulb:SetAttribute("Index", i)
	end
	-- Red pointer wedge at 12 o'clock, pointing down into the wheel.
	local pointerCf = CFrame.new(hub + V(-1.1, 9.9, 0)) * CFrame.Angles(math.rad(45), 0, 0)
	Art.block(wheel, "Pointer", V(0.8, 2, 2), pointerCf, "plain", { color = C.Red })
	Art.block(wheel, "PointerPin", V(0.9, 0.9, 0.9), CFrame.new(hub + V(-1.2, 10.9, 0)), "plain", { color = C.Gold })
	wheel.Parent = m

	local anchor = anchorPart(m, "WheelAnchor", V(2, 4, 10), CFrame.lookAt(o + V(41, 3, 4), o + V(0, 3, 4)))
	addPrompt(anchor, "Wheel", "Spin", "Lucky Wheel", V(0, 0, -1))
	stationLabel(anchor, "Lucky Wheel", C.White, 22, { rainbow = true })
end

local function buildPlayZone(m: Model, o: Vector3)
	local c = Lobby.PLAY_ZONE_OFFSET
	local size = Lobby.PLAY_ZONE_SIZE
	local half = size.X / 2
	local zone = box(
		m,
		o,
		"PlayZone",
		V(c.X - half, 0, c.Z - half),
		V(c.X + half, Lobby.PLAY_ZONE_TOP, c.Z + half),
		"checker_pad",
		{ color = PAD_GOLD }
	)
	-- white squares of the gold / white checker (5-stud squares, a hair above the pad)
	for ix = 0, 5 do
		for iz = 0, 5 do
			if (ix + iz) % 2 == 0 then
				local x0, z0 = c.X - half + ix * 5, c.Z - half + iz * 5
				box(m, o, "Checker", V(x0, 0.35, z0), V(x0 + 5, 0.45, z0 + 5), "plain", with(GHOST, {
					color = CHECKER_WHITE,
					castShadow = false,
				}))
			end
		end
	end

	-- 1-stud Neon frame; the World client turns it green while counting and flashes it yellow at the end.
	local border = Instance.new("Model")
	border.Name = "ZoneBorder"
	local bars = {
		{ V(c.X - half - 1, 0, c.Z + half), V(c.X + half + 1, 0.5, c.Z + half + 1) },
		{ V(c.X - half - 1, 0, c.Z - half - 1), V(c.X + half + 1, 0.5, c.Z - half) },
		{ V(c.X - half - 1, 0, c.Z - half), V(c.X - half, 0.5, c.Z + half) },
		{ V(c.X + half, 0, c.Z - half), V(c.X + half + 1, 0.5, c.Z + half) },
	}
	for _, b in bars do
		local bar = box(border, o, "Border", b[1], b[2], "plain", GHOST)
		neon(bar, C.White, 0.1)
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "ZoneSparkles"
		sparkles.Enabled = false
		sparkles.Rate = 5
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(3, 6)
		sparkles.SpreadAngle = Vector2.new(10, 10)
		sparkles.EmissionDirection = Enum.NormalId.Top
		sparkles.LightEmission = 0.8
		sparkles.Color = ColorSequence.new(C.Green)
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Parent = bar
	end
	border.Parent = m

	-- Live board above the pad: "3/12 READY" + "0:14" (texts filled by the World client from GameState).
	local board = Instance.new("BillboardGui")
	board.Name = "ZoneBoard"
	board.Size = UDim2.fromScale(16, 6.4)
	board.StudsOffsetWorldSpace = V(0, 12, 0)
	board.LightInfluence = 0
	board.MaxDistance = 260
	board.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = C.PanelDeep
	pill.BackgroundTransparency = 0.15
	pill.Parent = board
	corner(pill, 0.3)
	stroke(pill, 3, true)
	inkText(pill, "Count", ("0/%d READY"):format(Config.MAX_PLAYERS), {
		position = UDim2.fromScale(0.06, 0.08),
		size = UDim2.fromScale(0.88, 0.36),
	})
	inkText(pill, "Timer", "STEP IN!", {
		font = Theme.FontHype,
		color = C.Yellow,
		position = UDim2.fromScale(0.06, 0.44),
		size = UDim2.fromScale(0.88, 0.5),
		stroke = 4,
	})
	board.Parent = zone

	-- PLAY arch on the north edge: red/white block pillars, a red beam and the PLAY board facing the spawns.
	local arch = Instance.new("Model")
	arch.Name = "PlayArch"
	local archZ = c.Z + half + 2
	for _, px in { -18.5, 18.5 } do
		for k = 0, 7 do
			Art.block(arch, "Pillar", V(3, 2, 3), CFrame.new(o + V(px, 1 + k * 2, archZ)), "toy_block", {
				color = if k % 2 == 0 then C.Red else C.White,
			})
		end
	end
	Art.block(arch, "Beam", V(40, 3, 3), CFrame.new(o + V(0, 17.5, archZ)), "toy_block", { color = C.Red })
	local playBoard = Art.block(arch, "PlayBoard", V(24, 6.5, 1), CFrame.new(o + V(0, 22.25, archZ)), "plain", {
		color = C.GreenDark,
	})
	for _, faceId in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = surface(playBoard, faceId, "PlaySign", 40)
		local face = Instance.new("Frame")
		face.Size = UDim2.fromScale(1, 1)
		face.BackgroundColor3 = C.White
		face.Parent = gui
		gradient(face, C.Green, C.GreenDark)
		corner(face, 0.16)
		stroke(face, 10, true)
		inkText(face, "Title", "PLAY", {
			position = UDim2.fromScale(0.1, 0.08),
			size = UDim2.fromScale(0.8, 0.8),
			stroke = 6,
			drop = true,
		})
	end
	arch.Parent = m
end

-- Leaderboard frame around a 16 x 10 anchor face that looks at (0, 30).
local function buildBoard(m: Model, o: Vector3, spec: { [string]: any })
	local frame = Instance.new("Model")
	frame.Name = (spec.anchor:gsub("Anchor$", ""))
	local base = facing(o, spec.x, spec.z, 0, 30)
	local function at(lx, ly, lz)
		return base * CFrame.new(lx, ly, lz)
	end
	for _, lx in { -9.6, 9.6 } do
		Art.block(frame, "Post", V(1.2, 15.6, 1.2), at(lx, 7.8, 0.7), "wood")
	end
	Art.block(frame, "BackPanel", V(19, 12.6, 0.6), at(0, 8.3, 0.6), "wood", { color = W.WoodDark })
	local header = Art.block(frame, "Header", V(20, 3, 1.2), at(0, 15.6, 0.4), "toy_block", { color = spec.color })
	local gui = surface(header, Enum.NormalId.Front, "HeaderFace", 40)
	image(gui, Assets.icon(spec.icon), UDim2.fromScale(0.16, 0.92), UDim2.fromScale(0.5, 0.5))
	if spec.crown then
		Art.block(frame, "CrownBase", V(5, 1, 1.6), at(0, 17.6, 0.4), "plain", { color = C.Gold })
		for _, lx in { -2, 0, 2 } do
			Art.block(frame, "CrownSpike", V(1, 1.4, 1), at(lx, 18.8, 0.4), "plain", { color = C.Gold })
		end
		Art.block(frame, "CrownGem", V(0.8, 0.8, 0.3), at(0, 17.6, -0.45), "plain", { color = C.Red })
	end
	frame.Parent = m

	local anchor = Art.block(m, spec.anchor, V(16, 10, 0.4), at(0, 8, 0), "plain", { color = C.Panel })
	stationLabel(anchor, spec.title, spec.labelColor, 11.5)
end

local function buildTV(m: Model, o: Vector3)
	local tv = Instance.new("Model")
	tv.Name = "LiveTV"
	local base = facing(o, 30, 42, 0, 30)
	local function at(lx, ly, lz)
		return base * CFrame.new(lx, ly, lz)
	end
	for _, lx in { -11.5, 11.5 } do
		Art.block(tv, "Post", V(1.4, 10, 1.4), at(lx, 5, 1.1), "stone_all")
	end
	Art.block(tv, "Bezel", V(26, 15, 1), at(0, 10, 0.6), "plain", { color = C.InkSoft })
	Art.block(tv, "TopTrim", V(26.4, 1, 1.4), at(0, 18, 0.5), "toy_block", { color = C.Red })
	tv.Parent = m

	local screenPart = Art.block(m, "WatchAnchor", V(24, 13, 0.4), at(0, 10, 0), "plain", { color = C.Ink })
	local screen = surface(screenPart, Enum.NormalId.Front, "Screen", 40)
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.White
	bg.Parent = screen
	gradient(bg, C.PanelLight, C.PanelDeep)
	local live = Instance.new("Frame")
	live.Name = "LiveTag"
	live.Size = UDim2.fromScale(0.18, 0.13)
	live.Position = UDim2.fromScale(0.04, 0.06)
	live.BackgroundColor3 = C.Red
	live.Visible = false
	live.Parent = bg
	corner(live, 0.5)
	stroke(live, 4, true)
	inkText(live, "Text", "LIVE", { position = UDim2.fromScale(0.1, 0.1), size = UDim2.fromScale(0.8, 0.8) })
	image(bg, Assets.icon("spectate_eye"), UDim2.fromScale(0.12, 0.2), UDim2.fromScale(0.92, 0.13))
	inkText(bg, "Main", "NEXT GAME SOON", {
		position = UDim2.fromScale(0.05, 0.3),
		size = UDim2.fromScale(0.9, 0.36),
		stroke = 5,
	})
	inkText(bg, "Sub", "Step on the PLAY pad!", {
		font = Theme.FontBodyHeavy,
		color = C.Muted,
		position = UDim2.fromScale(0.1, 0.72),
		size = UDim2.fromScale(0.8, 0.16),
	})
	addPrompt(screenPart, "Watch", "Watch", "Live TV", V(0, -7, -3))
	stationLabel(screenPart, "Live TV", C.Red, 10)
end

local function buildSoloPortal(m: Model, o: Vector3)
	local portal = Instance.new("Model")
	portal.Name = "SoloPortal"
	local base = facing(o, -42, -38, 0, -20)
	local function at(lx, ly, lz)
		return base * CFrame.new(lx, ly, lz)
	end
	Art.block(portal, "Platform", V(16, 1, 6), at(0, 0.5, 0), "stone_top")
	for _, lx in { -7, 7 } do
		Art.block(portal, "Pillar", V(2, 14, 2), at(lx, 8, 0), "stone_all")
	end
	Art.block(portal, "Lintel", V(16, 2, 2.4), at(0, 16, 0), "stone_all")
	Art.block(portal, "Cap", V(16.4, 1, 2.8), at(0, 17.5, 0), "toy_block", { color = C.Purple })
	local face = Art.block(portal, "PortalFace", V(12, 14, 0.4), at(0, 8, 0), "plain", with(GHOST, {
		color = C.Purple,
		transparency = 0.2,
		castShadow = false,
	}))
	for _, faceId in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = surface(face, faceId, "Swirl", 20)
		local swirl = Instance.new("Frame")
		swirl.Size = UDim2.fromScale(1, 1)
		swirl.BackgroundColor3 = C.White
		swirl.BackgroundTransparency = 0.15
		swirl.Parent = gui
		gradient(swirl, C.Pink, C.PurpleDark)
		image(swirl, Assets.icon("stopwatch"), UDim2.fromScale(0.6, 0.45), UDim2.fromScale(0.5, 0.5))
	end
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "PortalSparkles"
	sparkles.Rate = 6
	sparkles.Lifetime = NumberRange.new(1, 1.6)
	sparkles.Speed = NumberRange.new(1, 2.5)
	sparkles.LightEmission = 0.7
	sparkles.Color = ColorSequence.new(C.White, C.Pink)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Parent = face
	portal.Parent = m

	local anchor = anchorPart(m, "SoloPortalAnchor", V(12, 14, 1), at(0, 8, 0))
	addPrompt(anchor, "Solo", "Solo", "Solo Run", V(0, -5, -3))
	stationLabel(anchor, "Solo Run", C.Purple, 12)
end

local function buildTrampolines(m: Model, o: Vector3)
	local folder = Instance.new("Model")
	folder.Name = "Trampolines"
	for _, spot in { V(-30, TERRACE_Y, -61), V(30, TERRACE_Y, -61), V(69, TERRACE_Y, -40) } do
		local g = o + spot
		Art.block(folder, "TrampolineBase", V(7, 1.2, 7), CFrame.new(g + V(0, 0.6, 0)), "toy_block", {
			color = C.Red,
		})
		local mat = Art.block(folder, "Trampoline", V(5.4, 0.3, 5.4), CFrame.new(g + V(0, 1.35, 0)), "plain", {
			color = C.PurpleDark,
		})
		mat:SetAttribute("LaunchY", Lobby.LAUNCH_Y)
		local chevron = Instance.new("Decal")
		chevron.Name = "Chevron"
		chevron.Face = Enum.NormalId.Top
		chevron.Texture = Assets.icon("arrow_jump")
		chevron.Parent = mat
		local ring = {
			{ V(6.4, 0.2, 0.5), V(0, 1.3, 2.95) },
			{ V(6.4, 0.2, 0.5), V(0, 1.3, -2.95) },
			{ V(0.5, 0.2, 5.4), V(2.95, 1.3, 0) },
			{ V(0.5, 0.2, 5.4), V(-2.95, 1.3, 0) },
		}
		for _, r in ring do
			neon(Art.block(folder, "TrampolineRing", r[1], CFrame.new(g + r[2]), "plain", GHOST), C.Lime)
		end
	end
	folder.Parent = m
end

-- ===== decor (edges only) ============================================================================

-- Post-and-rail fence along the plateau edge (0.75 inside it), with gaps at the stairs and the PLAY arch.
local function buildFence(m: Model, o: Vector3)
	local fence = Instance.new("Model")
	fence.Name = "Fence"
	local e = 0.75
	local lines = {
		{ Vector2.new(-24, 56 - e), Vector2.new(-56 + e, 56 - e), Vector2.new(-56 + e, 48 - e), Vector2.new(-64 + e, 48 - e), Vector2.new(-64 + e, -19) },
		{ Vector2.new(-64 + e, -29), Vector2.new(-64 + e, -48 + e), Vector2.new(-56 + e, -48 + e), Vector2.new(-56 + e, -56 + e), Vector2.new(-5, -56 + e) },
		{ Vector2.new(5, -56 + e), Vector2.new(56 - e, -56 + e), Vector2.new(56 - e, -48 + e), Vector2.new(64 - e, -48 + e), Vector2.new(64 - e, -29) },
		{ Vector2.new(64 - e, -19), Vector2.new(64 - e, 48 - e), Vector2.new(56 - e, 48 - e), Vector2.new(56 - e, 56 - e), Vector2.new(24, 56 - e) },
	}
	local function post(p: Vector2)
		Art.block(fence, "FencePost", V(1, 3, 1), CFrame.new(o + V(p.X, 1.5, p.Y)), "wood")
	end
	for _, line in lines do
		post(line[1])
		for i = 2, #line do
			local a, b = line[i - 1], line[i]
			local len = (b - a).Magnitude
			local n = math.max(1, math.ceil(len / 6))
			for k = 1, n do
				post(a + (b - a) * (k / n))
			end
			local mid = (a + b) / 2
			for _, y in { 1.2, 2.3 } do
				local center = o + V(mid.X, y, mid.Y)
				local to = o + V(b.X, y, b.Y)
				Art.block(fence, "Rail", V(0.4, 0.5, len), CFrame.lookAt(center, to), "wood_rail")
			end
		end
	end
	fence.Parent = m
end

local function umbrella(parent: Instance, ground: Vector3)
	Art.block(parent, "UmbrellaPole", V(0.5, 8, 0.5), CFrame.new(ground + V(0, 4, 0)), "wood")
	for _, q in { { -2, -2, C.Red }, { 2, 2, C.Red }, { -2, 2, C.White }, { 2, -2, C.White } } do
		Art.block(parent, "UmbrellaTop", V(4, 0.6, 4), CFrame.new(ground + V(q[1], 8.2, q[2])), "plain", {
			color = q[3],
		})
	end
end

local function flowerCluster(parent: Instance, ground: Vector3, rng: Random)
	local used = {}
	for i = 1, 7 do
		local dx, dz = rng:NextInteger(-2, 2), rng:NextInteger(-2, 2)
		local key = dx .. ":" .. dz
		if not used[key] then
			used[key] = true
			local h = if i % 3 == 0 then 1.4 else 1
			Art.block(parent, "Flower", V(1, h, 1), CFrame.new(ground + V(dx, h / 2, dz)), "plain", with(GHOST, {
				color = FLOWER_COLORS[(i - 1) % #FLOWER_COLORS + 1],
			}))
		end
	end
end

local function buildDecor(m: Model, o: Vector3, sea: number)
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	local rng = Random.new(3402026)
	-- palms on the terraces
	local palms = {
		V(-14, TERRACE_Y, -62),
		V(14, TERRACE_Y, -62),
		V(-50, TERRACE_Y, -61),
		V(50, TERRACE_Y, -61),
		V(69, TERRACE_Y, -6),
		V(69, TERRACE_Y, 32),
		V(-69, TERRACE_Y, -40),
		V(-69, TERRACE_Y, 32),
	}
	for _, p in palms do
		Art.palm(decor, o + p, 1.25, rng)
	end
	-- block trees at the plateau corners and sides
	for _, p in { V(-51, 0, 51), V(51, 0, 51), V(-54, 0, -50), V(54, 0, -50), V(-58, 0, -12), V(58, 0, -12) } do
		Art.tree(decor, o + p, 1.1, rng)
	end
	-- flower clusters
	local flowers = {
		V(-17, 0, -34),
		V(17, 0, -34),
		V(-19, 0, 13),
		V(19, 0, 13),
		V(-32, 0, -14),
		V(32, 0, -14),
		V(40, 0, -40),
		V(-26, 0, -47),
	}
	for _, p in flowers do
		flowerCluster(decor, o + p, rng)
	end
	-- grey rocks: three on the beach terraces, three in the shallows
	for _, p in { V(-40, TERRACE_Y, -64), V(40, TERRACE_Y, -64), V(-71, TERRACE_Y, 18) } do
		Art.rock(decor, o + p, 0.5, rng)
	end
	for _, p in { V(-40, sea, -78), V(52, sea, -74), V(-84, sea, -30) } do
		Art.rock(decor, o + p, 0.8, rng)
	end
	-- beach umbrellas
	for _, p in { V(-62, TERRACE_Y, -61), V(62, TERRACE_Y, -61), V(69, TERRACE_Y, 18) } do
		umbrella(decor, o + p)
	end
	decor.Parent = m
end

-- ===== build =========================================================================================

function Lobby.build(center: Vector3?): Model
	local o = center or Config.LOBBY_CENTER
	local sea = Config.SEA_LEVEL - o.Y -- relative sea surface (-14 for the default layout)
	local m = Instance.new("Model")
	m.Name = "Lobby"

	buildGround(m, o, sea)
	buildStairs(m, o, sea)
	buildDock(m, o, sea)
	buildBoundary(m, o, sea)
	buildSpawnPad(m, o)
	buildPaths(m, o)
	buildPlaza(m, o)
	buildChest(m, o, "Daily", -20, -18)
	buildChest(m, o, "Group", 20, -18)
	buildShop(m, o)
	buildWheel(m, o)
	buildPlayZone(m, o)
	buildBoard(m, o, {
		anchor = "WinsBoardAnchor",
		title = "Top Wins",
		x = -48,
		z = 34,
		color = C.Gold,
		labelColor = C.Gold,
		icon = "trophy",
		crown = true,
	})
	buildBoard(m, o, {
		anchor = "LevelBoardAnchor",
		title = "Top Level",
		x = -30,
		z = 42,
		color = C.Blue,
		labelColor = C.Cyan,
		icon = "xp_star",
	})
	buildBoard(m, o, {
		anchor = "LeaderboardAnchor",
		title = "Top Solo",
		x = 48,
		z = 34,
		color = C.Orange,
		labelColor = C.Orange,
		icon = "stopwatch",
	})
	buildTV(m, o)
	buildSoloPortal(m, o)
	buildTrampolines(m, o)
	buildFence(m, o)
	buildDecor(m, o, sea)

	m.WorldPivot = CFrame.new(o)
	return m
end

return Lobby
