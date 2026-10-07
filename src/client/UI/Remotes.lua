--!nonstrict
-- Lazy access to remotes. Most remotes the HUD talks to belong to other pieces (Core, Economy) and may appear
-- late or never (tests, partial builds), so nothing here yields or errors:
--   Remotes.on("Core_Death", fn)          -- connects OnClientEvent as soon as the remote exists
--   Remotes.fire("Core_Vote", id)         -- fires now, or within a short grace period once it appears
--   Remotes.find("Economy_UseRevive")     -- non-yielding lookup
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FIRE_GRACE = 5 -- seconds a fire waits for a missing remote before it is dropped

-- Calls fn(child) once `parent` has a child called `name` (right away if it already has). Returns cancel().
local function onChild(parent: Instance, name: string, fn: (Instance) -> ()): () -> ()
	local existing = parent:FindFirstChild(name)
	if existing then
		fn(existing)
		return function() end
	end
	local conn
	conn = parent.ChildAdded:Connect(function(child)
		if child.Name == name then
			conn:Disconnect()
			fn(child)
		end
	end)
	return function()
		conn:Disconnect()
	end
end

-- Non-yielding lookup of ReplicatedStorage.Remotes.<name>.
function Remotes.find(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	return folder and folder:FindFirstChild(name) or nil
end

-- Runs fn(remote) when the remote exists (now or later). Returns cancel().
function Remotes.when(name: string, fn: (Instance) -> ()): () -> ()
	local cancelled = false
	local cancelInner: (() -> ())? = nil
	local cancelOuter = onChild(ReplicatedStorage, "Remotes", function(folder)
		if cancelled then
			return
		end
		cancelInner = onChild(folder, name, function(remote)
			if not cancelled then
				fn(remote)
			end
		end)
	end)
	return function()
		cancelled = true
		cancelOuter()
		if cancelInner then
			cancelInner()
		end
	end
end

-- Connects a client handler to a RemoteEvent whenever it shows up.
function Remotes.on(name: string, handler: (...any) -> ())
	Remotes.when(name, function(remote)
		if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
			remote.OnClientEvent:Connect(handler)
		end
	end)
end

-- Fires a RemoteEvent. A remote that is not there yet gets the call when it appears (within FIRE_GRACE s), so a
-- tap is never lost to a slow server boot. Returns true when it was sent immediately.
function Remotes.fire(name: string, ...: any): boolean
	local remote = Remotes.find(name)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(...)
		return true
	end
	local args = table.pack(...)
	local cancel
	cancel = Remotes.when(name, function(r)
		if r:IsA("RemoteEvent") then
			r:FireServer(table.unpack(args, 1, args.n))
		end
		task.defer(function()
			cancel()
		end)
	end)
	task.delay(FIRE_GRACE, cancel)
	return false
end

return Remotes
