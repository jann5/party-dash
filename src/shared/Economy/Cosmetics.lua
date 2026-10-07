--!strict
-- Party Dash cosmetics catalog v2. Shared by the server (validation, rendering) and the shop UI.
--
-- Ids are stored in the profile (keep every id forever) and the equipped one is mirrored to Player Cos_<Slot>:
--   Trail      -> rendered by Economy on every character (server, Visuals.lua)
--   DashColor  -> read by Movement (Stats.parseDashColor): "Dash<ThemeColor>" / "DashRainbow"
--   BatColor   -> read by the bat (parseColor): "Bat<ThemeColor>" / "BatRainbow"
--   WinEffect  -> played by Economy on round winners (server)
--   BombSkin   -> read by Bomb Tag: Cosmetics.bombSkin(player:GetAttribute("Cos_BombSkin")) -> { color, material, accent }
-- "" always means the free default look.
--
-- Every item has a rarity and a source. Only source "coins" can be bought with coins (price by rarity); the rest
-- come from the VIP pass, Robux products, chests (reward) or the Wheel of Fortune. `icon` is a Shared.Assets key.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)

local C = Theme.Colors

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Limited"
export type Source = "coins" | "vip" | "robux" | "reward" | "wheel"
-- Particle dusting a trail adds on top of its ribbon (see Economy/Visuals.lua).
export type TrailFx = "sparkle" | "spark" | "bubble" | "ember" | "snow"

export type Item = {
	id: string,
	slot: string,
	name: string,
	rarity: Rarity,
	source: Source,
	price: number, -- coins; 0 unless source == "coins"
	color: Color3, -- main swatch color
	colors: { Color3 }?, -- gradient stops (trails); defaults to a light-to-main ramp of `color`
	rainbow: boolean?,
	vip: boolean?, -- unlocked by the VIP gamepass (same as source == "vip"; kept for older UI code)
	fx: TrailFx?,
	icon: string, -- Shared.Assets icon key
	order: number,
}

export type BombSkin = {
	id: string, -- "" for Classic, otherwise the cosmetic id (Cos_BombSkin value)
	name: string,
	rarity: Rarity?,
	color: Color3, -- bomb body
	material: Enum.Material,
	accent: Color3, -- cap / band / fuse holder
	rainbow: boolean?, -- renderers may cycle the body hue
}

local Cosmetics = {}

Cosmetics.SLOTS = { "Trail", "DashColor", "BatColor", "WinEffect", "BombSkin" }
Cosmetics.SLOT_INFO = {
	Trail = { title = "TRAILS", attr = "Cos_Trail", defaultName = "No Trail", icon = "trail_rainbow" },
	DashColor = { title = "DASH", attr = "Cos_DashColor", defaultName = "Classic Dash", icon = "action_dash" },
	BatColor = { title = "BAT", attr = "Cos_BatColor", defaultName = "Team Bat", icon = "bat" },
	WinEffect = { title = "WIN FX", attr = "Cos_WinEffect", defaultName = "Confetti Pop", icon = "party_popper" },
	BombSkin = { title = "BOMB", attr = "Cos_BombSkin", defaultName = "Classic Bomb", icon = "bomb" },
}

Cosmetics.RARITIES = { "Common", "Rare", "Epic", "Legendary", "Limited" } :: { Rarity }
Cosmetics.RARITY_PRICE = { Common = 300, Rare = 800, Epic = 2000, Legendary = 5000 }
Cosmetics.RARITY_COLOR = Theme.Rarity

Cosmetics.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 70)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
})

Cosmetics.GOLD = Color3.fromRGB(255, 200, 45)

local items: { Item } = {}
local byId: { [string]: Item } = {}

type Extra = {
	source: Source?,
	colors: { Color3 }?,
	rainbow: boolean?,
	fx: TrailFx?,
}

local function add(slot: string, id: string, name: string, rarity: Rarity, color: Color3, icon: string, extra: Extra?)
	assert(byId[id] == nil, "duplicate cosmetic id " .. id)
	local source: Source = (extra and extra.source) or "coins"
	local item: Item = {
		id = id,
		slot = slot,
		name = name,
		rarity = rarity,
		source = source,
		price = if source == "coins" then Cosmetics.RARITY_PRICE[rarity] or 0 else 0,
		color = color,
		colors = extra and extra.colors,
		rainbow = extra and extra.rainbow,
		vip = source == "vip" or nil,
		fx = extra and extra.fx,
		icon = icon,
		order = #items + 1,
	}
	table.insert(items, item)
	byId[id] = item
end

