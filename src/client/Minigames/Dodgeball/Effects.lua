-- Dodgeball (client): pooled one-shot effects. Nothing here is created per frame: a ring of
-- Terrain attachments carries the sounds + particle emitters, and a small pool of Neon parts is
-- reused for flashes and shockwave rings.
--   local fx = Effects.new(folder)
--   fx:sound(name, pos, speed?, volume?)   names: boom, pop, whoosh, chime, grab, thud
--   fx:puff(pos, dir, color)               cannon muzzle blast
--   fx:pop(pos, color, size)               ball bursting on a player
--   fx:bounce(groundPos, color, size, big)  ball bouncing on the floor (ring + thud)
--   fx:fizzle(pos, color, size)            ball coming to rest on the floor
--   fx:beam(pos)                           golden ball arrival
--   fx:grab(pos)                           golden ball pickup
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Effects = {}
Effects.__index = Effects

local SLOT_COUNT = 12
local FLASH_COUNT = 14
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)

local SOUNDS = {
	boom = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.5, speed = 1.3 },
	pop = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1, speed = 1.45 },
	thud = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = 0.7 },
	whoosh = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.6, speed = 1.7 },
	chime = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.9, speed = 1 },
	grab = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.7, speed = 1.9 },
}

type Slot = {
	attachment: Attachment,
	sounds: { [string]: Sound },
	smoke: ParticleEmitter,
	sparks: ParticleEmitter,
	bits: ParticleEmitter,
}

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function makeSlot(i: number): Slot
	local a = Instance.new("Attachment")
	a.Name = ("PD_DodgeballFx%02d"):format(i)
	local sounds = {}
	for name, def in SOUNDS do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = def.id
		s.Volume = def.volume
		s.PlaybackSpeed = def.speed
		s.RollOffMinDistance = 25
		s.RollOffMaxDistance = 260
		s.Parent = a
		sounds[name] = s
	end
	local smoke = emitter(a, {
		Name = "Smoke",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 215, 235)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 4.2) }),
		Lifetime = NumberRange.new(0.45, 0.8),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(28, 28),
		Drag = 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})
	local sparks = emitter(a, {
		Name = "Sparks",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		LightEmission = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(16, 30),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	})
	local bits = emitter(a, {
		Name = "Bits",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		LightEmission = 0.3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.2) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	})
	a.Parent = workspace.Terrain
	return { attachment = a, sounds = sounds, smoke = smoke, sparks = sparks, bits = bits }
end

local function makeFlash(folder: Instance): Part
	local p = Instance.new("Part")
	p.Name = "Flash"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(0, -5000, 0)
	p.Parent = folder
	return p
end

function Effects.new(folder: Instance)
	local self = setmetatable({}, Effects)
	self.slots = {} :: { Slot }
	self.nextSlot = 1
	self.flashes = {} :: { Part }
	self.nextFlash = 1
	for i = 1, SLOT_COUNT do
		table.insert(self.slots, makeSlot(i))
	end
	for _ = 1, FLASH_COUNT do
		table.insert(self.flashes, makeFlash(folder))
	end
	return self
end

function Effects:_slot(pos: Vector3): Slot
	local slot = self.slots[self.nextSlot]
	self.nextSlot = self.nextSlot % #self.slots + 1
	slot.attachment.WorldPosition = pos
	return slot
end

function Effects:_flash(): Part
	local p = self.flashes[self.nextFlash]
	self.nextFlash = self.nextFlash % #self.flashes + 1
	return p
end

function Effects:sound(name: string, pos: Vector3, speed: number?, volume: number?)
	local def = SOUNDS[name]
	if not def then
		return
	end
	local s = self:_slot(pos).sounds[name]
	s.PlaybackSpeed = def.speed * (speed or 1)
	s.Volume = def.volume * (volume or 1)
	s.TimePosition = 0
	s:Play()
end

-- An expanding, fading Neon ball (shape = Ball) or flat ring (shape = Cylinder).
function Effects:burst(cf: CFrame, shape: Enum.PartType, from: Vector3, to: Vector3, color: Color3, time: number)
	local p = self:_flash()
	p.Shape = shape
	p.Color = color
	p.Size = from
	p.CFrame = cf
	p.Transparency = 0.15
	TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = to,
		Transparency = 1,
	}):Play()
end

function Effects:puff(pos: Vector3, dir: Vector3, color: Color3)
	local slot = self:_slot(pos)
	local aim = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
	slot.smoke.EmissionDirection = Enum.NormalId.Top
	slot.attachment.WorldCFrame = CFrame.lookAt(pos, pos + aim) * CFrame.Angles(-math.pi / 2, 0, 0)
	slot.smoke:Emit(14)
	slot.sparks.Color = ColorSequence.new(Theme.Colors.Yellow, color)
	slot.sparks:Emit(10)
	self:burst(CFrame.new(pos), Enum.PartType.Ball, Vector3.one * 2, Vector3.one * 7, Theme.Colors.Yellow, 0.22)
	local s = slot.sounds.boom
	s.PlaybackSpeed = SOUNDS.boom.speed * (0.9 + math.random() * 0.25)
	s.TimePosition = 0
	s:Play()
