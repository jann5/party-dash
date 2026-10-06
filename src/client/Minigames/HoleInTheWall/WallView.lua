--[[
Hole in the Wall (client): renders one wall from its server Configuration (map.Walls.WallN).

The server replicates timing only (Telegraph, Enter, Speed, Start, Finish, Dir, Origin) plus the hole
layout, so every client moves its wall with workspace:GetServerTimeNow() and stays in sync with the
server's pass/hit logic without replicating a single CFrame.

	local view = WallView.new(config, parent)  -- nil if the config is malformed
	view:update(now)        -- move (BulkMoveTo), rise/sink animation, telegraph pulse; false when finished
	view:release()          -- the server removed the wall: sink into the void, then finish
	view:kick()             -- impact wobble
	view:destroy()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local WallView = {}
WallView.__index = WallView

-- Hole type code -> outline color + label (green = run, yellow = jump, cyan = slide).
WallView.HOLE_STYLE = {
	N = { color = Theme.Colors.Green, label = "RUN!" },
	H = { color = Theme.Colors.Yellow, label = "JUMP!" },
	L = { color = Theme.Colors.Cyan, label = "SLIDE!" },
}

local FRAME = 0.6 -- glowing hole outline thickness
local RISE_TIME = 1.1
local SINK_TIME = 0.5
local TELEGRAPH_DEPTH = 7
local KICK_TIME = 0.35
local LABEL_PPS = 40 -- SurfaceGui pixels per stud
local MAX_HOLES = 6

type Hole = { code: string, minX: number, maxX: number, bottom: number, top: number }

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function easeOutBack(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- Parses "N:-20.50:-13.50:0.00:8.00;H:..." defensively.
local function parseHoles(raw: any, halfWidth: number, height: number): { Hole }?
	if type(raw) ~= "string" or #raw > 400 then
		return nil
	end
	local holes: { Hole } = {}
	for chunk in string.gmatch(raw, "[^;]+") do
		local code, a, b, c, d = string.match(chunk, "^(%a):([%-%d%.]+):([%-%d%.]+):([%-%d%.]+):([%-%d%.]+)$")
		local minX, maxX, bottom, top = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
		if code and WallView.HOLE_STYLE[code] and minX and maxX and bottom and top then
			if minX < maxX and bottom < top and minX >= -halfWidth and maxX <= halfWidth and top <= height then
				table.insert(holes, { code = code, minX = minX, maxX = maxX, bottom = math.max(0, bottom), top = top })
			end
		end
		if #holes >= MAX_HOLES then
			break
		end
	end
	table.sort(holes, function(x, y)
		return x.minX < y.minX
	end)
	return holes
end

local function newPart(parent: Instance, name: string, size: Vector3, color: Color3, neon: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.CastShadow = not neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function label(part: BasePart, text: string, color: Color3, faceHeight: number, centerFromTop: number)
	local heightPx = math.max(1, math.min(2.6, faceHeight - 0.3)) * LABEL_PPS
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = LABEL_PPS
		gui.LightInfluence = 0
		gui.Brightness = 1.4
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.new(0.5, 0, 0, centerFromTop * LABEL_PPS)
		t.Size = UDim2.new(0.94, 0, 0, heightPx)
		t.FontFace = Theme.FontFace
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = color
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Ink
		stroke.Thickness = 4
		stroke.Parent = t
		t.Parent = gui
		gui.Parent = part
	end
end

function WallView.new(config: Configuration, parent: Instance)
	local origin = config:GetAttribute("Origin")
	local dir = config:GetAttribute("Dir")
	local color = config:GetAttribute("Color")
	local telegraph = config:GetAttribute("Telegraph")
	local enter = config:GetAttribute("Enter")
	local speed = config:GetAttribute("Speed")
	local start = config:GetAttribute("Start")
	local finish = config:GetAttribute("Finish")
	local width = config:GetAttribute("Width")
	local height = config:GetAttribute("Height")
	local thick = config:GetAttribute("Thick")
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or typeof(color) ~= "Color3" then
		return nil
	end
	-- Numeric loop on purpose: a missing attribute is a nil hole that `for in` would silently skip.
	local numbers = { telegraph, enter, speed, start, finish, width, height, thick }
	for i = 1, 8 do
		if not isFinite(numbers[i]) then
			return nil
		end
	end
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.5 or width <= 0 or width > 200 or height <= 0 or height > 60 or thick <= 0 then
		return nil
	end
	flatDir = flatDir.Unit
	local holes = parseHoles(config:GetAttribute("Holes"), width / 2, height)
	if not holes then
		return nil
	end

	local self = setmetatable({}, WallView)
	self.origin = origin :: Vector3
	self.dir = flatDir
	self.right = flatDir:Cross(Vector3.yAxis).Unit
	self.color = color :: Color3
	self.telegraphAt = telegraph :: number
	self.enter = enter :: number
	self.speed = speed :: number
	self.start = start :: number
	self.finish = finish :: number
	self.height = height :: number
	self.releasedAt = nil :: number?
	self.kickAt = -math.huge
	self.parts = {} :: { BasePart }
	self.offsets = {} :: { CFrame }
	self.cframes = {} :: { CFrame }
	self.model = Instance.new("Model")
	self.model.Name = config.Name
	self.telegraph = nil :: Model?
	self.pulse = {} :: { BasePart }

	local W, H, T = width :: number, height :: number, thick :: number
	local light = (color :: Color3):Lerp(Theme.Colors.White, 0.45)
	local dark = (color :: Color3):Lerp(Theme.Colors.Ink, 0.35)

	local function box(name: string, x0: number, x1: number, y0: number, y1: number, depth: number, c: Color3, neon)
		if x1 - x0 < 0.05 or y1 - y0 < 0.05 then
			return nil
		end
		local p = newPart(self.model, name, Vector3.new(x1 - x0, y1 - y0, depth), c, neon == true)
		table.insert(self.parts, p)
		table.insert(self.offsets, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0))
		return p
	end

	-- Solid panel pieces around the holes (no CSG): full columns between holes, plus the bits
	-- under / over each hole.
	local cursor = -W / 2
	for _, hole in holes do
		box("Panel", cursor, hole.minX, 0, H, T, color)
		box("Base", cursor, hole.minX, 0, 1, T + 0.3, dark)
		local style = WallView.HOLE_STYLE[hole.code]
		local below = box("Panel", hole.minX, hole.maxX, 0, hole.bottom, T, color)
		local above = box("Panel", hole.minX, hole.maxX, hole.top, H, T, color)
		if hole.code == "H" and below then
			label(below, style.label, style.color, hole.bottom - FRAME, FRAME + (hole.bottom - FRAME) / 2)
		elseif above then
			local room = math.min(H - 2.6 - hole.top - FRAME, 3.2) -- stay under the light band
			label(above, style.label, style.color, room, (H - hole.top) - FRAME - room / 2)
		end
		cursor = hole.maxX
	end
	box("Panel", cursor, W / 2, 0, H, T, color)
	box("Base", cursor, W / 2, 0, 1, T + 0.3, dark)

	-- Cartoon trim: a light band near the top (above every hole type) and a white cap.
	box("Band", -W / 2, W / 2, H - 2.6, H - 1.6, T + 0.3, light)
	box("Cap", -W / 2 - 0.3, W / 2 + 0.3, H, H + 1, T + 0.8, Theme.Colors.White)

	-- Glowing, color-coded hole outlines (+ a glow strip on the floor for ground-level holes).
	for _, hole in holes do
		local c = WallView.HOLE_STYLE[hole.code].color
		local d = T + 0.5
		local y0 = if hole.bottom > 0 then hole.bottom - FRAME else 0
		box("Outline", hole.minX - FRAME, hole.minX, y0, hole.top + FRAME, d, c, true)
		box("Outline", hole.maxX, hole.maxX + FRAME, y0, hole.top + FRAME, d, c, true)
		box("Outline", hole.minX - FRAME, hole.maxX + FRAME, hole.top, hole.top + FRAME, d, c, true)
		if hole.bottom > 0 then
			box("Outline", hole.minX - FRAME, hole.maxX + FRAME, hole.bottom - FRAME, hole.bottom, d, c, true)
		else
			local strip = box("FloorGlow", hole.minX, hole.maxX, 0.03, 0.18, T + 1.6, c, true)
			if strip then
				strip.Transparency = 0.25
			end
		end
	end
	self.baseTransparency = {} :: { number }
	for i, p in self.parts do
		self.baseTransparency[i] = p.Transparency
		self.cframes[i] = CFrame.identity
	end

	self:_buildTelegraph(parent, holes, W)
	self.model.Parent = parent
	self:update(workspace:GetServerTimeNow())
	return self
end

-- Floor warning just inside the entry edge: a dark "shadow" strip of the wall with its holes lit up in
-- their colors, pulsing chevrons in the travel direction and a "!" bubble readable from anywhere.
function WallView:_buildTelegraph(parent: Instance, holes: { Hole }, width: number)
	local now = workspace:GetServerTimeNow()
	if now > self.enter + 0.4 then
		return
	end
	local tele = Instance.new("Model")
	tele.Name = "Telegraph"
	local edge = self.start + 4 -- platform edge (the wall starts 4 studs outside it)
	local y = self.origin.Y + 0.12
	local function place(localX: number, along: number, yaw: number): CFrame
		local pos = self.origin + self.right * localX + self.dir * (edge + along) + Vector3.new(0, y - self.origin.Y, 0)
		return CFrame.fromMatrix(pos, self.right, Vector3.yAxis) * CFrame.Angles(0, yaw, 0)
	end

	local shadow = newPart(tele, "Shadow", Vector3.new(width - 2, 0.1, TELEGRAPH_DEPTH), Theme.Colors.Ink, false)
	shadow.CFrame = place(0, TELEGRAPH_DEPTH / 2, 0)
	shadow.Transparency = 0.45
	shadow.CastShadow = false
	for _, hole in holes do
		local style = WallView.HOLE_STYLE[hole.code]
		local patch =
			newPart(tele, "HolePatch", Vector3.new(hole.maxX - hole.minX, 0.12, TELEGRAPH_DEPTH), style.color, true)
		patch.CFrame = place((hole.minX + hole.maxX) / 2, TELEGRAPH_DEPTH / 2, 0) + Vector3.new(0, 0.02, 0)
		patch.Transparency = 0.2
	end
	-- Chevrons ">" pointing along the travel direction (local -Z is the travel direction).
	for _, x in { -22, -11, 0, 11, 22 } do
		for _, sign in { 1, -1 } do
			local bar = newPart(tele, "Chevron", Vector3.new(0.7, 0.14, 3.2), self.color, true)
			bar.CFrame = place(x + sign * 1.05, TELEGRAPH_DEPTH / 2, 0)
				* CFrame.Angles(0, sign * math.rad(40), 0)
				* CFrame.new(0, 0.05, 0)
			table.insert(self.pulse, bar)
		end
	end

	-- "!" bubble above the slot (AlwaysOnTop so walls from behind are never a surprise).
	local anchor = newPart(tele, "Anchor", Vector3.one * 0.2, self.color, false)
	anchor.Transparency = 1
	anchor.CFrame = CFrame.new(self.origin + self.dir * self.start + Vector3.new(0, 9, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(5, 5)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	local bubble = Instance.new("TextLabel")
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0.5, 0.5)
	bubble.Size = UDim2.fromScale(0.8, 0.8)
	bubble.BackgroundColor3 = self.color
	bubble.FontFace = Theme.FontFace
	bubble.Text = "!"
	bubble.TextScaled = true
	bubble.TextColor3 = Theme.Colors.White
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Ink
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bubble
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = bubble
	bubble.Parent = gui
	gui.Adornee = anchor
	gui.Parent = anchor
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	tele.Parent = parent
	self.telegraph = tele

	-- Rising whoosh from the slot (positional, so you can hear which side it comes from).
	local whoosh = Instance.new("Sound")
	whoosh.SoundId = "rbxasset://sounds/action_falling.mp3"
	whoosh.Volume = 0.55
	whoosh.PlaybackSpeed = 1.5
	whoosh.RollOffMinDistance = 25
	whoosh.RollOffMaxDistance = 200
	whoosh.Parent = anchor
	whoosh:Play()
end

function WallView:kick()
	self.kickAt = os.clock()
end

function WallView:release()
	if not self.releasedAt then
		self.releasedAt = os.clock()
	end
end

-- Current wall plane offset along its travel direction (same formula as the server).
function WallView:plane(now: number): number
	return self.start + self.speed * math.max(0, now - self.enter)
end

function WallView:update(now: number): boolean
	local clock = os.clock()

	-- Vertical offset: rise out of the slot during the telegraph, sink away when released.
	local y = 0
	local rise = math.clamp((now - self.telegraphAt) / RISE_TIME, 0, 1)
	if rise < 1 then
		y = -(self.height + 2) * (1 - easeOutBack(rise))
	end
	local fade = 0
	if self.releasedAt then
		local s = math.clamp((clock - self.releasedAt) / SINK_TIME, 0, 1)
		y -= (self.height + 2) * s * s
		fade = s
		if s >= 1 then
			return false
		end
	end

	-- Impact wobble: a quick shudder along the travel direction.
	local along = self:plane(now)
	local kick = clock - self.kickAt
	if kick < KICK_TIME then
		along += math.sin(kick * 55) * 0.45 * (1 - kick / KICK_TIME)
	end

	local base = CFrame.fromMatrix(self.origin + self.dir * along + Vector3.new(0, y, 0), self.right, Vector3.yAxis)
	for i, offset in self.offsets do
		self.cframes[i] = base * offset
	end
	workspace:BulkMoveTo(self.parts, self.cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if fade > 0 then
		for i, p in self.parts do
			p.Transparency = self.baseTransparency[i] + (1 - self.baseTransparency[i]) * fade
		end
	end

	-- Telegraph: pulse while warning, fade out shortly after the wall starts moving.
	local tele = self.telegraph
	if tele then
		local after = now - self.enter
		if after > 0.9 or self.releasedAt then
			tele:Destroy()
			self.telegraph = nil
		else
			local wave = 0.5 + 0.5 * math.sin(now * 14)
			local out = math.clamp(after / 0.9, 0, 1)
			for _, bar in self.pulse do
				bar.Transparency = math.min(1, 0.1 + 0.45 * wave + out)
			end
		end
	end
	return true
end

function WallView:destroy()
	if self.telegraph then
		self.telegraph:Destroy()
		self.telegraph = nil
	end
	self.model:Destroy()
	table.clear(self.parts)
end

return WallView
