-- Local player input + motion for DASH and SLIDE (plus the jump assist hook-up).
-- The client owns its character's physics, so the motion happens here (a LinearVelocity on the root), then the server
-- is told through Movement_Dash(t) / Movement_Slide(active, t) and publishes the trusted attributes.
--   Dash   LeftShift / RightShift / Q / gamepad X / touch button: a 16-stud burst (Config.DASH_*), works once in the
--          air without killing the jump arc, eases out through a short momentum tail.
--   Slide  C / LeftControl / gamepad B / touch button: football slide tackle on the ground, fast start that eases
--          out over Config.SLIDE_DURATION, a little steering, ends on time / jump (long jump) / leaving the ground /
--          hitting a wall / dash. Cooldown Config.SLIDE_COOLDOWN after it ends, no bar anywhere.
--   A dash or slide pressed up to Stats.INPUT_BUFFER early still fires; anything else is ignored.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)
local Net = require(Shared.Net)
local Body = require(Shared.Movement.Body)
local CameraFx = require(Shared.Movement.CameraFx)
local Stats = require(Shared.Movement.Stats)

local JumpAssist = require(script.Parent.JumpAssist)
local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)

type Rig = Rigs.Rig

local Controller = {}

local player = Players.LocalPlayer

-- Dash speed profile: v(t) = peak * (1 - DROP * t^2), t in 0..1. Its average is (1 - DROP / 3) * peak,
-- so peak = distance / (duration * PROFILE_AREA) covers exactly the dash distance.
local DASH_PROFILE_DROP = 0.55
local DASH_PROFILE_AREA = 1 - DASH_PROFILE_DROP / 3
local AIR_DASH_HOP = 6 -- an air dash never kills the jump: vertical speed becomes at least this
local DASH_TAIL_TIME = 0.15
local DASH_TAIL_START = 1.35 -- x WalkSpeed when the exit tail begins
local DASH_FOV_KICK = 6
local DASH_FOV_TIME = 0.25

local SLIDE_BOOST = 20 -- added to the entry speed
local SLIDE_MAX_SPEED = 44
local SLIDE_END_SPEED = 0.9 -- x WalkSpeed at the end of the slide
local SLIDE_STEER_EARLY = 3.0 -- rad/s during the first 40% of the slide
local SLIDE_STEER_LATE = 1.6
local SLIDE_AIR_END = 0.12 -- airborne this long ends the slide
local SLIDE_BLOCK_RATIO = 0.35 -- moving slower than this share of the commanded speed...
local SLIDE_BLOCK_TIME = 0.1 -- ...for this long = slid into a wall
local LONG_JUMP_CAP = 36 -- horizontal speed kept when jumping out of a slide
local LONG_JUMP_TIME = 0.45
local TAIL_STEER = 3.5
local TAIL_PULL_BACK = -0.3 -- MoveDirection . tail direction below this cancels the tail

local MOVER_ACCEL = 9000 -- MaxForce = AssemblyMass * this (snappy without tunnelling through thin walls)
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
local facing: AlignOrientation? = nil
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

local dashRemote: RemoteEvent
local slideRemote: RemoteEvent

local dash = {
	active = false,
	t = 0,
	dir = Vector3.new(0, 0, -1),
	peak = 0,
	grounded = true,
	endsAt = 0,
}
local slide = {
	active = false,
	t = 0,
	dir = Vector3.new(0, 0, -1),
	speed0 = 0,
	speedEnd = 0,
	air = 0,
	blocked = 0,
	prevAutoRotate = true,
}
-- Momentum tail after a dash or a slide-jump: keeps (decaying) speed instead of stopping dead.
local tail = {
	active = false,
	t = 0,
	duration = 0,
	dir = Vector3.new(0, 0, -1),
	from = 0,
	to = 0,
	landEnds = false,
}
local slideBufferedUntil = 0
local dashBufferedUntil = 0
local dashReadyAnnounced = true

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

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

