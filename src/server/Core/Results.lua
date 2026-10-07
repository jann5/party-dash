--[[
Party Dash Core: turns a finished main round into stats, the result line, celebrations and Signals.RoundFinished.
The headline (GameState ResultText) is shown by the HUD's results card only: it is never sent as a big announcement
(that used to print it twice). Winners get their own "YOU WIN!" banner and confetti.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameState = require(Shared.GameState)
local Theme = require(Shared.Theme)

local Server = script.Parent.Parent
local Announce = require(Server.Announce)
local Signals = require(Server.Signals)
local Fx = require(script.Parent.Fx)
local Places = require(script.Parent.Places)
local PlayerSetup = require(script.Parent.PlayerSetup)

local Results = {}

local function names(players: { Player }): string
	local list = {}
	for _, p in players do
		table.insert(list, p.DisplayName)
	end
	return table.concat(list, " & ")
end

local function headline(r: { [string]: any }, winners: { Player }): string
	local participants: { Player } = r.participants
	if #winners == 1 then
		return string.upper(winners[1].DisplayName) .. " WINS!"
	elseif #winners == 2 then
		return string.upper(names(winners)) .. " WIN!"
	elseif #winners > 2 then
		return ("%d WINNERS!"):format(#winners)
	elseif #participants == 1 then
		local p = participants[1]
		if r.scores then
			return ("%s SCORED %d!"):format(string.upper(p.DisplayName), r.scores[p] or 0)
		end
		return ("%s LASTED %ds!"):format(string.upper(p.DisplayName), math.floor(r.survived[p] or r.duration))
	end
	return if r.scores then "NOBODY SCORED!" else "NOBODY SURVIVED!"
end

-- info = { roundNumber, minigameId, modifierId?, displayName }
function Results.apply(ctx: any, info: { [string]: any })
	local r = ctx:_results()
	local participants: { Player } = r.participants
	local winners: { Player } = {}
	-- A lone player can't "win" a round (no farming), but still gets a friendly result line.
	if #participants >= 2 then
		for _, p in r.winners do
			if p.Parent == Players then
				table.insert(winners, p)
			end
		end
	end
	local isWinner = {}
	for _, p in winners do
		isWinner[p] = true
	end

	-- Leaderstats: Wins and Streak (streaks only reset in real multiplayer rounds).
	for _, p in winners do
		local wins = PlayerSetup.stat(p, "Wins")
		local streak = PlayerSetup.stat(p, "Streak")
		if wins then
			wins.Value += 1
		end
		if streak then
			streak.Value += 1
		end
	end
	if #participants >= 2 then
		for _, p in participants do
			local streak = p.Parent == Players and not isWinner[p] and PlayerSetup.stat(p, "Streak")
			if streak then
				streak.Value = 0
			end
		end
	end

	local ids = {}
	for _, p in winners do
		table.insert(ids, tostring(p.UserId))
	end
	GameState.write("WinnersCsv", table.concat(ids, ","))
	GameState.write("ResultText", headline(r, winners))

	-- Celebrate: a personal banner for each winner, feed lines for everyone.
	local everyone = Places.audience()
	local gameName = info.displayName or info.minigameId
	for _, p in winners do
		local streak = PlayerSetup.stat(p, "Streak")
		local streakValue = streak and streak.Value or 0
		Announce.big(
			p,
			"YOU WIN!",
			if streakValue >= 2 then ("WIN STREAK x%d!"):format(streakValue) else nil,
			Theme.Colors.Gold
		)
		Fx.confetti(p)
		if streakValue >= 2 then
			Announce.feed(everyone, ("%s: %d WIN STREAK!"):format(p.DisplayName, streakValue))
		else
			Announce.feed(everyone, ("%s won %s!"):format(p.DisplayName, gameName))
		end
	end
	local mvp: Player? = r.mvp
	if mvp and mvp.Parent == Players and #participants >= 2 then
		local kos = r.kos[mvp] or 0
		Announce.feed(everyone, ("MVP: %s (%d KO%s)"):format(mvp.DisplayName, kos, if kos == 1 then "" else "s"))
	end

	Signals.RoundFinished:Fire({
		roundNumber = info.roundNumber,
		minigameId = info.minigameId,
		modifierId = info.modifierId,
		kind = r.kind,
		participants = participants,
		winners = winners,
		placements = r.placements,
		survived = r.survived,
		scores = r.scores,
		kos = r.kos,
		mvp = r.mvp,
	})
	return r
end

return Results
