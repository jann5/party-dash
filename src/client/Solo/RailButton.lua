--!strict
--[[
The big "SOLO" button docked in PlayerGui.PartyHUD.MenuRail (LayoutOrder 20).
If the rail never shows up (UI failed to load), the button docks on its own at the left-middle instead.

	local api = RailButton.mount(fallbackGui, onClick)
	api.setEnabled(on)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
local Ui = require(script.Parent.Ui)

local RailButton = {}

RailButton.NAME = "SoloButton"
RailButton.LAYOUT_ORDER = 20
local RAIL_TIMEOUT = 20

local C = Theme.Colors
local ON_TOP = Color3.fromRGB(110, 225, 255)
local ON_BOTTOM = Color3.fromRGB(60, 120, 255)
local OFF_TOP = Color3.fromRGB(170, 170, 185)
local OFF_BOTTOM = Color3.fromRGB(105, 105, 125)

export type Api = { setEnabled: (boolean) -> (), button: TextButton }

local function build(onClick: () -> ()): (TextButton, (boolean) -> ())
	local button = Ui.new("TextButton", {
		Name = RailButton.NAME,
		LayoutOrder = RailButton.LAYOUT_ORDER,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 80),
		ZIndex = 6,
	})
	Ui.corner(button, UDim.new(0.28, 0))
	local outline = Ui.stroke(button, 3.5, C.Ink, true)
	local fill = Ui.gradient(button, ON_TOP, ON_BOTTOM)
	local scale = Ui.scaler(button)

	-- Square: height follows the rail's width.
	local function fit()
		local w = button.AbsoluteSize.X
		if w > 0 and math.abs(button.Size.Y.Offset - w) > 0.5 then
			button.Size = UDim2.new(1, 0, 0, w)
		end
	end
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local gloss = Ui.new("Frame", {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.84, 0.3),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = button,
	})
	Ui.corner(gloss, UDim.new(0.5, 0))

	-- Stopwatch icon.
	local watch = Ui.new("Frame", {
		Name = "Stopwatch",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = button,
	})
	Ui.aspect(watch, 1)
	Ui.corner(watch, UDim.new(0.5, 0))
	Ui.stroke(watch, 3, C.Ink, true)
	local knob = Ui.new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.26, 0.16),
		BackgroundColor3 = C.Yellow,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = watch,
	})
	Ui.corner(knob, UDim.new(0.3, 0))
	Ui.stroke(knob, 2.5, C.Ink, true)
	local hand = Ui.new("Frame", {
		Name = "Hand",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.1, 0.76), -- half of it is hidden under the face: rotates around the center
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = watch,
	})
	local needle = Ui.new("Frame", {
		Name = "Needle",
		Size = UDim2.fromScale(1, 0.5),
		BackgroundColor3 = C.Red,
		BorderSizePixel = 0,
		ZIndex = 9,
		Parent = hand,
	})
	Ui.corner(needle, UDim.new(0.5, 0))
	local pin = Ui.new("Frame", {
		Name = "Pin",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.18, 0.18),
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = watch,
	})
	Ui.corner(pin, UDim.new(0.5, 0))
	local spin = TweenService:Create(
		hand,
		TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 360 }
	)
	spin:Play()

	local label = Ui.label("SOLO", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.9, 0.27),
		TextColor3 = C.Yellow,
		ZIndex = 9,
		Parent = button,
	}, 36, 2.5)

	local enabled = true
	Ui.bounce(button, scale, 1.08)
	button.Activated:Connect(function()
		if enabled then
			onClick()
		else
			-- a little "nope" wiggle
			Ui.tween(button, 0.05, { Rotation = -6 })
			task.delay(0.05, function()
				Ui.tween(button, 0.18, { Rotation = 0 }, Enum.EasingStyle.Back)
			end)
		end
	end)

	local function setEnabled(on: boolean)
		if on == enabled then
			return
		end
		enabled = on
		fill.Color = if on then ColorSequence.new(ON_TOP, ON_BOTTOM) else ColorSequence.new(OFF_TOP, OFF_BOTTOM)
		label.TextColor3 = if on then C.Yellow else Color3.fromRGB(225, 225, 235)
		outline.Transparency = if on then 0 else 0.3
		watch.BackgroundTransparency = if on then 0 else 0.35
		if on then
			spin:Play()
			Ui.punch(scale, 0.15)
		else
			spin:Pause()
		end
	end
	task.defer(fit)
	return button, setEnabled
end

function RailButton.mount(fallbackGui: ScreenGui, onClick: () -> ()): Api
	local button, setEnabled = build(onClick)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local function findRail(): Instance?
		local hud = playerGui:FindFirstChild("PartyHUD")
		return hud and hud:FindFirstChild("MenuRail")
	end

	-- Fallback dock (only used when the shared rail is missing).
	local dock = Ui.box({
		Name = "SoloDock",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromScale(0.11, 0.11),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Visible = false,
		Parent = fallbackGui,
	})
	Ui.limit(dock, 100, 100, 56, 56)

	local function attach(): boolean
		local rail = findRail()
		if rail then
			button.Parent = rail
			dock.Visible = false
			return true
		end
		return false
	end

	task.spawn(function()
		-- Wait for the shared rail; after RAIL_TIMEOUT dock on our own, but keep looking for the rail.
		local deadline = os.clock() + RAIL_TIMEOUT
		while not attach() do
			if os.clock() > deadline and button.Parent ~= dock then
				button.Parent = dock
				dock.Visible = true
			end
			task.wait(0.5)
		end
	end)

	return { setEnabled = setEnabled, button = button }
end

return RailButton
