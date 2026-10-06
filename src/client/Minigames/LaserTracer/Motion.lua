--!strict
--[[
Laser Tracer: laser motion math, shared by the SERVER (hit detection) and the CLIENT (rendering).

It lives in the client folder because that is the only place both sides can reach (the server requires it
from StarterPlayer.StarterPlayerScripts). Pure functions only: no state, no instances.

Every laser is described by one State, replicated as a single string attribute "State" on its Model so a
client never sees half an update. Its position is a deterministic function of workspace:GetServerTimeNow(),
so every client renders it smoothly by itself and the server uses the very same math for hits.

Coordinates are LOCAL to the map's center CFrame: (x, z) on the floor plane, angle a measured so that
the point at angle a and radius r is (cos a * r, sin a * r).

Patterns
	"sweep": a ray from the central hub to the rim, rotating around the center.
	         a = angle at t0, s = signed angular speed (rad/s), revAt = telegraphed reversal time (0 = none).
	"slide": a straight chord crossing the platform. a = travel heading, b = signed offset at t0,
	         s = speed (studs/s). It enters from outside the rim and leaves on the far side.
]]

local Motion = {}

Motion.RADIUS = 42 -- walkable platform radius
Motion.RIM_RADIUS = 42.6 -- beams end on the glowing rim
Motion.HUB_RADIUS = 3.4 -- sweep beams start at the surface of the central hub
Motion.ENTRY = 43.4 -- slide lasers start (and end) this far from the center line, fully outside the rim
Motion.HEIGHT = { low = 1.6, high = 4.6 } :: { [string]: number } -- beam height above the floor
Motion.HIT_HALF_WIDTH = 1.15 -- beam radius + half a body: the horizontal hit band is 2x this wide
Motion.FADE_TIME = 0.35 -- client fade-out after tOff

export type State = {
	pattern: string, -- "sweep" | "slide"
	kind: string, -- "low" | "high"
	tWarn: number, -- telegraph starts (server time)
	tOn: number, -- beam becomes live
	tOff: number, -- beam switches off
	a: number,
	b: number,
	t0: number,
	s: number,
	revAt: number,
}

local function num(v: string?): number?
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

function Motion.encode(st: State): string
	return string.format(
		"%s|%s|%.4f|%.4f|%.4f|%.6f|%.4f|%.4f|%.6f|%.4f",
		st.pattern,
		st.kind,
		st.tWarn,
		st.tOn,
		st.tOff,
		st.a,
		st.b,
		st.t0,
		st.s,
		st.revAt
	)
end

function Motion.decode(raw: any): State?
	if type(raw) ~= "string" then
		return nil
	end
	local f = string.split(raw, "|")
	if #f ~= 10 or (f[1] ~= "sweep" and f[1] ~= "slide") or (f[2] ~= "low" and f[2] ~= "high") then
		return nil
	end
	local tWarn, tOn, tOff = num(f[3]), num(f[4]), num(f[5])
	local a, b, t0, s, revAt = num(f[6]), num(f[7]), num(f[8]), num(f[9]), num(f[10])
	if not (tWarn and tOn and tOff and a and b and t0 and s and revAt) then
		return nil
	end
	return {
		pattern = f[1],
		kind = f[2],
		tWarn = tWarn,
		tOn = tOn,
		tOff = tOff,
		a = a,
		b = b,
		t0 = t0,
		s = s,
		revAt = revAt,
	}
end

function Motion.copy(st: State): State
	return table.clone(st)
end

-- Sweep angle at time t. Before t0 the laser holds its start angle (telegraph). After a scheduled reversal
-- it folds back, so clients render the reversal on time even before the server re-keys the state.
function Motion.angle(st: State, t: number): number
	local tt = math.max(t, st.t0)
	if st.revAt > 0 and tt > st.revAt then
		local pivot = st.a + st.s * (math.max(st.revAt, st.t0) - st.t0)
		return pivot - st.s * (tt - math.max(st.revAt, st.t0))
	end
	return st.a + st.s * (tt - st.t0)
end

