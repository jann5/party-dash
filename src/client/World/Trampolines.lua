--[[
World client: lobby trampolines (GAME_DESIGN 1.7 #9). The local character is network-owned by this client, so the
launch happens here: touching a "Trampoline" part sets the root's vertical velocity to its LaunchY attribute
(0.3 s cooldown), plays the "Jump" sound and squashes the mat. A light per-tick footprint check backs up Touched
(which can miss a character that is teleported straight onto the mat).

	Trampolines.bind(lobbyModel, trove)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local LobbyWatch = require(script.Parent:WaitForChild("LobbyWatch"))

local Trampolines = {}

local player = Players.LocalPlayer

local COOLDOWN = 0.3
local DEFAULT_LAUNCH = 110
local CHECK_STEP = 1 / 30
local SQUASH = TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

local lastLaunch = 0

type Mat = { part: BasePart, base: CFrame }

local function characterParts(): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return character, nil, nil
	end
	return character, root, humanoid
end

local function launch(mat: Mat)
	local now = os.clock()
	if now - lastLaunch < COOLDOWN then
		return
	end
	local _, root, humanoid = characterParts()
	if not root or not humanoid then
		return
	end
	lastLaunch = now
	local speed = mat.part:GetAttribute("LaunchY")
	speed = if typeof(speed) == "number" and speed > 0 then speed else DEFAULT_LAUNCH
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, speed, v.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	-- boing: the mat dips and springs back
	mat.part.CFrame = mat.base - Vector3.new(0, 0.3, 0)
	TweenService:Create(mat.part, SQUASH, { CFrame = mat.base }):Play()
	Audio.play("Jump", { pitch = 0.9 + math.random() * 0.25 })
end

-- True when the root stands on (or just above) the mat's footprint and is not already flying up.
local function standingOn(mat: Mat, root: BasePart, humanoid: Humanoid): boolean
	local rel = mat.base:PointToObjectSpace(root.Position)
	local size = mat.part.Size
	-- R15 floats the root HipHeight above the floor; R6 (HipHeight 0) stands on 2-stud legs
	local reach = math.max(humanoid.HipHeight, 2) + root.Size.Y / 2 + size.Y / 2 + 0.6
	return math.abs(rel.X) <= size.X / 2 + 0.3
		and math.abs(rel.Z) <= size.Z / 2 + 0.3
		and rel.Y > 0
		and rel.Y <= reach
		and root.AssemblyLinearVelocity.Y < 5
end

function Trampolines.bind(lobby: Model, trove: any)
	local mats: { [BasePart]: Mat } = {}

	LobbyWatch.eachDescendant(lobby, trove, function(inst)
		if inst.Name ~= "Trampoline" or not inst:IsA("BasePart") or mats[inst] then
			return
		end
		local mat: Mat = { part = inst, base = inst.CFrame }
		mats[inst] = mat
		trove:connect(inst.Touched, function(hit)
			local character = player.Character
			if character and hit:IsDescendantOf(character) then
				launch(mat)
			end
		end)
	end)

	local sinceTick = 0
	trove:connect(RunService.Heartbeat, function(dt)
		sinceTick += dt
		if sinceTick < CHECK_STEP then
			return
		end
		sinceTick = 0
		local _, root, humanoid = characterParts()
		if not root or not humanoid then
			return
		end
		for part, mat in mats do
			if part.Parent == nil then
				mats[part] = nil
			elseif standingOn(mat, root, humanoid) then
				launch(mat)
				break
			end
		end
	end)
end

return Trampolines
