--!strict
-- Dodgeball: every gameplay number in one place (read-only constants + pure functions of intensity).
local Tuning = {}

-- Arena -------------------------------------------------------------------------------------------
Tuning.ARENA_RADIUS = 37.5 -- ~75 studs across, no walls
Tuning.SPAWN_RADIUS = 14
Tuning.SPAWN_COUNT = 12

-- Cannons (local cannon space: pivot on the pedestal top, -Z points at the arena center) -----------
Tuning.CANNON_COUNT = 10
Tuning.CANNON_RING = 46 -- distance from the center to each cannon pivot
Tuning.CANNON_SCALE = 1.35
Tuning.CANNON_DROP = 0.5 -- pivot sits this far below the floor top
Tuning.TRUNNION = Vector3.new(0, 3.2, 0.4) -- barrel pivot in cannon space (unscaled)
Tuning.BARREL_FRONT = 4.85 -- trunnion -> muzzle distance along the barrel (unscaled)
Tuning.REST_PITCH = math.rad(8)
Tuning.MAX_PITCH = math.rad(35)
Tuning.MIN_PITCH = math.rad(-6)

-- Cannonballs ---------------------------------------------------------------------------------------
Tuning.GRACE = 1.5 -- quiet seconds after GO!
Tuning.BALL_RADIUS = 2
Tuning.GIANT_RADIUS = 5
Tuning.GRAVITY = 70 -- lighter than the world so shots stay fast and only slightly arced
Tuning.TARGET_HEIGHT = 3 -- aim at about root height (a well-timed jump clears a normal ball)
Tuning.AIM_AT_PLAYER = 0.7 -- share of shots aimed at a player (the rest hit random spots)
Tuning.LEAD_FACTOR = 0.3 -- fraction of the predicted movement a cannon leads by
Tuning.MAX_LEAD = 7
Tuning.MAX_ACTIVE = 32 -- hard cap on balls in flight per session (pending + flying)
Tuning.MAX_LIFE = 4.5
Tuning.MAX_BOUNCES = 2
Tuning.RECOIL_TIME = 0.35 -- a cannon is busy this long after it fires
Tuning.STUN = 0.7

-- Golden ball ---------------------------------------------------------------------------------------
Tuning.GOLD_FIRST = 7 -- seconds after GO! until the first golden ball
Tuning.GOLD_EVERY = 12 -- a new one appears this long after the previous one was taken
Tuning.GOLD_FLOOR_HEIGHT = 2.2 -- center height above the floor while it waits to be picked up
Tuning.GOLD_PICKUP_RANGE = 4.5 -- root <-> ball distance that picks it up
Tuning.GOLD_RADIUS = 1.6
Tuning.GOLD_SPEED = 135
Tuning.GOLD_GRAVITY = 30
Tuning.GOLD_POWER = 150
Tuning.GOLD_STUN = 0.9
Tuning.GOLD_MAX_LIFE = 2.2
Tuning.GOLD_ASSIST_ANGLE = math.rad(16) -- aim assist cone around the throw direction
Tuning.GOLD_ASSIST_RANGE = 110
Tuning.THROW_COOLDOWN = 0.4

local function clampIntensity(i: number): number
	if i ~= i then
		return 1
	end
	return math.max(i, 0.1)
end

-- Seconds between volleys: 2.1 s at intensity 1, ~0.73 s at 2.5, never below 0.45 s.
function Tuning.fireInterval(intensity: number): number
	return math.max(0.45, 2.1 / clampIntensity(intensity) ^ 1.15)
end

-- Cannons firing together: more with intensity and with a bigger lobby.
function Tuning.volleySize(intensity: number, alive: number): number
	local i = clampIntensity(intensity)
	local base = 1 + math.floor(math.max(alive - 1, 0) / 5)
	return math.clamp(base + math.floor((i - 1) * 1.2), 1, 6)
end

-- Telegraph length (barrel glow + shake before the shot).
function Tuning.chargeTime(intensity: number): number
	return math.clamp(0.85 - 0.06 * (clampIntensity(intensity) - 1), 0.6, 0.85)
end

-- Horizontal ball speed in studs/s.
function Tuning.ballSpeed(intensity: number): number
	return math.min(150, 72 * (1 + 0.3 * (clampIntensity(intensity) - 1)))
end

-- Chance that a shot is a giant ball (only after intensity 2).
function Tuning.giantChance(intensity: number): number
	local i = clampIntensity(intensity)
	if i <= 2 then
		return 0
	end
	return math.min(0.45, (i - 2) * 0.3)
end

-- Knockback power of a cannonball hit.
function Tuning.knockPower(intensity: number, giant: boolean): number
	local power = 135 * (1 + 0.1 * (clampIntensity(intensity) - 1))
	if giant then
		power *= 1.2
	end
	return math.min(power, 210)
end

return Tuning
