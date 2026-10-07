-- Movement HUD (local player). Deliberately tiny: brief #11 wants NO slide bar and no key chips.
--   PC / gamepad  one compact round dash icon (Assets "action_dash") at ~38% of the screen width, above the bottom
--                 110 px (clear of the bottom-center toast / action lanes). It refills bottom-up while the dash
--                 recharges and pops when ready. The slide shows nothing at all on PC.
--   Touch         the action pad (Shared.Movement.ActionButton): Dash with its fill inside the button, Slide at 45%
--                 opacity while it cools down and a pop when it is ready again.
--   Speed lines   a short screen-space burst on every dash.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local UIKit = require(Shared.UIKit)
local ActionButton = require(Shared.Movement.ActionButton)

local Controller = require(script.Parent.Controller)
local State = require(script.Parent.State)

local Hud = {}

local player = Players.LocalPlayer
local Colors = Theme.Colors

local GUI_NAME = "PD_MoveHud"
local INDICATOR_SIZE = 68 -- design px
local INDICATOR_X = 0.38 -- share of the screen width
local INDICATOR_BOTTOM = 118 -- px above the bottom edge (never less, whatever the UI scale)
local SPEED_LINE_COUNT = 22
local LANE_CHECK_EVERY = 0.25

type Indicator = {
	frame: Frame,
	pop: UIScale,
	shade: Frame,
	glow: UIStroke,
	shown: boolean,
	progress: number,
}

local root: Frame
local indicator: Indicator
local padDash: ActionButton.SlotApi
local padSlide: ActionButton.SlotApi
local slideWasCooling = false
local laneBusy = false
local nextLaneCheck = 0

local function uiScale(): number
	local s = root:FindFirstChildOfClass("UIScale")
	return if s and s.Scale > 0 then s.Scale else 1
end

local function alive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Something is showing in the bottom-center action lane (death panel, vote cards): step aside.
local function actionLaneBusy(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local lanes = pg and pg:FindFirstChild("PD_Lanes")
	if not lanes or not lanes:IsA("ScreenGui") or not lanes.Enabled then
		return false
	end
	local laneRoot = lanes:FindFirstChild("Root")
	local lane = laneRoot and laneRoot:FindFirstChild("Action")
	if not lane then
		return false
	end
	for _, child in lane:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- PC dash indicator

local function buildIndicator(): Indicator
	local frame = UIKit.new("Frame", {
		Name = "DashIndicator",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(INDICATOR_SIZE, INDICATOR_SIZE),
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	local pop = UIKit.new("UIScale", { Name = "Pop", Parent = frame })
	local disc = UIKit.new("CanvasGroup", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 1, -6),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		ZIndex = 2,
		Parent = frame,
	})
	UIKit.corner(disc, UDim.new(0.5, 0))
	UIKit.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = Assets.icon("action_dash"),
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		ZIndex = 3,
		Parent = disc,
	})
	-- Covers the part still recharging, so the icon fills back in from the bottom up.
	local shade = UIKit.new("Frame", {
		Name = "Shade",
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		Visible = false,
		ZIndex = 4,
		Parent = disc,
	})
	local ringFrame = UIKit.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 5,
		Parent = frame,
	})
	UIKit.corner(ringFrame, UDim.new(0.5, 0))
	UIKit.border(ringFrame, 3, Colors.Ink)
	local glowFrame = UIKit.new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2, 1, -2),
		ZIndex = 6,
		Parent = frame,
	})
	UIKit.corner(glowFrame, UDim.new(0.5, 0))
	local glow = UIKit.border(glowFrame, 3, Colors.Yellow, 1)
	return { frame = frame, pop = pop, shade = shade, glow = glow, shown = false, progress = 1 }
end

local function placeIndicator()
	local s = uiScale()
	local px = math.max(INDICATOR_BOTTOM, INDICATOR_BOTTOM * s)
	indicator.frame.Position = UDim2.new(INDICATOR_X, 0, 1, -px / s)
end

local function setIndicatorProgress(progress: number)
	if math.abs(progress - indicator.progress) < 0.004 and (progress < 1) == indicator.shade.Visible then
		return
	end
	indicator.progress = progress
	indicator.shade.Visible = progress < 1
	indicator.shade.Size = UDim2.fromScale(1, 1 - progress)
end

