-- World-space movement juice for every character on this client (all purely visual / local):
--   running dust puffs, slide dust stream, landing ring + puff burst,
--   dash trail (Cos_DashColor), dash afterimages, a shockwave ring, sparkles, whoosh / slide sounds,
--   and for the local player a camera FOV punch on dash (additive, never stomps other FOV changes).
-- Remote characters react to the replicated "Dashing" / "Sliding" attributes; the local character
-- reacts instantly to State events.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(Shared.Theme)
local Assets = require(Shared.Movement.Assets)
local Stats = require(Shared.Movement.Stats)

local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)

type Rig = Rigs.Rig

local Effects = {}

local RUN_PUFF_SPEED = 13 -- horizontal speed needed for running puffs
local RUN_PUFF_INTERVAL = 0.12
local SLIDE_PUFF_INTERVAL = 0.035
local TRAIL_TIME = Config.DASH_DURATION + 0.25
local DUST_COLOR = Color3.fromRGB(255, 246, 228)

type FxState = {
	feet: Attachment,
	dust: ParticleEmitter,
	sparkles: ParticleEmitter,
	trail: Trail,
	whoosh: Sound,
	slideSound: Sound,
	nextPuff: number,
	trailToken: number,
	puffSide: number,
}

local states: { [Rig]: FxState } = {}

-- Folder for local-only effect parts (lives under the camera so it never touches the real workspace).
local function fxFolder(): Instance
	local camera = workspace.CurrentCamera
	local folder = camera:FindFirstChild("MovementFx")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MovementFx"
		folder.Parent = camera
	end
	return folder
end

local function legLength(rig: Rig): number
	return if rig.isR15 then rig.humanoid.HipHeight else 2
end

local function feetPosition(rig: Rig): Vector3
	local root = rig.root
	return root.Position - Vector3.new(0, root.Size.Y / 2 + legLength(rig), 0)
end

local function isGrounded(rig: Rig): boolean
	if rig.isLocal then
		return rig.humanoid.FloorMaterial ~= Enum.Material.Air
	end
	-- FloorMaterial is not reliable for characters simulated by another client: cast a short ray.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig.character }
	params.IgnoreWater = true
	local reach = rig.root.Size.Y / 2 + legLength(rig) + 0.8
	return workspace:Raycast(rig.root.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

local function newEffectPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	return part
end

-- Expanding flat disc. `normal` is the disc's facing direction.
local function ring(position: Vector3, normal: Vector3, color: Color3, startSize: number, endSize: number, time: number)
	local part = newEffectPart()
	part.Shape = Enum.PartType.Cylinder
	part.Color = color
	part.Transparency = 0.3
	part.Size = Vector3.new(0.12, startSize, startSize)
	-- A cylinder's axis is its local X; point it along `normal` (vertical normals need no lookAt).
	if math.abs(normal.Y) > 0.99 then
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	else
		part.CFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.pi / 2, 0)
	end
	part.Parent = fxFolder()
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, endSize, endSize),
		Transparency = 1,
	}):Play()
	Debris:AddItem(part, time + 0.05)
end

