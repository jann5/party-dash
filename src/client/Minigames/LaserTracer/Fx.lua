--!strict
-- Laser Tracer visual builders (client only). Pure constructors: everything they make is returned to the
-- caller (or self-destroys through Debris), nothing is kept at module level.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Motion = require(script.Parent.Motion)

local Fx = {}

Fx.COLORS = Motion.COLORS
Fx.CORE_THICKNESS = 0.55
Fx.GLOW_THICKNESS = 1.5
Fx.CORE_WHITENESS = 0.12 -- just a hint of white-hot core; more washes the hue out under bloom
Fx.GLOW_TRANSPARENCY = 0.6
Fx.FLOOR_TRANSPARENCY = 0.4
Fx.NODE_SIZE = 1.5

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

export type Beam = {
	core: Part,
	glow: Part,
	floor: Part,
	nodeA: Part,
	nodeB: Part,
	lights: { PointLight },
	emitters: { ParticleEmitter },
	lengthSparks: ParticleEmitter,
	color: Color3,
	coreColor: Color3,
	visible: boolean,
}

local function neon(parent: Instance, name: string, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Shape = shape or Enum.PartType.Block
	p.Size = Vector3.one * 0.2
	p.Parent = parent
	return p
end

local function sparks(parent: Instance, color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "Sparks"
	e.Texture = SPARK_TEXTURE
	e.Color = ColorSequence.new(Theme.Colors.White, color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(8, 16)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -60, 0)
	e.Drag = 2
	e.Rate = 28
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = parent
	return e
end

-- One beam: bright core + soft glow + a glowing "shadow" line on the floor (depth cue for jumping)
-- + a spark-spitting node at each end.
function Fx.newBeam(parent: Instance, kind: string): Beam
	local color = Fx.COLORS[kind] or Fx.COLORS.low
	local coreColor = color:Lerp(Theme.Colors.White, Fx.CORE_WHITENESS)
	local core = neon(parent, "BeamCore", coreColor, 0, Enum.PartType.Cylinder)
	local glow = neon(parent, "BeamGlow", color, Fx.GLOW_TRANSPARENCY, Enum.PartType.Cylinder)
	local floor = neon(parent, "BeamFloor", color, Fx.FLOOR_TRANSPARENCY)
	local nodeA = neon(parent, "NodeA", coreColor, 0, Enum.PartType.Ball)
	local nodeB = neon(parent, "NodeB", coreColor, 0, Enum.PartType.Ball)
	nodeA.Size = Vector3.one * Fx.NODE_SIZE
	nodeB.Size = Vector3.one * Fx.NODE_SIZE

	local lights = {}
	for _, node in { nodeA, nodeB } do
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 12
		light.Brightness = 2.5
		light.Shadows = false
		light.Parent = node
		table.insert(lights, light)
	end
	local emitters = { sparks(nodeA, color), sparks(nodeB, color) }

	-- Sparks drizzling down from the whole length of the beam.
	local lengthSparks = sparks(core, color)
	lengthSparks.EmissionDirection = Enum.NormalId.Bottom
	lengthSparks.Speed = NumberRange.new(2, 6)
	lengthSparks.SpreadAngle = Vector2.new(35, 35)
	lengthSparks.Lifetime = NumberRange.new(0.2, 0.4)
	lengthSparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	table.insert(emitters, lengthSparks)

	local beam: Beam = {
		core = core,
		glow = glow,
		floor = floor,
		nodeA = nodeA,
		nodeB = nodeB,
		lights = lights,
		emitters = emitters,
		lengthSparks = lengthSparks,
		color = color,
		coreColor = coreColor,
		visible = true,
	}
	Fx.setVisible(beam, false)
	return beam
end

function Fx.setVisible(beam: Beam, visible: boolean)
	if beam.visible == visible then
		return
	end
	beam.visible = visible
	beam.core.Transparency = if visible then 0 else 1
	beam.glow.Transparency = if visible then Fx.GLOW_TRANSPARENCY else 1
	beam.floor.Transparency = if visible then Fx.FLOOR_TRANSPARENCY else 1
	beam.nodeA.Transparency = if visible then 0 else 1
	beam.nodeB.Transparency = if visible then 0 else 1
	for _, light in beam.lights do
		light.Enabled = visible
	end
	for _, e in beam.emitters do
		e.Enabled = visible
	end
end

-- Zap on a hit player: flash ball, a few lightning shards, a spark burst. Cleans itself up.
function Fx.zap(parent: Instance, position: Vector3, kind: string, rng: Random): BasePart
	local color = Fx.COLORS[kind] or Fx.COLORS.low
	local flash = neon(parent, "Zap", Theme.Colors.White, 0.1, Enum.PartType.Ball)
	flash.Size = Vector3.one * 1.5
	flash.CFrame = CFrame.new(position)
	TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 8,
		Transparency = 1,
		Color = color,
	}):Play()

	for _ = 1, 6 do
		local shard = neon(flash, "Bolt", if rng:NextNumber() < 0.5 then Theme.Colors.White else color, 0)
		shard.Size = Vector3.new(0.18, 0.18, rng:NextNumber(2, 3.6))
		local dir = rng:NextUnitVector()
		shard.CFrame = CFrame.lookAt(position + dir * 1.6, position + dir * 4)
			* CFrame.Angles(0, 0, rng:NextNumber(0, 6))
		TweenService:Create(shard, TweenInfo.new(0.25, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	end

	local burst = sparks(flash, color)
	burst.Enabled = false
	burst.Speed = NumberRange.new(18, 32)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	burst:Emit(36)

	Debris:AddItem(flash, 1)
	return flash
end

return Fx
