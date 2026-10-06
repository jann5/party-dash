--!strict
-- Server-rendered economy visuals (replicated to everyone):
--   * BillboardGui "PlayerTag" above every character: name, "Lv 7", gold VIP badge
--   * the equipped cosmetic Trail ("CosmeticTrail" on the HumanoidRootPart)
--   * the equipped WinEffect on round winners (confetti storm / star sparkles / fireworks)
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local C = Theme.Colors

local Visuals = {}

local TAG_NAME = "PlayerTag"
local TRAIL_NAME = "CosmeticTrail"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local POP_SOUND = "rbxasset://sounds/impact_explosion_03.mp3"
local LAUNCH_SOUND = "rbxasset://sounds/action_swim.mp3"

local playerTroves: { [Player]: any } = {}

local function fxFolder(): Folder
	local f = workspace:FindFirstChild("EconomyFx")
	if f and f:IsA("Folder") then
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = "EconomyFx"
	folder.Parent = workspace
	return folder
end

-- Overhead tag -------------------------------------------------------------------------------------

local function pill(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	order: number,
	width: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(width, 1)
	label.BackgroundColor3 = color
	label.BorderSizePixel = 0
	label.FontFace = Theme.FontFace
	label.Text = text
	label.TextColor3 = C.White
	label.TextScaled = true
	label.LayoutOrder = order
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.14, 0)
	pad.PaddingRight = UDim.new(0.14, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = label
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = C.Ink
	border.Thickness = 2
	border.Parent = label
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = C.Ink
	textStroke.Thickness = 1.5
	textStroke.Parent = label
	label.Parent = parent
	return label
end

local function buildTag(player: Player, head: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromScale(6, 1.7) -- studs: shrinks with distance like a real name plate
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.56)
	name.FontFace = Theme.FontFace
	name.Text = player.DisplayName
	name.TextColor3 = C.White
	name.TextScaled = true
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = C.Ink
	nameStroke.Thickness = 2.5
	nameStroke.Parent = name
	name.Parent = gui

	local row = Instance.new("Frame")
	row.Name = "Badges"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, 0.6)
	row.Size = UDim2.fromScale(1, 0.38)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = row
	row.Parent = gui

	pill(row, "VIP", "VIP", Cosmetics.GOLD, 1, 0.24)
	pill(row, "Level", "Lv 1", C.Purple, 2, 0.3)

	gui.Parent = head
	return gui
end

local function refreshTag(player: Player, gui: BillboardGui)
	local row = gui:FindFirstChild("Badges")
	if not row then
		return
	end
	local level = row:FindFirstChild("Level") :: TextLabel?
	local vip = row:FindFirstChild("VIP") :: TextLabel?
	local lv = player:GetAttribute("Level")
	if level then
		level.Text = ("Lv %d"):format(if type(lv) == "number" then lv else 1)
		level.Visible = type(lv) == "number"
	end
	if vip then
		vip.Visible = player:GetAttribute("Pass_VIP") == true
	end
	local name = gui:FindFirstChild("PlayerName") :: TextLabel?
	if name then
		name.TextColor3 = if player:GetAttribute("Pass_VIP") == true then Color3.fromRGB(255, 225, 90) else C.White
	end
end

-- Trail --------------------------------------------------------------------------------------------

local function clearTrail(root: BasePart)
	for _, name in { TRAIL_NAME, "CosmeticTrailTop", "CosmeticTrailBottom", "CosmeticSparkles" } do
		local inst = root:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
end

local function applyTrail(player: Player, root: BasePart)
	clearTrail(root)
	local item = Cosmetics.get(player:GetAttribute("Cos_Trail"))
	if not item or item.slot ~= "Trail" then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "CosmeticTrailTop"
	top.Position = Vector3.new(0, 0.9, 0.35)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "CosmeticTrailBottom"
	bottom.Position = Vector3.new(0, -1.1, 0.35)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = Cosmetics.sequence(item)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.Lifetime = if item.rainbow or item.vip then 0.7 else 0.5
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = if item.vip then 0.6 else 0.3
	trail.LightInfluence = 0.2
	trail.Parent = root

	if item.vip or item.rainbow then
		-- a light sparkle dusting for the premium trails
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "CosmeticSparkles"
		sparkles.Texture = SPARKLE_TEXTURE
		sparkles.Color = Cosmetics.sequence(item)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Lifetime = NumberRange.new(0.5, 0.9)
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = 7
		sparkles.Parent = bottom
	end
end

-- Character decoration ------------------------------------------------------------------------------

