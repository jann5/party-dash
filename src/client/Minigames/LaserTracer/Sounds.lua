--!strict
-- Laser Tracer sounds. Only sounds bundled with the Roblox client (rbxasset://), so nothing can fail to
-- load or be moderated away. One Sounds object is created by the boot script and shared by every map.
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Sounds = {}
Sounds.__index = Sounds

local DEFS = {
	beep = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.55, speed = 1.5 }, -- telegraph
	powerOn = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.3, speed = 2.6 }, -- beam goes live
	reverse = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.45, speed = 0.75 }, -- direction flip
	zap = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.4, speed = 2.3 }, -- player hit
	crackle = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5, speed = 0.45 }, -- hit tail
}

export type Sounds = typeof(setmetatable({} :: { folder: Folder, templates: { [string]: Sound } }, Sounds))

function Sounds.new(): Sounds
	local folder = Instance.new("Folder")
	folder.Name = "LaserTracerSfx"
	local templates = {}
	for name, def in DEFS do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.id
		s.Volume = def.volume
		s.PlaybackSpeed = def.speed
		s.Parent = folder
		templates[name] = s
	end
	folder.Parent = SoundService
	return setmetatable({ folder = folder, templates = templates }, Sounds)
end

-- Flat (2D) sound for this client only. speedMul tweaks the pitch (rising telegraph beeps).
function Sounds.play(self: Sounds, name: string, speedMul: number?, volumeMul: number?)
	local s = self.templates[name]
	local def = DEFS[name]
	if not s or not def then
		return
	end
	s.PlaybackSpeed = def.speed * (speedMul or 1)
	s.Volume = def.volume * (volumeMul or 1)
	pcall(SoundService.PlayLocalSound, SoundService, s)
end

-- Positional one-shot attached to a part or attachment in the world.
function Sounds.playAt(self: Sounds, name: string, parent: Instance, speedMul: number?)
	local template = self.templates[name]
	local def = DEFS[name]
	if not template or not def then
		return
	end
	local s = template:Clone()
	s.PlaybackSpeed = def.speed * (speedMul or 1)
	s.RollOffMinDistance = 25
	s.RollOffMaxDistance = 220
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

function Sounds.destroy(self: Sounds)
	self.folder:Destroy()
end

return Sounds
