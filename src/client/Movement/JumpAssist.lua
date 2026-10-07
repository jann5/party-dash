-- Jump feel for the local character (brief #3):
--   coyote time  Config.COYOTE_TIME: you can still jump this long after running off a ledge
--   jump buffer  Config.JUMP_BUFFER: a jump pressed this long before landing fires on touchdown
-- One jump per airtime (no double jump). The jump height itself is the stock Humanoid jump, so every minigame's
-- clear heights stay valid. Nothing happens while the Controller says the character cannot act.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Rigs = require(script.Parent.Rigs)

type Rig = Rigs.Rig

local JumpAssist = {}

local AIR_STATES = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local current: Rig? = nil
local canAct: (Rig) -> boolean = function(_rig: Rig)
	return false
end
local lastGroundedAt = -math.huge
local jumpedThisAir = false
local requestedAt = -math.huge
local wasGrounded = true

local function grounded(rig: Rig): boolean
	return rig.humanoid.FloorMaterial ~= Enum.Material.Air and not AIR_STATES[rig.humanoid:GetState()]
end

local function canJump(rig: Rig): boolean
	local humanoid = rig.humanoid
	local power = if humanoid.UseJumpPower then humanoid.JumpPower else humanoid.JumpHeight
	return power > 0 and canAct(rig)
end

local function jump(rig: Rig)
	jumpedThisAir = true
	requestedAt = -math.huge
	rig.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

-- `actCheck` is the Controller's "may the character act" test (alive, not stunned / anchored / frozen).
function JumpAssist.setCanAct(actCheck: (Rig) -> boolean)
	canAct = actCheck
end

function JumpAssist.attach(rig: Rig)
	current = rig
	lastGroundedAt = -math.huge
	jumpedThisAir = false
	requestedAt = -math.huge
	wasGrounded = true
	rig.trove:connect(rig.humanoid.StateChanged, function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			jumpedThisAir = true
			requestedAt = -math.huge
		end
	end)
	rig.trove:add(function()
		if current == rig then
			current = nil
		end
	end)
end

-- UserInputService.JumpRequest (keyboard, touch jump button, gamepad).
function JumpAssist.request()
	local rig = current
	if not rig or not rig.alive then
		return
	end
	local now = os.clock()
	requestedAt = now
	if grounded(rig) or not canJump(rig) then
		return -- on the ground the Humanoid jumps by itself
	end
	local state = rig.humanoid:GetState()
	if
		state == Enum.HumanoidStateType.Freefall
		and not jumpedThisAir
		and now - lastGroundedAt <= Config.COYOTE_TIME
	then
		jump(rig)
	end
end

-- Every PreSimulation step, before dash / slide.
function JumpAssist.step(rig: Rig, now: number)
	if rig ~= current then
		return
	end
	local onGround = grounded(rig)
	if onGround then
		lastGroundedAt = now
		jumpedThisAir = false
		if not wasGrounded and now - requestedAt <= Config.JUMP_BUFFER and not rig.humanoid.Jump and canJump(rig) then
			jump(rig) -- buffered: pressed just before touchdown and already released
		end
	end
	wasGrounded = onGround
end

return JumpAssist
