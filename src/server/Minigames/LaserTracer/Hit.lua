--!strict
--[[
Laser Tracer: pure vertical hit rule (no instances, no state; safe to require from anywhere).

	Hit.check(kind, laserY, floorY, rootY, sliding, horizontallyInside) -> boolean
		kind                "low" (must be JUMPED) or "high" (must be SLID under)
		laserY, floorY      absolute heights of the beam and the floor
		rootY               absolute height of the HumanoidRootPart center
		sliding             the character's server-side "Sliding" attribute (plus a small grace window)
		horizontallyInside  the beam is passing through the player's position this frame

A standing character's root is ~3 studs above the floor and ~5+ at the apex of a jump.
	LOW  hits unless the feet are above the beam (root >= floor + JUMP_CLEAR).
	HIGH hits unless sliding (it cannot be jumped: the band reaches well above a full jump).
]]

local Hit = {}

Hit.JUMP_CLEAR = 4.2 -- root this high above the floor = feet above a low beam
Hit.REACH_BELOW = 4.5 -- a root further than this below the beam is under the platform: no hit
Hit.REACH_ABOVE = 8 -- a high beam still catches a root this far above it (covers a boosted jump apex)

function Hit.check(
	kind: string,
	laserY: number,
	floorY: number,
	rootY: number,
	sliding: boolean,
	horizontallyInside: boolean
): boolean
	if not horizontallyInside then
		return false
	end
	-- A beam is never below the floor, so a smaller laserY is a height relative to the floor.
	if laserY < floorY then
		laserY += floorY
	end
	if rootY < laserY - Hit.REACH_BELOW then
		return false
	end
	if kind == "low" then
		return rootY < floorY + Hit.JUMP_CLEAR
	elseif kind == "high" then
		return not sliding and rootY <= laserY + Hit.REACH_ABOVE
	end
	return false
end

return Hit
