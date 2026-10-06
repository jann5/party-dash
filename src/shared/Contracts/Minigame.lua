--[[
Party Dash: MINIGAME CONTRACT v2 (FROZEN; do not change without the lead's approval). [v2] marks additions.

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
	minPlayers: number?   -- [v2] fewest queued players for this game to be offered in the vote (default 1).
	                      --   Debug_ForceMinigame ignores it. Core mirrors it to MinigameInfo.<Id>.MinPlayers.
	icon: string?         -- [v2] Shared.Assets icon key for cards (e.g. "mg_bombtag"); mirrored as attribute Icon
	color: Color3?        -- [v2] card accent (default Theme.MinigameColors[id]); mirrored as attribute Color
	[v2] Every v2 game is kind "survival": you are out when you fall below KillY (no respawns; Core still
	supports "score" but nothing uses it). Default KillY = center.Y - Config.KILL_DEPTH (10), maps may set a
	higher KillY attribute, never a lower one. The sea surface is at Config.SEA_LEVEL.

SESSION (returned by create; one per running copy: the main arena AND any number of Solo copies can run
at the same time, so NEVER keep mutable state at module level; keep it in the session/closure)
	map: Model            -- built inside create(); Core parents it. Required children/attributes:
	                      --   Folder "Spawns" with BaseParts (players are placed on them, round-robin)
	                      --   optional number attribute "KillY" (absolute Y), else ctx.killY default is used
	                      --   everything positioned relative to ctx.center (a CFrame), never world-absolute
	start: (self) -> ()   -- called when the countdown ends and players are unfrozen; begin hazards here
	stop: (self) -> ()    -- called once when the round ends for any reason; must stop all loops/threads.
	                      -- Core destroys `map` and calls ctx.trove:clean() right after stop().
	onRevive: ((self, player: Player) -> CFrame?)?  -- [v2] optional: a player was revived (paid/free revive).
	                      -- Reset that player's per-session state and return where to put them (nil = a random
	                      -- spawn). Core gives them character attribute ShieldUntil = now + Config.SPAWN_SHIELD.
	                      -- Minigames MUST tolerate a player re-appearing in ctx.players() after elimination.

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
	ctx.knockback: (Player, direction: Vector3, power: number, stun: number?, attacker: Player?) -> boolean
	        -- THE ONLY way to hit a player. direction is normalized internally (y component is respected,
	        -- Core adds a small upward lift). power ~ 60 = light shove, 120 = strong, 180 = launch off map.
	        -- Applied on the owning client (network ownership), with a short stun/ragdoll.
	        -- [v2] Returns false (and does nothing) when the target is shielded (ShieldUntil > now) or not alive.
	        -- [v2] attacker = the player who caused it (bat, golden ball...): Core records KO credit
	        --      (Player attributes LastHitBy = attacker.UserId, LastHitAt = server time); a fall within
	        --      Config.KO_CREDIT_WINDOW seconds credits the attacker (feed "A [icon] B", +coins via Economy).
	        -- [v2] Plays the hit sound on the victim's client (Core).
	ctx.credit: (victim: Player, attacker: Player) -> ()   -- [v2] KO credit without a knockback (Bomb Tag pass)
	ctx.isShielded: (Player) -> boolean                    -- [v2] spawn/revive protection active
	ctx.respawn: (Player) -> ()          -- score kind: put the player back on a spawn (Core calls it after a fall)
	ctx.finish: () -> ()                 -- optional early end (e.g. score target reached)
	ctx.announce: (text: string, sub: string?, color: Color3?) -> ()  -- big center text to this session's players
	ctx.feed: (text: string) -> ()       -- small kill-feed line to this session's players

Character state the server can rely on (set by Movement on the server, read by minigames):
	character:GetAttribute("Sliding")  -- true while sliding: hitbox is low, high obstacles must miss
	character:GetAttribute("Dashing")  -- true during a dash
	character:GetAttribute("Stunned")  -- true during knockback stun (set by Core's Knockback)
	character:GetAttribute("ShieldUntil") -- [v2] server time; hazards must ignore the player before it

[v2] HIT JUDGING (fixes "I jumped and still got hit", brief #22): the server sees a client-owned character about
one ping late. NEVER decide "jumped over / slid under" from the current server position alone. When a hazard
crosses a player at server time t, ask Movement's Forgive module, which keeps ~1.5 s of per-player samples:
	local Forgive = require(ServerScriptService.Server.Movement.Forgive)
	task.spawn(function()
		-- YIELDS ~0.1-0.45 s until the lag window after t has been sampled. true = HIT, false = dodged.
		local hit = Forgive.judge(player, t, function(s) return s.feetY >= floorY + 1.0 end) -- jumped clear
		if hit and ctx.isAlive(player) then ctx.knockback(player, dir, power) end
	end)
	sample = { t, pos: Vector3, rootY, feetY (world Y of the feet, scale aware), sliding: boolean,
	           dashing: boolean, grounded: boolean }
	Forgive.samples(player, t0, t1) -> { sample } (non-yielding), Forgive.feetY(player) -> number? (now).
	A sample counts as sliding if the Sliding attribute was set OR the client-reported slide window covers it.

[v2] SHARED CODE: pure modules used by BOTH a minigame's server and client code live in
src/shared/Minigames/<Id>/ (ReplicatedStorage.Shared.Minigames.<Id>), owned by that minigame's piece.
Server-only helpers shared by several minigames live in src/server/Combat/ (the bat) and client ones in
src/client/Combat/. Never require modules out of StarterPlayerScripts from the server.
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
