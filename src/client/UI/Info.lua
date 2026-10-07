--!nonstrict
-- HUD metadata: minigame / modifier cards from ReplicatedStorage.MinigameInfo / ModifierInfo (with sane
-- fallbacks, so a card is never blank), control hints, player names / headshots, parsers and a text sanitizer.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Info = {}

export type Card = {
	id: string,
	name: string, -- display name, upper case
	rules: string, -- one rule line (minigame) or description (modifier)
	icon: string, -- Shared.Assets icon key
	color: Color3, -- card accent
	keys: { string }, -- control hints ("Jump", "Slide", ...)
	minPlayers: number,
}

local FALLBACK_COLORS = {
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Orange,
	Theme.Colors.Purple,
	Theme.Colors.Green,
	Theme.Colors.Blue,
}

local function hashColor(id: string): Color3
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 100003
	end
	return FALLBACK_COLORS[(h % #FALLBACK_COLORS) + 1]
end

-- Typographic punctuation some writers use, mapped to plain ASCII before the sanitizer runs.
local PUNCTUATION = {
	[0x2018] = "'",
	[0x2019] = "'",
	[0x201C] = '"',
	[0x201D] = '"',
	[0x2013] = "-",
	[0x2014] = "-",
	[0x2026] = "...",
	[0x00A0] = " ",
}

local function dropped(cp: number): boolean
	if cp == 0xE002 then
		return false -- the Robux glyph
	end
	return (cp >= 0x2000 and cp <= 0x2BFF) -- symbols, arrows, dingbats
		or (cp >= 0xE000 and cp <= 0xF8FF) -- private use
		or (cp >= 0xFE00 and cp <= 0xFE0F) -- emoji variation selectors
		or cp >= 0x1F000 -- emoji planes
end

-- Strips emoji and pictographs from text written by other systems (the HUD never shows emoji; images carry
-- the meaning). Letters of every script are kept.
function Info.clean(text: any): string
	if typeof(text) ~= "string" then
		return ""
	end
	if not text:find("[\128-\255]") then
		return text
	end
	local ok, out = pcall(function()
		local parts = {}
		for _, cp in utf8.codes(text) do
			local swap = PUNCTUATION[cp]
			if swap then
				table.insert(parts, swap)
			elseif not dropped(cp) then
				table.insert(parts, utf8.char(cp))
			end
		end
		return table.concat(parts)
	end)
	if not ok then
		out = text:gsub("[\128-\255]", "")
	end
	out = out:gsub("%s+", " "):match("^%s*(.-)%s*$")
	return out
end

-- "HoleInTheWall" -> "HOLE IN THE WALL"
function Info.prettify(id: string): string
	local spaced = id:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
	return string.upper(spaced)
end

function Info.csv(value: any): { string }
	local out = {}
	if typeof(value) ~= "string" then
		return out
	end
	for _, part in string.split(value, ",") do
		local trimmed = part:match("^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	return out
end

function Info.json(value: any): { [any]: any }?
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, value)
	return ok and typeof(t) == "table" and t or nil
end

-- First key that has an uploaded image.
local function firstIcon(...: any): string
	for _, key in { ... } do
		if typeof(key) == "string" and key ~= "" and Assets.icon(key) ~= "" then
			return key
		end
	end
	return "mg_random"
end

local function reader(folderName: string, id: string): (string) -> any
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	local cfg = folder and folder:FindFirstChild(id)
	return function(key: string): any
		return cfg and cfg:GetAttribute(key)
	end
end

local function str(v: any, fallback: string): string
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	return fallback
end

function Info.minigame(id: string): Card
	local get = reader("MinigameInfo", id)
	local color = get("Color")
	local minPlayers = get("MinPlayers")
	return {
		id = id,
		name = string.upper(Info.clean(str(get("DisplayName"), Info.prettify(id)))),
		rules = Info.clean(str(get("Rules"), "Be the last one standing!")),
		icon = firstIcon(get("Icon"), "mg_" .. string.lower(id), "mg_random"),
		color = typeof(color) == "Color3" and color or Theme.MinigameColors[id] or hashColor(id),
		keys = Info.csv(get("Keys")),
		minPlayers = typeof(minPlayers) == "number" and minPlayers or 1,
	}
end

function Info.modifier(id: string): Card
	local get = reader("ModifierInfo", id)
	local color = get("Color")
	local snake = id:gsub("(%l)(%u)", "%1_%2"):lower()
	return {
		id = id,
		name = string.upper(Info.clean(str(get("DisplayName"), Info.prettify(id)))),
		rules = Info.clean(str(get("Description"), "")),
		icon = firstIcon(get("Icon"), "mod_" .. snake, "lightning"),
		color = typeof(color) == "Color3" and color or hashColor(id),
		keys = {},
		minPlayers = 1,
	}
end

-- Ids published in an info folder (fallback reel when Core sent none).
function Info.knownIds(folderName: string): { string }
	local ids = {}
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			if string.sub(child.Name, 1, 1) ~= "_" and child:GetAttribute("Hidden") ~= true then
				table.insert(ids, child.Name)
			end
		end
	end
	table.sort(ids)
	return ids
end

-- Control hints: the PC key and the touch button icon for each action a minigame lists in Keys.
Info.KEYS = {
	Jump = { key = "SPACE", verb = "Jump", icon = "arrow_jump" },
	Slide = { key = "C", verb = "Slide", icon = "action_slide" },
	Dash = { key = "SHIFT", verb = "Dash", icon = "action_dash" },
	Swing = { key = "CLICK", verb = "Swing", icon = "action_swing" },
	Throw = { key = "CLICK", verb = "Throw", icon = "action_throw" },
}

function Info.keyHint(action: string): { key: string, verb: string, icon: string }
	return Info.KEYS[action] or { key = string.upper(action), verb = action, icon = "lightning" }
end

-- Touch layout when the last input was a touch (or the device has no keyboard).
function Info.isTouch(): boolean
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return true
	end
	if
		last == Enum.UserInputType.Keyboard
		or last == Enum.UserInputType.MouseButton1
		or last == Enum.UserInputType.MouseMovement
	then
		return false
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Player names: DisplayName for players in the server, an async lookup (cached) for players who left.
local nameCache: { [number]: string } = {}

function Info.name(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		nameCache[userId] = p.DisplayName
		return p.DisplayName
	end
	return nameCache[userId] or "Player"
end

-- Sets label.Text to the player's name now and again once a slow lookup resolves.
function Info.nameInto(label: TextLabel, userId: number)
	label.Text = Info.name(userId)
	if Players:GetPlayerByUserId(userId) or nameCache[userId] or userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		if ok and typeof(name) == "string" then
			nameCache[userId] = name
			if label.Parent then
				label.Text = name
			end
		end
	end)
end

-- Remember names of players leaving mid-round (for the podium).
Players.PlayerRemoving:Connect(function(p)
	nameCache[p.UserId] = p.DisplayName
end)

-- Avatar headshot url (nil for test / guest ids, which have no thumbnail).
function Info.headshot(userId: number): string?
	if typeof(userId) ~= "number" or userId <= 0 then
		return nil
	end
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(math.floor(userId))
end

function Info.hex(value: any): Color3?
	if typeof(value) ~= "string" or #value < 6 or #value > 9 then
		return nil
	end
	local ok, c = pcall(Color3.fromHex, value)
	return ok and c or nil
end

return Info
