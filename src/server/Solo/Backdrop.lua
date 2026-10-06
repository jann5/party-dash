--!strict
--[[
Scenery for Solo slots. The main arena sits above Core's tropical sea; a Solo copy is thousands of studs
away, so without this it would float in an empty sky. The first time slot k is used, a smaller version of
the same world is built around it (terrain sea, sandy islets, floating islands, clouds) and kept for the
rest of the server's life. Purely decorative: nothing collides, touches or blocks raycasts.

	Backdrop.ensure(k, center)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)

local Build = require(script.Parent.Parent:WaitForChild("Core"):WaitForChild("Build"))

local Backdrop = {}

local SEA_DROP = 62 -- same as Core: the sea is this far below the arena floor
local SEA_TILE = 512
local SEA_TILES = 3 -- 3x3 tiles of water
local C = Theme.Colors
local GRASS = Color3.fromRGB(110, 215, 95)
local SAND = Color3.fromRGB(255, 226, 150)
local DIRT = Color3.fromRGB(165, 105, 65)

local built: { [number]: boolean } = {}
local folder: Folder? = nil

local function root(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "SoloBackdrops"
	f.Parent = workspace
	folder = f
	return f
end

local function sea(center: Vector3)
	local terrain = workspace.Terrain
	local y = center.Y - SEA_DROP - 8
	local half = SEA_TILE * SEA_TILES / 2
	for x = -half + SEA_TILE / 2, half - SEA_TILE / 2, SEA_TILE do
		for z = -half + SEA_TILE / 2, half - SEA_TILE / 2, SEA_TILE do
			terrain:FillBlock(
				CFrame.new(center.X + x, y, center.Z + z),
				Vector3.new(SEA_TILE, 16, SEA_TILE),
				Enum.Material.Water
			)
		end
	end
end

local function islet(parent: Instance, center: Vector3, seaY: number, radius: number)
	local top = Vector3.new(center.X, seaY + 2.5, center.Z)
	Build.disc(parent, "Sand", top, 8, radius, SAND)
	Build.disc(parent, "Grass", top + Vector3.new(0, 0.6, 0), 0.8, radius * 0.55, GRASS)
	Build.pillar(parent, "Trunk", top + Vector3.new(0, 4, 0), 8, 0.6, Color3.fromRGB(140, 90, 55))
	Build.ball(parent, "Leaves", top + Vector3.new(0, 8.5, 0), 6, GRASS)
end

local function floatingIsland(parent: Instance, top: Vector3, radius: number, color: Color3)
	Build.disc(parent, "Grass", top, 2, radius, GRASS)
	Build.disc(parent, "Dirt", top - Vector3.new(0, 2, 0), radius * 0.35, radius * 0.92, DIRT)
	Build.disc(parent, "Tip", top - Vector3.new(0, 2 + radius * 0.35, 0), radius * 0.3, radius * 0.5, DIRT)
	Build.ball(parent, "Bush", top + Vector3.new(radius * 0.3, 2, 0), radius * 0.45, color)
end

function Backdrop.ensure(slot: number, center: Vector3)
	if built[slot] then
		return
	end
	built[slot] = true
	local ok, err = pcall(function()
		sea(center)
		local model = Instance.new("Model")
		model.Name = ("Slot%d"):format(slot)
		local rng = Random.new(1000 + slot)
		local seaY = center.Y - SEA_DROP
		for _ = 1, 6 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(150, 420)
			islet(model, center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), seaY, rng:NextNumber(12, 22))
		end
		local bushColors = { C.Pink, C.Yellow, C.Cyan, C.Purple }
		for i = 1, 5 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(200, 380)
			local top = center + Vector3.new(math.cos(a) * d, rng:NextNumber(10, 80), math.sin(a) * d)
			floatingIsland(model, top, rng:NextNumber(14, 26), bushColors[(i - 1) % #bushColors + 1])
		end
		for _ = 1, 10 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(160, 520)
			local h = rng:NextNumber(50, 150)
			Build.cloud(model, center + Vector3.new(math.cos(a) * d, h, math.sin(a) * d), rng:NextNumber(14, 28), rng)
		end
		for _ = 1, 6 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(90, 260)
			local h = rng:NextNumber(-45, -30) -- below killY: you see them while falling
			Build.cloud(model, center + Vector3.new(math.cos(a) * d, h, math.sin(a) * d), rng:NextNumber(10, 18), rng)
		end
		Build.decorative(model)
		model.Parent = root()
	end)
	if not ok then
		warn(("[Solo] backdrop for slot %d failed: %s"):format(slot, tostring(err)))
	end
end

-- The default slot is prepared at boot so the first run starts instantly.
function Backdrop.prewarm()
	Backdrop.ensure(0, Config.SOLO_ORIGIN)
end

return Backdrop
