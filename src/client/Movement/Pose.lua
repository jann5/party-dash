-- Procedural body layers for every character on this client. They are written to the joints' .Transform
-- (Motor6D or AnimationConstraint) in RunService.PreSimulation, i.e. AFTER the Animator posed the body and before
-- physics / rendering, so no walk / run / fall track can fight them:
--   lean    a small turn roll and a dash lean (root joint only)
--   tackle  the football slide tackle (Tackle.lua) on every joint: blends in over 0.08 s, out over 0.15 s. The
--           hips drop physically for the local R15 character (Humanoid.HipHeight, so the real hitbox is low and
--           everyone sees it) and visually through the root joint for the rest (R6, the first frames).
--   trick   jump flips (JumpFx)
-- C0 is never written. When a layer goes idle every joint still holding our Transform gets its rest value back (the
-- Animator re-poses animated joints next frame anyway), HipHeight returns to its exact rest value and the camera
-- lift is cleared. The same happens at once on stun, death and respawn.
-- Remote characters are posed from the replicated Sliding / Dashing attributes; the local one from State.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Body = require(Shared.Movement.Body)
local CameraFx = require(Shared.Movement.CameraFx)

local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)
local Tackle = require(script.Parent.Tackle)

type Rig = Rigs.Rig

local Pose = {}

local BLEND_IN = 0.08 -- seconds to the full tackle pose
local BLEND_OUT = 0.15
local BLEND_OUT_JUMP = 0.1 -- jumping out of a slide stands up faster
local MIN_HIP_HEIGHT = 0.3
local CAMERA_KEEP = 0.55 -- share of the physical hip drop the camera does NOT follow (softer dip)
local SLIDE_FOV = 3
local DASH_PITCH = math.rad(-14)
local MAX_ROLL = math.rad(12)
local ROLL_PER_YAW_RATE = 0.05
local FLOOR_PROBE = 6

type JointRef = { inst: Instance, rot: CFrame, wrote: CFrame? }
type Trick = { axis: Vector3, angle: number, start: number, duration: number }
type PoseState = {
	rig: Rig,
	isR15: boolean,
	joints: { JointRef },
	root: JointRef?,
	dirty: boolean,
	touched: boolean, -- some joint may still hold one of our Transforms
	w: number, -- tackle blend 0..1 (linear; eased when applied)
	outTime: number,
	roll: number,
	pitch: number,
	lastYaw: number?,
	trick: Trick?,
	hipRest: number?, -- local R15: HipHeight before we lowered it
	hipWrote: number?,
	camLift: number,
	floorY: number?,
	params: RaycastParams,
}

local poses: { [Rig]: PoseState } = {}

local function isJoint(inst: Instance?): boolean
	return inst ~= nil and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint"))
end

local function frameOf(inst: Instance): CFrame
	if inst:IsA("Motor6D") then
		return inst.C0
	end
	local a0 = (inst :: AnimationConstraint).Attachment0
	return if a0 then a0.CFrame else CFrame.identity
end

local function findJoint(character: Model, spec: Tackle.JointSpec): Instance?
	local part = character:FindFirstChild(spec.part)
	local joint = part and part:FindFirstChild(spec.joint)
	if isJoint(joint) then
		return joint
	end
	for _, d in character:GetDescendants() do
		if d.Name == spec.joint and isJoint(d) then
			return d
		end
	end
	return nil
end

local function resolve(p: PoseState)
	p.dirty = false
	local specs = if p.isR15 then Tackle.R15 else Tackle.R6
	local rootName = if p.isR15 then Tackle.ROOT.R15 else Tackle.ROOT.R6
	table.clear(p.joints)
	p.root = nil
	for _, spec in specs do
		local inst = findJoint(p.rig.character, spec)
		if inst then
			local ref: JointRef = { inst = inst, rot = Tackle.rotation(spec), wrote = nil }
			table.insert(p.joints, ref)
			if spec.joint == rootName then
				p.root = ref
			end
		end
	end
end

-- The joint's Transform this frame without our own leftover (a joint no track animates keeps our last write).
local function baseTransform(ref: JointRef): CFrame
	local t = (ref.inst :: any).Transform
	if ref.wrote and t == ref.wrote then
		return CFrame.identity
	end
	return t
end

local function write(p: PoseState, ref: JointRef, value: CFrame)
	(ref.inst :: any).Transform = value
	ref.wrote = value
	p.touched = true
end

-- Gives every joint that still holds our value its rest Transform back.
local function releaseJoints(p: PoseState)
	if not p.touched then
		return
	end
	p.touched = false
	for _, ref in p.joints do
		if ref.wrote then
			if ref.inst.Parent and (ref.inst :: any).Transform == ref.wrote then
				(ref.inst :: any).Transform = CFrame.identity
			end
			ref.wrote = nil
		end
	end