-- Trails ------------------------------------------------------------------------------------------
add("Trail", "TrailPink", "Bubblegum", "Common", C.Pink, "trail_hearts")
add("Trail", "TrailCyan", "Ice Blast", "Common", C.Cyan, "splash")
add("Trail", "TrailYellow", "Sunshine", "Common", C.Yellow, "trail_gold")
add("Trail", "TrailGreen", "Lime Zoom", "Rare", C.Lime, "speed_shoe")
add("Trail", "TrailPurple", "Grape Rush", "Rare", C.Purple, "potion")
add("Trail", "TrailRed", "Hot Sauce", "Rare", C.Red, "fire_streak")
add("Trail", "TrailRainbow", "Rainbow", "Epic", C.Yellow, "trail_rainbow", { rainbow = true, fx = "sparkle" })
add("Trail", "TrailVIP", "VIP Gold", "Legendary", Cosmetics.GOLD, "vip_badge", {
	source = "vip",
	colors = { Color3.fromRGB(255, 250, 200), Cosmetics.GOLD, Color3.fromRGB(230, 145, 20) },
	fx = "sparkle",
})
add("Trail", "TrailStarter", "Starter Spark", "Rare", Color3.fromRGB(255, 186, 40), "starter_pack", {
	source = "robux",
	colors = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 186, 40), C.Orange },
	fx = "spark",
})
add("Trail", "TrailGalaxy", "Galaxy Comet", "Limited", C.Purple, "trail_galaxy", {
	source = "robux",
	colors = { Color3.fromRGB(255, 120, 210), C.Purple, Color3.fromRGB(46, 40, 170), Color3.fromRGB(20, 18, 70) },
	fx = "sparkle",
})
-- Wheel of Fortune trails (2% each on the wheel; never sold).
add("Trail", "TrailLightning", "Lightning", "Epic", C.Yellow, "trail_lightning", {
	source = "wheel",
	colors = { Color3.fromRGB(255, 255, 230), C.Yellow, Color3.fromRGB(255, 170, 20) },
	fx = "spark",
})
add("Trail", "TrailBubbles", "Bubbles", "Epic", C.Cyan, "trail_bubbles", {
	source = "wheel",
	colors = { Color3.fromRGB(225, 250, 255), C.Cyan, C.Blue },
	fx = "bubble",
})
add("Trail", "TrailLava", "Lava", "Epic", C.Orange, "trail_fire", {
	source = "wheel",
	colors = { Color3.fromRGB(255, 220, 60), C.Orange, Color3.fromRGB(200, 30, 20) },
	fx = "ember",
})
add("Trail", "TrailSnowflake", "Snowflake", "Epic", Color3.fromRGB(170, 225, 255), "trail_ice", {
	source = "wheel",
	colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 225, 255), Color3.fromRGB(90, 170, 245) },
	fx = "snow",
})

