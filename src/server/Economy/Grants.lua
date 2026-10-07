--!strict
-- Every change to a player's wallet goes through here: coins, XP + level-ups, spins, revive tokens, 2x boosts,
-- cosmetics, upgrades. Nothing here yields, so a check followed by a grant is always atomic.
--
-- applyBundle(player, bundle, reason) is the one reward primitive (daily, group, gifts, wheel, products...):
--   bundle = { coins?, xp?, spins?, revives?, boostSeconds?, items?, dupCoins?, chest?, pool?, equip? }
--   -> Granted { coins, xp, spins, revives, boostSeconds, items, converted, levels }
-- Items already owned turn into coins (bundle.dupCoins, else the item's coin value).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Feedback = require(script.Parent.Feedback)
local Mirror = require(script.Parent.Mirror)
local Sessions = require(script.Parent.Sessions)
local Types = require(script.Parent.Types)

type Session = Types.Session
type Granted = Types.Granted

local Grants = {}

local rng = Random.new()
local MAX_GRANT = 1e9

local function now(): number
	return workspace:GetServerTimeNow()
end

local function whole(value: any): number
	local n = tonumber(value)
	if not n or n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), -MAX_GRANT, MAX_GRANT)
end

function Grants.boostActive(s: Session): boolean
	return s.data.boostUntil > now()
end

-- Coins (negative = spend). Returns the new balance, or nil while the profile is loading.
function Grants.addCoins(player: Player, amount: number, _reason: string?): number?
	local s = Sessions.get(player)
	if not s then
		return nil
	end
	local n = whole(amount)
	s.data.coins = math.max(0, s.data.coins + n)
	if n > 0 then
		s.data.stats.coinsEarned += n
	end
	Mirror.coins(s)
	return s.data.coins
end

-- XP with level-ups. Each new level pays Rules.levelReward (coins, a spin every 5th level), fires the
-- "levelup" reveal and the LevelUp jingle. Returns (levels gained, coins paid for them).
function Grants.addXP(player: Player, amount: number): (number, number)
	local s = Sessions.get(player)
	if not s then
		return 0, 0
	end
	local d = s.data
	d.xp += math.max(0, whole(amount))
	local gained, coins, spins = 0, 0, 0
	while d.xp >= Rules.xpForLevel(d.level) do
		d.xp -= Rules.xpForLevel(d.level)
		d.level += 1
		gained += 1
		local reward = Rules.levelReward(d.level)
		coins += reward.coins
		spins += reward.spins
	end
	if gained > 0 then
		d.coins += coins
		d.stats.coinsEarned += coins
		d.spins += spins
		Mirror.coins(s)
		Mirror.spins(s)
		Feedback.reward(player, "levelup", { level = d.level, coins = coins, spins = spins })
		Feedback.sound(player, "LevelUp")
		Feedback.toast(player, ("LEVEL UP! Lv %d"):format(d.level), Theme.Colors.Purple)
	end
	Mirror.level(s)
	return gained, coins
end

function Grants.setUpgrade(s: Session, name: string, level: number)
	if not Config.UPGRADES[name] then
		return
	end
	s.data.upgrades[name] = math.clamp(math.floor(level), 0, Config.UPGRADE_MAX_LEVEL)
	s.player:SetAttribute("Upg_" .. name, s.data.upgrades[name])
end

function Grants.equip(s: Session, slot: string, id: string)
	if not Cosmetics.isSlot(slot) then
		return
	end
	s.data.equipped[slot] = id
	Mirror.cosmetics(s)
end

-- Adds an owned cosmetic. Returns false when it was already owned (or unknown / VIP-only).
function Grants.giveItem(s: Session, id: string): boolean
	local item = Cosmetics.get(id)
	if not item or item.source == "vip" or Mirror.owns(s, item) then
		return false
	end
	s.data.ownedCosmetics[item.id] = true
	return true
end

function Grants.addBoost(s: Session, seconds: number)
	s.data.boostUntil = math.max(s.data.boostUntil, math.floor(now())) + seconds
	Mirror.boost(s)
end

