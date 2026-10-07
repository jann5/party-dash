--[[
Party Dash Core (client): draws the remote Core_Fx (kind, position) the server sends to the round audience.
	"splash"  white foam disc growing 2 -> 10 studs + 40 droplets + the Splash sound (ART_BIBLE 5.2)
	"poof"    small cartoon puff of white balls (knocked out on the map, revive pop)
	"boom"    neon burst White -> Orange, smoke cubes, sparks, Explosion sound, camera shake nearby (ART_BIBLE 7.5)
	"ko"      hit_star burst where an attacker got a knock-out credit
Parts and billboards come from small pools; particles come from one emitter per effect that is moved to each event
and emitted (emitted particles stay in world space), so nothing is created per frame and nothing leaks.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Audio = require(Shared.Audio)
local Knockback = require(Shared.Knockback)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)

local Fx = {}

local FOAM = Color3.fromRGB(235, 250, 255)
local DROPLET = Color3.fromRGB(150, 225, 255)
local PUFF = Color3.fromRGB(246, 246, 252)
local PUFF_SHADE = Color3.fromRGB(214, 218, 232)
local SMOKE = Color3.fromRGB(60, 60, 70)
local POOL_LIMIT = 24
local BOOM_SHAKE_RADIUS = 30

local folder: Folder
local holder: Part
local emitters: { [string]: { attachment: Attachment, emitter: ParticleEmitter } } = {}

local function tween(
	instance: Instance,
	seconds: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	dir: Enum.EasingDirection?
)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

-- A free list of reusable instances. give() parks the item (Parent = nil) for the next take().
local function pool(make: () -> Instance)
	local free: { Instance } = {}
	return {
		take = function(): any
			return table.remove(free) or make()
		end,
		give = function(item: Instance)
			if #free >= POOL_LIMIT then
				item:Destroy()
				return
			end
			item.Parent = nil
			table.insert(free, item)
		end,
	}
end

local function fxPart(shape: Enum.PartType, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local rings = pool(function()
	local ring = fxPart(Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
	ring.Name = "SplashRing"
	ring.Color = FOAM
	return ring
end)
local balls = pool(function()
	local ball = fxPart(Enum.PartType.Ball, Enum.Material.SmoothPlastic)
	ball.Name = "Puff"
	return ball
end)
local cubes = pool(function()
	local cube = fxPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	cube.Name = "Smoke"
	cube.Color = SMOKE
	return cube
end)
local flashes = pool(function()
	local flash = fxPart(Enum.PartType.Ball, Enum.Material.Neon)
	flash.Name = "BoomFlash"
	return flash
end)
local stars = pool(function()
	local attachment = Instance.new("Attachment")
	attachment.Name = "KoStar"
	local gui = Instance.new("BillboardGui")
	gui.Name = "Star"
	gui.Size = UDim2.fromScale(7, 7)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = attachment
	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.Image = Assets.icon("hit_star")
	image.Parent = gui
	Instance.new("UIScale").Parent = image
	gui.Parent = attachment
	return attachment
end)

local function newEmitter(name: string, props: { [string]: any })
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = attachment
	attachment.Parent = holder
	emitters[name] = { attachment = attachment, emitter = emitter }
end

local function emit(name: string, position: Vector3, count: number)
	local e = emitters[name]
	e.attachment.WorldPosition = position
	e.emitter:Emit(count)
end

local function setup()
	folder = Instance.new("Folder")
	folder.Name = "PD_CoreFx"
	folder.Parent = workspace
	holder = fxPart(Enum.PartType.Block, Enum.Material.SmoothPlastic)
	holder.Name = "EmitterHolder"
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(0, -400, 0)
	holder.Parent = folder

	local soft = Assets.Textures.glow_soft
	newEmitter("Droplets", {
		Texture = soft,
		Color = ColorSequence.new(Theme.Colors.White, DROPLET),
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.6, 0.9),
		Speed = NumberRange.new(18, 28),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -90, 0),
		LightEmission = 0.15,
	})
	newEmitter("Sparks", {
		Texture = soft,
		Color = ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.Orange),
		Size = NumberSequence.new(0.9, 0),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(22, 40),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		LightEmission = 0.7,
	})
	newEmitter("Twinkles", {
		Texture = soft,
		Color = ColorSequence.new(Theme.Colors.White, Theme.Colors.Yellow),
		Size = NumberSequence.new(0.7, 0),
		Lifetime = NumberRange.new(0.3, 0.55),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		LightEmission = 0.5,
	})
end

-- Effects -------------------------------------------------------------------------------------------

