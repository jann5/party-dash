--!strict
-- Coins + XP for finished rounds and Solo runs, and the winners' equipped win effect.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Announce = require(script.Parent.Parent.Announce)
local Sessions = require(script.Parent.Sessions)
local Visuals = require(script.Parent.Visuals)

local Rewards = {}

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent == Players
end

-- Tolerant lookup: result tables are keyed by Player, but accept userId/name keys too.
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
	if v == nil then
		v = map[player.Name]
	end
	return v
end

-- Grants coins (+ the same amount of XP) and shows a toast. Returns the coins granted.
function Rewards.grant(player: Player, coins: number, reason: string, suffix: string?): number
	if coins <= 0 or not Sessions.get(player) then
		return 0
	end
	Sessions.addCoins(player, coins, reason)
	Sessions.addXP(player, coins)
	Announce.toast(player, ("+%d coins%s"):format(coins, suffix or ""), Theme.Colors.Yellow)
	return coins
end

-- Signals.RoundFinished payload (see src/server/Signals.lua). Returns { [Player]: coins } for tests.
function Rewards.roundFinished(result: any): { [Player]: number }
	local granted: { [Player]: number } = {}
	if type(result) ~= "table" then
		return granted
	end
	local winners: { [Player]: boolean } = {}
	local everyone: { Player } = {}
	local seen: { [Player]: boolean } = {}
	local function include(list: any, isWinner: boolean)
		if type(list) ~= "table" then
			return
		end
		for _, p in list do
			if isPlayer(p) then
				if isWinner then
					winners[p] = true
				end
				if not seen[p] then
					seen[p] = true
					table.insert(everyone, p)
				end
			end
		end
	end
	include(result.participants, false)
	include(result.winners, true)

	local modifierRound = type(result.modifierId) == "string" and result.modifierId ~= ""
	for _, p in everyone do
		local s = Sessions.get(p)
		if s then
			s.data.stats.rounds += 1
			local survived = tonumber(lookup(result.survived, p)) or 0
			local coins =
				Rules.roundCoins(survived, winners[p] == true, modifierRound, Sessions.hasPass(p, "DoubleCoins"))
			local suffix = if winners[p] then "  WINNER BONUS!" elseif modifierRound then "  (special round x2)" else ""
			granted[p] = Rewards.grant(p, coins, "round", suffix)
		end
	end

	-- win effects a beat after Core's own confetti
	for p in winners do
		local effect = p:GetAttribute("Cos_WinEffect")
		if type(effect) == "string" and effect ~= "" then
			task.delay(0.35, Visuals.winEffect, p, effect)
		end
	end
	return granted
end

-- Signals.SoloFinished(player, { minigameId, seconds, isRecord })
function Rewards.soloFinished(player: any, info: any): number
	if not isPlayer(player) or type(info) ~= "table" then
		return 0
	end
	local coins = Rules.soloCoins(tonumber(info.seconds) or 0, Sessions.hasPass(player, "DoubleCoins"))
	return Rewards.grant(player, coins, "solo", if info.isRecord == true then "  NEW RECORD!" else "")
end

return Rewards
