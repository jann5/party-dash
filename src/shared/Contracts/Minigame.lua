--[[
Party Dash: MINIGAME CONTRACT (FROZEN; do not change without the lead's approval).

A minigame is a folder  src/server/Minigames/<Id>/  whose init.lua is a ModuleScript returning a
DEFINITION table. Core auto-discovers every child of ServerScriptService.Server.Minigames, so adding a
minigame never requires editing a shared list. Optional client code goes in src/client/Minigames/<Id>/
(an init.client.lua LocalScript that boots itself).

DEFINITION fields
	id: string            -- equals the folder name, e.g. "LaserTracer"
	displayName: string   -- "LASER TRACER"
	rules: string         -- one sentence for the roulette/intro card, e.g. "Jump the low lasers, slide under the high ones!"
	keys: { string }      -- control hints shown on the card, from: "Jump", "Slide", "Dash", "Swing", "Throw"
	kind: "survival" | "score"
	duration: number?     -- REQUIRED for kind == "score" (seconds); ignored for survival
	soloCapable: boolean  -- may it be played in Solo Record mode?
	create: (ctx: Context) -> Session

SESSION (returned by create; one per running copy: the main arena AND any number of Solo copies can run
at the same time, so NEVER keep mutable state at module level; keep it in the session/closure)
	map: Model            -- built inside create(); Core parents it. Required children/attributes:
	                      --   Folder "Spawns" with BaseParts (players are placed on them, round-robin)
	                      --   optional number attribute "KillY" (absolute Y), else ctx.killY default is used
	                      --   everything positioned relative to ctx.center (a CFrame), never world-absolute
	start: (self) -> ()   -- called when the countdown ends and players are unfrozen; begin hazards here
	stop: (self) -> ()    -- called once when the round ends for any reason; must stop all loops/threads.
	                      -- Core destroys `map` and calls ctx.trove:clean() right after stop().

CONTEXT (built by Core's Context.new; also used by Solo)
	ctx.center: CFrame          -- origin of this copy of the map (platform top-center)
	ctx.killY: number           -- default fall-elimination height (Core enforces it, not the minigame)
	ctx.isSolo: boolean
	ctx.modifier: string?       -- active modifier id or nil
	ctx.trove: Trove            -- put every connection/instance/thread here; Core cleans it
	ctx.players: () -> { Player }        -- players currently ALIVE in this session (copy of the list)
	ctx.allPlayers: () -> { Player }     -- everyone who started this session
	ctx.isAlive: (Player) -> boolean
	ctx.elapsed: () -> number            -- seconds since start()
	ctx.intensity: () -> number          -- (1 + elapsed / Config.INTENSITY_RAMP_SECONDS) * modifier mult;
	                                     -- use it to scale hazard speed/spawn-rate. Grows without limit.
	ctx.eliminate: (Player, reason: string?) -> ()   -- survival: removes from alive (Core also does this on fall/death)
	ctx.addScore: (Player, amount: number) -> ()     -- score kind: adds to the player's score (ScoresJson)
	ctx.getScore: (Player) -> number
	ctx.knockback: (Player, direction: Vector3, power: number, stun: number?) -> ()
	        -- THE ONLY way to hit a player. direction is normalized internally (y component is respected,
	        -- Core adds a small upward lift). power ~ 60 = light shove, 120 = strong, 180 = launch off map.
	        -- Applied on the owning client (network ownership), with a short stun/ragdoll.
	ctx.respawn: (Player) -> ()          -- score kind: put the player back on a spawn (Core calls it after a fall)
	ctx.finish: () -> ()                 -- optional early end (e.g. score target reached)
	ctx.announce: (text: string, sub: string?, color: Color3?) -> ()  -- big center text to this session's players
	ctx.feed: (text: string) -> ()       -- small kill-feed line to this session's players

Character state the server can rely on (set by Movement P2 on the server, read by minigames):
	character:GetAttribute("Sliding")  -- true while sliding: hitbox is low, high obstacles must miss
	character:GetAttribute("Dashing")  -- true during a dash
	character:GetAttribute("Stunned")  -- true during knockback stun (set by Core's Knockback)
Jump detection on the server: compare HumanoidRootPart.Position.Y with the floor height (ctx.center.Y);
a jumping player's root is >= ~4.5 studs above the floor at the apex.
]]

local Contract = {}

function Contract.validate(def: any): (boolean, string?)
	if type(def) ~= "table" then
		return false, "definition is not a table"
	end
	for _, k in { "id", "displayName", "rules" } do
		if type(def[k]) ~= "string" or def[k] == "" then
			return false, "missing string field " .. k
		end
	end
	if def.kind ~= "survival" and def.kind ~= "score" then
		return false, "kind must be survival|score"
	end
	if def.kind == "score" and type(def.duration) ~= "number" then
		return false, "score minigames need duration"
	end
	if type(def.create) ~= "function" then
		return false, "missing create(ctx)"
	end
	if type(def.keys) ~= "table" then
		return false, "missing keys"
	end
	return true
end

return Contract
