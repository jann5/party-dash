-- One settings row (ART_BIBLE 8.4 card): a colored icon badge, a title, a short hint and a chunky ON/OFF switch
-- (green face + knob on the right when ON, grey face + knob on the left when OFF, 3D lip under it). The whole row
-- is the hit area. The row only draws the state: the caller decides what a toggle means through def.onToggle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIKit"))

local Style = UIKit.Style
local C = Style.Colors

local Toggle = {}

local ROW_HEIGHT = 100
local TRACK = Vector2.new(140, 56)
local LIP = 6
local KNOB = 44
local KNOB_INSET = 6
local SPEED = 0.18

local GREEN, GREEN_DARK = Style.Variants.Green[1], Style.Variants.Green[2]
local GREY, GREY_DARK = Style.Variants.Disabled[1], Style.Variants.Disabled[2]
local ROW_COLOR = C.PanelLight
local ROW_HOVER = Style.lighten(C.PanelLight, 0.07)

export type Def = {
	name: string,
	order: number,
	title: string,
	hint: string,
	icon: string,
	color: string,
	value: boolean,
	onToggle: (on: boolean) -> (),
}

export type Row = {
	button: TextButton,
	set: (on: boolean, animate: boolean?) -> (),
	get: () -> boolean,
}

local function face(parent: Instance, name: string, color: Color3, zindex: number): Frame
	local f = UIKit.new("Frame", {
		Name = name,
		BackgroundColor3 = C.White,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zindex,
		Parent = parent,
	})
	UIKit.corner(f, Style.Corner.Pill)
	UIKit.gradient(f, { Style.lighten(color, 0.15), color, Style.darken(color, 0.12) }, 90)
	return f
end

local function sheen(parent: Instance, zindex: number, radius: UDim)
	local g = UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -10, 0.45, 0),
		Position = UDim2.fromOffset(5, 3),
		ZIndex = zindex,
		Parent = parent,
	})
	UIKit.corner(g, radius)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0.55, 1),
		Parent = g,
	})
end

local function knobX(on: boolean): number
	return on and (TRACK.X - KNOB_INSET - KNOB / 2) or (KNOB_INSET + KNOB / 2)
end

