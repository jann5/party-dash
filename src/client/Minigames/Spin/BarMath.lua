--!strict
--[[
Spin: arena dimensions and the spinning-bar math, shared by the server (hit checks) and every client
(smooth rendering). The server requires this module from StarterPlayerScripts so both sides always run
the exact same formula.

A bar's motion is one "segment" that only depends on server time, so each client computes the angle
itself every frame (no per-frame replication, no jitter):
	a0, t0   angle (radians) at server time t0 (a bar that has not started yet has w0 = 0 and waits at a0)
	w0, w1   speed ramps linearly from w0 to w1 (rad/s, magnitudes) over `ramp` seconds, then stays w1
	dir      +1 / -1 rotation direction
	rt       0, or a server time when the bar reverses: the speed flips smoothly over TURN_TIME
The server re-anchors a segment (new a0/t0 at the current angle) whenever the speed target changes.

Angle convention (same as the legacy SpinShared): the bar's long axis is the map's X axis rotated by
`angle` around Y, i.e. it points at (cos a, 0, -sin a) in map space.
]]
local BarMath = {}

-- Arena layout (map space: origin = ctx.center, pillar tops at y = 0).
BarMath.PILLAR_COUNT = 12
BarMath.RING_RADIUS = 36 -- pillar centers
BarMath.TOP_RADIUS = 4.5 -- walkable pillar top
BarMath.BAR_HEIGHT = 1.5 -- bar center above the pillar tops
BarMath.BAR_THICK = 1.4
BarMath.BAR_HALF_LEN = 42
BarMath.START_ANGLE = math.pi / BarMath.PILLAR_COUNT -- arms rest between two pillars

-- Timings (seconds).
BarMath.TURN_TIME = 0.5 -- a reversal brakes and re-accelerates over this long
BarMath.TELEGRAPH = 1.1 -- the bar flashes this long before a reversal
BarMath.APPEAR_TIME = 1.4 -- a new bar rises out of the hub over this long

export type State = {
	a0: number,
	t0: number,
	w0: number,
	w1: number,
	ramp: number,
	dir: number,
	rt: number,
}

local function finite(n: number?): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function BarMath.encode(s: State): string
	return string.format("%.6f,%.4f,%.5f,%.5f,%.4f,%d,%.4f", s.a0, s.t0, s.w0, s.w1, s.ramp, s.dir, s.rt)
end

function BarMath.decode(raw: any): State?
	if type(raw) ~= "string" then
		return nil
	end
	local parts = string.split(raw, ",")
	if #parts ~= 7 then
		return nil
	end
	local n = table.create(7, 0)
	for i, p in parts do
		local v = tonumber(p)
		if not finite(v) then
			return nil
		end
		n[i] = v :: number
	end
	return {
		a0 = n[1],
		t0 = n[2],
		w0 = n[3],
		w1 = n[4],
		ramp = math.max(n[5], 0),
		dir = if n[6] < 0 then -1 else 1,
		rt = n[7],
	}
end

-- Speed magnitude `dt` seconds into the segment (ignoring reversals).
local function rampSpeed(s: State, dt: number): number
	if dt <= 0 then
		return s.w0
	end
	if s.ramp <= 0 or dt >= s.ramp then
		return s.w1
	end
	return s.w0 + (s.w1 - s.w0) * dt / s.ramp
end

-- Distance travelled `dt` seconds into the segment (ignoring reversals).
local function rampTravel(s: State, dt: number): number
	if dt <= 0 then
		return 0
	end
	if s.ramp <= 0 then
		return s.w1 * dt
	end
	if dt < s.ramp then
		return s.w0 * dt + 0.5 * (s.w1 - s.w0) * dt * dt / s.ramp
	end
	return 0.5 * (s.w0 + s.w1) * s.ramp + s.w1 * (dt - s.ramp)
end

-- Bar angle at server time t.
function BarMath.angle(s: State, t: number): number
	if t <= s.t0 then
		-- A client clock a few ms behind the server extrapolates backwards instead of stalling.
		return s.a0 + s.dir * s.w0 * (t - s.t0)
	end
	if s.rt > s.t0 and t > s.rt then
		local base = rampTravel(s, s.rt - s.t0)
		local v = rampSpeed(s, s.rt - s.t0)
		local u = t - s.rt
		local turn = BarMath.TURN_TIME
		local extra
		if u < turn then
			-- speed goes +v -> -v linearly: the bar brakes, stops and swings back (net 0 over the turn)
			extra = v * (u - u * u / turn)
		else
			extra = -v * (u - turn)
		end
		return s.a0 + s.dir * (base + extra)
	end
	return s.a0 + s.dir * rampTravel(s, t - s.t0)
end

-- Signed angular velocity (rad/s) at server time t.
function BarMath.velocity(s: State, t: number): number
	if t <= s.t0 then
		return s.dir * s.w0 -- (0 for a bar that has not started yet: its w0 is 0)
	end
	if s.rt > s.t0 and t > s.rt then
		local v = rampSpeed(s, s.rt - s.t0)
		local u = t - s.rt
		local turn = BarMath.TURN_TIME
		if u < turn then
			return s.dir * v * (1 - 2 * u / turn)
		end
		return -s.dir * v
	end
	return s.dir * rampSpeed(s, t - s.t0)
end

-- True while a scheduled reversal has not fully finished at time t.
function BarMath.turning(s: State, t: number): boolean
	return s.rt > s.t0 and t < s.rt + BarMath.TURN_TIME
end

-- Angle of a map-space position in the bar's convention.
function BarMath.positionAngle(localPos: Vector3): number
	return math.atan2(-localPos.Z, localPos.X)
end

function BarMath.pillarAngle(index: number): number
	return (index - 1) * (2 * math.pi / BarMath.PILLAR_COUNT)
end

-- Map-space position of a pillar's top center.
function BarMath.pillarTop(index: number): Vector3
	local a = BarMath.pillarAngle(index)
	return Vector3.new(math.cos(a), 0, -math.sin(a)) * BarMath.RING_RADIUS
end

-- The bar has two arms, so its distance to an angle is taken modulo pi, in (-pi/2, pi/2].
function BarMath.armDistance(barAngle: number, posAngle: number): number
	local d = (barAngle - posAngle) % math.pi
	if d > math.pi / 2 then
		d -= math.pi
	end
	return d
end

-- Seconds until an arm moving at `velocity` reaches `posAngle` (math.huge if it is not moving).
function BarMath.timeUntil(barAngle: number, velocity: number, posAngle: number): number
	local speed = math.abs(velocity)
	if speed < 1e-3 then
		return math.huge
	end
	local sign = if velocity > 0 then 1 else -1
	local ahead = ((posAngle - barAngle) * sign) % math.pi
	return ahead / speed
end

-- World CFrame of a bar (pivot = middle of the bar) for a map centered on `center`.
function BarMath.barCFrame(center: CFrame, angle: number, lift: number?): CFrame
	return center * CFrame.new(0, BarMath.BAR_HEIGHT + (lift or 0), 0) * CFrame.Angles(0, angle, 0)
end

return BarMath
