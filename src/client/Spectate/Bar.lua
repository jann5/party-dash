--!nonstrict
-- Spectate bar in UIKit.Lanes "Action":
--   [<] [avatar  WATCHING / Name / 4 left] [>]   [Lobby]   [Revive while your offer is open]
-- With nobody alive it shows a calm "Nobody left" state. The arrows (and Q / E, bound by the caller) cycle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local UI = script.Parent.Parent:WaitForChild("UI")
local Info = require(UI:WaitForChild("Info"))
local Revive = require(UI:WaitForChild("Revive"))
local State = require(UI:WaitForChild("State"))
local Widgets = require(UI:WaitForChild("Widgets"))

local C = UIKit.Style.Colors

local Bar = {}

local HEIGHT = 116
local PAD = 18
local BASE_WIDTH = PAD + 84 + 14 + 380 + 14 + 84 + 26 + 180 + PAD
local REVIVE_WIDTH = 16 + 230

--[[
callbacks: onPrev(), onNext(), onLobby()
Returns { holder, show(), hide(), setTarget(player?, alive), update() }
]]
function Bar.new(callbacks: { [string]: () -> () })
	local lane = UIKit.Lanes.get("Action")
	local holder = UIKit.new("Frame", {
		Name = "PD_Spectate",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BASE_WIDTH + REVIVE_WIDTH, HEIGHT + 30),
		Visible = false,
		LayoutOrder = 30,
		Parent = lane,
	})
	holder:SetAttribute("Shown", false)
	local slide = UIKit.new(
		"Frame",
		{ Name = "Slide", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holder }
	)
	local card = Widgets.card(slide, {
		name = "Card",
		size = UDim2.fromOffset(BASE_WIDTH, HEIGHT),
		position = UDim2.fromScale(0.5, 1),
		anchor = Vector2.new(0.5, 1),
		zindex = 2,
	})
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, PAD), PaddingRight = UDim.new(0, PAD), Parent = card })
	UIKit.list(card, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

	local touch = Info.isTouch()
	local function arrow(name: string, glyph: string, key: string, order: number, onClick: () -> ())
		local b = Widgets.button(card, {
			name = name,
			size = Vector2.new(84, 80),
			color = "Blue",
			text = glyph,
			textSize = 52,
			layoutOrder = order,
			onClick = onClick,
		})
		if not touch then
			Widgets.keycap(b.button, key, 30, {
				position = UDim2.fromScale(0.5, 1),
				anchor = Vector2.new(0.5, 0.5),
				zindex = 20,
			})
		end
		return b
	end
	local prev = arrow("Prev", "<", "Q", 1, callbacks.onPrev)

	local info = UIKit.new("Frame", {
		Name = "Target",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 96),
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = card,
	})
	local caption = UIKit.text(info, {
		name = "Caption",
		text = "WATCHING",
		size = 20,
		font = "bodyHeavy",
		color = C.Muted,
		xalign = "left",
		frameSize = UDim2.new(1, -100, 0, 24),
		position = UDim2.fromOffset(100, 2),
		zindex = 5,
	})
	local nameLabel = UIKit.text(info, {
		name = "Name",
		text = "",
		size = 38,
		xalign = "left",
		frameSize = UDim2.new(1, -100, 0, 44),
		position = UDim2.fromOffset(100, 24),
		zindex = 5,
	})
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local alive = Widgets.pill(info, {
		name = "Alive",
		icon = "group_friends",
		text = "0 left",
		height = 30,
		position = UDim2.fromOffset(104, 70),
		zindex = 5,
	})
	local avatar = nil

	local nextButton = arrow("Next", ">", "E", 3, callbacks.onNext)
	UIKit.new("Frame", {
		Name = "Spacer",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(12, 10),
		LayoutOrder = 4,
		Parent = card,
	})
	Widgets.button(card, {
		name = "Lobby",
		size = Vector2.new(180, 80),
		color = "Green",
		icon = "home",
		iconLeft = true,
		iconSize = 70,
		text = "Lobby",
		textSize = 30,
		layoutOrder = 5,
		onClick = callbacks.onLobby,
	})

	local revive = nil -- Revive.button while Player.ReviveUntil is in the future
	local shown = false
	local currentUserId: number? = -1

	local api = { holder = holder }

	function api.setTarget(target: Player?, count: number)
		local userId = target and target.UserId or nil
		if userId ~= currentUserId then
			currentUserId = userId
			if avatar then
				avatar:Destroy()
			end
			avatar = Widgets.avatar(info, userId or 0, 88, {
				position = UDim2.fromOffset(0, 48),
				anchor = Vector2.new(0, 0.5),
				zindex = 5,
				fallback = "spectate_eye",
				ringColor = target and C.Blue or C.PanelLight,
			})
			UIKit.pop(avatar, 0.6, 0.25)
		end
		if target then
			caption.Text = "WATCHING"
			nameLabel.Text = target.DisplayName
			alive.fit(("%d left"):format(count))
			alive.frame.Visible = true
		else
			caption.Text = "SPECTATING"
			nameLabel.Text = "Nobody left"
			alive.frame.Visible = false
		end
		-- cycling needs someone else to cycle to
		prev.setEnabled(count > 1)
		nextButton.setEnabled(count > 1)
		holder:SetAttribute("TargetUserId", userId or 0)
		holder:SetAttribute("Empty", target == nil)
	end

	local function setRevive(endsAt: number?)
		if endsAt and not revive then
			revive = Revive.button(card, { size = Vector2.new(230, 80), layoutOrder = 6 })
			Widgets.popButton(revive.api)
		elseif not endsAt and revive then
			revive.api.button:Destroy()
			revive = nil
		end
		if revive and endsAt then
			revive.setWindow(endsAt, Config.REVIVE_WINDOW)
		end
		card.Size = UDim2.fromOffset(BASE_WIDTH + (revive and REVIVE_WIDTH or 0), HEIGHT)
	end

	-- Per frame while shown: the revive offer (Player.ReviveUntil, set by Core) and its ring.
	function api.update()
		if not shown then
			return
		end
		local untilT = State.player:GetAttribute("ReviveUntil")
		local open = typeof(untilT) == "number" and untilT > State.now() and not State.flag("InRound")
		setRevive(open and untilT or nil)
		if revive and not revive.update() then
			setRevive(nil)
		end
	end

	function api.show()
		if shown then
			return
		end
		shown = true
		holder.Visible = true
		holder:SetAttribute("Shown", true)
		slide.Position = UDim2.fromOffset(0, 240)
		UIKit.tween(slide, 0.35, { Position = UDim2.new() }, Enum.EasingStyle.Back)
		UIKit.sound("UiOpen")
	end

	function api.hide()
		if not shown then
			return
		end
		shown = false
		holder:SetAttribute("Shown", false)
		setRevive(nil)
		UIKit.tween(
			slide,
			0.22,
			{ Position = UDim2.fromOffset(0, 260) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		task.delay(0.23, function()
			if not shown then
				holder.Visible = false
			end
		end)
	end

	api.setTarget(nil, 0)
	return api
end

return Bar
