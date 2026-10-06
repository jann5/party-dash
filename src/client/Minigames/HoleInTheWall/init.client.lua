--[[
Hole in the Wall (client): renders every running copy of the minigame (main arena + Solo copies).
Arenas are found through the CollectionService tag the server puts on the map; each wall Configuration in
map.Walls becomes a WallView that moves in sync with server time. Impact / pass effects arrive through the
server -> client remote "HoleInTheWall_Fx" (validated here; there is no client -> server traffic).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Trove = require(Shared.Util.Trove)

local Fx = require(script.Fx)
local WallView = require(script.WallView)

local TAG = "HoleInTheWall_Arena"
local FX_REMOTE = "HoleInTheWall_Fx"
local MAX_FX_PER_SECOND = 40

local localPlayer = Players.LocalPlayer

type Arena = {
	map: Model,
	visuals: Folder,
	views: { [Configuration]: any },
	dying: { [any]: boolean },
	trove: any,
}

local arenas: { [Model]: Arena } = {}
local fx = Fx.new()
local fxConnected = false
local fxBudget = { window = 0, count = 0 }

local function removeArena(map: Model)
	local arena = arenas[map]
	if not arena then
		return
	end
	arenas[map] = nil
	for _, view in arena.views do
		view:destroy()
	end
	for view in arena.dying do
		view:destroy()
	end
	arena.trove:clean()
end

local function onFx(kind: any, map: any, wallName: any, position: any, code: any, userId: any)
	-- Validate everything: this is remote input.
	if type(kind) ~= "string" or typeof(map) ~= "Instance" or typeof(position) ~= "Vector3" then
		return
	end
	if type(wallName) ~= "string" or type(code) ~= "string" or type(userId) ~= "number" then
		return
	end
	local arena = arenas[map :: Model]
	if not arena then
		return
	end
	local now = os.clock()
	if now - fxBudget.window > 1 then
		fxBudget.window = now
		fxBudget.count = 0
	end
	fxBudget.count += 1
	if fxBudget.count > MAX_FX_PER_SECOND then
		return
	end

	local config = arena.map:FindFirstChild("Walls") and (arena.map :: any).Walls:FindFirstChild(wallName)
	local view = config and arena.views[config]
	local isMe = userId == localPlayer.UserId
	if kind == "hit" then
		local direction = if view then view.dir else Vector3.zAxis
		local color = if view then view.color else Color3.new(1, 1, 1)
		if view then
			view:kick()
		end
		fx:hit(position, direction, color, isMe)
	elseif kind == "pass" then
		local style = WallView.HOLE_STYLE[code]
		if style then
			fx:pass(position, style.color, isMe)
		end
	end
end

local function connectFx()
	if fxConnected then
		return
	end
	fxConnected = true
	-- The server creates this remote when the first Hole in the Wall session is built (before the map
	-- appears), so it already exists here; pcall guards against a slow replication edge case.
	task.spawn(function()
		local ok, remote = pcall(Net.event, FX_REMOTE)
		if ok and remote then
			remote.OnClientEvent:Connect(onFx)
		else
			fxConnected = false
		end
	end)
end

local function addArena(instance: Instance)
	if not instance:IsA("Model") or arenas[instance] then
		return
	end
	local map = instance :: Model
	local trove = Trove.new()
	local visuals = Instance.new("Folder")
	visuals.Name = "HoleInTheWallVisuals"
	visuals.Parent = workspace
	trove:add(visuals)
	local arena: Arena = { map = map, visuals = visuals, views = {}, dying = {}, trove = trove }
	arenas[map] = arena
	connectFx()

	local function addWall(child: Instance)
		if arenas[map] ~= arena or not child:IsA("Configuration") or arena.views[child] then
			return
		end
		local ok, view = pcall(WallView.new, child, visuals)
		if ok and view then
			arena.views[child] = view
		elseif not ok then
			warn("[HoleInTheWall] could not draw wall:", view)
		end
	end
	local function removeWall(child: Instance)
		local view = arena.views[child :: Configuration]
		if view then
			arena.views[child :: Configuration] = nil
			view:release()
			arena.dying[view] = true
		end
	end

	trove:add(task.spawn(function()
		local walls = map:WaitForChild("Walls", 15)
		if not walls or arenas[map] ~= arena then
			return
		end
		trove:connect(walls.ChildAdded, addWall)
		trove:connect(walls.ChildRemoved, removeWall)
		for _, child in walls:GetChildren() do
			addWall(child)
		end
	end))
	trove:connect(map.AncestryChanged, function()
		if not map:IsDescendantOf(workspace) then
			removeArena(map)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(addArena)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	if instance:IsA("Model") then
		removeArena(instance)
	end
end)
for _, instance in CollectionService:GetTagged(TAG) do
	addArena(instance)
end

-- One render loop moves every wall of every arena.
RunService.RenderStepped:Connect(function()
	if next(arenas) == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, arena in arenas do
		for config, view in arena.views do
			local ok, alive = pcall(view.update, view, now)
			if not ok or not alive then
				arena.views[config] = nil
				view:destroy()
			end
		end
		for view in arena.dying do
			local ok, alive = pcall(view.update, view, now)
			if not ok or not alive then
				arena.dying[view] = nil
				view:destroy()
			end
		end
	end
end)

-- Keep the pooled fx part around for the whole session; nothing else to clean on the client.
script.Destroying:Connect(function()
	for map in arenas do
		removeArena(map)
	end
	fx:destroy()
end)
