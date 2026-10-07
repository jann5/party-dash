--!strict
-- Profile data shape v2: defaults, migration + sanitizing of whatever comes back from the DataStore, serializing.
-- Stored record (DataStore "PartyDash_Profiles_v1", key "u_<userId>") = the fields below + `lock` (Sessions).
--
-- Forward compatibility (rolling updates, catalog edits): top-level keys this server doesn't know are kept in
-- `extra`, and owned cosmetic ids missing from the catalog in `ownedUnknown`; both are written back untouched,
-- so an older server can never wipe newer data or Robux-bought items. `version` never goes down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

export type Settings = { music: boolean, sfx: boolean, shake: boolean }
export type Stats = { rounds: number, wins: number, kos: number, coinsEarned: number, robuxSpent: number }

export type Data = {
	version: number,
	coins: number,
	wins: number, -- mirrors leaderstats.Wins (Core increments it)
	xp: number, -- progress inside the current level
	level: number,
	upgrades: { [string]: number },
	ownedCosmetics: { [string]: boolean }, -- stored as an array of ids
	ownedUnknown: { string }, -- owned ids this catalog doesn't know (kept, never shown)
	equipped: { [string]: string },
	lastDaily: number, -- UTC day of the last daily chest claim
	calendarDay: number, -- 1..7: the calendar day the next claim pays out
	loginStreak: number, -- consecutive days claimed
	spins: number, -- wheel spin tokens
	freeSpinDay: number, -- UTC day the daily free spin was used
	vipSpinDay: number, -- UTC day the VIP bonus spin token was handed out
	groupDay: number, -- UTC day of the last group chest claim
	groupFirstClaimed: boolean,
	reviveTokens: number,
	boughtStarter: boolean,
	firstJoin: number, -- unix seconds (Galaxy Comet welcome deal = first 48 h)
	boostUntil: number, -- unix seconds the 2x coins boost ends
	firstWinDay: number, -- UTC day of the last "first win of the day" bonus
	settings: Settings,
	seenTutorial: boolean,
	receipts: { string }, -- last Rules.MAX_RECEIPTS PurchaseIds, oldest first
	stats: Stats,
	extra: { [string]: any }, -- unknown top-level keys from a newer server
}

local Profile = {}

Profile.VERSION = 2

local MAX_ID = 40
local MAX_COUNT = 1e12

-- Keys this version understands (everything else in a stored record goes to `extra`).
local KNOWN: { [string]: boolean } = {}
for _, key in
	{
		"version",
		"coins",
		"wins",
		"xp",
		"level",
		"upgrades",
		"ownedCosmetics",
		"equipped",
		"lastDaily",
		"calendarDay",
		"loginStreak",
		"spins",
		"freeSpinDay",
		"vipSpinDay",
		"groupDay",
		"groupFirstClaimed",
		"reviveTokens",
		"boughtStarter",
		"firstJoin",
		"boostUntil",
		"firstWinDay",
		"settings",
		"seenTutorial",
		"receipts",
		"stats",
		"lock",
	}
do
	KNOWN[key] = true
end

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

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID
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
		ownedUnknown = {},
		equipped = equipped,
		lastDaily = 0,
		calendarDay = 1,
		loginStreak = 0,
		spins = 0,
		freeSpinDay = 0,
		vipSpinDay = 0,
		groupDay = 0,
		groupFirstClaimed = false,
		reviveTokens = 0,
		boughtStarter = false,
		firstJoin = os.time(),
		boostUntil = 0,
		firstWinDay = 0,
		settings = { music = true, sfx = true, shake = true },
		seenTutorial = false,
		receipts = {},
		stats = { rounds = 0, wins = 0, kos = 0, coinsEarned = 0, robuxSpent = 0 },
		extra = {},
	}
end

