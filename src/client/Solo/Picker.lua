--!strict
--[[
Solo picker: a modal with one card per solo-capable minigame (plus RANDOM). Each card shows your best
time and the world #1. Clicking a card calls onPick(id).

	local picker = Picker.new(overlayGui, onPick)
	picker.open() / picker.close() / picker.isOpen()
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
local Data = require(script.Parent.Data)
local Emblems = require(script.Parent.Emblems)
local Sfx = require(script.Parent.Sfx)
local Ui = require(script.Parent.Ui)

local Picker = {}

local C = Theme.Colors
local Z = 40
local CARD_GAP = 0.022
local MUTED = Color3.fromRGB(190, 185, 215)

export type Api = { open: () -> (), close: () -> (), isOpen: () -> boolean }

type CardRefs = { id: string, best: TextLabel?, world: TextLabel? }

function Picker.new(gui: ScreenGui, onPick: (string) -> ()): Api
	local localPlayer = Players.LocalPlayer

	local root = Ui.box({ Name = "SoloPicker", Visible = false, ZIndex = Z, Parent = gui })
	local dim = Ui.new("TextButton", {
		Name = "Dim",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z,
		Parent = root,
	})

	local panel = Ui.panel(C.White, {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.9, 0.78),
		ZIndex = Z + 1,
		Active = true,
		Parent = root,
	}, UDim.new(0.06, 0), 5)
	Ui.aspect(panel, 1.9)
	Ui.limit(panel, 1040, 548)
	Ui.gradient(panel, C.Panel:Lerp(C.Purple, 0.3), C.Panel:Lerp(C.Ink, 0.35))
	local panelScale = Ui.scaler(panel, 0)

	-- Title ribbon straddling the top edge.
	local ribbon = Ui.panel(C.White, {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.0),
		Size = UDim2.fromScale(0.46, 0.15),
		ZIndex = Z + 3,
		Parent = panel,
	}, UDim.new(0.5, 0), 4)
	Ui.gradient(ribbon, C.Yellow, C.Orange)
	Ui.label("SOLO RECORD", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.72),
		ZIndex = Z + 4,
		Parent = ribbon,
	}, 60, 3)

	Ui.label("Survive as long as you can and beat your best time!", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.11),
		Size = UDim2.fromScale(0.8, 0.075),
		TextColor3 = C.Cyan,
		ZIndex = Z + 2,
		Parent = panel,
	}, 30, 2)

	local closeButton = Ui.new("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.975, 0.04),
		Size = UDim2.fromScale(0.13, 0.13),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ZIndex = Z + 5,
		Parent = panel,
	})
	Ui.corner(closeButton, UDim.new(0.5, 0))
	Ui.stroke(closeButton, 3.5, C.Ink, true)
	Ui.gradient(closeButton, C.Red:Lerp(C.White, 0.15), C.Red:Lerp(C.Ink, 0.3))
	Ui.label("X", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = Z + 6,
		Parent = closeButton,
	}, 48, 2.5)
	local closeScale = Ui.scaler(closeButton)
	Ui.bounce(closeButton, closeScale, 1.12)

	local row = Ui.box({
		Name = "Cards",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.215),
		Size = UDim2.fromScale(0.95, 0.63),
		ZIndex = Z + 2,
		Parent = panel,
	})
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(CARD_GAP, 0),
		Parent = row,
	})

	Ui.label("Hazards speed up forever. Fall off and the clock stops!", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.8, 0.06),
		TextColor3 = Color3.fromRGB(200, 190, 240),
		ZIndex = Z + 2,
		Parent = panel,
	}, 24, 2)

	-- Cards ---------------------------------------------------------------------------------------------

	local cards: { CardRefs } = {}
	local builtKey = ""
	local isOpen = false
	local picking = false

	local function caption(parent: Instance, text: string, y: number, h: number, color: Color3, z: number): TextLabel
		return Ui.label(text, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromScale(0.88, h),
			TextColor3 = color,
			ZIndex = z,
			Parent = parent,
		}, 40, 2)
	end

	local function fillCard(refs: CardRefs)
		local bestLabel, worldLabel = refs.best, refs.world
		if not bestLabel or not worldLabel then
			return -- RANDOM
		end
		local best = Data.best(refs.id)
		bestLabel.Text = if best then Data.fmt(best) else "--"
		bestLabel.TextColor3 = if best then C.Yellow else MUTED
		local top = Data.top1(refs.id)
		if top then
			local mine = top.userId == localPlayer.UserId
			worldLabel.Text = ("%s  %s"):format(if mine then "YOU" else top.name, Data.fmt(top.seconds))
			worldLabel.TextColor3 = if mine then C.Green else C.White
		else
			worldLabel.Text = "Be the first!"
			worldLabel.TextColor3 = MUTED
		end
	end

	local function buildCard(id: string, name: string, accent: Color3, order: number, width: number): CardRefs
		local z = Z + 3
		local card = Ui.new("TextButton", {
			Name = "Card_" .. id,
			LayoutOrder = order,
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromScale(width, 0.9),
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = row,
		})
		Ui.aspect(card, 0.66)
		Ui.corner(card, UDim.new(0.1, 0))
		local outline = Ui.stroke(card, 3.5, C.Ink, true)
		Ui.gradient(card, C.Panel:Lerp(C.White, 0.12), C.Panel:Lerp(C.Ink, 0.2))
		local scale = Ui.scaler(card)

		local band = Ui.new("Frame", {
			Name = "Band",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.03),
			Size = UDim2.fromScale(0.92, 0.42),
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			ZIndex = z + 1,
			Parent = card,
		})
		Ui.corner(band, UDim.new(0.12, 0))
		Ui.gradient(band, accent:Lerp(C.White, 0.25), accent:Lerp(C.Ink, 0.25))
		local emblem = Ui.box({
			Name = "Emblem",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.82, 0.82),
			ZIndex = z + 2,
			Parent = band,
		})
		Ui.aspect(emblem, 1)
		Emblems.draw(emblem, id, accent)

		Ui.label(name, {
			Name = "GameName",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.475),
			Size = UDim2.fromScale(0.92, 0.1),
			ZIndex = z + 1,
			Parent = card,
		}, 40, 2.5)

		local refs: CardRefs
		if id == "RANDOM" then
			caption(card, "SURPRISE ME!", 0.62, 0.08, C.Cyan, z + 1)
			caption(card, "A random game", 0.72, 0.07, C.White, z + 1)
			caption(card, "every time", 0.8, 0.07, C.White, z + 1)
			refs = { id = id }
		else
			caption(card, "YOUR BEST", 0.6, 0.06, C.Cyan, z + 1)
			local best = caption(card, "--", 0.665, 0.1, C.Yellow, z + 1)
			caption(card, "WORLD #1", 0.78, 0.055, C.Pink, z + 1)
			local world = caption(card, "", 0.84, 0.075, C.White, z + 1)
			world.TextTruncate = Enum.TextTruncate.AtEnd
			refs = { id = id, best = best, world = world }
		end

		-- PLAY tab hanging off the bottom edge.
		local play = Ui.panel(C.White, {
			Name = "Play",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.985),
			Size = UDim2.fromScale(0.64, 0.11),
			ZIndex = z + 2,
			Parent = card,
		}, UDim.new(0.5, 0), 3)
		Ui.gradient(play, C.Green:Lerp(C.White, 0.1), C.Green:Lerp(C.Ink, 0.3))
		Ui.label("PLAY", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.8, 0.72),
			ZIndex = z + 3,
			Parent = play,
		}, 32, 2)

		card.MouseEnter:Connect(function()
			outline.Color = C.Yellow
			Ui.tween(scale, 0.18, { Scale = 1.06 }, Enum.EasingStyle.Back)
			Sfx.play("tick", 1.4)
		end)
		card.MouseLeave:Connect(function()
			outline.Color = C.Ink
			Ui.tween(scale, 0.18, { Scale = 1 })
		end)
		card.MouseButton1Down:Connect(function()
			Ui.tween(scale, 0.08, { Scale = 0.95 })
		end)
		card.Activated:Connect(function()
			if picking or not isOpen then
				return
			end
			picking = true
			Sfx.play("click")
			Ui.punch(scale, 0.12)
			task.delay(0.12, function()
				onPick(id)
			end)
		end)

		fillCard(refs)
		return refs
	end

	local function rebuild()
		local games = Data.soloGames()
		local key = ""
		for _, g in games do
			key ..= g.id .. ","
		end
		if key == builtKey then
			for _, refs in cards do
				fillCard(refs)
			end
			return
		end
		builtKey = key
		for _, child in row:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(cards)
		local n = #games + 1
		local width = math.min(0.19, (1 - CARD_GAP * (n - 1)) / n)
		for i, g in games do
			table.insert(cards, buildCard(g.id, g.name, g.accent, i, width))
		end
		table.insert(cards, buildCard("RANDOM", "RANDOM", C.Purple, n, width))
		if #games == 0 then
			Ui.label("Loading games...", {
				Size = UDim2.fromScale(0.6, 0.2),
				TextColor3 = C.Cyan,
				ZIndex = Z + 3,
				LayoutOrder = 0,
				Parent = row,
			}, 36, 2)
		end
	end

	-- Open / close --------------------------------------------------------------------------------------

	local api: Api
	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		Ui.tween(dim, 0.2, { BackgroundTransparency = 1 })
		local tw = Ui.popOut(panelScale, 0.2)
		tw.Completed:Connect(function()
			if not isOpen then
				root.Visible = false
			end
		end)
	end

	local function open()
		if isOpen then
			return
		end
		isOpen = true
		picking = false
		rebuild()
		root.Visible = true
		dim.BackgroundTransparency = 1
		Ui.tween(dim, 0.25, { BackgroundTransparency = 0.4 })
		Ui.popIn(panelScale, 0.42)
		Sfx.play("open")
	end

	dim.Activated:Connect(close)
	closeButton.Activated:Connect(function()
		Sfx.play("click", 0.8)
		close()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if isOpen and not processed and input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)

	-- Live updates while open (a new best or a fresh TOP list).
	localPlayer.AttributeChanged:Connect(function(attr)
		if isOpen and string.sub(attr, 1, #Data.BEST_PREFIX) == Data.BEST_PREFIX then
			rebuild()
		end
	end)
	task.spawn(function()
		local top = ReplicatedStorage:WaitForChild("SoloTop", 60)
		if top then
			top.AttributeChanged:Connect(function()
				if isOpen then
					rebuild()
				end
			end)
		end
	end)

	api = {
		open = open,
		close = close,
		isOpen = function()
			return isOpen
		end,
	}
	return api
end

return Picker
