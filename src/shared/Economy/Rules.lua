--!strict
-- Party Dash economy rules v2, shared by the server (authority) and the client (shop, wheel, calendar, results UI).
-- Pure data + pure functions only. Tuning lives here and in Config, never in UI code.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local C = Theme.Colors

local Rules = {}

-- Remotes (all via Shared.Net). See docs/ARCHITECTURE.md "Remotes" for payloads.
Rules.Remote = {
	BuyUpgrade = "Economy_BuyUpgrade", -- C->S (upgradeName)
	BuyCosmetic = "Economy_BuyCosmetic", -- C->S (cosmeticId)
	Equip = "Economy_Equip", -- C->S (cosmeticId) or (slot, cosmeticId; "" = default)
	Result = "Economy_Result", -- S->C (ok, action, id, message)
	Claim = "Economy_Claim", -- RemoteFunction (kind "daily"|"group"|"gift") -> { ok, reward, message }
	Spin = "Economy_Spin", -- RemoteFunction () -> { ok, index, prize, spinsLeft, usedFree, message }
	UseRevive = "Economy_UseRevive", -- C->S (); reply on Result with action "revive"
	Settings = "Economy_Settings", -- C->S ({ music, sfx, shake })
	DevBuy = "Economy_DevBuy", -- C->S (productKey), Studio only
	Reward = "Economy_Reward", -- S->C (kind, payload) for reveal animations
}

-- Player attributes owned by Economy (the full table is in docs/ARCHITECTURE.md).
Rules.Attr = {
	Loaded = "EconomyLoaded", -- true once the saved profile is applied
	XPNext = "XPNext", -- XP needed to reach the next level
	Owned = "Owned_Cosmetics", -- CSV of owned cosmetic ids
	PassPrefix = "Pass_", -- Pass_DoubleCoins / Pass_VIP (booleans)
	Spins = "Spins",
	FreeSpinReady = "FreeSpinReady",
	DailyReady = "DailyReady",
	CalendarDay = "CalendarDay", -- the calendar day (1..7) the NEXT daily claim pays out
	LoginStreak = "LoginStreak",
	GroupReady = "GroupReady",
	GiftIndex = "GiftIndex", -- next playtime gift (1-based)
	GiftAt = "GiftAt", -- server time it becomes claimable
	BoostUntil = "BoostUntil", -- server time the 2x coins boost ends
	ReviveTokens = "ReviveTokens",
	StarterOwned = "StarterOwned",
	FirstJoin = "FirstJoin",
	RoundStreak = "RoundStreak",
	PaidRandomRestricted = "PaidRandomRestricted",
	LastReward = "LastReward", -- JSON { total, xp, lines = { { label, coins } } }
	SetMusic = "Set_Music",
	SetSFX = "Set_SFX",
	SetShake = "Set_Shake",
}

-- Upgrades: display order + presentation (prices/levels live in Config.UPGRADES). Icons are Assets keys.
Rules.UPGRADE_ORDER = { "DashCooldown", "DashDistance", "JumpBoost", "BatPower" }
Rules.UPGRADE_INFO = {
	DashCooldown = { icon = "hourglass", blurb = "Dash again sooner", stat = "cooldown", color = C.Cyan },
	DashDistance = { icon = "speed_shoe", blurb = "Dash further", stat = "distance", color = C.Blue },
	JumpBoost = { icon = "spring", blurb = "Jump higher", stat = "jump", color = C.Green },
	BatPower = { icon = "bat", blurb = "Bonk harder", stat = "bat power", color = C.Orange },
}

-- Coin packs sold for Robux (Shared.Products key -> coins), in shop order.
Rules.COIN_PACK_ORDER = { "Coins500", "Coins1500", "Coins5000" }
Rules.COIN_PACKS = { Coins500 = 500, Coins1500 = 1500, Coins5000 = 5000 }

-- Gamepasses in shop order with their pitch.
Rules.PASS_ORDER = { "DoubleCoins", "VIP" }
Rules.PASS_INFO = {
	DoubleCoins = { title = "2X COINS", blurb = "Double coins from every round, forever!", icon = "coins_x2" },
	VIP = { title = "VIP", blurb = "Gold tag, VIP Gold trail, +20% coins, +1 free spin a day", icon = "vip_ticket" },
}
Rules.VIP_COIN_MULT = 1.2
Rules.VIP_DAILY_SPINS = 1

