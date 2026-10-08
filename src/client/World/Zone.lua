--[[
World client: the PLAY square (brief #26, ART_BIBLE 6.3 "Join zone").
	Border     white while idle, green pulsing while the lobby counts down with players queued, yellow flashing in
	           the last 5 seconds of the lobby; green sparkles rise from the edges while it is active.
	ZoneBoard  "3/12 READY" + "0:14" from GameState (Phase, QueuedCount, PhaseEnd, Alive).

	Zone.bind(lobbyModel, trove)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Theme = require(Shared:WaitForChild("Theme"))
local RoundInfo = require(script.Parent:WaitForChild("RoundInfo"))

local Zone = {}

local C = Theme.Colors
local STEP = 1 / 30
local FINAL_SECONDS = 5
local BORDER = {
	idle = { color = C.White, sparkles = nil },
	counting = { color = Color3.fromRGB(60, 255, 90), sparkles = C.Green },
	final = { color = C.Yellow, sparkles = C.Yellow },
}

type Labels = { count: TextLabel?, timer: TextLabel? }

local function borderMode(phase: any, queued: number, left: number?): string
	if phase ~= "Lobby" then
		return "idle"
	end
	if left and left <= FINAL_SECONDS then
		return "final"
	end
	return if queued > 0 then "counting" else "idle"
end

-- Board texts for the current phase: (count line, timer line, timer colour).
local function boardTexts(phase: any, queued: number, left: number?): (string, string, Color3)
	local ready = ("%d/%d READY"):format(queued, Config.MAX_PLAYERS)
	if phase == "Lobby" then
		if left == nil then
			return ready, "STEP IN!", C.Yellow
		end
		return ready, RoundInfo.clock(left), if left <= FINAL_SECONDS then C.Orange else C.Yellow
	elseif phase == "Roulette" or phase == "ModifierRoulette" then
		return "GET READY", if left then RoundInfo.clock(left) else "...", C.Yellow
	elseif RoundInfo.isMatchPhase(phase) then
		local alive = RoundInfo.get("Alive")
		return "GAME ON", ("%d LEFT"):format(if typeof(alive) == "number" then alive else 0), C.Yellow
	elseif phase == "End" then
		return "NEXT GAME", RoundInfo.clock((left or 0) + Config.LOBBY_TIME), C.Yellow
	end
	return ready, "STEP IN!", C.Yellow
end

function Zone.bind(lobby: Model, trove: any)
	local bars: { BasePart } = {}
	local labels: Labels = {}
	local lastMode, lastCount, lastTimer = nil, nil, nil
	local sinceTick = STEP

	-- Pieces may stream in after the model: (re)resolve whatever is missing, cheaply, on each tick.
	local function resolve()
		local stale = #bars < 4
		for _, bar in bars do
			stale = stale or bar.Parent == nil
		end
		if stale then
			local border = lobby:FindFirstChild("ZoneBorder")
			if border then
				table.clear(bars)
				for _, d in border:GetChildren() do
					if d:IsA("BasePart") then
						table.insert(bars, d)
					end
				end
				lastMode = nil
			end
		end
		if labels.count == nil or labels.count.Parent == nil then
			local zone = lobby:FindFirstChild("PlayZone")
			local board = zone and zone:FindFirstChild("ZoneBoard")
			local pill = board and board:FindFirstChild("Pill")
			local count = pill and pill:FindFirstChild("Count")
			local timer = pill and pill:FindFirstChild("Timer")
			if count and count:IsA("TextLabel") and timer and timer:IsA("TextLabel") then
				labels.count, labels.timer = count, timer
				lastCount, lastTimer = nil, nil
			end
		end
	end

	local function paintBorder(mode: string, now: number)
		local style = BORDER[mode]
		local transparency = 0.1
		if mode == "counting" then
			transparency = 0.25 - 0.25 * math.sin(now * math.pi * 2.4) -- ~1.2 Hz pulse between 0 and 0.5
		elseif mode == "final" then
			transparency = if math.floor(now * 8) % 2 == 0 then 0 else 0.75 -- 4 Hz flash
		end
		for _, bar in bars do
			if bar.Parent then
				bar.Transparency = transparency
				if mode ~= lastMode then
					bar.Color = style.color
					local sparkles = bar:FindFirstChild("ZoneSparkles")
					if sparkles and sparkles:IsA("ParticleEmitter") then
						sparkles.Enabled = style.sparkles ~= nil
						if style.sparkles then
							sparkles.Color = ColorSequence.new(style.sparkles)
						end
					end
				end
			end
		end
		lastMode = mode
	end

	trove:connect(RunService.Heartbeat, function(dt)
		sinceTick += dt
		if sinceTick < STEP then
			return
		end
		sinceTick = 0
		resolve()
		local phase = RoundInfo.get("Phase")
		local queued = RoundInfo.get("QueuedCount")
		queued = if typeof(queued) == "number" then math.max(0, math.floor(queued)) else 0
		local left = RoundInfo.timeLeft()

		paintBorder(borderMode(phase, queued, left), os.clock())

		local count, timer = labels.count, labels.timer
		if count and timer then
			local countText, timerText, timerColor = boardTexts(phase, queued, left)
			if countText ~= lastCount then
				count.Text = countText
				lastCount = countText
			end
			if timerText ~= lastTimer then
				timer.Text = timerText
				lastTimer = timerText
			end
			timer.TextColor3 = timerColor
		end
	end)
end

return Zone
