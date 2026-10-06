--!strict
--[[
Laser Tracer client: renders every Laser Tracer arena in the workspace (the main round and any Solo copies)
with one Renderer per map Model, found through the "LaserTracerMap" CollectionService tag that the server
puts on each arena. Also plays the zap effect when the server reports a laser hit (remote LaserTracer_Zap).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Renderer = require(script.Renderer)
local Sounds = require(script.Sounds)

local TAG = "LaserTracerMap"

local function main()
	local renderers: { [Model]: Renderer.Renderer } = {}
	local sounds = Sounds.new()

	local function add(instance: Instance)
		if instance:IsA("Model") and not renderers[instance] then
			renderers[instance] = Renderer.new(instance, sounds)
		end
	end

	local function remove(instance: Instance)
		local renderer = renderers[instance :: Model]
		if renderer then
			renderers[instance :: Model] = nil
			renderer:destroy()
		end
	end

	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
	for _, instance in CollectionService:GetTagged(TAG) do
		add(instance)
	end

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		for map, renderer in renderers do
			if map.Parent then
				renderer:update(now)
			else
				remove(map)
			end
		end
	end)

	-- The remote is created by the server module; never let a missing remote break this script.
	task.spawn(function()
		local ok, remote = pcall(Net.unreliable, "LaserTracer_Zap")
		if not ok then
			return
		end
		remote.OnClientEvent:Connect(function(map: any, player: any, position: any, kind: any)
			if typeof(map) ~= "Instance" or typeof(player) ~= "Instance" or not player:IsA("Player") then
				return
			end
			if typeof(position) ~= "Vector3" or (kind ~= "low" and kind ~= "high") then
				return
			end
			local renderer = renderers[map :: Model]
			if renderer and player.Parent == Players then
				renderer:zap(player, position, kind)
			end
		end)
	end)
end

main()
