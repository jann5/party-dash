--!strict
--[[
Spin: pure bar-vs-player hit test (no Instances, no state; easy to unit test).

	Hit.check(barAngle, playerAngle, heightAboveTop, barSpeed, radius?, halfWidth?) -> boolean
		barAngle        bar angle in radians (the bar has two arms, so pi apart is the same bar)
		playerAngle     the player's angle around the arena center, same convention
		heightAboveTop  feet height above the pillar tops in studs (0 = standing; a jump clears the bar)
		barSpeed        angular speed in rad/s (sign ignored); a fast bar gets a slightly wider window so
		                it cannot skip over a player between two server frames
		radius          optional distance of the player from the center (default: the pillar ring)
		halfWidth       optional body half-width + bar half-thickness in studs (bigger for Giant players)
]]
local Hit = {}

Hit.CLEAR_HEIGHT = 1.4 -- feet at least this high above the tops pass over the bar
Hit.LOW_LIMIT = -5.5 -- feet this far below the tops: the bar passes over the head
Hit.DEFAULT_RADIUS = 36
Hit.HALF_WIDTH = 2.0 -- ~1.3 body + 0.7 half bar thickness
Hit.MIN_RADIUS = 3 -- the hub: the bar's axle, no hits
Hit.SWEEP_WINDOW = 1 / 60
Hit.MAX_SWEEP = 0.2

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Signed distance from the nearest arm to `playerAngle`, in (-pi/2, pi/2].
function Hit.armDistance(barAngle: number, playerAngle: number): number
	local d = (barAngle - playerAngle) % math.pi
	if d > math.pi / 2 then
		d -= math.pi
	end
	return d
end

function Hit.check(
	barAngle: number,
	playerAngle: number,
	heightAboveTop: number,
	barSpeed: number,
	radius: number?,
	halfWidth: number?
): boolean
	if not (finite(barAngle) and finite(playerAngle) and finite(heightAboveTop)) then
		return false
	end
	if heightAboveTop >= Hit.CLEAR_HEIGHT or heightAboveTop <= Hit.LOW_LIMIT then
		return false
	end
	local r = if finite(radius) then radius :: number else Hit.DEFAULT_RADIUS
	if r < Hit.MIN_RADIUS then
		return false
	end
	local width = if finite(halfWidth) and (halfWidth :: number) > 0 then halfWidth :: number else Hit.HALF_WIDTH
	local speed = if finite(barSpeed) then math.abs(barSpeed) else 0
	local tolerance = width / r + math.min(speed * Hit.SWEEP_WINDOW, Hit.MAX_SWEEP)
	return math.abs(Hit.armDistance(barAngle, playerAngle)) <= tolerance
end

return Hit
