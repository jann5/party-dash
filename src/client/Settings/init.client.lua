-- Party Dash Settings (client; brief #23): a Settings tile in the left dock opens a Blue panel with three big
-- toggles (Music, Sound Effects, Camera Shake). A toggle applies instantly through the client-local Player attributes
-- Set_Music / Set_SFX / Set_Shake (Shared.Audio mutes its SoundGroups from them, camera shake readers check
-- Set_Shake) and is saved by the server through Economy_Settings({ music, sfx, shake }). Missing attribute = ON.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIKit"))
local Toggle = require(script.Toggle)

local player = Players.LocalPlayer
local Style = UIKit.Style

local SEND_GAP = 0.6 -- min seconds between Economy_Settings sends (the server rate-limits it)
local REMOTE_WAIT = 20 -- how long a pending save waits for Economy to create the remote
local ECHO_WINDOW = 1.5 -- after a save, a stale server echo of an older save cannot undo the player's latest pick

local OPTIONS = {
	{
		name = "Music",
		attr = "Set_Music",
		field = "music",
		title = "Music",
		hint = "Calm background tunes",
		icon = "music",
		color = "Purple",
	},
	{
		name = "SFX",
		attr = "Set_SFX",
		field = "sfx",
		title = "Sound Effects",
		hint = "Clicks, hits and booms",
		icon = "speaker",
		color = "Cyan",
	},
	{
		name = "Shake",
		attr = "Set_Shake",
		field = "shake",
		title = "Camera Shake",
		hint = "Screen shake on big hits",
		icon = "lightning",
		color = "Orange",
	},
}

local function isOn(attr: string): boolean
	return player:GetAttribute(attr) ~= false
end

-- ===== saving (throttled; the remote is looked up lazily so a missing Economy never breaks the panel) =====

local sendQueued = false
local waitingForRemote = false
local lastSent = -math.huge
local picked: { [string]: boolean } = {} -- attr -> the player's latest choice
local holdUntil = 0 -- picks win over replicated values until this time

local function findRemote(): RemoteEvent?
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("Economy_Settings")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function send()
	local remote = findRemote()
	if not remote then
		-- keep the local state; save it once Economy creates the remote
		if not waitingForRemote then
			waitingForRemote = true
			task.spawn(function()
				local folder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
				local found = folder and folder:WaitForChild("Economy_Settings", REMOTE_WAIT)
				waitingForRemote = false
				if found then
					send()
				else
					holdUntil = 0 -- no Economy: stop guarding against echoes that will never come
				end
			end)
		end
		return
	end
	lastSent = os.clock()
	local payload = {}
	for _, option in OPTIONS do
		payload[option.field] = isOn(option.attr)
	end
	remote:FireServer(payload)
	holdUntil = os.clock() + ECHO_WINDOW
end

-- Several quick toggles collapse into one send carrying the final state.
local function queueSend()
	if sendQueued then
		return
	end
	sendQueued = true
	task.delay(math.max(0.1, lastSent + SEND_GAP - os.clock()), function()
		sendQueued = false
		send()
	end)
end

-- ===== panel =====

local panel = UIKit.panel({
	name = "Settings",
	title = "Settings",
	icon = "settings",
	color = "Blue",
	size = Vector2.new(760, 520),
})

local list = UIKit.new("Frame", {
	Name = "Rows",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 6),
	Size = UDim2.new(1, 0, 1, -40),
	ZIndex = 13,
	Parent = panel.body,
})
UIKit.list(list, Enum.FillDirection.Vertical, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

for i, option in OPTIONS do
	local row
	row = Toggle.new(list, {
		name = option.name,
		order = i,
		title = option.title,
		hint = option.hint,
		icon = option.icon,
		color = option.color,
		value = isOn(option.attr),
		onToggle = function(on: boolean)
			picked[option.attr] = on
			holdUntil = math.huge -- until the save goes out
			player:SetAttribute(option.attr, on) -- local first: Audio reacts this frame
			row.set(on, true)
			UIKit.sound("UiClick", { pitch = 0.95 + math.random() * 0.1 }) -- after the SFX change, so ON is audible
			queueSend()
		end,
	})
	-- the saved value arrives from the server (profile load, save confirmation) while the panel exists
	player:GetAttributeChangedSignal(option.attr):Connect(function()
		local pick = picked[option.attr]
		if pick ~= nil and isOn(option.attr) ~= pick and os.clock() < holdUntil then
			player:SetAttribute(option.attr, pick) -- echo of an older save: keep the latest pick
			return
		end
		row.set(isOn(option.attr), true)
	end)
end

UIKit.text(panel.body, {
	name = "Version",
	text = "Version 2.0",
	size = Style.Text.Caption,
	font = "body",
	color = Style.Colors.Muted,
	stroke = 0,
	frameSize = UDim2.new(1, 0, 0, 24),
	position = UDim2.fromScale(0.5, 1),
	anchor = Vector2.new(0.5, 1),
	zindex = 14,
})

UIKit.Dock.add("Left", {
	id = "Settings",
	order = 90,
	icon = "settings",
	label = "Settings",
	color = "Dark",
	onClick = function()
		if player:GetAttribute("InRound") ~= true then
			panel.toggle()
		end
	end,
})

-- panels never stay open over a round you are playing
player:GetAttributeChangedSignal("InRound"):Connect(function()
	if player:GetAttribute("InRound") == true then
		panel.close()
	end
end)
