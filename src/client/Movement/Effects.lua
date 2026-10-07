-- World-space movement juice for every character on this client (purely visual, local):
--   running dust puffs, landing ring + puff burst,
--   slide tackle: dust and turf bits kicked up at the lead heel + a ground streak behind it, in the floor's color,
--   dash: trail (Cos_DashColor), one pooled afterimage, a shockwave ring, sparkles.
-- Sounds go through Shared.Audio ("Dash", "Slide"), so the settings menu mutes them. Everything is built once per
-- character (emitters, trails, pooled ring / ghost parts) and cleaned with the rig; nothing is created per frame.
-- Remote characters react to the replicated Dashing / Sliding attributes, the local one to State events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Audio)
local Config = require(Shared.Config)
local GameAssets = require(Shared.Assets)
local Theme = require(Shared.Theme)
local Body = require(Shared.Movement.Body)
local MoveAssets = require(Shared.Movement.Assets)
local Stats = require(Shared.Movement.Stats)

local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)

type Rig = Rigs.Rig

local Effects = {}

local RUN_PUFF_SPEED = 13 -- horizontal speed needed for running puffs
local RUN_PUFF_INTERVAL = 0.12
local TRAIL_TIME = Config.DASH_DURATION + 0.25
local GHOST_FADE = 0.32
local DUST_WHITE = 0.35 -- slide dust = floor color lifted this much toward white
local STREAK_DARK = 0.25 -- ground streak = floor color darkened this much
local DEFAULT_FLOOR = Color3.fromRGB(100, 210, 45) -- lobby grass
local REMOTE_VOLUME = 0.6

type Ghost = { model: Model, pairs: { { source: BasePart, copy: BasePart } } }
type FxState = {
	rig: Rig,
	feet: Attachment,
	dust: ParticleEmitter,
	sparkles: ParticleEmitter,
	trail: Trail,
	heelDust: ParticleEmitter?,
	turf: ParticleEmitter?,
	streak: Trail?,
	params: RaycastParams,
	ghost: Ghost?,
	rings: { Part },
	ringIndex: number,
	nextPuff: number,
	trailToken: number,
	puffSide: number,
	sliding: boolean,
	slideStart: number,
	slideSound: Sound?,
}

local states: { [Rig]: FxState } = {}

-- Folder for local-only effect parts (under the camera, so nothing touches the real workspace).
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

local function feetOffset(rig: Rig): number
	return -Body.rootToFeet(rig.character, rig.humanoid, rig.root)
end

local function isGrounded(state: FxState): boolean
	local rig = state.rig
	if rig.isLocal then
		return rig.humanoid.FloorMaterial ~= Enum.Material.Air
	end
	-- FloorMaterial is not reliable for characters simulated by another client: cast a short ray.
	local reach = -feetOffset(rig) + 0.8
	return workspace:Raycast(rig.root.Position, Vector3.new(0, -reach, 0), state.params) ~= nil
end

-- Color of whatever is under the character (part color or terrain material color).
local function floorColor(state: FxState): Color3
	local rig = state.rig
	local reach = -feetOffset(rig) + 3
	local hit = workspace:Raycast(rig.root.Position, Vector3.new(0, -reach, 0), state.params)
	if not hit then
		return DEFAULT_FLOOR
	end
	if hit.Instance:IsA("Terrain") then
		local ok, color = pcall(function()
			return workspace.Terrain:GetMaterialColor(hit.Material)
		end)
		return if ok then color else DEFAULT_FLOOR
	end
	return if hit.Instance:IsA("BasePart") then (hit.Instance :: BasePart).Color else DEFAULT_FLOOR
end

local function effectPart(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	return part
end

-- Expanding flat disc from the rig's small ring pool. `normal` is the disc's facing direction.
local function ring(
	state: FxState,
	position: Vector3,
	normal: Vector3,
	color: Color3,
	from: number,
	to: number,
	time: number
)
	state.ringIndex = state.ringIndex % #state.rings + 1
	local part = state.rings[state.ringIndex]
	part.Shape = Enum.PartType.Cylinder
	part.Color = color
	part.Transparency = 0.3
	part.Size = Vector3.new(0.12, from, from)
	-- A cylinder's axis is its local X; point it along `normal`.
	if math.abs(normal.Y) > 0.99 then
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	else
		part.CFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(0, math.pi / 2, 0)
	end
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, to, to),
		Transparency = 1,
	}):Play()
end

