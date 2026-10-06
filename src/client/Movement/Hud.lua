-- Movement HUD (local player):
--   PlayerGui.MovementHUD.DashCooldownBar.Fill   Size.X.Scale goes 0 -> 1 while the dash recharges;
--                                                 pops + flashes when ready, shakes when pressed too early
--   mobile Dash / Slide buttons (the ContextActionService touch buttons), restyled in the Theme, placed
--   above the jump button and showing their own cooldown fill
--   subtle screen-space speed lines during a dash / slide
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Assets = require(Shared.Movement.Assets)
local Stats = require(Shared.Movement.Stats)

local State = require(script.Parent.State)

local Hud = {}

local player = Players.LocalPlayer
local Colors = Theme.Colors

local CHARGING = ColorSequence.new(Colors.Cyan, Colors.Blue)
local READY = ColorSequence.new(Colors.Yellow, Colors.Orange)
local SPEED_LINE_COUNT = 22

local gui: ScreenGui
local bar: Frame
local fill: Frame
local fillGradient: UIGradient
local label: TextLabel
local glow: UIStroke
local barScale: UIScale
local flash: Frame
local wasReady = true
local readySound: Sound

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or Theme.CornerRadius
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Color = color or Colors.Ink
	s.Thickness = thickness or Theme.StrokeThickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function textLabel(parent: Instance, name: string, text: string, maxSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Text = text
	t.FontFace = Theme.FontFace
	t.TextColor3 = Colors.White
	t.TextScaled = true
	t.Size = UDim2.fromScale(1, 1)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = t
	local outline = Instance.new("UIStroke")
	outline.Color = Colors.Ink
	outline.Thickness = 2
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = t
	t.Parent = parent
	return t
end

local function isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

---------------------------------------------------------------------------------------------------
-- Dash cooldown bar

local function buildBar()
	bar = Instance.new("Frame")
	bar.Name = "DashCooldownBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -92)
	bar.Size = UDim2.new(0.22, 0, 0, 26)
	bar.BackgroundColor3 = Colors.Ink
	bar.BackgroundTransparency = 0.15
	bar.ZIndex = 2
	corner(bar, UDim.new(0.5, 0))
	stroke(bar, 3)
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(180, 26)
	size.MaxSize = Vector2.new(320, 26)
	size.Parent = bar
	barScale = Instance.new("UIScale")
	barScale.Parent = bar

	-- Soft outer glow that breathes while the dash is ready.
	local glowFrame = Instance.new("Frame")
	glowFrame.Name = "Glow"
	glowFrame.BackgroundTransparency = 1
	glowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	glowFrame.Position = UDim2.fromScale(0.5, 0.5)
	glowFrame.Size = UDim2.new(1, 8, 1, 8)
	glowFrame.ZIndex = 1
	corner(glowFrame, UDim.new(0.5, 0))
	glow = stroke(glowFrame, 4, Colors.Yellow)
	glowFrame.Parent = bar

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Colors.White
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 3
	corner(fill, UDim.new(0.5, 0))
	fillGradient = Instance.new("UIGradient")
	fillGradient.Color = READY
	fillGradient.Parent = fill
	fill.Parent = bar

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Colors.White
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.new(0.5, 0, 0, 3)
	gloss.Size = UDim2.new(1, -14, 0.3, 0)
	gloss.ZIndex = 4
	corner(gloss, UDim.new(0.5, 0))
	gloss.Parent = bar

	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Colors.White
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 5
	corner(flash, UDim.new(0.5, 0))
	flash.Parent = bar

	label = textLabel(bar, "Label", "DASH", 18)
	label.ZIndex = 6

	-- Key hint chip on the left (hidden on touch-only devices, which use the big button instead).
	local chip = Instance.new("Frame")
	chip.Name = "KeyHint"
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(0, -10, 0.5, 0)
	chip.Size = UDim2.fromOffset(56, 28)
	chip.BackgroundColor3 = Colors.Yellow
	chip.ZIndex = 2
	corner(chip, UDim.new(0, 8))
	stroke(chip, 3)
	local chipText = textLabel(chip, "Key", "SHIFT", 15)
	chipText.TextColor3 = Colors.Ink
	chipText.ZIndex = 3
	local chipStroke = chipText:FindFirstChildOfClass("UIStroke")
	if chipStroke then
		chipStroke.Enabled = false
	end
	chip.Parent = bar

	local slideChip = chip:Clone()
	slideChip.Name = "SlideHint"
	slideChip.AnchorPoint = Vector2.new(0, 0.5)
	slideChip.Position = UDim2.new(1, 10, 0.5, 0)
	slideChip.Size = UDim2.fromOffset(84, 28)
	slideChip.BackgroundColor3 = Colors.Cyan
	local slideText = slideChip:FindFirstChild("Key")
	if slideText and slideText:IsA("TextLabel") then
		slideText.Text = "C SLIDE"
	end
	slideChip.Parent = bar

	local function updateHints()
		local show = not isTouchOnly()
		chip.Visible = show
		slideChip.Visible = show
	end
	updateHints()
	UserInputService.LastInputTypeChanged:Connect(updateHints)

	bar.Parent = gui
end

local function flashReady()
	flash.BackgroundTransparency = 0.15
	TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	barScale.Scale = 1.16
	TweenService:Create(barScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	fillGradient.Color = READY
	label.Text = "DASH"
	if readySound then
		readySound:Play()
	end
end

local function shakeDenied()
	local base = UDim2.new(0.5, 0, 1, -92)
	label.TextColor3 = Colors.Red
	task.spawn(function()
		for _, x in { -7, 6, -4, 3, 0 } do
			bar.Position = base + UDim2.fromOffset(x, 0)
			task.wait(0.035)
		end
		bar.Position = base
		label.TextColor3 = Colors.White
	end)
end

local function onDash()
	-- Drop to empty in the same frame as the press.
	fill.Size = UDim2.fromScale(0, 1)
	fillGradient.Color = CHARGING
	wasReady = false
	barScale.Scale = 0.94
	TweenService:Create(barScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function updateBar(now: number)
	local progress = State.dashProgress(now)
	fill.Size = UDim2.fromScale(progress, 1)
	if progress >= 1 then
		if not wasReady then
			wasReady = true
			flashReady()
		end
		glow.Transparency = 0.55 + 0.3 * (0.5 + 0.5 * math.sin(now * 4))
	else
		if wasReady then
			wasReady = false
			fillGradient.Color = CHARGING
		end
		glow.Transparency = 1
		label.Text = string.format("%.1f", math.max(0, State.dashReadyAt - now))
	end
end

---------------------------------------------------------------------------------------------------
-- Mobile buttons (ContextActionService touch buttons, restyled)

type ButtonSkin = { button: ImageButton, shade: Frame, scale: UIScale, wasReady: boolean }
local skins: { [string]: ButtonSkin } = {}

local function skinButton(actionName: string, title: string, color: Color3): ButtonSkin?
	local existing = skins[actionName]
	local button = ContextActionService:GetButton(actionName)
	if not button then
		return nil
	end
	if existing and existing.button == button and button:FindFirstChild("PartyDashSkin") then
		return existing
	end

	button.ImageTransparency = 1
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = color
	button.AutoButtonColor = false

	local marker = Instance.new("Folder")
	marker.Name = "PartyDashSkin"
	marker.Parent = button

	corner(button, UDim.new(1, 0))
	stroke(button, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	-- Squash on press (the stock pressed image is hidden by our skin).
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.9 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Colors.White
	gloss.BackgroundTransparency = 0.7
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.fromScale(0.5, 0.08)
	gloss.Size = UDim2.fromScale(0.62, 0.26)
	gloss.ZIndex = button.ZIndex + 1
	corner(gloss, UDim.new(1, 0))
	gloss.Parent = button

	-- Cooldown: a dark shade clipped to the circle that shrinks from the top as it recharges.
	local clip = Instance.new("CanvasGroup")
	clip.Name = "Cooldown"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = button.ZIndex + 2
	corner(clip, UDim.new(1, 0))
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = Colors.Ink
	shade.BackgroundTransparency = 0.3
	shade.BorderSizePixel = 0
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0)
	shade.Parent = clip
	clip.Parent = button

	local text = textLabel(button, "Title", title, 30)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.52)
	text.Size = UDim2.fromScale(0.82, 0.36)
	text.ZIndex = button.ZIndex + 3

	local skin = { button = button, shade = shade, scale = scale, wasReady = true }
	skins[actionName] = skin
	return skin
end

local function jumpButtonRect(): (Vector2, number)
	local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		return jump.AbsolutePosition, jump.AbsoluteSize.X
	end
	-- Fallback: the stock touch controls' jump button layout.
	local viewport = gui.AbsoluteSize
	local small = math.min(viewport.X, viewport.Y) <= 500
	local size = if small then 70 else 120
	local y = if small then viewport.Y - size - 20 else viewport.Y - size * 1.75
	return Vector2.new(viewport.X - (size * 1.5 - 10), y), size
end

local function place(button: ImageButton, center: Vector2, size: number)
	local parent = button.Parent
	local origin = if parent and parent:IsA("GuiBase2d") then parent.AbsolutePosition else Vector2.zero
	button.AnchorPoint = Vector2.zero
	button.Size = UDim2.fromOffset(size, size)
	button.Position =
		UDim2.fromOffset(math.floor(center.X - size / 2 - origin.X), math.floor(center.Y - size / 2 - origin.Y))
end

-- Dash right above the jump button, Slide to its left: big, thumb-reachable and never overlapping.
local function layoutButtons()
	local dashSkin = skinButton(Stats.Action.Dash, "DASH", Colors.Pink)
	local slideSkin = skinButton(Stats.Action.Slide, "SLIDE", Colors.Cyan)
	if not dashSkin and not slideSkin then
		return
	end
	local jumpPos, jumpSize = jumpButtonRect()
	local size = math.clamp(jumpSize * 0.86, 58, 104)
	local gap = math.max(8, size * 0.14)
	local jumpCenter = jumpPos + Vector2.new(jumpSize / 2, jumpSize / 2)
	local dashCenter = jumpCenter - Vector2.new(0, jumpSize / 2 + gap + size / 2)
	local slideCenter = dashCenter - Vector2.new(size + gap, 0)
	if dashSkin then
		place(dashSkin.button, dashCenter, size)
	end
	if slideSkin then
		place(slideSkin.button, slideCenter, size)
	end
end

local function updateButtons(now: number)
	local dashSkin = skins[Stats.Action.Dash]
	if dashSkin and dashSkin.button.Parent then
		local progress = State.dashProgress(now)
		dashSkin.shade.Size = UDim2.fromScale(1, 1 - progress)
		local ready = progress >= 1
		if ready and not dashSkin.wasReady then
			dashSkin.scale.Scale = 1.15
			TweenService:Create(dashSkin.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		dashSkin.wasReady = ready
	end
	local slideSkin = skins[Stats.Action.Slide]
	if slideSkin and slideSkin.button.Parent then
		local remaining = if State.sliding
			then 1
			else math.clamp((State.slideReadyAt - now) / Config.SLIDE_COOLDOWN, 0, 1)
		slideSkin.shade.Size = UDim2.fromScale(1, remaining)
	end
end

---------------------------------------------------------------------------------------------------
-- Speed lines

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
	line.frame.Size = UDim2.fromOffset(line.len, 2 + math.random(0, 2))
	line.frame.Rotation = math.deg(line.angle)
end

local function buildLines()
	linesFrame = Instance.new("Frame")
	linesFrame.Name = "SpeedLines"
	linesFrame.BackgroundTransparency = 1
	linesFrame.Size = UDim2.fromScale(1, 1)
	linesFrame.ZIndex = 0
	linesFrame.Visible = false
	linesFrame.Parent = gui
	for _ = 1, SPEED_LINE_COUNT do
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Colors.White
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BackgroundTransparency = 1
		frame.Parent = linesFrame
		table.insert(lines, { frame = frame, angle = 0, r = 0, len = 0, speed = 0 })
	end
end

local function updateLines(now: number, dt: number)
	local target = 0
	if now < burstUntil then
		target = 1
	elseif State.sliding then
		target = 0.45
	end
	lineStrength += (target - lineStrength) * (1 - math.exp(-(if target > lineStrength then 25 else 7) * dt))
	if lineStrength < 0.01 then
		if linesFrame.Visible then
			linesFrame.Visible = false
		end
		return
	end
	local size = gui.AbsoluteSize
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
		line.frame.BackgroundTransparency = 1 - 0.55 * lineStrength * edgeFade
	end
end

---------------------------------------------------------------------------------------------------

function Hud.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("MovementHUD")
	if old then
		old:Destroy()
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "MovementHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 3

	readySound = Instance.new("Sound")
	readySound.Name = "DashReady"
	readySound.SoundId = Assets.Sounds.Ready
	readySound.Volume = 0.35
	readySound.Parent = SoundService

	buildLines()
	buildBar()
	gui.Parent = playerGui

	State.on("Dash", function()
		onDash()
		burstUntil = os.clock() + Config.DASH_DURATION + 0.18
	end)
	State.on("DashDenied", shakeDenied)

	RunService.PreRender:Connect(function(dt)
		local now = os.clock()
		updateBar(now)
		updateButtons(now)
		updateLines(now, dt)
	end)

	-- Touch buttons appear asynchronously and can be re-created; keep them skinned and placed.
	if UserInputService.TouchEnabled then
		task.spawn(function()
			while gui.Parent do
				local ok, err = pcall(layoutButtons)
				if not ok then
					warn("[Movement] touch button layout failed:", err)
				end
				task.wait(1)
			end
		end)
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			pcall(layoutButtons)
		end)
	end
end

return Hud
