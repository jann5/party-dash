-- Party Dash: replicated round state. FROZEN CONTRACT.
-- A single Configuration instance, ReplicatedStorage.GameState, created at runtime by the server.
-- Only Core (P1) writes it (except ScoresJson, which score-kind minigames update via ctx.addScore).
-- Everyone else reads attributes. See docs/ARCHITECTURE.md for the full attribute table.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local GameState = {}

GameState.Phase = {
	Waiting = "Waiting", -- no players
	Lobby = "Lobby", -- intermission on the lobby map
	Roulette = "Roulette", -- minigame card roulette
	ModifierRoulette = "ModifierRoulette", -- second roulette, every Config.MODIFIER_EVERY rounds
	Intro = "Intro", -- map built, players placed & frozen, rules card shown
	Countdown = "Countdown", -- 3-2-1
	Round = "Round", -- playing
	End = "End", -- results
}

function GameState.get(): Configuration
	local s = ReplicatedStorage:FindFirstChild("GameState")
	if s then
		return s
	end
	if RunService:IsServer() then
		s = Instance.new("Configuration")
		s.Name = "GameState"
		s.Parent = ReplicatedStorage
		return s
	end
	return ReplicatedStorage:WaitForChild("GameState")
end

function GameState.read(key: string): any
	return GameState.get():GetAttribute(key)
end

function GameState.write(key: string, value: any)
	assert(RunService:IsServer(), "GameState.write is server-only")
	GameState.get():SetAttribute(key, value)
end

-- Seconds left until PhaseEnd (0 if none).
function GameState.timeLeft(): number
	local e = GameState.read("PhaseEnd") or 0
	if e <= 0 then
		return 0
	end
	return math.max(0, e - workspace:GetServerTimeNow())
end

-- Scores for score-kind minigames: { [userIdString] = number }
function GameState.scores(): { [string]: number }
	local raw = GameState.read("ScoresJson")
	if typeof(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and t or {}
end

function GameState.onChanged(key: string, fn: (any) -> ()): RBXScriptConnection
	return GameState.get():GetAttributeChangedSignal(key):Connect(function()
		fn(GameState.read(key))
	end)
end

return GameState
