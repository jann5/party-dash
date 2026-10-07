-- Party Dash Core: debug hooks (workspace attributes, see docs/ARCHITECTURE.md "Debug hooks").
-- Every hook is honored ONLY in Studio: on a live server each getter returns its default, so an attribute that was
-- left in the saved place can never change real games. Values are read live so critics can toggle them mid-test.
local RunService = game:GetService("RunService")

local Debug = {}

Debug.ENABLED = RunService:IsStudio()
Debug.FAST_PHASE_SECONDS = 2
Debug.HOOKS = {
	"Debug_ForceMinigame",
	"Debug_ForceModifier",
	"Debug_FastIntermission",
	"Debug_NoEliminate",
	"Debug_IntensityOverride",
	"Debug_AutoQueue",
	"Debug_FreeRevive",
	"Debug_ForceVote",
	"Debug_SuddenDeathAt",
}

local function read(name: string): any
	if not Debug.ENABLED then
		return nil
	end
	return workspace:GetAttribute(name)
end

local function str(name: string): string?
	local v = read(name)
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

local function positive(name: string): number?
	local v = read(name)
	if type(v) == "number" and v == v and v > 0 and v < math.huge then
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

function Debug.forceVote(): string?
	return str("Debug_ForceVote")
end

function Debug.fast(): boolean
	return read("Debug_FastIntermission") == true
end

function Debug.noEliminate(): boolean
	return read("Debug_NoEliminate") == true
end

function Debug.autoQueue(): boolean
	return read("Debug_AutoQueue") == true
end

function Debug.freeRevive(): boolean
	return read("Debug_FreeRevive") == true
end

function Debug.intensityOverride(): number?
	return positive("Debug_IntensityOverride")
end

function Debug.suddenDeathAt(): number?
	return positive("Debug_SuddenDeathAt")
end

-- Lobby/Roulette/ModifierRoulette/Intro/End length, shortened by Debug_FastIntermission.
function Debug.phaseTime(seconds: number): number
	if Debug.fast() then
		return math.min(seconds, Debug.FAST_PHASE_SECONDS)
	end
	return seconds
end

-- Boot report: in Studio, lists the active hooks; on a live server, says that leftovers are ignored.
function Debug.report()
	local found = {}
	for _, name in Debug.HOOKS do
		local v = workspace:GetAttribute(name)
		if v ~= nil and v ~= false and v ~= "" then
			table.insert(found, ("%s=%s"):format(name, tostring(v)))
		end
	end
	if #found == 0 then
		return
	end
	if Debug.ENABLED then
		warn("[Core] DEBUG HOOKS ACTIVE (Studio): " .. table.concat(found, ", "))
	else
		warn("[Core] ignoring debug attributes left in the place (live server): " .. table.concat(found, ", "))
	end
end

return Debug
