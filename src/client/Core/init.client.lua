-- Party Dash Core (client): applies knockback to our own character and adds hit juice for everyone
-- (a comic "POW!" pop + sparkle burst + a little camera shake when *we* get hit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Knockback = require(Shared.Knockback)
local Theme = require(Shared.Theme)

local localPlayer = Players.LocalPlayer

Knockback.startClient()

local HIT_WORDS = { "POW!", "BONK!", "WHAM!", "BOOP!", "BAM!", "OOF!" }
local HIT_COLORS = { Theme.Colors.Yellow, Theme.Colors.Pink, Theme.Colors.Cyan, Theme.Colors.Orange }

local function sparkles(root: BasePart)
	local emitter = root:FindFirstChild("PD_HitSparkles") :: ParticleEmitter?
	if not emitter then
		local e = Instance.new("ParticleEmitter")
		e.Name = "PD_HitSparkles"
		e.Enabled = false
		e.Color = ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.White)
		e.LightEmission = 0.6
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(18, 30)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 4
		e.Rotation = NumberRange.new(0, 360)
		e.Parent = root
		emitter = e
	end
	(emitter :: ParticleEmitter):Emit(18)
end

local function popWord(character: Model)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PD_HitWord"
	gui.Size = UDim2.fromScale(5, 2.2)
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.3, 0.3)
	label.Rotation = math.random(-14, 14)
	label.FontFace = Theme.FontFace
	label.Text = HIT_WORDS[math.random(1, #HIT_WORDS)]
	label.TextScaled = true
	label.TextColor3 = HIT_COLORS[math.random(1, #HIT_COLORS)]
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Ink
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Adornee = head
	gui.Parent = head

	local pop = TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
	})
	pop:Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.25), {
			TextTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.1),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end)
	task.delay(0.75, function()
		gui:Destroy()
	end)
end

local function shakeCamera(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local start = os.clock()
	local duration = 0.3
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= duration or not humanoid.Parent then
			conn:Disconnect()
			if humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
			end
			return
		end
		local strength = 0.6 * (1 - t / duration)
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength
		)
	end)
end

local function watchCharacter(player: Player, character: Model)
	character:GetAttributeChangedSignal("Stunned"):Connect(function()
		if character:GetAttribute("Stunned") ~= true then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			sparkles(root)
		end
		popWord(character)
		if player == localPlayer then
			shakeCamera(character)
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
