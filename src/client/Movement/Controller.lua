-- Local player input + motion for DASH and SLIDE.
-- The client owns its character's physics, so the motion happens here (a LinearVelocity on the root),
-- then the server is told through Movement_Dash / Movement_Slide and publishes the trusted attributes.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Net = require(Shared.Net)
local Assets = require(Shared.Movement.Assets)
local Stats = require(Shared.Movement.Stats)

local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)

type Rig = Rigs.Rig

local Controller = {}

local player = Players.LocalPlayer

-- Dash speed profile: v(t) = peak * (1 - DROP * t^2), t in 0..1. Its average is (1 - DROP / 3) * peak,
-- so peak = distance / (duration * PROFILE_AREA) covers exactly the dash distance.
local DASH_PROFILE_DROP = 0.55
local DASH_PROFILE_AREA = 1 - DASH_PROFILE_DROP / 3
local AIR_DASH_RISE = 2 -- slight upward drift during an air dash (it ignores gravity)
local DASH_EXIT_GROUND = 1.05 -- * WalkSpeed carried out of a ground dash
local DASH_EXIT_AIR = 1.2

local SLIDE_BOOST = 22 -- added to the entry speed
local SLIDE_MAX_SPEED = 48
local SLIDE_END_SPEED = 0.8 -- * WalkSpeed at the end of the slide
local SLIDE_STEER = 2.4 -- radians per second of steering while sliding
local SLIDE_JUMP_CAP = 36 -- horizontal speed kept when jumping out of a slide
local SLIDE_BUFFER = 0.22 -- a slide pressed in the air / during a dash starts this long after

local MOVER_FORCE = 1e7
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 50

local BLOCKING_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

local current: Rig? = nil
local mover: LinearVelocity? = nil
local slideTrack: AnimationTrack? = nil
local dashRemote: RemoteEvent
local slideRemote: RemoteEvent

local dash = {
	active = false,
	t = 0,
	dir = Vector3.new(0, 0, -1),
	peak = 0,
	grounded = true,
}
local slide = {
	active = false,
	t = 0,
	dir = Vector3.new(0, 0, -1),
	speed0 = 0,
	speedEnd = 0,
	prevAutoRotate = true,
}
local slideBufferedUntil = 0

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return nil
	end
	return f.Unit
end

local function isGrounded(rig: Rig): boolean
	return rig.humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Players placed on a round map are frozen during the intro card and the 3-2-1 countdown.
local function frozenByRound(): boolean
	if player:GetAttribute("InRound") ~= true then
		return false
	end
	local gs = ReplicatedStorage:FindFirstChild("GameState")
	local phase = gs and gs:GetAttribute("Phase")
	return phase == GameState.Phase.Intro or phase == GameState.Phase.Countdown
end

local function canAct(rig: Rig): boolean
	local humanoid, root = rig.humanoid, rig.root
	if not rig.alive or not humanoid.Parent or not root.Parent then
		return false
	end
	if humanoid.Health <= 0 or root.Anchored or humanoid.PlatformStand or humanoid.Sit then
		return false
	end
	if rig.character:GetAttribute("Stunned") == true then
		return false
	end
	if humanoid.WalkSpeed < 0.5 or BLOCKING_STATES[humanoid:GetState()] then
		return false
	end
	return not frozenByRound()
end

local function faceDirection(root: BasePart, dir: Vector3)
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + dir)
end

local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	return CFrame.Angles(0, sign * maxAngle, 0):VectorToWorldSpace(from)
end

local function setHorizontalVelocity(root: BasePart, horizontal: Vector3)
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, v.Y, horizontal.Z)
end

---------------------------------------------------------------------------------------------------
-- Dash

local function finishDash(rig: Rig?, natural: boolean)
	if not dash.active then
		return
	end
	dash.active = false
	State.dashing = false
	if mover and not slide.active then
		mover.Enabled = false
	end
	if natural and rig and rig.root.Parent then
		local exit = rig.humanoid.WalkSpeed * (if dash.grounded then DASH_EXIT_GROUND else DASH_EXIT_AIR)
		setHorizontalVelocity(rig.root, dash.dir * exit)
	end
	State.fire("DashEnd", rig)
end

local endSlide: (Rig?, string) -> ()

