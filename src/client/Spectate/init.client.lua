-- Party Dash: spectate bar. While Player.Spectating is true, a bottom-center bar
-- "SPECTATING <Name>" lets you cycle through players still in the round (arrows or Q / E),
-- the camera follows them, and STOP gives the camera back to you (WATCH resumes).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local localPlayer = Players.LocalPlayer
local C = Theme.Colors

-- UI ---------------------------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "SpectateGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local SHOWN_POS = UDim2.new(0.5, 0, 1, -16)
local HIDDEN_POS = UDim2.new(0.5, 0, 1, 140)

local bar = Instance.new("Frame")
bar.Name = "SpectatingBar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = HIDDEN_POS
bar.Size = UDim2.fromScale(0.56, 0.13)
bar.BackgroundColor3 = C.Panel
bar.Visible = false
bar.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.3, 0)
corner.Parent = bar
local barStroke = Instance.new("UIStroke")
barStroke.Color = C.Ink
barStroke.Thickness = Theme.StrokeThickness
barStroke.Parent = bar
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 6.4
aspect.Parent = bar
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(320, 50)
sizeLimit.MaxSize = Vector2.new(640, 100)
sizeLimit.Parent = bar

local function textLabel(parent: Instance, name: string, text: string, color: Color3, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = Theme.FontFace
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = C.Ink
	s.Thickness = 2
	s.Parent = l
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = l
	return l
end

local function roundButton(name: string, text: string, color: Color3, anchorX: number, posX: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(anchorX, 0.5)
	b.Position = UDim2.fromScale(posX, 0.5)
	b.Size = UDim2.fromScale(0.13, 0.78)
	b.BackgroundColor3 = color
	b.AutoButtonColor = false
	b.FontFace = Theme.FontFace
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = C.White
	b.Parent = bar
	local cornerB = Instance.new("UICorner")
	cornerB.CornerRadius = UDim.new(0.5, 0)
	cornerB.Parent = b
	local strokeB = Instance.new("UIStroke")
	strokeB.Color = C.Ink
	strokeB.Thickness = Theme.StrokeThickness
	strokeB.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	strokeB.Parent = b
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = C.Ink
	textStroke.Thickness = 2
	textStroke.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	-- Juicy hover/press feedback.
	local function tweenScale(target: number)
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = target,
		}):Play()
	end
	b.MouseEnter:Connect(function()
		tweenScale(1.08)
	end)
	b.MouseLeave:Connect(function()
		tweenScale(1)
	end)
	b.MouseButton1Down:Connect(function()
		tweenScale(0.9)
	end)
	b.MouseButton1Up:Connect(function()
		tweenScale(1.08)
	end)
	return b
end

local prevButton = roundButton("Prev", "<", C.Yellow, 0, 0.02)
local nextButton = roundButton("Next", ">", C.Yellow, 0, 0.16)
nextButton.Position = UDim2.fromScale(0.69, 0.5)
local stopButton = roundButton("Stop", "STOP", C.Red, 1, 0.98)
stopButton.Size = UDim2.fromScale(0.15, 0.62)

local title = textLabel(bar, "Title", "SPECTATING", C.Cyan, 22)
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.fromScale(0.42, 0.08)
title.Size = UDim2.fromScale(0.5, 0.3)

local targetName = textLabel(bar, "TargetName", "", C.White, 42)
targetName.AnchorPoint = Vector2.new(0.5, 0)
targetName.Position = UDim2.fromScale(0.42, 0.38)
targetName.Size = UDim2.fromScale(0.5, 0.5)

local keyHint = textLabel(bar, "KeyHint", "Q / E", C.Yellow, 16)
keyHint.AnchorPoint = Vector2.new(0.5, 0)
keyHint.Position = UDim2.fromScale(0.42, -0.32)
keyHint.Size = UDim2.fromScale(0.3, 0.26)
keyHint.Visible = UserInputService.KeyboardEnabled

gui.Parent = localPlayer:WaitForChild("PlayerGui")

-- Logic --------------------------------------------------------------------------------------------------

local active = false -- bar shown (we are spectating)
local watching = true -- camera follows a target (false after STOP)
local target: Player? = nil

local function candidates(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= localPlayer and p:GetAttribute("InRound") == true then
			local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				table.insert(list, p)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

local function ownHumanoid(): Humanoid?
	local character = localPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function applyCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local subject: Instance? = nil
	if active and watching and target then
		subject = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	end
	subject = subject or ownHumanoid()
	if subject and camera.CameraSubject ~= subject then
		camera.CameraSubject = subject
	end
end

local function refreshLabels()
	if not watching then
		title.Text = "SPECTATING"
		targetName.Text = "PAUSED"
		stopButton.Text = "WATCH"
		stopButton.BackgroundColor3 = C.Green
	elseif target then
		title.Text = "SPECTATING"
		targetName.Text = target.DisplayName
		stopButton.Text = "STOP"
		stopButton.BackgroundColor3 = C.Red
	else
		title.Text = "SPECTATING"
		targetName.Text = "Nobody left..."
		stopButton.Text = "STOP"
		stopButton.BackgroundColor3 = C.Red
	end
	local many = #candidates() > 1
	prevButton.Visible = many and watching
	nextButton.Visible = many and watching
end

local function cycle(step: number)
	local list = candidates()
	if #list == 0 then
		target = nil
	else
		local index = target and table.find(list, target) or 0
		if index == 0 and step < 0 then
			index = 1
		end
		target = list[(index - 1 + step) % #list + 1]
	end
	refreshLabels()
	applyCamera()
end

-- Make sure the current target is still valid (left the round -> next one).
local function validate()
	if not active then
		return
	end
	local list = candidates()
	if not target or not table.find(list, target) then
		target = list[1]
	end
	refreshLabels()
	applyCamera()
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		watching = true
		target = nil
		validate()
		bar.Visible = true
		bar.Position = HIDDEN_POS
		TweenService:Create(bar, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = SHOWN_POS,
		}):Play()
	else
		target = nil
		bar.Visible = false
		bar.Position = HIDDEN_POS
		applyCamera()
	end
end

prevButton.Activated:Connect(function()
	cycle(-1)
end)
nextButton.Activated:Connect(function()
	cycle(1)
end)
stopButton.Activated:Connect(function()
	watching = not watching
	if watching then
		validate()
	else
		refreshLabels()
		applyCamera()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not active or not watching then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		cycle(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		cycle(1)
	end
end)

localPlayer:GetAttributeChangedSignal("Spectating"):Connect(function()
	setActive(localPlayer:GetAttribute("Spectating") == true)
end)
localPlayer.CharacterAdded:Connect(function()
	task.defer(applyCamera)
end)
setActive(localPlayer:GetAttribute("Spectating") == true)

-- Light polling keeps the target valid as players get knocked out or leave.
task.spawn(function()
	while true do
		task.wait(0.3)
		if active then
			validate()
		end
	end
end)
