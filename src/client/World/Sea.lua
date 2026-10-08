--[[
World client: the living backdrop (ART_BIBLE 5.2 / 5.3).
	Water   both wave layers of every PD_Water part scroll (layer A +1.1/+0.45, layer B -0.6/+0.8 studs/s),
	        written ~30 times a second and wrapped to the tile size.
	Clouds  every PD_Cloud model drifts +X at 2 studs/s and wraps at +-1000.
Purely local and cosmetic; parts and textures that replicate late are picked up as they arrive.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared:WaitForChild("Art"))

local Sea = {}

local LAYERS = Art.RECIPES.water.layers
local WAVE_SPEED = { Vector2.new(1.1, 0.45), Vector2.new(-0.6, 0.8) } -- studs/s per layer, in LAYERS order
local WAVE_STEP = 1 / 30
local CLOUD_SPEED = 2
local CLOUD_WRAP = 1000
local CLOUD_STEP = 1 / 20

type Wave = { layer: any, speed: Vector2 }
type Cloud = { x0: number, born: number, parts: { BasePart }, bases: { CFrame }, conn: RBXScriptConnection }

local waves: { [Texture]: Wave } = {}
local waterConns: { [Instance]: RBXScriptConnection } = {}
local clouds: { [Instance]: Cloud } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function trackTexture(inst: Instance)
	if not inst:IsA("Texture") or waves[inst] then
		return
	end
	for i, layer in LAYERS do
		if math.abs(inst.StudsPerTileU - layer.u) < 0.01 then
			waves[inst] = { layer = layer, speed = WAVE_SPEED[i] or Vector2.zero }
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

local function addCloud(model: Instance)
	if clouds[model] or not model:IsA("Model") then
		return
	end
	local cloud = { x0 = model:GetPivot().X, born = os.clock(), parts = {}, bases = {} } :: any
	local function addPart(inst: Instance)
		if inst:IsA("BasePart") then
			table.insert(cloud.parts, inst)
			table.insert(cloud.bases, inst.CFrame)
		end
	end
	cloud.conn = model.DescendantAdded:Connect(addPart)
	for _, inst in model:GetDescendants() do
		addPart(inst)
	end
	clouds[model] = cloud
end

local function removeCloud(model: Instance)
	local cloud = clouds[model]
	if cloud then
		cloud.conn:Disconnect()
		clouds[model] = nil
	end
end

local function updateWaves(t: number)
	for texture, wave in waves do
		if texture.Parent == nil then
			waves[texture] = nil
		else
			local layer = wave.layer
			texture.OffsetStudsU = ((layer.offU or 0) + wave.speed.X * t) % layer.u
			texture.OffsetStudsV = ((layer.offV or 0) + wave.speed.Y * t) % layer.v
		end
	end
end

local function updateClouds(now: number)
	table.clear(moveParts)
	table.clear(moveCFrames)
	for model, cloud in clouds do
		if model.Parent == nil then
			removeCloud(model)
		else
			local x = cloud.x0 + CLOUD_SPEED * (now - cloud.born)
			local dx = ((x + CLOUD_WRAP) % (2 * CLOUD_WRAP)) - CLOUD_WRAP - cloud.x0
			for i, part in cloud.parts do
				if part.Parent then
					table.insert(moveParts, part)
					table.insert(moveCFrames, cloud.bases[i] + Vector3.new(dx, 0, 0))
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
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
	local waveWait, cloudWait = 0, 0
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