end

function Effects:pop(pos: Vector3, color: Color3, size: number)
	local slot = self:_slot(pos)
	slot.attachment.WorldCFrame = CFrame.new(pos)
	slot.sparks.Color = ColorSequence.new(Theme.Colors.White, color)
	slot.sparks:Emit(22)
	slot.bits.Color = ColorSequence.new(color)
	slot.bits:Emit(16)
	self:burst(CFrame.new(pos), Enum.PartType.Ball, Vector3.one * size, Vector3.one * size * 3.2, color, 0.3)
	self:burst(
		CFrame.new(pos) * VERTICAL,
		Enum.PartType.Cylinder,
		Vector3.new(0.3, size, size),
		Vector3.new(0.3, size * 5, size * 5),
		Theme.Colors.White,
		0.35
	)
	local s = slot.sounds.pop
	s.PlaybackSpeed = SOUNDS.pop.speed * (0.9 + math.random() * 0.3)
	s.TimePosition = 0
	s:Play()
end

function Effects:bounce(ground: Vector3, color: Color3, size: number, big: boolean)
	self:burst(
		CFrame.new(ground) * VERTICAL,
		Enum.PartType.Cylinder,
		Vector3.new(0.2, size, size),
		Vector3.new(0.2, size * (if big then 4.5 else 2.6), size * (if big then 4.5 else 2.6)),
		color,
		if big then 0.45 else 0.3
	)
	local slot = self:_slot(ground)
	slot.attachment.WorldCFrame = CFrame.new(ground)
	slot.smoke:Emit(if big then 10 else 4)
	local s = slot.sounds.thud
	s.PlaybackSpeed = SOUNDS.thud.speed * (if big then 0.75 else 1.25)
	s.Volume = SOUNDS.thud.volume * (if big then 1.3 else 0.7)
	s.TimePosition = 0
	s:Play()
end

function Effects:fizzle(pos: Vector3, color: Color3, size: number)
	local slot = self:_slot(pos)
	slot.attachment.WorldCFrame = CFrame.new(pos)
	slot.smoke:Emit(6)
	slot.bits.Color = ColorSequence.new(color)
	slot.bits:Emit(8)
	self:burst(CFrame.new(pos), Enum.PartType.Ball, Vector3.one * size, Vector3.one * size * 1.8, color, 0.25)
	local s = slot.sounds.thud
	s.PlaybackSpeed = SOUNDS.thud.speed
	s.Volume = SOUNDS.thud.volume
	s.TimePosition = 0
	s:Play()
end

function Effects:beam(pos: Vector3)
	local gold = Color3.fromRGB(255, 208, 64)
	self:burst(
		CFrame.new(pos + Vector3.new(0, 30, 0)) * VERTICAL,
		Enum.PartType.Cylinder,
		Vector3.new(60, 7, 7),
		Vector3.new(60, 0.5, 0.5),
		gold,
		0.9
	)
	self:burst(
		CFrame.new(pos - Vector3.new(0, 1.9, 0)) * VERTICAL,
		Enum.PartType.Cylinder,
		Vector3.new(0.3, 2, 2),
		Vector3.new(0.3, 16, 16),
		Theme.Colors.White,
		0.6
	)
	local slot = self:_slot(pos)
	slot.attachment.WorldCFrame = CFrame.new(pos)
	slot.sparks.Color = ColorSequence.new(gold, Theme.Colors.White)
	slot.sparks:Emit(30)
	-- A rising three-note "bling".
	for i, speed in { 1.2, 1.5, 1.9 } do
		task.delay((i - 1) * 0.09, function()
			self:sound("chime", pos, speed)
		end)
	end
end

function Effects:grab(pos: Vector3)
	local gold = Color3.fromRGB(255, 208, 64)
	local slot = self:_slot(pos)
	slot.attachment.WorldCFrame = CFrame.new(pos)
	slot.sparks.Color = ColorSequence.new(gold, Theme.Colors.White)
	slot.sparks:Emit(26)
	self:burst(CFrame.new(pos), Enum.PartType.Ball, Vector3.one * 3, Vector3.one * 10, gold, 0.3)
	local s = slot.sounds.grab
	s.TimePosition = 0
	s:Play()
	self:sound("chime", pos, 2.2)
end

function Effects:destroy()
	for _, slot in self.slots do
		slot.attachment:Destroy()
	end
	for _, p in self.flashes do
		p:Destroy()
	end
	table.clear(self.slots)
	table.clear(self.flashes)
end

return Effects
