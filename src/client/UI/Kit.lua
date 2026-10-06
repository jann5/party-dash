-- Party Dash UI kit: tiny instance builders + tween helpers shared by every HUD module.
-- Everything is sized in Scale; pixel-based things (stroke widths) are rescaled with the viewport so
-- the cartoon outlines look the same on a phone (~800x360) and on 1080p.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.Theme)

local Kit = {}

local INK = Theme.Colors.Ink

-- Stroke registry: UIStroke -> base thickness at a 900px-tall reference screen.
local strokes: { [UIStroke]: number } = setmetatable({}, { __mode = "k" }) :: any
local pixelScale = 1

-- Generic constructor: Kit.new("Frame", { Size = ..., Parent = ... }, { child1, child2 })
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
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

function Kit.corner(radius: UDim?): UICorner
	return Kit.new("UICorner", { CornerRadius = radius or Theme.CornerRadius })
end

-- Thick cartoon outline. `base` is the thickness on a 900px-tall screen; it is rescaled automatically.
function Kit.stroke(base: number?, color: Color3?, border: boolean?): UIStroke
	local b = base or Theme.StrokeThickness
	local s = Kit.new("UIStroke", {
		Thickness = math.max(1, b * pixelScale),
		Color = color or INK,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	})
	strokes[s] = b
	return s
end

function Kit.gradient(c0: Color3, c1: Color3, rotation: number?): UIGradient
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(c0, c1),
		Rotation = rotation or 90,
	})
end

function Kit.aspect(ratio: number): UIAspectRatioConstraint
	return Kit.new("UIAspectRatioConstraint", { AspectRatio = ratio })
end

function Kit.sizeLimit(maxX: number, maxY: number, minX: number?, minY: number?): UISizeConstraint
	return Kit.new("UISizeConstraint", {
		MaxSize = Vector2.new(maxX, maxY),
		MinSize = Vector2.new(minX or 0, minY or 0),
	})
end

export type LabelOpts = {
	stroke: number?, -- outline thickness (nil = default, 0 = none)
	strokeColor: Color3?,
	maxText: number?, -- UITextSizeConstraint.MaxTextSize
	minText: number?,
}

-- Scaled cartoon label: Fredoka font, TextScaled + size constraint, thick ink outline.
function Kit.label(text: string, props: { [string]: any }?, opts: LabelOpts?): TextLabel
	local o: LabelOpts = opts or {}
	local base = {
		BackgroundTransparency = 1,
		FontFace = Theme.FontFace,
		Text = text,
		TextColor3 = Theme.Colors.White,
		TextScaled = true,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local label = Kit.new("TextLabel", base)
	Kit.new("UITextSizeConstraint", {
		MaxTextSize = math.min(o.maxText or 72, 100), -- TextScaled never renders above 100px
		MinTextSize = o.minText or 8,
		Parent = label,
	})
	if o.stroke ~= 0 then
		Kit.stroke(o.stroke or 2.5, o.strokeColor).Parent = label
	end
	return label
end

-- Plain invisible container.
function Kit.box(props: { [string]: any }?, children: { Instance }?): Frame
	local base = { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Kit.new("Frame", base, children)
end

-- Rounded, outlined colored panel.
function Kit.panel(color: Color3, props: { [string]: any }?, radius: UDim?, strokeBase: number?): Frame
	local base = { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local f = Kit.new("Frame", base)
	Kit.corner(radius).Parent = f
	if strokeBase ~= 0 then
		Kit.stroke(strokeBase or 3, INK, true).Parent = f
	end
	return f
end

-- Drawn gold coin (no emoji: the coin emoji has no glyph in Roblox fonts). Pass Size/Position/Parent.
function Kit.coin(props: { [string]: any }): Frame
	-- white base: the UIGradient below multiplies it into a shiny gold
	local base = { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }
	for k, v in props do
		base[k] = v
	end
	local coin = Kit.new("Frame", base)
	local z = coin.ZIndex
	Kit.corner(UDim.new(0.5, 0)).Parent = coin
	Kit.stroke(3, INK, true).Parent = coin
	Kit.gradient(Color3.fromRGB(255, 235, 120), Color3.fromRGB(235, 150, 20)).Parent = coin
	-- inner rim
	local rim = Kit.new("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		BackgroundColor3 = Color3.fromRGB(255, 215, 70),
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = coin,
	})
	Kit.corner(UDim.new(0.5, 0)).Parent = rim
	Kit.new("UIStroke", {
		Thickness = 2,
		Color = Color3.fromRGB(205, 120, 10),
		Transparency = 0.2,
		Parent = rim,
	})
	-- embossed slot + glint
	local slot = Kit.new("Frame", {
		Name = "Slot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.16, 0.5),
		BackgroundColor3 = Color3.fromRGB(215, 130, 15),
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = coin,
	})
	Kit.corner(UDim.new(0.5, 0)).Parent = slot
	local glint = Kit.new("Frame", {
		Name = "Glint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.28),
		Size = UDim2.fromScale(0.16, 0.16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = coin,
	})
	Kit.corner(UDim.new(0.5, 0)).Parent = glint
	return coin
end

-- UIScale child used for pop/punch animations (keeps the layout Size untouched).
function Kit.scaler(parent: Instance, initial: number?): UIScale
	return Kit.new("UIScale", { Scale = initial or 1, Parent = parent })
end

function Kit.tween(
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

-- Bouncy appear from nothing.
function Kit.popIn(scale: UIScale, time: number?, delay: number?): Tween
	scale.Scale = 0
	return Kit.tween(scale, time or 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
end

function Kit.popOut(scale: UIScale, time: number?): Tween
	return Kit.tween(scale, time or 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
end

-- Quick "boing" when a value changes.
function Kit.punch(scale: UIScale, amount: number?, time: number?): Tween
	scale.Scale = 1 + (amount or 0.18)
	return Kit.tween(scale, time or 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

function Kit.lighten(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount)
end

function Kit.darken(c: Color3, amount: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), amount)
end

-- Called by the boot script whenever the screen size changes.
function Kit.setViewport(size: Vector2)
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

function Kit.pixelScale(): number
	return pixelScale
end

return Kit
