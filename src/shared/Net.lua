-- Party Dash: remote helper. FROZEN CONTRACT.
-- Remotes live in ReplicatedStorage.Remotes (created at runtime by the server, never in src/).
-- Name remotes "<Owner>_<Thing>", e.g. "LaserTracer_Hit", "Core_Announce", "Movement_Dash".
--   server: Net.event("LaserTracer_Hit")  -> creates if missing, returns RemoteEvent
--   client: Net.event("LaserTracer_Hit")  -> waits for it (up to 30s), returns RemoteEvent
-- Same for Net.func(name) with RemoteFunction.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local IS_SERVER = RunService:IsServer()

local function folder()
	local f = ReplicatedStorage:FindFirstChild("Remotes")
	if f then
		return f
	end
	if IS_SERVER then
		f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = ReplicatedStorage
		return f
	end
	return ReplicatedStorage:WaitForChild("Remotes")
end

local function get(name, className)
	local f = folder()
	local r = f:FindFirstChild(name)
	if r then
		return r
	end
	if IS_SERVER then
		r = Instance.new(className)
		r.Name = name
		r.Parent = f
		return r
	end
	r = f:WaitForChild(name, 30)
	if not r then
		error(("Net: remote %q never appeared"):format(name))
	end
	return r
end

function Net.event(name: string): RemoteEvent
	return get(name, "RemoteEvent")
end

function Net.unreliable(name: string): UnreliableRemoteEvent
	return get(name, "UnreliableRemoteEvent")
end

function Net.func(name: string): RemoteFunction
	return get(name, "RemoteFunction")
end

return Net
