-- Procedural body pose for every character on this client:
--   * leans into turns and slightly forward while running
--   * a strong forward lean while dashing
--   * the belly-slide pose (body tilted flat, head first, close to the floor) while sliding
-- It works on the root joint (LowerTorso.Root for R15, HumanoidRootPart.RootJoint for R6; Motor6D C0 or
-- the AnimationConstraint's Attachment0). Every change is applied ADDITIVELY (we remember our own offset
-- and remove it before applying the next one), so other code can still change the joint / HipHeight /
-- CameraOffset and nothing is ever left bent when a character dies or this rig is cleaned up.
--
-- Remote characters are posed from the replicated "Sliding" / "Dashing" attributes; the local one from
-- the predicted State (no latency). Only the local character's HipHeight is lowered (we own its
-- physics, the lowered root then replicates to everyone), which also makes the real hitbox low.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)

type Rig = Rigs.Rig

local Pose = {}

local SLIDE_PITCH = -math.rad(78) -- forward tilt of the whole body while sliding (head first)
local DASH_PITCH = -math.rad(24)
local RUN_PITCH = -math.rad(5)
local MAX_ROLL = math.rad(17)
local ROLL_PER_YAW_RATE = 0.05
local SLIDE_PIVOT_HEIGHT = 0.95 -- hips this high above the floor in the slide pose
local MIN_HIP_HEIGHT = 0.25
local CAMERA_KEEP = 0.55 -- share of the slide drop the camera does NOT follow (keeps it smooth)

type PoseState = {
	joint: Instance,
	lastL: CFrame, -- our current left-multiplied offset on the joint frame
	wroteFrame: CFrame?,
	lastHip: number,
	wroteHip: number?,
	lastCam: Vector3,
	wroteCam: Vector3?,
	slide: number,
	dash: number,
	roll: number,
	pitch: number,
	lastYaw: number?,
}

local poses: { [Rig]: PoseState } = {}

local function findJoint(rig: Rig): Instance?
	local lower = rig.character:FindFirstChild("LowerTorso")
	local joint = lower and lower:FindFirstChild("Root")
	if not joint then
		joint = rig.root:FindFirstChild("RootJoint")
	end
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

local function readFrame(joint: Instance): CFrame?
	if joint:IsA("Motor6D") then
		return joint.C0
	elseif joint:IsA("AnimationConstraint") then
		local a0 = joint.Attachment0
		return a0 and a0.CFrame
	end
	return nil
end

local function writeFrame(joint: Instance, frame: CFrame)
	if joint:IsA("Motor6D") then
		joint.C0 = frame
	elseif joint:IsA("AnimationConstraint") then
		local a0 = joint.Attachment0
		if a0 then
			a0.CFrame = frame
		end
	end
end

