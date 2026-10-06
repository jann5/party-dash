-- Party Dash Core: turns a finished main round into stats, banners, confetti and Signals.RoundFinished.
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

local function seconds(s: number): string
	return ("%.1fs"):format(s)
end

local function names(players: { Player }): string
	local list = {}
	for _, p in players do
		table.insert(list, p.DisplayName)
	end
	return table.concat(list, " & ")
end

-- info = { roundNumber, minigameId, modifierId?, displayName }
function Results.apply(ctx: any, info: { [string]: any })
	local r = ctx:_results()
	local participants: { Player } = r.participants
	local winners: { Player } = {}
	-- A lone player can't "win" a round (no farming), but still gets a friendly result line.
	if #participants >= 2 then
		for _, p in r.winners do
			if p.Parent then
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
			local streak = p.Parent and not isWinner[p] and PlayerSetup.stat(p, "Streak")
			if streak then
				streak.Value = 0
			end
		end
	end

	-- Result text.
	local text, sub
	local color = Theme.Colors.Yellow
	local scores = r.scores
	if #winners == 1 then
		local w = winners[1]
		text = string.upper(w.DisplayName) .. " WINS!"
		local streak = PlayerSetup.stat(w, "Streak")
		if scores then
			sub = ("%d points"):format(scores[w] or 0)
		elseif streak and streak.Value >= 2 then
			sub = ("WIN STREAK x%d!"):format(streak.Value)
		else
			sub = ("Survived %s"):format(seconds(r.survived[w] or r.duration))
		end
	elseif #winners == 2 then
		text = string.upper(names(winners)) .. " WIN!"
	elseif #winners > 2 then
		text = ("%d WINNERS!"):format(#winners)
		sub = names(winners)
	elseif #participants == 1 then
		local p = participants[1]
		if scores then
			text = ("%s SCORED %d!"):format(string.upper(p.DisplayName), scores[p] or 0)
			sub = "Bring friends to battle for the win!"
		else
			text = "NOBODY SURVIVED!"
			sub = ("%s lasted %s"):format(p.DisplayName, seconds(r.survived[p] or r.duration))
			color = Theme.Colors.Red
		end
	else
		text = if scores then "NOBODY SCORED!" else "NOBODY SURVIVED!"
		color = Theme.Colors.Red
	end

	local ids = {}
	for _, p in winners do
		table.insert(ids, tostring(p.UserId))
	end
	GameState.write("WinnersCsv", table.concat(ids, ","))
	GameState.write("ResultText", text)

	local audience = Places.audience()
	Announce.big(audience, text, sub, color)
	for _, p in winners do
		Announce.feed(audience, ("%s won %s!"):format(p.DisplayName, info.displayName or info.minigameId))
		Fx.confetti(p)
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
		scores = scores,
	})
	return r
end

return Results