local function startDash(rig: Rig)
	local humanoid, root = rig.humanoid, rig.root
	local now = os.clock()
	local dir = flat(humanoid.MoveDirection) or flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local grounded = isGrounded(rig)
	if slide.active then
		endSlide(rig, "dash")
	end
	if not grounded then
		State.airDashUsed = true
	end

	local cooldown = Stats.dashCooldown(player)
	State.dashCooldown = cooldown
	State.dashReadyAt = now + cooldown
	State.dashing = true

	dash.active = true
	dash.t = 0
	dash.dir = dir
	dash.grounded = grounded
	dash.peak = Stats.dashDistance(player) / (Config.DASH_DURATION * DASH_PROFILE_AREA)

	if mover then
		if grounded then
			-- Plane mode: horizontal speed is forced, gravity / ledges still work.
			mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
			mover.PlaneVelocity = Vector2.new(dir.X, dir.Z) * dash.peak
		else
			-- Air dash: a flat burst that ignores gravity for its short duration.
			mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			mover.VectorVelocity = dir * dash.peak + Vector3.new(0, AIR_DASH_RISE, 0)
		end
		mover.Enabled = true
	end
	if humanoid.AutoRotate then
		faceDirection(root, dir)
	end

	dashRemote:FireServer()
	State.fire("Dash", rig, dir, grounded)
end

local function stepDash(rig: Rig, dt: number)
	local duration = Config.DASH_DURATION
	if dash.t >= duration then
		finishDash(rig, true)
		return
	end
	local t = math.clamp((dash.t + dt * 0.5) / duration, 0, 1)
	dash.t += dt
	local speed = dash.peak * (1 - DASH_PROFILE_DROP * t * t)
	if mover then
		if mover.VelocityConstraintMode == Enum.VelocityConstraintMode.Plane then
			mover.PlaneVelocity = Vector2.new(dash.dir.X, dash.dir.Z) * speed
		else
			mover.VectorVelocity = dash.dir * speed + Vector3.new(0, AIR_DASH_RISE, 0)
		end
	end
end

local function tryDash()
	local rig = current
	if not rig or not canAct(rig) or dash.active then
		return
	end
	if os.clock() < State.dashReadyAt or (not isGrounded(rig) and State.airDashUsed) then
		State.fire("DashDenied")
		return
	end
	startDash(rig)
end

---------------------------------------------------------------------------------------------------
-- Slide

endSlide = function(rig: Rig?, reason: string)
	if not slide.active then
		return
	end
	slide.active = false
	State.sliding = false
	State.slideReadyAt = os.clock() + Stats.slideCooldown()
	if mover and not dash.active then
		mover.Enabled = false
	end
	if slideTrack then
		slideTrack:Stop(0.18)
	end
	if rig and rig.humanoid.Parent then
		rig.humanoid.AutoRotate = slide.prevAutoRotate
		if rig.root.Parent then
			local v = rig.root.AssemblyLinearVelocity
			local horizontal = Vector3.new(v.X, 0, v.Z)
			if reason == "jump" then
				-- Slide-jump keeps (capped) momentum: a satisfying long jump.
				if horizontal.Magnitude > SLIDE_JUMP_CAP then
					setHorizontalVelocity(rig.root, horizontal.Unit * SLIDE_JUMP_CAP)
				end
			elseif reason == "time" then
				setHorizontalVelocity(rig.root, slide.dir * math.max(rig.humanoid.WalkSpeed * 0.9, 1))
			end
		end
	end
	if reason ~= "time" then
		slideRemote:FireServer(false)
	end
	State.fire("SlideEnd", rig, reason)
end

local function loadSlideTrack(rig: Rig)
	slideTrack = nil
	if not rig.isR15 then
		return
	end
	local animator = rig.humanoid:FindFirstChildOfClass("Animator") or rig.humanoid:WaitForChild("Animator", 5)
	if not animator or not animator:IsA("Animator") or current ~= rig then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = Assets.animationId(Assets.SlidePose)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track and current == rig then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		slideTrack = track
	end
end

local function startSlide(rig: Rig)
	local humanoid, root = rig.humanoid, rig.root
	local dir = flat(humanoid.MoveDirection) or flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local v = root.AssemblyLinearVelocity
	local entry = math.max(Vector3.new(v.X, 0, v.Z).Magnitude, humanoid.WalkSpeed)

	slide.active = true
	slide.t = 0
	slide.dir = dir
	slide.speed0 = math.min(entry + SLIDE_BOOST, SLIDE_MAX_SPEED)
	slide.speedEnd = humanoid.WalkSpeed * SLIDE_END_SPEED
	slide.prevAutoRotate = humanoid.AutoRotate
	State.sliding = true
	slideBufferedUntil = 0

	humanoid.AutoRotate = false
	faceDirection(root, dir)
	-- Snap down so the lowered body hugs the floor right away.
	root.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, -6), v.Z)
	if mover then
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		mover.PlaneVelocity = Vector2.new(dir.X, dir.Z) * slide.speed0
		mover.Enabled = true
	end
	if slideTrack then
		slideTrack:Play(0.08)
	end

	slideRemote:FireServer(true)
	State.fire("SlideStart", rig, dir)
