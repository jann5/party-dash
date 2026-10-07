--!strict
-- Free reward claims through Economy_Claim (RemoteFunction) -> { ok, reward?, message, ... }:
--   "daily" (brief #27): the 7-day calendar chest, once per UTC day; missing a day restarts at Day 1.
--   "group" (brief #27): +150 coins a day for group members (+1 spin on the very first claim).
--   "gift"  (GAME_DESIGN 5.6): playtime gifts on a session schedule; each one must be tapped.
-- Every claim checks and grants without yielding (the group check yields BEFORE, then re-checks).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local Feedback = require(script.Parent.Feedback)
local Grants = require(script.Parent.Grants)
local Limiter = require(script.Parent.Limiter)
local Mirror = require(script.Parent.Mirror)
local Sessions = require(script.Parent.Sessions)
local Types = require(script.Parent.Types)

type Session = Types.Session
export type ClaimResult = {
	ok: boolean,
	reward: Types.Granted?,
	message: string,
	[string]: any,
}

local Claims = {}

local busy: { [Player]: boolean } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function loading(): ClaimResult
	return { ok = false, message = "Your save is still loading..." }
end

-- Economy_Reward payload for the reveal UI: the granted bundle plus a few facts about the claim.
local function reveal(player: Player, kind: string, granted: Types.Granted?, extra: { [string]: any })
	local payload: { [string]: any } = if granted then table.clone(granted) :: any else {}
	for k, v in extra do
		payload[k] = v
	end
	Feedback.reward(player, kind, payload)
end

function Claims.daily(player: Player): ClaimResult
	local s = Sessions.get(player)
	if not s then
		return loading()
	end
	local d = s.data
	local today = Rules.utcDay()
	local ready, day, streak = Rules.dailyState(d.lastDaily, d.calendarDay, d.loginStreak, today)
	if not ready then
		return { ok = false, message = "Come back tomorrow!", nextAt = (today + 1) * 86400 }
	end
	local entry = Rules.DAILY[day]
	local bundle = table.clone(entry.reward) :: any
	bundle.equip = "empty"
	local granted = Grants.applyBundle(player, bundle, "daily")
	d.lastDaily = today
	d.loginStreak = streak
	d.calendarDay = day % #Rules.DAILY + 1
	Mirror.daily(s)
	reveal(player, "daily", granted, { day = day, streak = streak })
	Sessions.saveSoon(player)
	return {
		ok = true,
		reward = granted,
		day = day,
		streak = streak,
		message = ("Day %d: %s"):format(day, if granted then Grants.describe(granted) else ""),
	}
end

function Claims.group(player: Player): ClaimResult
	if Config.GROUP_ID == 0 then
		return { ok = false, message = "Coming soon!" }
	end
	local s = Sessions.get(player)
	if not s then
		return loading()
	end
	if s.data.groupDay == Rules.utcDay() then
		return { ok = false, message = "Come back tomorrow!" }
	end
	if busy[player] then
		return { ok = false, message = "Checking..." }
	end
	busy[player] = true
	local member = Sessions.checkGroupFresh(s) -- yields
	busy[player] = nil
	-- re-check everything after the yield
	local live = Sessions.get(player)
	local today = Rules.utcDay()
	if live ~= s then
		return loading()
	end
	Mirror.group(s)
	if not member then
		return { ok = false, notMember = true, message = "Join the group first!" }
	end
	if s.data.groupDay == today then
		return { ok = false, message = "Come back tomorrow!" }
	end
	local first = not s.data.groupFirstClaimed
	local granted = Grants.applyBundle(player, {
		coins = Rules.GROUP.coins,
		spins = if first then Rules.GROUP.firstSpins else 0,
	}, "group")
	s.data.groupDay = today
	s.data.groupFirstClaimed = true
	Mirror.group(s)
	reveal(player, "group", granted, { first = first })
	Sessions.saveSoon(player)
	return {
		ok = true,
		reward = granted,
		message = "Thanks for joining! " .. (if granted then Grants.describe(granted) else ""),
	}
end

function Claims.gift(player: Player): ClaimResult
	local s = Sessions.get(player)
	if not s then
		return loading()
	end
	if now() < s.giftAt then
		return { ok = false, message = "Not ready yet!", readyAt = s.giftAt }
	end
	local index = s.giftIndex
	local bundle = table.clone(Rules.giftReward(index)) :: any
	bundle.equip = "empty"
	local granted = Grants.applyBundle(player, bundle, "gift")
	s.giftIndex = index + 1
	s.giftAt = s.joinedAt + Rules.giftOffset(s.giftIndex)
	Mirror.gift(s)
	reveal(player, "gift", granted, { index = index })
	Sessions.saveSoon(player)
	return {
		ok = true,
		reward = granted,
		index = index,
		message = if granted then Grants.describe(granted) else "",
	}
end

local KINDS: { [string]: (Player) -> ClaimResult } = {
	daily = Claims.daily,
	group = Claims.group,
	gift = Claims.gift,
}

function Claims.claim(player: Player, kind: any): ClaimResult
	local fn = type(kind) == "string" and KINDS[kind]
	if not fn then
		return { ok = false, message = "Unknown reward" }
	end
	local ok, result = pcall(fn, player)
	if not ok then
		warn("[Economy] claim failed:", result)
		return { ok = false, message = "Try again!" }
	end
	return result
end

-- Test/debug hook: move the next playtime gift's ready time (server time).
function Claims.setGiftAt(player: Player, at: number): boolean
	local s = Sessions.get(player)
	if not s or type(at) ~= "number" then
		return false
	end
	s.giftAt = at
	Mirror.gift(s)
	return true
end

function Claims.start()
	Net.func(Rules.Remote.Claim).OnServerInvoke = function(player: Player, kind: any)
		if not Limiter.allow(player, "claim", 10, 2) then
			return { ok = false, message = "Slow down!" }
		end
		return Claims.claim(player, kind)
	end
end

return Claims