local function indicatorReady()
	if not indicator.shown then
		return
	end
	indicator.pop.Scale = 1.15
	UIKit.tween(indicator.pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	indicator.glow.Transparency = 0
	UIKit.tween(indicator.glow, 0.45, { Transparency = 1 })
	UIKit.sound("UiHover", { volume = 0.25, pitch = 1.15 })
end

local function indicatorDenied()
	if not indicator.shown then
		return
	end
	indicator.frame.Rotation = 10
	UIKit.tween(indicator.frame, 0.2, { Rotation = 0 }, Enum.EasingStyle.Back)
end

---------------------------------------------------------------------------------------------------
-- Speed lines (dash only)

type Line = { frame: Frame, angle: number, r: number, len: number, speed: number }
local linesFrame: Frame
local lines: { Line } = {}
local lineStrength = 0
local burstUntil = 0

local function respawnLine(line: Line, diag: number, initial: boolean)
	line.angle = math.random() * math.pi * 2
	line.r = diag * (if initial then 0.45 + math.random() * 0.4 else 0.45 + math.random() * 0.1)
	line.len = diag * (0.1 + math.random() * 0.16)
	line.speed = diag * (1.4 + math.random() * 1.2)
	line.frame.Size = UDim2.fromOffset(line.len, 3 + math.random(0, 2))
	line.frame.Rotation = math.deg(line.angle)
end

local function buildLines()
	linesFrame = UIKit.new("Frame", {
		Name = "SpeedLines",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Visible = false,
		Parent = root,
	})
	for _ = 1, SPEED_LINE_COUNT do
		local frame = UIKit.new("Frame", {
			BackgroundColor3 = Colors.White,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Parent = linesFrame,
		})
		table.insert(lines, { frame = frame, angle = 0, r = 0, len = 0, speed = 0 })
	end
end

local function updateLines(now: number, dt: number)
	local target = if now < burstUntil then 1 else 0
	local rate = if target > lineStrength then 25 else 7
	lineStrength += (target - lineStrength) * (1 - math.exp(-rate * dt))
	if lineStrength < 0.01 then
		if linesFrame.Visible then
			linesFrame.Visible = false
		end
		return
	end
	-- Design-pixel canvas (the root is scaled by UIKit).
	local size = root.AbsoluteSize / uiScale()
	local center = size / 2
	local diag = size.Magnitude / 2
	if not linesFrame.Visible then
		linesFrame.Visible = true
		for _, line in lines do
			respawnLine(line, diag, true)
		end
	end
	for _, line in lines do
		line.r += line.speed * dt
		if line.r > diag * 1.05 then
			respawnLine(line, diag, false)
		end
		local dir = Vector2.new(math.cos(line.angle), math.sin(line.angle))
		local p = center + dir * (line.r + line.len / 2)
		line.frame.Position = UDim2.fromOffset(p.X, p.Y)
		local edgeFade = math.clamp((line.r - diag * 0.45) / (diag * 0.15), 0, 1)
		line.frame.BackgroundTransparency = 1 - 0.5 * lineStrength * edgeFade
	end
end

---------------------------------------------------------------------------------------------------

local function update(dt: number)
	local now = os.clock()
	if now >= nextLaneCheck then
		nextLaneCheck = now + LANE_CHECK_EVERY
		laneBusy = actionLaneBusy()
	end

	local touch = ActionButton.isTouch()
	local show = not touch and alive() and player:GetAttribute("Spectating") ~= true and not laneBusy
	if show ~= indicator.shown then
		indicator.shown = show
		indicator.frame.Visible = show
	end
	if show then
		setIndicatorProgress(State.dashProgress(now))
	end

	-- Touch pad feedback (only while the pad is the active control scheme).
	if touch and padDash.isShown() then
		padDash.setProgress(State.dashProgress(now))
		local cooling = State.sliding or now < State.slideReadyAt
		padSlide.setCooling(cooling)
		if slideWasCooling and not cooling then
			padSlide.pop()
		end
		slideWasCooling = cooling
	end

	updateLines(now, dt)
end

function Hud.start()
	local _, screenRoot = UIKit.screen(GUI_NAME, "HUD")
	root = screenRoot
	buildLines()
	indicator = buildIndicator()
	placeIndicator()
	local uiScaleObject = root:FindFirstChildOfClass("UIScale")
	if uiScaleObject then
		uiScaleObject:GetPropertyChangedSignal("Scale"):Connect(placeIndicator)
	end

	padDash = ActionButton.move("Dash", Controller.requestDash)
	padSlide = ActionButton.move("Slide", Controller.requestSlide)

	State.on("Dash", function()
		burstUntil = os.clock() + Config.DASH_DURATION + 0.18
		setIndicatorProgress(0)
	end)
	State.on("DashReady", function()
		indicatorReady()
		if ActionButton.isTouch() then
			padDash.pop()
		end
	end)
	State.on("DashDenied", indicatorDenied)

	RunService.PreRender:Connect(update)
end

return Hud
