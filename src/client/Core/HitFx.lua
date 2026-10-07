--[[
Party Dash Core (client): hit juice for EVERY character whose "Stunned" attribute turns on (any knockback with a
stun): a hit_star pop over the head and a sparkle burst, plus a 3D hit sound for other players' hits (the victim's
own client plays the 2D "Hit" sound and the camera shake in Shared.Knockback).
One billboard and one emitter per character, created on its first hit and reused; both die with the character.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Assets)
local Audio = require(Shared.Audio)
local Theme = require(Shared.Theme)

local HitFx = {}

local localPlayer = Players.LocalPlayer
local popTokens: { [BillboardGui]: number } = setmetatable({}, { __mode = "k" }) :: any -- latest pop per billboard

local function sparkles(root: BasePart)
	local emitter = root:FindFirstChild("PD_HitSparkles")
	if not (emitter and emitter:IsA("ParticleEmitter")) then
		local e = Instance.new("ParticleEmitter")
		e.Name = "PD_HitSparkles"
		e.Enabled = false
		e.Texture = Assets.Textures.glow_soft
		e.Color = ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.White)
		e.LightEmission = 0.6
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(18, 30)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 4
		e.Parent = root
		emitter = e
	end
	(emitter :: ParticleEmitter):Emit(18)
end

-- The star billboard over the head, reused for every hit on this character.
local function starFor(head: BasePart): (BillboardGui, ImageLabel, UIScale)
	local gui = head:FindFirstChild("PD_HitStar")
	if gui and gui:IsA("BillboardGui") then
		local image = gui:FindFirstChild("Star") :: ImageLabel
		return gui, image, image:FindFirstChildOfClass("UIScale") :: UIScale
	end
	local newGui = Instance.new("BillboardGui")
	newGui.Name = "PD_HitStar"
	newGui.Size = UDim2.fromScale(4.5, 4.5)
	newGui.StudsOffset = Vector3.new(0, 2.8, 0)
	newGui.AlwaysOnTop = true
	newGui.MaxDistance = 140
	newGui.LightInfluence = 0
	newGui.Enabled = false
	newGui.Adornee = head
	local image = Instance.new("ImageLabel")
	image.Name = "Star"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.Image = Assets.icon("hit_star")
	image.Parent = newGui
	local scale = Instance.new("UIScale")
	scale.Parent = image
	newGui.Parent = head
	return newGui, image, scale
end

local function popStar(character: Model)
	local head = character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local gui, image, scale = starFor(head)
	local token = (popTokens[gui] or 0) + 1
	popTokens[gui] = token
	gui.StudsOffset = Vector3.new((math.random() - 0.5) * 1.6, 2.8, 0)
	gui.Enabled = true
	image.ImageTransparency = 0
	image.Rotation = math.random(-18, 18)
	scale.Scale = 0.25
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(0.4, function()
		if popTokens[gui] ~= token then
			return
		end
		TweenService:Create(image, TweenInfo.new(0.25), { ImageTransparency = 1 }):Play()
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 1.25 }):Play()
	end)
	task.delay(0.7, function()
		if popTokens[gui] == token then
			gui.Enabled = false
		end
	end)
end

local function watchCharacter(player: Player, character: Model)
	local stunned = character:GetAttributeChangedSignal("Stunned"):Connect(function()
		if character:GetAttribute("Stunned") ~= true then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			sparkles(root)
			if player ~= localPlayer then
				Audio.at("Hit", root, { volume = 0.35 })
			end
		end
		popStar(character)
	end)
	-- Old characters are not always destroyed on respawn: drop the listener once this one leaves the world.
	local removed
	removed = character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			stunned:Disconnect()
			removed:Disconnect()
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

function HitFx.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
end

return HitFx
