--!strict
-- Solo Record confetti: a pooled burst of paper bits simulated on RenderStepped (no per-frame Instance.new).
--   Confetti.init(parent)          -- full-screen Frame host
--   Confetti.burst(origin, count)  -- origin in screen scale, e.g. Vector2.new(0.5, 0.4)
--   Confetti.rain(count)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Confetti = {}

local POOL = 120
local C = Theme.Colors
local COLORS = { C.Yellow, C.Pink, C.Cyan, C.Green, C.Purple, C.Orange, C.White }

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

local host: Frame? = nil
local pieces: { Piece } = {}
local active = 0
local conn: RBXScriptConnection? = nil
local rng = Random.new()

local function step(dt: number)
	local root = host
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
				active -= 1
			else
				p.vy += h * 1.4 * dt
				p.vx *= 1 - 1.5 * dt
				p.vy *= 1 - 0.9 * dt
				p.x += (p.vx + math.sin(p.life * 7 + p.wobble) * h * 0.04) * dt
				p.y += p.vy * dt
				p.rot += p.vr * dt
				local flip = math.abs(math.sin(p.life * 9 + p.wobble))
				local base = h * 0.017
				p.frame.Position = UDim2.fromOffset(p.x, p.y)
				p.frame.Rotation = p.rot
				p.frame.Size = UDim2.fromOffset(base * (0.25 + flip), base * 1.4)
				p.frame.BackgroundTransparency = 1 - math.clamp((p.maxLife - p.life) / 0.4, 0, 1)
			end
		end
	end
	if active <= 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function spawnPiece(x: number, y: number, vx: number, vy: number)
	for _, p in pieces do
		if not p.active then
			p.active = true
			active += 1
			p.x, p.y, p.vx, p.vy = x, y, vx, vy
			p.rot = rng:NextNumber(0, 360)
			p.vr = rng:NextNumber(-540, 540)
			p.life = 0
			p.maxLife = rng:NextNumber(1.6, 2.8)
			p.wobble = rng:NextNumber(0, math.pi * 2)
			p.frame.BackgroundColor3 = COLORS[rng:NextInteger(1, #COLORS)]
			p.frame.Position = UDim2.fromOffset(x, y)
			p.frame.Visible = true
			if not conn then
				conn = RunService.RenderStepped:Connect(step)
			end
			return
		end
	end
end

function Confetti.init(parent: Instance)
	local root = Instance.new("Frame")
	root.Name = "Confetti"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 80
	root.Parent = parent
	host = root
	for _ = 1, POOL do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Visible = false
		f.ZIndex = 80
		f.Parent = root
		table.insert(pieces, {
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
		})
	end
end

function Confetti.burst(origin: Vector2, count: number)
	local root = host
	if not root then
		return
	end
	local size = root.AbsoluteSize
	local h = math.max(size.Y, 1)
	for _ = 1, count do
		local angle = rng:NextNumber(-math.pi * 0.95, -math.pi * 0.05)
		local speed = rng:NextNumber(0.6, 1.5) * h
		spawnPiece(origin.X * size.X, origin.Y * size.Y, math.cos(angle) * speed, math.sin(angle) * speed)
	end
end

function Confetti.rain(count: number)
	local root = host
	if not root then
		return
	end
	local size = root.AbsoluteSize
	for _ = 1, count do
		spawnPiece(rng:NextNumber(0, size.X), rng:NextNumber(-size.Y * 0.3, -10), rng:NextNumber(-60, 60), 0)
	end
end

return Confetti