-- Neon afterimage of the body at its current pose.
local function ghost(rig: Rig, color: Color3, transparency: number)
	if not rig.alive then
		return
	end
	local model = Instance.new("Model")
	model.Name = "DashGhost"
	for _, part in rig.character:GetChildren() do
		if part:IsA("BasePart") and part ~= rig.root and part.Transparency < 0.9 then
			-- Clone can fail / return nil for non-archivable parts; those are simply skipped.
			local ok, result = pcall(part.Clone, part)
			local copy: BasePart? = if ok
					and typeof(result) == "Instance"
					and result:IsA("BasePart")
				then result
				else nil
			if copy then
				copy:ClearAllChildren()
				copy.Anchored = true
				copy.CanCollide = false
				copy.CanQuery = false
				copy.CanTouch = false
				copy.CastShadow = false
				copy.Massless = true
				copy.Material = Enum.Material.Neon
				copy.Color = color
				copy.Transparency = transparency
				if copy:IsA("MeshPart") then
					pcall(function()
						copy.TextureID = ""
					end)
				end
				copy.Parent = model
				TweenService:Create(copy, TweenInfo.new(0.32, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
			end
		end
	end
	model.Parent = fxFolder()
	Debris:AddItem(model, 0.4)
end

local function makeSound(parent: Instance, id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = 120
	sound.Parent = parent
	return sound
end

local function attach(rig: Rig)
	local root = rig.root
	local trove = rig.trove

	local feet = trove:add(Instance.new("Attachment"))
	feet.Name = "MovementFeet"
	feet.Position = Vector3.new(0, -(root.Size.Y / 2 + legLength(rig)) + 0.3, 0)
	feet.Parent = root

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "MovementDust"
	dust.Texture = Assets.Textures.Puff
	dust.Color = ColorSequence.new(DUST_COLOR)
	dust.LightEmission = 0.15
	dust.LightInfluence = 0.5
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.1),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(75, 75)
	dust.Acceleration = Vector3.new(0, 3, 0)
	dust.Drag = 5
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-120, 120)
	dust.Rate = 0
	dust.Enabled = false
	dust.Parent = feet

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "MovementSparkles"
	sparkles.Texture = Assets.Textures.Sparkle
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.1, 1)
	sparkles.Lifetime = NumberRange.new(0.3, 0.5)
	sparkles.Speed = NumberRange.new(6, 13)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Drag = 6
	sparkles.Rate = 0
	sparkles.Enabled = false
	sparkles.Parent = root

	-- Dash trail: a camera-facing ribbon from chest to knees.
	local top = trove:add(Instance.new("Attachment"))
	top.Name = "DashTrailTop"
	top.Position = Vector3.new(0, 0.9, 0)
	top.Parent = root
	local bottom = trove:add(Instance.new("Attachment"))
	bottom.Name = "DashTrailBottom"
	bottom.Position = Vector3.new(0, -1.1, 0)
	bottom.Parent = root
	local trail = trove:add(Instance.new("Trail"))
	trail.Name = "DashTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.FaceCamera = true
	trail.Lifetime = 0.42
	trail.LightEmission = 0.7
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = root

	local state: FxState = {
		feet = feet,
		dust = dust,
		sparkles = sparkles,
		trail = trail,
		whoosh = trove:add(makeSound(root, Assets.Sounds.Dash, if rig.isLocal then 0.7 else 0.45)),
		slideSound = trove:add(makeSound(root, Assets.Sounds.Slide, if rig.isLocal then 0.55 else 0.35)),
		nextPuff = 0,
		trailToken = 0,
		puffSide = 1,
	}
	trove:add(dust)
	trove:add(sparkles)
	states[rig] = state
	trove:add(function()
		states[rig] = nil
	end)

	if not rig.isLocal then
		local character = rig.character
		trove:connect(character:GetAttributeChangedSignal("Dashing"), function()
			if character:GetAttribute("Dashing") == true then
				local v = rig.root.AssemblyLinearVelocity
				local dir = Vector3.new(v.X, 0, v.Z)
				if dir.Magnitude < 1 then
					dir = rig.root.CFrame.LookVector * Vector3.new(1, 0, 1)
				end
				Effects.dash(rig, if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1))
			end
		end)
		trove:connect(character:GetAttributeChangedSignal("Sliding"), function()
			if character:GetAttribute("Sliding") == true then
				Effects.slideStart(rig)
			else
				Effects.slideEnd(rig)
			end
		end)
	end
end

function Effects.dash(rig: Rig, dir: Vector3)
	local state = states[rig]
	if not state then
		return
	end
	local sequence, main = Stats.dashColor(rig.player)
	state.trail.Color = sequence
	state.trail.Enabled = true
	state.trailToken += 1
	local token = state.trailToken
	task.delay(TRAIL_TIME, function()
		if state.trailToken == token and state.trail.Parent then
			state.trail.Enabled = false
		end
	end)

	state.whoosh.PlaybackSpeed = 0.95 + math.random() * 0.15
	state.whoosh:Play()
	state.sparkles.Color = ColorSequence.new(main)
	state.sparkles:Emit(if rig.isLocal then 14 else 8)
	if isGrounded(rig) then
		state.dust:Emit(6)
	end

	local chest = rig.root.Position
	ring(chest - dir * 0.5, dir, main:Lerp(Theme.Colors.White, 0.5), 1.5, 7, 0.3)
	ghost(rig, main, 0.45)
	if rig.isLocal then
		task.delay(Config.DASH_DURATION * 0.5, ghost, rig, main, 0.55)
	end
