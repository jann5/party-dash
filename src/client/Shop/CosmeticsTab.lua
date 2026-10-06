--!strict
-- COSMETICS tab: slot list on the left (Trails / Dash / Bat / Win FX), a grid of preview cards on the
-- right. Cards buy with coins, equip what you own, and show VIP-only items with a gold lock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local C = Theme.Colors

local CosmeticsTab = {}

local LIST_W = 172
local GRID_X = LIST_W + 14
local CELL_W, CELL_H = 176, 198
local LOCKED = Color3.fromRGB(110, 100, 150)
local SLOT_ICONS = { Trail = "🌈", DashColor = "💨", BatColor = "🏏", WinEffect = "🎉" }
local DEFAULT_ICON = "🎊"
local CONFETTI = { C.Pink, C.Yellow, C.Cyan, C.Green, C.Purple, C.Orange }

type Entry = { slot: string, id: string, item: Cosmetics.Item?, refresh: () -> () }

-- Previews ------------------------------------------------------------------------------------------

local function ball(parent: Instance, x: number, y: number)
	local b = Ui.panel(parent, C.White, {
		Name = "Ball",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 6,
	}, UDim.new(0.5, 0), 3)
	Ui.gradient(b, C.White, Color3.fromRGB(200, 205, 230))
	-- two dot eyes so it reads as a little character
	for i = 0, 1 do
		local eye = Ui.box(b, {
			Position = UDim2.fromOffset(15 + i * 7, 9),
			Size = UDim2.fromOffset(4, 8),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.Ink,
			ZIndex = 7,
		})
		Ui.corner(eye, UDim.new(0.5, 0))
	end
end

-- A strip filled with the item's colors, fading out toward the tail (left).
local function streak(
	parent: Instance,
	x: number,
	y: number,
	w: number,
	h: number,
	seq: ColorSequence,
	rotation: number
)
	local f = Ui.box(parent, {
		Name = "Streak",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.White,
		Rotation = rotation,
		ZIndex = 5,
	})
	Ui.corner(f, UDim.new(0.5, 0))
	Ui.new("UIGradient", {
		Color = seq,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = f,
	})
	return f
end

local function preview(tile: Frame, slot: string, item: Cosmetics.Item?)
	local w, h = CELL_W - 16, 104
	if slot == "Trail" then
		if item then
			local seq = Cosmetics.sequence(item)
			streak(tile, w * 0.72, h * 0.56, 128, 30, seq, -12)
			streak(tile, w * 0.72, h * 0.56, 96, 12, ColorSequence.new(C.White), -12).BackgroundTransparency = 0.4
		end
		ball(tile, w * 0.78, h * 0.5)
	elseif slot == "DashColor" then
		local seq = if item then Cosmetics.sequence(item) else ColorSequence.new(C.White, C.Cyan)
		streak(tile, w * 0.68, h * 0.3, 96, 12, seq, 0)
		streak(tile, w * 0.68, h * 0.5, 120, 16, seq, 0)
		streak(tile, w * 0.68, h * 0.7, 80, 12, seq, 0)
		ball(tile, w * 0.76, h * 0.5)
	elseif slot == "BatColor" then
		local bat = Ui.box(tile, {
			Name = "Bat",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(w / 2, h / 2),
			Size = UDim2.fromOffset(130, 30),
			Rotation = -28,
			ZIndex = 5,
		})
		local color = if item then item.color else Theme.MinigameColors.KingOfTheHill
		local barrel = Ui.panel(bat, color, {
			Name = "Barrel",
			Position = UDim2.fromOffset(46, 0),
			Size = UDim2.fromOffset(84, 30),
			ZIndex = 6,
		}, UDim.new(0.5, 0), 3)
		if item and item.rainbow then
			barrel.BackgroundColor3 = C.White
			Ui.new("UIGradient", { Color = Cosmetics.RAINBOW, Parent = barrel })
		else
			Ui.gradient(barrel, Ui.lighten(color, 0.35), color)
		end
		local wood = Color3.fromRGB(150, 95, 55)
		Ui.panel(bat, wood, {
			Name = "Handle",
			Position = UDim2.fromOffset(4, 9),
			Size = UDim2.fromOffset(54, 12),
			ZIndex = 5,
		}, UDim.new(0.5, 0), 2.5)
		Ui.panel(bat, wood, {
			Name = "Knob",
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 6,
		}, UDim.new(0.5, 0), 2.5)
	else
		-- win effect: big emoji + a sprinkle of confetti
		for i = 1, 7 do
			local bit = Ui.box(tile, {
				Name = "Confetti",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(18 + ((i * 53) % (w - 30)), 14 + ((i * 37) % (h - 24))),
				Size = UDim2.fromOffset(10, 6),
				BackgroundTransparency = 0,
				BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1],
				Rotation = (i * 47) % 180,
				ZIndex = 5,
			})
			Ui.corner(bit, UDim.new(0, 2))
		end
		Ui.label(tile, if item and item.icon then item.icon else DEFAULT_ICON, {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(w / 2, h / 2),
			Size = UDim2.fromOffset(84, 76),
			ZIndex = 6,
		}, { max = 60, stroke = 0 })
	end
