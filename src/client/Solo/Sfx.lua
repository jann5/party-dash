--!strict
-- Solo Record sounds. Only sounds bundled with the Roblox client (rbxasset://), so nothing can fail to load.
local SoundService = game:GetService("SoundService")

local Sfx = {}

local DEFS = {
	click = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, speed = 1.7 },
	open = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.3, speed = 1.6 },
	tick = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.45, speed = 1.0 },
	land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = 0.8 },
	boom = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.2, speed = 1.3 },
}

local folder = Instance.new("Folder")
folder.Name = "SoloSfx"
folder.Parent = SoundService

local templates: { [string]: Sound } = {}
for name, def in DEFS do
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.id
	s.Volume = def.volume
	s.PlaybackSpeed = def.speed
	s.Parent = folder
	templates[name] = s
end

function Sfx.play(name: string, speedMul: number?)
	local s = templates[name]
	local def = DEFS[name]
	if not s or not def then
		return
	end
	s.PlaybackSpeed = def.speed * (speedMul or 1)
	pcall(SoundService.PlayLocalSound, SoundService, s)
end

return Sfx
