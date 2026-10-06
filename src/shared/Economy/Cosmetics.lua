--!strict
-- Party Dash cosmetics catalog (coin prices). Shared by the server (validation, rendering) and the shop UI.
--
-- Ids are stored in the profile and mirrored to Player attributes Cos_<Slot>:
--   Trail      -> rendered by Economy on every character (server)
--   DashColor  -> read by Movement (Stats.parseDashColor): "Dash<ThemeColor>" / "DashRainbow"
--   BatColor   -> read by King of the Hill (BatTool.parseColor): "Bat<ThemeColor>" / "BatRainbow"
--   WinEffect  -> played by Economy on round winners (server)
-- "" always means the free default look.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.Theme)

local C = Theme.Colors

export type Item = {
	id: string,
	slot: string,
	name: string,
	price: number,
	color: Color3, -- main swatch color
	rainbow: boolean?,
	vip: boolean?, -- unlocked by the VIP gamepass instead of coins
	icon: string?, -- win effects: emoji shown on the card
	order: number,
}

local Cosmetics = {}

Cosmetics.SLOTS = { "Trail", "DashColor", "BatColor", "WinEffect" }
Cosmetics.SLOT_INFO = {
	Trail = { title = "TRAILS", attr = "Cos_Trail", defaultName = "No Trail" },
	DashColor = { title = "DASH", attr = "Cos_DashColor", defaultName = "Classic Dash" },
	BatColor = { title = "BAT", attr = "Cos_BatColor", defaultName = "Team Bat" },
	WinEffect = { title = "WIN FX", attr = "Cos_WinEffect", defaultName = "Confetti Pop" },
}

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

local function add(slot: string, id: string, name: string, price: number, color: Color3, extra: { [string]: any }?)
	local item: Item = {
		id = id,
		slot = slot,
		name = name,
		price = price,
		color = color,
		order = #items + 1,
	}
	if extra then
		for k, v in extra do
			(item :: any)[k] = v
		end
	end
	table.insert(items, item)
	byId[id] = item
end

-- Trails: 6 colors + rainbow + VIP gold.
add("Trail", "TrailPink", "Bubblegum", 150, C.Pink)
add("Trail", "TrailCyan", "Ice Blast", 150, C.Cyan)
add("Trail", "TrailYellow", "Sunshine", 150, C.Yellow)
add("Trail", "TrailGreen", "Lime Zoom", 200, C.Green)
add("Trail", "TrailPurple", "Grape Rush", 200, C.Purple)
add("Trail", "TrailRed", "Hot Sauce", 250, C.Red)
add("Trail", "TrailRainbow", "Rainbow", 750, C.Yellow, { rainbow = true })
add("Trail", "TrailVIP", "VIP Gold", 0, Cosmetics.GOLD, { vip = true })

-- Dash colors (ids parse in Movement's Stats.parseDashColor).
add("DashColor", "DashPink", "Pink Pop", 150, C.Pink)
add("DashColor", "DashYellow", "Lemon", 150, C.Yellow)
add("DashColor", "DashGreen", "Slime", 150, C.Green)
add("DashColor", "DashOrange", "Tangerine", 200, C.Orange)
add("DashColor", "DashPurple", "Galaxy", 200, C.Purple)
add("DashColor", "DashLaser", "Neon Laser", 300, C.Laser)
add("DashColor", "DashRainbow", "Rainbow", 600, C.Yellow, { rainbow = true })

-- Bat colors (ids parse in King of the Hill's BatTool.parseColor).
add("BatColor", "BatPink", "Pink Slugger", 120, C.Pink)
add("BatColor", "BatCyan", "Frost Bat", 120, C.Cyan)
add("BatColor", "BatGreen", "Swamp Bat", 120, C.Green)
add("BatColor", "BatOrange", "Pumpkin", 180, C.Orange)
add("BatColor", "BatPurple", "Royal Bonk", 180, C.Purple)
add("BatColor", "BatRed", "Fire Bat", 240, C.Red)
add("BatColor", "BatRainbow", "Rainbow Bonk", 600, C.Yellow, { rainbow = true })

-- Win effects (played on top of Core's confetti when you win a round).
add("WinEffect", "WinConfetti", "Confetti Storm", 300, C.Pink, { icon = "🎉" })
add("WinEffect", "WinSparkles", "Star Sparkles", 400, C.Yellow, { icon = "✨" })
add("WinEffect", "WinFireworks", "Fireworks", 500, C.Purple, { icon = "🎆" })

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

-- Color sequence used for trails / previews.
function Cosmetics.sequence(item: Item): ColorSequence
	if item.rainbow then
		return Cosmetics.RAINBOW
	end
	if item.vip then
		return ColorSequence.new(Color3.fromRGB(255, 250, 200), Cosmetics.GOLD)
	end
	return ColorSequence.new(item.color:Lerp(Color3.new(1, 1, 1), 0.35), item.color)
end

return Cosmetics