-- One-time and limited Robux bundles (brief #30, #31).
Rules.STARTER = { coins = 1000, item = "TrailStarter", boostSeconds = 30 * 60, refundCoins = 1000 }
Rules.GALAXY = { item = "TrailGalaxy", dupCoins = 1500 }

Rules.MAX_RECEIPTS = 100
Rules.SOLO_COINS_PER_10S = 2
Rules.SOLO_MAX_SECONDS = 180 -- Solo pays for at most 3 minutes per run (no AFK farming)
Rules.XP_PER_ROUND = 10
Rules.WIN_STREAK_STEP = 5
Rules.WIN_STREAK_MAX = 20

-- Reward bundle: what every reward source hands to Economy.applyBundle.
export type Bundle = {
	coins: number?,
	xp: number?,
	spins: number?,
	revives: number?,
	boostSeconds: number?,
	items: { string }?,
	dupCoins: number?, -- coins per item already owned (default: the item's coin value)
	chest: string?, -- "Rare" | "Epic": a random cosmetic of that rarity the player doesn't own (see CHESTS)
	pool: { string }?, -- one random item from this list (wheel trails)
}

-- WHEEL OF FORTUNE (brief #29, GAME_DESIGN 5.3) -------------------------------------------------------
-- Slices in WHEEL-FACE ORDER: slice 1 is the wedge at 12 o'clock, then clockwise (Assets.Art.wheel_face draws
-- 8 equal wedges Red, Yellow, Blue, Green, Purple, Orange, Cyan, Pink). `odds` are percent and sum to 100.
export type Slice = {
	id: string,
	label: string,
	icon: string, -- Assets icon key
	color: Color3, -- the wedge color on the wheel face
	odds: number,
	reward: Bundle,
}

Rules.WHEEL_TRAILS = { "TrailLightning", "TrailBubbles", "TrailLava", "TrailSnowflake" }

Rules.WHEEL = {
	{ id = "Coins50", label = "50", icon = "coin", color = C.Red, odds = 30, reward = { coins = 50 } },
	{ id = "Coins100", label = "100", icon = "coin_stack", color = C.Yellow, odds = 22, reward = { coins = 100 } },
	{ id = "Coins250", label = "250", icon = "coin_sack", color = C.Blue, odds = 14, reward = { coins = 250 } },
	{
		id = "Boost",
		label = "2x 15m",
		icon = "coins_x2",
		color = C.Green,
		odds = 12,
		reward = { boostSeconds = 15 * 60 },
	},
	{ id = "Spin", label = "+1 Spin", icon = "spin_ticket", color = C.Purple, odds = 8, reward = { spins = 1 } },
	{
		id = "Trail",
		label = "Trail",
		icon = "trail_lightning",
		color = C.Orange,
		odds = 8, -- 2% for each of the 4 wheel trails; 400 coins instead if you already own the one you hit
		reward = { pool = Rules.WHEEL_TRAILS, dupCoins = 400 },
	},
	{ id = "Coins1000", label = "1,000", icon = "coin_chest", color = C.Cyan, odds = 4, reward = { coins = 1000 } },
	{
		id = "GoldenBomb",
		label = "Golden Bomb",
		icon = "bomb",
		color = C.Pink,
		odds = 2,
		reward = { items = { "GoldenBomb" }, dupCoins = 2500 },
	},
} :: { Slice }

local fallbackRng = Random.new()

function Rules.wheelOddsTotal(): number
	local total = 0
	for _, slice in Rules.WHEEL do
		total += slice.odds
	end
	return total
end

-- Rolls one slice index (1..#WHEEL) weighted by odds. Pure given `rng` (pass a seeded Random in tests).
function Rules.rollWheel(rng: Random?): number
	local r = (rng or fallbackRng):NextInteger(1, Rules.wheelOddsTotal())
	for i, slice in Rules.WHEEL do
		r -= slice.odds
		if r <= 0 then
			return i
		end
	end
	return #Rules.WHEEL
end

-- DAILY CHEST CALENDAR (brief #27, GAME_DESIGN 5.4) -------------------------------------------------
-- One claim per UTC day; missing a day restarts at Day 1. After Day 7 it loops to Day 1 while the login streak
-- keeps counting.
Rules.DAILY = {
	{ day = 1, label = "100", icon = "coin", reward = { coins = 100 } },
	{ day = 2, label = "150", icon = "coin_stack", reward = { coins = 150 } },
	{ day = 3, label = "1 Spin", icon = "spin_ticket", reward = { spins = 1 } },
	{ day = 4, label = "250", icon = "coin_sack", reward = { coins = 250 } },
	{ day = 5, label = "Rare Chest", icon = "chest_daily", reward = { chest = "Rare" } },
	{ day = 6, label = "400", icon = "coin_chest", reward = { coins = 400 } },
	{ day = 7, label = "Epic Chest", icon = "mega_chest", reward = { chest = "Epic", boostSeconds = 30 * 60 } },
}

-- Chests hand out a random cosmetic of that rarity the player doesn't own yet, or coins when they own them all.
Rules.CHESTS = {
	Rare = { rarity = "Rare", fallbackCoins = 500, icon = "chest_daily" },
	Epic = { rarity = "Epic", fallbackCoins = 1200, icon = "mega_chest" },
}

-- GROUP CHEST (brief #27): members only, once per UTC day; the very first claim adds a spin.
Rules.GROUP = { coins = 150, firstSpins = 1 }

-- PLAYTIME GIFTS (GAME_DESIGN 5.6): seconds since the session started; tap to claim.
Rules.GIFTS = {
	{ at = 2 * 60, icon = "coin", reward = { coins = 40 } },
	{ at = 5 * 60, icon = "coin_stack", reward = { coins = 60 } },
	{ at = 10 * 60, icon = "spin_ticket", reward = { spins = 1 } },
	{ at = 15 * 60, icon = "coin_sack", reward = { coins = 120 } },
	{ at = 25 * 60, icon = "chest_daily", reward = { chest = "Rare" } },
	{ at = 40 * 60, icon = "coins_x2", reward = { coins = 250, boostSeconds = 15 * 60 } },
}
Rules.GIFT_REPEAT_EVERY = 20 * 60
Rules.GIFT_REPEAT = { icon = "coin_sack", reward = { coins = 150 } }

-- Seconds after the session start at which gift `index` (1-based) becomes claimable.
function Rules.giftOffset(index: number): number
	local n = #Rules.GIFTS
	if index <= n then
		return Rules.GIFTS[math.max(1, index)].at
	end
	return Rules.GIFTS[n].at + (index - n) * Rules.GIFT_REPEAT_EVERY
end

function Rules.giftReward(index: number): Bundle
	local gift = Rules.GIFTS[index] or Rules.GIFT_REPEAT
	return gift.reward
end

-- LEVELS (GAME_DESIGN 6.2) ------------------------------------------------------------------------

-- XP needed to go from level n to n + 1.
function Rules.xpForLevel(n: number): number
	return 50 + 25 * n
end

-- Reward for reaching `level`: 20 + 5 x level coins, and a spin every 5th level.
function Rules.levelReward(level: number): { coins: number, spins: number }
	return { coins = 20 + 5 * level, spins = if level % 5 == 0 then 1 else 0 }
end

-- TIME --------------------------------------------------------------------------------------------

-- UTC day number (days since the Unix epoch). Clients pass workspace:GetServerTimeNow().
function Rules.utcDay(t: number?): number
	return math.floor(t or os.time()) // 86400
end

-- Daily calendar state from the stored fields. Returns (ready, dayToClaim, streakAfterClaim).
function Rules.dailyState(lastDaily: number, calendarDay: number, loginStreak: number, today: number)
	if lastDaily >= today then
		return false, calendarDay, loginStreak
	end
	if lastDaily == today - 1 then
		return true, calendarDay, loginStreak + 1
	end
	return true, 1, 1 -- never claimed, or missed a day: back to Day 1
end

-- ROUND COINS v2 (GAME_DESIGN 1.6) ----------------------------------------------------------------
export type RoundInput = {
	participants: number, -- how many started the round
	placement: number?, -- 1-based finishing place
	winner: boolean, -- in result.winners
	survived: number, -- seconds
	kos: number,
	mvp: boolean,
	winStreak: number, -- leaderstats Streak after this round (winners)
	roundStreak: number, -- Player RoundStreak (consecutive rounds played)
	modifier: boolean, -- a modifier round
	double: boolean, -- 2X Coins pass or an active 2x boost (never x4)
	vip: boolean,
	firstWin: boolean, -- first counted win of this UTC day
}
export type Line = { label: string, coins: number }
export type RoundReward = { total: number, xp: number, base: number, lines: { Line } }

local PLACE_LABEL = { "1st place", "2nd place", "3rd place" }

function Rules.roundStreakMult(streak: number): number
	local mult = Config.ROUND_STREAK_MULT
	return mult[math.clamp(math.floor(streak), 1, #mult)]
end

-- A lone player never "wins": placement, win-streak and first-win bonuses need 2+ participants (anti-farm,
-- same rule as Core's Wins leaderstat). Placement: 3+ participants pay 1st/2nd/3rd; exactly 2 pay the winner.
function Rules.placementBonus(participants: number, placement: number?, winner: boolean): (number, string?)
	if participants >= 3 then
		local place = placement or (if winner then 1 else nil)
		local pay = { Config.COINS_WIN, Config.COINS_SECOND, Config.COINS_THIRD }
		if place and pay[place] then
			return pay[place], PLACE_LABEL[place]
		end
	elseif participants == 2 and winner then
		return Config.COINS_WIN, PLACE_LABEL[1]
	end
	return 0, nil
end

-- base  = played + survived + placement + KOs + MVP + win streak
-- coins = floor(base * roundStreak * modifier * (2x pass or boost) * VIP) + first win of the day
-- XP    = base + 10 (before multipliers, so the Level board can't be bought)
-- The lines always add up to `total`: each multiplier line is the extra coins that multiplier added.
function Rules.roundReward(input: RoundInput): RoundReward
	local lines: { Line } = {}
	local function line(label: string, coins: number)
		if coins ~= 0 then
			table.insert(lines, { label = label, coins = coins })
		end
	end

	local counted = input.participants >= 2
	local winner = counted and input.winner
	local survivedPay = math.floor(math.max(0, input.survived) / 10) * Config.COINS_PER_SURVIVAL_10S
	local placePay, placeLabel = Rules.placementBonus(input.participants, input.placement, winner)
	local kos = math.clamp(math.floor(input.kos), 0, Config.COINS_KO_CAP)
	local streakPay = 0
	if winner and input.winStreak >= 2 then
		streakPay = math.min(Rules.WIN_STREAK_STEP * (math.floor(input.winStreak) - 1), Rules.WIN_STREAK_MAX)
	end

	line("Played", Config.COINS_PARTICIPATE)
	line("Survived", survivedPay)
	if placeLabel then
		line(placeLabel, placePay)
	end
	line(("KOs x%d"):format(kos), kos * Config.COINS_PER_KO)
	line("MVP", if input.mvp then Config.COINS_MVP else 0)
	line("Win streak", streakPay)

	local base = Config.COINS_PARTICIPATE
		+ survivedPay
		+ placePay
		+ kos * Config.COINS_PER_KO
		+ (if input.mvp then Config.COINS_MVP else 0)
		+ streakPay

	-- Multipliers, applied in order; each line is the floor of the running product minus the previous one.
	local factor = 1
	local shown = base
	local function multiply(label: string, by: number)
		if by == 1 then
			return
		end
		factor *= by
		local now = math.floor(base * factor + 1e-6)
		line(label, now - shown)
		shown = now
	end
	local streakMult = Rules.roundStreakMult(input.roundStreak)
	multiply(("Streak x%.1f"):format(streakMult), streakMult)
	multiply("Bonus round", if input.modifier then Config.MODIFIER_COIN_MULTIPLIER else 1)
	multiply("2x Coins", if input.double then 2 else 1)
	multiply("VIP", if input.vip then Rules.VIP_COIN_MULT else 1)

	local total = shown
	if winner and input.firstWin then
		line("First win!", Config.COINS_FIRST_WIN_OF_DAY)
		total += Config.COINS_FIRST_WIN_OF_DAY
	end
	return { total = total, xp = base + Rules.XP_PER_ROUND, base = base, lines = lines }
end

-- Coins for a Solo Record run (capped, nothing under 10 s). Returns (coins, base before the 2x).
function Rules.soloCoins(seconds: number, double: boolean): (number, number)
	local paid = math.min(math.max(0, tonumber(seconds) or 0), Rules.SOLO_MAX_SECONDS)
	local base = math.floor(paid / 10) * Rules.SOLO_COINS_PER_10S
	return if double then base * 2 else base, base
end

-- UPGRADES ----------------------------------------------------------------------------------------

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

-- "UpgradeDashDistance" -> "DashDistance"
function Rules.upgradeFromProduct(key: string): string?
	local name = string.match(key, "^Upgrade(%w+)$")
	if name and Config.UPGRADES[name] then
		return name
	end
	return nil
end

-- FORMATTING --------------------------------------------------------------------------------------

-- 12345 -> "12,345"
function Rules.formatNumber(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if n < 0 then "-" else "") .. out
end

return Rules
