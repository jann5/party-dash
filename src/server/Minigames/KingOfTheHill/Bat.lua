--!strict
-- King of the Hill: pure bat math (no instances, no state). Unit-testable from the command line:
--   local Bat = require(ServerScriptService.Server.Minigames.KingOfTheHill.Bat)
--   Bat.findTargets(CFrame.new(), { { id = 1, position = Vector3.new(0, 0, -4) } })  --> { 1 }
local Bat = {}

Bat.RANGE = 7.5 -- max horizontal reach in studs
Bat.HALF_ANGLE = math.rad(70) -- frontal cone: targets within 70 degrees of where the attacker faces
Bat.MAX_HEIGHT_DIFF = 6 -- ignore targets far above/below (other tiers of the hill)
Bat.COOLDOWN = 1
Bat.BASE_POWER = 95
Bat.RAMP = 0.6 -- power grows by +60% over the round
Bat.ROUND_SECONDS = 90

export type Candidate = { id: any, position: Vector3 }

-- Returns the ids of the candidates inside the frontal cone, nearest first.
function Bat.findTargets(attackerCFrame: CFrame, candidates: { Candidate }): { any }
	local origin = attackerCFrame.Position
	local look = attackerCFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		return {}
	end
	flatLook = flatLook.Unit
	local minDot = math.cos(Bat.HALF_ANGLE)

	local hits: { { id: any, dist: number } } = {}
	for _, c in candidates do
		-- Accept { id = x, position = v } and the positional form { x, v }.
		local raw = c :: any
		local id = if raw.id ~= nil then raw.id else raw[1]
		local pos = if raw.position ~= nil then raw.position else raw[2]
		if id ~= nil and typeof(pos) == "Vector3" then
			local offset = pos - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude
			if dist <= Bat.RANGE and math.abs(offset.Y) <= Bat.MAX_HEIGHT_DIFF then
				-- Someone standing right inside you counts as "in front" (no direction to measure).
				if dist < 0.5 or flat.Unit:Dot(flatLook) >= minDot then
					table.insert(hits, { id = id, dist = dist })
				end
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.dist < b.dist
	end)
	local ids = {}
	for i, h in hits do
		ids[i] = h.id
	end
	return ids
end

-- Knockback power for a swing: upgrade level 0..5 and seconds since the round started.
function Bat.power(batPowerLevel: number, elapsed: number, perLevel: number): number
	local level = math.clamp(if batPowerLevel == batPowerLevel then batPowerLevel else 0, 0, 10)
	local t = math.clamp(elapsed / Bat.ROUND_SECONDS, 0, 1)
	return Bat.BASE_POWER * (1 + level * perLevel) * (1 + Bat.RAMP * t)
end

-- Launch direction: away from the attacker, flattened, with a slight upward tilt.
function Bat.direction(attackerCFrame: CFrame, targetPosition: Vector3): Vector3
	local offset = targetPosition - attackerCFrame.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.2 then
		local look = attackerCFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return (flat.Unit + Vector3.new(0, 0.3, 0)).Unit
end

return Bat
