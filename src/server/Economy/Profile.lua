--!strict
-- Profile data shape: defaults, sanitizing of whatever comes back from the DataStore, and serializing.
-- Stored record (DataStore "PartyDash_Profiles_v1", key "u_<userId>") = the fields below + `lock`.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

export type Data = {
	version: number,
	coins: number,
	wins: number,
	xp: number, -- progress inside the current level
	level: number,
	upgrades: { [string]: number },
	ownedCosmetics: { [string]: boolean }, -- stored as an array of ids
	equipped: { [string]: string },
	lastDaily: number, -- UTC day number of the last daily reward
	seenTutorial: boolean,
	receipts: { string }, -- last Rules.MAX_RECEIPTS PurchaseIds, oldest first
	stats: { rounds: number, coinsEarned: number },
}

local Profile = {}

Profile.VERSION = 1

local function int(value: any, min: number, max: number?): number
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return min
	end
	n = math.floor(n)
	if n < min then
		return min
	end
	if max and n > max then
		return max
	end
	return n
end

function Profile.default(): Data
	local upgrades = {}
	for name in Config.UPGRADES do
		upgrades[name] = 0
	end
	local equipped = {}
	for _, slot in Cosmetics.SLOTS do
		equipped[slot] = ""
	end
	return {
		version = Profile.VERSION,
		coins = 0,
		wins = 0,
		xp = 0,
		level = 1,
		upgrades = upgrades,
		ownedCosmetics = {},
		equipped = equipped,
		lastDaily = 0,
		seenTutorial = false,
		receipts = {},
		stats = { rounds = 0, coinsEarned = 0 },
	}
end

-- Turns any stored value (nil, old versions, garbage) into a valid Data table.
function Profile.reconcile(raw: any): Data
	local data = Profile.default()
	if type(raw) ~= "table" then
		return data
	end
	data.coins = int(raw.coins, 0)
	data.wins = int(raw.wins, 0)
	data.level = int(raw.level, 1)
	data.xp = math.min(int(raw.xp, 0), Rules.xpForLevel(data.level) - 1)
	data.lastDaily = int(raw.lastDaily, 0)
	data.seenTutorial = raw.seenTutorial == true

	if type(raw.upgrades) == "table" then
		for name in Config.UPGRADES do
			data.upgrades[name] = int(raw.upgrades[name], 0, Config.UPGRADE_MAX_LEVEL)
		end
	end

	-- owned cosmetics: array of ids (also accepts a { id = true } set)
	if type(raw.ownedCosmetics) == "table" then
		for k, v in raw.ownedCosmetics do
			local id = if type(k) == "string" and v == true then k else v
			local item = Cosmetics.get(id)
			if item and not item.vip then
				data.ownedCosmetics[item.id] = true
			end
		end
	end

	if type(raw.equipped) == "table" then
		for _, slot in Cosmetics.SLOTS do
			local id = raw.equipped[slot]
			local item = Cosmetics.get(id)
			if item and item.slot == slot then
				data.equipped[slot] = item.id -- ownership is re-checked when the profile is applied
			end
		end
	end

	if type(raw.receipts) == "table" then
		for _, id in raw.receipts do
			if type(id) == "string" and #id <= 100 then
				table.insert(data.receipts, id)
			end
		end
		while #data.receipts > Rules.MAX_RECEIPTS do
			table.remove(data.receipts, 1)
		end
	end

	if type(raw.stats) == "table" then
		data.stats.rounds = int(raw.stats.rounds, 0)
		data.stats.coinsEarned = int(raw.stats.coinsEarned, 0)
	end
	return data
end

-- Plain JSON-safe table for the DataStore (no lock; the Store adds it).
function Profile.serialize(data: Data): { [string]: any }
	local owned = {}
	for id in data.ownedCosmetics do
		table.insert(owned, id)
	end
	table.sort(owned)
	return {
		version = Profile.VERSION,
		coins = data.coins,
		wins = data.wins,
		xp = data.xp,
		level = data.level,
		upgrades = table.clone(data.upgrades),
		ownedCosmetics = owned,
		equipped = table.clone(data.equipped),
		lastDaily = data.lastDaily,
		seenTutorial = data.seenTutorial,
		receipts = table.clone(data.receipts),
		stats = table.clone(data.stats),
	}
end

function Profile.hasReceipt(data: Data, purchaseId: string): boolean
	return table.find(data.receipts, purchaseId) ~= nil
end

function Profile.addReceipt(data: Data, purchaseId: string)
	if Profile.hasReceipt(data, purchaseId) then
		return
	end
	table.insert(data.receipts, purchaseId)
	while #data.receipts > Rules.MAX_RECEIPTS do
		table.remove(data.receipts, 1)
	end
end

return Profile
