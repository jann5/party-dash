--[[
Party Dash: world-building kit (ART_BIBLE sections 3-5). FROZEN CONTRACT v2, lead-owned.
Every map builder (Lobby, World backdrop, every minigame, Solo backdrop) uses this so the whole game shares ONE
material language: blocky parts on a 2-stud grid, SmoothPlastic + tinted seamless textures, dark cliff bands down
into a cartoon sea, Neon only on hazards.

	local Art = require(ReplicatedStorage.Shared.Art)
	local floor = Art.block(map, "Floor", Vector3.new(64, 2, 64), CFrame.new(center.Position - Vector3.new(0, 1, 0)), "grass_top")
	Art.cliffUnder(map, floor, Config.SEA_LEVEL, "dirt_cliff")      -- dark textured band down into the water + foam
	Art.skin(somePart, "wood")                                       -- re-skin an existing part
	local strips = Art.voxelDisc(map, center, 42, 4, 2, "lt_tile", { altRecipe = "lt_tile_alt" })
	Art.water(folder, Vector3.new(0, Config.SEA_LEVEL, 0), Vector2.new(2048, 2048))
	Art.tree(map, groundPos, 1, rng) / Art.palm(...) / Art.cloud(...) / Art.rock(...)
	Art.hazardOutline(model)                                         -- Highlight on moving hazards

Recipes (Art.RECIPES[name]): tint, texture key (Shared.Assets.Textures), faces ("top" | "sides" | "all" |
"topsides" | "frontback"), StudsPerTile U x V, material. A recipe's tint can be overridden per call:
Art.block(..., "toy_block", { color = Theme.Colors.Red }).
Textures are created as children named "ArtTex". Cylinders and Balls never get textures (mapping stretches): skin()
only sets their color/material.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Art = {}

local W = Theme.World
local C = Theme.Colors

export type Recipe = {
	tint: Color3,
	tex: string?,
	fallback: string?,
	faces: string?,
	u: number?,
	v: number?,
	transparency: number?,
	material: Enum.Material?,
	layers: { any }?,
}

Art.RECIPES = {
	grass_top = { tint = W.GrassTop, tex = "grass_top", fallback = "tile_bevel_2x2", faces = "top", u = 8, v = 8 },
	grass_lip = { tint = W.GrassLip, tex = "tile_bevel", faces = "sides", u = 2, v = 2 },
	dirt_cliff = { tint = W.Dirt, tex = "bricks", faces = "sides", u = 8, v = 8 },
	dirt_cliff_low = { tint = W.DirtDark, tex = "bricks", faces = "sides", u = 8, v = 8 },
	stone = { tint = W.Stone, tex = "stone_blocks", fallback = "bricks", faces = "sides", u = 10, v = 10 },
	stone_top = { tint = Color3.fromRGB(160, 162, 176), tex = "tile_bevel_2x2", faces = "top", u = 8, v = 8 },
	stone_all = { tint = W.Stone, tex = "stone_blocks", fallback = "bricks", faces = "all", u = 10, v = 10 },
	wood = { tint = W.Wood, tex = "planks", faces = "all", u = 8, v = 16 },
	wood_rail = { tint = W.Wood, tex = "planks", faces = "all", u = 4, v = 4 },
	sand = { tint = W.Sand, tex = "speckle", faces = "topsides", u = 12, v = 12 },
	paver = { tint = W.Paver, tex = "tile_bevel", faces = "top", u = 4, v = 4 },
	hazard_trim = { tint = C.Yellow, tex = "hazard", faces = "topsides", u = 6, v = 6 },
	toy_block = { tint = C.Red, tex = "studs", faces = "top", u = 4, v = 4, sidesTex = "tile_bevel" },
	lt_tile = { tint = Theme.Maps.LaserTracer.floor, tex = "tile_bevel", faces = "top", u = 6, v = 6 },
	lt_tile_alt = { tint = Theme.Maps.LaserTracer.floorAlt, tex = "tile_bevel", faces = "top", u = 6, v = 6 },
	steel = { tint = Theme.Maps.LaserTracer.edgeTint, tex = "tile_bevel_2x2", faces = "sides", u = 6, v = 6 },
	maple = { tint = Theme.Maps.Dodgeball.floor, tex = "planks", faces = "top", u = 6, v = 24 },
	turf_check = { tint = Theme.Maps.HoleInTheWall.floor, tex = "checker_soft", faces = "top", u = 8, v = 8 },
	brick_wall = { tint = C.Red, tex = "bricks", faces = "frontback", u = 8, v = 8 },
	foam_mat = { tint = Theme.Maps.BombTag.floor, tex = "tile_bevel_2x2", faces = "top", u = 8, v = 8 },
	leaf = { tint = W.Leaf, tex = "tile_bevel_2x2", faces = "all", u = 6, v = 6 },
	leaf_dark = { tint = W.LeafDark, tex = "tile_bevel_2x2", faces = "all", u = 6, v = 6 },
	trunk = { tint = W.Trunk, tex = "planks", faces = "sides", u = 2, v = 6 },
	awning = { tint = C.Red, tex = "awning", fallback = "checker", faces = "all", u = 4, v = 4 },
	checker_pad = { tint = C.Yellow, tex = "checker", faces = "top", u = 8, v = 8 },
	plain = { tint = C.White, faces = "none" },
	cloud = { tint = W.Cloud, faces = "none" },
	water = {
		tint = W.Water,
		faces = "top",
		layers = {
			{ tex = "waves", color = W.WaterLine, u = 28, v = 28, transparency = 0.15, offU = 0, offV = 0 },
			{ tex = "waves", color = W.WaterLine2, u = 43, v = 43, transparency = 0.55, offU = 14, offV = 9 },
		},
	},
}

local FACE_SETS = {
	top = { Enum.NormalId.Top },
	sides = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right },
	topsides = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right },
	all = {
		Enum.NormalId.Top,
		Enum.NormalId.Bottom,
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	},
	frontback = { Enum.NormalId.Front, Enum.NormalId.Back },
	none = {},
}

