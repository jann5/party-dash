--!strict
-- Dodgeball: pure hit tests (no state, no Instances), shared by cannonballs and the golden ball.
--   Hit.ballHitsPlayer(ballPos, ballRadius, rootPos) -> boolean
--       true when the ball's center is closer than ballRadius + PLAYER_RADIUS to the HumanoidRootPart.
--   Hit.segmentHitsPlayer(fromPos, toPos, ballRadius, rootPos) -> boolean
--       the same test against the whole path a ball travelled during one frame (no tunnelling).
local Hit = {}

-- Rough "body radius" around the HumanoidRootPart (covers torso, head and legs of a standard rig).
Hit.PLAYER_RADIUS = 2.2

function Hit.ballHitsPlayer(ballPos: Vector3, ballRadius: number, rootPos: Vector3): boolean
	return (ballPos - rootPos).Magnitude < ballRadius + Hit.PLAYER_RADIUS
end

-- Closest point to `point` on the segment a -> b.
function Hit.closestPoint(a: Vector3, b: Vector3, point: Vector3): Vector3
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	if lengthSq < 1e-8 then
		return a
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSq, 0, 1)
	return a + ab * t
end

function Hit.segmentHitsPlayer(fromPos: Vector3, toPos: Vector3, ballRadius: number, rootPos: Vector3): boolean
	return Hit.ballHitsPlayer(Hit.closestPoint(fromPos, toPos, rootPos), ballRadius, rootPos)
end

return Hit
