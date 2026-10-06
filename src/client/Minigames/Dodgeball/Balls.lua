-- Dodgeball (client): renders the server's balls from their launch parameters.
-- The server sends a flight plan (parabolic segments in server time, see the server's Ballistics.lua);
-- every frame we evaluate it at workspace:GetServerTimeNow(), so every client sees the same smooth arc
-- without any physics replication. Ball parts, drop shadows and landing markers are pooled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Balls = {}
Balls.__index = Balls

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)
local HIDDEN = CFrame.new(0, -5000, 0)
local SEAM_TURN = CFrame.Angles(0, math.pi / 2, 0) -- seam band faces the travel direction
local MAX_VISUALS = 60
local CULL_DISTANCE = 900 -- skip balls of far-away arenas (e.g. other Solo copies)

type Segment = { t0: number, p0: Vector3, v0: Vector3 }

export type FloorInfo = { y: number, center: Vector3, radius: number }

type Parts = {
	ball: Part,
	seam: Part,
	trail: Trail,
	a0: Attachment,
	a1: Attachment,
	sparkles: ParticleEmitter,
	shadow: Part,
	marker: Part,
	ring: Part,
}

export type Visual = {
	sid: string,
	id: number,
	kind: string,
	cannon: number,
	launchAt: number,
	endAt: number,
	fizzle: boolean,
	g: number,
	radius: number,
	color: Color3,
	segments: { Segment },
	target: Vector3?,
	targetAt: number,
	floor: FloorInfo?,
	parts: Parts,
	launched: boolean,
	spin: number,
	heading: Vector3,
	segment: number, -- index of the segment currently flying (each new one = a bounce)
	pos: Vector3,
}

local function basePart(name: string, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.CFrame = HIDDEN
	return p
end

local function unpackSegments(flat: { any }): { Segment }?
	local out = {}
	for i = 1, #flat, 3 do
		local t0, p0, v0 = flat[i], flat[i + 1], flat[i + 2]
		if type(t0) ~= "number" or typeof(p0) ~= "Vector3" or typeof(v0) ~= "Vector3" then
			return nil
		end
		table.insert(out, { t0 = t0, p0 = p0, v0 = v0 })
	end
	if #out == 0 then
		return nil
	end
	return out
end

local function segmentAt(segments: { Segment }, t: number): Segment
	local seg = segments[1]
	for i = 2, #segments do
		if segments[i].t0 <= t then
			seg = segments[i]
		else
			break
		end
	end
	return seg
end

local function evaluate(segments: { Segment }, g: number, t: number): (Vector3, Vector3)
	local seg = segmentAt(segments, t)
	local dt = math.max(0, t - seg.t0)
	return seg.p0 + seg.v0 * dt - Vector3.new(0, 0.5 * g * dt * dt, 0), seg.v0 - Vector3.new(0, g * dt, 0)
end

function Balls.new(folder: Instance)
	local self = setmetatable({}, Balls)
	self.folder = folder
	self.active = {} :: { Visual }
	self.pool = {} :: { Parts }
	return self
end

function Balls:_acquire(): Parts
	local parts = table.remove(self.pool)
	if parts then
		return parts
	end
	local ball = basePart("DodgeBall", Enum.PartType.Ball)
	local a0 = Instance.new("Attachment")
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.2
	trail.LightEmission = 0.35
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = ball
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Theme.Colors.Yellow, Theme.Colors.White)
	sparkles.LightEmission = 0.8
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.3, 0.5)
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 40
	sparkles.Enabled = false
	sparkles.Parent = ball
	ball.Parent = self.folder
	-- A white seam band makes the roll visible (a plain ball looks static while spinning).
	local seam = basePart("Seam", Enum.PartType.Cylinder)
	seam.Color = Theme.Colors.White
	seam.Transparency = 1
	seam.Parent = self.folder

	local shadow = basePart("Shadow", Enum.PartType.Cylinder)
	shadow.Color = Theme.Colors.Ink
	shadow.Transparency = 1
	shadow.Parent = self.folder

	local marker = basePart("Marker", Enum.PartType.Cylinder)
	marker.Material = Enum.Material.Neon
	marker.Transparency = 1
	marker.Parent = self.folder
	local ring = basePart("MarkerRing", Enum.PartType.Cylinder)
	ring.Color = Theme.Colors.White
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	ring.Parent = self.folder

	return {
		ball = ball,
		seam = seam,
		trail = trail,
		a0 = a0,
		a1 = a1,
		sparkles = sparkles,
		shadow = shadow,
		marker = marker,
		ring = ring,
	}