function Fx.splash(position: Vector3)
	local ring = rings.take()
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.Transparency = 0.2
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = folder
	tween(ring, 0.5, { Size = Vector3.new(0.2, 10, 10), Transparency = 1 })
	task.delay(0.55, rings.give, ring)
	emit("Droplets", position + Vector3.new(0, 0.3, 0), 40)
	Audio.at("Splash", position)
end

function Fx.poof(position: Vector3)
	for i = 1, 6 do
		local ball = balls.take()
		local angle = (i / 6) * math.pi * 2 + math.random() * 0.6
		local offset = Vector3.new(math.cos(angle) * 1.4, math.random() * 1.6, math.sin(angle) * 1.4)
		local size = 1.8 + math.random() * 1.4
		ball.Color = if i % 2 == 0 then PUFF else PUFF_SHADE
		ball.Transparency = 0
		ball.Size = Vector3.one * 0.4
		ball.CFrame = CFrame.new(position + offset)
		ball.Parent = folder
		tween(
			ball,
			0.18,
			{ Size = Vector3.one * size, CFrame = CFrame.new(position + offset * 1.5) },
			Enum.EasingStyle.Back
		)
		task.delay(0.2, function()
			tween(ball, 0.35, {
				Size = Vector3.one * 0.3,
				Transparency = 1,
				CFrame = CFrame.new(position + offset * 1.8 + Vector3.new(0, 1.6, 0)),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		task.delay(0.6, balls.give, ball)
	end
	emit("Twinkles", position, 12)
	Audio.at("Land", position, { pitch = 1.25, volume = 0.5 })
end

function Fx.boom(position: Vector3)
	local flash = flashes.take()
	flash.Color = Theme.Colors.White
	flash.Transparency = 0
	flash.Size = Vector3.one * 0.5
	flash.CFrame = CFrame.new(position)
	flash.Parent = folder
	tween(flash, 0.25, { Size = Vector3.one * 14, Color = Theme.Colors.Orange })
	task.delay(0.25, function()
		tween(flash, 0.3, { Transparency = 1 })
	end)
	task.delay(0.6, flashes.give, flash)
	for i = 1, 6 do
		local cube = cubes.take()
		local angle = (i / 6) * math.pi * 2
		local start = position + Vector3.new(math.cos(angle) * 2, 0.5, math.sin(angle) * 2)
		local size = 2 + math.random()
		cube.Transparency = 0.1
		cube.Size = Vector3.one * size
		cube.CFrame = CFrame.new(start) * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
		cube.Parent = folder
		local rise = Vector3.new(math.cos(angle) * 3, 7 + math.random() * 4, math.sin(angle) * 3)
		tween(cube, 0.8, {
			Size = Vector3.one * (size * 1.6),
			Transparency = 1,
			CFrame = CFrame.new(start + rise) * CFrame.Angles(math.random() * 3, math.random() * 3, 0),
		})
		task.delay(0.85, cubes.give, cube)
	end
	emit("Sparks", position, 30)
	Audio.at("Explosion", position)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local distance = (root.Position - position).Magnitude
		if distance < BOOM_SHAKE_RADIUS then
			Knockback.shake(0.7 * (1 - distance / BOOM_SHAKE_RADIUS))
		end
	end
end

function Fx.ko(position: Vector3)
	local star = stars.take()
	local gui = star:FindFirstChild("Star") :: BillboardGui
	local image = gui:FindFirstChild("Image") :: ImageLabel
	local scale = image:FindFirstChildOfClass("UIScale") :: UIScale
	star.Parent = holder
	star.WorldPosition = position + Vector3.new(0, 2.5, 0)
	image.ImageTransparency = 0
	image.Rotation = math.random(-20, 20)
	scale.Scale = 0.2
	tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(image, 0.6, { Rotation = image.Rotation + 25 })
	task.delay(0.4, function()
		tween(image, 0.25, { ImageTransparency = 1 })
		tween(scale, 0.25, { Scale = 1.3 })
	end)
	task.delay(0.7, stars.give, star)
	emit("Twinkles", position, 16)
end

local HANDLERS: { [string]: (Vector3) -> () } = {
	splash = Fx.splash,
	poof = Fx.poof,
	boom = Fx.boom,
	ko = Fx.ko,
}

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

function Fx.start()
	setup()
	task.spawn(function()
		Net.event("Core_Fx").OnClientEvent:Connect(function(kind: any, position: any)
			local handler = type(kind) == "string" and HANDLERS[kind]
			if handler and typeof(position) == "Vector3" and finite(position) then
				handler(position)
			end
		end)
	end)
end

return Fx
