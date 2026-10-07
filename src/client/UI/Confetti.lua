--!nonstrict
-- Confetti: a pool of paper bits on one UIKit screen, simulated on RenderStepped only while some are flying.
-- Nothing is created per frame. Positions are in screen scale, so it looks the same on every device.
--   Confetti.burst(Vector2.new(0.5, 0.5), 60)   -- explode from a point (screen scale)
--   Confetti.rain(90)                           -- fall from the top edge
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIKit = require(ReplicatedStorage.Shared.UIKit)

local C = UIKit.Style.Colors

local Confetti = {}

local POOL = 120
local COLORS = { C.Yellow, C.Pink, C.Cyan, C.Green, C.Purple, C.Orange, C.Red, C.White }

local root: Frame? = nil
local pieces = {}
local conn: RBXScriptConnection? = nil
local rng = Random.new()

local function ensure()
	if root and root.Parent then
		return
	end
	local _, r = UIKit.screen("PD_Confetti", 64, { fullscreen = true })
	root = r
	pieces = {}
	for i = 1, POOL do
		local f = UIKit.new("Frame", {
			Name = "Bit",
			BorderSizePixel = 0,
			Visible = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(16, 22),
			ZIndex = 5,
			Parent = r,
		})
		pieces[i] = { frame = f, active = false, u = 0, v = 0, vu = 0, vv = 0, rot = 0, vr = 0, life = 0, maxLife = 1 }
	end
end

local function step(dt: number)
	local r = root
	if not r then
		return
	end
	local size = r.AbsoluteSize
	local aspect = size.Y > 0 and size.X / size.Y or 16 / 9
	local flying = 0
	for _, p in pieces do
		if p.active then
			p.life += dt
			if p.life >= p.maxLife or p.v > 1.1 then
				p.active = false
				p.frame.Visible = false
			else
				flying += 1
				-- velocities are in screen heights per second; x is converted to screen widths
				p.vv += 1.5 * dt
				p.vu *= 1 - 1.4 * dt
				p.vv *= 1 - 0.8 * dt
				p.u += (p.vu + math.sin(p.life * 7 + p.rot) * 0.05) / aspect * dt
				p.v += p.vv * dt
				p.frame.Position = UDim2.fromScale(p.u, p.v)
				p.frame.Rotation += p.vr * dt
				local flip = math.abs(math.sin(p.life * 9 + p.rot))
				p.frame.Size = UDim2.fromOffset(16 * (0.25 + flip), 22)
				p.frame.BackgroundTransparency = 1 - math.clamp((p.maxLife - p.life) / 0.4, 0, 1)
			end
		end
	end
	if flying == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function launch(u: number, v: number, vu: number, vv: number)
	for _, p in pieces do
		if not p.active then
			p.active = true
			p.u, p.v, p.vu, p.vv = u, v, vu, vv
			p.rot = rng:NextNumber(0, math.pi * 2)
			p.vr = rng:NextNumber(-540, 540)
			p.life = 0
			p.maxLife = rng:NextNumber(1.6, 2.6)
			p.frame.Rotation = rng:NextNumber(0, 360)
			p.frame.BackgroundColor3 = COLORS[rng:NextInteger(1, #COLORS)]
			p.frame.BackgroundTransparency = 0
			p.frame.Position = UDim2.fromScale(u, v)
			p.frame.Visible = true
			return
		end
	end
end

local function run()
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

-- Explodes `count` bits upward from `origin` (screen scale).
function Confetti.burst(origin: Vector2, count: number?)
	ensure()
	for _ = 1, count or 50 do
		local angle = rng:NextNumber(-math.pi * 0.95, -math.pi * 0.05)
		local speed = rng:NextNumber(0.55, 1.35)
		launch(origin.X, origin.Y, math.cos(angle) * speed, math.sin(angle) * speed)
	end
	run()
end

-- Bits falling from the top edge across the whole width.
function Confetti.rain(count: number?)
	ensure()
	for _ = 1, count or 80 do
		launch(
			rng:NextNumber(0.02, 0.98),
			rng:NextNumber(-0.25, -0.02),
			rng:NextNumber(-0.2, 0.2),
			rng:NextNumber(0.05, 0.4)
		)
	end
	run()
end

return Confetti
