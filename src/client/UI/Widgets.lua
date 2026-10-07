--!nonstrict
-- Small HUD widgets composed from Shared.UIKit primitives (UIKit stays the only kit: buttons, pills, text,
-- icons, corners and strokes all come from it; these helpers only arrange them).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Info = require(script.Parent.Info)

local Style = UIKit.Style
local C = Style.Colors

local Widgets = {}

-- UIKit hit areas are ImageButtons without an image. Ours get a fully transparent one so that no image element
-- the HUD creates is left blank (every visible image carries an asset).
local HIT_IMAGE = Assets.Textures.glow_soft or ""

function Widgets.fillHitArea(button: GuiObject)
	if button:IsA("ImageButton") and button.Image == "" and HIT_IMAGE ~= "" then
		button.Image = HIT_IMAGE
		button.ImageTransparency = 1
	end
end

-- UIKit.button with the hit-area image filled in.
function Widgets.button(parent: Instance?, props: { [string]: any })
	local api = UIKit.button(parent, props)
	Widgets.fillHitArea(api.button)
	return api
end

-- Pop-in for a UIKit button / tile: reuses the button's own hover UIScale (a second UIScale on the same object
-- would be ignored), so the whole button including its label grows in.
function Widgets.popButton(api)
	local scale = api.button:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.5
		UIKit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

--[[
UIKit.text with the chunky ink drop, wrapped in its own container. The drop is a sibling label, so the pair must
share a parent that can be popped / scaled / laid out as ONE item (a UIListLayout would otherwise place the drop
next to the text). props = UIKit.text props; frameSize / position / anchor / layoutOrder / name apply to the box.
With autoSize = X the box grows with the text. Returns (box, label).
]]
function Widgets.dropText(parent: Instance?, props: { [string]: any }): (Frame, TextLabel)
	local auto = props.autoSize or Enum.AutomaticSize.None
	local box = UIKit.new("Frame", {
		Name = props.name or "Text",
		BackgroundTransparency = 1,
		Size = props.frameSize or UDim2.new(1, 0, 0, (props.size or 22) * 1.25),
		AutomaticSize = auto,
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = props.zindex or 2,
		Parent = parent,
	})
	local p = table.clone(props)
	p.name = "Label"
	p.drop = true
	p.position = nil
	p.anchor = nil
	p.frameSize = if auto == Enum.AutomaticSize.X then UDim2.fromScale(0, 1) else UDim2.fromScale(1, 1)
	local label = UIKit.text(box, p)
	return box, label
end

-- Width of a single line of FredokaOne (or another legacy font) text in design px.
function Widgets.textWidth(text: string, px: number, font: Enum.Font?): number
	local ok, size =
		pcall(TextService.GetTextSize, TextService, text, px, font or Enum.Font.FredokaOne, Vector2.new(4000, px * 2))
	return ok and size.X or #text * px * 0.62
end

-- Glossy colour fill on a Frame: the UIKit button-face recipe (lighter top, the colour, darker bottom).
function Widgets.paint(frame: GuiObject, color: Color3)
	frame.BackgroundColor3 = C.White
	frame.BackgroundTransparency = 0
	local g = frame:FindFirstChild("Paint")
	if not g then
		g = UIKit.gradient(frame, { C.White, C.White }, 90)
		g.Name = "Paint"
	end
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Style.lighten(color, 0.18)),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, Style.darken(color, 0.15)),
	})
end

-- Pill width that fits its text (UIKit.pill padding rules).
function Widgets.pillWidth(text: string, height: number, hasIcon: boolean): number
	local px = math.floor(height * 0.56)
	local pads = (hasIcon and height or height * 0.35) + height * 0.35
	return math.ceil(Widgets.textWidth(text, px) + pads + 12)
end

--[[
Status pill: UIKit.pill sized to its text, optionally painted with a glossy colour.
props: name, icon, text, height (default 60), fill (Color3), textColor, layoutOrder, zindex, position, anchor
Returns the UIKit pill api plus fit(text) (sets the text and resizes) and setIcon(key).
]]
function Widgets.pill(parent: Instance?, props: { [string]: any })
	local h = props.height or 60
	local hasIcon = props.icon ~= nil
	local pill = UIKit.pill(parent, {
		name = props.name,
		icon = props.icon,
		text = props.text or "",
		size = Vector2.new(Widgets.pillWidth(props.text or "", h, hasIcon), h),
		textColor = props.textColor,
		transparency = props.fill and 0 or 0.08,
		layoutOrder = props.layoutOrder,
		zindex = props.zindex,
		position = props.position,
		anchor = props.anchor,
	})
	if props.fill then
		Widgets.paint(pill.frame, props.fill)
	end
	function pill.fit(text: string)
		if pill.label.Text ~= text then
			pill.label.Text = text
			pill.frame.Size = UDim2.fromOffset(Widgets.pillWidth(text, h, hasIcon), h)
		end
	end
	function pill.setIcon(key: string)
		if pill.icon then
			pill.icon.Image = Assets.icon(key)
		end
	end
	return pill
end

