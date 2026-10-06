--!strict
--[[
Solo Record result card.
	record   -> gold "NEW RECORD!" ribbon, the time counts up, sun rays + confetti, "#3 IN THE WORLD!"
	no record -> "YOU FELL!" (or why it ended), "YOUR TIME 22.1s", "best 41.2s - 19.1s to go!"
Buttons: PLAY AGAIN (same minigame) and CLOSE. Closes by itself after AUTO_CLOSE seconds.

	local result = Result.new(gui)
	result.show(payload, onAgain)   -- payload = the server's "result" message (see server Runs.lua)
	result.hide()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
local Confetti = require(script.Parent.Confetti)
local Data = require(script.Parent.Data)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Result = {}

local C = Theme.Colors
local Z = 50
local AUTO_CLOSE = 12
local COUNT_TIME = 0.9
local RAYS = 12
local GOLD_TOP = Color3.fromRGB(255, 228, 95)
local GOLD_BOTTOM = Color3.fromRGB(255, 145, 30)
local MUTED = Color3.fromRGB(200, 190, 240)

local TITLES = {
	fell = "YOU FELL!",
	died = "KNOCKED OUT!",
	quit = "RUN ENDED",
	allOut = "YOU FELL!",
}

export type Payload = {
	minigameId: string,
	displayName: string,
	seconds: number,
	best: number?,
	previous: number?,
	isRecord: boolean,
	reason: string,
	rank: number?,
	started: boolean,
}

export type Api = {
	show: (payload: Payload, onAgain: (() -> ())?) -> (),
	hide: () -> (),
	isShown: () -> boolean,
}

function Result.new(gui: ScreenGui): Api
	local root = Ui.box({ Name = "SoloResult", Visible = false, ZIndex = Z, Parent = gui })
	local dim = Ui.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z,
		Parent = root,
	})

	-- Sun rays (rotated individually around the card center).
	local rays = Ui.box({
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.2, 1.2),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Visible = false,
		ZIndex = Z + 1,
		Parent = root,
	})
	local rayFrames: { Frame } = {}
	for i = 1, RAYS do
		local ray = Ui.new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 0.07),
			BackgroundColor3 = GOLD_TOP,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			Rotation = (i - 1) * 180 / RAYS,
			ZIndex = Z + 1,
			Parent = rays,
		})
		Ui.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
		table.insert(rayFrames, ray)
	end

	local card = Ui.panel(C.White, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.6, 0.62),
		ZIndex = Z + 2,
		Active = true,
		Parent = root,
	}, UDim.new(0.08, 0), 5)
	Ui.aspect(card, 1.45)
	Ui.limit(card, 660, 455, 300, 207)
	local cardGradient = Ui.gradient(card, C.Panel:Lerp(C.Purple, 0.3), C.Panel:Lerp(C.Ink, 0.35))
	local cardScale = Ui.scaler(card, 0)

	local ribbon = Ui.panel(C.White, {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.0),
		Size = UDim2.fromScale(0.78, 0.2),
		ZIndex = Z + 4,
		Parent = card,
	}, UDim.new(0.5, 0), 4)
	local ribbonGradient = Ui.gradient(ribbon, GOLD_TOP, GOLD_BOTTOM)
	local ribbonScale = Ui.scaler(ribbon)
	local title = Ui.label("NEW RECORD!", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.88, 0.74),
		ZIndex = Z + 5,
		Parent = ribbon,
	}, 64, 3.5)

	local gameName = Ui.label("", {
		Name = "Game",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.135),
		Size = UDim2.fromScale(0.7, 0.085),
		ZIndex = Z + 3,
		Parent = card,
	}, 30, 2)
	local caption = Ui.label("YOUR TIME", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.24),
		Size = UDim2.fromScale(0.6, 0.075),
		TextColor3 = C.Cyan,
		ZIndex = Z + 3,
		Parent = card,
	}, 30, 2)
	local timeText = Ui.label("0.0s", {
		Name = "Time",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.86, 0.27),
		ZIndex = Z + 3,
		Parent = card,
	}, 100, 4.5)
	local timeScale = Ui.scaler(timeText)
	local subText = Ui.label("", {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.575),
		Size = UDim2.fromScale(0.86, 0.085),
		TextColor3 = MUTED,
		ZIndex = Z + 3,
		Parent = card,
	}, 32, 2)

	local rankBadge = Ui.panel(C.White, {
		Name = "Rank",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.67),
		Size = UDim2.fromScale(0.52, 0.1),
		Visible = false,
		ZIndex = Z + 3,
		Parent = card,
	}, UDim.new(0.5, 0), 3)
	Ui.gradient(rankBadge, C.Pink, C.Purple)
	local rankScale = Ui.scaler(rankBadge)
	local rankText = Ui.label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.88, 0.74),
		ZIndex = Z + 4,
		Parent = rankBadge,
	}, 30, 2)

	local again, _, againScale = Ui.button("PLAY AGAIN", C.Green, {
		Name = "Again",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.485, 0.88),
		Size = UDim2.fromScale(0.4, 0.15),
		ZIndex = Z + 4,
		Parent = card,
	}, 34)
	local closeButton, _, closeScale = Ui.button("CLOSE", C.Purple, {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.515, 0.88),
		Size = UDim2.fromScale(0.4, 0.15),
		ZIndex = Z + 4,
		Parent = card,
	}, 34)

	-- State ---------------------------------------------------------------------------------------------
	local shown = false
	local token = 0
	local onAgainFn: (() -> ())? = nil
	local rayConn: RBXScriptConnection? = nil

	local function stopRays()
		if rayConn then
			rayConn:Disconnect()
			rayConn = nil
		end
		rays.Visible = false
	end

	local function startRays()
		stopRays()
		rays.Visible = true
		local angle = 0
		rayConn = RunService.RenderStepped:Connect(function(dt)
			angle = (angle + dt * 18) % 360
			for i, ray in rayFrames do
				ray.Rotation = angle + (i - 1) * 180 / RAYS
			end
		end)
	end

	local function hide()
		if not shown then
			return
		end
		shown = false
		token += 1
		stopRays()
		Ui.tween(dim, 0.2, { BackgroundTransparency = 1 })
		local tw = Ui.popOut(cardScale, 0.22)
		tw.Completed:Connect(function()
			if not shown then
				root.Visible = false
			end
		end)
	end

	-- Counts the big number up from 0 with ticks, then punches it.
	local function countUp(target: number, myToken: number, onDone: () -> ())
		task.spawn(function()
			local t0 = os.clock()
			local lastTick = 0
			while token == myToken do
				local a = math.clamp((os.clock() - t0) / COUNT_TIME, 0, 1)
				local eased = 1 - (1 - a) ^ 3
				timeText.Text = Data.fmt(target * eased)
				if os.clock() - lastTick > 0.07 and a < 1 then
					lastTick = os.clock()
					Sfx.play("tick", 0.9 + a * 0.6)
				end
				if a >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
			if token == myToken then
				timeText.Text = Data.fmt(target)
				Ui.punch(timeScale, 0.25, 0.4)
				onDone()
			end
		end)
	end

	local function show(payload: Payload, onAgain: (() -> ())?)
		token += 1
		local myToken = token
		shown = true
		onAgainFn = onAgain
		root.Visible = true
		dim.BackgroundTransparency = 1
		Ui.tween(dim, 0.3, { BackgroundTransparency = 0.45 })
		Ui.popIn(cardScale, 0.5)
		Ui.popIn(ribbonScale, 0.5, 0.12)
		Ui.popIn(againScale, 0.4, 0.35)
		Ui.popIn(closeScale, 0.4, 0.42)
		rankBadge.Visible = false

		local accent = Data.accent(payload.minigameId)
		gameName.Text = payload.displayName
		gameName.TextColor3 = accent:Lerp(C.White, 0.35)
		again.Visible = onAgain ~= nil

		if payload.isRecord then
			title.Text = "NEW RECORD!"
			ribbonGradient.Color = ColorSequence.new(GOLD_TOP, GOLD_BOTTOM)
			cardGradient.Color = ColorSequence.new(Color3.fromRGB(120, 75, 190), Color3.fromRGB(50, 30, 90))
			caption.Text = "YOUR NEW BEST"
			caption.TextColor3 = GOLD_TOP
			timeText.TextColor3 = GOLD_TOP
			if payload.previous then
				subText.Text = ("Previous best: %s  (+%s)"):format(
					Data.fmt(payload.previous),
					Data.fmt(payload.seconds - payload.previous)
				)
			else
				subText.Text = "Your first record! Now go beat it!"
			end
			subText.TextColor3 = C.White
			startRays()
			Sfx.play("boom")
			Confetti.burst(Vector2.new(0.5, 0.45), 70)
			task.delay(0.35, function()
				if token == myToken then
					Confetti.rain(50)
				end
			end)
		else
			title.Text = if payload.started then TITLES[payload.reason] or "RUN OVER" else "RUN CANCELLED"
			ribbonGradient.Color = ColorSequence.new(C.Pink, C.Purple)
			cardGradient.Color = ColorSequence.new(C.Panel:Lerp(C.Purple, 0.3), C.Panel:Lerp(C.Ink, 0.35))
			caption.Text = "YOUR TIME"
			caption.TextColor3 = C.Cyan
			timeText.TextColor3 = C.White
			subText.TextColor3 = MUTED
			stopRays()
			Sfx.play("land", 0.9)
			if not payload.started then
				subText.Text = "You left before the GO. No time recorded."
			elseif payload.best then
				local gap = payload.best - payload.seconds
				subText.Text = if gap > 0.05
					then ("best %s  -  only %s to go!"):format(Data.fmt(payload.best), Data.fmt(gap))
					else ("best %s  -  so close!"):format(Data.fmt(payload.best))
			else
				subText.Text = "Keep going!"
			end
		end

		if payload.started then
			timeText.Text = Data.fmt(0)
			countUp(payload.seconds, myToken, function()
				local rank = payload.rank
				if payload.isRecord and rank then
					rankText.Text = if rank == 1 then "#1 IN THE WORLD!" else ("#%d IN THE WORLD!"):format(rank)
					rankBadge.Visible = true
					Ui.popIn(rankScale, 0.45)
					Confetti.burst(Vector2.new(0.5, 0.62), 30)
				end
			end)
		else
			timeText.Text = "--"
		end

		task.delay(AUTO_CLOSE, function()
			if token == myToken then
				hide()
			end
		end)
	end

	again.Activated:Connect(function()
		local fn = onAgainFn
		if shown and fn then
			Sfx.play("click")
			hide()
			fn()
		end
	end)
	closeButton.Activated:Connect(function()
		Sfx.play("click", 0.8)
		hide()
	end)

	return {
		show = show,
		hide = hide,
		isShown = function()
			return shown
		end,
	}
end

return Result
