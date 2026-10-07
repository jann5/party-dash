--!strict
-- Round rewards v2 (GAME_DESIGN 1.5 / 1.6): coins + XP for every participant of a finished main round, the round
-- streak multiplier, first win of the day, the winners' win effect and the LastReward breakdown for the results card.
-- Solo runs pay a capped amount (no farming).
--
-- Player.LastReward = JSON { round, total, xp, lines = { { label, coins } } } where the lines add up to `total`
-- (= the exact Coins delta, including a "Level up!" line when the round's XP reached a new level).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Feedback = require(script.Parent.Feedback)
local Grants = require(script.Parent.Grants)
local Sessions = require(script.Parent.Sessions)
local Visuals = require(script.Parent.Visuals)

local Rewards = {}

local A = Rules.Attr

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

-- Tolerant lookup: result tables are keyed by Player, but accept userId (number or string) keys too
-- (results forwarded from another VM are re-keyed by userId).
local function lookup(map: any, player: Player): any
	if type(map) ~= "table" then
		return nil
	end
	local v = map[player]
	if v == nil then
		v = map[player.UserId]
	end
	if v == nil then
		v = map[tostring(player.UserId)]
	end
	return v
end

local function number(value: any): number
	local n = tonumber(value)
	if not n or n ~= n then
		return 0
	end
	return n
end

local function stat(player: Player, name: string): number
	local stats = player:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(name)
	return if v and v:IsA("IntValue") then v.Value else 0
end

local function streakOf(player: Player): number
	local v = player:GetAttribute(A.RoundStreak)
	return if type(v) == "number" then v else 0
end

-- Signals.RoundStarted: participants extend their round streak; everyone else in the lobby loses it.
function Rewards.roundStarted(info: any)
	if type(info) ~= "table" or type(info.participants) ~= "table" then
		return
	end
	local playing: { [Player]: boolean } = {}
	for _, p in info.participants do
		if isPlayer(p) then
			playing[p] = true
		end
	end
	for _, p in Players:GetPlayers() do
		if playing[p] then
			p:SetAttribute(A.RoundStreak, streakOf(p) + 1)
		elseif p:GetAttribute("InSolo") ~= true then
			p:SetAttribute(A.RoundStreak, 0)
		end
	end
end

-- Pays one participant. Returns the coins granted (the LastReward total).
local function payOne(p: Player, result: any, participants: number, isWinner: boolean, modifier: boolean): number
	local s = Sessions.get(p)
	if not s then
		return 0
	end
	local d = s.data
	local today = Rules.utcDay()
	local counted = participants >= 2
	local kos = math.max(0, math.floor(number(lookup(result.kos, p))))
	local reward = Rules.roundReward({
		participants = participants,
		placement = tonumber(lookup(result.placements, p)),
		winner = isWinner,
		survived = number(lookup(result.survived, p)),
		kos = kos,
		mvp = result.mvp == p,
		winStreak = stat(p, "Streak"),
		roundStreak = streakOf(p),
		modifier = modifier,
		double = Sessions.hasPass(p, "DoubleCoins") or Grants.boostActive(s),
		vip = Sessions.hasPass(p, "VIP"),
		firstWin = d.firstWinDay ~= today,
	})

	d.stats.rounds += 1
	d.stats.kos += kos
	if counted and isWinner then
		d.stats.wins += 1
		if d.firstWinDay ~= today then
			d.firstWinDay = today
		end
	end
	Grants.addCoins(p, reward.total, "round")
	local levels, levelCoins = Grants.addXP(p, reward.xp)
	local lines = reward.lines
	local total = reward.total
	if levels > 0 and levelCoins > 0 then
		table.insert(lines, { label = "Level up!", coins = levelCoins })
		total += levelCoins
	end
	p:SetAttribute(
		A.LastReward,
		HttpService:JSONEncode({
			round = number(result.roundNumber),
			total = total,
			xp = reward.xp,
			lines = lines,
		})
	)
	Feedback.toast(p, ("+%s coins"):format(Rules.formatNumber(total)), Theme.Colors.Yellow)
	return total
end

-- Signals.RoundFinished payload (see src/server/Signals.lua). Returns { [Player]: coins } for tests.
function Rewards.roundFinished(result: any): { [Player]: number }
	local granted: { [Player]: number } = {}
	if type(result) ~= "table" then
		return granted
	end
	local everyone: { Player } = {}
	local seen: { [Player]: boolean } = {}
	local participants = 0
	if type(result.participants) == "table" then
		for _, p in result.participants do
			if isPlayer(p) then
				participants += 1 -- everyone who started counts, even if they left since
				if not seen[p] then
					seen[p] = true
					table.insert(everyone, p)
				end
			end
		end
	end
	local winners: { [Player]: boolean } = {}
	if type(result.winners) == "table" then
		for _, p in result.winners do
			if isPlayer(p) then
				winners[p] = true
				if not seen[p] then
					seen[p] = true
					participants += 1
					table.insert(everyone, p)
				end
			end
		end
	end

	local modifier = type(result.modifierId) == "string" and result.modifierId ~= ""
	for _, p in everyone do
		if p.Parent == Players then
			granted[p] = payOne(p, result, participants, winners[p] == true, modifier)
		end
	end

	-- win effects a beat after Core's own confetti
	for p in winners do
		local effect = p:GetAttribute("Cos_WinEffect")
		if p.Parent == Players and type(effect) == "string" and effect ~= "" then
			task.delay(0.35, Visuals.winEffect, p, effect)
		end
	end
	return granted
end

-- Signals.SoloFinished(player, { minigameId, seconds, isRecord })
function Rewards.soloFinished(player: any, info: any): number
	if not isPlayer(player) or player.Parent ~= Players or type(info) ~= "table" then
		return 0
	end
	local s = Sessions.get(player)
	if not s then
		return 0
	end
	local double = Sessions.hasPass(player, "DoubleCoins") or Grants.boostActive(s)
	local coins, base = Rules.soloCoins(number(info.seconds), double)
	if coins <= 0 then
		return 0
	end
	Grants.addCoins(player, coins, "solo")
	Grants.addXP(player, base)
	local suffix = if info.isRecord == true then "  NEW RECORD!" else ""
	Feedback.toast(player, ("+%s coins%s"):format(Rules.formatNumber(coins), suffix), Theme.Colors.Yellow)
	return coins
end

return Rewards
