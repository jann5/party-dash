--!strict
-- Key/value backend for profiles: the real DataStore when available, otherwise an in-memory table
-- (Studio without API access). Both expose the same UpdateAsync-style `update(key, transform)` so the
-- session-locking logic in Sessions runs identically in either mode.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Store = {}

Store.NAME = "PartyDash_Profiles_v1"
Store.MAX_ATTEMPTS = 4

type Transform = (old: any) -> any

local mode: "datastore" | "memory" | nil = nil
local dataStore: DataStore? = nil
local memory: { [string]: string } = {} -- JSON copies, so callers can never alias stored tables
local ready = false

function Store.key(userId: number): string
	return "u_" .. tostring(userId)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

local function useMemory(reason: string)
	mode = "memory"
	dataStore = nil
	warn(
		("[Economy] DataStores unavailable (%s). Using in-memory profiles: progress lasts only for this server."):format(
			reason
		)
	)
end

-- Probes the DataStore once. Yields; call from a spawned thread.
function Store.init()
	if mode then
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Store.NAME)
	end)
	if not ok then
		useMemory(tostring(result))
	else
		dataStore = result
		-- A read probe tells us whether this place may access DataStores (Studio API access, publishing).
		local probeOk, err = pcall(function()
			return (result :: DataStore):GetAsync("__probe")
		end)
		if probeOk then
			mode = "datastore"
		elseif RunService:IsStudio() then
			useMemory(tostring(err))
		else
			-- live server: assume a transient outage and keep using the real store (with retries)
			mode = "datastore"
			warn("[Economy] DataStore probe failed, will retry per request:", err)
		end
	end
	ready = true
end

function Store.waitReady()
	while not ready do
		task.wait(0.05)
	end
end

function Store.mode(): string
	return mode or "pending"
end

function Store.isPersistent(): boolean
	return mode == "datastore"
end

local function waitForBudget()
	-- Don't burn retries while the per-server write budget is empty.
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)
		if not ok or budget > 0 then
			return
		end
		task.wait(0.5)
	end
end

-- UpdateAsync with retries + exponential backoff. `transform(old)` returns the new value, or nil to
-- cancel the write. Returns (ok, errorMessage?). Yields.
function Store.update(key: string, transform: Transform): (boolean, string?)
	Store.waitReady()
	if mode == "memory" then
		local raw = memory[key]
		local old = if raw then HttpService:JSONDecode(raw) else nil
		local ok, result = pcall(transform, deepCopy(old))
		if not ok then
			return false, tostring(result)
		end
		if result ~= nil then
			memory[key] = HttpService:JSONEncode(result)
		end
		return true, nil
	end

	local store = dataStore :: DataStore
	local lastErr = "unknown"
	for attempt = 1, Store.MAX_ATTEMPTS do
		waitForBudget()
		local ok, err = pcall(function()
			store:UpdateAsync(key, function(old)
				return transform(old)
			end)
		end)
		if ok then
			return true, nil
		end
		lastErr = tostring(err)
		if attempt < Store.MAX_ATTEMPTS then
			task.wait(2 ^ (attempt - 1) + math.random() * 0.5) -- 1s, 2s, 4s (+ jitter)
		end
	end
	warn(("[Economy] DataStore update failed for %s: %s"):format(key, lastErr))
	return false, lastErr
end

-- Read-only copy of what is stored (tests / debugging). Yields.
function Store.peek(key: string): any
	Store.waitReady()
	if mode == "memory" then
		local raw = memory[key]
		return if raw then HttpService:JSONDecode(raw) else nil
	end
	local ok, value = pcall(function()
		return (dataStore :: DataStore):GetAsync(key)
	end)
	return if ok then value else nil
end

return Store