end

function Effects.slideStart(rig: Rig)
	local state = states[rig]
	if not state then
		return
	end
	state.slideSound.PlaybackSpeed = 0.95 + math.random() * 0.1
	state.slideSound:Play()
	state.dust:Emit(8)
end

function Effects.slideEnd(rig: Rig)
	local state = states[rig]
	if state and state.slideSound.IsPlaying then
		TweenService:Create(state.slideSound, TweenInfo.new(0.15), { Volume = 0 }):Play()
		local volume = if rig.isLocal then 0.55 else 0.35
		task.delay(0.16, function()
			state.slideSound:Stop()
			state.slideSound.Volume = volume
		end)
	end
end

-- Landing: legacy shock ring on the floor + a puff burst. strength 0..1.
function Effects.land(rig: Rig, strength: number?)
	local state = states[rig]
	if not state or not rig.root.Parent then
		return
	end
	local s = math.clamp(strength or 1, 0.3, 1.4)
	local feet = feetPosition(rig)
	ring(feet + Vector3.new(0, 0.08, 0), Vector3.yAxis, Color3.fromRGB(220, 240, 255), 1.5, 6 + 4 * s, 0.35)
	state.dust:Emit(math.floor(4 + 6 * s))
end

local function stepPuffs()
	local now = os.clock()
	for rig, state in states do
		if rig.alive and rig.root.Parent and now >= state.nextPuff then
			local sliding = if rig.isLocal then State.sliding else rig.character:GetAttribute("Sliding") == true
			local v = rig.root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if sliding then
				state.nextPuff = now + SLIDE_PUFF_INTERVAL
				state.feet.Position = Vector3.new(0, -(rig.root.Size.Y / 2 + legLength(rig)) + 0.3, 0)
				state.dust:Emit(2)
			elseif speed > RUN_PUFF_SPEED and isGrounded(rig) then
				state.nextPuff = now + RUN_PUFF_INTERVAL * (Config.WALK_SPEED / math.max(speed, 1))
				-- Alternate left / right foot.
				state.puffSide = -state.puffSide
				state.feet.Position =
					Vector3.new(0.5 * state.puffSide, -(rig.root.Size.Y / 2 + legLength(rig)) + 0.3, 0.4)
				state.dust:Emit(1)
			else
				state.nextPuff = now + 0.1
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Local camera FOV punch (additive: we only ever add/remove our own offset).

local fovStart = -math.huge
local fovSlide = 0
local lastFov = 0
local wroteFov: number? = nil
local fovCamera: Camera? = nil

local function fovEnvelope(t: number): number
	if t < 0 then
		return 0
	elseif t < 0.06 then
		return t / 0.06
	end
	return math.exp(-(t - 0.06) * 6)
end

local function stepFov(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera ~= fovCamera then
		fovCamera = camera
		lastFov = 0
		wroteFov = nil
	end
	local base = camera.FieldOfView
	if wroteFov and math.abs(base - wroteFov) < 1e-3 then
		base -= lastFov
	end
	fovSlide += ((if State.sliding then 1 else 0) - fovSlide) * (1 - math.exp(-10 * dt))
	local offset = 13 * fovEnvelope(os.clock() - fovStart) + 6 * fovSlide
	if offset < 0.01 then
		offset = 0
	end
	if offset ~= 0 or lastFov ~= 0 then
		local fov = math.clamp(base + offset, 1, 120)
		camera.FieldOfView = fov
		wroteFov = fov
		lastFov = fov - base
	end
end

function Effects.start()
	Rigs.onAdded(attach)

	State.on("Dash", function(rig, dir)
		fovStart = os.clock()
		Effects.dash(rig, dir)
	end)
	State.on("SlideStart", function(rig)
		Effects.slideStart(rig)
	end)
	State.on("SlideEnd", function(rig)
		if rig then
			Effects.slideEnd(rig)
		end
	end)

	RunService.Heartbeat:Connect(stepPuffs)
	RunService.PreRender:Connect(stepFov)
end

return Effects
