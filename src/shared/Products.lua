-- Party Dash: the Robux catalog (display data). FROZEN CONTRACT v2 (lead-owned).
-- Ids live in Config.PRODUCTS / Config.GAMEPASSES (0 = not created yet). This table is the single source for
-- what every Robux button shows: title, price (the price to create the product at in Creator Hub, shown while
-- the id is 0; once an id is set the UI may show the live price from MarketplaceService instead), icon and badge.
-- What a product GRANTS is implemented by Economy (src/server/Economy) keyed by the same names.
--
--   local Products = require(ReplicatedStorage.Shared.Products)
--   Products.INFO.WheelSpin1.price  --> 9
--   Products.id("Revive")            --> number (0 if not configured)
--   Products.kind("VIP")             --> "gamepass"
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Products = {}

export type Info = {
	title: string,
	price: number, -- Robux
	wasPrice: number?, -- shown struck through (only where that price is real elsewhere, see GalaxyTrail)
	badge: string?, -- small ribbon text ("BEST VALUE", "SAVE 13%", "ONE-TIME")
	icon: string, -- Shared.Assets icon key
	kind: "product" | "gamepass",
	oneTime: boolean?, -- can only ever be bought once per account
	paidRandom: boolean?, -- a paid random item: odds must be shown before purchase (ODDS button), hidden when
	-- PolicyService says ArePaidRandomItemsRestricted
	desc: string,
}

Products.INFO = {
	-- brief #29 wheel of fortune
	WheelSpin1 = {
		title = "1 Spin",
		price = 9,
		icon = "wheel",
		kind = "product",
		paidRandom = true,
		desc = "Spin the Wheel of Fortune once.",
	},
	WheelSpin5 = {
		title = "5 Spins",
		price = 39,
		badge = "SAVE 13%",
		icon = "wheel",
		kind = "product",
		paidRandom = true,
		desc = "Five spins of the Wheel of Fortune.",
	},
	-- brief #28
	Revive = {
		title = "Revive",
		price = 19,
		icon = "revive_heart",
		kind = "product",
		desc = "Jump back into the round right where the action is!",
	},
	-- brief #30
	StarterPack = {
		title = "Starter Pack",
		price = 49,
		badge = "ONE-TIME",
		icon = "starter_pack",
		kind = "product",
		oneTime = true,
		desc = "1,000 coins + Starter Spark trail + 2x coins for 30 min.",
	},
	-- brief #31: the Galaxy Comet trail really costs 199 R$ all Season 1; each player's first 48 h it is 19 R$.
	GalaxyTrail19 = {
		title = "Galaxy Comet",
		price = 19,
		wasPrice = 199,
		badge = "LIMITED",
		icon = "trail_galaxy",
		kind = "product",
		oneTime = true,
		desc = "Limited trail. Welcome deal: 90% off for your first 48 hours!",
	},
	GalaxyTrail199 = {
		title = "Galaxy Comet",
		price = 199,
		badge = "LIMITED",
		icon = "trail_galaxy",
		kind = "product",
		oneTime = true,
		desc = "Limited Season 1 trail.",
	},
	Coins500 = { title = "500 Coins", price = 25, icon = "coin_stack", kind = "product", desc = "A handful of coins." },
	Coins1500 = {
		title = "1,500 Coins",
		price = 65,
		badge = "+15%",
		icon = "coin_sack",
		kind = "product",
		desc = "A bag of coins.",
	},
	Coins5000 = {
		title = "5,000 Coins",
		price = 179,
		badge = "BEST VALUE",
		icon = "coin_chest",
		kind = "product",
		desc = "A chest full of coins.",
	},
	UpgradeDashCooldown = {
		title = "Dash Cooldown +1",
		price = 25,
		icon = "hourglass",
		kind = "product",
		desc = "Next Dash Cooldown level.",
	},
	UpgradeDashDistance = {
		title = "Dash Distance +1",
		price = 25,
		icon = "speed_shoe",
		kind = "product",
		desc = "Next Dash Distance level.",
	},
	UpgradeBatPower = {
		title = "Bat Power +1",
		price = 25,
		icon = "bat",
		kind = "product",
		desc = "Next Bat Power level.",
	},
	UpgradeJumpBoost = {
		title = "Jump Boost +1",
		price = 25,
		icon = "spring",
		kind = "product",
		desc = "Next Jump Boost level.",
	},
	DoubleCoins = {
		title = "2X Coins",
		price = 149,
		icon = "coins_x2",
		kind = "gamepass",
		desc = "Double coins from every round, forever.",
	},
	VIP = {
		title = "VIP",
		price = 249,
		icon = "vip_ticket",
		kind = "gamepass",
		desc = "Gold name tag, VIP Gold trail, +20% coins, +1 free spin a day.",
	},
}

function Products.kind(key: string): string?
	local info = Products.INFO[key]
	return info and info.kind or nil
end

-- The configured Roblox id (developer product or gamepass), 0 when not created yet.
function Products.id(key: string): number
	local info = Products.INFO[key]
	if info and info.kind == "gamepass" then
		return Config.GAMEPASSES[key] or 0
	end
	return Config.PRODUCTS[key] or 0
end

function Products.isConfigured(key: string): boolean
	return Products.id(key) ~= 0
end

-- Reverse lookup for ProcessReceipt: developer product id -> key (nil if unknown).
function Products.keyForProductId(productId: number): string?
	for key, id in Config.PRODUCTS do
		if id ~= 0 and id == productId then
			return key
		end
	end
	return nil
end

return Products