end

function Balls:_release(index: number)
	local v = self.active[index]
	self.active[index] = self.active[#self.active]
	self.active[#self.active] = nil
	local parts = v.parts
	parts.trail.Enabled = false
	parts.sparkles.Enabled = false
	parts.ball.Transparency = 1
	parts.ball.CFrame = HIDDEN
	parts.seam.Transparency = 1
	parts.seam.CFrame = HIDDEN
	parts.shadow.Transparency = 1
	parts.shadow.CFrame = HIDDEN
	parts.marker.Transparency = 1
	parts.marker.CFrame = HIDDEN
	parts.ring.Transparency = 1
	parts.ring.CFrame = HIDDEN
	table.insert(self.pool, parts)
end

-- Registers a ball from a "shot" message. Returns the visual (nil when invalid or culled).
function Balls:spawn(
	sid: string,
	id: number,
	kind: string,
	cannon: number,
	launchAt: number,
	endAt: number,
	fizzle: boolean,
	g: number,
	radius: number,
	color: Color3,
	packed: { any },
	target: Vector3?,
	floor: FloorInfo?,
	cameraPos: Vector3
): Visual?
	local segments = unpackSegments(packed)
	if not segments then
		return nil
	end
	if (segments[1].p0 - cameraPos).Magnitude > CULL_DISTANCE then
		return nil
	end
	if #self.active >= MAX_VISUALS then
		self:_release(1)
	end
	local parts = self:_acquire()
	local ball = parts.ball
	ball.Size = Vector3.one * radius * 2
	ball.Color = color
	ball.Material = if kind == "gold" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	ball.Name = if kind == "gold" then "GoldenBallThrown" else "DodgeBall"
	ball.Transparency = 1
	parts.seam.Size = Vector3.new(radius * 0.4, radius * 2.06, radius * 2.06)
	parts.seam.Color = if kind == "gold" then Color3.fromRGB(255, 245, 200) else Theme.Colors.White
	parts.seam.Material = ball.Material
	parts.a0.Position = Vector3.new(0, radius * 0.7, 0)
	parts.a1.Position = Vector3.new(0, -radius * 0.7, 0)
	parts.trail.Color = ColorSequence.new(Theme.Colors.White, color)
	parts.trail.Lifetime = if kind == "giant" then 0.3 else 0.2
	parts.trail:Clear()
	parts.sparkles.Enabled = false

	-- When the ball reaches its target (for the landing marker).
	local targetAt = launchAt
	if target then
		local v0 = segments[1].v0
		local flatSpeed = Vector3.new(v0.X, 0, v0.Z).Magnitude
		local dist = Vector3.new(target.X - segments[1].p0.X, 0, target.Z - segments[1].p0.Z).Magnitude
		targetAt = launchAt + dist / math.max(flatSpeed, 1)
		parts.marker.Color = color
	end

	local visual: Visual = {
		sid = sid,
		id = id,
		kind = kind,
		cannon = cannon,
		launchAt = launchAt,
		endAt = endAt,
		fizzle = fizzle,
		g = g,
		radius = radius,
		color = color,
		segments = segments,
		target = target,
		targetAt = targetAt,
		floor = floor,
		parts = parts,
		launched = false,
		spin = 0,
		heading = Vector3.zAxis,
		segment = 1,
		pos = segments[1].p0,
	}
	table.insert(self.active, visual)
	return visual
end

-- Removes a ball early (server said it popped). Returns its last rendered position.
function Balls:remove(sid: string, id: number): Visual?
	for i, v in self.active do
		if v.sid == sid and v.id == id then
			self:_release(i)
			return v
		end
	end
	return nil
end

function Balls:clear(sid: string?)
	for i = #self.active, 1, -1 do
		if sid == nil or self.active[i].sid == sid then
			self:_release(i)
		end
	end
end

local function updateMarker(v: Visual, t: number)
	local parts = v.parts
	local target, floor = v.target, v.floor
	if not target or not floor or t > v.targetAt + 0.05 then
		parts.marker.Transparency = 1
		parts.ring.Transparency = 1
		return
	end
	-- Shrinks onto the landing spot as the ball arrives, pulsing faster near the end.
	local total = math.max(v.targetAt - (v.launchAt - 1), 0.1)
	local k = math.clamp(1 - (v.targetAt - t) / total, 0, 1)
	local d = v.radius * 2 + 1 + (1 - k) * 6
	local pulse = 0.5 + 0.5 * math.sin(t * (10 + k * 20))
	local pos = Vector3.new(target.X, floor.y + 0.16, target.Z)
	parts.marker.Size = Vector3.new(0.12, d, d)
	parts.marker.CFrame = CFrame.new(pos) * VERTICAL
	parts.marker.Transparency = 0.55 - 0.25 * k * pulse
	parts.ring.Size = Vector3.new(0.1, d + 1.2, d + 1.2)
	parts.ring.CFrame = CFrame.new(pos - Vector3.new(0, 0.02, 0)) * VERTICAL
	parts.ring.Transparency = 0.35 + 0.3 * pulse
end

local function updateShadow(v: Visual, pos: Vector3)
	local shadow = v.parts.shadow
	local floor = v.floor
	if not floor then
		shadow.Transparency = 1
		return
	end
	local offset = Vector3.new(pos.X - floor.center.X, 0, pos.Z - floor.center.Z)
	local height = pos.Y - floor.y
	if offset.Magnitude > floor.radius - 0.5 or height < 0 then
		shadow.Transparency = 1
		return
	end
	local scale = math.clamp(1 - height / 45, 0.35, 1)
	local d = v.radius * 2 * scale
	shadow.Size = Vector3.new(0.1, d, d)
	shadow.CFrame = CFrame.new(pos.X, floor.y + 0.2, pos.Z) * VERTICAL
	shadow.Transparency = 0.45 + 0.4 * (1 - scale)
end

-- Advances every ball to server time `t`. Calls onLaunch(visual) once when a ball leaves its cannon,
-- onBounce(visual) when it bounces on the floor and onEnd(visual) when its flight is over
-- (visual.fizzle = it came to rest on the floor).
function Balls:update(t: number, dt: number, onLaunch: (Visual) -> (), onBounce: (Visual) -> (), onEnd: (Visual) -> ())
	local i = 1
	while i <= #self.active do
		local v = self.active[i]
		local parts = v.parts
		updateMarker(v, t)
		if t >= v.endAt then
			v.pos = (evaluate(v.segments, v.g, v.endAt))
			onEnd(v)
			self:_release(i)
		else
			if t >= v.launchAt then
				local pos, vel = evaluate(v.segments, v.g, t)
				if not v.launched then
					v.launched = true
					parts.ball.Transparency = 0
					parts.seam.Transparency = 0
					parts.trail.Enabled = true
					parts.sparkles.Enabled = v.kind == "gold"
					onLaunch(v)
				end
				-- Roll forward around the horizontal axis perpendicular to the travel direction.
				local flatVel = Vector3.new(vel.X, 0, vel.Z)
				if flatVel.Magnitude > 0.5 then
					v.heading = flatVel.Unit
				end
				v.spin -= flatVel.Magnitude / math.max(v.radius, 0.5) * dt
				local cf = CFrame.lookAt(pos, pos + v.heading) * CFrame.Angles(v.spin, 0, 0)
				parts.ball.CFrame = cf
				parts.seam.CFrame = cf * SEAM_TURN
				v.pos = pos
				updateShadow(v, pos)
				local nextSeg = v.segments[v.segment + 1]
				if nextSeg and t >= nextSeg.t0 then
					v.segment += 1
					onBounce(v)
				end
			end
			i += 1
		end
	end
end

function Balls:destroy()
	self:clear(nil)
	for _, parts in self.pool do
		parts.ball:Destroy()
		parts.seam:Destroy()
		parts.shadow:Destroy()
		parts.marker:Destroy()
		parts.ring:Destroy()
	end
	table.clear(self.pool)
end

return Balls