local function rotateToward(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local sign = if from:Cross(to).Y >= 0 then 1 else -1
	return CFrame.Angles(0, sign * maxAngle, 0):VectorToWorldSpace(from)
end

-- The floor right under the character (nil in the air). A ray, not FloorMaterial: while the slide lowers the hips
-- the root is still settling and FloorMaterial can flicker to Air.
local function probeFloor(rig: Rig): RaycastResult?
	local reach = Body.rootToFeet(rig.character, rig.humanoid, rig.root) + 1.5
	return workspace:Raycast(rig.root.Position, Vector3.new(0, -reach, 0), floorParams)
end

-- Horizontal velocity of whatever we stand on (moving / spinning platforms carry the dash and the slide).
local function floorVelocity(hit: RaycastResult?): Vector3
	if not hit or not hit.Instance:IsA("BasePart") then
		return Vector3.zero
	end
	local v = (hit.Instance :: BasePart):GetVelocityAtPosition(hit.Position)
	return Vector3.new(v.X, 0, v.Z)
end

local function drive(rig: Rig, dir: Vector3, speed: number, floor: RaycastResult?)
	if not mover then
		return
	end
	local v = dir * speed + floorVelocity(if floor ~= nil then floor else probeFloor(rig))
	mover.PlaneVelocity = Vector2.new(v.X, v.Z)
	mover.MaxForce = rig.root.AssemblyMass * MOVER_ACCEL
	mover.Enabled = true
end

local function releaseMover()
	if mover and not dash.active and not slide.active and not tail.active then
		mover.Enabled = false
	end
end

local function face(dir: Vector3?)
	if not facing then
		return
	end
	if dir then
		facing.CFrame = CFrame.lookAt(Vector3.zero, dir)
		facing.Enabled = true
	else
		facing.Enabled = false
	end
end

local function horizontalSpeed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

---------------------------------------------------------------------------------------------------
-- Momentum tail

local function stopTail()
	if tail.active then
		tail.active = false
		releaseMover()
	end
end

local function startTail(dir: Vector3, from: number, to: number, duration: number, landEnds: boolean)
	tail.active = true
	tail.t = 0
	tail.duration = duration
	tail.dir = dir
	tail.from = from
	tail.to = to
	tail.landEnds = landEnds
end

local function stepTail(rig: Rig, dt: number)
	tail.t += dt
	local want = flat(rig.humanoid.MoveDirection)
	local grounded = isGrounded(rig)
	if
		tail.t >= tail.duration
		or (tail.landEnds and grounded and tail.t > 0.08)
		or (want and want:Dot(tail.dir) < TAIL_PULL_BACK)
	then
		stopTail()
		return
	end
	if want then
		tail.dir = rotateToward(tail.dir, want, TAIL_STEER * dt)
	end
	local u = tail.t / tail.duration
	local speed = tail.from + (tail.to - tail.from) * (1 - (1 - u) * (1 - u))
	drive(rig, tail.dir, speed)
end

---------------------------------------------------------------------------------------------------
-- Dash

local endSlide: (Rig?, string) -> ()

local function finishDash(rig: Rig?, natural: boolean)
	if not dash.active then
		return
	end
	dash.active = false
	State.dashing = false
	if natural and rig and rig.root.Parent then
		local walk = rig.humanoid.WalkSpeed
		startTail(dash.dir, walk * DASH_TAIL_START, walk, DASH_TAIL_TIME, false)
	end
	releaseMover()
	State.fire("DashEnd", rig)
end

local function startDash(rig: Rig)
	local humanoid, root = rig.humanoid, rig.root
	local now = os.clock()
	local dir = flat(humanoid.MoveDirection) or flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local grounded = isGrounded(rig)
	if slide.active then
		endSlide(rig, "dash")
	end
	stopTail()
	if not grounded then
		State.airDashUsed = true
		-- Plane mode keeps gravity, so the jump arc continues; give it a small hop instead of cutting it.
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, AIR_DASH_HOP), v.Z)
	end

	local cooldown = Stats.dashCooldown(player)
	State.dashCooldown = cooldown
	State.dashReadyAt = now + cooldown
	State.dashing = true
	dashReadyAnnounced = false
	dashBufferedUntil = 0

	dash.active = true
	dash.t = 0
	dash.dir = dir
	dash.grounded = grounded
	dash.endsAt = now + Config.DASH_DURATION
	dash.peak = Stats.dashDistance(player) / (Config.DASH_DURATION * DASH_PROFILE_AREA)
	drive(rig, dir, dash.peak)
	if humanoid.AutoRotate then
		local pos = root.Position
		root.CFrame = CFrame.lookAt(pos, pos + dir)
	end

	CameraFx.fovKick(DASH_FOV_KICK, DASH_FOV_TIME)
	dashRemote:FireServer(serverNow())
	State.fire("Dash", rig, dir, grounded)
end

local function stepDash(rig: Rig, dt: number)
	if dash.t >= Config.DASH_DURATION then
		finishDash(rig, true)
		return
	end
	local t = math.clamp((dash.t + dt * 0.5) / Config.DASH_DURATION, 0, 1)
	dash.t += dt
	drive(rig, dash.dir, dash.peak * (1 - DASH_PROFILE_DROP * t * t))
