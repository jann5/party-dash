--!nonstrict
-- How-to-play card (Phase Intro, round members only): the minigame icon and name on an accent header, ONE rule
-- line, control chips (PC keycaps or the touch button icons) and the goal ribbon "LAST ONE STANDING WINS".
-- A modifier round adds a "2x COINS" sticker with the modifier icon.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Audio = require(ReplicatedStorage.Shared.Audio)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Info = require(script.Parent.Info)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors
local Style = UIKit.Style

local Intro = {}

local SIZE = Vector2.new(860, 430)
local HEADER = 124

local gui: ScreenGui = nil
local root: Frame = nil
local view: Frame? = nil
local viewKey = ""

-- One control chip: keycap + verb on PC, the touch button icon + verb on phones.
local function chip(parent: Instance, action: string, order: number, touch: boolean)
	local hint = Info.keyHint(action)
	local f = UIKit.new("Frame", {
		Name = "Key_" .. action,
		BackgroundColor3 = C.PanelLight,
		Size = UDim2.fromOffset(0, 72),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		ZIndex = 6,
		Parent = parent,
	})
	UIKit.corner(f, UDim.new(0, 16))
	UIKit.border(f, 3)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 18), Parent = f })
	UIKit.list(f, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	if touch then
		local icon = UIKit.icon(f, hint.icon, { size = UDim2.fromOffset(60, 60), anchor = Vector2.zero, zindex = 7 })
		icon.LayoutOrder = 1
	else
		Widgets.keycap(f, hint.key, 50, { layoutOrder = 1, zindex = 7 })
	end
	local verb = UIKit.text(f, {
		text = hint.verb,
		size = 32,
		frameSize = UDim2.fromOffset(0, 60),
		autoSize = Enum.AutomaticSize.X,
		zindex = 7,
	})
	verb.LayoutOrder = 2
	return f
end

local function close()
	local v = view
	if not v then
		return
	end
	view = nil
	viewKey = ""
	Widgets.fadeOut(v, 0.18)
	local s = v:FindFirstChild("Card") and v.Card:FindFirstChild("PopScale")
	if s then
		UIKit.tween(s, 0.18, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(0.2, function()
		v:Destroy()
		if not view then
			gui.Enabled = false
		end
	end)
end

local function open(minigameId: string, modifierId: string)
	local info = Info.minigame(minigameId)
	local frame =
		UIKit.new("Frame", { Name = "View", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	-- soft dim so the card reads over any map
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = frame,
	})
	UIKit.tween(dim, 0.2, { BackgroundTransparency = 0.55 })

	local card = Widgets.card(frame, {
		name = "Card",
		size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		position = UDim2.fromScale(0.5, 0.47),
		anchor = Vector2.new(0.5, 0.5),
		zindex = 2,
		radius = 26,
	})

	-- accent header with the stripes overlay, gloss and the title
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER),
		ZIndex = 3,
		Parent = card,
	})
	UIKit.corner(header, UDim.new(0, 26))
	UIKit.border(header, 4)
	Widgets.paint(header, info.color)
	UIKit.new("Frame", {
		Name = "Squarer",
		BackgroundColor3 = Style.darken(info.color, 0.15),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 1, -26),
		ZIndex = 3,
		Parent = header,
	})
	-- ink seam between the header and the body
	UIKit.new("Frame", {
		Name = "Seam",
		BackgroundColor3 = C.Ink,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.new(0, 0, 1, -2),
		ZIndex = 5,
		Parent = header,
	})
	local stripes = Assets.Textures.stripes_diag
	if stripes and stripes ~= "" then
		local overlay = UIKit.new("ImageLabel", {
			Name = "Stripes",
			BackgroundTransparency = 1,
			Image = stripes,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(96, 96),
			ImageTransparency = 0.85,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = header,
		})
		UIKit.corner(overlay, UDim.new(0, 26))
	end
	local gloss = UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -12, 0.42, 0),
		Position = UDim2.fromOffset(6, 5),
		ZIndex = 4,
		Parent = header,
	})
	UIKit.corner(gloss, UDim.new(0, 22))
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Parent = gloss,
	})
	local icon = UIKit.icon(card, info.icon, {
		size = UDim2.fromOffset(200, 200),
		position = UDim2.fromOffset(92, HEADER * 0.42),
		rotation = -7,
		zindex = 8,
	})
	UIKit.text(header, {
		name = "Title",
		text = info.name,
		size = 64,
		drop = true,
		xalign = "left",
		frameSize = UDim2.new(1, -230, 1, 0),
		position = UDim2.fromOffset(200, 0),
		zindex = 6,
	})

	-- the one rule line
	local rules = UIKit.text(card, {
		name = "Rules",
		text = info.rules,
		size = 32,
		font = "bodyHeavy",
		wrap = true,
		frameSize = UDim2.new(1, -80, 0, 84),
		position = UDim2.new(0.5, 0, 0, HEADER + 18),
		anchor = Vector2.new(0.5, 0),
		zindex = 5,
	})
	rules.TextScaled = true
	UIKit.new("UITextSizeConstraint", { MaxTextSize = 32, MinTextSize = 16, Parent = rules })

	-- control chips
	local keys = UIKit.new("Frame", {
		Name = "Keys",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 80),
		Position = UDim2.new(0.5, 0, 0, HEADER + 116),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 5,
		Parent = card,
	})
	UIKit.list(keys, Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local touch = Info.isTouch()
	local actions = #info.keys > 0 and info.keys or { "Jump", "Dash", "Slide" }
	for i, action in actions do
		if i > 4 then
			break
		end
		chip(keys, action, i, touch)
	end

	-- goal ribbon hanging off the bottom edge
	local goal = Widgets.pill(card, {
		name = "Goal",
		icon = "trophy",
		text = "LAST ONE STANDING WINS",
		height = 70,
		fill = C.Gold,
		position = UDim2.new(0.5, 0, 1, 8),
		anchor = Vector2.new(0.5, 0.5),
		zindex = 9,
	})

	if modifierId ~= "" then
		local mod = Info.modifier(modifierId)
		local sticker = Widgets.pill(card, {
			name = "Modifier",
			icon = mod.icon,
			text = mod.name .. "  2x COINS",
			height = 58,
			fill = C.Purple,
			position = UDim2.new(1, 24, 0, -14),
			anchor = Vector2.new(1, 0.5),
			zindex = 10,
		})
		sticker.frame.Rotation = 6
	end

	UIKit.pop(card, 0.7, 0.3)
	UIKit.pop(goal.frame, 0.4, 0.4)
	icon.Rotation = -25
	UIKit.tween(icon, 0.45, { Rotation = -7 }, Enum.EasingStyle.Back)
	Audio.ui("UiOpen")
	return frame
end

local function sync()
	local want = State.phase() == "Intro" and State.isMember() and not State.flag("InSolo")
	local minigameId = State.str("MinigameId")
	if not want or minigameId == "" then
		close()
		return
	end
	local key = minigameId .. "|" .. State.str("ModifierId")
	if view and viewKey == key then
		return
	end
	if view then
		view:Destroy()
		view = nil
	end
	gui.Enabled = true
	view = open(minigameId, State.str("ModifierId"))
	viewKey = key
end

function Intro.start()
	gui, root = UIKit.screen("PD_Intro", UIKit.Style.Layers.Overlay + 1)
	gui.Enabled = false
	State.watch({ "Phase", "MinigameId", "ModifierId" }, { "InRound", "Eliminated", "Spectating", "InSolo" }, sync)
end

return Intro
