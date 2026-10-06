--[[
Hole in the Wall: builds the static arena Model around ctx.center (platform top-center).
A 64 x 64 striped candy platform with a hazard-tile rim, a tiered floating underside, four wall slots
(where walls rise out of the void) and corner pylons. Walls themselves are rendered by the client.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)
local Patterns = require(script.Parent.Patterns)

local Arena = {}

Arena.TAG = "HoleInTheWall_Arena" -- the client finds arenas (main + Solo copies) through this tag
Arena.MODEL_NAME = "HoleInTheWallArena"

local C = Theme.Colors
local ACCENT = Theme.MinigameColors.HoleInTheWall

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function pastel(color: Color3): Color3
	return color:Lerp(C.White, 0.3)
end

function Arena.build(center: CFrame): Model
	local map = Instance.new("Model")
	map.Name = Arena.MODEL_NAME
	local half = Patterns.HALF
	local size = Patterns.PLATFORM

	-- Everything is placed in center space so a rotated or moved copy just works.
	local function at(x: number, y: number, z: number): CFrame
		return center * CFrame.new(x, y, z)
	end

	-- Floor: eight pastel stripes whose top faces are exactly at the floor height.
	local floor = Instance.new("Model")
	floor.Name = "Floor"
	local stripes = 8
	local stripeWidth = size / stripes
	for i = 1, stripes do
		local x = -half + (i - 0.5) * stripeWidth
		local color = pastel(Theme.MapPalette[(i - 1) % #Theme.MapPalette + 1])
		part(floor, "Stripe" .. i, Vector3.new(stripeWidth, 2, size), at(x, -1, 0), color)
	end
	floor.Parent = map

	-- Hazard rim: yellow/ink tiles hugging the edge (flush, so they never trip anyone).
	local rim = Instance.new("Model")
	rim.Name = "Rim"
	local tileDepth = 1.4
	local function rimRow(count: number, span: number, place: (offset: number) -> CFrame, along: boolean)
		local length = span / count
		for k = 1, count do
			local offset = -span / 2 + (k - 0.5) * length
			local tileSize = if along then Vector3.new(length, 0.3, tileDepth) else Vector3.new(tileDepth, 0.3, length)
			decor(part(rim, "Tile", tileSize, place(offset), if k % 2 == 0 then C.Ink else C.Yellow))
		end
	end
	local edge = half - tileDepth / 2
	rimRow(16, size, function(o)
		return at(o, -0.1, edge)
	end, true)
	rimRow(16, size, function(o)
		return at(o, -0.1, -edge)
	end, true)
	rimRow(15, size - 2 * tileDepth, function(o)
		return at(edge, -0.1, o)
	end, false)
	rimRow(15, size - 2 * tileDepth, function(o)
		return at(-edge, -0.1, o)
	end, false)
	rim.Parent = map

	-- Frosting band around the platform sides and a tiered floating underside.
	local under = Instance.new("Model")
	under.Name = "Underside"
	for _, side in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local long = if side.X ~= 0 then Vector3.new(0.8, 1.2, size + 1.6) else Vector3.new(size + 1.6, 1.2, 0.8)
		decor(part(under, "Band", long, at(side.X * (half + 0.4), -1.1, side.Z * (half + 0.4)), C.White))
	end
	local tiers = {
		{ size = size - 2, height = 4, y = -4, color = C.Purple },
		{ size = size - 12, height = 4, y = -8, color = C.Blue },
		{ size = size - 26, height = 4, y = -12, color = C.Pink },
		{ size = size - 40, height = 4, y = -16, color = C.Yellow },
	}
	for k, tier in tiers do
		part(under, "Tier" .. k, Vector3.new(tier.size, tier.height, tier.size), at(0, tier.y, 0), tier.color)
	end
	under.Parent = map

	-- Wall slots: dark grooves just outside each edge where the walls rise from.
	local slots = Instance.new("Model")
	slots.Name = "Slots"
	local slotDist = -Patterns.START_DIST
	local slotLength = Patterns.WALL_WIDTH + 2
	for _, side in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		local alongX = side.Z ~= 0
		local function slotPart(name: string, width: number, height: number, offset: number, y: number, color)
			local s = if alongX then Vector3.new(slotLength, height, width) else Vector3.new(width, height, slotLength)
			local d = slotDist + offset
			return part(slots, name, s, at(side.X * d, y, side.Z * d), color)
		end
		slotPart("Groove", 3.4, 1, 0, -1.2, C.Ink)
		local inner = slotPart("GlowInner", 0.35, 0.25, -1.85, -0.75, ACCENT)
		local outer = slotPart("GlowOuter", 0.35, 0.25, 1.85, -0.75, ACCENT)
		inner.Material = Enum.Material.Neon
		outer.Material = Enum.Material.Neon
		decor(inner)
		decor(outer)
	end
	slots.Parent = map

	-- Corner pylons with candy balls on top.
	local pylons = Instance.new("Model")
	pylons.Name = "Pylons"
	local corner = slotDist + 0.5
	local ballColors = { C.Pink, C.Yellow, C.Cyan, C.Green }
	for k, sign in { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(-1, -1), Vector2.new(1, -1) } do
		local x, z = sign.X * corner, sign.Y * corner
		local column =
			part(pylons, "Column", Vector3.new(18, 4, 4), at(x, 2, z) * CFrame.Angles(0, 0, math.pi / 2), C.White)
		column.Shape = Enum.PartType.Cylinder
		local ring = part(pylons, "Ring", Vector3.new(1, 5, 5), at(x, 9, z) * CFrame.Angles(0, 0, math.pi / 2), ACCENT)
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		decor(ring)
		local ball = part(pylons, "Ball", Vector3.one * 6, at(x, 13.5, z), ballColors[k])
		ball.Shape = Enum.PartType.Ball
		local base = part(pylons, "Base", Vector3.new(2, 7, 7), at(x, -7, z) * CFrame.Angles(0, 0, math.pi / 2), C.Ink)
		base.Shape = Enum.PartType.Cylinder
	end
	pylons.Parent = map

	-- Spawns: a 4 x 3 grid around the middle (Core turns players to face the center).
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	local index = 0
	for row = -1, 1 do
		for col = 0, 3 do
			index += 1
			local s = part(
				spawns,
				string.format("Spawn%02d", index),
				Vector3.new(4, 1, 4),
				at(-10.5 + col * 7, -0.5, row * 7),
				C.White
			)
			s.Transparency = 1
			decor(s)
		end
	end
	spawns.Parent = map

	-- Server-side wall state lives here (one Configuration per wall); the client renders from it.
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = map

	-- Always stream the whole (small) arena so every client can draw the walls from map.Walls.
	pcall(function()
		map.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	CollectionService:AddTag(map, Arena.TAG)
	return map
end

return Arena
