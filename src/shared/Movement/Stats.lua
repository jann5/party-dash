-- Party Dash movement math, shared by the server (validation) and the client (motion + HUD).
-- Every value is derived from Config plus the player's live upgrade attributes (missing = level 0).
--
-- Cos_DashColor (Player attribute, set by Economy) accepts any of:
--   "#FF5FA0" / "FF5FA0"        a hex color
--   "Pink", "dash_pink", "DashPink"  a Theme.Colors key (case-insensitive, optional "dash" prefix)
--   "Really red"                 a BrickColor name
--   "Rainbow"                    a rainbow gradient
--   "" or missing                the default cyan/white dash trail
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Stats = {}

-- Remote names (Net.event) and ContextActionService action names.
Stats.Remote = {
	Dash = "Movement_Dash",
	Slide = "Movement_Slide",
	JumpFx = "Movement_JumpFx",
}
Stats.Action = {
	Dash = "PartyDash_Dash",
	Slide = "PartyDash_Slide",
}

-- The server forgives this much latency jitter when checking cooldowns.
Stats.DASH_TOLERANCE = 0.3
Stats.SLIDE_TOLERANCE = 0.15

Stats.RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 70)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
})

local DEFAULT_DASH = Theme.Colors.Cyan

-- Upgrade level 0..UPGRADE_MAX_LEVEL read live from the Player attribute "Upg_<name>".
function Stats.upgradeLevel(player: Player, name: string): number
	local value = player:GetAttribute("Upg_" .. name)
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, Config.UPGRADE_MAX_LEVEL)
end

local function multiplier(player: Player, name: string): number
	local def = Config.UPGRADES[name]
	local perLevel = def and def.perLevel or 0
	return 1 + Stats.upgradeLevel(player, name) * perLevel
end

function Stats.dashCooldown(player: Player): number
	return Config.DASH_COOLDOWN * math.max(0.2, multiplier(player, "DashCooldown"))
end

function Stats.dashDistance(player: Player): number
	return Config.DASH_DISTANCE * math.max(0.2, multiplier(player, "DashDistance"))
end

function Stats.jumpPower(player: Player): number
	return Config.JUMP_POWER * math.max(0.2, multiplier(player, "JumpBoost"))
end

-- Seconds between the END of one slide and the start of the next.
function Stats.slideCooldown(): number
	return Config.SLIDE_COOLDOWN
end

local function namedColor(raw: string): Color3?
	local key = string.lower(raw):gsub("[%s_%-]", "")
	if string.sub(key, 1, 4) == "dash" and #key > 4 then
		key = string.sub(key, 5)
	end
	for name, color in Theme.Colors do
		if string.lower(name) == key then
			return color
		end
	end
	return nil
end

-- Parses a Cos_DashColor value. Returns (sequence, mainColor).
function Stats.parseDashColor(raw: any): (ColorSequence, Color3)
	if type(raw) ~= "string" or raw == "" then
		return ColorSequence.new(Theme.Colors.White, DEFAULT_DASH), DEFAULT_DASH
	end
	if string.lower(raw) == "rainbow" or string.lower(raw) == "dashrainbow" then
		return Stats.RAINBOW, Color3.fromRGB(255, 240, 70)
	end
	local hex = string.match(raw, "^#?(%x%x%x%x%x%x)$")
	if hex then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return ColorSequence.new(Theme.Colors.White, color), color
		end
	end
	local named = namedColor(raw)
	if named then
		return ColorSequence.new(Theme.Colors.White, named), named
	end
	local brick = BrickColor.new(raw :: any)
	if brick.Name == raw then
		return ColorSequence.new(Theme.Colors.White, brick.Color), brick.Color
	end
	return ColorSequence.new(Theme.Colors.White, DEFAULT_DASH), DEFAULT_DASH
end

function Stats.dashColor(player: Player?): (ColorSequence, Color3)
	return Stats.parseDashColor(player and player:GetAttribute("Cos_DashColor"))
end

return Stats
