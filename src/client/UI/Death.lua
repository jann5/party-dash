--!nonstrict
-- Death panel (brief #17 / #28), opened by Core_Death:
--   { reason, placement, total, survived, aliveLeft, minigameId, killerName?, revive = { offered, endsAt, tokens } }
-- A card in the Action lane: reason icon + "OUT!" + "#5 of 9" + "by Alex", then the choices
--   REVIVE (while offered: radial timer, Robux price or FREE)  SPECTATE (auto after 6 s)  LOBBY
-- Choices go to Core_DeathChoice ("spectate" | "lobby"). The panel leaves on a choice, when the player is revived
-- (InRound) or starts spectating, or when the round ends. Remotes are connected lazily.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Info = require(script.Parent.Info)
local Remotes = require(script.Parent.Remotes)
local Revive = require(script.Parent.Revive)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Death = {}

local AUTO_SPECTATE = 6 -- seconds until SPECTATE is chosen for you
local REASON_ICON = {
	fell = "splash",
	water = "splash",
	splash = "splash",
	drowned = "splash",
	bomb = "explosion",
	boom = "explosion",
	exploded = "explosion",
	explosion = "explosion",
}

local holder: Frame = nil
local slide: Frame = nil
local panel = nil -- the open panel state

local function hide()
	local p = panel
	if not p then
		return
	end
	panel = nil
	p.conn:Disconnect()
	holder:SetAttribute("Shown", false)
	UIKit.tween(slide, 0.22, { Position = UDim2.fromOffset(0, 300) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.23, function()
		if panel == nil then
			holder.Visible = false
		end
		p.card:Destroy()
	end)
end

local function choose(kind: string)
	if not panel or panel.chosen then
		return
	end
	panel.chosen = true
	holder:SetAttribute("Choice", kind)
	Remotes.fire("Core_DeathChoice", kind)
	hide()
end

local function headline(parent: Instance, payload): Frame
	local row = UIKit.new("Frame", {
		Name = "Headline",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -170, 0, 78),
		Position = UDim2.fromOffset(160, 10),
		ZIndex = 4,
		Parent = parent,
	})
	UIKit.list(row, Enum.FillDirection.Horizontal, 18, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	Widgets.dropText(row, {
		name = "Out",
		text = "OUT!",
		size = 70,
		font = "hype",
		color = C.Red,
		frameSize = UDim2.fromOffset(0, 78),
		autoSize = Enum.AutomaticSize.X,
		layoutOrder = 1,
		zindex = 6,
	})
	local placement, total = tonumber(payload.placement), tonumber(payload.total)
	if placement and total and total > 0 then
		local place = UIKit.text(row, {
			name = "Place",
			text = ("#%d of %d"):format(math.floor(placement), math.floor(total)),
			size = 40,
			frameSize = UDim2.fromOffset(0, 60),
			autoSize = Enum.AutomaticSize.X,
			zindex = 6,
		})
		place.LayoutOrder = 2
	end
	local killer = typeof(payload.killerName) == "string" and Info.clean(payload.killerName) or ""
	if utf8.len(killer) and utf8.len(killer) > 14 then
		killer = killer:sub(1, utf8.offset(killer, 14) - 1) .. "..."
	end
	if killer ~= "" then
		local by = UIKit.text(row, {
			name = "Killer",
			text = "by " .. killer,
			size = 28,
			font = "bodyHeavy",
			color = C.Muted,
			frameSize = UDim2.fromOffset(0, 50),
			autoSize = Enum.AutomaticSize.X,
			zindex = 6,
		})
		by.LayoutOrder = 3
	end
	return row
end

function Death.show(payload)
	if typeof(payload) ~= "table" then
		return
	end
	if panel then
		panel.conn:Disconnect()
		panel.card:Destroy()
		panel = nil
	end
	local revive = typeof(payload.revive) == "table" and payload.revive or {}
	local offered = revive.offered == true and typeof(revive.endsAt) == "number" and revive.endsAt > State.now()
	local reason = typeof(payload.reason) == "string" and string.lower(payload.reason) or ""

	-- width fits the buttons row (REVIVE 230 + SPECTATE 226 + LOBBY 184, gaps and padding)
	local width = math.max(660, (offered and 246 or 0) + 226 + 16 + 184 + 56)
	local card = Widgets.card(slide, {
		name = "Card",
		size = UDim2.fromOffset(width, 206),
		position = UDim2.fromScale(0.5, 1),
		anchor = Vector2.new(0.5, 1),
		zindex = 2,
	})
	UIKit.icon(card, REASON_ICON[reason] or "skull_out", {
		name = "Reason",
		size = UDim2.fromOffset(150, 150),
		position = UDim2.fromOffset(70, 30),
		rotation = -10,
		zindex = 8,
	})
	headline(card, payload)

	local buttons = UIKit.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 100),
		Position = UDim2.new(0, 0, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		ZIndex = 4,
		Parent = card,
	})
	UIKit.list(
		buttons,
		Enum.FillDirection.Horizontal,
		16,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Bottom
	)

	local state = {
		card = card,
		chosen = false,
		autoAt = os.clock() + AUTO_SPECTATE,
		revive = nil,
	}

	if offered then
		local reviveButton = Revive.button(buttons, {
			size = Vector2.new(230, 88),
			layoutOrder = 1,
			tokens = revive.tokens,
			onRequest = function()
				-- hold the auto-spectate while the revive is being bought / processed
				if panel == state then
					state.autoAt = math.max(state.autoAt, os.clock() + math.max(0, revive.endsAt - State.now()) + 0.5)
				end
			end,
		})
		reviveButton.setWindow(revive.endsAt, Config.REVIVE_WINDOW)
		state.revive = reviveButton
	end
	local spectate = Widgets.button(buttons, {
		name = "Spectate",
		size = Vector2.new(226, 88),
		color = "Blue",
		icon = "spectate_eye",
		iconLeft = true,
		iconSize = 74,
		text = "Spectate",
		textSize = 28,
		layoutOrder = 2,
		onClick = function()
			choose("spectate")
		end,
	})
	Widgets.button(buttons, {
		name = "Lobby",
		size = Vector2.new(184, 88),
		color = "Green",
		icon = "home",
		iconLeft = true,
		iconSize = 72,
		text = "Lobby",
		textSize = 28,
		layoutOrder = 3,
		onClick = function()
			choose("lobby")
		end,
	})
	-- auto-spectate countdown bubble on the SPECTATE button
	local bubble = UIKit.new("Frame", {
		Name = "Auto",
		BackgroundColor3 = C.PanelDeep,
		Size = UDim2.fromOffset(42, 42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 4),
		ZIndex = spectate.button.ZIndex + 10,
		Parent = spectate.button,
	})
	UIKit.corner(bubble, UDim.new(0.5, 0))
	UIKit.border(bubble, 2.5)
	local autoLabel = UIKit.text(bubble, {
		name = "Seconds",
		text = tostring(AUTO_SPECTATE),
		size = 24,
		frameSize = UDim2.fromScale(1, 1),
		zindex = spectate.button.ZIndex + 11,
	})

	local lastShown = -1
	state.conn = RunService.Heartbeat:Connect(function()
		if panel ~= state then
			return
		end
		if state.revive and not state.revive.update() then
			-- the offer window closed: the button leaves, the rest stays
			state.revive.api.button:Destroy()
			state.revive = nil
		end
		local left = state.autoAt - os.clock()
		local secs = math.max(0, math.ceil(left))
		if secs ~= lastShown then
			lastShown = secs
			autoLabel.Text = tostring(secs)
			bubble.Visible = secs <= AUTO_SPECTATE
			if secs <= 3 and secs > 0 then
				UIKit.punch(bubble, 1.25)
			end
		end
		if left <= 0 then
			choose("spectate")
		end
	end)

	panel = state
	holder.Visible = true
	holder:SetAttribute("Shown", true)
	holder:SetAttribute("Choice", "")
	slide.Position = UDim2.fromOffset(0, 300)
	UIKit.tween(slide, 0.4, { Position = UDim2.new() }, Enum.EasingStyle.Back)
	Audio.ui("UiOpen")
end

function Death.start()
	local lane = UIKit.Lanes.get("Action")
	holder = UIKit.new("Frame", {
		Name = "PD_Death",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(820, 224),
		Visible = false,
		LayoutOrder = 20,
		Parent = lane,
	})
	holder:SetAttribute("Shown", false)
	slide = UIKit.new(
		"Frame",
		{ Name = "Slide", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holder }
	)

	Remotes.on("Core_Death", Death.show)
	-- the panel only leaves on these CHANGES (a test may open it in any phase)
	State.gs:GetAttributeChangedSignal("Phase"):Connect(function()
		if panel and State.phase() ~= "Round" then
			hide()
		end
	end)
	State.player:GetAttributeChangedSignal("InRound"):Connect(function()
		if panel and State.flag("InRound") then
			hide() -- revived
		end
	end)
	State.player:GetAttributeChangedSignal("Spectating"):Connect(function()
		if panel and State.flag("Spectating") then
			hide()
		end
	end)
end

return Death
