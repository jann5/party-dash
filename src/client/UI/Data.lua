-- Party Dash UI data helpers: minigame/modifier metadata, key hints, player names, input mode.
-- Reads ReplicatedStorage.MinigameInfo / ModifierInfo (written by Core) and always has a sane fallback,
-- so the HUD never shows a blank card even when metadata is missing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage.Shared.Theme)

local Data = {}

export type CardInfo = {
	id: string,
	name: string, -- display name, upper case
	text: string, -- rules (minigame) or description (modifier)
	icon: string,
	color: Color3,
	keys: { string },
	kind: string,
}

-- Only long-supported emoji (Unicode 6 era or older): newer ones (e.g. the coin) render as nothing.
local MINIGAME_ICONS = {
	LaserTracer = "⚡",
	Dodgeball = "⚽",
	KingOfTheHill = "👑",
	HoleInTheWall = "🚧",
	Spin = "🌀",
}

local MODIFIER_ICONS = {
	LowGravity = "🎈",
	Turbo = "🚀",
	Fog = "☁",
	Giant = "🐘",
	Tiny = "🐭",
	Slippery = "❄",
	Ice = "❄",
	Night = "🌙",
	Darkness = "🌙",
	Wind = "🍃",
	SpeedUp = "💨",
	DoubleJump = "🐸",
	Bouncy = "🏀",
}

-- Fallback accents for modifiers / unknown minigames (deterministic per id).
local FALLBACK_COLORS = {
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Green,
	Theme.Colors.Purple,
	Theme.Colors.Orange,
	Theme.Colors.Blue,
	Theme.Colors.Yellow,
}

local function hashColor(id: string): Color3
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 100003
	end
	return FALLBACK_COLORS[(h % #FALLBACK_COLORS) + 1]
end

-- "KingOfTheHill" -> "KING OF THE HILL"
function Data.prettify(id: string): string
	local spaced = id:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
	return string.upper(spaced)
end

function Data.csv(value: any): { string }
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

local function str(v: any, fallback: string): string
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	return fallback
end

local function infoFolder(name: string, id: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(name)
	return folder and folder:FindFirstChild(id) or nil
end

function Data.minigame(id: string): CardInfo
	local cfg = infoFolder("MinigameInfo", id)
	local attr = function(key: string): any
		return cfg and cfg:GetAttribute(key)
	end
	local color = attr("Color")
	return {
		id = id,
		name = string.upper(str(attr("DisplayName"), Data.prettify(id))),
		text = str(attr("Rules"), "Be the last one standing!"),
		icon = str(attr("Icon"), MINIGAME_ICONS[id] or "🎲"),
		color = typeof(color) == "Color3" and color or Theme.MinigameColors[id] or hashColor(id),
		keys = Data.csv(attr("Keys")),
		kind = str(attr("Kind"), ""),
	}
end

function Data.modifier(id: string): CardInfo
	local cfg = infoFolder("ModifierInfo", id)
	local attr = function(key: string): any
		return cfg and cfg:GetAttribute(key)
	end
	local color = attr("Color")
	return {
		id = id,
		name = string.upper(str(attr("DisplayName"), Data.prettify(id))),
		text = str(attr("Description"), "Something wild is about to happen!"),
		icon = str(attr("Icon"), MODIFIER_ICONS[id] or "✨"),
		color = typeof(color) == "Color3" and color or hashColor(id),
		keys = {},
		kind = "",
	}
end

-- Every known id in an info folder (used when a reel CSV is missing).
function Data.knownIds(folderName: string): { string }
	local ids = {}
	local folder = ReplicatedStorage:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			if string.sub(child.Name, 1, 1) ~= "_" then
				table.insert(ids, child.Name)
			end
		end
	end
	if #ids == 0 and folderName == "MinigameInfo" then
		for id in Theme.MinigameColors do
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Input mode ------------------------------------------------------------------------------------
function Data.isTouch(): boolean
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

-- Key hint for an action: PC shows the key, touch shows the on-screen button name.
local KEYS = {
	Jump = { key = "SPACE", button = "JUMP", verb = "JUMP" },
	Slide = { key = "C", button = "SLIDE", verb = "SLIDE" },
	Dash = { key = "SHIFT", button = "DASH", verb = "DASH" },
	Swing = { key = "CLICK", button = "SWING", verb = "SWING" },
	Throw = { key = "CLICK", button = "THROW", verb = "THROW" },
}

function Data.keyHint(action: string): (string?, string?)
	local k = KEYS[action]
	if not k then
		return nil, nil
	end
	if Data.isTouch() then
		return k.button, "TAP"
	end
	return k.key, k.verb
end

-- Player names (works for players who already left, resolved asynchronously) -------------------
local nameCache: { [number]: string } = {}
local pending: { [number]: boolean } = {}
local nameResolved = Instance.new("BindableEvent")
Data.NameResolved = nameResolved.Event

function Data.playerName(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return p.DisplayName
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	if not pending[userId] and userId > 0 then
		pending[userId] = true
		task.spawn(function()
			local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			if ok and typeof(name) == "string" then
				nameCache[userId] = name
				nameResolved:Fire(userId)
			end
		end)
	end
	return "Player"
end

-- Sorted { {userId, score} } from GameState.scores(), highest first.
function Data.rankScores(scores: { [string]: any }): { { userId: number, score: number } }
	local list = {}
	for key, value in scores do
		local uid = tonumber(key)
		local score = tonumber(value)
		if uid and score then
			table.insert(list, { userId = uid, score = score })
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.userId < b.userId
	end)
	return list
end

function Data.formatScore(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.1f", n)
end

function Data.parseHex(hex: any): Color3?
	if typeof(hex) ~= "string" or #hex > 9 then
		return nil
	end
	local ok, c = pcall(Color3.fromHex, hex)
	return ok and c or nil
end

-- "m:ss" for long timers, plain seconds below a minute.
function Data.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 60 then
		return string.format("%d:%02d", s // 60, s % 60)
	end
	return tostring(s)
end

-- Avatar headshot (no yielding); nil for test/guest ids.
function Data.headshot(userId: number): string?
	if userId <= 0 then
		return nil
	end
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

return Data