-- Dark rounded card with the panel gradient, ink outline and the faint stud pattern of UIKit panels.
function Widgets.card(parent: Instance?, props: { [string]: any }): Frame
	local f = UIKit.new("Frame", {
		Name = props.name or "Card",
		BackgroundColor3 = C.White,
		Size = props.size or UDim2.fromOffset(400, 200),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		AutomaticSize = props.autoSize or Enum.AutomaticSize.None,
		LayoutOrder = props.layoutOrder or 0,
		ZIndex = props.zindex or 2,
		Parent = parent,
	})
	UIKit.corner(f, UDim.new(0, props.radius or 22))
	UIKit.border(f, Style.Stroke.Panel)
	UIKit.gradient(f, { C.Panel, C.PanelDeep }, 90)
	local studs = Assets.Textures.studs
	if studs and studs ~= "" then
		local pattern = UIKit.new("ImageLabel", {
			Name = "Pattern",
			BackgroundTransparency = 1,
			Image = studs,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(40, 40),
			ImageTransparency = 0.92,
			Size = UDim2.fromScale(1, 1),
			ZIndex = f.ZIndex,
			Parent = f,
		})
		UIKit.corner(pattern, UDim.new(0, props.radius or 22))
	end
	return f
end

-- PC keycap: a small white key with an ink label ("SPACE", "C").
function Widgets.keycap(parent: Instance?, key: string, height: number, props: { [string]: any }?): Frame
	local p = props or {}
	local px = math.floor(height * 0.5)
	local w = math.max(height, math.ceil(Widgets.textWidth(key, px) + height * 0.6))
	local cap = UIKit.new("Frame", {
		Name = "Key",
		BackgroundColor3 = C.White,
		Size = UDim2.fromOffset(w, height),
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.new(),
		LayoutOrder = p.layoutOrder or 0,
		ZIndex = p.zindex or 6,
		Parent = parent,
	})
	UIKit.corner(cap, UDim.new(0, math.floor(height * 0.24)))
	UIKit.border(cap, 3)
	UIKit.gradient(cap, { C.White, Color3.fromRGB(196, 196, 214) }, 90)
	UIKit.text(cap, {
		text = key,
		size = px,
		color = C.Ink,
		stroke = 0,
		frameSize = UDim2.fromScale(1, 1),
		zindex = cap.ZIndex + 1,
	})
	return cap
end

--[[
Radial (pie) timer: a disc split into two clipped halves, each revealed by a hard-edged rotated UIGradient.
set(f) shows f (0..1) of the disc, clockwise from 12 o'clock. props: size, color, trackColor, position, anchor,
zindex, name. Returns { frame, set }.
]]
function Widgets.radial(parent: Instance?, props: { [string]: any })
	local size = props.size or 80
	local z = props.zindex or 5
	local frame = UIKit.new("Frame", {
		Name = props.name or "Radial",
		BackgroundColor3 = props.trackColor or C.PanelDeep,
		Size = UDim2.fromOffset(size, size),
		Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(),
		ZIndex = z,
		Parent = parent,
	})
	UIKit.corner(frame, UDim.new(0.5, 0))
	UIKit.border(frame, 3)
	local hardEdge = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local halves = {}
	for _, side in { "Right", "Left" } do
		local clip = UIKit.new("Frame", {
			Name = side,
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(side == "Right" and 0.5 or 0, 0),
			ZIndex = z + 1,
			Parent = frame,
		})
		local disc = UIKit.new("Frame", {
			Name = "Disc",
			BackgroundColor3 = C.White,
			Size = UDim2.fromScale(2, 1),
			Position = UDim2.fromScale(side == "Right" and -1 or 0, 0),
			ZIndex = z + 1,
			Parent = clip,
		})
		UIKit.corner(disc, UDim.new(0.5, 0))
		halves[side] = UIKit.new("UIGradient", {
			Color = ColorSequence.new(props.color or C.Gold),
			Transparency = hardEdge,
			Parent = disc,
		})
	end
	local api = { frame = frame }
	function api.set(f: number)
		local sweep = 360 * math.clamp(f, 0, 1)
		halves.Right.Rotation = math.min(sweep, 180)
		halves.Left.Rotation = if sweep > 180 then sweep else 180
	end
	api.set(1)
	return api
end

-- Round avatar: the player's headshot (or an icon for test accounts) inside an ink ring.
function Widgets.avatar(parent: Instance?, userId: number, size: number, props: { [string]: any }?)
	local p = props or {}
	local ring = UIKit.new("Frame", {
		Name = p.name or "Avatar",
		BackgroundColor3 = p.ringColor or C.PanelLight,
		Size = UDim2.fromOffset(size, size),
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.new(),
		LayoutOrder = p.layoutOrder or 0,
		ZIndex = p.zindex or 4,
		Parent = parent,
	})
	UIKit.corner(ring, UDim.new(0.5, 0))
	UIKit.border(ring, p.stroke or 3)
	local shot = Info.headshot(userId)
	local img = UIKit.new("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Image = shot or Assets.icon(p.fallback or "group_friends"),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(shot and 1 or 0.8, shot and 1 or 0.8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = ring.ZIndex + 1,
		Parent = ring,
	})
	UIKit.corner(img, UDim.new(0.5, 0))
	return ring, img
end

-- Tweens a GUI subtree to fully transparent (before it is destroyed or hidden).
function Widgets.fadeOut(root: Instance, t: number)
	local items = root:GetDescendants()
	table.insert(items, root)
	for _, d in items do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			UIKit.tween(d, t, { TextTransparency = 1, BackgroundTransparency = 1 })
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			UIKit.tween(d, t, { ImageTransparency = 1, BackgroundTransparency = 1 })
		elseif d:IsA("GuiObject") then
			UIKit.tween(d, t, { BackgroundTransparency = 1 })
		elseif d:IsA("UIStroke") then
			UIKit.tween(d, t, { Transparency = 1 })
		end
	end
end

return Widgets
