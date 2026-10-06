--!strict
-- Little drawn emblems for the Solo picker cards (built from Frames: no image assets to load or moderate).
--   Emblems.draw(container, id, accent)  -- fills a square container
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
local Ui = require(script.Parent.Ui)

local Emblems = {}

local C = Theme.Colors
local SPIN_INFO = TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)

local function shape(parent: Instance, props: { [string]: any }, round: boolean?): Frame
	local base: { [string]: any } = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		BackgroundColor3 = C.White,
		ZIndex = (parent :: any).ZIndex,
	}
	for k, v in props do
		base[k] = v
	end
	local f = Ui.new("Frame", base)
	f.Parent = parent
	if round then
		Ui.corner(f, UDim.new(0.5, 0))
	end
	return f
end

local function laserTracer(root: Frame)
	local disc = shape(root, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9) }, true)
	disc.BackgroundColor3 = C.Ink
	Ui.stroke(disc, 3, C.White, true)
	local high = shape(disc, {
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.84, 0.1),
		BackgroundColor3 = C.LaserAlt,
		ZIndex = disc.ZIndex + 1,
	}, true)
	Ui.stroke(high, 3, C.LaserAlt:Lerp(C.White, 0.5), true).Transparency = 0.4
	local low = shape(disc, {
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(0.84, 0.1),
		BackgroundColor3 = C.Laser,
		ZIndex = disc.ZIndex + 1,
	}, true)
	Ui.stroke(low, 3, C.Laser:Lerp(C.White, 0.5), true).Transparency = 0.4
	-- a tiny runner jumping the low beam
	shape(disc, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.16, 0.16),
		BackgroundColor3 = C.Yellow,
		ZIndex = disc.ZIndex + 2,
	}, true)
end

local function dodgeball(root: Frame)
	for i = 1, 3 do
		local line = shape(root, {
			Position = UDim2.fromScale(0.16, 0.32 + i * 0.1),
			Size = UDim2.fromScale(0.22 - i * 0.03, 0.05),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.25,
		}, true)
		line.AnchorPoint = Vector2.new(0, 0.5)
	end
	local ball = shape(root, { Position = UDim2.fromScale(0.58, 0.52), Size = UDim2.fromScale(0.74, 0.74) }, true)
	ball.BackgroundColor3 = C.White -- tinted by the gradient
	Ui.gradient(ball, C.Yellow, C.Red, 45)
	Ui.stroke(ball, 3, C.Ink, true)
	local seam = shape(ball, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.07),
		BackgroundColor3 = C.Ink,
		Rotation = -30,
		ZIndex = ball.ZIndex + 1,
	})
	seam.BackgroundTransparency = 0.2
	shape(ball, {
		Position = UDim2.fromScale(0.32, 0.28),
		Size = UDim2.fromScale(0.2, 0.14),
		BackgroundTransparency = 0.35,
		ZIndex = ball.ZIndex + 1,
	}, true)
end

local function holeInTheWall(root: Frame)
	local wall = shape(root, { Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.86, 0.8) })
	wall.BackgroundColor3 = C.White
	Ui.corner(wall, UDim.new(0.14, 0))
	Ui.gradient(wall, C.Cyan, C.Blue)
	Ui.stroke(wall, 3, C.Ink, true)
	local body = shape(wall, {
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromScale(0.3, 0.46),
		BackgroundColor3 = C.Ink,
		ZIndex = wall.ZIndex + 1,
	})
	Ui.corner(body, UDim.new(0.3, 0))
	shape(wall, {
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromScale(0.24, 0.24),
		BackgroundColor3 = C.Ink,
		ZIndex = wall.ZIndex + 1,
	}, true)
end

local function spin(root: Frame)
	local base = shape(root, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9) }, true)
	base.BackgroundColor3 = C.White
	Ui.gradient(base, C.Pink, C.Purple, 45)
	Ui.stroke(base, 3, C.Ink, true)
	local bar = shape(base, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.13),
		BackgroundColor3 = C.Yellow,
		ZIndex = base.ZIndex + 1,
	}, true)
	Ui.stroke(bar, 2.5, C.Ink, true)
	local hub = shape(base, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.26, 0.26),
		BackgroundColor3 = C.White,
		ZIndex = base.ZIndex + 2,
	}, true)
	Ui.stroke(hub, 2.5, C.Ink, true)
	local tw = TweenService:Create(bar, SPIN_INFO, { Rotation = 360 })
	tw:Play()
	bar.Destroying:Connect(function()
		tw:Cancel()
	end)
end

local function random(root: Frame)
	local disc = shape(root, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9) }, true)
	Ui.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.Red),
			ColorSequenceKeypoint.new(0.25, C.Yellow),
			ColorSequenceKeypoint.new(0.5, C.Green),
			ColorSequenceKeypoint.new(0.75, C.Cyan),
			ColorSequenceKeypoint.new(1, C.Purple),
		}),
		Rotation = 45,
		Parent = disc,
	})
	Ui.stroke(disc, 3, C.Ink, true)
	Ui.label("?", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = disc.ZIndex + 1,
		Parent = disc,
	}, 100, 3)
end

local DRAW: { [string]: (Frame) -> () } = {
	LaserTracer = laserTracer,
	Dodgeball = dodgeball,
	HoleInTheWall = holeInTheWall,
	Spin = spin,
	RANDOM = random,
}

function Emblems.draw(container: Frame, id: string, accent: Color3)
	local fn = DRAW[id]
	if fn then
		fn(container)
		return
	end
	-- Unknown minigame: a badge with its initial.
	local disc = shape(container, { Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9) }, true)
	disc.BackgroundColor3 = accent
	Ui.stroke(disc, 3, C.Ink, true)
	Ui.label(string.sub(id, 1, 1), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.62),
		ZIndex = disc.ZIndex + 1,
		Parent = disc,
	}, 100, 3)
end

return Emblems