local function texId(key: string?, fallback: string?): string?
	if not key then
		return nil
	end
	local id = Assets.Textures[key]
	if (not id or id == "") and fallback then
		id = Assets.Textures[fallback]
	end
	if not id or id == "" then
		return nil
	end
	return id
end

local function addTexture(
	part: BasePart,
	face: Enum.NormalId,
	id: string,
	color: Color3,
	u: number,
	v: number,
	tr: number?
)
	local t = Instance.new("Texture")
	t.Name = "ArtTex"
	t.Face = face
	t.Texture = id
	t.Color3 = color
	t.StudsPerTileU = u
	t.StudsPerTileV = v
	t.Transparency = tr or 0
	t.Parent = part
	return t
end

-- Applies a recipe to an existing part. opts: { color: Color3?, faces: string?, u: number?, v: number?, keepMaterial: bool? }
function Art.skin(part: BasePart, recipeName: string, opts: { [string]: any }?): BasePart
	local r = Art.RECIPES[recipeName]
	assert(r, "Art.skin: unknown recipe " .. tostring(recipeName))
	local o = opts or {}
	local tint = o.color or r.tint
	if not o.keepMaterial then
		part.Material = r.material or Enum.Material.SmoothPlastic
	end
	part.Color = tint
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for _, c in part:GetChildren() do
		if c:IsA("Texture") and c.Name == "ArtTex" then
			c:Destroy()
		end
	end
	local round = part:IsA("Part") and (part.Shape == Enum.PartType.Ball or part.Shape == Enum.PartType.Cylinder)
	if round then
		return part
	end
	if r.layers then
		for _, layer in r.layers do
			local id = texId(layer.tex, nil)
			if id then
				local t = addTexture(part, Enum.NormalId.Top, id, layer.color, layer.u, layer.v, layer.transparency)
				t.OffsetStudsU = layer.offU or 0
				t.OffsetStudsV = layer.offV or 0
			end
		end
		return part
	end
	local id = texId(r.tex, r.fallback)
	local faces = FACE_SETS[o.faces or r.faces or "all"] or FACE_SETS.all
	local u, v = o.u or r.u or 8, o.v or r.v or 8
	if id then
		for _, face in faces do
			addTexture(part, face, id, tint, u, v, r.transparency)
		end
	end
	if r.sidesTex then
		local sid = texId(r.sidesTex, nil)
		if sid then
			-- one bevel frame per side face (toy blocks): StudsPerTile = that face's size
			local s = part.Size
			addTexture(part, Enum.NormalId.Front, sid, tint, s.X, s.Y)
			addTexture(part, Enum.NormalId.Back, sid, tint, s.X, s.Y)
			addTexture(part, Enum.NormalId.Left, sid, tint, s.Z, s.Y)
			addTexture(part, Enum.NormalId.Right, sid, tint, s.Z, s.Y)
		end
	end
	return part
