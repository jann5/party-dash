--!nonstrict
-- UIKit primitives: instance builder, screens with design-pixel scaling, outlined text, chunky buttons, icon tiles,
-- pills, badges, price tags and juice (pop/shake/pulse/count-up/shine). Client-only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Style = require(script.Parent.Style)

local Core = {}

local C = Style.Colors
local INK = C.Ink

local audioMod = nil
local function audio()
	if audioMod == nil then
		local ok, m = pcall(require, ReplicatedStorage.Shared.Audio)
		audioMod = ok and m or false
	end
	return audioMod or nil
end

function Core.sound(key: string, opts: any?)
	local a = audio()
	if a and a.ui then
		a.ui(key, opts)
	end
end

-- Generic constructor: Core.new("Frame", { Size = ..., Parent = ... }, { children })
function Core.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Core.corner(parent: Instance, radius: UDim?): UICorner
	return Core.new("UICorner", { CornerRadius = radius or Style.Corner.Card, Parent = parent })
end

-- Border stroke on a frame (UIStroke Border mode).
function Core.border(parent: Instance, thickness: number?, color: Color3?, transparency: number?): UIStroke
	return Core.new("UIStroke", {
		Thickness = thickness or Style.Stroke.Card,
		Color = color or INK,
		Transparency = transparency or 0,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Core.gradient(
	parent: Instance,
	colors: { Color3 } | ColorSequence,
	rotation: number?,
	transparency: NumberSequence?
): UIGradient
	local seq
	if typeof(colors) == "ColorSequence" then
		seq = colors
	elseif #colors == 1 then
		seq = ColorSequence.new(colors[1])
	elseif #colors == 2 then
		seq = ColorSequence.new(colors[1], colors[2])
	else
		local kps = {}
		for i, c in colors do
			table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
		end
		seq = ColorSequence.new(kps)
	end
	return Core.new(
		"UIGradient",
		{ Color = seq, Rotation = rotation or 90, Transparency = transparency, Parent = parent }
	)
end

function Core.padding(parent: Instance, px: number)
	return Core.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function Core.list(
	parent: Instance,
	dir: Enum.FillDirection,
	gap: number,
	halign: Enum.HorizontalAlignment?,
	valign: Enum.VerticalAlignment?
)
	return Core.new("UIListLayout", {
		FillDirection = dir,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

-- ===== screens & scaling =====

local function viewport(): Vector2
	local cam = Workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

-- Design scale for the current screen: 1 at 1080 px tall, never below 0.55 (phones) or above 1.3.
function Core.scale(): number
	local v = viewport()
	return math.clamp(v.Y / 1080, 0.55, 1.3)
end

function Core.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local screens = {}

-- A ScreenGui with a full-screen design canvas `Root` (children use design pixels; UIScale maps them to the
-- real screen). `layer` = Style.Layers key or a number. Returns (screenGui, root).
function Core.screen(name: string, layer: (string | number)?, opts: { [string]: any }?): (ScreenGui, Frame)
	local o = opts or {}
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(name)
	if old and old:IsA("ScreenGui") and old:FindFirstChild("Root") then
		return old, old.Root
	end
	local order = typeof(layer) == "number" and layer or Style.Layers[layer or "HUD"] or 10
	local gui = Core.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		ScreenInsets = o.fullscreen and Enum.ScreenInsets.None or Enum.ScreenInsets.DeviceSafeInsets,
		Enabled = o.enabled ~= false,
	})
	local root = Core.new("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local uiScale = Core.new("UIScale", { Parent = root })
	local function fit()
		local s = Core.scale()
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	table.insert(screens, fit)
	gui.Parent = pg
	return gui, root
end

task.spawn(function()
	local cam = Workspace.CurrentCamera
	while not cam do
		task.wait(0.1)
		cam = Workspace.CurrentCamera
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		for _, fit in screens do
			fit()
		end
	end)
end)

-- ===== text =====

-- Outlined label. props: text, size (design px font size), font ("display"|"hype"|"body"|"bodyHeavy"),
-- color, stroke (thickness override, 0 = none), drop (bool: extruded drop label behind), gold (bool gradient),
-- xalign ("left"|"center"|"right"), wrap, frameSize (UDim2), position, anchor, zindex, name, rich.
function Core.text(parent: Instance?, props: { [string]: any }): TextLabel
	local px = props.size or Style.Text.Body
	local fontFace = Style.Font
	if props.font == "hype" then
		fontFace = Style.FontHype
	elseif props.font == "body" then
		fontFace = Style.FontBody
	elseif props.font == "bodyHeavy" then
		fontFace = Style.FontBodyHeavy
	end
	local xalign = Enum.TextXAlignment.Center
	if props.xalign == "left" then
		xalign = Enum.TextXAlignment.Left
	elseif props.xalign == "right" then
		xalign = Enum.TextXAlignment.Right
	end
	local label = Core.new("TextLabel", {
		Name = props.name or "Label",
		BackgroundTransparency = 1,
		FontFace = fontFace,
		Text = props.text or "",
		TextColor3 = props.color or C.White,
		TextSize = px,
		TextWrapped = props.wrap == true,
		TextXAlignment = xalign,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = props.rich == true,
		Size = props.frameSize or UDim2.new(1, 0, 0, px * 1.25),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		ZIndex = props.zindex or 2,
		AutomaticSize = props.autoSize or Enum.AutomaticSize.None,
	})
	local th = props.stroke
	if th == nil then
		th = Style.textStroke(px)
	end
	if th > 0 then
		Core.new("UIStroke", {
			Thickness = th,
			Color = props.strokeColor or INK,
			LineJoinMode = Enum.LineJoinMode.Round,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			Parent = label,
		})
	end
	if props.gold then
		Core.gradient(label, { Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 170, 20) }, 90)
	elseif props.gradient then
		Core.gradient(label, props.gradient, 90)
	end
	if props.drop then
		-- Chunky extruded look: an ink copy BEHIND the label (a sibling with a lower ZIndex; children always draw
		-- on top of their parent), nudged down and kept in sync with the label.
		local dropLabel = label:Clone()
		dropLabel.Name = (label.Name or "Label") .. "Drop"
		dropLabel.TextColor3 = INK
		for _, g in dropLabel:GetChildren() do
			if g:IsA("UIGradient") then
				g:Destroy()
			end
		end
		local nudge = math.floor(px * 0.06 + 0.5)
		local function sync()
			dropLabel.Text = label.Text
			dropLabel.Size = label.Size
			dropLabel.AnchorPoint = label.AnchorPoint
			dropLabel.Position = label.Position + UDim2.fromOffset(0, nudge)
			dropLabel.Visible = label.Visible
			dropLabel.TextTransparency = label.TextTransparency
			dropLabel.Rotation = label.Rotation
			dropLabel.ZIndex = label.ZIndex - 1
			dropLabel.LayoutOrder = label.LayoutOrder
			dropLabel.Parent = label.Parent
		end
		for _, prop in
			{ "Text", "Size", "AnchorPoint", "Position", "Visible", "TextTransparency", "Rotation", "ZIndex", "Parent" }
		do
			label:GetPropertyChangedSignal(prop):Connect(sync)
		end
		label.Destroying:Connect(function()
			dropLabel:Destroy()
		end)
		label:SetAttribute("PD_HasDrop", true)
	end
	label.Parent = parent
	return label
end

-- ===== juice =====

function Core.tween(
	inst: Instance,
	t: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
): Tween
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function scaleOf(gui: GuiObject): UIScale
	local s = gui:FindFirstChild("PopScale")
	if not s then
		s = Core.new("UIScale", { Name = "PopScale", Parent = gui })
	end
	return s
end

-- Pop in (0 -> 1, Back Out). from = start scale (default 0.6).
function Core.pop(gui: GuiObject, from: number?, t: number?)
	local s = scaleOf(gui)
	s.Scale = from or 0.6
	Core.tween(s, t or 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Quick punch (1 -> amount -> 1).
function Core.punch(gui: GuiObject, amount: number?)
	local s = scaleOf(gui)
	s.Scale = amount or 1.15
	Core.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Horizontal shake (deny feedback).
function Core.shake(gui: GuiObject, px: number?)
	local base = gui.Position
	local d = px or 6
	task.spawn(function()
		for i = 1, 6 do
			gui.Position = base + UDim2.fromOffset((i % 2 == 0) and d or -d, 0)
			task.wait(0.03)
		end
		gui.Position = base
	end)
end

-- Endless pulse of a GuiObject's scale between 1 and `amount`. Returns stop().
function Core.pulse(gui: GuiObject, amount: number?, period: number?): () -> ()
	local s = scaleOf(gui)
	local tw = TweenService:Create(
		s,
		TweenInfo.new((period or 0.6) / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = amount or 1.12 }
	)
	tw:Play()
	return function()
		tw:Cancel()
		s.Scale = 1
	end
end

-- Idle bob (+-2 px, 1.6 s). Returns stop().
function Core.bob(gui: GuiObject, px: number?): () -> ()
	local base = gui.Position
	local tw = TweenService:Create(
		gui,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = base - UDim2.fromOffset(0, px or 2) }
	)
	tw:Play()
	return function()
		tw:Cancel()
		gui.Position = base
	end
end

-- Counts a label from -> to over `t` seconds using fmt (default Format.number).
function Core.countUp(label: TextLabel, from: number, to: number, t: number?, fmt: ((number) -> string)?)
	local Format = require(script.Parent.Format)
	local f = fmt or Format.number
	local value = Core.new("NumberValue", { Value = from })
	value.Changed:Connect(function(v)
		label.Text = f(v)
	end)
	label.Text = f(from)
	local tw = Core.tween(value, t or 0.6, { Value = to }, Enum.EasingStyle.Quad)
	tw.Completed:Once(function()
		label.Text = f(to)
		value:Destroy()
	end)
end

-- Diagonal white shine sweeping across `gui` every `every` seconds (offer buttons). Returns stop().
function Core.shine(gui: GuiObject, every: number?): () -> ()
	local holder = Core.new("Frame", {
		Name = "Shine",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = gui.ZIndex + 3,
		Parent = gui,
	})
	local corner = gui:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = holder
	end
	local band = Core.new("Frame", {
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.35, 2),
		Position = UDim2.fromScale(-0.6, -0.5),
		Rotation = 20,
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	Core.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = band,
	})
	local alive = true
	task.spawn(function()
		while alive and holder.Parent do
			band.Position = UDim2.fromScale(-0.6, -0.5)
			Core.tween(
				band,
				0.6,
				{ Position = UDim2.fromScale(1.3, -0.5) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut
			)
			task.wait(every or 3.5)
		end
	end)
	return function()
		alive = false
		holder:Destroy()
	end
end

-- ===== image helpers =====

function Core.icon(parent: Instance?, key: string, props: { [string]: any }?): ImageLabel
	local p = props or {}
	return Core.new("ImageLabel", {
		Name = p.name or "Icon",
		BackgroundTransparency = 1,
		Image = Assets.icon(key),
		ScaleType = Enum.ScaleType.Fit,
		Size = p.size or UDim2.fromOffset(64, 64),
		Position = p.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = p.anchor or Vector2.new(0.5, 0.5),
		Rotation = p.rotation or 0,
		ZIndex = p.zindex or 3,
		ImageColor3 = p.color or C.White,
		Parent = parent,
	})
end

-- Red "!" (or text) badge in the top-right corner of `parent`. Returns the badge (set .Visible).
function Core.badge(parent: GuiObject, text: string?, size: number?): Frame
	local s = size or 30
	local b = Core.new("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(s, s),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -s * 0.15, 0, s * 0.15),
		Rotation = -8,
		ZIndex = 20,
		Parent = parent,
	})
	Core.corner(b, UDim.new(0.5, 0))
	Core.border(b, 2.5)
	Core.text(b, {
		text = text or "!",
		size = s * 0.75,
		font = "hype",
		frameSize = UDim2.fromScale(1, 1),
		zindex = 21,
		stroke = 2,
	})
	local stop = Core.pulse(b, 1.12, 0.6)
	b.Destroying:Connect(stop)
	return b
