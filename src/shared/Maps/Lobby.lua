--[[
Party Dash: the lobby island, built by Core at Config.LOBBY_CENTER between rounds.

	local model = Lobby.build(center: Vector3?)  -- returns an unparented Model named "Lobby"

The Model contains:
	Folder "Spawns"            -- invisible BaseParts facing the big sign (players are placed on them)
	Part "LeaderboardAnchor"   -- 16x10 anchored panel facing the spawns; Solo Record mounts its TOP 10 here
	Folder "Boundary"          -- invisible walls so nobody can fall off
	plus the tiles, the "PARTY DASH" sign, a rainbow and plenty of candy decorations.
The top surface of the tiles is at center.Y. Positive Z is "toward the sign".
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local Lobby = {}

Lobby.RADIUS = 60 -- walkable radius (walls sit just outside)
Lobby.SIGN_Z = 46

local C = Theme.Colors
local PAL = Theme.MapPalette
local GRASS = Color3.fromRGB(110, 215, 95)
local DIRT = { Color3.fromRGB(176, 112, 70), Color3.fromRGB(150, 92, 58), Color3.fromRGB(122, 74, 48) }
local RAINBOW = {
	Color3.fromRGB(255, 80, 90),
	Color3.fromRGB(255, 160, 50),
	Color3.fromRGB(255, 220, 70),
	Color3.fromRGB(100, 220, 110),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(170, 110, 255),
}

-- Helpers -------------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Vertical cylinder with its top face at `top`.
local function disc(parent: Instance, name: string, top: Vector3, height: number, radius: number, color: Color3): Part
	local p = part(
		parent,
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3): Part
	local p = part(parent, name, Vector3.one * diameter, CFrame.new(center), color)
	p.Shape = Enum.PartType.Ball
	return p
end

local function ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3): Part
	local p = part(parent, name, size, cf, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function noCollide(p: BasePart)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
end

local function stroke(label: TextLabel, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = C.Ink
	s.Thickness = thickness
	s.Parent = label
end

local function surface(p: BasePart, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.Parent = p
	return gui
end

local function label(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, strokeSize: number)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.FontFace = Theme.FontFace
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.Parent = parent
	stroke(l, strokeSize)
	return l
end

-- Pieces ----------------------------------------------------------------------------------------------

local function buildGround(m: Model, o: Vector3)
	local ground = Instance.new("Model")
	ground.Name = "Ground"

	-- Grass rim, white grout disc, then the colorful tiles on top.
	disc(ground, "Grass", o - Vector3.new(0, 0.6, 0), 4, Lobby.RADIUS + 4, GRASS)
	disc(ground, "Grout", o - Vector3.new(0, 0.25, 0), 1, 57.5, C.White)
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = ground
	local size = 8
	for gx = -7, 7 do
		for gz = -7, 7 do
			local x, z = gx * size, gz * size
			local d = math.sqrt(x * x + z * z)
			if d <= 52 then
				local ring = math.floor(d / 12)
				local color = PAL[ring % #PAL + 1]
				if (gx + gz) % 2 == 0 then
					color = color:Lerp(C.White, 0.22)
				end
				part(
					tiles,
					"Tile",
					Vector3.new(size - 0.4, 1, size - 0.4),
					CFrame.new(o + Vector3.new(x, -0.5, z)),
					color
				)
			end
		end
	end

	-- Layered dirt underneath: a cartoon floating island.
	local r = Lobby.RADIUS + 3
	local y = o.Y - 4.6
	for i, color in DIRT do
		local h = 9 - i
		disc(ground, "Dirt", Vector3.new(o.X, y, o.Z), h, r, color)
		y -= h
		r *= 0.7
	end
	disc(ground, "Tip", Vector3.new(o.X, y, o.Z), 6, r * 0.55, DIRT[3])

	-- Candy bead border.
	local beads = 40
	for i = 0, beads - 1 do
		local a = i / beads * math.pi * 2
		local pos = o + Vector3.new(math.cos(a) * (Lobby.RADIUS + 1.5), 1.2, math.sin(a) * (Lobby.RADIUS + 1.5))
		ball(ground, "Bead", pos, 3.2, if i % 2 == 0 then C.Pink else C.Yellow)
	end

	-- Start pad under the spawns.
	disc(ground, "StartPad", o + Vector3.new(0, 0.12, -16), 0.24, 15, C.Yellow)
	disc(ground, "StartPadInner", o + Vector3.new(0, 0.16, -16), 0.24, 13, C.White)
	ground.Parent = m
end

local function buildSign(m: Model, o: Vector3)
	local sign = Instance.new("Model")
	sign.Name = "Sign"
	local z = Lobby.SIGN_Z
	local boardCenter = o + Vector3.new(0, 26, z)

	-- Candy-cane posts.
	for _, x in { -30, 30 } do
		for i = 0, 6 do
			local p = part(
				sign,
				"Post",
				Vector3.new(4.4, 4.4, 4.4),
				CFrame.new(o + Vector3.new(x, 2.2 + i * 4.4, z + 0.5)) * CFrame.Angles(0, 0, math.pi / 2),
				if i % 2 == 0 then C.White else C.Red
			)
			p.Shape = Enum.PartType.Cylinder
		end
		ball(sign, "PostTop", o + Vector3.new(x, 33.5, z + 0.5), 6, C.Yellow)
	end

	-- Board with a thick yellow frame.
	local board = part(sign, "Board", Vector3.new(60, 18, 2), CFrame.new(boardCenter), C.Panel)
	part(sign, "FrameTop", Vector3.new(62, 1.6, 2.6), CFrame.new(boardCenter + Vector3.new(0, 9.4, 0)), C.Yellow)
	part(sign, "FrameBottom", Vector3.new(62, 1.6, 2.6), CFrame.new(boardCenter - Vector3.new(0, 9.4, 0)), C.Yellow)
	part(sign, "FrameLeft", Vector3.new(1.6, 20.4, 2.6), CFrame.new(boardCenter - Vector3.new(30.2, 0, 0)), C.Yellow)
	part(sign, "FrameRight", Vector3.new(1.6, 20.4, 2.6), CFrame.new(boardCenter + Vector3.new(30.2, 0, 0)), C.Yellow)
	for _, corner in
		{
			Vector3.new(-30.2, 9.4, 0),
			Vector3.new(30.2, 9.4, 0),
			Vector3.new(-30.2, -9.4, 0),
			Vector3.new(30.2, -9.4, 0),
		}
	do
		ball(sign, "Stud", boardCenter + corner - Vector3.new(0, 0, 1.4), 2.6, C.Pink)
	end

	-- Title text on both faces (Front faces the spawns).
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = surface(board, face, 24)
		local title = label(
			gui,
			string.upper(Config.GAME_NAME),
			UDim2.fromScale(0.03, 0.04),
			UDim2.fromScale(0.94, 0.66),
			C.White,
			7
		)
		title.Name = "Title"
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(C.Yellow, C.Orange)
		gradient.Rotation = 90
		gradient.Parent = title
		local sub =
			label(gui, "LAST ONE STANDING WINS!", UDim2.fromScale(0.1, 0.7), UDim2.fromScale(0.8, 0.24), C.Cyan, 4)
		sub.Name = "Subtitle"
	end

	-- Balloon bunches tied to the posts.
	local colors = { C.Pink, C.Cyan, C.Purple, C.Green, C.Orange, C.Red }
	for side, x in { -30, 30 } do
		for i = 1, 3 do
			local offset = Vector3.new((i - 2) * 3.4 + (if side == 1 then -2 else 2), 9 + (i % 2) * 2.5, 0)
			local top = o + Vector3.new(x, 33.5, z) + offset
			local b =
				ellipsoid(sign, "Balloon", CFrame.new(top), Vector3.new(4.5, 5.5, 4.5), colors[(side - 1) * 3 + i])
			b.Material = Enum.Material.Glass
			b.Reflectance = 0.1
			local from = o + Vector3.new(x, 34, z)
			local to = top - Vector3.new(0, 2.8, 0)
			local string_ = part(
				sign,
				"String",
				Vector3.new(0.12, 0.12, (to - from).Magnitude),
				CFrame.lookAt((from + to) / 2, to),
				C.White
			)
			noCollide(string_)
			noCollide(b)
		end
	end
	sign.Parent = m
end

local function buildRainbow(m: Model, o: Vector3)
	local rainbow = Instance.new("Model")
	rainbow.Name = "Rainbow"
	local center = o + Vector3.new(0, 4, Lobby.SIGN_Z + 12)
	local segments = 22
	for band, color in RAINBOW do
		local r = 52 - (band - 1) * 3.2
		local chord = r * math.pi / segments * 1.12
		for i = 0, segments - 1 do
			local a = (i + 0.5) / segments * math.pi
			local pos = center + Vector3.new(math.cos(a) * r, math.sin(a) * r, 0)
			local p = part(
				rainbow,
				"Arc",
				Vector3.new(chord, 3.3, 3),
				CFrame.new(pos) * CFrame.Angles(0, 0, a + math.pi / 2),
				color
			)
			noCollide(p)
			p.CastShadow = false
		end
	end
	-- Clouds at both feet of the rainbow.
	for _, side in { -1, 1 } do
		local foot = center + Vector3.new(side * 47, 2, 0)
		for i = -2, 2 do
			local d = 9 - math.abs(i) * 1.6
			local puff =
				ball(rainbow, "Cloud", foot + Vector3.new(i * 3.6, math.abs(i) * -0.8, (i % 2) * 1.5), d, C.White)
			noCollide(puff)
			puff.CastShadow = false
		end
	end
	rainbow.Parent = m
end

-- A panel on two legs facing `target` (used by the leaderboard anchor and the how-to-play board).
local function panel(m: Model, name: string, pos: Vector3, target: Vector3, color: Color3): Part
	local cf = CFrame.lookAt(pos, Vector3.new(target.X, pos.Y, target.Z))
	local board = part(m, name, Vector3.new(16, 10, 1), cf, color)
	part(m, name .. "Frame", Vector3.new(17.4, 11.4, 0.8), cf * CFrame.new(0, 0, 0.5), C.Yellow)
	local floorY = pos.Y - 9.5
	for _, x in { -6.5, 6.5 } do
		local top = (cf * CFrame.new(x, -5, 0.6)).Position
		disc(m, name .. "Leg", top, top.Y - floorY, 0.6, C.White)
	end
	return board
end

local function buildBoards(m: Model, o: Vector3)
	local boards = Instance.new("Model")
	boards.Name = "Boards"
	local target = o + Vector3.new(0, 0, -14)

	-- Solo Record mounts its TOP 10 on this part later; a gold trophy sits on top.
	local anchorPos = o + Vector3.new(38, 9.5, 16)
	local anchor = panel(boards, "LeaderboardAnchor", anchorPos, target, C.Panel)
	local trophyBase = anchorPos + Vector3.new(0, 6.6, 0)
	disc(boards, "TrophyBase", trophyBase + Vector3.new(0, 0.8, 0), 1.6, 1.8, C.Purple)
	disc(boards, "TrophyStem", trophyBase + Vector3.new(0, 2.6, 0), 1.8, 0.5, C.Yellow)
	local cup = ellipsoid(
		boards,
		"TrophyCup",
		CFrame.new(trophyBase + Vector3.new(0, 4, 0)),
		Vector3.new(3.6, 3.2, 3.6),
		C.Yellow
	)
	cup.Material = Enum.Material.Foil
	anchor.Parent = m -- keep it a direct child for Solo Record

	-- How to play board on the other side.
	local howPos = o + Vector3.new(-38, 9.5, 16)
	local how = panel(boards, "HowToPlay", howPos, target, C.Panel)
	local gui = surface(how, Enum.NormalId.Front, 40)
	label(gui, "HOW TO PLAY", UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.2), C.Yellow, 3)
	local lines = {
		{ "SPACE", "Jump" },
		{ "SHIFT", "Dash" },
		{ "C / CTRL", "Slide" },
		{ "CLICK", "Swing / Throw" },
	}
	for i, line in lines do
		local y = 0.25 + (i - 1) * 0.15
		local key = label(gui, line[1], UDim2.fromScale(0.05, y), UDim2.fromScale(0.42, 0.13), C.Cyan, 2)
		key.TextXAlignment = Enum.TextXAlignment.Right
		local action = label(gui, line[2], UDim2.fromScale(0.53, y), UDim2.fromScale(0.42, 0.13), C.White, 2)
		action.TextXAlignment = Enum.TextXAlignment.Left
	end
	label(gui, "Fall off and you're OUT!", UDim2.fromScale(0.05, 0.85), UDim2.fromScale(0.9, 0.12), C.Pink, 2)
	boards.Parent = m
end

local function lollipop(parent: Instance, ground: Vector3, height: number, color: Color3)
	local stick = part(
		parent,
		"Stick",
		Vector3.new(height, 0.9, 0.9),
		CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		C.White
	)
	stick.Shape = Enum.PartType.Cylinder
	local candy = part(
		parent,
		"Candy",
		Vector3.new(1.4, 7, 7),
		CFrame.new(ground + Vector3.new(0, height + 2.5, 0)) * CFrame.Angles(0, math.rad(90), 0),
		color
	)
	candy.Shape = Enum.PartType.Cylinder
	local swirl = part(
		parent,
		"Swirl",
		Vector3.new(1.6, 3.6, 3.6),
		CFrame.new(ground + Vector3.new(0, height + 2.5, 0)) * CFrame.Angles(0, math.rad(90), 0),
		C.White
	)
	swirl.Shape = Enum.PartType.Cylinder
end

local function mushroom(parent: Instance, ground: Vector3, scale: number)
	local stemH = 5 * scale
	local stem = part(
		parent,
		"Stem",
		Vector3.new(stemH, 3.6 * scale, 3.6 * scale),
		CFrame.new(ground + Vector3.new(0, stemH / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 240, 220)
	)
	stem.Shape = Enum.PartType.Cylinder
	local capCenter = ground + Vector3.new(0, stemH + 1.2 * scale, 0)
	ellipsoid(parent, "Cap", CFrame.new(capCenter), Vector3.new(12, 5.5, 12) * scale, C.Red)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local dot = capCenter + Vector3.new(math.cos(a) * 3.6 * scale, 1.6 * scale, math.sin(a) * 3.6 * scale)
		noCollide(ball(parent, "Dot", dot, 1.6 * scale, C.White))
	end
	noCollide(ball(parent, "Dot", capCenter + Vector3.new(0, 2.6 * scale, 0), 1.8 * scale, C.White))
end

local function gift(parent: Instance, ground: Vector3, size: number, color: Color3, ribbon: Color3, yaw: number)
	local cf = CFrame.new(ground + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, yaw, 0)
	part(parent, "Box", Vector3.one * size, cf, color)
	noCollide(part(parent, "Ribbon", Vector3.new(size + 0.1, size + 0.1, size * 0.2), cf, ribbon))
	noCollide(part(parent, "Ribbon", Vector3.new(size * 0.2, size + 0.1, size + 0.1), cf, ribbon))
	noCollide(ball(parent, "Bow", (cf * CFrame.new(-0.5, size / 2 + 0.4, 0)).Position, size * 0.3, ribbon))
	noCollide(ball(parent, "Bow", (cf * CFrame.new(0.5, size / 2 + 0.4, 0)).Position, size * 0.3, ribbon))
end

local function puffTree(parent: Instance, ground: Vector3, color: Color3)
	local trunk = part(
		parent,
		"Trunk",
		Vector3.new(7, 1.6, 1.6),
		CFrame.new(ground + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(150, 100, 60)
	)
	trunk.Shape = Enum.PartType.Cylinder
	ball(parent, "Puff", ground + Vector3.new(0, 9, 0), 7.5, color)
	ball(parent, "Puff", ground + Vector3.new(2.6, 7.6, 1), 5, color:Lerp(C.White, 0.15))
	ball(parent, "Puff", ground + Vector3.new(-2.4, 7.8, -1), 5.2, color:Lerp(C.Ink, 0.08))
end

local function buildDecor(m: Model, o: Vector3)
	local decor = Instance.new("Model")
	decor.Name = "Decor"
	local candyColors = { C.Pink, C.Cyan, C.Purple, C.Orange, C.Green, C.Red }
	-- Lollipops and puffy trees around the rim (the spawn side stays open).
	local ring = {
		{ a = 200, kind = "lollipop" },
		{ a = 225, kind = "tree" },
		{ a = 315, kind = "tree" },
		{ a = 340, kind = "lollipop" },
		{ a = 160, kind = "lollipop" },
		{ a = 20, kind = "lollipop" },
		{ a = 140, kind = "tree" },
		{ a = 40, kind = "tree" },
		{ a = 250, kind = "lollipop" },
		{ a = 290, kind = "lollipop" },
	}
	for i, info in ring do
		local a = math.rad(info.a)
		local ground = o + Vector3.new(math.cos(a) * 52, 0, math.sin(a) * 52)
		if info.kind == "lollipop" then
			lollipop(decor, ground, 8 + (i % 3) * 2, candyColors[i % #candyColors + 1])
		else
			puffTree(decor, ground, if i % 2 == 0 then Color3.fromRGB(255, 150, 200) else C.Green)
		end
	end
	mushroom(decor, o + Vector3.new(-44, 0, -24), 1.1)
	mushroom(decor, o + Vector3.new(46, 0, -20), 0.9)
	mushroom(decor, o + Vector3.new(-20, 0, 30), 0.75)
	gift(decor, o + Vector3.new(-30, 0, -40), 4, C.Blue, C.Yellow, 0.3)
	gift(decor, o + Vector3.new(-25, 0, -44), 3, C.Pink, C.White, -0.4)
	gift(decor, o + Vector3.new(30, 0, -42), 4.5, C.Green, C.Pink, 0.6)
	gift(decor, o + Vector3.new(24, 0, 34), 3.5, C.Purple, C.Yellow, -0.2)
	gift(decor, o + Vector3.new(44, 0, 2), 3, C.Orange, C.Cyan, 0.9)
	decor.Parent = m
end

local function buildBoundary(m: Model, o: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	local count = 32
	local r = Lobby.RADIUS + 4
	local height = 60
	local width = 2 * math.pi * r / count + 1
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local pos = o + Vector3.new(math.cos(a) * r, height / 2 - 1, math.sin(a) * r)
		local wall = part(
			folder,
			"Wall",
			Vector3.new(width, height, 2),
			CFrame.lookAt(pos, Vector3.new(o.X, pos.Y, o.Z)),
			C.White
		)
		wall.Transparency = 1
		wall.CastShadow = false
	end
	folder.Parent = m
end

local function buildSpawns(m: Model, o: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "Spawns"
	local i = 0
	for _, z in { -22, -16, -10 } do
		for _, x in { -9, -3, 3, 9 } do
			i += 1
			local pos = o + Vector3.new(x, 0.5, z)
			local p = part(
				folder,
				("Spawn%02d"):format(i),
				Vector3.new(4, 1, 4),
				CFrame.lookAt(pos, pos + Vector3.zAxis),
				C.White
			)
			p.Transparency = 1
			noCollide(p)
		end
	end
	folder.Parent = m
end

function Lobby.build(center: Vector3?): Model
	local o = center or Config.LOBBY_CENTER
	local m = Instance.new("Model")
	m.Name = "Lobby"
	buildGround(m, o)
	buildSign(m, o)
	buildRainbow(m, o)
	buildBoards(m, o)
	buildDecor(m, o)
	buildBoundary(m, o)
	buildSpawns(m, o)
	return m
end

return Lobby
