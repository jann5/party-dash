--!strict
-- UPGRADES tab: four cards (Dash Cooldown, Dash Distance, Jump Boost, Bat Power) with level pips,
-- now/next effect, and a coin buy button (or a gold MAXED state).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local C = Theme.Colors

local UpgradesTab = {}

local CARD_W, CARD_H, GAP = 226, 404, 16
local LOCKED = Color3.fromRGB(110, 100, 150)

type Card = { refresh: (animate: boolean) -> () }

local function statChip(parent: Instance, x: number, caption: string, name: string): (Frame, TextLabel, TextLabel)
	local chip = Ui.panel(parent, Ui.TILE, {
		Name = name,
		Position = UDim2.fromOffset(x, 0),
		Size = UDim2.fromOffset(99, 46),
		ZIndex = 4,
	}, UDim.new(0, 12), 0)
	local cap = Ui.label(chip, caption, {
		Name = "Caption",
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.new(1, 0, 0, 14),
		TextColor3 = Ui.MUTED,
		ZIndex = 5,
	}, { max = 13, stroke = 0 })
	local value = Ui.label(chip, "", {
		Name = "Value",
		Position = UDim2.fromOffset(4, 17),
		Size = UDim2.new(1, -8, 0, 26),
		ZIndex = 5,
	}, { max = 24, stroke = 2 })
	return chip, cap, value
end

