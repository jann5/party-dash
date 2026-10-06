--!strict
-- Dodgeball: deterministic ball flight (pure math, no state).
--
-- A flight is a list of parabolic SEGMENTS. Segment k starts at absolute server time t0 (seconds from
-- workspace:GetServerTimeNow()) at position p0 with velocity v0, and falls with gravity g:
--     p(t) = p0 + v0 * dt - (0, g * dt^2 / 2, 0),  dt = t - t0
-- A new segment starts at every bounce on the arena floor. The server plans the whole flight once at
-- launch and sends the segments to clients, which only evaluate them: everyone sees the same ball.
local Ballistics = {}

export type Segment = { t0: number, p0: Vector3, v0: Vector3 }

export type Plan = {
	segments: { Segment },
	endAt: number, -- absolute server time the ball disappears
	fizzle: boolean, -- true: it comes to rest on the floor (pop); false: it falls into the void
}

export type Floor = {
	y: number, -- floor top height
	center: Vector3, -- arena center (only X/Z matter)
	radius: number, -- the floor is a disc of this radius
}

local BOUNCE_KEEP_FLAT = 0.88 -- horizontal speed kept per bounce
local BOUNCE_RESTITUTION = 0.6 -- vertical speed kept per bounce
local MIN_BOUNCE_SPEED = 9 -- a softer landing than this just stops (pop)
local VOID_DEPTH = 40 -- a ball that misses the floor is gone this far below it

-- Velocity that carries a ball from `origin` through `target`, travelling horizontally at `speed`.
function Ballistics.solve(origin: Vector3, target: Vector3, speed: number, g: number): Vector3
	local delta = target - origin
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local time = math.max(0.2, flat / math.max(speed, 1))
	return delta / time + Vector3.new(0, 0.5 * g * time, 0)
end

-- Later (descending) time at which y(t) reaches `height`, or nil if it never does.
local function descendTime(p: Vector3, v: Vector3, g: number, height: number): number?
	local disc = v.Y * v.Y - 2 * g * (height - p.Y)
	if disc < 0 then
		return nil
	end
	local t = (v.Y + math.sqrt(disc)) / g
	if t <= 1e-3 then
		return nil
	end
	return t
end

function Ballistics.plan(
	origin: Vector3,
	velocity: Vector3,
	launchAt: number,
	g: number,
	radius: number,
	floor: Floor,
	maxBounces: number,
	maxLife: number
): Plan
	local segments: { Segment } = { { t0 = launchAt, p0 = origin, v0 = velocity } }
	local p, v, ts = origin, velocity, launchAt
	local contactY = floor.y + radius
	local bounces = 0
	while true do
		local tc = descendTime(p, v, g, contactY)
		if not tc then
			break
		end
		local landing = p + v * tc - Vector3.new(0, 0.5 * g * tc * tc, 0)
		local offset = landing - floor.center
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > floor.radius then
			break -- misses the floor: it falls into the void
		end
		local vIn = v - Vector3.new(0, g * tc, 0)
		if bounces >= maxBounces or -vIn.Y * BOUNCE_RESTITUTION < MIN_BOUNCE_SPEED then
			return { segments = segments, endAt = math.min(ts + tc, launchAt + maxLife), fizzle = true }
		end
		bounces += 1
		ts += tc
		p = landing
		v = Vector3.new(vIn.X * BOUNCE_KEEP_FLAT, -vIn.Y * BOUNCE_RESTITUTION, vIn.Z * BOUNCE_KEEP_FLAT)
		table.insert(segments, { t0 = ts, p0 = p, v0 = v })
	end
	local fall = descendTime(p, v, g, floor.y - VOID_DEPTH) or 1
	return { segments = segments, endAt = math.min(ts + fall, launchAt + maxLife), fizzle = false }
end

-- Segment active at time t (the last one that has started).
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

function Ballistics.position(segments: { Segment }, g: number, t: number): Vector3
	local seg = segmentAt(segments, t)
	local dt = math.max(0, t - seg.t0)
	return seg.p0 + seg.v0 * dt - Vector3.new(0, 0.5 * g * dt * dt, 0)
end

function Ballistics.velocity(segments: { Segment }, g: number, t: number): Vector3
	local seg = segmentAt(segments, t)
	local dt = math.max(0, t - seg.t0)
	return seg.v0 - Vector3.new(0, g * dt, 0)
end

-- Flat wire format for remotes: { t0, p0, v0, t0, p0, v0, ... }.
function Ballistics.pack(segments: { Segment }): { any }
	local out: { any } = table.create(#segments * 3)
	for _, seg in segments do
		table.insert(out, seg.t0)
		table.insert(out, seg.p0)
		table.insert(out, seg.v0)
	end
	return out
end

return Ballistics
