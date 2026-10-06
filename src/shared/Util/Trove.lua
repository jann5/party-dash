-- Minimal cleanup bag. FROZEN CONTRACT.
--   local t = Trove.new()
--   t:add(instanceOrConnectionOrFunctionOrThread)  -> returns the same object
--   t:connect(signal, fn)                          -> RBXScriptConnection
--   t:clean()                                      -> destroys/disconnects/calls everything, newest first
local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({ _items = {} }, Trove)
end

function Trove:add(item)
	table.insert(self._items, item)
	return item
end

function Trove:connect(signal, fn)
	return self:add(signal:Connect(fn))
end

local function cleanup(item)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		pcall(task.cancel, item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.clean) == "function" then
			item:clean()
		end
	end
end

function Trove:clean()
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		local ok, err = pcall(cleanup, items[i])
		if not ok then
			warn("[Trove] cleanup failed:", err)
		end
	end
end

Trove.Destroy = Trove.clean

return Trove
