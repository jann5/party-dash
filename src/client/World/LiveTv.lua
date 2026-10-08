--[[
World client: the lobby's live TV (WatchAnchor SurfaceGui "Screen").
	During a match (Intro / Countdown / Round): "LIVE: BOMB TAG - 4 ALIVE" with a pulsing LIVE tag, and the Watch
	prompt is enabled. Otherwise: "NEXT GAME 0:14" (estimated from the phase timers) and the prompt is hidden.

	LiveTv.bind(lobbyModel, trove)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoundInfo = require(script.Parent:WaitForChild("RoundInfo"))

local LiveTv = {}

local STEP = 1 / 15

type Screen = { main: TextLabel, sub: TextLabel?, live: GuiObject?, prompt: ProximityPrompt? }

local function findScreen(lobby: Model): Screen?
	local anchor = lobby:FindFirstChild("WatchAnchor")
	local screen = anchor and anchor:FindFirstChild("Screen")
	local bg = screen and screen:FindFirstChild("Background")
	local main = bg and bg:FindFirstChild("Main")
	if not (main and main:IsA("TextLabel")) then
		return nil
	end
	local sub = bg:FindFirstChild("Sub")
	local live = bg:FindFirstChild("LiveTag")
	local point = anchor:FindFirstChild("PromptPoint")
	local prompt = point and point:FindFirstChildOfClass("ProximityPrompt")
	return {
		main = main,
		sub = if sub and sub:IsA("TextLabel") then sub else nil,
		live = if live and live:IsA("GuiObject") then live else nil,
		prompt = prompt,
	}
end

-- Seconds until the next match starts, when the phase timers tell us.
local function nextGameIn(phase: any, left: number?): number?
	if phase == "Lobby" then
		return left
	elseif phase == "Roulette" or phase == "ModifierRoulette" then
		return if left then left + Config.INTRO_TIME + Config.COUNTDOWN_TIME else nil
	elseif phase == "End" then
		return (left or 0) + Config.LOBBY_TIME
	end
	return nil
end

-- (main line, sub line, live?) for the current state.
local function screenTexts(): (string, string, boolean)
	local phase = RoundInfo.get("Phase")
	if RoundInfo.isMatchPhase(phase) then
		local alive = RoundInfo.get("Alive")
		local name = RoundInfo.minigameName() or "PARTY DASH"
		local count = if typeof(alive) == "number" then alive else 0
		return ("LIVE: %s - %d ALIVE"):format(name, count), "Watch the round live!", true
	end
	local seconds = nextGameIn(phase, RoundInfo.timeLeft())
	local main = if seconds then "NEXT GAME " .. RoundInfo.clock(seconds) else "NEXT GAME SOON"
	return main, "Step on the PLAY pad!", false
end

function LiveTv.bind(lobby: Model, trove: any)
	local screen: Screen? = nil
	local lastMain, lastLive = nil, nil
	local sinceTick = STEP

	trove:connect(RunService.Heartbeat, function(dt)
		sinceTick += dt
		if sinceTick < STEP then
			return
		end
		sinceTick = 0
		if screen == nil or screen.main.Parent == nil then
			screen = findScreen(lobby)
			lastMain, lastLive = nil, nil
			if screen == nil then
				return
			end
		end
		local s = screen :: Screen
		local main, sub, live = screenTexts()
		if main ~= lastMain then
			s.main.Text = main
			if s.sub then
				s.sub.Text = sub
			end
			lastMain = main
		end
		if live ~= lastLive then
			if s.prompt then
				s.prompt.Enabled = live
			end
			lastLive = live
		end
		if s.live then
			s.live.Visible = live
			s.live.BackgroundTransparency = if live then 0.15 + 0.15 * math.sin(os.clock() * 6) else 0
		end
	end)
end

return LiveTv
