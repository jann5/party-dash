--!strict
--[[
Solo Record persistence.

	Personal bests   DataStore "PartyDash_Solo_v1", key "u_<userId>" -> { [minigameId] = bestMs }
	Global TOP 10    OrderedDataStore "PartyDash_SoloTop_<minigameId>", key "<userId>" -> bestMs

Every value is in integer milliseconds (OrderedDataStores only take integers). Longer survival is better.

Replication for the UI:
	Player attribute "SoloBest_<id>"         best time in seconds (missing = no record yet)
	ReplicatedStorage.SoloTop attribute <id> JSON list [{ n = name, t = seconds, u = userId }], best first

When DataStores are unavailable (unpublished place, Studio without API access, outages) everything keeps
working from memory for the lifetime of the server, with a warning.
]]
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Records = {}

Records.STORE_NAME = "PartyDash_Solo_v1"
Records.TOP_PREFIX = "PartyDash_SoloTop_"
Records.TOP_SIZE = 10
Records.ATTR_PREFIX = "SoloBest_"

export type TopEntry = { userId: number, name: string, ms: number }

type Profile = {
	loaded: boolean,
	bests: { [string]: number }, -- minigameId -> best ms
}

local profiles: { [number]: Profile } = {} -- by userId (kept after leaving so a late save still merges)
local names: { [number]: string } = {} -- userId -> display name cache
local topCache: { [string]: { TopEntry } } = {}
local memoryOnly = false
local warnedOnce: { [string]: boolean } = {}

local bestStore: DataStore? = nil
local orderedStores: { [string]: OrderedDataStore } = {}

local topFolder = ReplicatedStorage:FindFirstChild("SoloTop")
if not topFolder then
	local config = Instance.new("Configuration")
	config.Name = "SoloTop"
	config.Parent = ReplicatedStorage
	topFolder = config
end

local changedListeners: { (minigameId: string) -> () } = {}

-- Helpers -------------------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if not warnedOnce[key] then
		warnedOnce[key] = true
		warn("[Solo] " .. message)
	end
end

-- Errors that mean "DataStores will never work in this session".
local function isFatal(err: any): boolean
	local text = string.lower(tostring(err))
	return string.find(text, "studioaccesstoapisnotallowed", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
		or string.find(text, "api services", 1, true) ~= nil
		or string.find(text, "not allowed", 1, true) ~= nil
		or string.find(text, "403", 1, true) ~= nil
end

local function fail(what: string, err: any)
	if isFatal(err) then
		if not memoryOnly then
			memoryOnly = true
			warn(
				("[Solo] DataStores unavailable (%s: %s). Solo records are kept in memory for this server only."):format(
					what,
					tostring(err)
				)
			)
		end
	else
		warnOnce(what, ("%s failed: %s (keeping the in-memory value)"):format(what, tostring(err)))
	end
end

local function getBestStore(): DataStore?
	if memoryOnly then
		return nil
	end
	if bestStore then
		return bestStore
	end
	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, Records.STORE_NAME)
	if not ok then
		fail("GetDataStore", store)
		return nil
	end
	bestStore = store
	return store
end

local function getOrdered(minigameId: string): OrderedDataStore?
	if memoryOnly then
		return nil
	end
	local cached = orderedStores[minigameId]
	if cached then
		return cached
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, Records.TOP_PREFIX .. minigameId)
	if not ok then
		fail("GetOrderedDataStore", store)
		return nil
	end
	orderedStores[minigameId] = store
	return store
end

local function isValidMs(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v < 1e9
end

local function profileOf(userId: number): Profile
	local profile = profiles[userId]
	if not profile then
		profile = { loaded = false, bests = {} }
		profiles[userId] = profile
	end
	return profile
end

local function publishAttributes(player: Player)
	local profile = profiles[player.UserId]
	if not profile or player.Parent ~= Players then
		return
	end
	for id, ms in profile.bests do
		player:SetAttribute(Records.ATTR_PREFIX .. id, math.floor(ms / 10 + 0.5) / 100)
	end
end

local function publishTop(minigameId: string)
	local out = {}
	for _, e in topCache[minigameId] or {} do
		table.insert(out, { n = e.name, t = e.ms / 1000, u = e.userId })
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, out)
	if ok then
		(topFolder :: Instance):SetAttribute(minigameId, json)
	end
	for _, fn in changedListeners do
		task.spawn(fn, minigameId)
	end
end

-- Inserts/raises one entry in the cached top list (keeps it sorted and capped).
local function mergeTop(minigameId: string, entry: TopEntry)
	local list = topCache[minigameId] or {}
	local found = false
	for _, e in list do
		if e.userId == entry.userId then
			found = true
			if entry.ms > e.ms then
				e.ms = entry.ms
			end
			e.name = entry.name
			break
		end
	end
	if not found then
		table.insert(list, { userId = entry.userId, name = entry.name, ms = entry.ms })
	end
	table.sort(list, function(a, b)
		if a.ms ~= b.ms then
			return a.ms > b.ms
		end
		return a.userId < b.userId
	end)
	while #list > Records.TOP_SIZE do
		table.remove(list)
	end
	topCache[minigameId] = list
end

local function resolveNames(userIds: { number })
	local missing = {}
	for _, id in userIds do
		if not names[id] then
			local player = Players:GetPlayerByUserId(id)
			if player then
				names[id] = player.DisplayName
			elseif id > 0 then
				table.insert(missing, id)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				names[info.Id] = if type(info.DisplayName) == "string" and info.DisplayName ~= ""
					then info.DisplayName
					else tostring(info.Username)
			end
		end
	end
	for _, id in missing do
		if not names[id] then
			local okName, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
			if okName and type(name) == "string" then
				names[id] = name
			end
		end
	end
