--!strict
-- King of the Hill: builds the cartoon bat Tool and the server-side swing/bonk effects.
-- The bat is made of welded parts around an invisible Handle; its long axis is the Handle's +Z.
-- Color comes from the Player attribute Cos_BatColor (Economy cosmetic) or the player's round color.
--
-- Cos_BatColor accepts: "#FF5FA0" / "FF5FA0" (hex), a Theme.Colors key ("Pink", "bat_pink", "BatPink"),
-- a BrickColor name ("Really red"), "Rainbow", or a Color3 attribute. ""/missing = round color.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local BatTool = {}

BatTool.TAG_ATTRIBUTE = "KOTH_Bat"

local C = Theme.Colors
local RAINBOW = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(255, 240, 70),
	Color3.fromRGB(80, 230, 110),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(190, 90, 255),
}

-- Sounds bundled with the Roblox client (rbxasset://), so they always load.
local WHOOSH_ID = "rbxasset://sounds/action_swim.mp3"
local BONK_ID = "rbxasset://sounds/action_jump_land.mp3"
local BONK_POP_ID = "rbxasset://sounds/impact_explosion_03.mp3"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function namedColor(raw: string): Color3?
	local key = string.lower(raw):gsub("[%s_%-]", "")
	if string.sub(key, 1, 3) == "bat" and #key > 3 then
		key = string.sub(key, 4)
	end
	for name, color in C do
		if string.lower(name) == key then
			return color
		end
	end
	return nil
end

-- Returns (main color, isRainbow). Falls back to `default` for anything unknown.
function BatTool.parseColor(raw: any, default: Color3): (Color3, boolean)
	if typeof(raw) == "Color3" then
		return raw, false
	end
	if type(raw) ~= "string" or raw == "" then
		return default, false
	end
	local lower = string.lower(raw)
	if lower == "rainbow" or lower == "batrainbow" then
		return RAINBOW[1], true
	end
	local hex = string.match(raw, "^#?(%x%x%x%x%x%x)$")
	if hex then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return color, false
		end
	end
	local named = namedColor(raw)
	if named then
		return named, false
	end
	local okBrick, brick = pcall(BrickColor.new, raw :: any)
	if okBrick and brick.Name == raw then
		return brick.Color, false
	end
	return default, false
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- One welded visual piece. `offset` is relative to the Handle.
local function piece(handle: BasePart, props: { [string]: any }, offset: CFrame): Part
	local p = Instance.new("Part")
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.CFrame = handle.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = handle
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = handle
	return p
end

-- A cylinder lying along the Handle's Z axis.
local function alongZ(z: number): CFrame
	return CFrame.new(0, 0, z) * CFrame.Angles(0, math.pi / 2, 0)
end

local function sound(parent: Instance, name: string, id: string, volume: number, speed: number): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 110
	s.Parent = parent
	return s
end

-- Builds a bat for `player`. `map` is referenced so client code can find the arena the bat belongs to.
function BatTool.build(player: Player, roundColor: Color3, map: Model): Tool
	local color, rainbow = BatTool.parseColor(player:GetAttribute("Cos_BatColor"), roundColor)

	local tool = Instance.new("Tool")
	tool.Name = "Bat"
	tool.ToolTip = "Bonk!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- Hand holds the bat near the knob; the barrel points up/forward in the idle tool pose.
	tool.Grip = CFrame.fromMatrix(Vector3.new(0, 0, -1.7), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
	tool:SetAttribute(BatTool.TAG_ATTRIBUTE, true)
	tool:SetAttribute("Cooldown", 1)
	tool:SetAttribute("LastSwing", 0)

	local mapRef = Instance.new("ObjectValue")
	mapRef.Name = "KOTH_Map"
	mapRef.Value = map
	mapRef.Parent = tool

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.5, 4.8)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	local barrelColor = color
	piece(handle, {
		Name = "Knob",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.85,
		Color = C.Yellow,
	}, CFrame.new(0, 0, -2.35))
	piece(handle, {
		Name = "Grip",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.9, 0.55, 0.55),
		Color = C.Ink,
		Material = Enum.Material.Fabric,
	}, alongZ(-1.35))
	piece(handle, {
		Name = "Taper",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.0, 0.82, 0.82),
		Color = darken(barrelColor, 0.12),
	}, alongZ(-0.05))
	piece(handle, {
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.1, 1.2, 1.2),
		Color = barrelColor,
	}, alongZ(1.4))
	piece(handle, {
		Name = "Tip",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.2,
		Color = barrelColor,
	}, CFrame.new(0, 0, 2.45))
	local stripeColors = if rainbow then { RAINBOW[3], RAINBOW[5] } else { C.White, C.White }
	for i, z in { 0.85, 1.85 } do
		piece(handle, {
			Name = "Stripe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.28, 1.26, 1.26),
			Color = stripeColors[i],
		}, alongZ(z))
	end

	-- Swing trail along the barrel.
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = Vector3.new(0, 0, 0.5)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = Vector3.new(0, 0, 3)
	a1.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	trail.FaceCamera = true
	trail.Lifetime = 0.18
	trail.LightEmission = 0.6
	trail.Color = if rainbow
		then ColorSequence.new({
			ColorSequenceKeypoint.new(0, RAINBOW[1]),
			ColorSequenceKeypoint.new(0.5, RAINBOW[3]),
			ColorSequenceKeypoint.new(1, RAINBOW[5]),
		})
		else ColorSequence.new(C.White, color)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Parent = handle

	sound(handle, "Whoosh", WHOOSH_ID, 0.7, 1.9)
	return tool
end

-- Swing juice on the server (replicates to everyone): whoosh + a short trail.
function BatTool.playSwing(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	if not handle then
		return
	end
	local whoosh = handle:FindFirstChild("Whoosh")
	if whoosh and whoosh:IsA("Sound") then
		whoosh.PlaybackSpeed = 1.75 + math.random() * 0.35
		whoosh:Play()
	end
	local trail = handle:FindFirstChild("SwingTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = true
		task.delay(0.32, function()
			if trail.Parent then
				trail.Enabled = false
			end
		end)
	end
	-- The stock Animate script plays its slash animation when it sees this value.
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)
end

-- Bonk burst at `position`: star sparkles, an expanding shock ring and a cartoon thud.
function BatTool.bonkFx(parent: Instance, position: Vector3, color: Color3)
	local holder = Instance.new("Part")
	holder.Name = "BonkFx"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(position)
	holder.Parent = parent

	local stars = Instance.new("ParticleEmitter")
	stars.Enabled = false
	stars.Texture = SPARKLE_TEXTURE
	stars.Color = ColorSequence.new(C.Yellow, color)
	stars.LightEmission = 0.7
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	stars.Lifetime = NumberRange.new(0.35, 0.65)
	stars.Speed = NumberRange.new(22, 38)
	stars.SpreadAngle = Vector2.new(180, 180)
	stars.Drag = 5
	stars.Rotation = NumberRange.new(0, 360)
	stars.RotSpeed = NumberRange.new(-300, 300)
	stars.Parent = holder
	stars:Emit(26)

	local ring = Instance.new("Part")
	ring.Name = "BonkRing"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = C.White
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = holder
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 9, 9),
		Transparency = 1,
	}):Play()

	local thud = sound(holder, "Bonk", BONK_ID, 1, 1.25 + math.random() * 0.3)
	thud:Play()
	local pop = sound(holder, "BonkPop", BONK_POP_ID, 0.25, 2.2)
	pop:Play()

	Debris:AddItem(holder, 1.5)
end

return BatTool
