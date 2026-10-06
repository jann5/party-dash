--!strict
-- ROBUX tab: coin packs, instant upgrade products and gamepasses. Ids come from Config.PRODUCTS /
-- Config.GAMEPASSES; an id of 0 shows "COMING SOON" and never prompts a purchase. Prices are fetched
-- from MarketplaceService for configured ids. Granting happens on the server (ProcessReceipt).
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local C = Theme.Colors

local RobuxTab = {}

local ROW_W = 940
local SOON = Color3.fromRGB(105, 98, 140)
local ROBUX_GREEN = Color3.fromRGB(60, 200, 110)

local priceCache: { [string]: number } = {}

-- Fetches the Robux price once (yields). kind: "product" | "pass"
local function fetchPrice(kind: string, id: number): number?
	local key = kind .. id
	if priceCache[key] then
		return priceCache[key]
	end
	local infoType = if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
		priceCache[key] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

local function header(parent: Instance, text: string, order: number)
	local row = Ui.box(parent, { Name = text, Size = UDim2.fromOffset(ROW_W, 36), LayoutOrder = order, ZIndex = 3 })
	Ui.label(row, text, {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.fromOffset(ROW_W - 12, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 226, 110),
		ZIndex = 4,
	}, { max = 28, stroke = 2.5 })
end

-- A Robux buy button that knows the "coming soon" / owned / maxed states.
type RobuxButton = {
	button: TextButton,
	set: (mode: "price" | "soon" | "owned" | "maxed", price: number?) -> (),
}

local function robuxButton(parent: Instance, props: { [string]: any }, onBuy: () -> ()): RobuxButton
	local button, scale = Ui.button(parent, ROBUX_GREEN, props, UDim.new(0, 16))
	local label = Ui.label(button, "", {
		Name = "Label",
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.new(1, -16, 1, -12),
		ZIndex = (props.ZIndex or 4) + 1,
	}, { max = 28, stroke = 2.5 })
	local mode = "soon"
	local function set(m: string, price: number?)
		mode = m
		if m == "price" then
			label.Text = if price then ("R$ %s"):format(Rules.formatNumber(price)) else "BUY"
			Ui.tint(button, ROBUX_GREEN)
		elseif m == "owned" then
			label.Text = "OWNED"
			Ui.tint(button, Ui.darken(C.Green, 0.3))
		elseif m == "maxed" then
			label.Text = "MAXED!"
			Ui.tint(button, Ui.GOLD)
		else
			label.Text = "COMING SOON"
			Ui.tint(button, SOON)
		end
	end
	button.Activated:Connect(function()
		Ui.punch(scale, -0.06, 0.2)
		if mode == "price" then
			Sfx.play("click")
			onBuy()
		elseif mode == "soon" then
			Sfx.play("error")
			Ui.shake(button, 8)
		else
			Sfx.play("pop", 1.2)
		end
	end)
	set("soon")
	return { button = button, set = set :: any }
end

local function coinStack(parent: Instance, count: number)
	-- a little pile: bottom row first, higher coins in front
	local positions = {
		{ 0, 0 },
		{ -26, 8 },
		{ 26, 8 },
		{ -13, -18 },
		{ 13, -18 },
		{ 0, -36 },
	}
	for i = 1, math.min(count, #positions) do
		local p = positions[i]
		Ui.coin(parent, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(62 + p[1], 104 + p[2]),
			Size = UDim2.fromOffset(52, 52),
			ZIndex = 4 + i,
		}, 3)
	end
end

