-- Party Dash UI sounds. Uses sounds bundled with the Roblox client (rbxasset://) so nothing can fail
-- to load or be moderated away. PlayLocalSound lets the same template overlap (fast reel ticks).
local SoundService = game:GetService("SoundService")

local Sfx = {}

local DEFS = {
	tick = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.45, speed = 1.0 },
	pop = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.35, speed = 1.6 },
	land = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = 0.8 },
	whoosh = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.25, speed = 1.8 },
	boom = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.18, speed = 1.4 },
}

local folder = Instance.new("Folder")
folder.Name = "PartyUISfx"
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

-- speedMul tweaks pitch (e.g. rising countdown beeps).
function Sfx.play(name: string, speedMul: number?)
	local s = templates[name]
	if not s then
		return
	end
	s.PlaybackSpeed = DEFS[name].speed * (speedMul or 1)
	pcall(SoundService.PlayLocalSound, SoundService, s)
end

return Sfx
