--[[
Football slide-tackle pose (brief #11): feet first, torso leaning back, lead (right) leg straight along the ground,
trailing leg tucked under it with the knee bent ~100 deg, trailing-side hand back on the ground, other arm up.

Angles are degrees in the PARENT part's rest frame (X right, Y up, -Z forward), applied as
R = Angles(rx, 0, 0) * Angles(0, 0, rz) * Angles(0, ry, 0) (twist about the limb first):
	+rx swings a hanging limb forward / tilts a torso back; +rz swings a hanging limb toward +X; ry twists the limb.
Limb target:  Transform = C0rot^-1 * R * C0rot (rotation only, so it works for every body scale and for R6's
              rotated joint frames).
Root target:  Transform = C0^-1 * (Drop * Pivot * R * Pivot^-1) * C0, rotating the whole body about the hip line
              and lowering it by `drop` studs (the part of the hip drop HipHeight does not cover physically).
The tables were checked offline against the R6 rig and a default R15 rig: hips ~1.05 (R15) / ~1.4 (R6) above the
floor, head ~1.5 / ~1.0 studs behind the hips, lead foot ~1.95 / ~2.0 studs in front, and no collidable part
(torso, head) gets closer than 0.3 studs to the floor.
]]
local Tackle = {}

export type JointSpec = { joint: string, part: string, rx: number, rz: number, ry: number }

local R15: { JointSpec } = {
	{ joint = "Root", part = "LowerTorso", rx = 58, rz = 8, ry = 0 },
	{ joint = "Waist", part = "UpperTorso", rx = -8, rz = -3, ry = 6 },
	{ joint = "Neck", part = "Head", rx = -32, rz = 0, ry = -6 },
	-- lead leg: straight, ~15 deg below horizontal, toes up (studs showing)
	{ joint = "RightHip", part = "RightUpperLeg", rx = 21, rz = -3, ry = 0 },
	{ joint = "RightKnee", part = "RightLowerLeg", rx = -4, rz = 0, ry = 0 },
	{ joint = "RightAnkle", part = "RightFoot", rx = 24, rz = 0, ry = 0 },
	-- trailing leg: thigh flat on the ground, twisted so the 100 deg knee bend folds the shin under the lead leg
	{ joint = "LeftHip", part = "LeftUpperLeg", rx = 10, rz = -20, ry = 90 },
	{ joint = "LeftKnee", part = "LeftLowerLeg", rx = -100, rz = 0, ry = 0 },
	{ joint = "LeftAnkle", part = "LeftFoot", rx = 0, rz = 0, ry = 0 },
	-- trailing-side hand back on the ground, palm flat
	{ joint = "LeftShoulder", part = "LeftUpperArm", rx = -72, rz = -16, ry = 0 },
	{ joint = "LeftElbow", part = "LeftLowerArm", rx = 10, rz = 0, ry = 0 },
	{ joint = "LeftWrist", part = "LeftHand", rx = -65, rz = 0, ry = 0 },
	-- balance arm forward and up
	{ joint = "RightShoulder", part = "RightUpperArm", rx = 62, rz = 36, ry = 0 },
	{ joint = "RightElbow", part = "RightLowerArm", rx = 35, rz = 0, ry = 0 },
	{ joint = "RightWrist", part = "RightHand", rx = 10, rz = 0, ry = 0 },
}

-- R6 has no knees / elbows: the trailing leg splays out flat instead of tucking.
local R6: { JointSpec } = {
	{ joint = "RootJoint", part = "HumanoidRootPart", rx = 55, rz = 8, ry = 0 },
	{ joint = "Neck", part = "Torso", rx = -34, rz = 0, ry = 0 },
	{ joint = "Right Hip", part = "Torso", rx = 21, rz = -3, ry = 0 },
	{ joint = "Left Hip", part = "Torso", rx = 33, rz = -45, ry = 0 },
	{ joint = "Left Shoulder", part = "Torso", rx = -60, rz = -14, ry = 0 },
	{ joint = "Right Shoulder", part = "Torso", rx = 60, rz = 36, ry = 0 },
}

Tackle.R15 = R15
Tackle.R6 = R6
Tackle.ROOT = { R15 = "Root", R6 = "RootJoint" }

-- Slide hip-line height as a share of the standing hip line: R15 2.0 -> 0.94, R6 2.0 -> 0.8 (its straight trailing
-- leg and support arm need the body a little lower to reach the floor).
Tackle.HIP_LINE_RATIO = { R15 = 0.47, R6 = 0.4 }
Tackle.HIP_LINE_MIN = 0.6
Tackle.HIP_LINE_MAX = 1.25

function Tackle.rotation(spec: JointSpec): CFrame
	return CFrame.Angles(math.rad(spec.rx), 0, 0)
		* CFrame.Angles(0, 0, math.rad(spec.rz))
		* CFrame.Angles(0, math.rad(spec.ry), 0)
end

-- Rotation `rot` (parent rest frame) as a Motor6D / AnimationConstraint Transform for a joint whose frame is `c0`.
function Tackle.limbTransform(c0: CFrame, rot: CFrame): CFrame
	local c0rot = c0.Rotation
	return c0rot:Inverse() * rot * c0rot
end

-- Whole-body Transform: rotate by `rot` about `pivot` (parent space), then lower by `drop` studs.
function Tackle.rootTransform(c0: CFrame, pivot: Vector3, rot: CFrame, drop: number): CFrame
	local p = CFrame.new(pivot)
	local m = CFrame.new(0, -drop, 0) * p * rot * p:Inverse()
	return c0:Inverse() * m * c0
end

-- Slide hip-line height for a body whose standing hip line is `standing` studs above the floor.
function Tackle.hipLine(standing: number, isR15: boolean): number
	local ratio = if isR15 then Tackle.HIP_LINE_RATIO.R15 else Tackle.HIP_LINE_RATIO.R6
	return math.clamp(standing * ratio, Tackle.HIP_LINE_MIN, Tackle.HIP_LINE_MAX)
end

return Tackle