end

-- Cards ---------------------------------------------------------------------------------------------

local function buildCell(grid: ScrollingFrame, slot: string, item: Cosmetics.Item?, order: number, ctx: any): Entry
	local id = if item then item.id else ""
	local cell = Ui.box(grid, { Name = if item then item.id else "Default", LayoutOrder = order, ZIndex = 3 })
	local card = Ui.panel(cell, Ui.CARD, {
		Name = "Card",
		ZIndex = 3,
	}, UDim.new(0, 18), 3)
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local cardScale = Ui.scaler(card)

	local tile = Ui.panel(card, Ui.TILE, {
		Name = "Preview",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(CELL_W - 16, 104),
		ClipsDescendants = true,
		ZIndex = 4,
	}, UDim.new(0, 14), 0)
	preview(tile, slot, item)
	local previewScale = Ui.scaler(tile)

	local tag = Ui.panel(card, C.Green, {
		Name = "EquippedTag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(CELL_W / 2, 10),
		Size = UDim2.fromOffset(110, 26),
		Visible = false,
		ZIndex = 8,
	}, UDim.new(0.5, 0), 2.5)
	Ui.label(tag, "EQUIPPED", { Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 1, -6), ZIndex = 9 }, {
		max = 16,
		stroke = 2,
	})
	if item and (item.vip or item.rainbow) then
		local ribbon = Ui.panel(card, if item.vip then Ui.GOLD else C.Purple, {
			Name = "Ribbon",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(CELL_W - 4, 4),
			Size = UDim2.fromOffset(62, 24),
			Rotation = 8,
			ZIndex = 7,
		}, UDim.new(0.5, 0), 2.5)
		Ui.label(ribbon, if item.vip then "VIP" else "RARE", {
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.new(1, -8, 1, -4),
			ZIndex = 8,
		}, { max = 16, stroke = 2 })
	end

	Ui.label(card, if item then item.name else Cosmetics.SLOT_INFO[slot].defaultName, {
		Name = "ItemName",
		Position = UDim2.fromOffset(8, 116),
		Size = UDim2.fromOffset(CELL_W - 16, 28),
		ZIndex = 4,
	}, { max = 21, stroke = 2 })

	local button, buttonScale = Ui.button(card, C.Green, {
		Name = "Action",
		Position = UDim2.fromOffset(12, 148),
		Size = UDim2.fromOffset(CELL_W - 24, 40),
		ZIndex = 4,
	}, UDim.new(0, 14))
	local coin = Ui.coin(button, {
		Name = "Coin",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(28, 20),
		Size = UDim2.fromOffset(28, 28),
		ZIndex = 5,
	}, 2)
	local label = Ui.label(button, "", {
		Name = "Label",
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.fromOffset(CELL_W - 40, 30),
		ZIndex = 5,
	}, { max = 22, stroke = 2 })

	local busy = false
	local function state(): string
		local equipped = State.equipped(slot) == id
		if equipped then
			return "equipped"
		end
		if not item or State.owns(item) then
			return "owned"
		end
		if item.vip then
			return "vip"
		end
		return "buy"
	end

	local function refresh()
		local st = state()
		tag.Visible = st == "equipped"
		cardStroke.Color = if st == "equipped" then C.Green else C.Ink
		cardStroke.Thickness = if st == "equipped" then 4 else 3
		coin.Visible = st == "buy"
		if st == "buy" then
			local price = (item :: Cosmetics.Item).price
			label.Position = UDim2.fromOffset(46, 5)
			label.Size = UDim2.fromOffset(CELL_W - 24 - 54, 30)
			label.Text = Rules.formatNumber(price)
			Ui.tint(button, if State.coins() >= price then C.Green else LOCKED)
		else
			label.Position = UDim2.fromOffset(8, 5)
			label.Size = UDim2.fromOffset(CELL_W - 40, 30)
			if st == "equipped" then
				label.Text = "EQUIPPED"
				Ui.tint(button, Ui.darken(C.Green, 0.25))
			elseif st == "owned" then
				label.Text = "EQUIP"
				Ui.tint(button, C.Blue)
			else
				label.Text = "VIP ONLY"
				Ui.tint(button, Ui.darken(Ui.GOLD, 0.1))
			end
		end
	end

	local function done(ok: boolean, message: string, bought: boolean)
		busy = false
		refresh()
		if ok then
			if bought then
				Sfx.purchase()
				Ui.burst(card, Vector2.new(CELL_W / 2, 60), item and item.color or C.Yellow, 12)
			else
				Sfx.play("pop", 1.2)
			end
			Ui.punch(cardScale, 0.08, 0.4)
			Ui.punch(previewScale, 0.12, 0.4)
			ctx.toast(message, true)
		else
			Sfx.play("error")
			Ui.shake(card, 10)
			ctx.toast(message, false)
		end
	end

	button.Activated:Connect(function()
		if busy then
			return
		end
		if not State.loaded() then
			ctx.toast("Your save is still loading...", false)
			return
		end
		local st = state()
		Ui.punch(buttonScale, -0.06, 0.2)
		if st == "equipped" then
			Ui.punch(previewScale, 0.1, 0.3)
			return
		elseif st == "vip" then
			Sfx.play("click")
			ctx.toast("VIP only! Check out the VIP pass", false)
			ctx.switch("Robux")
			return
		elseif st == "owned" then
			busy = true
			if item then
				State.request("equip", id, function(ok, message)
					done(ok, message, false)
				end)
			else
				State.request("equip", slot, function(ok, message)
					done(ok, message, false)
				end, slot, "")
			end
		else
			local price = (item :: Cosmetics.Item).price
			if State.coins() < price then
				Sfx.play("error")
				Ui.shake(card, 10)
				ctx.toast(
					("Not enough coins! You need %s more"):format(Rules.formatNumber(price - State.coins())),
					false
				)
				return
			end
			busy = true
			label.Text = "..."
			State.request("cosmetic", id, function(ok, message)
				done(ok, message, true)
			end)
		end
	end)

	refresh()
	return { slot = slot, id = id, item = item, refresh = refresh }
