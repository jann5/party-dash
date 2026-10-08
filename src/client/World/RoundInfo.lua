--[[
World client helper: non-blocking reads of the replicated round state (ReplicatedStorage.GameState attributes,
docs/ARCHITECTURE.md). Every function copes with GameState not having replicated yet.

	RoundInfo.get("Phase")            -> attribute value or nil
	RoundInfo.timeLeft()              -> seconds until PhaseEnd, or nil when the phase is open-ended (PhaseEnd 0)
	RoundInfo.clock(14.2)             -> "0:15"
	RoundInfo.minigameName()          -> "BOMB TAG" (MinigameInfo DisplayName, upper case) or nil
	RoundInfo.isMatchPhase(phase)     -> true for Intro / Countdown / Round (a match is on the arena)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundInfo = {}

local state: Instance? = nil

function RoundInfo.get(key: string): any
	if state == nil or state.Parent == nil then
		state = ReplicatedStorage:FindFirstChild("GameState")
	end
	return if state then state:GetAttribute(key) else nil
end

function RoundInfo.timeLeft(): number?
	local phaseEnd = RoundInfo.get("PhaseEnd")
	if typeof(phaseEnd) ~= "number" or phaseEnd <= 0 then
		return nil
	end
	return math.max(0, phaseEnd - workspace:GetServerTimeNow())
end

function RoundInfo.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(s // 60, s % 60)
end

function RoundInfo.minigameName(): string?
	local id = RoundInfo.get("MinigameId")
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("MinigameInfo")
	local info = folder and folder:FindFirstChild(id)
	local display = info and info:GetAttribute("DisplayName")
	return string.upper(if typeof(display) == "string" and display ~= "" then display else id)
end

local MATCH_PHASES = { Intro = true, Countdown = true, Round = true }

function RoundInfo.isMatchPhase(phase: any): boolean
	return MATCH_PHASES[phase] == true
end

return RoundInfo
