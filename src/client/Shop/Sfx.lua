--!strict
-- Economy UI sounds. Only sounds bundled with the Roblox client (rbxasset://) so nothing can fail to load.
local SoundService = game:GetService("SoundService")

local Sfx = {}

local DEFS = {
	coin = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5, speed = 2.2 },
	ding = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.3, speed = 2.3 },
	pop = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.3, speed = 1.6 },
	click = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.35, speed = 1.3 },
	whoosh = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.22, speed = 1.9 },
	error = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = 0.55 },
	boom = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.16, speed = 1.6 },
}

local folder = Instance.new("Folder")
folder.Name = "EconomySfx"
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
	if not s then
		return
	end
	s.PlaybackSpeed = DEFS[name].speed * (speedMul or 1)
	pcall(SoundService.PlayLocalSound, SoundService, s)
end

-- "Ka-ching": a bright tick layered with a high blip.
function Sfx.purchase()
	Sfx.play("coin", 1)
	Sfx.play("ding", 1)
	task.delay(0.08, Sfx.play, "coin", 1.25)
end

return Sfx
