-- Party Dash Core: the persistent spectator stands (floating bleachers held up by balloons),
-- built once at ARENA_CENTER + Config.SPECTATOR_OFFSET and facing the arena.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Build = require(script.Parent.Build)

local Stands = {}

local C = Theme.Colors
local PAL = Theme.MapPalette

local WIDTH = 46
local FRONT = -10 -- local z of the front edge (negative = toward the arena)
local BACK = 22
local ROW_DEPTH = 6
local ROW_RISE = 1.6

local model: Model? = nil
local spots: { CFrame } = {}
local base = CFrame.new()

-- Local frame: x right, y up, z = distance BACK from the arena (negative is toward the arena).
local function L(x: number, y: number, z: number): CFrame
	return base * CFrame.new(x, y, z)
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?)
	local p = { Name = name, Size = size, CFrame = cf, Color = color, Parent = parent }
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	return Build.part(p)
end

local function buildBalloon(parent: Instance, anchor: Vector3, top: Vector3, color: Color3)
	local balloon = Build.ellipsoid(parent, "Balloon", CFrame.new(top), Vector3.new(7, 8.5, 7), color)
	balloon.Material = Enum.Material.Glass
	balloon.Reflectance = 0.15
	local knot = Build.ball(parent, "Knot", top - Vector3.new(0, 4.4, 0), 1, color)
	knot.CastShadow = false
	local from = anchor
	local to = top - Vector3.new(0, 4.6, 0)
	local length = (to - from).Magnitude
	local string_ = Build.part({
		Name = "String",
		Size = Vector3.new(0.15, 0.15, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = C.White,
		CastShadow = false,
		Parent = parent,
	})
	return string_
end

function Stands.build(): Model
	if model then
		return model
	end
	local origin = Config.ARENA_CENTER + Config.SPECTATOR_OFFSET
	local toArena = Vector3.new(Config.ARENA_CENTER.X - origin.X, 0, Config.ARENA_CENTER.Z - origin.Z)
	if toArena.Magnitude < 1 then
		toArena = Vector3.zAxis
	end
	-- LookVector (local -Z) points at the arena, so +Z local is "back".
	base = CFrame.lookAt(origin, origin + toArena.Unit)

	local m = Instance.new("Model")
	m.Name = "SpectatorStands"
	local depth = BACK - FRONT

	-- Deck: colorful boards across the standing area.
	box(m, "Deck", Vector3.new(WIDTH, 2, depth), L(0, -1, (FRONT + BACK) / 2), Color3.fromRGB(250, 246, 255))
	local boards = 8
	local boardW = WIDTH / boards
	for i = 1, boards do
		local x = -WIDTH / 2 + boardW * (i - 0.5)
		box(
			m,
			"Board",
			Vector3.new(boardW - 0.3, 0.2, 13.6),
			L(x, 0.1, FRONT + 7),
			if i % 2 == 0 then C.Pink else C.Cyan
		)
	end

	-- Bleacher rows rising toward the back.
	for row = 1, 3 do
		local h = ROW_RISE * row
		local z = FRONT + 14 + ROW_DEPTH * (row - 0.5)
		box(m, "Row" .. row, Vector3.new(WIDTH, h, ROW_DEPTH), L(0, h / 2, z), PAL[row])
		box(m, "RowTrim" .. row, Vector3.new(WIDTH, 0.3, 0.6), L(0, h + 0.15, z - ROW_DEPTH / 2 + 0.3), C.White)
	end

	-- Hull underneath (stacked, shrinking slabs).
	box(m, "Hull1", Vector3.new(WIDTH - 2, 3, depth - 2), L(0, -3.5, (FRONT + BACK) / 2), C.Purple)
	box(m, "Hull2", Vector3.new(WIDTH - 10, 3, depth - 8), L(0, -6.5, (FRONT + BACK) / 2), C.Blue)
	box(m, "Hull3", Vector3.new(WIDTH - 22, 3, depth - 16), L(0, -9.5, (FRONT + BACK) / 2), C.Cyan)

	-- Low front railing: candy posts, a yellow top rail and a see-through panel (keeps the view open).
	local posts = 12
	for i = 0, posts - 1 do
		local x = -WIDTH / 2 + 1 + (WIDTH - 2) * i / (posts - 1)
		Build.pillar(m, "Post", L(x, 1.8, FRONT + 0.6).Position, 3.6, 0.45, PAL[i % #PAL + 1])
	end
	Build.part({
		Name = "TopRail",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(WIDTH, 1, 1),
		CFrame = L(0, 3.8, FRONT + 0.6),
		Color = C.Yellow,
		Parent = m,
	})
	box(m, "Glass", Vector3.new(WIDTH - 2, 2.8, 0.2), L(0, 1.9, FRONT + 0.6), C.Cyan, { Transparency = 0.75 })

	-- Side walls and the back wall with a sign facing the arena.
	for _, side in { -1, 1 } do
		local x = side * (WIDTH / 2 + 0.4)
		box(m, "SideWall", Vector3.new(0.8, 7, depth), L(x, 3.5, (FRONT + BACK) / 2), C.Pink)
		box(m, "SideTrim", Vector3.new(1.2, 0.6, depth + 0.4), L(x, 7.2, (FRONT + BACK) / 2), C.Yellow)
		Build.ball(m, "Cap", L(x, 7.8, FRONT).Position, 1.8, C.Yellow)
	end
	local backWall = box(m, "BackWall", Vector3.new(WIDTH + 1.6, 12, 1), L(0, 6, BACK + 0.5), C.Purple)
	box(m, "BackTrim", Vector3.new(WIDTH + 2, 0.8, 1.4), L(0, 12.2, BACK + 0.5), C.Yellow)
	Build.sign(backWall, Enum.NormalId.Front, "SPECTATOR STANDS", C.Yellow, Theme.FontFace, 20)

	-- Balloons holding the stands up (behind the spectators, out of the arena view).
	local balloonColors = { C.Red, C.Yellow, C.Cyan, C.Pink, C.Green, C.Purple }
	local k = 0
	for _, side in { -1, 1 } do
		for j = 0, 2 do
			k += 1
			local anchor = L(side * (WIDTH / 2), 7.5, BACK - 2).Position
			local top = L(side * (WIDTH / 2 + 2 + j * 4.5), 20 + j * 4.5, BACK + 3 + j * 2).Position
			buildBalloon(m, anchor, top, balloonColors[k])
		end
	end
	Build.decorative(m)
	-- Re-enable collisions for the parts people stand on or bump into.
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "Balloon" and d.Name ~= "Knot" and d.Name ~= "String" then
			d.CanCollide = true
			d.CanQuery = true
		end
	end

	-- Invisible walls so nobody falls off.
	local wallH = 18
	local function wall(size: Vector3, cf: CFrame)
		box(m, "Boundary", size, cf, C.White, { Transparency = 1, CastShadow = false })
	end
	wall(Vector3.new(WIDTH + 4, wallH, 1), L(0, wallH / 2, FRONT - 0.5))
	wall(Vector3.new(WIDTH + 4, wallH, 1), L(0, wallH / 2, BACK + 1.5))
	wall(Vector3.new(1, wallH, depth + 4), L(-WIDTH / 2 - 1.5, wallH / 2, (FRONT + BACK) / 2))
	wall(Vector3.new(1, wallH, depth + 4), L(WIDTH / 2 + 1.5, wallH / 2, (FRONT + BACK) / 2))

	-- Fallback spawn for brand new characters (invisible, no force field). Core moves people right away.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "StandsSpawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.CFrame = L(0, 0.5, FRONT + 6)
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.CanQuery = false
	spawnLocation.CanTouch = false
	spawnLocation.Duration = 0
	spawnLocation.Neutral = true
	spawnLocation.Parent = m

	-- Standing spots: the front deck plus the first two bleacher rows.
	spots = {}
	for _, z in { FRONT + 4, FRONT + 10 } do
		for x = -18, 18, 6 do
			table.insert(spots, L(x, 0.2, z))
		end
	end
	for row = 1, 2 do
		local z = FRONT + 14 + ROW_DEPTH * (row - 0.5)
		for x = -18, 18, 6 do
			table.insert(spots, L(x, ROW_RISE * row, z))
		end
	end

	m.Parent = workspace
	model = m
	return m
end

-- A random standing spot on the stands (floor CFrame facing the arena).
function Stands.randomFloor(): CFrame
	if #spots == 0 then
		Stands.build()
	end
	local cf = spots[math.random(1, #spots)]
	return cf * CFrame.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)
end

-- True when a world position is on/above the stands deck.
function Stands.contains(position: Vector3): boolean
	if not model then
		return false
	end
	local rel = base:PointToObjectSpace(position)
	return math.abs(rel.X) <= WIDTH / 2 + 2 and rel.Z >= FRONT - 2 and rel.Z <= BACK + 2 and rel.Y > -3 and rel.Y < 25
end

return Stands