local function prompt(kind: string, id: number)
	local player = State.player
	pcall(function()
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
end

function RobuxTab.build(page: Frame, ctx: any)
	local scroll = Ui.new("ScrollingFrame", {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Ui.lighten(C.Green, 0.3),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 3,
		Parent = page,
	})
	Ui.new("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 10),
		Parent = scroll,
	})
	Ui.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = scroll,
	})

	local refreshers: { () -> () } = {}

	-- Coin packs ----------------------------------------------------------------------------------
	header(scroll, "COIN PACKS", 1)
	local packsRow =
		Ui.box(scroll, { Name = "CoinPacks", Size = UDim2.fromOffset(ROW_W, 184), LayoutOrder = 2, ZIndex = 3 })
	local PACK_W = (ROW_W - 2 * 16) / 3
	local packTags = { Coins1500 = "POPULAR", Coins5000 = "BEST VALUE" }
	for i, key in Rules.COIN_PACK_ORDER do
		local coins = Rules.COIN_PACKS[key]
		local card = Ui.panel(packsRow, Ui.CARD, {
			Name = key,
			Position = UDim2.fromOffset((i - 1) * (PACK_W + 16), 0),
			Size = UDim2.fromOffset(PACK_W, 184),
			ZIndex = 3,
		}, UDim.new(0, 20), 4)
		local glow = Ui.panel(card, Ui.TILE, {
			Name = "Pile",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(124, 164),
			ZIndex = 4,
		}, UDim.new(0, 16), 0)
		Ui.gradient(glow, Color3.fromRGB(90, 75, 40), Ui.TILE)
		coinStack(glow, i * 2)
		Ui.label(card, Rules.formatNumber(coins), {
			Name = "Amount",
			Position = UDim2.fromOffset(144, 22),
			Size = UDim2.fromOffset(PACK_W - 156, 46),
			TextColor3 = Color3.fromRGB(255, 226, 110),
			ZIndex = 4,
		}, { max = 40, stroke = 3 })
		Ui.label(card, "COINS", {
			Name = "Caption",
			Position = UDim2.fromOffset(144, 68),
			Size = UDim2.fromOffset(PACK_W - 156, 26),
			ZIndex = 4,
		}, { max = 22, stroke = 2 })
		local tag = packTags[key]
		if tag then
			local ribbon = Ui.panel(card, if key == "Coins5000" then C.Pink else C.Purple, {
				Name = "Ribbon",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromOffset(PACK_W + 6, 6),
				Size = UDim2.fromOffset(118, 28),
				Rotation = 6,
				ZIndex = 8,
			}, UDim.new(0.5, 0), 2.5)
			Ui.label(ribbon, tag, { Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 1, -6), ZIndex = 9 }, {
				max = 17,
				stroke = 2,
			})
		end
		local buy = robuxButton(card, {
			Name = "Buy",
			Position = UDim2.fromOffset(144, 112),
			Size = UDim2.fromOffset(PACK_W - 156, 56),
			ZIndex = 4,
		}, function()
			prompt("product", Config.PRODUCTS[key])
		end)
		table.insert(refreshers, function()
			local id = Config.PRODUCTS[key] or 0
			if id == 0 then
				buy.set("soon")
			else
				buy.set("price", priceCache["product" .. id])
			end
		end)
	end

	-- Instant upgrades ----------------------------------------------------------------------------
	header(scroll, "INSTANT UPGRADES", 3)
	local upgRow =
		Ui.box(scroll, { Name = "Upgrades", Size = UDim2.fromOffset(ROW_W, 150), LayoutOrder = 4, ZIndex = 3 })
	local UPG_W = (ROW_W - 3 * 16) / 4
	for i, name in Rules.UPGRADE_ORDER do
		local info = Rules.UPGRADE_INFO[name]
		local key = "Upgrade" .. name
		local card = Ui.panel(upgRow, Ui.CARD, {
			Name = key,
			Position = UDim2.fromOffset((i - 1) * (UPG_W + 16), 0),
			Size = UDim2.fromOffset(UPG_W, 150),
			ZIndex = 3,
		}, UDim.new(0, 20), 4)
		local iconTile = Ui.panel(card, info.color, {
			Name = "IconTile",
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(62, 62),
			ZIndex = 4,
		}, UDim.new(0, 14), 2.5)
		Ui.gradient(iconTile, Ui.lighten(info.color, 0.35), info.color)
		Ui.label(
			iconTile,
			info.icon,
			{ Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(50, 50), ZIndex = 5 },
			{
				max = 40,
				stroke = 0,
			}
		)
		Ui.label(card, string.upper(Config.UPGRADES[name].name), {
			Name = "Title",
			Position = UDim2.fromOffset(80, 12),
			Size = UDim2.fromOffset(UPG_W - 88, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}, { max = 20, stroke = 2 })
		local nextText = Ui.label(card, "", {
			Name = "Next",
			Position = UDim2.fromOffset(80, 44),
			Size = UDim2.fromOffset(UPG_W - 88, 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.MUTED,
			ZIndex = 4,
		}, { max = 17, stroke = 0 })
		local buy = robuxButton(card, {
			Name = "Buy",
			Position = UDim2.fromOffset(12, 84),
			Size = UDim2.fromOffset(UPG_W - 24, 54),
			ZIndex = 4,
		}, function()
			prompt("product", Config.PRODUCTS[key])
		end)
		table.insert(refreshers, function()
			local level = State.upgradeLevel(name)
			local id = Config.PRODUCTS[key] or 0
			if level >= Config.UPGRADE_MAX_LEVEL then
				nextText.Text = "Fully upgraded!"
				buy.set("maxed")
			else
				nextText.Text = ("Instantly to Lv %d"):format(level + 1)
				if id == 0 then
					buy.set("soon")
				else
					buy.set("price", priceCache["product" .. id])
				end
			end
		end)
	end

	-- Gamepasses ----------------------------------------------------------------------------------
	header(scroll, "GAME PASSES", 5)
	local passRow =
		Ui.box(scroll, { Name = "Passes", Size = UDim2.fromOffset(ROW_W, 170), LayoutOrder = 6, ZIndex = 3 })
	local PASS_W = (ROW_W - 16) / 2
	for i, name in Rules.PASS_ORDER do
		local info = Rules.PASS_INFO[name]
		local vip = name == "VIP"
		local card = Ui.panel(passRow, Ui.CARD, {
			Name = name,
			Position = UDim2.fromOffset((i - 1) * (PASS_W + 16), 0),
			Size = UDim2.fromOffset(PASS_W, 170),
			ZIndex = 3,
		}, UDim.new(0, 20), 4)
		local badge = Ui.panel(card, if vip then Ui.GOLD else C.Yellow, {
			Name = "Badge",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(146, 146),
			ZIndex = 4,
		}, UDim.new(0, 22), 3)
		if vip then
			Ui.gradient(badge, Color3.fromRGB(255, 245, 170), Color3.fromRGB(230, 145, 20))
			Ui.label(
				badge,
				"👑",
				{ Position = UDim2.fromOffset(28, 6), Size = UDim2.fromOffset(90, 70), ZIndex = 5 },
				{
					max = 56,
					stroke = 0,
				}
			)
			Ui.label(
				badge,
				"VIP",
				{ Position = UDim2.fromOffset(10, 80), Size = UDim2.fromOffset(126, 54), ZIndex = 5 },
				{
					max = 50,
					stroke = 3.5,
				}
			)
		else
			Ui.gradient(badge, Ui.lighten(C.Purple, 0.3), C.Purple)
			Ui.coin(badge, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(60, 64),
				Size = UDim2.fromOffset(78, 78),
				ZIndex = 5,
			}, 3)
			Ui.label(badge, "x2", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(104, 108),
				Size = UDim2.fromOffset(70, 56),
				Rotation = -10,
				ZIndex = 6,
			}, { max = 48, stroke = 3.5 })
		end
		Ui.label(card, info.title, {
			Name = "Title",
			Position = UDim2.fromOffset(172, 16),
			Size = UDim2.fromOffset(PASS_W - 186, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if vip then Color3.fromRGB(255, 225, 90) else C.White,
			ZIndex = 4,
		}, { max = 34, stroke = 3 })
		Ui.label(card, info.blurb, {
			Name = "Blurb",
			Position = UDim2.fromOffset(172, 58),
			Size = UDim2.fromOffset(PASS_W - 186, 46),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Ui.MUTED,
			ZIndex = 4,
		}, { max = 18, stroke = 0 })
		local buy = robuxButton(card, {
			Name = "Buy",
			Position = UDim2.fromOffset(172, 108),
			Size = UDim2.fromOffset(220, 50),
			ZIndex = 4,
		}, function()
			prompt("pass", Config.GAMEPASSES[name])
		end)
		table.insert(refreshers, function()
			local id = Config.GAMEPASSES[name] or 0
			if State.hasPass(name) then
				buy.set("owned")
			elseif id == 0 then
				buy.set("soon")
			else
				buy.set("price", priceCache["pass" .. id])
			end
		end)
	end

	local function refreshAll()
		for _, fn in refreshers do
			fn()
		end
	end
	refreshAll()

	-- Prices load lazily the first time the tab is shown.
	local fetched = false
	ctx.onSwitched(function(tab: string)
		if tab ~= "Robux" or fetched then
			return
		end
		fetched = true
		task.spawn(function()
			for _, id in Config.PRODUCTS do
				if id ~= 0 then
					fetchPrice("product", id)
				end
			end
			for _, id in Config.GAMEPASSES do
				if id ~= 0 then
					fetchPrice("pass", id)
				end
			end
			refreshAll()
		end)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, _, purchased)
		if purchased then
			ctx.toast("Thank you! Your pass is active", true)
			Sfx.purchase()
		end
	end)

	State.changed:Connect(function(attr: string)
		if string.sub(attr, 1, 4) == "Upg_" or string.sub(attr, 1, 5) == "Pass_" then
			refreshAll()
		end
	end)
end

return RobuxTab