-- One pooled neon afterimage per character, built on its first dash.
local function ghostOf(state: FxState): Ghost
	if state.ghost and state.ghost.model.Parent then
		return state.ghost
	end
	local model = Instance.new("Model")
	model.Name = "DashGhost"
	local list = {}
	for _, part in state.rig.character:GetChildren() do
		if part:IsA("BasePart") and part ~= state.rig.root and part.Transparency < 0.9 then
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
				copy.Transparency = 1
				if copy:IsA("MeshPart") then
					pcall(function()
						copy.TextureID = ""
					end)
				end
				copy.Parent = model
				table.insert(list, { source = part, copy = copy })
			end
		end
	end
	model.Parent = fxFolder()
	state.rig.trove:add(model)
	local ghost = { model = model, pairs = list }
	state.ghost = ghost
	return ghost
end

local function showGhost(state: FxState, color: Color3)
	local ghost = ghostOf(state)
	for _, pair in ghost.pairs do
		if pair.source.Parent then
			pair.copy.CFrame = pair.source.CFrame
			pair.copy.Color = color
			pair.copy.Transparency = 0.45
			TweenService:Create(pair.copy, TweenInfo.new(GHOST_FADE, Enum.EasingStyle.Quad), { Transparency = 1 })
				:Play()
		end
	end
end

local function emitter(parent: Instance, name: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	e.Enabled = true
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- Heel emitters + ground streak on the lead (right) foot of the tackle.
local function buildHeel(state: FxState)
	local rig = state.rig
	local foot = rig.character:FindFirstChild(if rig.isR15 then "RightFoot" else "Right Leg")
	if not foot or not foot:IsA("BasePart") then
		return
	end
	local size = foot.Size
	local heelPos = Vector3.new(0, -size.Y / 2, size.Z * 0.35)
	local heel = rig.trove:add(Instance.new("Attachment"))
	heel.Name = "TackleHeel"
	heel.Position = heelPos
	heel.Parent = foot
	state.heelDust = rig.trove:add(emitter(heel, "TackleDust", {
		Texture = MoveAssets.Textures.Puff,
		LightEmission = 0.1,
		LightInfluence = 0.6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.9) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.6, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.35, 0.55),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(55, 55),
		Acceleration = Vector3.new(0, 4, 0),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		EmissionDirection = Enum.NormalId.Top,
	}))
	state.turf = rig.trove:add(emitter(heel, "TackleTurf", {
		Texture = MoveAssets.Textures.Sparkle,
		LightEmission = 0,
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0.18) }),
		Lifetime = NumberRange.new(0.35, 0.5),
		Speed = NumberRange.new(7, 12),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -45, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
		EmissionDirection = Enum.NormalId.Top,
	}))
	local left = rig.trove:add(Instance.new("Attachment"))
	left.Name = "TackleStreakA"
	left.Position = heelPos + Vector3.new(-0.35, 0, 0)
	left.Parent = foot
	local right = rig.trove:add(Instance.new("Attachment"))
	right.Name = "TackleStreakB"
	right.Position = heelPos + Vector3.new(0.35, 0, 0)
	right.Parent = foot
	local streak = rig.trove:add(Instance.new("Trail"))
	streak.Name = "TackleStreak"
	streak.Attachment0 = left
	streak.Attachment1 = right
	streak.FaceCamera = false
	streak.Lifetime = 0.45
	streak.MinLength = 0.05
	streak.LightInfluence = 1
	streak.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	streak.Enabled = false
	streak.Parent = foot
	state.streak = streak
end

local function attach(rig: Rig)
	local root = rig.root
	local trove = rig.trove
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig.character }
	params.RespectCanCollide = true

	local feet = trove:add(Instance.new("Attachment"))
	feet.Name = "MovementFeet"
	feet.Position = Vector3.new(0, feetOffset(rig) + 0.3, 0)
	feet.Parent = root

	local dust = trove:add(emitter(feet, "MovementDust", {
		Texture = MoveAssets.Textures.Puff,
		Color = ColorSequence.new(Color3.fromRGB(255, 246, 228)),
		LightEmission = 0.15,
		LightInfluence = 0.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.1) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.6, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 5,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
	}))
	local sparkles = trove:add(emitter(root, "MovementSparkles", {
		Texture = MoveAssets.Textures.Sparkle,
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(6, 13),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
	}))

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
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.MinLength = 0.05
	trail.Enabled = false
	trail.Parent = root

	local rings = {}
	for i = 1, 2 do
		local part = effectPart()
		part.Name = "MovementRing" .. i
		part.Parent = fxFolder()
		trove:add(part)
		table.insert(rings, part)
	end

	local state: FxState = {
		rig = rig,
		feet = feet,
		dust = dust,
		sparkles = sparkles,
		trail = trail,
		heelDust = nil,
		turf = nil,
		streak = nil,
		params = params,
		ghost = nil,
		rings = rings,
		ringIndex = 0,
		nextPuff = 0,
		trailToken = 0,
		puffSide = 1,
		sliding = false,
		slideStart = 0,
		slideSound = nil,
	}
	buildHeel(state)
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

