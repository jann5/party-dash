--[[
Party Dash: knockback, the ONLY way a hazard hits a player (owned by Core). Minigames call ctx.knockback, which adds
the alive/shield checks and KO credit, then lands here.

Server:
	Knockback.apply(player, direction: Vector3, power: number, stun: number?): boolean
		direction is normalized here (its y component is respected) and an upward lift is added.
		power ~ 60 light shove, 120 strong, 180 launch. stun defaults to Config.KNOCKBACK_STUN (0 = no stun).
		Returns false (and does nothing) for a dead/anchored character or one whose ShieldUntil is in the future.
		Sets the character attribute "Stunned" for the stun time and fires remote "Core_Knockback" to the
		owning client, which owns its character's physics and applies the velocity.

Client (booted by src/client/Core/init.client.lua):
	Knockback.startClient()  -- applies velocity + a short tumble, plays the "Hit" sound and a small camera shake,
	                         -- then stands the character back up smoothly (no teleport, no snap upward).
	Knockback.shake(trauma)  -- camera shake (Shared.Movement.CameraFx when it exists, else a tiny local one)

The server side keeps no state (the stun timer lives in character attributes), so it works the same no matter
which script (or Studio command line) requires it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Knockback = {}

Knockback.REMOTE = "Core_Knockback"
Knockback.MAX_POWER = 400
Knockback.MAX_STUN = 3
Knockback.LIFT_RATIO = 0.4 -- upward lift as a fraction of power
Knockback.MIN_LIFT = 18
Knockback.MAX_LIFT = 75
Knockback.TUMBLE_SPEED = 3 -- rad/s while stunned: a readable roll, not a blender
Knockback.UPRIGHT_TIME = 0.35 -- seconds the upright constraint helps after a stun
Knockback.UPRIGHT_RESPONSIVENESS = 40

local function isFinite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function validVector(v: any): boolean
	return typeof(v) == "Vector3" and isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)
end

-- Final launch velocity: unit(direction) * power + an upward lift (shared by server and client).
function Knockback.velocity(direction: Vector3, power: number): Vector3
	local unit = if direction.Magnitude > 1e-4 then direction.Unit else Vector3.zero
	local lift = math.clamp(power * Knockback.LIFT_RATIO, Knockback.MIN_LIFT, Knockback.MAX_LIFT)
	return unit * power + Vector3.new(0, lift, 0)
end

-- SERVER --------------------------------------------------------------------------------------------

local remote: RemoteEvent? = nil
local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.event(Knockback.REMOTE)
	end
	return remote :: RemoteEvent
end

if RunService:IsServer() then
	getRemote() -- create the remote at require time so clients never wait for it
end

function Knockback.apply(player: Player, direction: Vector3, power: number, stun: number?): boolean
	assert(RunService:IsServer(), "Knockback.apply is server-only")
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	if not validVector(direction) or type(power) ~= "number" or not isFinite(power) then
		return false
	end
	local stunTime = if type(stun) == "number" and isFinite(stun) then stun else Config.KNOCKBACK_STUN
	stunTime = math.clamp(stunTime, 0, Knockback.MAX_STUN)
	power = math.clamp(power, 0, Knockback.MAX_POWER)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local shieldUntil = character:GetAttribute("ShieldUntil")
	if type(shieldUntil) == "number" and shieldUntil > now then
		return false
	end

	if stunTime > 0 then
		local stunnedUntil = math.max(character:GetAttribute("StunnedUntil") or 0, now + stunTime)
		character:SetAttribute("StunnedUntil", stunnedUntil)
		character:SetAttribute("Stunned", true)
		task.delay(stunTime + 0.05, function()
			if character.Parent and (character:GetAttribute("StunnedUntil") or 0) <= workspace:GetServerTimeNow() then
				character:SetAttribute("Stunned", false)
			end
		end)
	end

	-- If the server happens to own the assembly (e.g. right after a teleport), push it here too.
	local ok, owner = pcall(root.GetNetworkOwner, root)
	if ok and owner == nil then
		root.AssemblyLinearVelocity = Knockback.velocity(direction, power)
	end
	getRemote():FireClient(player, direction, power, stunTime)
	return true
end

-- Server safety sweep (started once by Core): clears "Stunned" when its time is up even if the
-- delayed reset above never ran (e.g. apply() was called from a short-lived command thread).
function Knockback.startServer()
	assert(RunService:IsServer(), "Knockback.startServer is server-only")
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = workspace:GetServerTimeNow()
			for _, p in Players:GetPlayers() do
				local character = p.Character
				if
					character
					and character:GetAttribute("Stunned") == true
					and (character:GetAttribute("StunnedUntil") or 0) <= now
				then
					character:SetAttribute("Stunned", false)
				end
			end
		end
	end)
end

-- CLIENT --------------------------------------------------------------------------------------------