end

-- Creates an anchored, styled Part. opts: { color, collide (default true), shape (Enum.PartType), transparency,
-- castShadow, canQuery, canTouch, faces, u, v }
function Art.block(
	parent: Instance?,
	name: string,
	size: Vector3,
	cf: CFrame,
	recipeName: string,
	opts: { [string]: any }?
): Part
	local o = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	if o.shape then
		p.Shape = o.shape
	end
	p.Size = size
	p.CFrame = cf
	p.CanCollide = o.collide ~= false
	if o.canQuery ~= nil then
		p.CanQuery = o.canQuery
	end
	if o.canTouch ~= nil then
		p.CanTouch = o.canTouch
	end
	if o.castShadow ~= nil then
		p.CastShadow = o.castShadow
	end
	p.Transparency = o.transparency or 0
	Art.skin(p, recipeName, o)
	p.Parent = parent
	return p
end

-- A round floor made of horizontal strips (stair-stepped rim like the references): one Part per `cell`-deep strip,
-- X extent snapped to multiples of `cell`. The TOP of every strip is at center.Y. Returns the strips.
-- opts: { altRecipe: string? (every other strip), collide, color, altColor }
function Art.voxelDisc(
	parent: Instance?,
	center: CFrame,
	radius: number,
	cell: number,
	height: number,
	recipeName: string,
	opts: { [string]: any }?
): { Part }
	local o = opts or {}
	local strips = {}
	local n = math.floor(radius / cell)
	local i = 0
	for k = -n, n - 1 do
		local z0 = k * cell
		local zFar = math.max(math.abs(z0), math.abs(z0 + cell))
		if zFar <= radius then
			local half = math.floor(math.sqrt(radius * radius - zFar * zFar) / cell) * cell
			if half >= cell then
				i += 1
				local recipe = (o.altRecipe and i % 2 == 0) and o.altRecipe or recipeName
				local color = (i % 2 == 0) and o.altColor or o.color
				local cf = center * CFrame.new(0, -height / 2, z0 + cell / 2)
				local strip = Art.block(parent, "Strip" .. i, Vector3.new(half * 2, height, cell), cf, recipe, {
					collide = o.collide,
					color = color,
				})
				table.insert(strips, strip)
			end
		end
	end
	return strips
end

-- Thin foam frame around a rectangle footprint at the sea surface.
function Art.foam(parent: Instance?, centerXZ: Vector3, sizeX: number, sizeZ: number, seaY: number)
	local w = 2
	local y = seaY + 0.05
	local function bar(name, size, pos)
		local p = Art.block(parent, name, size, CFrame.new(pos), "plain", {
			color = W.Foam,
			collide = false,
			canQuery = false,
			canTouch = false,
			castShadow = false,
			transparency = 0.25,
		})
		return p
	end
	bar("FoamN", Vector3.new(sizeX + 2 * w, 0.2, w), Vector3.new(centerXZ.X, y, centerXZ.Z + sizeZ / 2 + w / 2))
	bar("FoamS", Vector3.new(sizeX + 2 * w, 0.2, w), Vector3.new(centerXZ.X, y, centerXZ.Z - sizeZ / 2 - w / 2))
	bar("FoamE", Vector3.new(w, 0.2, sizeZ), Vector3.new(centerXZ.X + sizeX / 2 + w / 2, y, centerXZ.Z))
	bar("FoamW", Vector3.new(w, 0.2, sizeZ), Vector3.new(centerXZ.X - sizeX / 2 - w / 2, y, centerXZ.Z))
