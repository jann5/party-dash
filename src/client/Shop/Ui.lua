--!strict
-- Tiny UI kit for the economy screens. Layouts are authored in "design pixels" and a UIScale on the
-- root fits them to the screen, so the same layout reads well on a phone (~800x360) and on 1080p.
-- Text uses TextScaled + UITextSizeConstraint so long names shrink instead of overflowing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)

local C = Theme.Colors

local Ui = {}

Ui.INK = C.Ink
Ui.GOLD = Color3.fromRGB(255, 200, 45)
Ui.MUTED = Color3.fromRGB(190, 180, 235) -- secondary text on dark panels
Ui.CARD = Color3.fromRGB(62, 54, 108) -- card body on the window panel
Ui.TILE = Color3.fromRGB(36, 31, 64) -- dark preview tiles / troughs

function Ui.new(className: string, props: { [string]: any }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

function Ui.darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

function Ui.corner(parent: Instance, radius: UDim?): UICorner
	return Ui.new("UICorner", { CornerRadius = radius or UDim.new(0, 18), Parent = parent })
end

function Ui.stroke(parent: Instance, thickness: number?, color: Color3?, border: boolean?): UIStroke
	return Ui.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Ui.INK,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = if border == false then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.gradient(parent: Instance, c0: Color3, c1: Color3, rotation: number?): UIGradient
	-- a UIGradient multiplies the background color, so paint the base white to get the true colors
	if parent:IsA("Frame") or parent:IsA("TextButton") then
		parent.BackgroundColor3 = Color3.new(1, 1, 1)
	end
	return Ui.new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rotation or 90, Parent = parent })
end

-- Plain invisible container at a design-pixel rect.
function Ui.box(parent: Instance?, props: { [string]: any }?): Frame
	local f = Ui.new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(f :: any)[k] = v
			end
		end
	end
	f.Parent = parent
	return f
end

-- Rounded, ink-outlined panel.
function Ui.panel(
	parent: Instance?,
	color: Color3,
	props: { [string]: any }?,
	radius: UDim?,
	strokeWidth: number?
): Frame
	local f = Ui.box(nil, props)
	f.BackgroundTransparency = if props and props.BackgroundTransparency then props.BackgroundTransparency else 0
	f.BackgroundColor3 = color
	Ui.corner(f, radius)
	if strokeWidth ~= 0 then
		Ui.stroke(f, strokeWidth or 3)
	end
	f.Parent = parent
	return f
end

export type LabelOpts = { max: number?, stroke: number?, strokeColor: Color3? }

-- Cartoon label: Fredoka, scaled text capped at `max`, ink outline.
function Ui.label(parent: Instance?, text: string, props: { [string]: any }?, opts: LabelOpts?): TextLabel
	local o: LabelOpts = opts or {}
	local label = Ui.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = Theme.FontFace,
		Text = text,
		TextColor3 = C.White,
		TextScaled = true,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
	})
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(label :: any)[k] = v
			end
		end
	end
	Ui.new("UITextSizeConstraint", { MaxTextSize = o.max or 32, MinTextSize = 6, Parent = label })
	if o.stroke ~= 0 then
		Ui.new("UIStroke", {
			Thickness = o.stroke or 2,
			Color = o.strokeColor or Ui.INK,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = label,
		})
	end
	label.Parent = parent
	return label
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

function Ui.scaler(parent: Instance, initial: number?): UIScale
	return Ui.new("UIScale", { Scale = initial or 1, Parent = parent })
end

