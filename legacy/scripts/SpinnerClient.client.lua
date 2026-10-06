-- Kręci kijami lokalnie (płynnie) i wykrywa, czy kij trafił naszą postać.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = require(ReplicatedStorage:WaitForChild("SpinShared"))
local hitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Hit")

local player = Players.LocalPlayer
local arena = workspace:WaitForChild("Arena")
local bars = { arena:WaitForChild("Bar1"), arena:WaitForChild("Bar2") }
local hiddenCFrame = CFrame.new(0, Shared.HIDDEN_Y, 0)

local prevAngles = {}
local lastHit = 0

local function sweptHit(barAngle, prevAngle)
	if not player:GetAttribute("InRound") then
		return false
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	local pos = hrp.Position
	local r = Vector2.new(pos.X, pos.Z).Magnitude
	if r > Shared.BAR_HALF_LEN + 1.5 or r < 3 then
		return false
	end
	local legs = hum.RigType == Enum.HumanoidRigType.R6 and 2 or hum.HipHeight
	local feetY = pos.Y - hrp.Size.Y / 2 - legs
	local headY = pos.Y + hrp.Size.Y / 2 + 1.5
	if feetY > Shared.BAR_Y + Shared.BAR_THICK / 2 or headY < Shared.BAR_Y - Shared.BAR_THICK / 2 then
		return false
	end
	-- Sprawdzamy cały łuk przebyty od poprzedniej klatki, żeby szybki kij nie "przeskoczył" gracza.
	local halfWidth = (1.3 + Shared.BAR_THICK / 2) / r
	local d0 = Shared.armDistance(prevAngle, Shared.positionAngle(pos))
	local d1 = d0 + (barAngle - prevAngle)
	return math.min(d0, d1) <= halfWidth and math.max(d0, d1) >= -halfWidth
end

local function knockOut(dir)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return
	end
	local phi = Shared.positionAngle(hrp.Position)
	local outward = Vector3.new(math.cos(phi), 0, -math.sin(phi))
	local tangent = Vector3.new(-math.sin(phi), 0, -math.cos(phi)) * dir
	hum:ChangeState(Enum.HumanoidStateType.Ragdoll)
	hrp.AssemblyLinearVelocity = tangent * 70 + outward * 20 + Vector3.new(0, 45, 0)
	hrp.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
end

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	for i, bar in bars do
		local s = Shared.decode(bar:GetAttribute("State"))
		if s and s.active then
			local a = Shared.angle(s, now)
			bar:PivotTo(Shared.barCFrame(a))
			local prev = prevAngles[i]
			if prev and math.abs(a - prev) < 1 and os.clock() - lastHit > 1 and sweptHit(a, prev) then
				lastHit = os.clock()
				knockOut(s.dir)
				hitRemote:FireServer(i)
			end
			prevAngles[i] = a
		else
			if prevAngles[i] ~= false then
				bar:PivotTo(hiddenCFrame)
			end
			prevAngles[i] = false
		end
	end
end)