end

-- Cliff band under an (axis-aligned, rectangular) floor part: from the part's bottom down to seaY - 2, skinned with
-- `recipeName` (default dirt_cliff), plus a foam frame at the waterline. Non-collidable below the floor so nobody
-- can stand on a ledge (brief #22). Returns the cliff part.
function Art.cliffUnder(
	parent: Instance?,
	floor: BasePart,
	seaY: number,
	recipeName: string?,
	opts: { [string]: any }?
): Part?
	local o = opts or {}
	local bottom = floor.Position.Y - floor.Size.Y / 2
	local depth = bottom - (seaY - 2)
	if depth <= 0.2 then
		return nil
	end
	local inset = o.inset or 0
	local size = Vector3.new(floor.Size.X - inset * 2, depth, floor.Size.Z - inset * 2)
	local cf = CFrame.new(floor.Position.X, bottom - depth / 2, floor.Position.Z)
	local cliff = Art.block(parent, (o.name or floor.Name) .. "Cliff", size, cf, recipeName or "dirt_cliff", {
		collide = o.collide == true,
		color = o.color,
		canQuery = false,
		u = o.u,
		v = o.v,
	})
	if o.foam ~= false then
		Art.foam(parent, cf.Position, size.X, size.Z, seaY)
	end
	return cliff
end

-- Sea / pond surface: non-collidable Part with two wave texture layers. Tagged "PD_Water" so the World client
-- scrolls its textures (OffsetStudsU/V) every frame.
function Art.water(parent: Instance?, center: Vector3, size: Vector2): Part
	local p = Art.block(
		parent,
		"Water",
		Vector3.new(size.X, 1, size.Y),
		CFrame.new(center - Vector3.new(0, 0.5, 0)),
		"water",
		{
			collide = false,
			canQuery = false,
			canTouch = false,
			castShadow = false,
		}
	)
	p.Reflectance = 0
	CollectionService:AddTag(p, "PD_Water")
	return p
end

local function rnd(rng: Random?, a: number, b: number): number
	return rng and rng:NextNumber(a, b) or (a + (b - a) * 0.5)
end

-- Blocky tree: trunk 2x8x2 + canopy 10x6x10 + 7x4x7 top block. groundPos = where the trunk meets the ground.
function Art.tree(parent: Instance?, groundPos: Vector3, scale: number?, rng: Random?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Tree"
	local yaw = CFrame.Angles(0, math.rad(math.floor(rnd(rng, 0, 4)) * 90), 0)
	local base = CFrame.new(groundPos) * yaw
	Art.block(m, "Trunk", Vector3.new(2, 8, 2) * s, base * CFrame.new(0, 4 * s, 0), "trunk", { color = W.Trunk })
	Art.block(m, "Canopy", Vector3.new(10, 6, 10) * s, base * CFrame.new(0, 10 * s, 0), "leaf")
	Art.block(m, "Top", Vector3.new(7, 4, 7) * s, base * CFrame.new(1.5 * s, 14 * s, -1 * s), "leaf_dark")
	m.Parent = parent
	return m
end

-- Blocky palm: 5 stepped trunk cubes + 6 leaf slabs drooping 20 degrees + 2 coconuts.
function Art.palm(parent: Instance?, groundPos: Vector3, scale: number?, rng: Random?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Palm"
	local yaw = CFrame.Angles(0, math.rad(rnd(rng, 0, 360)), 0)
	local base = CFrame.new(groundPos) * yaw
	local top = base
	for i = 1, 5 do
		local cf = base * CFrame.new(0.5 * s * (i - 1), (1.6 * s) * (i - 0.5) + 0.4 * s * (i - 1), 0)
		Art.block(m, "Trunk" .. i, Vector3.new(1.6, 1.6, 1.6) * s, cf, "trunk")
		top = cf
	end
	local crown = top * CFrame.new(0, 1 * s, 0)
	for i = 1, 6 do
		local a = math.rad(60 * i)
		local cf = crown * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.new(0, 0, -3.5 * s)
		Art.block(
			m,
			"Leaf" .. i,
			Vector3.new(1.4, 0.4, 7) * s,
			cf,
			i % 2 == 0 and "leaf_dark" or "leaf",
			{ collide = false }
		)
	end
	for i = 1, 2 do
		Art.block(
			m,
			"Coconut" .. i,
			Vector3.new(1.2, 1.2, 1.2) * s,
			crown * CFrame.new((i == 1 and 0.7 or -0.6) * s, -0.9 * s, 0.4 * s),
			"plain",
			{
				shape = Enum.PartType.Ball,
				color = Color3.fromRGB(110, 70, 40),
				collide = false,
			}
		)
	end
	m.Parent = parent
	return m
end

-- Blocky cloud: 3-6 white boxes, the bottom one shaded. Non-collidable, no shadow. Tagged "PD_Cloud" (clients drift it).
function Art.cloud(parent: Instance?, pos: Vector3, scale: number?, rng: Random?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Cloud"
	local n = math.floor(rnd(rng, 3, 6.99))
	for i = 1, n do
		local size = Vector3.new(rnd(rng, 12, 40), rnd(rng, 6, 12), rnd(rng, 10, 24)) * s
		local off = Vector3.new(rnd(rng, -18, 18), (i == 1) and 0 or rnd(rng, 0, 8), rnd(rng, -8, 8)) * s
		Art.block(m, "Puff" .. i, size, CFrame.new(pos + off), "cloud", {
			color = (i == 1) and W.CloudShade or W.Cloud,
			collide = false,
			canQuery = false,
			canTouch = false,
			castShadow = false,
		})
	end
	m.Parent = parent
	CollectionService:AddTag(m, "PD_Cloud")
	return m
end

-- Grey sea rock (a few stacked stone blocks), base at the sea surface.
function Art.rock(parent: Instance?, seaPos: Vector3, scale: number?, rng: Random?): Model
	local s = scale or 1
	local m = Instance.new("Model")
	m.Name = "Rock"
	local h = rnd(rng, 4, 8) * s
	Art.block(
		m,
		"RockA",
		Vector3.new(rnd(rng, 6, 12), h + 4, rnd(rng, 6, 12)) * Vector3.new(s, 1, s),
		CFrame.new(seaPos + Vector3.new(0, (h + 4) / 2 - 4, 0)),
		"stone_all"
	)
	Art.block(
		m,
		"RockB",
		Vector3.new(4, 3, 4) * s,
		CFrame.new(seaPos + Vector3.new(2 * s, h + 0.5, 1 * s)),
		"stone_all",
		{ color = W.StoneDark }
	)
	m.Parent = parent
	return m
end

-- Dark outline so a moving hazard reads against any background (ART_BIBLE 3.5). Budget: Roblox draws at most
-- 31 Highlights; use it for the bomb holder, Spin bars, walls and balls only.
function Art.hazardOutline(adornee: Instance, color: Color3?): Highlight
	local h = Instance.new("Highlight")
	h.Name = "HazardOutline"
	h.FillTransparency = 1
	h.OutlineColor = color or C.Ink
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = adornee
	h.Parent = adornee
	return h
end

-- ART_BIBLE 4.3 rule 1 helper for critics/builders: is this a valid FLOOR color?
function Art.isFloorColorOk(c: Color3): boolean
	local h, s, v = c:ToHSV()
	local hueDeg = h * 360
	local blueish = hueDeg >= 180 and hueDeg <= 225
	return s >= 0.45 and v >= 0.45 and v <= 0.90 and not blueish
end

return Art
