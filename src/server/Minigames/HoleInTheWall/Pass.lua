--[[
Hole in the Wall: the pure "did this player make it through this hole?" rule (no state, no Instances).

	Pass.check(holeType, holeMinX, holeMaxX, playerX, rootHeightAboveFloor, sliding) -> boolean

	holeType              "NORMAL" | "HIGH" | "LOW" (case-insensitive; "N"/"H"/"L" also work)
	holeMinX, holeMaxX    the hole's horizontal span in wall-local coordinates (studs)
	playerX               the HumanoidRootPart's position in the same wall-local coordinates
	rootHeightAboveFloor  HumanoidRootPart.Position.Y - floor Y (a standing R15 character is ~3)
	sliding               the character's server-side "Sliding" attribute

Vertical rules (deliberately a little generous, players should feel the wall was fair):
	NORMAL  ground-level doorway: pass unless you are at the very top of a big jump
	HIGH    raised window (bottom ~4.5 studs): you must be in the air, root >= HIGH_MIN_ROOT
	LOW     crawl gap (~3 tall): you must be sliding (or already flat on the floor)
]]
local Pass = {}

Pass.NORMAL_MAX_ROOT = 10 -- jump apex is ~9.9 with default jump power; only an upgraded super-jump fails
Pass.HIGH_MIN_ROOT = 4.3 -- standing root is ~3.2; a jump stays above this for about half a second
Pass.LOW_MAX_ROOT = 1.6 -- lower than this counts as crawling even without the Sliding flag

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- Normalizes a hole type to "NORMAL" | "HIGH" | "LOW" (or nil for anything else).
function Pass.normalize(holeType: any): string?
	if type(holeType) ~= "string" or holeType == "" then
		return nil
	end
	local first = string.upper(string.sub(holeType, 1, 1))
	if first == "N" then
		return "NORMAL"
	elseif first == "H" then
		return "HIGH"
	elseif first == "L" then
		return "LOW"
	end
	return nil
end

function Pass.check(
	holeType: string,
	holeMinX: number,
	holeMaxX: number,
	playerX: number,
	rootHeightAboveFloor: number,
	sliding: boolean?
): boolean
	local kind = Pass.normalize(holeType)
	if not kind then
		return false
	end
	if not (isFinite(holeMinX) and isFinite(holeMaxX) and isFinite(playerX) and isFinite(rootHeightAboveFloor)) then
		return false
	end
	local lo, hi = math.min(holeMinX, holeMaxX), math.max(holeMinX, holeMaxX)
	if playerX < lo or playerX > hi then
		return false
	end

	local h = rootHeightAboveFloor
	if kind == "NORMAL" then
		return h <= Pass.NORMAL_MAX_ROOT
	elseif kind == "HIGH" then
		return h >= Pass.HIGH_MIN_ROOT
	else
		return sliding == true or h <= Pass.LOW_MAX_ROOT
	end
end

return Pass