end

local function releaseHip(p: PoseState)
	local humanoid = p.rig.humanoid
	if p.hipRest and humanoid.Parent and humanoid.Health > 0 then
		humanoid.HipHeight = p.hipRest
	end
	p.hipRest = nil
	p.hipWrote = nil
	if p.camLift ~= 0 then
		p.camLift = 0
		CameraFx.setOffset("slide", nil)
		CameraFx.setFov("slide", nil)
	end
end

local function restore(p: PoseState)
	releaseJoints(p)
	if p.rig.isLocal then
		releaseHip(p)
	end
	p.w = 0
	p.trick = nil
end

-- Root-joint pivot (parent = HumanoidRootPart space): the hip line.
local function pivotOf(p: PoseState, frame: CFrame): Vector3
	if p.isR15 then
		return frame.Position
	end
	local torso = p.rig.character:FindFirstChild("Torso")
	local half = if torso and torso:IsA("BasePart") then torso.Size.Y / 2 else 1
	return frame.Position - Vector3.new(0, half, 0)
end

-- Height of the hip line above the soles when standing.
local function standingHipLine(p: PoseState, pivot: Vector3): number
	local rig = p.rig
	local legs
	if p.isR15 then
		legs = p.hipRest or rig.humanoid.HipHeight
	else
		legs = Body.legLength(rig.character, rig.humanoid)
	end
	return rig.root.Size.Y / 2 + legs + pivot.Y
end

local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

local function slidingNow(rig: Rig): boolean
	if rig.isLocal then
		return State.sliding
	end
	return rig.character:GetAttribute("Sliding") == true
end

local function dashingNow(rig: Rig): boolean
	if rig.isLocal then
		return State.dashing
	end
	return rig.character:GetAttribute("Dashing") == true
end

