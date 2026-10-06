-- Party Dash confetti: pooled colorful paper bits simulated on RenderStepped (no per-frame Instance.new).
--   Confetti.init(screenGui)
--   Confetti.burst(Vector2.new(0.5, 0.5), 60)   -- origin in screen scale
--   Confetti.rain(80)                           -- falls from the top edge
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.Theme)

local Confetti = {}

local POOL_SIZE = 140
local COLORS = {
	Theme.Colors.Yellow,
	Theme.Colors.Pink,
	Theme.Colors.Cyan,
	Theme.Colors.Green,
	Theme.Colors.Purple,
	Theme.Colors.Orange,
	Theme.Colors.White,
}

type Piece = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	rot: number,
	vr: number,
	life: number,
	maxLife: number,
	wobble: number,
	active: boolean,
}

local container: Frame? = nil
local pieces: { Piece } = {}
local activeCount = 0
local conn: RBXScriptConnection? = nil
local rng = Random.new()

local function step(dt: number)
	local root = container
	if not root then
		return
	end
	local size = root.AbsoluteSize
	local h = math.max(size.Y, 1)
	for _, p in pieces do
		if p.active then
			p.life += dt
			if p.life >= p.maxLife or p.y > size.Y + 40 then
				p.active = false
				p.frame.Visible = false
				activeCount -= 1
			else
				p.vy += h * 1.5 * dt -- gravity (relative to screen height)
				p.vx *= 1 - 1.6 * dt -- air drag
				p.vy *= 1 - 0.9 * dt
				p.x += (p.vx + math.sin(p.life * 7 + p.wobble) * h * 0.04) * dt
				p.y += p.vy * dt
				p.rot += p.vr * dt
				p.frame.Position = UDim2.fromOffset(p.x, p.y)
				p.frame.Rotation = p.rot
				-- paper flip: squash the width with a sine
				local flip = math.abs(math.sin(p.life * 9 + p.wobble))
				local base = h * 0.016
				p.frame.Size = UDim2.fromOffset(base * (0.25 + flip), base * 1.4)
				local fade = math.clamp((p.maxLife - p.life) / 0.4, 0, 1)
				p.frame.BackgroundTransparency = 1 - fade
			end
		end
	end
	if activeCount <= 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function ensureRunning()
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

local function grab(): Piece?
	for _, p in pieces do
		if not p.active then
			return p
		end
	end
	return nil
end

local function spawnPiece(x: number, y: number, vx: number, vy: number)
	local p = grab()
	if not p then
		return
	end
	p.active = true
	activeCount += 1
	p.x, p.y, p.vx, p.vy = x, y, vx, vy
	p.rot = rng:NextNumber(0, 360)
	p.vr = rng:NextNumber(-540, 540)
	p.life = 0
	p.maxLife = rng:NextNumber(1.6, 2.6)
	p.wobble = rng:NextNumber(0, math.pi * 2)
	p.frame.BackgroundColor3 = COLORS[rng:NextInteger(1, #COLORS)]
	p.frame.BackgroundTransparency = 0
	p.frame.Position = UDim2.fromOffset(x, y)
	p.frame.Visible = true
end

function Confetti.init(gui: ScreenGui)
	local root = Instance.new("Frame")
	root.Name = "Confetti"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 50
	root.Parent = gui
	container = root
	for i = 1, POOL_SIZE do
		local f = Instance.new("Frame")
		f.Name = "Bit" .. i
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.Visible = false
		f.ZIndex = 50
		f.Parent = root
		pieces[i] = {
			frame = f,
			x = 0,
			y = 0,
			vx = 0,
			vy = 0,
			rot = 0,
			vr = 0,
			life = 0,
			maxLife = 1,
			wobble = 0,
			active = false,
		}
	end
end

-- Explosion of confetti from a point given in screen scale (0..1).
function Confetti.burst(origin: Vector2, count: number?)
	local root = container
	if not root then
		return
	end
	local size = root.AbsoluteSize
	local ox, oy = origin.X * size.X, origin.Y * size.Y
	local h = size.Y
	for _ = 1, count or 50 do
		local angle = rng:NextNumber(-math.pi * 0.95, -math.pi * 0.05) -- mostly upward
		local speed = rng:NextNumber(0.6, 1.5) * h
		spawnPiece(ox, oy, math.cos(angle) * speed, math.sin(angle) * speed)
	end
	ensureRunning()
end

-- Gentle confetti shower from the top edge.
function Confetti.rain(count: number?)
	local root = container
	if not root then
		return
	end
	local size = root.AbsoluteSize
	for _ = 1, count or 60 do
		spawnPiece(
			rng:NextNumber(0, size.X),
			rng:NextNumber(-size.Y * 0.3, 0),
			rng:NextNumber(-0.1, 0.1) * size.Y,
			rng:NextNumber(0, 0.2) * size.Y
		)
	end
	ensureRunning()
end

return Confetti