end

-- ===== buttons =====

export type ButtonApi = {
	button: ImageButton,
	face: Frame,
	label: TextLabel?,
	icon: ImageLabel?,
	setText: (string) -> (),
	setColor: (string) -> (),
	setEnabled: (boolean) -> (),
	setBadge: (boolean, string?) -> (),
	destroy: () -> (),
}

--[[
Chunky button (ART_BIBLE 8.3): ink-outlined face with gradient, gloss and inner rim over a darker 3D lip.
props:
	size: Vector2 design px (default 220x76), position: UDim2, anchor: Vector2, zindex, name, layoutOrder
	color: Style.Variants key ("Green" default)
	text: string?, textSize: number?, font
	icon: Assets key?, iconSize: number? (px), iconLeft: bool (icon left of the text instead of centered above)
	sub: string? small line under the label (e.g. a timer)
	badge: string? (e.g. "!")
	shine: bool (offer shine sweep)
	corner: UDim?
	sound: string? (default "UiClick"; "" = silent)
	onClick: () -> ()
]]
function Core.button(parent: Instance?, props: { [string]: any }): ButtonApi
	local size: Vector2 = props.size or Vector2.new(220, 76)
	local lip = math.max(3, math.floor(size.Y * 0.08 + 0.5))
	local variant = props.color or "Green"
	local enabled = props.disabled ~= true
	local radius = props.corner or Style.Corner.Button

	local btn = Core.new("ImageButton", {
		Name = props.name or "Button",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		Size = UDim2.fromOffset(size.X, size.Y + lip),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		ZIndex = props.zindex or 5,
		LayoutOrder = props.layoutOrder or 0,
		Selectable = true,
	})
	local z = btn.ZIndex
	local scale = Core.new("UIScale", { Parent = btn })
	local lipFrame = Core.new("Frame", {
		Name = "Lip",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromOffset(0, lip),
		ZIndex = z,
		Parent = btn,
	})
	Core.corner(lipFrame, radius)
	Core.border(lipFrame, Style.Stroke.Button)
	local face = Core.new("Frame", {
		Name = "Face",
		BackgroundColor3 = C.White,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = z + 1,
		Parent = btn,
	})
	Core.corner(face, radius)
	Core.border(face, Style.Stroke.Button)
	local grad = Core.gradient(face, { C.White, C.White }, 90)
	local rim = Core.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		ZIndex = z + 1,
		Parent = face,
	})
	Core.corner(rim, radius)
	local rimStroke = Core.border(rim, 2, C.White, 0.2)
	local gloss = Core.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0.45, 0),
		Position = UDim2.fromOffset(4, 3),
		ZIndex = z + 2,
		Parent = face,
	})
	Core.corner(gloss, radius)
	Core.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Parent = gloss,
	})

	local iconImg: ImageLabel? = nil
	local label: TextLabel? = nil
	local subLabel: TextLabel? = nil
	local textSize = props.textSize or math.min(Style.Text.Button, math.floor(size.Y * 0.42))
	if props.icon then
		local isz = props.iconSize or math.floor(size.Y * (props.text and not props.iconLeft and 0.7 or 0.95))
		if props.iconLeft then
			iconImg = Core.icon(face, props.icon, {
				size = UDim2.fromOffset(isz, isz),
				position = UDim2.new(0, size.Y * 0.08 + isz / 2, 0.5, 0),
				zindex = z + 4,
			})
		elseif props.text then
			iconImg = Core.icon(face, props.icon, {
				size = UDim2.fromOffset(isz, isz),
				position = UDim2.new(0.5, 0, 0.38, 0),
				zindex = z + 4,
			})
		else
			iconImg = Core.icon(face, props.icon, {
				size = UDim2.fromOffset(isz, isz),
				position = UDim2.fromScale(0.5, 0.5),
				zindex = z + 4,
			})
		end
	end
	if props.text then
		local textFrame
		if props.icon and props.iconLeft then
			local isz = props.iconSize or math.floor(size.Y * 0.95)
			textFrame = UDim2.new(1, -(isz + size.Y * 0.16), 1, 0)
			label = Core.text(face, {
				text = props.text,
				size = textSize,
				font = props.font,
				frameSize = textFrame,
				position = UDim2.new(1, -size.Y * 0.08, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				zindex = z + 5,
			})
		elseif props.icon then
			label = Core.text(face, {
				text = props.text,
				size = textSize,
				font = props.font,
				frameSize = UDim2.new(1, 0, 0, textSize * 1.2),
				position = UDim2.new(0.5, 0, 1, -textSize * 0.15),
				anchor = Vector2.new(0.5, 1),
				zindex = z + 5,
			})
		else
			label = Core.text(face, {
				text = props.text,
				size = textSize,
				font = props.font,
				frameSize = UDim2.fromScale(1, props.sub and 0.66 or 1),
				position = UDim2.fromScale(0.5, props.sub and 0.38 or 0.5),
				anchor = Vector2.new(0.5, 0.5),
				zindex = z + 5,
			})
		end
	end
	if props.sub then
		subLabel = Core.text(face, {
			name = "Sub",
			text = props.sub,
			size = math.floor(textSize * 0.62),
			font = "bodyHeavy",
			frameSize = UDim2.new(1, 0, 0.32, 0),
			position = UDim2.fromScale(0.5, 0.8),
			anchor = Vector2.new(0.5, 0.5),
			zindex = z + 5,
		})
	end

	local badge: Frame? = nil
	local function applyColor()
		local v = Style.Variants[enabled and variant or "Disabled"] or Style.Variants.Green
		local c, dark = v[1], v[2]
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Style.lighten(c, 0.15)),
			ColorSequenceKeypoint.new(0.5, c),
			ColorSequenceKeypoint.new(1, Style.darken(c, 0.12)),
		})
		lipFrame.BackgroundColor3 = dark
		rimStroke.Color = Style.lighten(c, 0.45)
		if iconImg then
			iconImg.ImageColor3 = enabled and C.White or Color3.fromRGB(170, 170, 180)
		end
		if label then
			label.TextTransparency = enabled and 0 or 0.35
		end
	end
	applyColor()

	local pressed = false
	local function setPressed(p: boolean)
		if pressed == p then
			return
		end
		pressed = p
		if p then
			Core.tween(face, 0.06, { Position = UDim2.fromOffset(0, lip) })
			Core.tween(scale, 0.06, { Scale = 0.96 })
		else
			Core.tween(face, 0.14, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
			Core.tween(scale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	btn.MouseEnter:Connect(function()
		if enabled and not Core.isTouch() then
			Core.tween(scale, 0.1, { Scale = 1.04 })
		end
	end)
	btn.MouseLeave:Connect(function()
		setPressed(false)
		Core.tween(scale, 0.1, { Scale = 1 })
	end)
	btn.MouseButton1Down:Connect(function()
		if enabled then
			setPressed(true)
		end
	end)
	btn.MouseButton1Up:Connect(function()
		setPressed(false)
	end)
	btn:SetAttribute("PD_NoClick", true) -- the global click hook skips UIKit buttons (they play their own)
	btn.Activated:Connect(function()
		if not enabled then
			Core.sound("UiError")
			Core.shake(btn, 4)
			return
		end
		local snd = props.sound
		if snd == nil then
			snd = "UiClick"
		end
		if snd ~= "" then
			Core.sound(snd, { pitch = 0.95 + math.random() * 0.1 })
		end
		if props.onClick then
			task.spawn(props.onClick)
		end
	end)
	if props.badge then
		badge = Core.badge(btn, props.badge, math.floor(size.Y * 0.38))
	end
	if props.shine then
		Core.shine(face)
	end
	btn.Parent = parent

	local api = {
		button = btn,
		face = face,
		label = label,
		icon = iconImg,
		sub = subLabel,
	}
	function api.setText(t: string)
		if label then
			label.Text = t
		end
	end
	function api.setSub(t: string)
		if subLabel then
			subLabel.Text = t
		end
	end
	function api.setColor(v: string)
		variant = v
		applyColor()
	end
	function api.setEnabled(e: boolean)
		enabled = e
		applyColor()
	end
	function api.setBadge(on: boolean, text: string?)
		if on and not badge then
			badge = Core.badge(btn, text or "!", math.floor(size.Y * 0.38))
		elseif badge then
			badge.Visible = on
			if on and text then
				local l = badge:FindFirstChild("Label")
				if l then
					l.Text = text
				end
			end
		end
	end
	function api.destroy()
		btn:Destroy()
	end
	return api
end

--[[
Icon tile (ref1 "Items / Shop / Daily"): a square gradient tile, the illustrated icon overflowing it, and an
outlined label straddling the bottom edge. Optional badge and a small timer pill on top.
props: size (px, default 96), color (variant, default "Blue"), icon (Assets key), label, badge, timer (string),
onClick, name, layoutOrder, position, anchor, zindex
Returns ButtonApi + setTimer(text?)
]]
function Core.tile(parent: Instance?, props: { [string]: any }): ButtonApi
	local s = props.size or 96
	local api = Core.button(parent, {
		name = props.name or (props.label or "Tile"),
		size = Vector2.new(s, s),
		color = props.color or "Blue",
		corner = Style.Corner.Tile,
		layoutOrder = props.layoutOrder,
		position = props.position,
		anchor = props.anchor,
		zindex = props.zindex,
		onClick = props.onClick,
		badge = props.badge,
		shine = props.shine,
	})
	local z = api.button.ZIndex
	-- icon overflows the tile by ~12%
	api.icon = Core.icon(api.face, props.icon or "gift", {
		size = UDim2.fromOffset(s * 1.08, s * 1.08),
		position = UDim2.new(0.5, 0, 0.44, 0),
		zindex = z + 4,
	})
	if props.label then
		api.label = Core.text(api.button, {
			text = props.label,
			size = math.floor(s * 0.27),
			frameSize = UDim2.new(1.3, 0, 0, s * 0.34),
			position = UDim2.new(0.5, 0, 1, 2),
			anchor = Vector2.new(0.5, 1),
			zindex = z + 8,
		})
	end
	local timer: TextLabel? = nil
	function api.setTimer(text: string?)
		if not text then
			if timer then
				timer.Parent.Visible = false
			end
			return
		end
		if not timer then
			local pill = Core.new("Frame", {
				Name = "TimerPill",
				BackgroundColor3 = C.PanelDeep,
				BackgroundTransparency = 0.1,
				Size = UDim2.fromOffset(s * 0.9, s * 0.3),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 0),
				ZIndex = z + 9,
				Parent = api.button,
			})
			Core.corner(pill, Style.Corner.Pill)
			Core.border(pill, 2.5)
			timer = Core.text(pill, {
				text = text,
				size = math.floor(s * 0.2),
				frameSize = UDim2.fromScale(1, 1),
				zindex = z + 10,
			})
		end
		timer.Text = text
		timer.Parent.Visible = true
	end
	if props.timer then
		api.setTimer(props.timer)
	end
	return api
end

--[[
Pill: rounded counter/timer (ref1 "00:46", coin counter). props: icon (Assets key), text, size (Vector2 px,
default 200x56), color (Color3 background, default PanelDeep), textColor, iconSide ("left"|"both"), name,
position, anchor, zindex, layoutOrder. Returns { frame, label, icon, setText }.
]]
function Core.pill(parent: Instance?, props: { [string]: any })
	local size: Vector2 = props.size or Vector2.new(200, 56)
	local f = Core.new("Frame", {
		Name = props.name or "Pill",
		BackgroundColor3 = props.color or C.PanelDeep,
		BackgroundTransparency = props.transparency or 0.1,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		ZIndex = props.zindex or 4,
		LayoutOrder = props.layoutOrder or 0,
		Parent = parent,
	})
	Core.corner(f, Style.Corner.Pill)
	Core.border(f, 3)
	local z = f.ZIndex
	local icon = nil
	local leftPad = size.Y * 0.35
	if props.icon then
		local isz = size.Y * 1.25
		icon = Core.icon(f, props.icon, {
			size = UDim2.fromOffset(isz, isz),
			position = UDim2.new(0, size.Y * 0.35, 0.5, 0),
			zindex = z + 2,
		})
		leftPad = size.Y * 1.0
		if props.iconSide == "both" then
			Core.icon(f, props.icon, {
				name = "Icon2",
				size = UDim2.fromOffset(isz, isz),
				position = UDim2.new(1, -size.Y * 0.35, 0.5, 0),
				zindex = z + 2,
			})
		end
	end
	local rightPad = (props.iconSide == "both") and size.Y * 1.0 or size.Y * 0.35
	local label = Core.text(f, {
		text = props.text or "",
		size = props.textSize or math.floor(size.Y * 0.56),
		color = props.textColor,
		font = props.font,
		frameSize = UDim2.new(1, -(leftPad + rightPad), 1, 0),
		position = UDim2.new(0, leftPad, 0, 0),
		zindex = z + 3,
	})
	local api = { frame = f, label = label, icon = icon }
	function api.setText(t: string)
		label.Text = t
	end
	return api
end

-- Robux price text with optional struck-through old price above it. Returns the container Frame.
-- props: price (number), was (number?), size (font px, default 30), color (text color), position, anchor, zindex
function Core.priceTag(parent: Instance?, props: { [string]: any }): Frame
	local px = props.size or 30
	local f = Core.new("Frame", {
		Name = "PriceTag",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(px * 4, px * (props.was and 2.3 or 1.3)),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		ZIndex = props.zindex or 5,
		Parent = parent,
	})
	Core.text(f, {
		name = "Price",
		text = Style.robux(props.price or 0),
		size = px,
		color = props.color or C.White,
		frameSize = UDim2.new(1, 0, 0, px * 1.25),
		position = UDim2.new(0.5, 0, 1, 0),
		anchor = Vector2.new(0.5, 1),
		zindex = f.ZIndex + 1,
	})
	if props.was then
		local was = Core.text(f, {
			name = "Was",
			text = Style.robux(props.was),
			size = math.floor(px * 0.7),
			color = Color3.fromRGB(255, 80, 80),
			frameSize = UDim2.new(1, 0, 0, px * 0.9),
			position = UDim2.new(0.5, 0, 0, 0),
			anchor = Vector2.new(0.5, 0),
			zindex = f.ZIndex + 1,
		})
		Core.new("Frame", {
			Name = "Strike",
			BackgroundColor3 = Color3.fromRGB(255, 60, 60),
			BorderSizePixel = 0,
			Size = UDim2.new(0.62, 0, 0, 3),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = -10,
			ZIndex = f.ZIndex + 2,
			Parent = was,
		})
	end
	return f
end

return Core
