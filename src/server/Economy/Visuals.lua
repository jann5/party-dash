--!strict
-- Server-rendered economy visuals (replicated to everyone):
--   * the nametag "PlayerTag" over every character: DisplayName, then pills [Lv N] [trophy wins] [flame streak] [VIP]
--   * the equipped cosmetic Trail ("CosmeticTrail" on the HumanoidRootPart) with its particle dusting
--   * the equipped WinEffect on round winners (confetti storm / star sparkles / fireworks)
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Audio = require(ReplicatedStorage.Shared.Audio)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Trove = require(ReplicatedStorage.Shared.Util.Trove)

local C = Theme.Colors

local Visuals = {}

local TAG_NAME = "PlayerTag"
local TRAIL_NAME = "CosmeticTrail"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

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

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Nametag -------------------------------------------------------------------------------------------
-- Sized in studs (shrinks with distance) plus a small pixel floor with the same aspect ratio, so far tags stay
-- readable and every child can be laid out in scale. Pill widths are computed from their text length.
local TAG_W, TAG_H = 6.4, 1.6 -- studs
local TAG_FLOOR = 5 -- pixels per stud added on top (keeps the aspect ratio)
local NAME_H = 0.56 -- fraction of the tag height
local ROW_H = 0.4
local UNIT = ROW_H * TAG_H / TAG_W -- one pill-height, as a fraction of the tag width
local CHAR_W = 0.56 -- FredokaOne glyph width in pill-heights
local PAD = 0.32
local ICON = 1.05

local VIP_GOLD = Color3.fromRGB(255, 225, 90)

type Pill = { frame: Frame, label: TextLabel, icon: ImageLabel? }

local function stroke(parent: Instance, thickness: number, border: boolean?)
	make("UIStroke", {
		Color = C.Ink,
		Thickness = thickness,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual,
	}, parent)
end

local function pill(row: Frame, name: string, color: Color3, order: number, icon: string?): Pill
	local frame = make("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.2, 1),
		LayoutOrder = order,
		Visible = false,
	}, row)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215)),
		Rotation = 90,
	}, frame)
	stroke(frame, 1.5, true)
	local image: ImageLabel? = nil
	if icon then
		image = make("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = Assets.icon(icon),
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(0.3, 1.25), -- overflows the pill a little (ART_BIBLE 8.3)
		}, frame)
	end
	local label = make("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		FontFace = Theme.FontFace,
		TextColor3 = C.White,
		TextScaled = true,
		Size = UDim2.fromScale(1, 0.84),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
	}, frame)
	stroke(label, 1.5)
	return { frame = frame, label = label, icon = image }
end

-- Shows/hides a pill and fits its width to the text.
local function setPill(p: Pill, text: string?)
	if not text then
		p.frame.Visible = false
		return
	end
	p.label.Text = text
	local iconW = if p.icon then ICON else 0
	local units = PAD + iconW + #text * CHAR_W + PAD
	p.frame.Size = UDim2.fromScale(units * UNIT, 1)
	if p.icon then
		p.icon.Position = UDim2.fromScale((PAD * 0.4) / units, 0.5)
		p.icon.Size = UDim2.fromScale(ICON / units, 1.25)
	end
	p.label.Position = UDim2.fromScale((PAD + iconW) / units, 0.5)
	p.label.Size = UDim2.fromScale((#text * CHAR_W + PAD * 0.5) / units, 0.84)
	p.frame.Visible = true
end

type Tag = { gui: BillboardGui, name: TextLabel, level: Pill, wins: Pill, streak: Pill, vip: Pill }

local function buildTag(player: Player, head: BasePart): Tag
	local gui = make("BillboardGui", {
		Name = TAG_NAME,
		Adornee = head,
		Size = UDim2.new(TAG_W, TAG_W * TAG_FLOOR, TAG_H, TAG_H * TAG_FLOOR),
		StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0),
		MaxDistance = 60,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
	})
	local name = make("TextLabel", {
		Name = "PlayerName",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, NAME_H),
		FontFace = Theme.FontFace,
		Text = player.DisplayName,
		TextColor3 = C.White,
		TextScaled = true,
	}, gui)
	stroke(name, 2)
	local row = make("Frame", {
		Name = "Pills",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, ROW_H),
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.015, 0),
	}, row)
	local tag: Tag = {
		gui = gui,
		name = name,
		level = pill(row, "Level", C.Blue, 1),
		wins = pill(row, "Wins", C.PanelDeep, 2, "trophy"),
		streak = pill(row, "Streak", C.Orange, 3, "fire_streak"),
		vip = pill(row, "VIP", C.Gold, 4),
	}
	gui.Parent = head
	return tag
end

local function statValue(player: Player, name: string): number?
	local stats = player:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(name)
	return if v and v:IsA("IntValue") then v.Value else nil
end

local function refreshTag(player: Player, tag: Tag)
	if not tag.gui.Parent then
		return
	end
	local vip = player:GetAttribute("Pass_VIP") == true
	tag.name.TextColor3 = if vip then VIP_GOLD else C.White
	local level = player:GetAttribute("Level")
	setPill(tag.level, if type(level) == "number" then ("Lv %d"):format(level) else nil)
	local wins = statValue(player, "Wins")
	setPill(tag.wins, if wins then tostring(wins) else nil)
	local streak = statValue(player, "Streak")
	setPill(tag.streak, if streak and streak >= 2 then tostring(streak) else nil)
	setPill(tag.vip, if vip then "VIP" else nil)
end

-- Trail ---------------------------------------------------------------------------------------------