local function buildCard(page: Frame, index: number, name: string, ctx: any): Card
	local def = Config.UPGRADES[name]
	local info = Rules.UPGRADE_INFO[name]
	local accent: Color3 = info.color

	local card = Ui.panel(page, Ui.CARD, {
		Name = name,
		Position = UDim2.fromOffset((index - 1) * (CARD_W + GAP), 0),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		ZIndex = 3,
	}, UDim.new(0, 22), 4)
	local cardScale = Ui.scaler(card)

	local header = Ui.panel(card, accent, {
		Name = "Header",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(CARD_W - 16, 142),
		ZIndex = 3,
	}, UDim.new(0, 16), 0)
	Ui.gradient(header, Ui.lighten(accent, 0.35), Ui.darken(accent, 0.1))
	local halo = Ui.box(header, {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((CARD_W - 16) / 2, 74),
		Size = UDim2.fromOffset(104, 104),
		BackgroundTransparency = 0.75,
		BackgroundColor3 = C.White,
		ZIndex = 3,
	})
	Ui.corner(halo, UDim.new(0.5, 0))
	local icon = Ui.label(header, info.icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((CARD_W - 16) / 2, 74),
		Size = UDim2.fromOffset(92, 80),
		ZIndex = 4,
	}, { max = 64, stroke = 0 })
	local iconScale = Ui.scaler(icon)
	local levelChip = Ui.panel(header, C.Ink, {
		Name = "LevelChip",
		Position = UDim2.fromOffset(CARD_W - 16 - 82, 8),
		Size = UDim2.fromOffset(74, 28),
		BackgroundTransparency = 0.3,
		ZIndex = 4,
	}, UDim.new(0.5, 0), 0)
	local levelChipText = Ui.label(levelChip, "LV 0", {
		Position = UDim2.fromOffset(4, 3),
		Size = UDim2.new(1, -8, 1, -6),
		ZIndex = 5,
	}, { max = 18, stroke = 0 })

	Ui.label(card, string.upper(def.name), {
		Name = "Title",
		Position = UDim2.fromOffset(10, 158),
		Size = UDim2.fromOffset(CARD_W - 20, 32),
		ZIndex = 4,
	}, { max = 25, stroke = 2.5 })
	Ui.label(card, info.blurb, {
		Name = "Blurb",
		Position = UDim2.fromOffset(10, 190),
		Size = UDim2.fromOffset(CARD_W - 20, 24),
		TextColor3 = Ui.MUTED,
		ZIndex = 4,
	}, { max = 18, stroke = 0 })

	local stats = Ui.box(card, {
		Name = "Stats",
		Position = UDim2.fromOffset(10, 222),
		Size = UDim2.fromOffset(CARD_W - 20, 46),
		ZIndex = 4,
	})
	local nowChip, _, nowValue = statChip(stats, 0, "NOW", "Now")
	local nextChip, nextCaption, nextValue = statChip(stats, 107, "NEXT", "Next")
	nextValue.TextColor3 = Color3.fromRGB(140, 255, 160)

	-- level pips
	local pips: { Frame } = {}
	local PIP_GAP = 8
	local pipW = (CARD_W - 28 - (Config.UPGRADE_MAX_LEVEL - 1) * PIP_GAP) / Config.UPGRADE_MAX_LEVEL
	local pipRow = Ui.box(card, {
		Name = "Pips",
		Position = UDim2.fromOffset(14, 280),
		Size = UDim2.fromOffset(CARD_W - 28, 18),
		ZIndex = 4,
	})
	for i = 1, Config.UPGRADE_MAX_LEVEL do
		local pip = Ui.panel(pipRow, Ui.TILE, {
			Name = "Pip" .. i,
			Position = UDim2.fromOffset((i - 1) * (pipW + PIP_GAP), 0),
			Size = UDim2.fromOffset(pipW, 18),
			ZIndex = 4,
		}, UDim.new(0.5, 0), 2.5)
		Ui.scaler(pip)
		pips[i] = pip
	end

	local buy, buyScale = Ui.button(card, C.Green, {
		Name = "Buy",
		Position = UDim2.fromOffset(14, 312),
		Size = UDim2.fromOffset(CARD_W - 28, 78),
		ZIndex = 4,
	}, UDim.new(0, 20))
	local buyCoin = Ui.coin(buy, {
		Name = "Coin",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(42, 39),
		Size = UDim2.fromOffset(42, 42),
		ZIndex = 5,
	}, 2.5)
	local buyText = Ui.label(buy, "", {
		Name = "Price",
		Position = UDim2.fromOffset(68, 14),
		Size = UDim2.fromOffset(CARD_W - 28 - 82, 50),
		ZIndex = 5,
	}, { max = 34, stroke = 3 })

	local busy = false
	local lastLevel = State.upgradeLevel(name)

	local function refresh(animate: boolean)
		local level = State.upgradeLevel(name)
		local price = Rules.upgradePrice(name, level)
		local maxed = price == nil
		levelChipText.Text = ("LV %d/%d"):format(level, Config.UPGRADE_MAX_LEVEL)
		nowValue.Text = Rules.upgradeEffect(name, level)
		if maxed then
			nextCaption.Text = "STATUS"
			nextValue.Text = "MAX"
			nextValue.TextColor3 = Ui.GOLD
		else
			nextCaption.Text = "NEXT"
			nextValue.Text = Rules.upgradeEffect(name, level + 1)
			nextValue.TextColor3 = Color3.fromRGB(140, 255, 160)
		end
		nowChip.Visible = true
		nextChip.Visible = true

		for i, pip in pips do
			local filled = i <= level
			pip.BackgroundColor3 = if filled then (if maxed then Ui.GOLD else accent) else Ui.TILE
			if animate and filled and i > lastLevel then
				local s = pip:FindFirstChildOfClass("UIScale")
				if s then
					Ui.punch(s, 0.6, 0.45)
				end
			end
		end
		lastLevel = level

		if maxed then
			Ui.tint(buy, Ui.GOLD)
			buyCoin.Visible = false
			buyText.Position = UDim2.fromOffset(12, 14)
			buyText.Size = UDim2.fromOffset(CARD_W - 28 - 24, 50)
			buyText.Text = "MAXED!"
			buy.Active = false
			buy.AutoButtonColor = false
		else
			local affordable = State.coins() >= (price :: number)
			Ui.tint(buy, if affordable then C.Green else LOCKED)
			buyCoin.Visible = true
			buyText.Position = UDim2.fromOffset(68, 14)
			buyText.Size = UDim2.fromOffset(CARD_W - 28 - 82, 50)
			buyText.Text = Rules.formatNumber(price :: number)
			buy.Active = true
		end
	end

	buy.Activated:Connect(function()
		local level = State.upgradeLevel(name)
		local price = Rules.upgradePrice(name, level)
		if busy or not price then
			if not price then
				Ui.punch(cardScale, 0.04, 0.25)
			end
			return
		end
		if not State.loaded() then
			ctx.toast("Your save is still loading...", false)
			return
		end
		if State.coins() < price then
			-- answer instantly; the server would refuse anyway
			Sfx.play("error")
			Ui.shake(card, 12)
			ctx.toast(("Not enough coins! You need %s more"):format(Rules.formatNumber(price - State.coins())), false)
			return
		end
		busy = true
		buyText.Text = "..."
		State.request("upgrade", name, function(ok: boolean, message: string)
			busy = false
			refresh(ok)
			if ok then
				Sfx.purchase()
				Ui.punch(cardScale, 0.07, 0.4)
				Ui.punch(iconScale, 0.35, 0.5)
				Ui.burst(card, Vector2.new(CARD_W / 2, 350), accent, 12)
				ctx.toast(message, true)
			else
				Sfx.play("error")
				Ui.shake(card, 12)
				ctx.toast(message, false)
			end
		end)
		Ui.punch(buyScale, -0.06, 0.2)
	end)

	refresh(false)
	return { refresh = refresh }
end

function UpgradesTab.build(page: Frame, ctx: any)
	local cards: { Card } = {}
	for i, name in Rules.UPGRADE_ORDER do
		table.insert(cards, buildCard(page, i, name, ctx))
	end
	State.changed:Connect(function(attr: string)
		if attr == "Coins" or string.sub(attr, 1, 4) == "Upg_" or attr == Rules.Attr.Loaded then
			for _, card in cards do
				card.refresh(true)
			end
		end
	end)
end

return UpgradesTab
