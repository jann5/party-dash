-- Jump tricks (ported from the legacy JumpFx): every jump plays a random flip / spin with a rainbow
-- trail, and every landing shows a shock ring. Purely visual. The local client plays its own tricks and
-- tells the server through Net remote "Movement_JumpFx", which relays them to everyone else.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Stats = require(Shared.Movement.Stats)

local Effects = require(script.Parent.Effects)
local Rigs = require(script.Parent.Rigs)

type Rig = Rigs.Rig

local JumpFx = {}

local TRICK_TIME = 0.45
-- Keep the count in sync with JUMP_TRICK_COUNT in the server Movement script.
local TRICKS = {
	{ axis = Vector3.new(1, 0, 0), angle = -2 * math.pi, weight = 40 }, -- front flip
	{ axis = Vector3.new(0, 1, 0), angle = 4 * math.pi, weight = 25 }, -- double pirouette
	{ axis = Vector3.new(1, 0, 0), angle = 2 * math.pi, weight = 20 }, -- back flip
	{ axis = Vector3.new(0, 0, 1), angle = 2 * math.pi, weight = 15 }, -- side cartwheel
}

local remote: RemoteEvent

-- The last Transform we wrote and the clean (trick-free) Transform it was based on, so we can tell
-- whether the Animator overwrote the joint this frame.
local lastSet: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local lastBase: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local playing: { [Model]: {} } = setmetatable({}, { __mode = "k" }) :: any
local trails: { [Model]: Trail } = setmetatable({}, { __mode = "k" }) :: any

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

-- R15 rigs may use Motor6D or AnimationConstraint joints; we never touch C0 here (Pose owns that),
-- we rotate the Transform instead, re-based so the spin happens around the HumanoidRootPart.
local function rootJoint(character: Model): Instance?
	local lower = character:FindFirstChild("LowerTorso")
	if lower then
		return lower:FindFirstChild("Root")
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return hrp and hrp:FindFirstChild("RootJoint")
end

local function jointFrame(joint: any): CFrame
	if joint:IsA("Motor6D") then
		return joint.C0
	end
	return joint.Attachment0 and joint.Attachment0.CFrame or CFrame.identity
end

local function buildTrail(rig: Rig)
	local character = rig.character
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
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
	trails[character] = trail
end

local function playTrick(character: Model, index: number)
	local trick = TRICKS[index]
	local joint = rootJoint(character)
	if not trick or not joint or character:GetAttribute("Stunned") == true then
		return
	end
	local token = {}
	playing[character] = token
	local trail = trails[character]
	if trail then
		trail.Enabled = true
	end
	local start = os.clock()
	local conn
	conn = RunService.PreSimulation:Connect(function()
		if playing[character] ~= token or not joint.Parent then
			conn:Disconnect()
			return
		end
		local j = joint :: any
		local current = j.Transform
		local base = (lastSet[joint] == current and lastBase[joint]) or current
		local t = (os.clock() - start) / TRICK_TIME
		-- A knockback stun interrupts the trick cleanly.
		if t >= 1 or character:GetAttribute("Stunned") == true then
			j.Transform = base
			lastSet[joint] = nil
			if trail and trail.Parent then
				trail.Enabled = false
			end
			playing[character] = nil
			conn:Disconnect()
			return
		end
		local eased = if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
		local frame = jointFrame(j)
		local spin = CFrame.fromAxisAngle(trick.axis, trick.angle * eased)
		local value = frame:Inverse() * spin * frame * base
		j.Transform = value
		lastSet[joint] = value
		lastBase[joint] = base
	end)
end

local function attach(rig: Rig)
	buildTrail(rig)
	rig.trove:add(function()
		playing[rig.character] = nil
	end)
	if not rig.isLocal then
		return
	end

	-- Track the hardest fall speed of this airtime to size the landing ring.
	local fallSpeed = 0
	rig.trove:connect(RunService.Heartbeat, function()
		if rig.humanoid.FloorMaterial == Enum.Material.Air then
			fallSpeed = math.max(fallSpeed, -rig.root.AssemblyLinearVelocity.Y)
		end
	end)
	rig.trove:connect(rig.humanoid.StateChanged, function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			local trick = pickTrick()
			playTrick(rig.character, trick)
			remote:FireServer("Jump", trick)
		elseif new == Enum.HumanoidStateType.Landed then
			Effects.land(rig, fallSpeed / 55)
			fallSpeed = 0
			remote:FireServer("Land")
		end
	end)
end

function JumpFx.start()
	remote = Net.event(Stats.Remote.JumpFx)
	Rigs.onAdded(attach)
	remote.OnClientEvent:Connect(function(kind: any, character: any, trick: any)
		local rig = Rigs.get(character)
		if not rig or rig.isLocal then
			return
		end
		if kind == "Jump" and type(trick) == "number" then
			playTrick(rig.character, trick)
		elseif kind == "Land" then
			Effects.land(rig, 1)
		end
	end)
end

return JumpFx