local function sameFrame(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3
		and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function isIdentity(cf: CFrame): boolean
	return sameFrame(cf, CFrame.identity)
end

-- Frame-rate independent exponential smoothing.
local function smooth(current: number, target: number, rate: number, dt: number): number
	local value = current + (target - current) * (1 - math.exp(-rate * dt))
	if math.abs(target - value) < 1e-4 then
		return target
	end
	return value
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- The joint frame without our offset (if someone else rewrote the joint, theirs becomes the base).
local function baseFrame(p: PoseState): CFrame?
	local current = readFrame(p.joint)
	if not current then
		return nil
	end
	if p.wroteFrame and sameFrame(current, p.wroteFrame) then
		return p.lastL:Inverse() * current
	end
	p.lastL = CFrame.identity
	return current
end

local function restore(rig: Rig, p: PoseState)
	local base = baseFrame(p)
	if base and p.joint.Parent and not isIdentity(p.lastL) then
		writeFrame(p.joint, base)
	end
	p.lastL = CFrame.identity
	p.wroteFrame = nil
	local humanoid = rig.humanoid
	if rig.isLocal and humanoid.Parent then
		if p.wroteHip and math.abs(humanoid.HipHeight - p.wroteHip) < 1e-3 then
			humanoid.HipHeight -= p.lastHip
		end
		if p.wroteCam and (humanoid.CameraOffset - p.wroteCam).Magnitude < 1e-3 then
			humanoid.CameraOffset -= p.lastCam
		end
	end
	p.lastHip = 0
	p.lastCam = Vector3.zero
end

local function update(rig: Rig, p: PoseState, dt: number)
	local humanoid, root, character = rig.humanoid, rig.root, rig.character
	if not p.joint.Parent or not root.Parent then
		return
	end

	local sliding, dashing
	if rig.isLocal then
		sliding, dashing = State.sliding, State.dashing
	else
		sliding = character:GetAttribute("Sliding") == true
		dashing = character:GetAttribute("Dashing") == true
	end
	local stunned = character:GetAttribute("Stunned") == true or humanoid.PlatformStand
	if stunned then
		sliding, dashing = false, false
	end

	p.slide = smooth(p.slide, if sliding then 1 else 0, if sliding then 16 else 11, dt)
	p.dash = smooth(p.dash, if dashing then 1 else 0, if dashing then 30 else 9, dt)

	-- Turn lean: roll toward the side we are turning to, scaled by speed.
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local yawRate = if p.lastYaw and dt > 0 then wrapAngle(yaw - p.lastYaw) / dt else 0
	p.lastYaw = yaw
	local v = root.AssemblyLinearVelocity
	local speedFrac = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / Config.WALK_SPEED, 0, 1.4)
	local targetRoll = if stunned then 0 else math.clamp(yawRate * ROLL_PER_YAW_RATE * speedFrac, -MAX_ROLL, MAX_ROLL)
	local targetPitch = if stunned then 0 else RUN_PITCH * math.min(speedFrac, 1.2)
	p.roll = smooth(p.roll, targetRoll, 9, dt)
	p.pitch = smooth(p.pitch, targetPitch, 7, dt)

	local upright = 1 - p.slide
	local pitch = (p.pitch + p.dash * DASH_PITCH) * upright + p.slide * SLIDE_PITCH
	local roll = p.roll * upright

	local base = baseFrame(p)
	if not base then
		return
	end

	-- Slide height: lower the hips to SLIDE_PIVOT_HEIGHT above the floor. On R15 most of it is real
	-- (HipHeight, owner only); whatever HipHeight cannot cover is a visual drop of the joint.
	local hipNow = humanoid.HipHeight
	if rig.isLocal and p.wroteHip and math.abs(hipNow - p.wroteHip) < 1e-3 then
		hipNow -= p.lastHip
	else
		p.lastHip = 0
	end
	local legs = if rig.isR15 then hipNow else 2
	local pivotAbove = root.Size.Y / 2 + legs + base.Position.Y
	local physical = 0
	if rig.isR15 then
		physical = math.clamp(pivotAbove - SLIDE_PIVOT_HEIGHT, 0, math.max(0, hipNow - MIN_HIP_HEIGHT))
	end
	local visualDrop = math.max(0, pivotAbove - physical - SLIDE_PIVOT_HEIGHT) * p.slide

	local offset = CFrame.identity
	if math.abs(pitch) > 1e-4 or math.abs(roll) > 1e-4 or visualDrop > 1e-4 then
		local pivot = CFrame.new(base.Position)
		offset = CFrame.new(0, -visualDrop, 0) * pivot * CFrame.Angles(pitch, 0, roll) * pivot:Inverse()
	end
	if not (isIdentity(offset) and isIdentity(p.lastL)) then
		local frame = offset * base
		writeFrame(p.joint, frame)
		p.lastL = offset
		p.wroteFrame = frame
	end

	if rig.isLocal then
		local hipDelta = -physical * p.slide
		local hip = math.max(0, hipNow + hipDelta)
		if math.abs(hipDelta) > 1e-4 or p.lastHip ~= 0 then
			humanoid.HipHeight = hip
			p.wroteHip = hip
			p.lastHip = hip - hipNow
		end

		local camBase = humanoid.CameraOffset
		if p.wroteCam and (camBase - p.wroteCam).Magnitude < 1e-3 then
			camBase -= p.lastCam
		end
		local camDelta = Vector3.new(0, physical * CAMERA_KEEP * p.slide, 0)
		if camDelta.Magnitude > 1e-4 or p.lastCam.Magnitude > 0 then
			local cam = camBase + camDelta
			humanoid.CameraOffset = cam
			p.wroteCam = cam
			p.lastCam = camDelta
		end
	end
end

local function attach(rig: Rig)
	local joint = findJoint(rig)
	if not joint then
		return
	end
	local p: PoseState = {
		joint = joint,
		lastL = CFrame.identity,
		wroteFrame = nil,
		lastHip = 0,
		wroteHip = nil,
		lastCam = Vector3.zero,
		wroteCam = nil,
		slide = 0,
		dash = 0,
		roll = 0,
		pitch = 0,
		lastYaw = nil,
	}
	poses[rig] = p
	rig.trove:add(function()
		poses[rig] = nil
		restore(rig, p)
	end)
end

function Pose.start()
	Rigs.onAdded(attach)
	RunService.PreRender:Connect(function(dt)
		for rig, p in poses do
			if rig.alive then
				local ok, err = pcall(update, rig, p, dt)
				if not ok then
					warn("[Movement] pose update failed:", err)
					poses[rig] = nil
					restore(rig, p)
				end
			end
		end
	end)
end

return Pose