-- Quick "boing".
function Ui.punch(scale: UIScale, amount: number?, time: number?)
	scale.Scale = 1 + (amount or 0.15)
	Ui.tween(scale, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Horizontal "nope" shake of a GuiObject around its current position.
local shaking: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
function Ui.shake(obj: GuiObject, strength: number?)
	if shaking[obj] then
		return
	end
	shaking[obj] = true
	local home = obj.Position
	local amp = strength or 10
	task.spawn(function()
		for i = 1, 6 do
			local dir = if i % 2 == 0 then -1 else 1
			local falloff = 1 - (i - 1) / 6
			obj.Position = home + UDim2.fromOffset(dir * amp * falloff, 0)
			task.wait(0.035)
		end
		obj.Position = home
		shaking[obj] = nil
	end)
end

-- Drawn gold coin (the coin emoji has no glyph in Roblox fonts).
function Ui.coin(parent: Instance?, props: { [string]: any }?, strokeWidth: number?): Frame
	local coin = Ui.box(nil, props)
	coin.BackgroundTransparency = 0
	coin.BackgroundColor3 = Color3.new(1, 1, 1)
	coin.SizeConstraint = Enum.SizeConstraint.RelativeYY
	local z = coin.ZIndex
	Ui.corner(coin, UDim.new(0.5, 0))
	Ui.stroke(coin, strokeWidth or 3)
	Ui.gradient(coin, Color3.fromRGB(255, 236, 125), Color3.fromRGB(236, 150, 20))
	local rim = Ui.box(coin, {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(255, 214, 70),
		ZIndex = z,
	})
	Ui.corner(rim, UDim.new(0.5, 0))
	Ui.new("UIStroke", { Thickness = 1.5, Color = Color3.fromRGB(205, 120, 10), Transparency = 0.2, Parent = rim })
	local slot = Ui.box(coin, {
		Name = "Slot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.15, 0.46),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(215, 130, 15),
		ZIndex = z,
	})
	Ui.corner(slot, UDim.new(0.5, 0))
	local glint = Ui.box(coin, {
		Name = "Glint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.28),
		Size = UDim2.fromScale(0.16, 0.16),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = z,
	})
	Ui.corner(glint, UDim.new(0.5, 0))
	coin.Parent = parent
	return coin
end

-- Chunky cartoon button. Returns (button, scale). Hover grows, press squashes.
function Ui.button(parent: Instance?, color: Color3, props: { [string]: any }?, radius: UDim?): (TextButton, UIScale)
	local b = Ui.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.fromScale(1, 1),
	})
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(b :: any)[k] = v
			end
		end
	end
	Ui.corner(b, radius or UDim.new(0, 16))
	Ui.stroke(b, 3)
	local g = Ui.gradient(b, Ui.lighten(color, 0.25), color)
	g.Name = "Fill"
	local scale = Ui.scaler(b)
	b.MouseEnter:Connect(function()
		if b.Active then
			Ui.tween(scale, 0.15, { Scale = 1.06 }, Enum.EasingStyle.Back)
		end
	end)
	b.MouseLeave:Connect(function()
		Ui.tween(scale, 0.15, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		Ui.tween(scale, 0.08, { Scale = 0.93 })
	end)
	b.MouseButton1Up:Connect(function()
		Ui.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.Parent = parent
	return b, scale
end

-- Little star burst (purchase "pop"). `center` is in the parent's design pixels.
function Ui.burst(parent: GuiObject, center: Vector2, color: Color3, count: number?)
	local n = count or 10
	for i = 1, n do
		local star = Ui.box(parent, {
			Name = "Spark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = if i % 3 == 0 then Color3.new(1, 1, 1) else color,
			Rotation = 45,
			ZIndex = parent.ZIndex + 8,
		})
		Ui.corner(star, UDim.new(0.25, 0))
		local angle = (i / n) * math.pi * 2 + math.random() * 0.5
		local dist = 55 + math.random() * 45
		local goal = center + Vector2.new(math.cos(angle), math.sin(angle)) * dist
		Ui.tween(star, 0.55, {
			Position = UDim2.fromOffset(goal.X, goal.Y),
			Size = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 1,
			Rotation = 225,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.6, function()
			star:Destroy()
		end)
	end
end

-- Recolors a Ui.button.
function Ui.tint(b: GuiObject, color: Color3)
	local g = b:FindFirstChild("Fill")
	if g and g:IsA("UIGradient") then
		g.Color = ColorSequence.new(Ui.lighten(color, 0.25), color)
	end
end

return Ui