end

local function stepSlide(rig: Rig, dt: number)
	slide.t += dt
	local t = slide.t / Config.SLIDE_DURATION
	if t >= 1 then
		endSlide(rig, "time")
		return
	end
	local want = flat(rig.humanoid.MoveDirection)
	if want and want:Dot(slide.dir) > -0.7 then
		slide.dir = rotateToward(slide.dir, want, SLIDE_STEER * dt)
	end
	local speed = slide.speedEnd + (slide.speed0 - slide.speedEnd) * (1 - t) ^ 1.6
	if mover then
		mover.PlaneVelocity = Vector2.new(slide.dir.X, slide.dir.Z) * speed
	end
	faceDirection(rig.root, slide.dir)
end

local function trySlide(fromBuffer: boolean?)
	local rig = current
	if not rig or not canAct(rig) or slide.active then
		return
	end
	local now = os.clock()
	if dash.active or now < State.slideReadyAt or not isGrounded(rig) then
		-- Remember the press briefly so a slide pressed just before landing still happens.
		if not fromBuffer then
			slideBufferedUntil = now + SLIDE_BUFFER
		end
		return
	end
	startSlide(rig)
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local function cancelAll(rig: Rig?)
	finishDash(rig, false)
	endSlide(rig, "cancel")
	slideBufferedUntil = 0
	if mover then
		mover.Enabled = false
	end
end

local function attach(rig: Rig)
	if not rig.isLocal then
		return
	end
	current = rig
	dash.active = false
	slide.active = false
	State.dashing = false
	State.sliding = false
	State.airDashUsed = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementAttachment"
	attachment.Parent = rig.root
	rig.trove:add(attachment)

	local lv = Instance.new("LinearVelocity")
	lv.Name = "MovementVelocity"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.MaxForce = MOVER_FORCE
	lv.Enabled = false
	lv.Parent = rig.root
	rig.trove:add(lv)
	mover = lv

	rig.trove:connect(rig.humanoid.StateChanged, function(_, new)
		if new == Enum.HumanoidStateType.Jumping and slide.active then
			endSlide(rig, "jump")
		end
	end)
	rig.trove:connect(rig.character:GetAttributeChangedSignal("Stunned"), function()
		if rig.character:GetAttribute("Stunned") == true then
			cancelAll(rig)
		end
	end)
	rig.trove:add(function()
		if current == rig then
			cancelAll(rig)
			current = nil
			mover = nil
			slideTrack = nil
		end
	end)

	task.spawn(loadSlideTrack, rig)
end

local function step(dt: number)
	local rig = current
	if not rig or not rig.alive then
		return
	end
	if (dash.active or slide.active) and not canAct(rig) then
		cancelAll(rig)
		return
	end
	if not dash.active and isGrounded(rig) then
		State.airDashUsed = false
	end
	if dash.active then
		stepDash(rig, dt)
	end
	if slide.active then
		stepSlide(rig, dt)
	elseif slideBufferedUntil > os.clock() and not dash.active then
		trySlide(true)
	end
end

local function onDashAction(_: string, inputState: Enum.UserInputState, _: InputObject)
	if inputState == Enum.UserInputState.Begin then
		tryDash()
	end
	-- Sink so LeftShift never toggles the default shift-lock while it means "dash".
	return Enum.ContextActionResult.Sink
end

local function onSlideAction(_: string, inputState: Enum.UserInputState, _: InputObject)
	if inputState == Enum.UserInputState.Begin then
		trySlide(false)
	end
	return Enum.ContextActionResult.Sink
end

function Controller.start()
	dashRemote = Net.event(Stats.Remote.Dash)
	slideRemote = Net.event(Stats.Remote.Slide)

	-- The server tells us when it refused a dash so the cooldown bar shows the real wait.
	dashRemote.OnClientEvent:Connect(function(kind: any, remaining: any)
		if kind == "Reject" and type(remaining) == "number" and remaining == remaining then
			local wait = math.clamp(remaining, 0, Config.DASH_COOLDOWN * 2)
			State.dashCooldown = math.max(State.dashCooldown, wait)
			State.dashReadyAt = math.max(State.dashReadyAt, os.clock() + wait)
		end
	end)

	ContextActionService:BindActionAtPriority(
		Stats.Action.Dash,
		onDashAction,
		true,
		ACTION_PRIORITY,
		Enum.KeyCode.LeftShift
	)
	ContextActionService:BindActionAtPriority(
		Stats.Action.Slide,
		onSlideAction,
		true,
		ACTION_PRIORITY,
		Enum.KeyCode.C,
		Enum.KeyCode.LeftControl
	)

	Rigs.onAdded(attach)
	RunService.PreSimulation:Connect(step)
end

return Controller