end

-- Tab -----------------------------------------------------------------------------------------------

function CosmeticsTab.build(page: Frame, ctx: any)
	local entries: { Entry } = {}
	local grids: { [string]: ScrollingFrame } = {}
	local slotButtons: { [string]: { button: TextButton, scale: UIScale, count: TextLabel } } = {}
	local current = ""

	local list = Ui.box(page, { Name = "Slots", Size = UDim2.fromOffset(LIST_W, 404), ZIndex = 3 })
	for i, slot in Cosmetics.SLOTS do
		local b, s = Ui.button(list, Ui.CARD, {
			Name = slot,
			Position = UDim2.fromOffset(0, (i - 1) * 101),
			Size = UDim2.fromOffset(LIST_W, 90),
			ZIndex = 3,
		}, UDim.new(0, 18))
		Ui.label(b, SLOT_ICONS[slot], {
			Name = "Icon",
			Position = UDim2.fromOffset(8, 18),
			Size = UDim2.fromOffset(50, 50),
			ZIndex = 4,
		}, { max = 40, stroke = 0 })
		Ui.label(b, Cosmetics.SLOT_INFO[slot].title, {
			Name = "Title",
			Position = UDim2.fromOffset(60, 14),
			Size = UDim2.fromOffset(LIST_W - 68, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}, { max = 26, stroke = 2.5 })
		local count = Ui.label(b, "", {
			Name = "Count",
			Position = UDim2.fromOffset(60, 50),
			Size = UDim2.fromOffset(LIST_W - 68, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.MUTED,
			ZIndex = 4,
		}, { max = 16, stroke = 0 })
		slotButtons[slot] = { button = b, scale = s, count = count }

		local grid = Ui.new("ScrollingFrame", {
			Name = slot .. "Grid",
			Position = UDim2.fromOffset(GRID_X, 0),
			Size = UDim2.fromOffset(952 - GRID_X, 404),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = Ui.lighten(C.Pink, 0.3),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Visible = false,
			ZIndex = 3,
			Parent = page,
		})
		Ui.new("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 8),
			Parent = grid,
		})
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(CELL_W, CELL_H),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		grids[slot] = grid

		table.insert(entries, buildCell(grid, slot, nil, 0, ctx))
		for order, item in Cosmetics.list(slot) do
			table.insert(entries, buildCell(grid, slot, item, order, ctx))
		end
	end

	local function refreshCounts()
		for _, slot in Cosmetics.SLOTS do
			local owned, total = 0, 0
			for _, item in Cosmetics.list(slot) do
				total += 1
				if State.owns(item) then
					owned += 1
				end
			end
			slotButtons[slot].count.Text = ("%d / %d OWNED"):format(owned, total)
		end
	end

	local function selectSlot(slot: string)
		if current == slot then
			return
		end
		local first = current == ""
		current = slot
		for id, info in slotButtons do
			Ui.tint(info.button, if id == slot then C.Pink else Ui.CARD)
			grids[id].Visible = id == slot
		end
		Ui.punch(slotButtons[slot].scale, 0.06, 0.3)
		grids[slot].CanvasPosition = Vector2.zero
		if not first then
			Sfx.play("pop", 1.4)
		end
	end

	for slot, info in slotButtons do
		info.button.Activated:Connect(function()
			selectSlot(slot)
		end)
	end
	selectSlot("Trail")
	refreshCounts()

	State.changed:Connect(function(attr: string)
		if attr == "Coins" or attr == Rules.Attr.Owned or string.sub(attr, 1, 4) == "Cos_" or attr == "Pass_VIP" then
			for _, e in entries do
				e.refresh()
			end
			refreshCounts()
		end
	end)
end

return CosmeticsTab
