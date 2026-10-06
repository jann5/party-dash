--[[
Hole in the Wall: arena dimensions, escalation curves and wall/hole generation.
Pure functions plus read-only constants (no mutable module state), shared by the session and the builder.
]]
local Patterns = {}

-- Geometry (studs). The platform's top surface is at ctx.center.Y.
Patterns.PLATFORM = 64
Patterns.HALF = Patterns.PLATFORM / 2
Patterns.WALL_WIDTH = 66 -- a hair wider than the platform so nobody can hug the edge
Patterns.WALL_HEIGHT = 14
Patterns.WALL_THICK = 2
Patterns.START_DIST = -(Patterns.HALF + 4) -- wall plane offset (along its travel direction) when it enters
Patterns.FINISH_DIST = Patterns.HALF + 5 -- despawn once the wall plane passes this
Patterns.TELEGRAPH = 1.5 -- seconds of floor warning before a wall starts to move
Patterns.HOLE_EDGE_MARGIN = 1.5 -- solid wall kept at each wall end and between neighbouring holes

-- Hole shapes: base width, bottom and top (studs above the floor).
Patterns.HOLES = {
	NORMAL = { code = "N", width = 7, bottom = 0, top = 8 },
	HIGH = { code = "H", width = 7, bottom = 4.5, top = 10.5 },
	LOW = { code = "L", width = 8, bottom = 0, top = 3 },
}

Patterns.WALL_COLORS = {
	Color3.fromRGB(255, 95, 160), -- pink
	Color3.fromRGB(150, 100, 255), -- purple
	Color3.fromRGB(60, 120, 245), -- blue
	Color3.fromRGB(255, 85, 85), -- coral
}

export type Tuning = {
	speed: number, -- studs per second
	gap: number, -- seconds between wall spawns
	directions: number, -- how many travel directions are unlocked (1..4)
	holeCount: number, -- expected hole count (randomized +-0.5 per wall)
	widthScale: number, -- multiplier for hole widths
	specialShare: number, -- chance a hole is HIGH or LOW
	power: number, -- knockback power
}

export type Hole = {
	kind: string, -- "NORMAL" | "HIGH" | "LOW"
	minX: number,
	maxX: number,
	bottom: number,
	top: number,
}

-- Escalation from ctx.intensity() (1 at the start, +1 every Config.INTENSITY_RAMP_SECONDS, unbounded).
function Patterns.tuning(intensity: number): Tuning
	local i = math.max(1, intensity)
	local extra = i - 1
	local directions = if i < 1.6 then 1 elseif i < 2.2 then 2 elseif i < 3 then 3 else 4
	return {
		speed = math.min(45, 12 * (1 + 0.45 * extra)),
		gap = math.max(1.5, 5.5 / i ^ 0.9),
		directions = directions,
		holeCount = 3.2 - 0.55 * extra,
		widthScale = math.clamp(1 - 0.1 * extra, 0.65, 1),
		specialShare = math.clamp(0.25 + 0.2 * extra, 0.25, 0.85),
		power = math.min(240, 170 * (1 + 0.08 * extra)),
	}
end

-- Builds the hole list for one wall. wallIndex 1..3 is a mini tutorial: the first wall only has
-- doorways, the second always shows a JUMP window, the third a SLIDE gap.
function Patterns.makeHoles(rng: Random, tuning: Tuning, wallIndex: number): { Hole }
	local count = math.clamp(math.floor(tuning.holeCount + rng:NextNumber(-0.5, 0.5) + 0.5), 1, 3)
	local kinds = table.create(count, "NORMAL")
	if wallIndex > 1 then
		for k = 1, count do
			if rng:NextNumber() < tuning.specialShare then
				kinds[k] = if rng:NextNumber() < 0.5 then "HIGH" else "LOW"
			end
		end
		if wallIndex == 2 then
			kinds[rng:NextInteger(1, count)] = "HIGH"
		elseif wallIndex == 3 then
			kinds[rng:NextInteger(1, count)] = "LOW"
		end
	end

	-- One hole per equal segment keeps holes apart without any overlap checks.
	local usable = Patterns.PLATFORM - 2
	local segment = usable / count
	local holes: { Hole } = {}
	for k = 1, count do
		local shape = Patterns.HOLES[kinds[k]]
		local width = shape.width * tuning.widthScale
		local segStart = -usable / 2 + (k - 1) * segment
		local slack = segment - 2 * Patterns.HOLE_EDGE_MARGIN - width
		local minX = segStart + Patterns.HOLE_EDGE_MARGIN + (if slack > 0 then rng:NextNumber(0, slack) else slack / 2)
		table.insert(holes, {
			kind = kinds[k],
			minX = minX,
			maxX = minX + width,
			bottom = shape.bottom,
			top = shape.top,
		})
	end
	return holes
end

-- Wire format for the client: "N:-20.50:-13.50:0.00:8.00;H:..."
function Patterns.encodeHoles(holes: { Hole }): string
	local parts = table.create(#holes)
	for _, hole in holes do
		table.insert(
			parts,
			string.format(
				"%s:%.2f:%.2f:%.2f:%.2f",
				Patterns.HOLES[hole.kind].code,
				hole.minX,
				hole.maxX,
				hole.bottom,
				hole.top
			)
		)
	end
	return table.concat(parts, ";")
end

return Patterns
