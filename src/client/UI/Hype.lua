--!nonstrict
-- Hype words: huge LuckiestGuy text with an ink drop in the upper middle of the screen. Used by Core_Announce
-- "big" and by the round countdown (3-2-1-GO! for round members). Strictly transient: a word lives LIFE seconds,
-- so no banner ever parks over the play area (rule: nothing mid-screen longer than 1.5 s during a round).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Confetti = require(script.Parent.Confetti)
local Info = require(script.Parent.Info)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Hype = {}

local LIFE = 1.2 -- seconds a word stays (pop + hold + exit)
local DEDUPE = 0.8 -- the countdown and Core may announce the same word; show it once

local gui: ScreenGui? = nil
local root: Frame? = nil
local current: Frame? = nil
local currentKey = ""
local shownAt = 0
local serial = 0

-- "Go!" and "GO" are the same word.
function Hype.key(text: string): string
	return (string.upper(text):gsub("[^%w]", ""))
end

local function ensure()
	if not root then
		gui, root = UIKit.screen("PD_Hype", 65)
	end
end

function Hype.gui(): ScreenGui
	ensure()
	return gui
end

function Hype.clear()
	if current then
		current:Destroy()
		current = nil
	end
	currentKey = ""
end

-- Removes the word on screen if it says `text` (the results card shows the result headline instead).
function Hype.clearIf(text: string)
	if currentKey ~= "" and currentKey == Hype.key(text) then
		Hype.clear()
	end
end

--[[
Shows one hype word. opts: sub (small line under it), color (solid colour instead of the gold gradient),
max (largest font px, default 220 for up to 3 characters, else 170), y (screen-scale centre, default 0.34).
]]
function Hype.show(text: string, opts: { [string]: any }?)
	local o = opts or {}
	text = Info.clean(text)
	local key = Hype.key(text)
	if key == "" then
		return
	end
	ensure()
	local now = os.clock()
	if key == currentKey and now - shownAt < DEDUPE then
		return
	end
	Hype.clear()
	serial += 1
	local mine = serial
	currentKey, shownAt = key, now
	gui:SetAttribute("LastBig", text)

	-- auto-shrink: LuckiestGuy is wide, so long lines get a smaller size instead of running off screen
	local n = math.max(1, utf8.len(text) or #text)
	local px = math.clamp(math.floor(1300 / (0.72 * n)), 64, o.max or (n <= 3 and 220 or 170)) -- digits go huge
	local sub = o.sub and Info.clean(o.sub) or ""
	local box = UIKit.new("Frame", {
		Name = "Big",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, o.y or 0.34),
		Size = UDim2.fromOffset(1500, math.floor(px * 1.25) + (sub ~= "" and 60 or 0)),
		Rotation = -6,
		Parent = root,
	})
	UIKit.text(box, {
		name = "Text",
		text = text,
		size = px,
		font = "hype",
		drop = true,
		gold = o.color == nil,
		color = o.color,
		frameSize = UDim2.new(1, 0, 0, math.floor(px * 1.25)),
		position = UDim2.fromScale(0.5, 0),
		anchor = Vector2.new(0.5, 0),
		zindex = 4,
	})
	if sub ~= "" then
		UIKit.text(box, {
			name = "Sub",
			text = sub,
			size = 40,
			frameSize = UDim2.new(1, 0, 0, 52),
			position = UDim2.new(0.5, 0, 0, math.floor(px * 1.25)),
			anchor = Vector2.new(0.5, 0),
			zindex = 4,
		})
	end
	current = box
	UIKit.pop(box, 1.9, 0.22)
	UIKit.tween(box, 0.22, { Rotation = 0 }, Enum.EasingStyle.Back)
	task.delay(LIFE - 0.2, function()
		if mine ~= serial or not box.Parent then
			return
		end
		local s = box:FindFirstChild("PopScale")
		if s then
			UIKit.tween(s, 0.18, { Scale = 0.3 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		Widgets.fadeOut(box, 0.18)
		task.delay(0.19, function()
			if mine == serial then
				Hype.clear()
			elseif box.Parent then
				box:Destroy()
			end
		end)
	end)
end

-- 3-2-1-GO! for round members, driven by the Countdown phase (Core may also announce the digits: deduped).
local function runCountdown()
	local last = nil
	while State.phase() == "Countdown" do
		local n = math.ceil(State.timeLeft())
		if n ~= last and n >= 1 and n <= 5 and State.isMember() then
			last = n
			Hype.show(tostring(n))
			Audio.play("Countdown", { pitch = 1 + (3 - math.min(n, 3)) * 0.06 })
		end
		task.wait(0.05)
	end
	if State.phase() == "Round" and State.isMember() and not State.flag("InSolo") then
		Hype.show("GO!", { color = C.Green })
		Audio.play("Go")
		Confetti.burst(Vector2.new(0.5, 0.36), 40)
	end
end

function Hype.start()
	ensure()
	gui:SetAttribute("LastBig", "")
	local running = false
	State.watch({ "Phase" }, {}, function()
		if State.phase() == "Countdown" and not running then
			running = true
			task.spawn(function()
				runCountdown()
				running = false
			end)
		end
	end)
end

return Hype