-- Picks a random unowned coin-shop cosmetic of a chest's rarity; nil when the player owns them all.
function Grants.chestItem(s: Session, rarity: Cosmetics.Rarity): string?
	local choices = {}
	for _, item in Cosmetics.pool(rarity) do
		if not Mirror.owns(s, item) then
			table.insert(choices, item.id)
		end
	end
	if #choices == 0 then
		return nil
	end
	return choices[rng:NextInteger(1, #choices)]
end

-- Turns the random parts of a bundle (chest, pool) into concrete items/coins for this player.
function Grants.resolve(s: Session, bundle: Rules.Bundle): Rules.Bundle
	local out = table.clone(bundle)
	local items = if type(bundle.items) == "table" then table.clone(bundle.items) else {}
	local chest = type(bundle.chest) == "string" and Rules.CHESTS[bundle.chest]
	if chest then
		local id = Grants.chestItem(s, chest.rarity :: Cosmetics.Rarity)
		if id then
			table.insert(items, id)
		else
			out.coins = whole(out.coins) + chest.fallbackCoins
		end
	end
	local pool = bundle.pool
	if type(pool) == "table" and #pool > 0 then
		table.insert(items, pool[rng:NextInteger(1, #pool)])
	end
	out.chest = nil
	out.pool = nil
	out.items = items
	return out
end

-- The reward primitive (see header). `bundle.equip`: true = wear new items now, "empty" = only into empty slots.
-- Returns nil while the profile is loading.
function Grants.applyBundle(player: Player, bundle: any, reason: string?): Granted?
	local s = Sessions.get(player)
	if not s or type(bundle) ~= "table" then
		return nil
	end
	local b = Grants.resolve(s, bundle)
	local granted: Granted = {
		coins = math.max(0, whole(b.coins)),
		xp = 0,
		spins = math.max(0, whole(b.spins)),
		revives = math.max(0, whole(b.revives)),
		boostSeconds = math.max(0, whole(b.boostSeconds)),
		items = {},
		converted = {},
		levels = 0,
	}
	local equipMode = (bundle :: any).equip
	for _, id in b.items or {} do
		local item = Cosmetics.get(id)
		if not item then
			warn(("[Economy] %s: unknown cosmetic %s"):format(tostring(reason), tostring(id)))
		elseif Grants.giveItem(s, item.id) then
			table.insert(granted.items, item.id)
			local slotEmpty = (s.data.equipped[item.slot] or "") == ""
			if equipMode == true or (equipMode == "empty" and slotEmpty) then
				s.data.equipped[item.slot] = item.id
			end
		else
			table.insert(granted.converted, item.id)
			granted.coins += if b.dupCoins then whole(b.dupCoins) else Cosmetics.dupCoins(item)
		end
	end

	local d = s.data
	if granted.coins > 0 then
		d.coins += granted.coins
		d.stats.coinsEarned += granted.coins
		Mirror.coins(s)
	end
	if granted.spins > 0 then
		d.spins += granted.spins
		Mirror.spins(s)
	end
	if granted.revives > 0 then
		d.reviveTokens += granted.revives
		Mirror.revives(s)
	end
	if granted.boostSeconds > 0 then
		Grants.addBoost(s, granted.boostSeconds)
	end
	if #granted.items > 0 then
		Mirror.cosmetics(s)
	end
	local xp = math.max(0, whole(b.xp))
	if xp > 0 then
		granted.xp = xp
		local levels, levelCoins = Grants.addXP(player, xp)
		granted.levels = levels
		granted.coins += levelCoins
	end
	return granted
end

-- Short human text for a granted bundle ("+150 coins", "Galaxy Comet!", "+1 spin"...).
function Grants.describe(granted: Granted): string
	local parts = {}
	for _, id in granted.items do
		local item = Cosmetics.get(id)
		table.insert(parts, (if item then item.name else id) .. "!")
	end
	if granted.coins > 0 then
		table.insert(parts, ("+%s coins"):format(Rules.formatNumber(granted.coins)))
	end
	if granted.spins > 0 then
		table.insert(parts, ("+%d spin%s"):format(granted.spins, if granted.spins == 1 then "" else "s"))
	end
	if granted.revives > 0 then
		table.insert(parts, ("+%d revive%s"):format(granted.revives, if granted.revives == 1 then "" else "s"))
	end
	if granted.boostSeconds > 0 then
		table.insert(parts, ("2x coins %d min"):format(math.floor(granted.boostSeconds / 60)))
	end
	return table.concat(parts, "  ")
end

return Grants
