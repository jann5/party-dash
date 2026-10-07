--!nonstrict
-- Kill feed (UIKit.Lanes "Feed", top-right). KO lines are drawn "Alex [icon] Sam" with the round's hit icon
-- (bat / bomb / hit star), other lines get a keyword icon. At most MAX lines; each fades after LIFE seconds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Info = require(script.Parent.Info)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Feed = {}

local MAX = 4
local LIFE = 5
local HEIGHT = 46
local TEXT = 26

-- "A <verb> B" lines that credit a knock-out.
local KO_VERBS = { "knocked out", "bonked", "blew up", "tagged", "eliminated", "splashed", "smacked", "launched" }

-- Hit icon per minigame for KO lines.
local HIT_ICON = { Spin = "bat", BombTag = "bomb", Dodgeball = "hit_star", LaserTracer = "hit_star" }

-- Keyword icons for every other line (first match wins).
local KEYWORD_ICONS = {
	{ "fell", "splash" },
	{ "splash", "splash" },
	{ "water", "splash" },
	{ "explod", "explosion" },
	{ "boom", "explosion" },
	{ "bomb", "bomb" },
	{ "revive", "revive_heart" },
	{ "is back", "revive_heart" },
	{ "streak", "fire_streak" },
	{ "mvp", "medal" },
	{ "win", "trophy" },
	{ "out", "skull_out" },
}

local counter = 0

local function lineIcon(lower: string): string?
	for _, pair in KEYWORD_ICONS do
		if string.find(lower, pair[1], 1, true) then
			return pair[2]
		end
	end
	return nil
end

-- Splits "A knocked out B" / "A [bat] B" into (attacker, iconKey, victim) or nil.
local function parseKO(text: string): (string?, string?, string?)
	local a, key, b = text:match("^(.-)%s*%[([%w_]+)%]%s*(.+)$")
	if a and a ~= "" and Assets.icon(key) ~= "" then
		return a, key, b
	end
	local hit = HIT_ICON[State.str("MinigameId")] or "hit_star"
	local victimFirst, byName = text:match("^(.-) got [%a ]- by (.+)$") -- "Sam got knocked out by Alex"
	if victimFirst and victimFirst ~= "" then
		return (byName:gsub("[!%.]+$", "")), hit, victimFirst
	end
	local lower = string.lower(text)
	for _, verb in KO_VERBS do
		local s, e = string.find(lower, " " .. verb .. " ", 1, true)
		if s then
			local attacker = text:sub(1, s - 1)
			local victim = text:sub(e + 1):gsub("[!%.]+$", "")
			if attacker ~= "" and victim ~= "" then
				return attacker, verb == "blew up" and "bomb" or hit, victim
			end
		end
	end
	return nil
end

local function isMe(name: string): boolean
	local me = Players.LocalPlayer
	return name == me.DisplayName or name == me.Name
end

local function label(parent: Instance, text: string, color: Color3, order: number)
	local l = UIKit.text(parent, {
		text = text,
		size = TEXT,
		color = color,
		frameSize = UDim2.fromOffset(0, HEIGHT - 8),
		autoSize = Enum.AutomaticSize.X,
		zindex = 6,
	})
	l.LayoutOrder = order
	return l
end

local function icon(parent: Instance, key: string, order: number)
	-- list children: a centre anchor would shift the icon inside the UIListLayout
	local img =
		UIKit.icon(parent, key, { size = UDim2.fromOffset(HEIGHT - 4, HEIGHT - 4), anchor = Vector2.zero, zindex = 7 })
	img.LayoutOrder = order
	return img
end

function Feed.push(raw: string)
	local text = Info.clean(raw)
	if text == "" then
		return
	end
	local lane = UIKit.Lanes.get("Feed")
	-- keep at most MAX lines: drop the oldest
	local lines = {}
	for _, child in lane:GetChildren() do
		if child.Name == "FeedLine" then
			table.insert(lines, child)
		end
	end
	table.sort(lines, function(x, y)
		return x.LayoutOrder < y.LayoutOrder
	end)
	while #lines >= MAX do
		table.remove(lines, 1):Destroy()
	end

	counter += 1
	local line = UIKit.new("Frame", {
		Name = "FeedLine",
		BackgroundColor3 = C.PanelDeep,
		BackgroundTransparency = 0.12,
		Size = UDim2.fromOffset(0, HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = counter,
		ZIndex = 5,
	})
	line:SetAttribute("Text", text)
	UIKit.corner(line, UDim.new(0.5, 0))
	UIKit.border(line, 2.5)
	UIKit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 18),
		Parent = line,
	})
	UIKit.list(line, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

	local attacker, hitIcon, victim = parseKO(text)
	if attacker then
		label(line, attacker, isMe(attacker) and C.Green or C.Yellow, 1)
		icon(line, hitIcon, 2)
		label(line, victim, isMe(victim) and C.Red or C.White, 3)
	else
		local key = lineIcon(string.lower(text))
		if key then
			icon(line, key, 1)
		end
		label(line, text, C.White, 2)
	end
	line.Parent = lane
	UIKit.pop(line, 0.5, 0.25)
	task.delay(LIFE, function()
		if line.Parent then
			Widgets.fadeOut(line, 0.3)
			task.wait(0.32)
			line:Destroy()
		end
	end)
end

return Feed
