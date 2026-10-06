--!strict
-- Solo Record UI helpers: instance builders, cartoon outlines that scale with the screen, tweens.
-- Kept local to the Solo piece so it never depends on another system's internals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Ui = {}

local C = Theme.Colors
local strokes: { [UIStroke]: number } = setmetatable({}, { __mode = "k" }) :: any
local pixelScale = 1

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(parent: Instance, radius: UDim?): UICorner
	return Ui.new("UICorner", { CornerRadius = radius or Theme.CornerRadius, Parent = parent })
end

-- Thick ink outline; `base` is the thickness on a 900px-tall screen (rescaled with the viewport).
function Ui.stroke(parent: Instance, base: number?, color: Color3?, border: boolean?): UIStroke
	local b = base or Theme.StrokeThickness
	local s = Ui.new("UIStroke", {
		Thickness = math.max(1, b * pixelScale),
		Color = color or C.Ink,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
	strokes[s] = b
	return s
end

function Ui.gradient(parent: Instance, c0: Color3, c1: Color3, rotation: number?): UIGradient
	return Ui.new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rotation or 90, Parent = parent })
end

function Ui.aspect(parent: Instance, ratio: number): UIAspectRatioConstraint
	return Ui.new("UIAspectRatioConstraint", { AspectRatio = ratio, Parent = parent })
end

function Ui.limit(parent: Instance, maxX: number, maxY: number, minX: number?, minY: number?): UISizeConstraint
	return Ui.new("UISizeConstraint", {
		MaxSize = Vector2.new(maxX, maxY),
		MinSize = Vector2.new(minX or 0, minY or 0),
		Parent = parent,
	})
end

function Ui.scaler(parent: Instance, initial: number?): UIScale
	return Ui.new("UIScale", { Scale = initial or 1, Parent = parent })
end

-- Invisible container.
function Ui.box(props: { [string]: any }): Frame
	local base: { [string]: any } = { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }
	for k, v in props do
		base[k] = v
	end
	return Ui.new("Frame", base)
end

-- Rounded outlined panel.
function Ui.panel(color: Color3, props: { [string]: any }, radius: UDim?, strokeBase: number?): Frame
	local base: { [string]: any } = { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }
	for k, v in props do
		base[k] = v
	end
	local f = Ui.new("Frame", base)
	Ui.corner(f, radius)
	if strokeBase ~= 0 then
		Ui.stroke(f, strokeBase or 3, C.Ink, true)
	end
	return f
end

-- Scaled cartoon label (Fredoka, TextScaled + max size, ink outline).
function Ui.label(text: string, props: { [string]: any }, maxText: number?, strokeBase: number?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = Theme.FontFace,
		Text = text,
		TextColor3 = C.White,
		TextScaled = true,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in props do
		base[k] = v
	end
	local l = Ui.new("TextLabel", base)
	Ui.new("UITextSizeConstraint", { MaxTextSize = math.min(maxText or 72, 100), MinTextSize = 8, Parent = l })
	if strokeBase ~= 0 then
		Ui.stroke(l, strokeBase or 2.5)
	end
	return l
end

-- A chunky pill button with a gradient, a label and hover/press bounce. Returns (button, label, scale).
function Ui.button(
	text: string,
	color: Color3,
	props: { [string]: any },
	maxText: number?
): (TextButton, TextLabel, UIScale)
	local base: { [string]: any } = {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Selectable = true,
	}
	for k, v in props do
		base[k] = v
	end
	local button = Ui.new("TextButton", base)
	Ui.corner(button, UDim.new(0.5, 0))
	Ui.stroke(button, 3, C.Ink, true)
	local gradient = Ui.gradient(button, color:Lerp(C.White, 0.12), color:Lerp(C.Ink, 0.3))
	gradient.Name = "Fill"
	-- glossy top highlight
	local gloss = Ui.new("Frame", {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.86, 0.34),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = button.ZIndex,
		Parent = button,
	})
	Ui.corner(gloss, UDim.new(0.5, 0))
	local label = Ui.label(text, {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.84, 0.66),
		ZIndex = button.ZIndex + 1,
		Parent = button,
	}, maxText or 40, 2.5)
	local scale = Ui.scaler(button)
	Ui.bounce(button, scale)
	return button, label, scale
end

-- Hover grow + press squash on any GuiButton.
function Ui.bounce(button: GuiButton, scale: UIScale, hover: number?)
	local grow = hover or 1.06
	local over = false
	button.MouseEnter:Connect(function()
		over = true
		Ui.tween(scale, 0.15, { Scale = grow }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		over = false
		Ui.tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Ui.tween(scale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		Ui.tween(scale, 0.25, { Scale = if over then grow else 1 }, Enum.EasingStyle.Back)
	end)
end

function Ui.tween(
	inst: Instance,
	time: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
): Tween
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0),
		goal
	)
	tw:Play()
	return tw
end

function Ui.popIn(scale: UIScale, time: number?, delay: number?): Tween
	scale.Scale = 0
	return Ui.tween(scale, time or 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
end

function Ui.popOut(scale: UIScale, time: number?): Tween
	return Ui.tween(scale, time or 0.22, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
end

function Ui.punch(scale: UIScale, amount: number?, time: number?): Tween
	scale.Scale = 1 + (amount or 0.18)
	return Ui.tween(scale, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

function Ui.setViewport(size: Vector2)
	if size.Y <= 0 then
		return
	end
	pixelScale = math.clamp(size.Y / 900, 0.5, 1.4)
	for s, base in strokes do
		if s.Parent then
			s.Thickness = math.max(1, base * pixelScale)
		end
	end
end

return Ui
