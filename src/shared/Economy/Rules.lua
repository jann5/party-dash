--!strict
-- Party Dash economy rules shared by the server (authority) and the client (shop UI previews).
-- Pure functions only: every number comes from Config so tuning stays in one place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Rules = {}

-- Remote names (Net.event). Requests go client -> server, Result goes server -> client.
Rules.Remote = {
	BuyUpgrade = "Economy_BuyUpgrade", -- (upgradeName: string)
	BuyCosmetic = "Economy_BuyCosmetic", -- (cosmeticId: string)
	Equip = "Economy_Equip", -- (cosmeticId: string) or (slot: string, cosmeticId: string; "" = default)
	Result = "Economy_Result", -- (ok: boolean, action: string, id: string, message: string)
}

-- Player attributes owned by Economy besides the ones in docs/ARCHITECTURE.md.
Rules.Attr = {
	Loaded = "EconomyLoaded", -- true once the saved profile is applied
	XPNext = "XPNext", -- XP needed to reach the next level
	Owned = "Owned_Cosmetics", -- CSV of owned cosmetic ids
	PassPrefix = "Pass_", -- Pass_DoubleCoins / Pass_VIP (booleans)
}

-- Display order + presentation of the four upgrades (prices/levels live in Config.UPGRADES).
Rules.UPGRADE_ORDER = { "DashCooldown", "DashDistance", "JumpBoost", "BatPower" }
Rules.UPGRADE_INFO = {
	DashCooldown = { icon = "⚡", blurb = "Dash again sooner", stat = "cooldown", color = Theme.Colors.Cyan },
	DashDistance = { icon = "💨", blurb = "Dash further", stat = "distance", color = Theme.Colors.Blue },
	JumpBoost = { icon = "🚀", blurb = "Jump higher", stat = "jump", color = Theme.Colors.Green },
	BatPower = { icon = "💥", blurb = "Bonk harder", stat = "bat power", color = Theme.Colors.Orange },
}

-- Coin packs sold for Robux (Config.PRODUCTS key -> coins), in shop order.
Rules.COIN_PACK_ORDER = { "Coins500", "Coins1500", "Coins5000" }
Rules.COIN_PACKS = { Coins500 = 500, Coins1500 = 1500, Coins5000 = 5000 }

-- Gamepasses in shop order with their pitch.
Rules.PASS_ORDER = { "DoubleCoins", "VIP" }
Rules.PASS_INFO = {
	DoubleCoins = { title = "2X COINS", blurb = "Earn double coins from every round, forever!", icon = "x2" },
	VIP = { title = "VIP", blurb = "Gold VIP name tag + the shiny gold VIP trail", icon = "VIP" },
}

Rules.MAX_RECEIPTS = 50
Rules.SOLO_COINS_PER_10S = 2

-- XP needed to go from level n to n + 1.
function Rules.xpForLevel(n: number): number
	return 50 + 25 * n
end

-- UTC day number (days since the Unix epoch).
function Rules.utcDay(t: number?): number
	return (t or os.time()) // 86400
end

function Rules.upgradeLevelOf(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, Config.UPGRADE_MAX_LEVEL)
end

-- Coin price of the NEXT level, or nil when the upgrade is maxed / unknown.
function Rules.upgradePrice(name: string, currentLevel: number): number?
	local def = Config.UPGRADES[name]
	if not def or currentLevel >= Config.UPGRADE_MAX_LEVEL then
		return nil
	end
	return def.prices[currentLevel + 1]
end

-- "-18%" style text for an upgrade at a level (0 -> "+0%").
function Rules.upgradeEffect(name: string, level: number): string
	local def = Config.UPGRADES[name]
	if not def then
		return ""
	end
	local pct = math.round(level * def.perLevel * 100)
	if pct > 0 then
		return ("+%d%%"):format(pct)
	elseif pct < 0 then
		return ("%d%%"):format(pct)
	end
	return "+0%"
end

-- Coins for one main round.
function Rules.roundCoins(
	survivedSeconds: number,
	isWinner: boolean,
	modifierRound: boolean,
	doubleCoins: boolean
): number
	local survived = math.max(0, tonumber(survivedSeconds) or 0)
	local coins = Config.COINS_PARTICIPATE + math.floor(survived / 10) * Config.COINS_PER_SURVIVAL_10S
	if isWinner then
		coins += Config.COINS_WIN
	end
	if modifierRound then
		coins *= Config.MODIFIER_COIN_MULTIPLIER
	end
	if doubleCoins then
		coins *= 2
	end
	return math.floor(coins)
end

-- Coins for a Solo Record run.
function Rules.soloCoins(seconds: number, doubleCoins: boolean): number
	local coins = math.floor(math.max(0, tonumber(seconds) or 0) / 10) * Rules.SOLO_COINS_PER_10S
	if doubleCoins then
		coins *= 2
	end
	return coins
end

-- Config.PRODUCTS key for a developer product id (read live, so tests may remap ids at runtime).
function Rules.productKey(productId: any): string?
	if type(productId) ~= "number" or productId == 0 then
		return nil
	end
	for key, id in Config.PRODUCTS do
		if id == productId then
			return key
		end
	end
	return nil
end

-- "UpgradeDashDistance" -> "DashDistance"
function Rules.upgradeFromProduct(key: string): string?
	local name = string.match(key, "^Upgrade(%w+)$")
	if name and Config.UPGRADES[name] then
		return name
	end
	return nil
end

-- 12345 -> "12,345"
function Rules.formatNumber(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (n < 0 and "-" or "") .. out
end

return Rules
