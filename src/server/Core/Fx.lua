-- Party Dash Core: server-side celebration effects (replicated to everyone).
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Fx = {}

local CONFETTI_COLORS = {
	Theme.Colors.Yellow,
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Green,
	Theme.Colors.Purple,
	Theme.Colors.Orange,
}

-- A short confetti fountain above a player's head.
function Fx.confetti(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ConfettiFx"
	attachment.Position = Vector3.new(0, 3, 0)
	for _, color in CONFETTI_COLORS do
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.25
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.8, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Lifetime = NumberRange.new(1.8, 2.8)
		e.Speed = NumberRange.new(28, 45)
		e.SpreadAngle = Vector2.new(55, 55)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -32, 0)
		e.Drag = 1.6
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-260, 260)
		e.Rate = 70
		e.Enabled = true
		e.Parent = attachment
	end
	attachment.Parent = root
	task.delay(0.4, function()
		for _, e in attachment:GetChildren() do
			if e:IsA("ParticleEmitter") then
				e.Enabled = false
			end
		end
	end)
	Debris:AddItem(attachment, 3.5)
end

return Fx
