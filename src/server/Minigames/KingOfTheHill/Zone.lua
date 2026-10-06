--!strict
-- King of the Hill: pure zone math (no instances, no state).
--   Zone.contains(center, radius, summitY, pos) -> boolean
--   Zone.radiusAt(elapsed) -> radius that shrinks smoothly from START_RADIUS to END_RADIUS
local Zone = {}

Zone.START_RADIUS = 11
Zone.END_RADIUS = 5
Zone.SHRINK_SECONDS = 90
Zone.BELOW = 1.5 -- a root may dip this far under the summit floor (crouch / slide)
Zone.ABOVE = 12 -- and be this high above it (jumping still counts)

-- center: the zone's center (a Vector3 or a CFrame; only X/Z are used).
-- summitY: Y of the summit floor surface. pos: a HumanoidRootPart position.
function Zone.contains(center: Vector3 | CFrame, radius: number, summitY: number, pos: Vector3): boolean
	local c: Vector3 = if typeof(center) == "CFrame" then (center :: CFrame).Position else center :: Vector3
	if typeof(pos) ~= "Vector3" or type(radius) ~= "number" or radius <= 0 then
		return false
	end
	local dx = pos.X - c.X
	local dz = pos.Z - c.Z
	if dx * dx + dz * dz > radius * radius then
		return false
	end
	return pos.Y >= summitY - Zone.BELOW and pos.Y <= summitY + Zone.ABOVE
end

-- Smooth (ease-in-out) shrink so the change is gentle at the start and settles at the end.
function Zone.radiusAt(elapsed: number): number
	local t = math.clamp(elapsed / Zone.SHRINK_SECONDS, 0, 1)
	local eased = t * t * (3 - 2 * t)
	-- Blend linear and eased so the zone visibly shrinks from the very first seconds.
	local k = 0.5 * t + 0.5 * eased
	return Zone.START_RADIUS + (Zone.END_RADIUS - Zone.START_RADIUS) * k
end

return Zone
