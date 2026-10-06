--[[
Hole in the Wall (client): impact and "made it through" effects.

	local fx = Fx.new()
	fx:hit(position, direction, wallColor, isMe)    -- shockwave ring + debris burst + thud
	fx:pass(position, holeColor, isMe)              -- sparkle ring in the hole's color (+ ding and "NICE!" for me)
	fx:destroy()

Particles come from one pooled anchored part; only the short-lived shockwave ring is created per hit.
Sounds are bundled with the Roblox client (rbxasset://), so they can never fail to load.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Fx = {}
Fx.__index = Fx

local PASS_WORDS = { "NICE!", "CLEAN!", "SMOOTH!", "PERFECT!", "SNEAKY!" }

local function sound(parent: Instance, id: string, volume: number, speed: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 220
	s.Parent = parent
	return s
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightEmission = 0.5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

function Fx.new()
	local self = setmetatable({}, Fx)
	local anchor = Instance.new("Part")
	anchor.Name = "HoleInTheWallFx"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(0, -500, 0)
	self.anchor = anchor

	local at = Instance.new("Attachment")
	at.Parent = anchor
	self.attachment = at

	self.debris = emitter(at, {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(25, 45),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -60, 0),
		Drag = 2,
		Shape = Enum.ParticleEmitterShape.Sphere,
	})
	self.stars = emitter(at, {
		Color = ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.White),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(10, 20),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		LightEmission = 0.9,
	})
	self.sparkles = emitter(at, {
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.3, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.45, 0.8),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 12, 0),
		Drag = 3,
		LightEmission = 1,
	})
	self.thud = sound(at, "rbxasset://sounds/action_jump_land.mp3", 1, 0.55)
	self.crash = sound(at, "rbxasset://sounds/impact_explosion_03.mp3", 0.25, 1.5)
	self.ding = sound(SoundService, "rbxasset://sounds/electronicpingshort.wav", 0.35, 1.3)
	anchor.Parent = workspace
	return self
end

function Fx:_moveTo(position: Vector3)
	self.attachment.WorldPosition = position
end

function Fx:hit(position: Vector3, direction: Vector3, color: Color3, isMe: boolean)
	self:_moveTo(position)
	-- Debris flies the way the wall is going.
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 0.1 then
		self.attachment.WorldCFrame = CFrame.lookAt(position, position + flat.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
	self.debris.Color = ColorSequence.new(color, Theme.Colors.White)
	self.debris.EmissionDirection = Enum.NormalId.Top
	self.debris:Emit(22)
	self.stars:Emit(14)
	self.thud.PlaybackSpeed = 0.5 + math.random() * 0.15
	self.thud:Play()
	self.crash:Play()

	-- Shockwave ring on the wall face.
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color:Lerp(Theme.Colors.White, 0.35)
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.3, 2, 2)
	local look = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
	ring.CFrame = CFrame.lookAt(position, position + look) * CFrame.Angles(0, math.pi / 2, 0)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, if isMe then 16 else 11, if isMe then 16 else 11),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.4)
end

local function popWord(character: Model, text: string, color: Color3)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "HoleInTheWall_Pass"
	gui.Size = UDim2.fromScale(5, 2)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.6)
	t.Size = UDim2.fromScale(0.3, 0.3)
	t.Rotation = math.random(-8, 8)
	t.FontFace = Theme.FontFace
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Ink
	stroke.Thickness = 3
	stroke.Parent = t
	t.Parent = gui
	gui.Adornee = head
	gui.Parent = head
	TweenService:Create(t, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
	}):Play()
	task.delay(0.5, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.3), { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0) })
				:Play()
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(gui, 0.9)
end

function Fx:pass(position: Vector3, color: Color3, isMe: boolean)
	self:_moveTo(position)
	self.sparkles.Color = ColorSequence.new(color, Theme.Colors.White)
	self.sparkles:Emit(if isMe then 20 else 10)
	if isMe then
		self.ding.PlaybackSpeed = 1.2 + math.random() * 0.25
		pcall(SoundService.PlayLocalSound, SoundService, self.ding)
		local character = Players.LocalPlayer.Character
		if character then
			popWord(character, PASS_WORDS[math.random(1, #PASS_WORDS)], color)
		end
	end
end

function Fx:destroy()
	self.anchor:Destroy()
	self.ding:Destroy()
end

return Fx