-- Signed angular speed actually in effect at time t (sweep).
function Motion.angularVelocity(st: State, t: number): number
	if st.revAt > 0 and t > st.revAt then
		return -st.s
	end
	return st.s
end

-- Signed offset of a slide laser along its heading at time t.
function Motion.offset(st: State, t: number): number
	return st.b + st.s * (math.max(t, st.t0) - st.t0)
end

-- Half length of the chord of the rim circle at distance d from the center (0 when outside).
function Motion.chordHalf(d: number): number
	local r = Motion.RIM_RADIUS
	if math.abs(d) >= r then
		return 0
	end
	return math.sqrt(r * r - d * d)
end

-- The visible beam segment at time t in local floor coordinates: (x1, z1, x2, z2). Zero length = hidden.
function Motion.segment(st: State, t: number): (number, number, number, number)
	if st.pattern == "sweep" then
		local a = Motion.angle(st, t)
		local c, s = math.cos(a), math.sin(a)
		return c * Motion.HUB_RADIUS, s * Motion.HUB_RADIUS, c * Motion.RIM_RADIUS, s * Motion.RIM_RADIUS
	end
	local d = Motion.offset(st, t)
	local half = Motion.chordHalf(d)
	local vx, vz = math.cos(st.a), math.sin(st.a)
	local wx, wz = -vz, vx
	local cx, cz = vx * d, vz * d
	return cx - wx * half, cz - wz * half, cx + wx * half, cz + wz * half
end

--[[
Where a point (px, pz) is relative to the beam at time t:
	dist    signed perpendicular distance to the beam line
	inside  the point lies within the beam's length (so crossing the line means crossing the beam)
	mx, mz  unit direction the beam is moving at that point
]]
function Motion.probe(st: State, t: number, px: number, pz: number): (number, boolean, number, number)
	if st.pattern == "sweep" then
		local a = Motion.angle(st, t)
		local ux, uz = math.cos(a), math.sin(a)
		local nx, nz = -uz, ux
		local along = px * ux + pz * uz
		local dist = px * nx + pz * nz
		local w = Motion.angularVelocity(st, t)
		local sign = if w >= 0 then 1 else -1
		local inside = along >= Motion.HUB_RADIUS - 0.4 and along <= Motion.RIM_RADIUS + 0.6
		-- The beam at angle a moves along +n while a grows (and along -n while it shrinks).
		return dist, inside, nx * sign, nz * sign
	end
	local d = Motion.offset(st, t)
	local vx, vz = math.cos(st.a), math.sin(st.a)
	local wx, wz = -vz, vx
	local along = px * wx + pz * wz
	local dist = (px * vx + pz * vz) - d
	local half = Motion.chordHalf(d)
	local inside = half > 0 and math.abs(along) <= half + 0.6
	return dist, inside, vx, vz
end

-- Did the beam sweep over the point between times t0 and t1? Returns (crossed, inside, mx, mz).
-- Checking the whole interval means a fast beam can never skip over a player between two frames.
function Motion.crossed(st: State, ta: number, tb: number, px: number, pz: number): (boolean, boolean, number, number)
	local d1, inside, mx, mz = Motion.probe(st, tb, px, pz)
	local d0 = d1
	if ta < tb then
		d0 = Motion.probe(st, ta, px, pz)
	end
	local w = Motion.HIT_HALF_WIDTH
	return math.min(d0, d1) <= w and math.max(d0, d1) >= -w, inside, mx, mz
end

-- Rim angles of the emitters that fire this laser (used to flash the edge towers during the telegraph).
function Motion.emitterAngles(st: State): { number }
	if st.pattern == "sweep" then
		return { Motion.angle(st, st.tOn) }
	end
	-- A slide laser enters from the side opposite its heading; both chord ends light up.
	local entry = st.a + math.pi
	return { entry - 0.5, entry + 0.5 }
end

-- Phase at time t: "warn" (telegraph), "on", "fade" (switching off) or "off".
function Motion.phase(st: State, t: number): string
	if t < st.tOn then
		return "warn"
	elseif t <= st.tOff then
		return "on"
	elseif t <= st.tOff + Motion.FADE_TIME then
		return "fade"
	end
	return "off"
end

return Motion