function Toggle.new(parent: Instance, def: Def): Row
	local state = def.value
	local variant = Style.Variants[def.color] or Style.Variants.Blue

	local row = UIKit.new("TextButton", {
		Name = def.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = ROW_COLOR,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		LayoutOrder = def.order,
		ZIndex = 14,
		Parent = parent,
	})
	row:SetAttribute("PD_NoClick", true) -- the caller plays the click after the new state is applied
	UIKit.corner(row, UDim.new(0, 16))
	UIKit.border(row, Style.Stroke.Card)
	local rowScale = UIKit.new("UIScale", { Parent = row })
	UIKit.new("Frame", {
		Name = "TopLight",
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -28, 0, 2),
		Position = UDim2.fromOffset(14, 4),
		ZIndex = 15,
		Parent = row,
	})

	-- icon badge (square tile, illustrated icon overflowing it)
	local badge = UIKit.new("Frame", {
		Name = "IconBadge",
		BackgroundColor3 = C.White,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(74, 74),
		ZIndex = 15,
		Parent = row,
	})
	UIKit.corner(badge, Style.Corner.Tile)
	UIKit.border(badge, Style.Stroke.Card)
	UIKit.gradient(badge, { Style.lighten(variant[1], 0.15), variant[1], Style.darken(variant[1], 0.12) }, 90)
	sheen(badge, 16, Style.Corner.Tile)
	UIKit.icon(badge, def.icon, { size = UDim2.fromOffset(88, 88), rotation = -6, zindex = 17 })

	UIKit.text(row, {
		name = "Title",
		text = def.title,
		size = 38,
		xalign = "left",
		frameSize = UDim2.new(1, -290, 0, 46),
		position = UDim2.fromOffset(110, 12),
		zindex = 16,
	})
	UIKit.text(row, {
		name = "Hint",
		text = def.hint,
		size = Style.Text.Body,
		font = "body",
		color = C.Muted,
		stroke = 0,
		xalign = "left",
		frameSize = UDim2.new(1, -290, 0, 26),
		position = UDim2.fromOffset(112, 60),
		zindex = 16,
	})

	-- the switch: lip + track (grey base, green face cross-fades in) + ON/OFF words + knob
	local switch = UIKit.new("Frame", {
		Name = "Switch",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0),
		Size = UDim2.fromOffset(TRACK.X, TRACK.Y + LIP),
		ZIndex = 15,
		Parent = row,
	})
	local lip = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = GREY_DARK,
		Position = UDim2.fromOffset(0, LIP),
		Size = UDim2.fromOffset(TRACK.X, TRACK.Y),
		ZIndex = 15,
		Parent = switch,
	})
	UIKit.corner(lip, Style.Corner.Pill)
	UIKit.border(lip, Style.Stroke.Button)
	local track = UIKit.new("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(TRACK.X, TRACK.Y),
		ZIndex = 16,
		Parent = switch,
	})
	local offFace = face(track, "OffFace", GREY, 16)
	UIKit.border(offFace, Style.Stroke.Button)
	local onFace = face(track, "OnFace", GREEN, 17)
	sheen(track, 18, Style.Corner.Pill)
	local onText = UIKit.text(track, {
		name = "OnText",
		text = "ON",
		size = 26,
		frameSize = UDim2.new(0, TRACK.X - KNOB - KNOB_INSET * 2, 1, 0),
		position = UDim2.fromOffset(KNOB_INSET, 0),
		zindex = 19,
	})
	local offText = UIKit.text(track, {
		name = "OffText",
		text = "OFF",
		size = 26,
		frameSize = UDim2.new(0, TRACK.X - KNOB - KNOB_INSET * 2, 1, 0),
		position = UDim2.fromOffset(KNOB + KNOB_INSET * 2, 0),
		zindex = 19,
	})
	local onStroke = onText:FindFirstChildOfClass("UIStroke")
	local offStroke = offText:FindFirstChildOfClass("UIStroke")
	local knob = UIKit.new("Frame", {
		Name = "Knob",
		BackgroundColor3 = C.White,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(knobX(state), TRACK.Y / 2),
		Size = UDim2.fromOffset(KNOB, KNOB),
		ZIndex = 20,
		Parent = track,
	})
	UIKit.corner(knob, Style.Corner.Pill)
	UIKit.border(knob, Style.Stroke.Card)
	UIKit.gradient(knob, { C.White, Color3.fromRGB(212, 216, 232) }, 90)

	-- Moves every part of the switch to `state` (tweened or instant).
	local function apply(animate: boolean)
		local function to(inst: Instance?, props: { [string]: any }, style: Enum.EasingStyle?)
			if not inst then
				return
			end
			if animate then
				UIKit.tween(inst, SPEED, props, style)
			else
				for key, value in props do
					(inst :: any)[key] = value
				end
			end
		end
		local lit = state and 1 or 0 -- 1 = ON parts visible, OFF parts hidden
		to(knob, { Position = UDim2.fromOffset(knobX(state), TRACK.Y / 2) }, Enum.EasingStyle.Back)
		to(onFace, { BackgroundTransparency = 1 - lit })
		to(lip, { BackgroundColor3 = state and GREEN_DARK or GREY_DARK })
		to(onText, { TextTransparency = 1 - lit })
		to(onStroke, { Transparency = 1 - lit })
		to(offText, { TextTransparency = lit })
		to(offStroke, { Transparency = lit })
		if animate then
			UIKit.punch(knob, 1.18)
			UIKit.punch(badge, 1.1)
		end
	end
	apply(false)

	row.MouseEnter:Connect(function()
		UIKit.tween(row, 0.1, { BackgroundColor3 = ROW_HOVER })
	end)
	row.MouseLeave:Connect(function()
		UIKit.tween(row, 0.1, { BackgroundColor3 = ROW_COLOR })
		UIKit.tween(rowScale, 0.12, { Scale = 1 })
	end)
	row.MouseButton1Down:Connect(function()
		UIKit.tween(rowScale, 0.06, { Scale = 0.98 })
	end)
	row.MouseButton1Up:Connect(function()
		UIKit.tween(rowScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	row.Activated:Connect(function()
		def.onToggle(not state)
	end)

	local api = { button = row }
	function api.set(on: boolean, animate: boolean?)
		if on == state then
			return
		end
		state = on
		apply(animate == true)
	end
	function api.get(): boolean
		return state
	end
	return api
end

return Toggle
