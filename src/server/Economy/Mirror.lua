--!strict
-- Mirrors a session's profile to Player attributes (+ leaderstats.Coins) so every client UI can read it.
-- Server-written attributes are authoritative: clients only ever read them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local Profile = require(script.Parent.Profile)
local Types = require(script.Parent.Types)

type Session = Types.Session

local A = Rules.Attr
local Mirror = {}

local function set(s: Session, name: string, value: any)
	s.player:SetAttribute(name, value)
end

function Mirror.owns(s: Session, item: Cosmetics.Item): boolean
	return Profile.owns(s.data, s.passes.VIP == true, item)
end

function Mirror.coins(s: Session)
	set(s, "Coins", s.data.coins)
	local stats = s.player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		coins.Value = s.data.coins
	end
end

function Mirror.level(s: Session)
	set(s, "Level", s.data.level)
	set(s, "XP", s.data.xp)
	set(s, A.XPNext, Rules.xpForLevel(s.data.level))
end

function Mirror.upgrades(s: Session)
	for name in Config.UPGRADES do
		set(s, "Upg_" .. name, s.data.upgrades[name] or 0)
	end
end

function Mirror.cosmetics(s: Session)
	for _, slot in Cosmetics.SLOTS do
		local id = s.data.equipped[slot] or ""
		local item = Cosmetics.get(id)
		if not item or not Mirror.owns(s, item) then
			id = "" -- unknown (newer catalog) or not owned (e.g. VIP trail while the pass check failed): keep it saved
		end
		set(s, Cosmetics.SLOT_INFO[slot].attr, id)
	end
	local ids = {}
	for id in s.data.ownedCosmetics do
		table.insert(ids, id)
	end
	if s.passes.VIP then
		for _, item in Cosmetics.all() do
			if item.source == "vip" then
				table.insert(ids, item.id)
			end
		end
	end
	table.sort(ids)
	set(s, A.Owned, table.concat(ids, ","))
end

function Mirror.passes(s: Session)
	for name in Config.GAMEPASSES do
		set(s, A.PassPrefix .. name, s.passes[name] == true)
	end
end

function Mirror.spins(s: Session)
	set(s, A.Spins, s.data.spins)
	set(s, A.FreeSpinReady, s.data.freeSpinDay ~= Rules.utcDay())
end

function Mirror.daily(s: Session)
	local ready, day = Rules.dailyState(s.data.lastDaily, s.data.calendarDay, s.data.loginStreak, Rules.utcDay())
	set(s, A.DailyReady, ready)
	set(s, A.CalendarDay, day)
	set(s, A.LoginStreak, s.data.loginStreak)
end

function Mirror.group(s: Session)
	local ready = Config.GROUP_ID ~= 0 and s.groupMember == true and s.data.groupDay ~= Rules.utcDay()
	set(s, A.GroupReady, ready)
end

function Mirror.gift(s: Session)
	set(s, A.GiftIndex, s.giftIndex)
	set(s, A.GiftAt, s.giftAt)
end

function Mirror.boost(s: Session)
	set(s, A.BoostUntil, s.data.boostUntil)
end

function Mirror.revives(s: Session)
	set(s, A.ReviveTokens, s.data.reviveTokens)
end

function Mirror.starter(s: Session)
	set(s, A.StarterOwned, s.data.boughtStarter)
	set(s, A.FirstJoin, s.data.firstJoin)
end

function Mirror.settings(s: Session)
	set(s, A.SetMusic, s.data.settings.music)
	set(s, A.SetSFX, s.data.settings.sfx)
	set(s, A.SetShake, s.data.settings.shake)
end

function Mirror.all(s: Session)
	Mirror.coins(s)
	Mirror.level(s)
	Mirror.upgrades(s)
	Mirror.passes(s)
	Mirror.cosmetics(s)
	Mirror.spins(s)
	Mirror.daily(s)
	Mirror.group(s)
	Mirror.gift(s)
	Mirror.boost(s)
	Mirror.revives(s)
	Mirror.starter(s)
	Mirror.settings(s)
	if s.data.seenTutorial then
		set(s, "Seen_Tutorial", true)
	end
end

return Mirror