local function particleProps(item: Cosmetics.Item): { [string]: any }?
	local fx = item.fx
	if fx == "sparkle" then
		return {
			Texture = SPARKLE_TEXTURE,
			Color = ColorSequence.new(C.White, item.color),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
			Rate = 9,
		}
	elseif fx == "spark" then
		return {
			Texture = SPARKLE_TEXTURE,
			Color = Cosmetics.sequence(item),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.3, 0.6),
			Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, -12, 0),
			Rate = 14,
		}
	elseif fx == "bubble" then
		return {
			Texture = Assets.Textures.glow_soft,
			Color = ColorSequence.new(C.White, C.Cyan),
			LightEmission = 0.4,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.6) }),
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 3, 0),
			Rate = 7,
		}
	elseif fx == "ember" then
		return {
			Texture = SPARKLE_TEXTURE,
			Color = ColorSequence.new(C.Yellow, Color3.fromRGB(220, 40, 20)),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(1, 2.5),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, 5, 0),
			Rate = 12,
		}
	elseif fx == "snow" then
		return {
			Texture = Assets.Textures.glow_soft,
			Color = ColorSequence.new(C.White),
			LightEmission = 0.6,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.1) }),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(0.5, 1.2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -3, 0),
			RotSpeed = NumberRange.new(-90, 90),
			Rate = 10,
		}
	end
	return nil
end

local function clearTrail(root: BasePart)
	for _, name in { TRAIL_NAME, "CosmeticTrailTop", "CosmeticTrailBottom" } do
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
	local premium = item.rarity ~= "Common" and item.rarity ~= "Rare"
	local top = make("Attachment", { Name = "CosmeticTrailTop", Position = Vector3.new(0, 0.9, 0.35) }, root)
	local bottom = make("Attachment", { Name = "CosmeticTrailBottom", Position = Vector3.new(0, -1.1, 0.35) }, root)
	make("Trail", {
		Name = TRAIL_NAME,
		Attachment0 = top,
		Attachment1 = bottom,
		Color = Cosmetics.sequence(item),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.6, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) }),
		Lifetime = if premium then 0.75 else 0.5,
		MinLength = 0.05,
		FaceCamera = true,
		LightEmission = if premium then 0.5 else 0.25,
		LightInfluence = 0.2,
	}, root)
	local props = particleProps(item)
	if props then
		props.Name = "CosmeticParticles"
		make("ParticleEmitter", props, bottom)
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
	if root and root:IsA("BasePart") then
		applyTrail(player, root)
		trove:connect(player:GetAttributeChangedSignal("Cos_Trail"), function()
			if root.Parent then
				applyTrail(player, root)
			end
		end)
	end
	if not (head and head:IsA("BasePart")) then
		return
	end
	local tag = buildTag(player, head)
	trove:add(tag.gui)
	local function refresh()
		refreshTag(player, tag)
	end
	refresh()
	trove:connect(player:GetAttributeChangedSignal("Level"), refresh)
	trove:connect(player:GetAttributeChangedSignal("Pass_VIP"), refresh)
	-- wins + win streak live in Core's leaderstats
	local stats = player:WaitForChild("leaderstats", 10)
	for _, name in { "Wins", "Streak" } do
		local v = stats and stats:WaitForChild(name, 10)
		if not (v and v:IsA("IntValue")) or player.Character ~= character then
			continue
		end
		trove:connect(v.Changed, refresh)
	end
	refresh()
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
	local e = make("ParticleEmitter", props)
	e.Texture = SPARKLE_TEXTURE
	e.Enabled = false
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

local function anchorAt(position: Vector3, life: number): Part
	local p = make("Part", {
		Name = "WinFx",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.4, 0.4, 0.4),
		Position = position,
	}, fxFolder())
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
	Audio.at("Hit", anchor, { volume = 0.35, pitch = 1.5 })
	-- a second, wider wave a beat later
	task.delay(0.6, function()
		if anchor.Parent then
			pulse(emitters, 0.25)
			Audio.at("Hit", anchor, { volume = 0.3, pitch = 1.8 })
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
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2,
		Rate = 40,
	})
	local light = make("PointLight", { Color = Cosmetics.GOLD, Range = 16, Brightness = 0 }, anchor)
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 3 }):Play()
	task.delay(2.6, function()
		if light.Parent then
			TweenService:Create(light, TweenInfo.new(1), { Brightness = 0 }):Play()
		end
	end)
	pulse({ gold, white }, 2.8)
	Audio.at("WheelWin", anchor, { volume = 0.35 })
end

local function firework(origin: Vector3, color: Color3, delay: number)
	task.delay(delay, function()
		local rocket = make("Part", {
			Name = "WinRocket",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Material = Enum.Material.Neon,
			Color = color,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7),
			Position = origin,
		})
		local a0 = make("Attachment", { Position = Vector3.new(0.3, 0, 0) }, rocket)
		local a1 = make("Attachment", { Position = Vector3.new(-0.3, 0, 0) }, rocket)
		make("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			Color = ColorSequence.new(C.White, color),
			LightEmission = 1,
			Lifetime = 0.35,
			FaceCamera = true,
			Transparency = NumberSequence.new(0, 1),
		}, rocket)
		local burst = burstEmitter(rocket, {
			Color = ColorSequence.new(C.White, color),
			LightEmission = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(26, 34),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 3,
			Acceleration = Vector3.new(0, -8, 0),
			Rate = 500,
		})
		rocket.Parent = fxFolder()
		Debris:AddItem(rocket, 4)
		Audio.at("Dash", rocket, { volume = 0.3, pitch = 1.6 })

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
			local light = make("PointLight", { Color = color, Range = 28, Brightness = 4 }, rocket)
			TweenService:Create(light, TweenInfo.new(0.9), { Brightness = 0 }):Play()
			pulse({ burst }, 0.12)
			Audio.at("Explosion", rocket, { volume = 0.3, pitch = 1.3 + math.random() * 0.3 })
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