-- Turns any stored value (nil, v1 records, newer records, garbage) into a valid v2 Data table.
function Profile.reconcile(raw: any): Data
	local data = Profile.default()
	if type(raw) ~= "table" then
		return data
	end
	data.version = math.max(Profile.VERSION, int(raw.version, 0))
	data.coins = int(raw.coins, 0, MAX_COUNT)
	data.wins = int(raw.wins, 0, MAX_COUNT)
	data.level = int(raw.level, 1, 100000)
	data.xp = math.min(int(raw.xp, 0), Rules.xpForLevel(data.level) - 1)
	data.lastDaily = int(raw.lastDaily, 0)
	data.calendarDay = int(raw.calendarDay, 1, #Rules.DAILY)
	data.loginStreak = int(raw.loginStreak, 0, 100000)
	data.spins = int(raw.spins, 0, 100000)
	data.freeSpinDay = int(raw.freeSpinDay, 0)
	data.vipSpinDay = int(raw.vipSpinDay, 0)
	data.groupDay = int(raw.groupDay, 0)
	data.groupFirstClaimed = raw.groupFirstClaimed == true
	data.reviveTokens = int(raw.reviveTokens, 0, 100000)
	data.boughtStarter = raw.boughtStarter == true
	data.boostUntil = int(raw.boostUntil, 0)
	data.firstWinDay = int(raw.firstWinDay, 0)
	data.seenTutorial = raw.seenTutorial == true
	local firstJoin = int(raw.firstJoin, 0)
	if firstJoin > 0 then
		data.firstJoin = firstJoin -- else: first time this profile is seen -> now (default)
	end

	if type(raw.upgrades) == "table" then
		for name in Config.UPGRADES do
			data.upgrades[name] = int(raw.upgrades[name], 0, Config.UPGRADE_MAX_LEVEL)
		end
	end

	-- owned cosmetics: array of ids (also accepts a { id = true } set); VIP items come from the pass, not the save
	if type(raw.ownedCosmetics) == "table" then
		for k, v in raw.ownedCosmetics do
			local id = if type(k) == "string" and v == true then k else v
			local item = Cosmetics.get(id)
			if item then
				if item.source ~= "vip" then
					data.ownedCosmetics[item.id] = true
				end
			elseif validId(id) and not table.find(data.ownedUnknown, id) then
				table.insert(data.ownedUnknown, id)
			end
		end
	end

	if type(raw.equipped) == "table" then
		for slot, id in raw.equipped do
			if type(slot) ~= "string" or not validId(slot) or type(id) ~= "string" or #id > MAX_ID then
				continue
			end
			local item = Cosmetics.get(id)
			if item and item.slot == slot then
				data.equipped[slot] = item.id -- ownership is re-checked when it is mirrored
			elseif not item and id ~= "" then
				data.equipped[slot] = id -- an item from a newer catalog: keep it saved, show the default
			end
		end
	end

	if type(raw.settings) == "table" then
		for _, key in { "music", "sfx", "shake" } do
			if type(raw.settings[key]) == "boolean" then
				(data.settings :: any)[key] = raw.settings[key]
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
		for key in data.stats do
			(data.stats :: any)[key] = int(raw.stats[key], 0, MAX_COUNT)
		end
	end

	for key, value in raw do
		if type(key) == "string" and not KNOWN[key] then
			data.extra[key] = value
		end
	end
	return data
end

-- Plain JSON-safe table for the DataStore (no lock; Sessions adds it).
function Profile.serialize(data: Data): { [string]: any }
	local owned = {}
	for id in data.ownedCosmetics do
		table.insert(owned, id)
	end
	for _, id in data.ownedUnknown do
		if not data.ownedCosmetics[id] then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	local record: { [string]: any } = {
		version = data.version,
		coins = data.coins,
		wins = data.wins,
		xp = data.xp,
		level = data.level,
		upgrades = table.clone(data.upgrades),
		ownedCosmetics = owned,
		equipped = table.clone(data.equipped),
		lastDaily = data.lastDaily,
		calendarDay = data.calendarDay,
		loginStreak = data.loginStreak,
		spins = data.spins,
		freeSpinDay = data.freeSpinDay,
		vipSpinDay = data.vipSpinDay,
		groupDay = data.groupDay,
		groupFirstClaimed = data.groupFirstClaimed,
		reviveTokens = data.reviveTokens,
		boughtStarter = data.boughtStarter,
		firstJoin = data.firstJoin,
		boostUntil = data.boostUntil,
		firstWinDay = data.firstWinDay,
		settings = table.clone(data.settings),
		seenTutorial = data.seenTutorial,
		receipts = table.clone(data.receipts),
		stats = table.clone(data.stats),
	}
	for key, value in data.extra do
		if record[key] == nil then
			record[key] = value
		end
	end
	return record
end

-- Deep copy (rollback point for a product grant that errors halfway).
function Profile.clone(data: Data): Data
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in value do
			out[k] = copy(v)
		end
		return out
	end
	return copy(data)
end

-- Cosmetic ownership: VIP items belong to the VIP pass holder, everything else to the profile.
function Profile.owns(data: Data, hasVip: boolean, item: Cosmetics.Item): boolean
	if item.source == "vip" then
		return hasVip
	end
	return data.ownedCosmetics[item.id] == true
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