local function update(p: PoseState, dt: number, now: number)
	local rig = p.rig
	local humanoid, root, character = rig.humanoid, rig.root, rig.character
	if not root.Parent or not humanoid.Parent then
		return
	end
	local stunned = character:GetAttribute("Stunned") == true or humanoid.PlatformStand or humanoid.Health <= 0
	if stunned then
		if p.touched or p.w > 0 or p.trick or p.hipRest then
			restore(p)
		end
		p.roll, p.pitch = 0, 0
		return
	end

	-- Blend weights.
	local sliding = slidingNow(rig)
	if sliding then
		p.w = math.min(1, p.w + dt / BLEND_IN)
		p.outTime = BLEND_OUT
	else
		p.w = math.max(0, p.w - dt / p.outTime)
	end
	local e = ease(p.w)

	-- Lean: roll into turns (scaled by speed), pitch forward while dashing.
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local yawRate = 0
	if p.lastYaw and dt > 0 then
		yawRate = ((yaw - p.lastYaw + math.pi) % (2 * math.pi) - math.pi) / dt
	end
	p.lastYaw = yaw
	local v = root.AssemblyLinearVelocity
	local speedFrac = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / Config.WALK_SPEED, 0, 1.4)
	local targetRoll = math.clamp(yawRate * ROLL_PER_YAW_RATE * speedFrac, -MAX_ROLL, MAX_ROLL)
	local targetPitch = if dashingNow(rig) then DASH_PITCH else 0
	p.roll += (targetRoll - p.roll) * (1 - math.exp(-9 * dt))
	p.pitch += (targetPitch - p.pitch) * (1 - math.exp(-(if targetPitch ~= 0 then 16 else 8) * dt))
	if math.abs(p.roll) < 0.002 then
		p.roll = 0
	end
	if math.abs(p.pitch) < 0.002 then
		p.pitch = 0
	end

	local trick = p.trick
	if trick and (now - trick.start >= trick.duration or sliding) then
		trick = nil
		p.trick = nil
	end

	local leaning = p.roll ~= 0 or p.pitch ~= 0
	if e <= 0 and not leaning and not trick then
		releaseJoints(p)
		if rig.isLocal and p.hipRest then
			releaseHip(p)
		end
		return
	end

	if p.dirty or (e > 0 and #p.joints == 0) or not p.root or not p.root.inst.Parent then
		resolve(p)
	end
	local rootRef = p.root
	if not rootRef then
		return
	end
	local c0 = frameOf(rootRef.inst)
	local pivot = pivotOf(p, c0)

	-- Hip drop: physical for the local R15 body, the rest visual through the root joint.
	local drop = 0
	if e > 0 then
		local standing = standingHipLine(p, pivot)
		local target = Tackle.hipLine(standing, p.isR15)
		if rig.isLocal and p.isR15 then
			if not p.hipRest then
				p.hipRest = humanoid.HipHeight
			elseif p.hipWrote and math.abs(humanoid.HipHeight - p.hipWrote) > 1e-3 then
				p.hipRest += humanoid.HipHeight - p.hipWrote -- the body was rescaled mid-slide (Giant / Tiny)
			end
			local rest = p.hipRest :: number
			local physical = math.clamp(standing - target, 0, math.max(0, rest - MIN_HIP_HEIGHT))
			local hip = rest - physical * e
			humanoid.HipHeight = hip
			p.hipWrote = hip
			local lift = physical * e * CAMERA_KEEP
			if math.abs(lift - p.camLift) > 0.01 then
				p.camLift = lift
				CameraFx.setOffset("slide", Vector3.new(0, lift, 0))
				CameraFx.setFov("slide", SLIDE_FOV * e)
			end
		end
		-- Whatever the root's real height does not cover yet is lowered visually.
		local hit =
			workspace:Raycast(root.Position, Vector3.new(0, -(standing + root.Size.Y / 2 + FLOOR_PROBE), 0), p.params)
		if hit then
			p.floorY = hit.Position.Y
		end
		local pivotY = (root.CFrame * pivot).Y
		local above = if p.floorY then pivotY - p.floorY else standing
		drop = math.clamp(above - target, 0, standing)
	elseif rig.isLocal and p.hipRest then
		releaseHip(p)
	end

	-- Root joint: animation (or rest) -> lean -> tackle -> trick.
	local rootT = baseTransform(rootRef)
	if leaning then
		local pv = CFrame.new(pivot)
		local lean = pv * CFrame.Angles(p.pitch, 0, p.roll) * pv:Inverse()
		rootT = c0:Inverse() * lean * c0 * rootT
	end
	if e > 0 then
		rootT = rootT:Lerp(Tackle.rootTransform(c0, pivot, rootRef.rot, drop), e)
	end
	if trick then
		local u = math.clamp((now - trick.start) / trick.duration, 0, 1)
		local eased = if u < 0.5 then 2 * u * u else 1 - (-2 * u + 2) ^ 2 / 2
		rootT = c0:Inverse() * CFrame.fromAxisAngle(trick.axis, trick.angle * eased) * c0 * rootT
	end
	write(p, rootRef, rootT)

	-- Every other joint: animation (or rest) -> tackle.
	for _, ref in p.joints do
		if ref ~= rootRef and ref.inst.Parent then
			if e > 0 then
				local target = Tackle.limbTransform(frameOf(ref.inst), ref.rot)
				write(p, ref, baseTransform(ref):Lerp(target, e))
			elseif ref.wrote then
				if (ref.inst :: any).Transform == ref.wrote then
					(ref.inst :: any).Transform = CFrame.identity
				end
				ref.wrote = nil
			end
		end
	end
end

local function attach(rig: Rig)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rig.character }
	params.RespectCanCollide = true
	local p: PoseState = {
		rig = rig,
		isR15 = Body.isR15(rig.humanoid),
		joints = {},
		root = nil,
		dirty = true,
		touched = false,
		w = 0,
		outTime = BLEND_OUT,
		roll = 0,
		pitch = 0,
		lastYaw = nil,
		trick = nil,
		hipRest = nil,
		hipWrote = nil,
		camLift = 0,
		floorY = nil,
		params = params,
	}
	poses[rig] = p
	local function markDirty(d: Instance)
		if isJoint(d) then
			p.dirty = true
		end
	end
	rig.trove:connect(rig.character.DescendantAdded, markDirty)
	rig.trove:connect(rig.character.DescendantRemoving, markDirty)
	if rig.isLocal then
		rig.trove:add(State.on("SlideEnd", function(_, reason)
			p.outTime = if reason == "jump" then BLEND_OUT_JUMP else BLEND_OUT
		end))
	end
	rig.trove:add(function()
		poses[rig] = nil
		restore(p)
	end)
end

-- Plays a root-joint flip / spin (JumpFx): `axis` in HumanoidRootPart space, `angle` in radians, eased in-out.
-- It rides on top of a fading tackle pose (the long jump out of a slide), never on an active one.
function Pose.trick(rig: Rig, axis: Vector3, angle: number, duration: number)
	local p = poses[rig]
	if not p or slidingNow(rig) or rig.character:GetAttribute("Stunned") == true then
		return
	end
	p.trick = { axis = axis, angle = angle, start = os.clock(), duration = duration }
end

function Pose.isTricking(rig: Rig): boolean
	local p = poses[rig]
	return p ~= nil and p.trick ~= nil
end

function Pose.start()
	Rigs.onAdded(attach)
	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		for rig, p in poses do
			if rig.alive then
				local ok, err = pcall(update, p, dt, now)
				if not ok then
					warn("[Movement] pose update failed:", err)
					poses[rig] = nil
					pcall(restore, p)
				end
			end
		end
	end)
end

return Pose
