--[[
Party Dash: MODIFIER CONTRACT (FROZEN).

A modifier is a ModuleScript  src/server/Modifiers/<Id>.lua  returning:
	id: string              -- equals the file name, e.g. "LowGravity"
	displayName: string     -- "LOW GRAVITY"
	description: string     -- one line for the roulette card
	intensityMultiplier: number?   -- e.g. Turbo = 1.5; folded into ctx.intensity()
	apply: (ctx) -> ()      -- called after the map is built, before the countdown
	clear: (ctx) -> ()      -- called after the round ends; MUST fully restore anything it changed

Core auto-discovers every ModuleScript in ServerScriptService.Server.Modifiers. Modifiers run every
Config.MODIFIER_EVERY-th round (never in Solo). Prefer per-player effects (only ctx.allPlayers()) so a
modifier never leaks into Solo copies running at the same time. Visual/physics effects that must run on
the client (Fog via Lighting, local workspace.Gravity) go in src/client/Modifiers/ and react to
GameState attribute "ModifierId" plus the player's "InRound" attribute.
]]

local Contract = {}

function Contract.validate(def: any): (boolean, string?)
	if type(def) ~= "table" then
		return false, "not a table"
	end
	for _, k in { "id", "displayName", "description" } do
		if type(def[k]) ~= "string" then
			return false, "missing " .. k
		end
	end
	if type(def.apply) ~= "function" or type(def.clear) ~= "function" then
		return false, "missing apply/clear"
	end
	return true
end

return Contract
