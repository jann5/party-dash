-- Animacja skoku: losowa sztuczka (salto, piruet...), tęczowy ślad i fala przy lądowaniu.
-- Każdy klient odgrywa ją sam, a serwer tylko przekazuje, kto skoczył.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JumpFx")
local player = Players.LocalPlayer

local TRICK_TIME = 0.45
local TRICKS = {
	{ axis = Vector3.new(1, 0, 0), angle = -2 * math.pi, weight = 40 }, -- salto w przód
	{ axis = Vector3.new(0, 1, 0), angle = 4 * math.pi, weight = 25 }, -- podwójny piruet
	{ axis = Vector3.new(1, 0, 0), angle = 2 * math.pi, weight = 20 }, -- salto w tył
	{ axis = Vector3.new(0, 0, 1), angle = 2 * math.pi, weight = 15 }, -- gwiazda bokiem
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 70)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
})

-- Ostatnio ustawione Transform i "czyste" Transform bez sztuczki (gdy Animator go nie nadpisze).
local lastSet = setmetatable({}, { __mode = "k" })
local lastBase = setmetatable({}, { __mode = "k" })
local playing = setmetatable({}, { __mode = "k" })

local function pickTrick()
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

-- R15 z nowym systemem stawów ma AnimationConstraint, starsze rigi Motor6D. Obu nie wolno ruszać C0,
-- więc obracamy Transform, przeliczony tak, by obrót był wokół HumanoidRootPart.
local function rootJoint(char)
	local lower = char:FindFirstChild("LowerTorso")
	if lower then
		return lower:FindFirstChild("Root")
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp:FindFirstChild("RootJoint")
end

local function jointFrame(joint)
	if joint:IsA("Motor6D") then
		return joint.C0
	end
	return joint.Attachment0 and joint.Attachment0.CFrame or CFrame.identity
end

local function getTrail(char)
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then
		return nil
	end
	local trail = torso:FindFirstChild("JumpTrail")
	if trail then
		return trail
	end
	local top = Instance.new("Attachment")
	top.Name = "JumpTrailTop"
	top.Position = Vector3.new(-1.1, 0.3, 0)
	top.Parent = torso
	local bottom = Instance.new("Attachment")
	bottom.Name = "JumpTrailBottom"
	bottom.Position = Vector3.new(1.1, 0.3, 0)
	bottom.Parent = torso
	trail = Instance.new("Trail")
	trail.Name = "JumpTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.3
	trail.LightEmission = 1
	trail.Color = RAINBOW
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = torso
	return trail
end

local function playTrick(char, index)
	local trick = TRICKS[index]
	local joint = char and rootJoint(char)
	if not trick or not joint then
		return
	end
	local token = {}
	playing[char] = token
	local trail = getTrail(char)
	if trail then
		trail.Enabled = true
	end
	local start = os.clock()
	local conn
	conn = RunService.PreSimulation:Connect(function()
		if playing[char] ~= token or not joint.Parent then
			conn:Disconnect()
			return
		end
		local current = joint.Transform
		local base = (lastSet[joint] == current and lastBase[joint]) or current
		local t = (os.clock() - start) / TRICK_TIME
		if t >= 1 then
			joint.Transform = base
			lastSet[joint] = nil
			if trail then
				trail.Enabled = false
			end
			playing[char] = nil
			conn:Disconnect()
			return
		end
		local eased = t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
		local frame = jointFrame(joint)
		local spin = CFrame.fromAxisAngle(trick.axis, trick.angle * eased)
		local value = frame:Inverse() * spin * frame * base
		joint.Transform = value
		lastSet[joint] = value
		lastBase[joint] = base
	end)
end

local function landingWave(char)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return
	end
	local legs = hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight
	local feetY = hrp.Position.Y - hrp.Size.Y / 2 - legs
	local wave = Instance.new("Part")
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.CanTouch = false
	wave.CastShadow = false
	wave.Shape = Enum.PartType.Cylinder
	wave.Material = Enum.Material.Neon
	wave.Color = Color3.fromRGB(220, 240, 255)
	wave.Transparency = 0.25
	wave.Size = Vector3.new(0.12, 1.5, 1.5)
	wave.CFrame = CFrame.new(hrp.Position.X, feetY + 0.08, hrp.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	wave.Parent = workspace
	TweenService:Create(wave, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, 9, 9),
		Transparency = 1,
	}):Play()
	Debris:AddItem(wave, 0.4)
end

local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid")
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			local trick = pickTrick()
			playTrick(char, trick)
			remote:FireServer("Jump", trick)
		elseif new == Enum.HumanoidStateType.Landed then
			landingWave(char)
			remote:FireServer("Land")
		end
	end)
end

player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	hookCharacter(player.Character)
end

remote.OnClientEvent:Connect(function(kind, char, trick)
	if typeof(char) ~= "Instance" or char == player.Character then
		return
	end
	if kind == "Jump" then
		playTrick(char, trick)
	elseif kind == "Land" then
		landingWave(char)
	end
end)
