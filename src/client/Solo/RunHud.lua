--!strict
--[[
In-run HUD for Solo Record: big running timer, "BEST: 41.2s", a progress bar toward your best that turns
gold once you beat it, and a QUIT button (tap twice to confirm).

	local hud = RunHud.new(gui, onQuit)
	hud.show(minigameId, displayName, best?)   -- intro / countdown
	hud.go(startedAt)                           -- server time at GO
	hud.freeze()                                -- stop the clock (run ended, waiting for the result)
	hud.hide()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
local Data = require(script.Parent.Data)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local RunHud = {}

local C = Theme.Colors
local Z = 10
local CONFIRM_SECONDS = 2.5
local GOLD_TOP = Color3.fromRGB(255, 225, 90)
local GOLD_BOTTOM = Color3.fromRGB(255, 150, 30)

export type Api = {
	show: (minigameId: string, displayName: string, best: number?) -> (),
	go: (startedAt: number) -> (),
	freeze: () -> (),
	hide: () -> (),
	isShown: () -> boolean,
}

function RunHud.new(gui: ScreenGui, onQuit: () -> ()): Api
	local root = Ui.box({ Name = "SoloRunHud", Visible = false, ZIndex = Z, Parent = gui })

	-- Top-center cluster ----------------------------------------------------------------------------------
	local cluster = Ui.box({
		Name = "Cluster",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromScale(0.36, 0.27),
		ZIndex = Z,
		Parent = root,
	})
	Ui.aspect(cluster, 2.1)
	Ui.limit(cluster, 460, 220, 230, 110)
	local clusterScale = Ui.scaler(cluster, 0)

	local chip = Ui.panel(C.White, {
		Name = "GameChip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.66, 0.2),
		ZIndex = Z + 2,
		Parent = cluster,
	}, UDim.new(0.5, 0), 3)
	local chipGradient = Ui.gradient(chip, C.Pink, C.Purple)
	local chipText = Ui.label("SOLO", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.9, 0.74),
		ZIndex = Z + 3,
		Parent = chip,
	}, 28, 2)

	local pill = Ui.panel(C.White, {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.86, 0.52),
		ZIndex = Z + 1,
		Parent = cluster,
	}, UDim.new(0.3, 0), 4)
	local pillGradient = Ui.gradient(pill, C.Panel:Lerp(C.Purple, 0.35), C.Ink)
	local pillScale = Ui.scaler(pill)
	local timerText = Ui.label("0.0s", {
		Name = "TimerText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.86, 0.74),
		ZIndex = Z + 2,
		Parent = pill,
	}, 90, 3.5)

	local bar = Ui.panel(C.Ink, {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.74, 0.085),
		BackgroundTransparency = 0.35,
		ClipsDescendants = true,
		ZIndex = Z + 1,
		Parent = cluster,
	}, UDim.new(0.5, 0), 2.5)
	local fill = Ui.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = Z + 2,
		Parent = bar,
	})
	Ui.corner(fill, UDim.new(0.5, 0))
	local fillGradient = Ui.gradient(fill, C.Cyan, C.Blue, 0)

	local bestText = Ui.label("BEST: --", {
		Name = "BestText",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.83),
		Size = UDim2.fromScale(0.8, 0.17),
		TextColor3 = C.Yellow,
		ZIndex = Z + 2,
		Parent = cluster,
	}, 34, 2.5)

	-- "NEW RECORD!" badge that pops when you pass your best.
	local badge = Ui.panel(C.White, {
		Name = "RecordBadge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1.04),
		Size = UDim2.fromScale(0.6, 0.2),
		Visible = false,
		ZIndex = Z + 3,
		Parent = cluster,
	}, UDim.new(0.5, 0), 3)
	Ui.gradient(badge, GOLD_TOP, GOLD_BOTTOM)
	local badgeScale = Ui.scaler(badge)
	Ui.label("NEW RECORD!", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.88, 0.74),
		ZIndex = Z + 4,
		Parent = badge,
	}, 30, 2.5)

	-- QUIT (left-middle; tap twice) --------------------------------------------------------------------
	local quit = Ui.new("TextButton", {
		Name = "Quit",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromScale(0.12, 0.12),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = Z + 1,
		Parent = root,
	})
	Ui.limit(quit, 104, 104, 58, 58)
	Ui.corner(quit, UDim.new(0.3, 0))
	Ui.stroke(quit, 3.5, C.Ink, true)
	local quitGradient = Ui.gradient(quit, C.Red:Lerp(C.White, 0.15), C.Red:Lerp(C.Ink, 0.3))
	local quitScale = Ui.scaler(quit)
	Ui.bounce(quit, quitScale, 1.08)
	local quitIcon = Ui.label("X", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = Z + 2,
		Parent = quit,
	}, 60, 3)
	local quitText = Ui.label("QUIT", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.93),
		Size = UDim2.fromScale(0.86, 0.28),
		ZIndex = Z + 2,
		Parent = quit,
	}, 28, 2)

	-- State ---------------------------------------------------------------------------------------------
	local shown = false
	local running = false
	local startedAt = 0
	local best: number? = nil
	local passedBest = false
	local lastMilestone = 0
	local confirmUntil = 0
	local conn: RBXScriptConnection? = nil

	local function setConfirm(on: boolean)
		quitIcon.Text = if on then "?" else "X"
		quitText.Text = if on then "SURE?" else "QUIT"
		quitGradient.Color = if on
			then ColorSequence.new(C.Orange:Lerp(C.White, 0.15), C.Orange:Lerp(C.Ink, 0.3))
			else ColorSequence.new(C.Red:Lerp(C.White, 0.15), C.Red:Lerp(C.Ink, 0.3))
	end

	quit.Activated:Connect(function()
		if not shown then
			return
		end
		local now = os.clock()
		if now < confirmUntil then
			confirmUntil = 0
			setConfirm(false)
			Sfx.play("click", 0.7)
			onQuit()
			return
		end
		confirmUntil = now + CONFIRM_SECONDS
		setConfirm(true)
		Ui.punch(quitScale, 0.15)
		Sfx.play("tick")
		task.delay(CONFIRM_SECONDS, function()
			if os.clock() >= confirmUntil then
				setConfirm(false)
			end
		end)
	end)

	local function setProgress(elapsed: number)
		if best and best > 0 then
			fill.Size = UDim2.fromScale(math.clamp(elapsed / best, 0, 1), 1)
		else
			-- No record yet: the bar loops every 10 seconds so it still feels alive.
			fill.Size = UDim2.fromScale((elapsed % 10) / 10, 1)
		end
	end

	local function onPassBest()
		passedBest = true
		fillGradient.Color = ColorSequence.new(GOLD_TOP, GOLD_BOTTOM)
		pillGradient.Color = ColorSequence.new(Color3.fromRGB(150, 95, 20), Color3.fromRGB(80, 40, 10))
		timerText.TextColor3 = GOLD_TOP
		badge.Visible = true
		Ui.popIn(badgeScale, 0.5)
		Ui.punch(pillScale, 0.3, 0.5)
		Sfx.play("boom")
		Sfx.play("land", 1.3)
	end

	local function step()
		if not running then
			return
		end
		local elapsed = math.max(0, workspace:GetServerTimeNow() - startedAt)
		timerText.Text = Data.fmt(elapsed)
		setProgress(elapsed)
		if best and not passedBest and elapsed > best then
			onPassBest()
		end
		local milestone = math.floor(elapsed / 10)
		if milestone > lastMilestone then
			lastMilestone = milestone
			Ui.punch(pillScale, 0.16)
			Sfx.play("tick", 1 + math.min(milestone, 10) * 0.05)
		end
	end

	local function disconnect()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	local api: Api = {
		show = function(minigameId: string, displayName: string, bestSeconds: number?)
			disconnect()
			running = false
			best = bestSeconds
			passedBest = false
			lastMilestone = 0
			confirmUntil = 0
			setConfirm(false)
			local accent = Data.accent(minigameId)
			chipText.Text = displayName
			chipGradient.Color = ColorSequence.new(accent:Lerp(C.White, 0.15), accent:Lerp(C.Ink, 0.3))
			pillGradient.Color = ColorSequence.new(C.Panel:Lerp(C.Purple, 0.35), C.Ink)
			fillGradient.Color = ColorSequence.new(C.Cyan, C.Blue)
			timerText.TextColor3 = C.White
			timerText.Text = "0.0s"
			bestText.Text = if bestSeconds
				then ("BEST: %s"):format(Data.fmt(bestSeconds))
				else "FIRST RUN - SET A RECORD!"
			fill.Size = UDim2.fromScale(0, 1)
			badge.Visible = false
			root.Visible = true
			if not shown then
				shown = true
				Ui.popIn(clusterScale, 0.45)
				Ui.popIn(quitScale, 0.45, 0.1)
			end
		end,
		go = function(at: number)
			startedAt = at
			running = true
			Ui.punch(pillScale, 0.25)
			disconnect()
			conn = RunService.RenderStepped:Connect(step)
		end,
		freeze = function()
			running = false
			disconnect()
		end,
		hide = function()
			running = false
			disconnect()
			if not shown then
				return
			end
			shown = false
			local tw = Ui.popOut(clusterScale, 0.2)
			Ui.popOut(quitScale, 0.2)
			tw.Completed:Connect(function()
				if not shown then
					root.Visible = false
				end
			end)
		end,
		isShown = function()
			return shown
		end,
	}
	return api
end

return RunHud
