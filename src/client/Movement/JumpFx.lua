-- Jump tricks (purely visual): every jump plays a quick flip or spin with a rainbow trail (a jump out of a slide,
-- the long jump, always gets the front flip), and every landing shows a shock ring. The flip is a Pose layer on the
-- root joint, never a physics change, so it cannot affect jump height or hit judging. No cartwheels: they would
-- widen the body sideways. The local client plays its own tricks and tells the server through the UNRELIABLE remote
-- "Movement_JumpFx", which relays them to everyone else.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Stats = require(Shared.Movement.Stats)

local Effects = require(script.Parent.Effects)
local Pose = require(script.Parent.Pose)
local Rigs = require(script.Parent.Rigs)
local State = require(script.Parent.State)

type Rig = Rigs.Rig

local JumpFx = {}

local TRICK_TIME = 0.45
local LONG_JUMP_TRICK = 1
-- Keep the count in sync with JUMP_TRICK_COUNT in the server Movement script.
local TRICKS = {
	{ axis = Vector3.xAxis, angle = -2 * math.pi, weight = 40 }, -- front flip
	{ axis = Vector3.yAxis, angle = 4 * math.pi, weight = 30 }, -- double pirouette
	{ axis = Vector3.xAxis, angle = 2 * math.pi, weight = 30 }, -- back flip
}
local LAND_SPEED = 55 -- fall speed that gives a full-size landing ring

local remote: UnreliableRemoteEvent
local trails: { [Rig]: Trail } = {}

local function pickTrick(): number
	local total = 0
	for _, t in TRICKS do
		total += t.weight
	end
	local roll = math.random() * total
	for i, t in TRICKS do
		roll -= t.weight
		if roll <= 0 then
			return i
		end
	end
	return 1
end

local function playTrick(rig: Rig, index: number)
	local trick = TRICKS[index]
	if not trick or not rig.alive then
		return
	end
	Pose.trick(rig, trick.axis, trick.angle, TRICK_TIME)
	if not Pose.isTricking(rig) then
		return -- sliding / stunned: no trick
	end
	local trail = trails[rig]
	if trail then
		trail.Enabled = true
		task.delay(TRICK_TIME, function()
			if trail.Parent and not Pose.isTricking(rig) then
				trail.Enabled = false
			end
		end)
	end
end

local function buildTrail(rig: Rig)
	local torso = rig.character:FindFirstChild("UpperTorso") or rig.character:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local top = rig.trove:add(Instance.new("Attachment"))
	top.Name = "JumpTrailTop"
	top.Position = Vector3.new(-1.1, 0.3, 0)
	top.Parent = torso
	local bottom = rig.trove:add(Instance.new("Attachment"))
	bottom.Name = "JumpTrailBottom"
	bottom.Position = Vector3.new(1.1, 0.3, 0)
	bottom.Parent = torso
	local trail = rig.trove:add(Instance.new("Trail"))
	trail.Name = "JumpTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.3
	trail.LightEmission = 1
	trail.Color = Stats.RAINBOW
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = torso
	trails[rig] = trail
end

local function attach(rig: Rig)
	buildTrail(rig)
	rig.trove:add(function()
		trails[rig] = nil
	end)
	if not rig.isLocal then
		return
	end
	-- The hardest fall speed of this airtime sizes the landing ring.
	local fallSpeed = 0
	rig.trove:connect(RunService.Heartbeat, function()
		if rig.humanoid.FloorMaterial == Enum.Material.Air then
			fallSpeed = math.max(fallSpeed, -rig.root.AssemblyLinearVelocity.Y)
		end
	end)
	rig.trove:connect(rig.humanoid.StateChanged, function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			Effects.land(rig, fallSpeed / LAND_SPEED)
			fallSpeed = 0
			remote:FireServer("Land")
		end
	end)
end

function JumpFx.start()
	remote = Net.unreliable(Stats.Remote.JumpFx)
	Rigs.onAdded(attach)
	-- The Controller reports every local jump (and whether it came out of a slide).
	State.on("Jump", function(rig: Rig, longJump: boolean)
		if not rig or not rig.isLocal then
			return
		end
		local trick = if longJump then LONG_JUMP_TRICK else pickTrick()
		playTrick(rig, trick)
		remote:FireServer("Jump", trick)
	end)
	remote.OnClientEvent:Connect(function(kind: any, character: any, trick: any)
		local rig = Rigs.get(character)
		if not rig or rig.isLocal then
			return
		end
		if kind == "Jump" and type(trick) == "number" then
			playTrick(rig, trick)
		elseif kind == "Land" then
			Effects.land(rig, 1)
		end
	end)
end

return JumpFx