end

local function nameOf(userId: number): string
	return names[userId] or ("Player " .. tostring(userId))
end

-- Public API ----------------------------------------------------------------------------------------

function Records.isMemoryOnly(): boolean
	return memoryOnly
end

-- Called with a minigameId whenever its global top list changed.
function Records.onTopChanged(fn: (minigameId: string) -> ())
	table.insert(changedListeners, fn)
end

-- Loads a player's bests (yields). Safe to call more than once.
function Records.load(player: Player)
	local userId = player.UserId
	names[userId] = player.DisplayName
	local profile = profileOf(userId)
	if profile.loaded then
		publishAttributes(player)
		return
	end
	if game.PlaceId == 0 then
		if not memoryOnly then
			memoryOnly = true
			warn("[Solo] This place is not published: Solo records are kept in memory for this server only.")
		end
	end
	local store = getBestStore()
	if store then
		local ok, data = pcall(store.GetAsync, store, "u_" .. userId)
		if ok then
			if type(data) == "table" then
				for id, ms in data do
					if type(id) == "string" and isValidMs(ms) then
						profile.bests[id] = math.max(profile.bests[id] or 0, math.floor(ms))
					end
				end
			end
		else
			fail("GetAsync", data)
		end
	end
	profile.loaded = true
	publishAttributes(player)
end

-- Best time in seconds, or nil when the player has no record for this minigame.
function Records.getBest(player: Player, minigameId: string): number?
	local profile = profiles[player.UserId]
	local ms = profile and profile.bests[minigameId]
	return if ms then ms / 1000 else nil
end

function Records.getBestMs(userId: number, minigameId: string): number?
	local profile = profiles[userId]
	return profile and profile.bests[minigameId] or nil
end

-- Submits a finished run. Returns (isRecord, previousBestSeconds?). Persists in the background.
function Records.submit(player: Player, minigameId: string, seconds: number): (boolean, number?)
	local userId = player.UserId
	local profile = profileOf(userId)
	local ms = math.floor(seconds * 1000)
	local previous = profile.bests[minigameId]
	if not isValidMs(ms) or (previous and ms <= previous) then
		return false, if previous then previous / 1000 else nil
	end
	profile.bests[minigameId] = ms
	if player.Parent == Players then
		names[userId] = player.DisplayName
		player:SetAttribute(Records.ATTR_PREFIX .. minigameId, math.floor(ms / 10 + 0.5) / 100)
	end
	mergeTop(minigameId, { userId = userId, name = nameOf(userId), ms = ms })
	publishTop(minigameId)

	task.spawn(function()
		local store = getBestStore()
		if store then
			local ok, err = pcall(store.UpdateAsync, store, "u_" .. userId, function(old: any)
				local data = if type(old) == "table" then old else {}
				local current = data[minigameId]
				if isValidMs(current) and current >= ms then
					return nil -- a better time is already saved (another server): keep it
				end
				data[minigameId] = ms
				return data
			end)
			if not ok then
				fail("UpdateAsync", err)
			end
		end
		local ordered = getOrdered(minigameId)
		if ordered then
			local ok, err = pcall(ordered.UpdateAsync, ordered, tostring(userId), function(old: any)
				if isValidMs(old) and old >= ms then
					return nil
				end
				return ms
			end)
			if not ok then
				fail("OrderedDataStore UpdateAsync", err)
			end
		end
	end)
	return true, if previous then previous / 1000 else nil
end

-- 1-based place of `userId` in the cached global top list, or nil when outside the TOP 10.
function Records.rankOf(minigameId: string, userId: number): number?
	for i, e in topCache[minigameId] or {} do
		if e.userId == userId then
			return i
		end
	end
	return nil
end

function Records.getTop(minigameId: string): { TopEntry }
	return table.clone(topCache[minigameId] or {})
end

-- Re-reads one global top list (yields). Results from this server's memory are merged in so a fresh
-- record shows up even before the OrderedDataStore catches up.
function Records.refreshTop(minigameId: string)
	local ordered = getOrdered(minigameId)
	local fetched: { TopEntry }? = nil
	if ordered then
		local ok, pages = pcall(ordered.GetSortedAsync, ordered, false, Records.TOP_SIZE)
		if ok then
			local okPage, page = pcall(pages.GetCurrentPage, pages)
			if okPage and type(page) == "table" then
				local list = {}
				local ids = {}
				for _, item in page do
					local userId = tonumber(item.key)
					if userId and isValidMs(item.value) then
						table.insert(list, { userId = userId, name = "", ms = math.floor(item.value) })
						table.insert(ids, userId)
					end
				end
				resolveNames(ids)
				for _, e in list do
					e.name = nameOf(e.userId)
				end
				fetched = list
			end
		else
			fail("GetSortedAsync", pages)
		end
	end
	if fetched then
		topCache[minigameId] = {}
		for _, e in fetched do
			mergeTop(minigameId, e)
		end
	end
	-- Memory always contributes (it is the only source when DataStores are unavailable).
	for userId, profile in profiles do
		local ms = profile.bests[minigameId]
		if ms then
			mergeTop(minigameId, { userId = userId, name = nameOf(userId), ms = ms })
		end
	end
	topCache[minigameId] = topCache[minigameId] or {}
	publishTop(minigameId)
end

return Records