local function decorate(player: Player, character: Model, trove: any)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local head = character:WaitForChild("Head", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if player.Character ~= character then
		return
	end
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- our tag replaces it
	end
	if head and head:IsA("BasePart") then
		local tag = buildTag(player, head)
		refreshTag(player, tag)
		local function refresh()
			if tag.Parent then
				refreshTag(player, tag)
			end
		end
		trove:connect(player:GetAttributeChangedSignal("Level"), refresh)
		trove:connect(player:GetAttributeChangedSignal("Pass_VIP"), refresh)
	end
	if root and root:IsA("BasePart") then
		applyTrail(player, root)
		trove:connect(player:GetAttributeChangedSignal("Cos_Trail"), function()
			if root.Parent then
				applyTrail(player, root)
			end
		end)
	end
end

local function onPlayer(player: Player)
	local function onCharacter(character: Model)
		local old = playerTroves[player]
		if old then
			old:clean()
		end
		local trove = Trove.new()
		playerTroves[player] = trove
		task.spawn(decorate, player, character, trove)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

-- Win effects -------------------------------------------------------------------------------------

local function burstEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE_TEXTURE
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Turns emitters on for a moment (property changes replicate reliably, unlike Emit()).
local function pulse(emitters: { ParticleEmitter }, duration: number)
	for _, e in emitters do
		e.Enabled = true
	end
	task.delay(duration, function()
		for _, e in emitters do
			if e.Parent then
				e.Enabled = false
			end
		end
	end)
end

local function sound(parent: Instance, id: string, volume: number, speed: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMaxDistance = 160
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

local function anchorAt(position: Vector3, life: number): Part
	local p = Instance.new("Part")
	p.Name = "WinFx"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.4, 0.4, 0.4)
	p.Position = position
	p.Parent = fxFolder()
	Debris:AddItem(p, life)
	return p
end

local CONFETTI = { C.Pink, C.Yellow, C.Cyan, C.Green, C.Purple, C.Orange, C.Red }

local function confettiStorm(position: Vector3)
	local anchor = anchorAt(position + Vector3.new(0, 4, 0), 6)
	local emitters = {}
	for _, color in CONFETTI do
		table.insert(
			emitters,
			burstEmitter(anchor, {
				Color = ColorSequence.new(color),
				LightEmission = 0.3,
				Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.7),
					NumberSequenceKeypoint.new(0.85, 0.55),
					NumberSequenceKeypoint.new(1, 0),
				}),
				Lifetime = NumberRange.new(2.4, 3.6),
				Speed = NumberRange.new(40, 62),
				SpreadAngle = Vector2.new(70, 70),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -30, 0),
				Drag = 1.8,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-320, 320),
				Rate = 160,
			})
		)
	end
	pulse(emitters, 0.35)
	sound(anchor, POP_SOUND, 0.35, 1.5)
	-- a second, wider wave a beat later
	task.delay(0.6, function()
		if anchor.Parent then
			pulse(emitters, 0.25)
			sound(anchor, POP_SOUND, 0.3, 1.8)
		end
	end)
end

local function starSparkles(position: Vector3)
	local anchor = anchorAt(position, 6)
	local gold = burstEmitter(anchor, {
		Color = ColorSequence.new(Color3.fromRGB(255, 250, 210), Cosmetics.GOLD),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 6, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		Rate = 60,
	})
	local white = burstEmitter(anchor, {
		Color = ColorSequence.new(C.White, C.Cyan),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		Rate = 40,
	})
	local light = Instance.new("PointLight")
	light.Color = Cosmetics.GOLD
	light.Range = 16
	light.Brightness = 0
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 3 }):Play()
	task.delay(2.6, function()
		if light.Parent then
			TweenService:Create(light, TweenInfo.new(1), { Brightness = 0 }):Play()
		end
	end)
	pulse({ gold, white }, 2.8)
	sound(anchor, LAUNCH_SOUND, 0.4, 2.4)
end

local function firework(origin: Vector3, color: Color3, delay: number)
	task.delay(delay, function()
		local rocket = Instance.new("Part")
		rocket.Name = "WinRocket"
		rocket.Anchored = true
		rocket.CanCollide = false
		rocket.CanQuery = false
		rocket.CanTouch = false
		rocket.Material = Enum.Material.Neon
		rocket.Color = color
		rocket.Shape = Enum.PartType.Ball
		rocket.Size = Vector3.new(0.7, 0.7, 0.7)
		rocket.Position = origin
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0.3, 0, 0)
		a0.Parent = rocket
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(-0.3, 0, 0)
		a1.Parent = rocket
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(C.White, color)
		trail.LightEmission = 1
		trail.Lifetime = 0.35
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = rocket
		local burst = burstEmitter(rocket, {
			Color = ColorSequence.new(C.White, color),
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(26, 34),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
			Acceleration = Vector3.new(0, -8, 0),
			Rate = 500,
		})
		rocket.Parent = fxFolder()
		Debris:AddItem(rocket, 4)
		sound(rocket, LAUNCH_SOUND, 0.35, 2.8)

		local apex = origin + Vector3.new(math.random(-8, 8), math.random(20, 28), math.random(-8, 8))
		local rise = TweenService:Create(
			rocket,
			TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = apex }
		)
		rise.Completed:Connect(function()
			if not rocket.Parent then
				return
			end
			rocket.Transparency = 1
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 28
			light.Brightness = 4
			light.Parent = rocket
			TweenService:Create(light, TweenInfo.new(0.9), { Brightness = 0 }):Play()
			pulse({ burst }, 0.12)
			sound(rocket, POP_SOUND, 0.45, 1 + math.random() * 0.4)
		end)
		rise:Play()
	end)
end

local FIREWORK_COLORS = { C.Pink, C.Cyan, C.Yellow, C.Green, C.Purple }

function Visuals.winEffect(player: Player, id: string?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = root.Position
	if id == "WinConfetti" then
		confettiStorm(position)
	elseif id == "WinSparkles" then
		starSparkles(position)
	elseif id == "WinFireworks" then
		for i, color in FIREWORK_COLORS do
			firework(position + Vector3.new(0, 2, 0), color, (i - 1) * 0.35)
		end
	end
end

function Visuals.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local trove = playerTroves[player]
		if trove then
			trove:clean()
			playerTroves[player] = nil
		end
	end)
end

return Visuals