-- Dash colors (ids parse in Movement's Stats.parseDashColor) --------------------------------------
add("DashColor", "DashPink", "Pink Pop", "Common", C.Pink, "action_dash")
add("DashColor", "DashYellow", "Lemon", "Common", C.Yellow, "action_dash")
add("DashColor", "DashGreen", "Slime", "Common", C.Green, "action_dash")
add("DashColor", "DashOrange", "Tangerine", "Rare", C.Orange, "action_dash")
add("DashColor", "DashPurple", "Galaxy", "Rare", C.Purple, "action_dash")
add("DashColor", "DashLaser", "Neon Laser", "Rare", C.Laser, "action_dash")
add("DashColor", "DashRainbow", "Rainbow", "Epic", C.Yellow, "action_dash", { rainbow = true })

-- Bat colors (ids parse in the bat's parseColor) ---------------------------------------------------
add("BatColor", "BatPink", "Pink Slugger", "Common", C.Pink, "bat")
add("BatColor", "BatCyan", "Frost Bat", "Common", C.Cyan, "bat")
add("BatColor", "BatGreen", "Swamp Bat", "Common", C.Green, "bat")
add("BatColor", "BatOrange", "Pumpkin", "Rare", C.Orange, "bat")
add("BatColor", "BatPurple", "Royal Bonk", "Rare", C.Purple, "bat")
add("BatColor", "BatRed", "Fire Bat", "Rare", C.Red, "bat")
add("BatColor", "BatRainbow", "Rainbow Bonk", "Epic", C.Yellow, "bat", { rainbow = true })

-- Win effects (played on top of Core's confetti when you win a round) ------------------------------
add("WinEffect", "WinConfetti", "Confetti Storm", "Rare", C.Pink, "party_popper")
add("WinEffect", "WinSparkles", "Star Sparkles", "Epic", C.Yellow, "win_star_sparkles")
add("WinEffect", "WinFireworks", "Fireworks", "Legendary", C.Purple, "win_fireworks")

-- Bomb skins (recolors + material swaps of the one Bomb Tag bomb) ----------------------------------
-- Cosmetic id == BombSkins key, so Cos_BombSkin indexes Cosmetics.BombSkins directly ("" = Classic).
Cosmetics.BombSkins = {
	Classic = {
		id = "",
		name = "Classic Bomb",
		color = Color3.fromRGB(34, 32, 44),
		material = Enum.Material.SmoothPlastic,
		accent = C.Yellow,
	},
	Watermelon = {
		id = "Watermelon",
		name = "Watermelon",
		rarity = "Common",
		color = Color3.fromRGB(62, 176, 62),
		material = Enum.Material.SmoothPlastic,
		accent = C.Red,
	},
	Disco = {
		id = "Disco",
		name = "Disco Ball",
		rarity = "Rare",
		color = Color3.fromRGB(205, 210, 230),
		material = Enum.Material.Foil,
		accent = C.Pink,
	},
	Pumpkin = {
		id = "Pumpkin",
		name = "Pumpkin",
		rarity = "Rare",
		color = C.Orange,
		material = Enum.Material.SmoothPlastic,
		accent = Color3.fromRGB(62, 150, 48),
	},
	GiftBox = {
		id = "GiftBox",
		name = "Gift Box",
		rarity = "Epic",
		color = C.Blue,
		material = Enum.Material.SmoothPlastic,
		accent = C.Gold,
	},
	Rainbow = {
		id = "Rainbow",
		name = "Rainbow",
		rarity = "Legendary",
		color = C.Pink,
		material = Enum.Material.SmoothPlastic,
		accent = C.Cyan,
		rainbow = true,
	},
	GoldenBomb = {
		id = "GoldenBomb",
		name = "Golden Bomb",
		rarity = "Legendary",
		color = C.Gold,
		material = Enum.Material.Foil,
		accent = Color3.fromRGB(255, 244, 190),
	},
} :: { [string]: BombSkin }

-- Shop order of the sellable / winnable skins (Classic is the free default, "" in the slot).
Cosmetics.BOMB_SKIN_ORDER = { "Watermelon", "Disco", "Pumpkin", "GiftBox", "Rainbow", "GoldenBomb" }
for _, key in Cosmetics.BOMB_SKIN_ORDER do
	local skin = Cosmetics.BombSkins[key]
	add(
		"BombSkin",
		key,
		skin.name,
		skin.rarity :: Rarity,
		skin.color,
		"bomb",
		{ source = if key == "GoldenBomb" then "wheel" else "coins", rainbow = skin.rainbow }
	)
end

-- Lookups -------------------------------------------------------------------------------------------

function Cosmetics.get(id: any): Item?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- Items of one slot in shop order.
function Cosmetics.list(slot: string): { Item }
	local out = {}
	for _, item in items do
		if item.slot == slot then
			table.insert(out, item)
		end
	end
	return out
end

function Cosmetics.all(): { Item }
	return table.clone(items)
end

function Cosmetics.isSlot(slot: any): boolean
	return type(slot) == "string" and Cosmetics.SLOT_INFO[slot] ~= nil
end

-- Coin-shop items of one rarity (the pool chests draw from).
function Cosmetics.pool(rarity: Rarity): { Item }
	local out = {}
	for _, item in items do
		if item.rarity == rarity and item.source == "coins" then
			table.insert(out, item)
		end
	end
	return out
end

-- Coins paid instead when a reward hands out an item the player already owns.
function Cosmetics.dupCoins(item: Item): number
	if item.price > 0 then
		return item.price
	end
	return Cosmetics.RARITY_PRICE[item.rarity] or 1500
end

-- Render data for a Cos_BombSkin value (anything unknown or "" = Classic).
function Cosmetics.bombSkin(id: any): BombSkin
	return (type(id) == "string" and Cosmetics.BombSkins[id]) or Cosmetics.BombSkins.Classic
end

-- Color sequence used for trails / previews.
function Cosmetics.sequence(item: Item): ColorSequence
	if item.rainbow then
		return Cosmetics.RAINBOW
	end
	local colors = item.colors
	if colors and #colors >= 2 then
		local points = {}
		for i, color in colors do
			table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
		end
		return ColorSequence.new(points)
	end
	return ColorSequence.new(item.color:Lerp(Color3.new(1, 1, 1), 0.35), item.color)
end

return Cosmetics