end

function Controller.requestDash()
	local rig = current
	if not rig or not canAct(rig) or dash.active then
		return
	end
	local now = os.clock()
	local wait = State.dashReadyAt - now
	if wait > 0 then
		if wait <= Stats.INPUT_BUFFER then
			dashBufferedUntil = State.dashReadyAt + 0.05
		else
			State.fire("DashDenied")
		end
		return
	end
	if not isGrounded(rig) and State.airDashUsed then
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
	face(nil)
	if rig and rig.humanoid.Parent then
		rig.humanoid.AutoRotate = slide.prevAutoRotate
		if rig.root.Parent and reason == "jump" then
			-- Long jump: keep (capped) momentum through the air instead of losing it in a few frames.
			local speed = math.min(horizontalSpeed(rig.root), LONG_JUMP_CAP)
			local walk = rig.humanoid.WalkSpeed
			if speed > walk then
				startTail(slide.dir, speed, walk, LONG_JUMP_TIME, true)
			end
		end
	end
	releaseMover()
	slideRemote:FireServer(false, serverNow())
	State.fire("SlideEnd", rig, reason)
end

local function startSlide(rig: Rig)
	local humanoid, root = rig.humanoid, rig.root
	local dir = flat(humanoid.MoveDirection) or flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local entry = math.max(horizontalSpeed(root), humanoid.WalkSpeed)
	stopTail()

	slide.active = true
	slide.t = 0
	slide.dir = dir
	slide.speed0 = math.min(entry + SLIDE_BOOST, SLIDE_MAX_SPEED)
	slide.speedEnd = humanoid.WalkSpeed * SLIDE_END_SPEED
	slide.air = 0
	slide.blocked = 0
	slide.prevAutoRotate = humanoid.AutoRotate
	State.sliding = true
	slideBufferedUntil = 0

	humanoid.AutoRotate = false
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + dir)
	face(dir)
	-- Hug the floor right away (the pose lowers the hips; do not float down).
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, -6), v.Z)
	drive(rig, dir, slide.speed0)

	slideRemote:FireServer(true, serverNow())
	State.fire("SlideStart", rig, dir)
end

local function stepSlide(rig: Rig, dt: number)
	slide.t += dt
	local t = slide.t / Config.SLIDE_DURATION
	if t >= 1 then
		endSlide(rig, "time")
		return
	end
	local floor = probeFloor(rig)
	if floor or isGrounded(rig) then
		slide.air = 0
	else
		slide.air += dt
		if slide.air > SLIDE_AIR_END then
			endSlide(rig, "air")
			return
		end
	end
	local want = flat(rig.humanoid.MoveDirection)
	if want and want:Dot(slide.dir) > -0.7 then
		local steer = if t < 0.4 then SLIDE_STEER_EARLY else SLIDE_STEER_LATE
		slide.dir = rotateToward(slide.dir, want, steer * dt)
	end
	-- Fast start that eases out: (1 - t)^2 from speed0 down to speedEnd.
	local speed = slide.speedEnd + (slide.speed0 - slide.speedEnd) * (1 - t) * (1 - t)
	if slide.t > 0.12 and horizontalSpeed(rig.root) < speed * SLIDE_BLOCK_RATIO then
		slide.blocked += dt
		if slide.blocked > SLIDE_BLOCK_TIME then
			endSlide(rig, "blocked")
			return
		end
	else
		slide.blocked = 0
	end
	drive(rig, slide.dir, speed, floor)
	face(slide.dir)
end

function Controller.requestSlide()
	local rig = current
	if not rig or not canAct(rig) or slide.active then
		return
	end
	local now = os.clock()
	local wait = State.slideReadyAt - now
	if wait > Stats.INPUT_BUFFER then
		return -- cooling down: ignored (no bar, no nag)
	end
	if wait > 0 or dash.active or not isGrounded(rig) then
		-- Remember the press briefly: it fires the moment the slide is ready / the dash ends / we land.
		slideBufferedUntil = math.max(now + Stats.INPUT_BUFFER, if dash.active then dash.endsAt + 0.05 else 0)
		return
	end
	startSlide(rig)
end

---------------------------------------------------------------------------------------------------
-- Lifecycle

local function cancelAll(rig: Rig?)
	finishDash(rig, false)
	endSlide(rig, "cancel")
	stopTail()
	slideBufferedUntil = 0
	dashBufferedUntil = 0
	if mover then
		mover.Enabled = false
	end
	face(nil)
