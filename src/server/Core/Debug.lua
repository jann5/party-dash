-- Party Dash Core: debug hooks (workspace attributes, see docs/ARCHITECTURE.md "Debug hooks").
-- Read live every time so critics can toggle them during a playtest.
local Debug = {}

Debug.FAST_PHASE_SECONDS = 2

local function str(name: string): string?
	local v = workspace:GetAttribute(name)
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

function Debug.forceMinigame(): string?
	return str("Debug_ForceMinigame")
end

function Debug.forceModifier(): string?
	return str("Debug_ForceModifier")
end

function Debug.fast(): boolean
	return workspace:GetAttribute("Debug_FastIntermission") == true
end

function Debug.noEliminate(): boolean
	return workspace:GetAttribute("Debug_NoEliminate") == true
end

function Debug.intensityOverride(): number?
	local v = workspace:GetAttribute("Debug_IntensityOverride")
	if type(v) == "number" and v == v and v > 0 then
		return v
	end
	return nil
end

-- Lobby/Roulette/ModifierRoulette/Intro/End length, shortened by Debug_FastIntermission.
function Debug.phaseTime(seconds: number): number
	if Debug.fast() then
		return math.min(seconds, Debug.FAST_PHASE_SECONDS)
	end
	return seconds
end

return Debug
