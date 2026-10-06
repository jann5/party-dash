-- Party Dash intro card (Phase Intro): minigame name, one-sentence rules and key hint chips
-- ("SPACE  JUMP" on PC, "TAP  JUMP" on touch), plus round / win-condition / modifier tags.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors
local Phase = GameState.Phase

local Intro = {}

function Intro.start(gui: ScreenGui)
	local root = Kit.box({ Name = "Intro", Visible = false, ZIndex = 20, Parent = gui })

	-- soft vignette so the card reads well over any map
	local vignette = Kit.new("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = root,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.25),
			NumberSequenceKeypoint.new(1, 0.6),
		}),
		Parent = vignette,
	})

	local card = Kit.panel(C.White, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.6),
		ZIndex = 21,
		Parent = root,
	}, UDim.new(0.08, 0), 5)
	Kit.aspect(1.6).Parent = card
	Kit.sizeLimit(820, 512).Parent = card
	local cardScale = Kit.scaler(card)

	-- header band in the minigame accent color
	local header = Kit.panel(C.Orange, {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.36),
		ZIndex = 22,
		Parent = card,
	}, UDim.new(0.22, 0), 0)
	-- square off the header's bottom corners where it meets the white body
	local headerFill = Kit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = C.Orange,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = header,
	})
	local shine = Kit.new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.96, 0.32),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = header,
	})
	Kit.corner(UDim.new(0.5, 0)).Parent = shine
	local bubble = Kit.panel(C.White, {
		Name = "IconBubble",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.55),
		Size = UDim2.fromScale(0.8, 0.8),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 23,
		Parent = header,
	}, UDim.new(0.5, 0), 4)
	local iconScale = Kit.scaler(bubble)
	local icon = Kit.label("🎲", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 24,
		Parent = bubble,
	}, { maxText = 120, stroke = 0 })
	local title = Kit.label("", {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.23, 0.55),
		Size = UDim2.fromScale(0.73, 0.62),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = header,
	}, { maxText = 90, stroke = 5 })

	local rules = Kit.label("", {
		Name = "Rules",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.41),
		Size = UDim2.fromScale(0.88, 0.25),
		TextColor3 = C.Ink,
		ZIndex = 22,
		Parent = card,
	}, { maxText = 44, stroke = 0 })

	local chipRow = Kit.box({
		Name = "Keys",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromScale(0.92, 0.17),
		ZIndex = 22,
		Parent = card,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.025, 0),
		Parent = chipRow,
	})

	-- tags hanging off the card edges
	local roundTag = Kit.panel(C.Ink, {
		Name = "RoundTag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.05, 0),
		Size = UDim2.fromScale(0.22, 0.1),
		ZIndex = 26,
		Parent = card,
	}, UDim.new(0.5, 0), 3)
	local roundText = Kit.label("ROUND 1", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.84, 0.72),
		ZIndex = 27,
		Parent = roundTag,
	}, { maxText = 30, stroke = 2 })

	local goalTag = Kit.panel(C.Yellow, {
		Name = "GoalTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.5, 0.12),
		ZIndex = 26,
		Parent = card,
	}, UDim.new(0.5, 0), 3.5)
	Kit.gradient(C.Yellow, C.Orange).Parent = goalTag
	local goalText = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.7),
		ZIndex = 27,
		Parent = goalTag,
	}, { maxText = 34, stroke = 2.5 })

	local modTag = Kit.panel(C.Pink, {
		Name = "ModifierTag",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.96, 0),
		Size = UDim2.fromScale(0.42, 0.1),
		ZIndex = 26,
		Visible = false,
		Parent = card,
	}, UDim.new(0.5, 0), 3)
	Kit.gradient(C.Pink, C.Purple, 0).Parent = modTag
	local modText = Kit.label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.72),
		ZIndex = 27,
		Parent = modTag,
	}, { maxText = 30, stroke = 2 })

	local function makeChip(action: string, order: number, widthScale: number)
		local cap, verb = Data.keyHint(action)
		if not cap then
			return
		end
		local touch = Data.isTouch()
		local chip = Kit.panel(C.Panel, {
			Name = "Chip_" .. action,
			Size = UDim2.fromScale(widthScale, 1),
			LayoutOrder = order,
			ZIndex = 23,
			Parent = chipRow,
		}, UDim.new(0.3, 0), 3)
		chip:SetAttribute("Action", action)
		chip:SetAttribute("Key", cap)
		-- on PC: [KEY] VERB ; on touch: TAP [BUTTON]
		local capBox = Kit.panel(touch and C.Cyan or C.White, {
			Name = "KeyCap",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(touch and 0.4 or 0.04, 0.5),
			Size = UDim2.fromScale(0.56, 0.78),
			ZIndex = 24,
			Parent = chip,
		}, UDim.new(0.3, 0), 3)
		Kit.label(cap, {
			Name = "KeyText",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.7),
			TextColor3 = C.Ink,
			ZIndex = 25,
			Parent = capBox,
		}, { maxText = 30, stroke = 0 })
		Kit.label(verb, {
			Name = "Verb",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(touch and 0.05 or 0.62, 0.5),
			Size = UDim2.fromScale(0.33, 0.64),
			ZIndex = 24,
			Parent = chip,
		}, { maxText = 30, stroke = 2 })
		Kit.popIn(Kit.scaler(chip), 0.4, 0.35 + order * 0.1)
	end

	local visible = false
	local animConn: RBXScriptConnection? = nil

	local function fill()
		local id = GameState.read("MinigameId")
		local info = Data.minigame(typeof(id) == "string" and id ~= "" and id or "Mystery")
		title.Text = info.name
		icon.Text = info.icon
		rules.Text = info.text
		header.BackgroundColor3 = info.color
		headerFill.BackgroundColor3 = info.color
		local round = tonumber(GameState.read("RoundNumber"))
		roundTag.Visible = round ~= nil and round > 0
		roundText.Text = ("ROUND %d"):format(round or 0)
		local kind = info.kind ~= "" and info.kind or GameState.read("MinigameKind")
		goalText.Text = kind == "score" and "⭐ MOST POINTS WINS" or "🏆 LAST ONE STANDING WINS"
		local modId = GameState.read("ModifierId")
		modTag.Visible = typeof(modId) == "string" and modId ~= ""
		if modTag.Visible then
			modText.Text = "✨ " .. Data.modifier(modId).name
		end

		for _, child in chipRow:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local keys = {}
		local seen = {}
		for _, k in info.keys do
			if Data.keyHint(k) and not seen[k] then
				seen[k] = true
				table.insert(keys, k)
			end
		end
		local n = #keys
		local width = n > 0 and math.min(0.31, (1 - 0.025 * (n - 1)) / n) or 0
		for i, k in keys do
			makeChip(k, i, width)
		end
	end

	local function setVisible(on: boolean)
		if on == visible then
			if on then
				fill()
			end
			return
		end
		visible = on
		if on then
			fill()
			root.Visible = true
			vignette.BackgroundTransparency = 1
			Kit.tween(vignette, 0.3, { BackgroundTransparency = 0.45 })
			card.Rotation = -8
			Kit.popIn(cardScale, 0.55)
			Kit.tween(card, 0.7, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			Kit.popIn(iconScale, 0.6, 0.2)
			Sfx.play("pop", 1)
			local t0 = os.clock()
			animConn = RunService.RenderStepped:Connect(function()
				local t = os.clock() - t0
				bubble.Rotation = math.sin(t * 3) * 8
				goalTag.Rotation = math.sin(t * 2.2) * 2
			end)
		else
			if animConn then
				animConn:Disconnect()
				animConn = nil
			end
			Kit.tween(vignette, 0.25, { BackgroundTransparency = 1 })
			local tw = Kit.popOut(cardScale, 0.25)
			tw.Completed:Connect(function()
				if not visible then
					root.Visible = false
				end
			end)
		end
	end

	local function refresh()
		setVisible(GameState.read("Phase") == Phase.Intro)
	end
	GameState.onChanged("Phase", refresh)
	for _, key in { "MinigameId", "ModifierId", "RoundNumber", "MinigameKind" } do
		GameState.onChanged(key, function()
			if visible then
				fill()
			end
		end)
	end
	-- swap PC/touch hints if the player changes input device while the card is up
	local wasTouch = Data.isTouch()
	UserInputService.LastInputTypeChanged:Connect(function()
		local touch = Data.isTouch()
		if touch ~= wasTouch then
			wasTouch = touch
			if visible then
				fill()
			end
		end
	end)
	refresh()
end

return Intro