end

local function attach(rig: Rig)
	if not rig.isLocal then
		return
	end
	current = rig
	dash.active = false
	slide.active = false
	tail.active = false
	slideBufferedUntil = 0
	dashBufferedUntil = 0
	dashReadyAnnounced = true
	State.reset()
	floorParams.FilterDescendantsInstances = { rig.character }
	rig.humanoid.AutoJumpEnabled = false

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
	lv.MaxForce = rig.root.AssemblyMass * MOVER_ACCEL
	lv.Enabled = false
	lv.Parent = rig.root
	rig.trove:add(lv)
	mover = lv

	-- Keeps the root facing the slide direction while AutoRotate is off (no per-frame CFrame writes).
	local align = Instance.new("AlignOrientation")
	align.Name = "MovementFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.Responsiveness = 60
	align.MaxTorque = math.huge
	align.Enabled = false
	align.Parent = rig.root
	rig.trove:add(align)
	facing = align

	JumpAssist.attach(rig)

	rig.trove:connect(rig.humanoid.StateChanged, function(_, new)
		if new ~= Enum.HumanoidStateType.Jumping then
			return
		end
		local longJump = slide.active
		if longJump then
			endSlide(rig, "jump")
		end
		State.fire("Jump", rig, longJump)
	end)
	rig.trove:connect(rig.character:GetAttributeChangedSignal("Stunned"), function()
		if rig.character:GetAttribute("Stunned") == true then
			cancelAll(rig)
		else
			State.airDashUsed = false -- recovering from a hit refunds the air dash (clutch save)
		end
	end)
	rig.trove:add(function()
		if current == rig then
			cancelAll(rig)
			current = nil
			mover = nil
			facing = nil
		end
	end)
end

local function step(dt: number)
	local rig = current
	if not rig or not rig.alive then
		return
	end
	local now = os.clock()
	JumpAssist.step(rig, now)
	if (dash.active or slide.active or tail.active) and not canAct(rig) then
		cancelAll(rig)
		return
	end
	if not dash.active and isGrounded(rig) then
		State.airDashUsed = false
	end
	if not dashReadyAnnounced and now >= State.dashReadyAt then
		dashReadyAnnounced = true
		State.fire("DashReady")
	end

	if dash.active then
		stepDash(rig, dt)
	elseif tail.active then
		stepTail(rig, dt)
	end
	if slide.active then
		stepSlide(rig, dt)
	elseif slideBufferedUntil >= now and not dash.active and now >= State.slideReadyAt and isGrounded(rig) then
		Controller.requestSlide()
	end
	if dashBufferedUntil >= now and now >= State.dashReadyAt and not dash.active then
		dashBufferedUntil = 0
		Controller.requestDash()
	end
end

local function onAction(actionName: string, inputState: Enum.UserInputState, _: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if actionName == Stats.Action.Dash then
		Controller.requestDash()
	else
		Controller.requestSlide()
	end
	-- Sink so the key never reaches anything else (e.g. Shift Lock) while it means "dash" / "slide".
	return Enum.ContextActionResult.Sink
end

function Controller.start()
	dashRemote = Net.event(Stats.Remote.Dash)
	slideRemote = Net.event(Stats.Remote.Slide)

	-- The server tells us when it refused a dash so the dash indicator shows the real wait.
	dashRemote.OnClientEvent:Connect(function(kind: any, remaining: any)
		if kind == "Reject" and Stats.isFinite(remaining) then
			local wait = math.clamp(remaining, 0, Config.DASH_COOLDOWN * 2)
			State.dashCooldown = math.max(State.dashCooldown, wait)
			State.dashReadyAt = math.max(State.dashReadyAt, os.clock() + wait)
			dashReadyAnnounced = false
		end
	end)

	-- No CAS touch buttons: the mobile pad (Shared.Movement.ActionButton) is driven by Hud.
	ContextActionService:BindActionAtPriority(
		Stats.Action.Dash,
		onAction,
		false,
		ACTION_PRIORITY,
		table.unpack(Stats.Keys.Dash)
	)
	ContextActionService:BindActionAtPriority(
		Stats.Action.Slide,
		onAction,
		false,
		ACTION_PRIORITY,
		table.unpack(Stats.Keys.Slide)
	)

	JumpAssist.setCanAct(canAct)
	UserInputService.JumpRequest:Connect(JumpAssist.request)
	Rigs.onAdded(attach)
	RunService.PreSimulation:Connect(step)
end

return Controller
