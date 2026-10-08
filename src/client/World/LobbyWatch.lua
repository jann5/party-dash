--[[
World client helper: binds to the lobby without ever blocking.

	LobbyWatch.onLobby(function(model, trove) ... end)
		runs for every workspace Model named "Lobby", now and whenever Core (re)builds one. `trove` is cleaned as
		soon as that Model leaves the workspace, so per-lobby connections never leak.
	LobbyWatch.eachDescendant(model, trove, fn)
		calls fn once for every current AND future descendant (the lobby may replicate piece by piece).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local LobbyWatch = {}

function LobbyWatch.onLobby(binder: (Model, any) -> ())
	local bound: { [Instance]: boolean } = {}
	local function bind(child: Instance)
		if bound[child] or not child:IsA("Model") or child.Name ~= "Lobby" then
			return
		end
		bound[child] = true
		local trove = Trove.new()
		trove:connect(child.AncestryChanged, function()
			if not child:IsDescendantOf(workspace) then
				bound[child] = nil
				trove:clean()
			end
		end)
		task.spawn(binder, child, trove)
	end
	workspace.ChildAdded:Connect(bind)
	for _, child in workspace:GetChildren() do
		bind(child)
	end
end

function LobbyWatch.eachDescendant(model: Instance, trove: any, fn: (Instance) -> ())
	local seen: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function visit(inst: Instance)
		if not seen[inst] then
			seen[inst] = true
			fn(inst)
		end
	end
	trove:connect(model.DescendantAdded, visit)
	for _, inst in model:GetDescendants() do
		visit(inst)
	end
end

return LobbyWatch
