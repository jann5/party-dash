--[[
World client: the living backdrop (ART_BIBLE 5.2 / 5.3). Purely local and cosmetic.
	Water   both wave layers of every PD_Water part scroll (layer A +1.1/+0.45, layer B -0.6/+0.8 studs/s), written
	        about 30 times a second and wrapped to the tile size.
	Clouds  every PD_Cloud model drifts +X at 2 studs/s and wraps from +1000 back to -1000 (Model:PivotTo, so the
	        model pivot moves with its parts).
Parts and textures that replicate (or stream in) late are picked up as they arrive.

	Sea.start()
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared:WaitForChild("Art"))

local Sea = {}

local LAYERS = Art.RECIPES.water.layers
local WAVE_SPEED = { Vector2.new(1.1, 0.45), Vector2.new(-0.6, 0.8) } -- studs/s, in LAYERS order (A, B)
local WAVE_STEP = 1 / 30
local CLOUD_SPEED = 2
local CLOUD_WRAP = 1000
local CLOUD_STEP = 1 / 20

type Wave = { u: number, v: number, offU: number, offV: number, speed: Vector2 }
type Cloud = { base: CFrame, centerX: number, born: number, dx: number, conn: RBXScriptConnection }

local waves: { [Texture]: Wave } = {}
local waterConns: { [Instance]: RBXScriptConnection } = {}
local clouds: { [Model]: Cloud } = {}

-- A wave texture is recognised by its tile size (the two layers use different StudsPerTile).
local function trackTexture(inst: Instance)
	if not inst:IsA("Texture") or waves[inst] then
		return
	end
	for i, layer in LAYERS do
		if math.abs(inst.StudsPerTileU - layer.u) < 0.01 then
			waves[inst] = {
				u = layer.u,
				v = layer.v,
				offU = layer.offU or 0,
				offV = layer.offV or 0,
				speed = WAVE_SPEED[i] or Vector2.zero,
			}
			return
		end
	end
end

local function addWater(part: Instance)
	if waterConns[part] then
		return
	end
	waterConns[part] = part.ChildAdded:Connect(trackTexture)
	for _, child in part:GetChildren() do
		trackTexture(child)
	end
end

local function removeWater(part: Instance)
	local conn = waterConns[part]
	if conn then
		conn:Disconnect()
		waterConns[part] = nil
	end
end

local function cloudCenterX(model: Model): number
	local sum, n = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			sum += d.Position.X
			n += 1
		end
	end
	return if n > 0 then sum / n else model:GetPivot().X
end

local function addCloud(model: Instance)
	if clouds[model :: Model] or not model:IsA("Model") then
		return
	end
	local cloud: Cloud = {
		base = model:GetPivot(),
		centerX = cloudCenterX(model),
		born = os.clock(),
		dx = 0,
		conn = nil :: any,
	}
	-- a part streaming in later arrives at its server position: shift it to where the cloud has drifted
	cloud.conn = model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and cloud.dx ~= 0 then
			d.CFrame += Vector3.new(cloud.dx, 0, 0)
		end
	end)
	clouds[model] = cloud
end

local function removeCloud(model: Instance)
	local cloud = clouds[model :: Model]
	if cloud then
		cloud.conn:Disconnect()
		clouds[model :: Model] = nil
	end
end

local function updateWaves(t: number)
	for texture, wave in waves do
		if texture.Parent == nil then
			waves[texture] = nil
		else
			texture.OffsetStudsU = (wave.offU + wave.speed.X * t) % wave.u
			texture.OffsetStudsV = (wave.offV + wave.speed.Y * t) % wave.v
		end
	end
end

local function updateClouds(now: number)
	for model, cloud in clouds do
		if model.Parent == nil then
			removeCloud(model)
		else
			local x = cloud.centerX + CLOUD_SPEED * (now - cloud.born)
			local wrapped = (x + CLOUD_WRAP) % (2 * CLOUD_WRAP) - CLOUD_WRAP
			cloud.dx = wrapped - cloud.centerX
			model:PivotTo(cloud.base + Vector3.new(cloud.dx, 0, 0))
		end
	end
end

local function watchTag(tag: string, added: (Instance) -> (), removed: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
	for _, inst in CollectionService:GetTagged(tag) do
		added(inst)
	end
end

function Sea.start()
	watchTag("PD_Water", addWater, removeWater)
	watchTag("PD_Cloud", addCloud, removeCloud)

	local start = os.clock()
	local waveWait, cloudWait = WAVE_STEP, CLOUD_STEP
	RunService.Heartbeat:Connect(function(dt)
		waveWait += dt
		cloudWait += dt
		local now = os.clock()
		if waveWait >= WAVE_STEP then
			waveWait = 0
			updateWaves(now - start)
		end
		if cloudWait >= CLOUD_STEP then
			cloudWait = 0
			updateClouds(now)
		end
	end)
end

return Sea