-- Yaw the character should face when it stands up (its travel heading, or where it was looking).
local function standHeading(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		local up = root.CFrame.UpVector
		flat = Vector3.new(up.X, 0, up.Z)
	end
	if flat.Magnitude < 0.1 then
		return Vector3.zAxis
	end
	return flat.Unit
end

-- One AlignOrientation per character (created on first use, destroyed with the character).
local function uprightConstraint(root: BasePart): AlignOrientation
	local existing = root:FindFirstChild("PD_Upright")
	if existing and existing:IsA("AlignOrientation") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PD_UprightAttachment"
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "PD_Upright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.Responsiveness = Knockback.UPRIGHT_RESPONSIVENESS
	align.MaxTorque = 1e7
	align.Enabled = false
	align.Parent = root
	return align
end

local function isAirborne(character: Model, humanoid: Humanoid, root: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 1.5
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params) == nil
end

-- Optional camera shake from the Movement piece (Shared.Movement.CameraFx), else a tiny local one.
local cameraFx: any = nil
local shakeUntil = 0
local shakeStrength = 0
local shakeOffset = CFrame.identity
local shaking = false
local SHAKE_TIME = 0.25
local SHAKE_UNDO = "PD_HitShakeUndo"
local SHAKE_APPLY = "PD_HitShake"

local function loadCameraFx(): any
	local movement = Shared:FindFirstChild("Movement")
	local module = movement and movement:FindFirstChild("CameraFx")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.shake) == "function" then
			return result
		end
	end
	return false
end

-- Client: a short camera shake (trauma 0..1). Respects the Set_Shake setting.
function Knockback.shake(trauma: number)
	if Players.LocalPlayer:GetAttribute("Set_Shake") == false then
		return
	end
	if cameraFx == nil then
		cameraFx = loadCameraFx()
	end
	if cameraFx then
		pcall(cameraFx.shake, trauma)
		return
	end
	shakeUntil = os.clock() + SHAKE_TIME
	shakeStrength = if shaking then math.max(shakeStrength, trauma) else trauma
	if shaking then
		return
	end
	shaking = true
	-- The offset is removed before the camera module runs and re-applied after it, so the view never drifts.
	local camera = workspace.CurrentCamera
	RunService:BindToRenderStep(SHAKE_UNDO, Enum.RenderPriority.Camera.Value - 1, function()
		camera.CFrame *= shakeOffset:Inverse()
		shakeOffset = CFrame.identity
	end)
	RunService:BindToRenderStep(SHAKE_APPLY, Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeUntil - os.clock()
		if left <= 0 then
			shaking = false
			RunService:UnbindFromRenderStep(SHAKE_UNDO)
			RunService:UnbindFromRenderStep(SHAKE_APPLY)
			return
		end
		local a = math.rad(1.6) * shakeStrength * (left / SHAKE_TIME)
		shakeOffset = CFrame.Angles((math.random() - 0.5) * a, (math.random() - 0.5) * a, (math.random() - 0.5) * a)
		camera.CFrame *= shakeOffset
	end)
end

function Knockback.startClient()
	assert(RunService:IsClient(), "Knockback.startClient is client-only")
	local Audio = require(Shared.Audio)
	local localPlayer = Players.LocalPlayer
	local token = 0
	local stunEndsAt = 0 -- os.clock() when our current stun should be over (0 = none)

	local function restore(character: Model, humanoid: Humanoid, root: BasePart)
		stunEndsAt = 0
		if not humanoid.Parent or humanoid.Health <= 0 then
			return
		end
		humanoid.PlatformStand = false
		root.AssemblyAngularVelocity = Vector3.zero
		if not root.Anchored then
			-- Rotate back upright in place over a few frames (no position snap that could pop us onto a ledge).
			local align = uprightConstraint(root)
			local myToken = token
			align.CFrame = CFrame.lookAt(Vector3.zero, standHeading(root))
			align.Enabled = true
			task.delay(Knockback.UPRIGHT_TIME, function()
				if token == myToken and align.Parent then
					align.Enabled = false
				end
			end)
		end
		if isAirborne(character, humanoid, root) then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	Net.event(Knockback.REMOTE).OnClientEvent:Connect(function(direction: any, power: any, stun: any)
		if not validVector(direction) or type(power) ~= "number" or type(stun) ~= "number" then
			return
		end
		if not isFinite(power) or not isFinite(stun) then
			return
		end
		power = math.clamp(power, 0, Knockback.MAX_POWER)
		stun = math.clamp(stun, 0, Knockback.MAX_STUN)
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
			return
		end

		token += 1
		local myToken = token
		local upright = root:FindFirstChild("PD_Upright")
		if upright and upright:IsA("AlignOrientation") then
			upright.Enabled = false -- a new hit wins over a recovery in progress
		end
		local velocity = Knockback.velocity(direction, power)
		if stun > 0 then
			humanoid.PlatformStand = true
			-- Light head-over-heels roll in the travel direction.
			local flat = Vector3.new(velocity.X, 0, velocity.Z)
			if flat.Magnitude > 0.5 then
				root.AssemblyAngularVelocity = Vector3.new(0, 1, 0):Cross(flat.Unit) * Knockback.TUMBLE_SPEED
			end
			stunEndsAt = os.clock() + stun
			task.delay(stun, function()
				if token == myToken then
					restore(character, humanoid, root)
				end
			end)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = velocity

		Audio.play("Hit", { pitch = 0.92 + math.random() * 0.16 })
		Knockback.shake(math.clamp(power / 220, 0.2, 0.7))
	end)

	-- Watchdog: never leave the character lying down if a delayed restore got lost.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if
				character
				and humanoid
				and root
				and humanoid.PlatformStand
				and stunEndsAt > 0
				and os.clock() > stunEndsAt + 0.75
			then
				restore(character, humanoid, root)
			end
		end
	end)

	localPlayer.CharacterAdded:Connect(function()
		token += 1
		stunEndsAt = 0
	end)
end

return Knockback
