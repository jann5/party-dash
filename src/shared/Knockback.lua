--[[
Party Dash: knockback, the ONLY way a hazard hits a player (owned by Core, P1).

Server:
	Knockback.apply(player, direction: Vector3, power: number, stun: number?)
		direction is normalized here (its y component is respected) and Core adds an upward lift.
		power ~ 60 light shove, 120 strong, 180 launch. stun defaults to Config.KNOCKBACK_STUN (0 = no stun).
		Sets the character attribute "Stunned" for the stun time and fires remote "Core_Knockback" to the
		owning client, which owns its character's physics and applies the velocity.

Client (booted by src/client/Core/init.client.lua):
	Knockback.startClient()  -- listens to "Core_Knockback" and applies velocity + a short tumble stun.

The module keeps no state on the server (the stun timer lives in character attributes), so it works the
same no matter which script (or Studio command line) requires it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local Knockback = {}

Knockback.REMOTE = "Core_Knockback"
Knockback.MAX_POWER = 400
Knockback.MAX_STUN = 3
Knockback.LIFT_RATIO = 0.4 -- upward lift as a fraction of power
Knockback.MIN_LIFT = 18
Knockback.MAX_LIFT = 75
Knockback.TUMBLE_SPEED = 5 -- rad/s while stunned

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

function Knockback.apply(player: Player, direction: Vector3, power: number, stun: number?)
	assert(RunService:IsServer(), "Knockback.apply is server-only")
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end
	if not validVector(direction) or type(power) ~= "number" or not isFinite(power) then
		return
	end
	local stunTime = if type(stun) == "number" and isFinite(stun) then stun else Config.KNOCKBACK_STUN
	stunTime = math.clamp(stunTime, 0, Knockback.MAX_STUN)
	power = math.clamp(power, 0, Knockback.MAX_POWER)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
		return
	end

	if stunTime > 0 then
		local now = workspace:GetServerTimeNow()
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

local function uprightCFrame(root: BasePart): CFrame
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		local up = root.CFrame.UpVector
		flat = Vector3.new(up.X, 0, up.Z)
	end
	if flat.Magnitude < 0.1 then
		flat = Vector3.zAxis
	end
	local pos = root.Position + Vector3.new(0, 1.5, 0)
	return CFrame.lookAt(pos, pos + flat.Unit)
end

function Knockback.startClient()
	assert(RunService:IsClient(), "Knockback.startClient is client-only")
	local localPlayer = Players.LocalPlayer
	local token = 0
	local stunEndsAt = 0 -- os.clock() when our current stun should be over (0 = none)

	local function restore(humanoid: Humanoid, root: BasePart)
		stunEndsAt = 0
		if not humanoid.Parent or humanoid.Health <= 0 then
			return
		end
		humanoid.PlatformStand = false
		root.AssemblyAngularVelocity = Vector3.zero
		if root.CFrame.UpVector.Y < 0.9 and not root.Anchored then
			root.CFrame = uprightCFrame(root)
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
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
		if not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
			return
		end

		token += 1
		local myToken = token
		local velocity = Knockback.velocity(direction, power)
		if stun > 0 then
			humanoid.PlatformStand = true
			-- Light head-over-heels tumble in the travel direction.
			local flat = Vector3.new(velocity.X, 0, velocity.Z)
			if flat.Magnitude > 0.5 then
				root.AssemblyAngularVelocity = Vector3.new(0, 1, 0):Cross(flat.Unit) * Knockback.TUMBLE_SPEED
			end
			stunEndsAt = os.clock() + stun
			task.delay(stun, function()
				if token == myToken then
					restore(humanoid, root)
				end
			end)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = velocity
	end)

	-- Watchdog: never leave the character lying down if a delayed restore got lost.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and root and humanoid.PlatformStand and stunEndsAt > 0 and os.clock() > stunEndsAt + 0.75 then
				restore(humanoid, root)
			end
		end
	end)

	localPlayer.CharacterAdded:Connect(function()
		token += 1
		stunEndsAt = 0
	end)
end

return Knockback