-- 3D sound on the character through Shared.Audio. Returns the new Sound (Audio parents it to the part right away)
-- so a slide sound can be faded out when the slide ends early.
local function playAt(rig: Rig, key: string, pitch: number): Sound?
	local info = GameAssets.Sounds[key]
	local base = if info and type(info.volume) == "number" then info.volume else 0.6
	local before = {}
	for _, child in rig.root:GetChildren() do
		if child.Name == key then
			before[child] = true
		end
	end
	Audio.at(key, rig.root, {
		volume = if rig.isLocal then base else base * REMOTE_VOLUME,
		pitch = pitch,
		maxDistance = 120,
	})
	for _, child in rig.root:GetChildren() do
		if child:IsA("Sound") and child.Name == key and not before[child] then
			return child
		end
	end
	return nil
end

function Effects.dash(rig: Rig, dir: Vector3)
	local state = states[rig]
	if not state or not rig.root.Parent then
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

	state.sparkles.Color = ColorSequence.new(main)
	state.sparkles:Emit(if rig.isLocal then 14 else 8)
	if isGrounded(state) then
		state.dust:Emit(6)
	end
	ring(state, rig.root.Position - dir * 0.5, dir, main:Lerp(Theme.Colors.White, 0.5), 1.5, 7, 0.3)
	showGhost(state, main)
	playAt(rig, "Dash", 0.95 + math.random() * 0.15)
end

function Effects.slideStart(rig: Rig)
	local state = states[rig]
	if not state or state.sliding then
		return
	end
	state.sliding = true
	state.slideStart = os.clock()
	local floor = floorColor(state)
	local dustColor = floor:Lerp(Theme.Colors.White, DUST_WHITE)
	local streakColor = floor:Lerp(Color3.new(0, 0, 0), STREAK_DARK)
	if state.heelDust then
		state.heelDust.Color = ColorSequence.new(dustColor)
		state.heelDust:Emit(8)
	end
	if state.turf then
		state.turf.Color = ColorSequence.new(streakColor)
		state.turf:Emit(10)
	end
	if state.streak then
		state.streak.Color = ColorSequence.new(streakColor)
	end
	if state.slideSound and state.slideSound.Parent then
		state.slideSound:Stop()
	end
	state.slideSound = playAt(rig, "Slide", 0.95 + math.random() * 0.1)
end

function Effects.slideEnd(rig: Rig)
	local state = states[rig]
	if not state or not state.sliding then
		return
	end
	state.sliding = false
	if state.heelDust then
		state.heelDust.Rate = 0
	end
	if state.turf then
		state.turf.Rate = 0
	end
	if state.streak then
		state.streak.Enabled = false
	end
	local sound = state.slideSound
	state.slideSound = nil
	if sound and sound.Parent and sound.IsPlaying then
		TweenService:Create(sound, TweenInfo.new(0.15), { Volume = 0 }):Play()
		task.delay(0.16, function()
			if sound.Parent then
				sound:Stop()
			end
		end)
	end
end

-- Landing: shock ring on the floor + a puff burst. strength 0..1.4.
function Effects.land(rig: Rig, strength: number?)
	local state = states[rig]
	if not state or not rig.root.Parent then
		return
	end
	local s = math.clamp(strength or 1, 0.3, 1.4)
	local feet = rig.root.Position + Vector3.new(0, feetOffset(rig), 0)
	ring(state, feet + Vector3.new(0, 0.08, 0), Vector3.yAxis, Color3.fromRGB(220, 240, 255), 1.5, 6 + 4 * s, 0.35)
	state.dust:Emit(math.floor(4 + 6 * s))
end

local function stepFx()
	local now = os.clock()
	for rig, state in states do
		if rig.alive and rig.root.Parent then
			if state.sliding then
				-- Heavy kick-up in the first quarter second, then a steady stream while the heel is down.
				local grounded = isGrounded(state)
				local early = now - state.slideStart < 0.25
				if state.heelDust then
					state.heelDust.Rate = if grounded then (if early then 45 else 22) else 0
				end
				if state.turf then
					state.turf.Rate = if grounded then (if early then 24 else 10) else 0
				end
				if state.streak then
					state.streak.Enabled = grounded
				end
			elseif now >= state.nextPuff then
				local v = rig.root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				if speed > RUN_PUFF_SPEED and isGrounded(state) then
					state.nextPuff = now + RUN_PUFF_INTERVAL * (Config.WALK_SPEED / math.max(speed, 1))
					-- Alternate left / right foot.
					state.puffSide = -state.puffSide
					state.feet.Position = Vector3.new(0.5 * state.puffSide, feetOffset(rig) + 0.3, 0.4)
					state.dust:Emit(1)
				else
					state.nextPuff = now + 0.1
				end
			end
		end
	end
end

function Effects.start()
	Rigs.onAdded(attach)
	State.on("Dash", function(rig, dir)
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
	RunService.Heartbeat:Connect(stepFx)
end

return Effects
