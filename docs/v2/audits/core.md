# Audit: core

**subsystem**: Core round loop, elimination, spectate, lobby flow (src/server/Core/*, src/server/Main.server.lua, src/shared/Knockback.lua, src/client/Core, src/client/Spectate, src/shared/Maps/Lobby.lua, src/server/Minigames/_Sandbox)

**howItWorks**: BOOT (src/server/Main.server.lua:10-26): Knockback.startServer() (creates remote Core_Knockback and runs a 0.1 s sweep that clears character attr Stunned), GameState.get(), Players.RespawnTime = 2, LightingSetup.apply(), Places.init() (Stands.build + Places.buildLobby + rescueLoop), PlayerSetup.init(), World.init(), Registry.init(Server), then RoundLoop.run() blocks forever.
WORLD: World.lua builds a Terrain water sea 2048x2048 whose surface is World.SEA_LEVEL = ARENA_CENTER.Y-62 = -12 (World.lua:14, 36-53: WaterColor 35,200,235, Transparency .25, Reflectance .6), 10 round floating islands 230-450 studs away, 9 sandy islets, 28 ball clouds (12 of them at y 5..25, between arena and sea), 3 hot-air balloons; all SmoothPlastic and Build.decorative (no collision). LightingSetup.lua:28-61 sets Brightness 3, ExposureCompensation +0.1, high Ambient/OutdoorAmbient, Atmosphere Density .24/Haze .6/Color 205,232,255, ColorCorrection Saturation .28/Brightness .03, Bloom .45/size 26/threshold 1.5.
LOBBY: Config.LOBBY_CENTER == Config.ARENA_CENTER == (0,50,0) (Config.lua:24,26). The lobby (Maps/Lobby.lua:505 Lobby.build) is a round pastel-tiled island of radius 60 with 32 invisible 60-stud walls and 12 invisible spawns. It is DESTROYED when a round's map is built (RoundLoop.lua:296 Places.destroyLobby) and rebuilt (~500 parts) in returnToLobby (RoundLoop.lua:177). Spectator stands (Stands.lua) are a permanent floating platform at ARENA_CENTER+(0,45,-110) with a hidden SpawnLocation (the only spawn in the place).
PHASE MACHINE (RoundLoop.run, RoundLoop.lua:380-408): Waiting (until #eligible()>=MIN_LOBBY_PLAYERS=1; eligible = not InSolo and alive character) -> Lobby (Config.LOBBY_TIME=15 s, aborts back to Waiting if eligible drops to 0) -> playRound (xpcall): pickMinigame (Debug_ForceMinigame, visible ids, no repeat) -> Roulette 5 s (MinigameId/RouletteReel written at start) -> optional ModifierRoulette 4 s every 5th round -> pickParticipants() (eligible, longest-waiting first, cap 12) -> Context.new + ctx:_build (pcall; on failure Registry.disableMinigame) -> destroyLobby -> ctx:_place(true) (anchored on spawns) -> participants InRound=true, everyone else Spectating=true and sent to the stands -> modifier.apply -> Intro 4 s -> Countdown 3x Announce.big + task.wait(1) -> ctx:_start() + Phase Round (PhaseEnd = duration for score kind, 0 for survival) -> poll ctx:_isOver() every 0.1 s -> ctx:_stop() -> modifier.clear -> Results.apply (leaderstats Wins/Streak, WinnersCsv, ResultText, confetti, Signals.RoundFinished -> Economy Rewards) -> End 6 s -> returnToLobby (ctx:_cleanup destroys the map, buildLobby, everyone InRound/Spectating=false and teleported to lobby spawns). Runphase durations marked fastable shrink to 2 s with Debug_FastIntermission (Debug.lua:40-45, RoundLoop.lua:49-64).
CONTEXT (Context.lua): one per running copy (main + Solo). Holds _all/_alive/_alivePlayers/_placements/_survived/_respawning. _start connects Heartbeat -> _step: for every alive participant NOT flagged _respawning, Health<=0 -> _onFall("died"), root.Y < killY -> _onFall("fell"). killY = center.Y - Config.KILL_DEPTH(30) unless the map sets attribute KillY. _onFall: score kind -> anchor in place, toast "Oops! Back in 2...", _respawnNow after 2 s (teleport to a random map spawn); survival -> _eliminate unless Debug_NoEliminate (then respawn on map). _eliminate sets placement = alive+1 and task.spawns params.onEliminated. End: survival >=2 participants alive<=1 "lastStanding", 1 participant alive==0 "allOut", score by duration, ctx.finish, SAFETY_ROUND_LIMIT 300 s. PlayerRemoving -> eliminate("left"); CharacterAdded -> _onCharacter re-places alive players.
ELIMINATION (RoundLoop.lua:258-280 onEliminated): writes GameState Alive, InRound=false, fires Signals.PlayerEliminated, sets Spectating=true, Places.sendToStands immediately, Announce.big(p,"YOU'RE OUT!", "You placed #x of y"). No death screen, no choice, no FX.
PLACES (Places.lua): route(player) -> stands if State.arenaActive else lobby (skips InSolo and players the main ctx owns). rescueLoop every 0.2 s: anyone (not InSolo) not alive in a RUNNING ctx with root.Y < RESCUE_Y (=20) is routed (lobby/stands); an alive player of a frozen/ended ctx goes to the stands. PlayerSetup: leaderstats Wins/Streak, InRound=false, Spectating=State.arenaActive, every CharacterAdded -> route.
KNOCKBACK (shared/Knockback.lua): server apply() validates, sets character Stunned/StunnedUntil, pushes velocity if the server owns the root, fires Core_Knockback to the owner; client sets PlatformStand + tumble, restores after stun (re-uprights root with +1.5 studs). src/client/Core/init.client.lua starts the client side and plays a POW! billboard + sparkles + camera shake whenever any character's Stunned flips true.
SPECTATE (client/Spectate/init.client.lua): ScreenGui SpectateGui; while Player.Spectating==true a bottom bar cycles CameraSubject through players with InRound==true (Prev/Next buttons, Q/E), STOP/WATCH toggles back to own humanoid; polls every 0.3 s. No server remotes, no lobby option.
SANDBOX (_Sandbox/init.lua): hidden survival test minigame (round platform, falling balls -> ctx.knockback); reference implementation, no fall handling of its own.


## bugs


---

**title**: Bug #16 root cause: score-kind fall handling teleports a pushed player back onto the map instead of eliminating him (King of the Hill)

**severity**: critical

**file**: src/server/Core/Context.lua

**line**: 295

**rootCause**: Context:_onFall (Context.lua:295-306) has a special branch for definition.kind == "score": on a fall it sets _respawning[p]=true, anchors the HumanoidRootPart where the player is (Teleport.setAnchored(p,true), line 299), toasts "Oops! Back in 2..." (line 300) and after SCORE_RESPAWN_DELAY=2 (line 81) calls _respawnNow -> Teleport.to(p, self:_randomSpawnFloor(), false) (line 274), i.e. a teleport back onto the map. King of the Hill is the only score minigame (KingOfTheHill/init.lua:64 kind="score", duration 90) and its whole point is bat bonks that knock people off (init.lua:273 ctx.knockback(..., BONK_STUN)). KOTH KillY = center.Y - 25 = 25 (KingOfTheHill/Map.lua:18, 392) while the sea surface is at -12 (World.lua:14), so the player sees himself falling toward the water, is frozen in mid-air ~37 studs above it, then teleported back. 'Sometimes' = only in KOTH rounds; every survival minigame (LaserTracer, Dodgeball, HoleInTheWall, Spin) eliminates. The owner's screenshot (docs/reference/current-game-koth.jpg) is KOTH with the sea right below.

**fix**: In Context:_onFall eliminate for every kind by default: `if Debug.noEliminate() then self:_respawnNow(p) return end; if self.definition.fallRule == "respawn" then <old score branch> return end; self:_eliminate(p, reason)`. KOTH is being replaced by Bomb Tag (survival), so no shipped minigame uses fallRule. Keep the score branch only behind the opt-in field. Also see the kill-plane/water and death-beat items, otherwise the death still looks like a teleport.

**evidence**: Context.lua:296-306; KingOfTheHill/init.lua:64,273; KingOfTheHill/Map.lua:18,392; World.lua:14; grep shows no other code calls ctx.respawn or Teleport.to for alive participants.


---

**title**: Debug hooks are honored on live servers and persist in the place file; nothing ever clears them

**severity**: major

**file**: src/server/Core/Debug.lua

**line**: 23

**rootCause**: Debug.fast/noEliminate/forceMinigame/forceModifier/intensityOverride read workspace attributes with no RunService:IsStudio() gate (Debug.lua:15-37). Critics set them in EDIT mode via execute_luau (docs/ARCHITECTURE.md:109), where workspace attributes are saved into the place. tools/studio_pull.luau only replaces scripts and never resets them, and Main.server.lua prints nothing. A leftover Debug_FastIntermission makes the lobby 2 s (Debug.phaseTime, Debug.lua:40-45; RoundLoop.lua:55-58), which looks exactly like complaint #14. A leftover Debug_NoEliminate makes every fall a respawn on the map (Context.lua:307-308, 318-321), which looks like #16. Debug_ForceMinigame would make every round the same game. If the place is published like this, live players get it too.

**fix**: Debug.lua: `local ENABLED = game:GetService("RunService"):IsStudio()`, and every getter returns its default (false/nil) when not ENABLED. Main.server.lua: in Studio, after boot, warn("[Core] DEBUG HOOKS ACTIVE: ...") listing every workspace attribute whose name starts with Debug_. Lead: append a reset loop to tools/studio_pull.luau (`for _, k in {"Debug_ForceMinigame","Debug_ForceModifier","Debug_FastIntermission","Debug_NoEliminate","Debug_IntensityOverride","Debug_AutoQueue"} do workspace:SetAttribute(k, nil) end`), and check the owner's place now with execute_luau(Edit): `local t={} for k,v in workspace:GetAttributes() do table.insert(t,k.."="..tostring(v)) end return table.concat(t,", ")`.

**evidence**: Debug.lua:15-45 (no IsStudio); tools/studio_pull.luau has no SetAttribute; ARCHITECTURE.md:79-83,109.


---

**title**: The lobby does not exist during a round, so 'go back to lobby' (#17) is impossible, and ~500 lobby parts are rebuilt every round

**severity**: major

**file**: src/server/Core/RoundLoop.lua

**line**: 296

**rootCause**: Config.LOBBY_CENTER == Config.ARENA_CENTER (Config.lua:24,26), so RoundLoop destroys the lobby when the arena is built (line 296 Places.destroyLobby()) and rebuilds it in returnToLobby (line 177 Places.buildLobby()). During a round every non-participant is forced to the stands (lines 305-311), and late joiners go there too (PlayerSetup.lua:42 + Places.route). There is nowhere to 'go back to', no hub for shop/wheel/chests during a round, and each rebuild replicates ~500 parts (≈170 tiles, 132 rainbow segments, 40 beads, decor) to every client at round end. Solo/Board.lua has to re-mount the TOP 10 every round (Board.lua:5,337-364).

**fix**: Make the lobby permanent at its own location: Config.LOBBY_CENTER = Vector3.new(0, 26, 420) (an island in the sea, see the lobby plan). Places.buildLobby only in Places.init; delete Places.destroyLobby() at RoundLoop.lua:296 and Places.buildLobby() at :177. returnToLobby only moves round members (participants + Spectating/Eliminated players) to the lobby. Non-participants stay in the lobby (remove the loop at :305-311). Places.route sends to the lobby unless Spectating is true while the arena is active. Solo/Runs.lua sendBack: always Places.sendToLobby (LOBBY_PHASES no longer needed).

**evidence**: Config.lua:24,26; RoundLoop.lua:170-185, 296, 305-311; Places.lua:22-46,78-88; PlayerSetup.lua:42.


---

**title**: Kill plane is 32-38 studs above the water and elimination is an instant cut to the stands, so a death never reads as a death

**severity**: major

**file**: src/server/Core/World.lua

**line**: 14

**rootCause**: The sea surface is at Y = -12 (World.lua:14 SEA_LEVEL = ARENA_CENTER.Y - 62; FillBlock -28..-12 at :43-51), but killY is 20 by default (Context.lua:105, Config.KILL_DEPTH 30), 25 in KOTH and 26 in Spin, and Places.RESCUE_Y is 20 (Places.lua:16). Nobody ever touches the water. In survival, onEliminated teleports the player to the stands in the same frame (RoundLoop.lua:271-272), with only a text banner (Announce.big :278), no splash, sound or camera hold. To a kid this reads as 'I was teleported'. Solo copies copy the same 62-stud drop (Solo/Backdrop.lua:20).

**fix**: Make the water the kill plane. World.SEA_LEVEL = Config.ARENA_CENTER.Y - Config.KILL_DEPTH - 1.5 (=18.5), so the default killY (root Y 20) is reached exactly when the feet enter the water. Solo/Backdrop.lua SEA_DROP = Config.KILL_DEPTH + 1.5. Move the low clouds (World.lua:212-217, Backdrop.lua:101-106) above the water or delete them. In Context:_build clamp `self.killY = math.max(mapKillY, self.center.Position.Y - Config.KILL_DEPTH)` so no map can put killY below the sea (no swimming possible). Add a death beat: on reason 'fell', fire a splash FX (server Fx.splash(pos) or remote Core_Death with pos) and sound rbxasset://sounds/impact_water.mp3, anchor the root at the splash for Config.DEATH_BEAT=1.0 s, then park the player (see #17 plan).

**evidence**: World.lua:14,43-51; Context.lua:105,395; Places.lua:16; RoundLoop.lua:271-278; KingOfTheHill/Map.lua:392; Spin/Arena.lua:32,335.


---

**title**: _respawning blind spot: a player flagged _respawning is never fall-checked by the Context or by the rescue loop

**severity**: major

**file**: src/server/Core/Context.lua

**line**: 388

**rootCause**: _step skips any player with _respawning[p] (line 388). rescueLoop also skips him because inRunningRound = ctx._running and ctx.isAlive(p) is true (Places.lua:96). _respawning stays true forever when _onCharacter's WaitForChild("HumanoidRootPart",5) times out or Teleport.to fails (lines 274-277, 286-291), or after _place failed at Intro (line 472). That player can fall into the sea and swim indefinitely (no death, alive count never drops), and a 1-participant survival round cannot end until SAFETY_ROUND_LIMIT (300 s).

**fix**: Store `_respawningSince[p] = os.clock()` wherever _respawning[p] is set. In _step: if _respawning[p] and os.clock()-since > 3, retry self:_respawnNow(p); if > 8 s, self:_eliminate(p, "stuck"). Independently of _respawning, if the root exists, is not Anchored and root.Y < killY, call _onFall. Clear _respawningSince wherever _respawning is cleared.

**evidence**: Context.lua:270-293, 388, 466-474; Places.lua:96-98.


---

**title**: Rescue loop parks alive participants on the stands during Intro/Countdown without eliminating or re-placing them

**severity**: minor

**file**: src/server/Core/Places.lua

**line**: 99

**rootCause**: When the ctx exists but is not running (Intro/Countdown, or End), an alive participant below RESCUE_Y is sent to the stands (Places.lua:99-101) but stays _alive and InRound=true. If it happens before _start, after GO the player is 'alive' on the stands at Y≈95 > killY forever: the survival round can't end (1 participant) or he wins from the stands (2+).

**fix**: In rescueLoop: if ctx and ctx.isAlive(p) and not ctx._stopped (Intro/Countdown), call ctx:_respawnNow(p), which puts him back on the map anchored (it uses ctx._frozen). Only after _stop (End) send to the stands.

**evidence**: Places.lua:90-109; Context.lua:270-279, 460-476.


---

**title**: Lobby countdown restarts when the only player resets (eligible() requires a live character)

**severity**: minor

**file**: src/server/Core/RoundLoop.lua

**line**: 392

**rootCause**: The Lobby abort predicate is #eligible() < MIN_LOBBY_PLAYERS and eligible() requires Teleport.parts(p) (alive Humanoid). A single player who resets (RespawnTime 2 s) or dies in the lobby aborts the phase, goes to Waiting, then the full Lobby timer restarts. Same when the only player starts a Solo run (P10 note).

**fix**: Abort the Lobby only when #Places.audience() == 0. Use the queue (Queued attribute) only at the moment the Lobby timer ends (see #26 plan).

**evidence**: RoundLoop.lua:69-77, 384-394.


---

**title**: Crash path never clears the active modifier: Giant/Tiny scale stays on characters

**severity**: minor

**file**: src/server/Core/RoundLoop.lua

**line**: 396

**rootCause**: If playRound errors after modifier.apply (line 317-322), modifier.clear (line 348-353) never runs. returnToLobby calls ctx:_cleanup() first (line 175), which cleans ctx.trove, including CharacterEffect's InRound listener (Modifiers/_Lib/CharacterEffect.lua:91-95), and only then sets InRound=false. Nothing restores scale and Mod_Active stays set.

**fix**: Keep `State.modifier = {def=modifier, ctx=ctx}` when applied. In returnToLobby (and the xpcall failure branch), pcall(modifier.clear, ctx) BEFORE ctx:_cleanup() if it was not cleared, then nil it.

**evidence**: RoundLoop.lua:170-185, 317-322, 347-353, 396-405; CharacterEffect.lua:80-108.


---

**title**: Countdown, GO and results banners go to everyone in the server, not to the round's audience

**severity**: minor

**file**: src/server/Core/RoundLoop.lua

**line**: 328

**rootCause**: Announce.big(Places.audience(), ...) for 3-2-1/GO (lines 328, 335), ctx audience = Places.audience (line 256), and Results.apply announces to Places.audience() (Results.lua:110). Today that is fine because everyone is on the stands. With a permanent lobby (needed for #17/#26), lobby players would get countdown numbers and 'YOU'RE OUT'-style spam over their shop/wheel UI. The P3 UI overlays are driven purely by GameState.Phase (client/UI/Hud.lua:19-28, Intro.lua:336, Results.lua:366), so they would also cover lobby players.

**fix**: Add RoundLoop.roundAudience() = participants + players with Spectating==true or Eliminated==true (not InSolo), and use it for the countdown, GO, ctx audience and Results.big. Keep feed lines to everyone. Clients gate the Intro/Countdown/Results overlays on 'InRound or Spectating or Eliminated' (new derived rule for the UI piece).

**evidence**: RoundLoop.lua:256, 328, 335; Results.lua:109-114; client/UI/Hud.lua:19-28.


---

**title**: A minigame is permanently removed after one build error and its MinigameInfo stays published

**severity**: minor

**file**: src/server/Core/Registry.lua

**line**: 139

**rootCause**: RoundLoop.lua:286-288 calls Registry.disableMinigame on any create() error; disableMinigame (Registry.lua:139-145) removes it for the server's lifetime but leaves ReplicatedStorage.MinigameInfo.<Id>. One transient error kills a mode for hours on a live server.

**fix**: Count failures per id. Disable only after 3 consecutive build failures, and also set MinigameInfo.<Id>:SetAttribute("Disabled", true). Reset the counter on a successful build.

**evidence**: RoundLoop.lua:282-292; Registry.lua:139-145.


---

**title**: Single-player survival rounds always end with a red 'NOBODY SURVIVED!'

**severity**: minor

**file**: src/server/Core/Results.lua

**line**: 89

**rootCause**: With 1 participant, the survival end condition is alive==0 (Context.lua:360), _results gives no winners (Context.lua:573), and Results.apply prints 'NOBODY SURVIVED!' in red (Results.lua:89-97). A kid alone in a fresh server only ever sees failure screens (bad for retention #6/#19).

**fix**: For #participants==1: text = 'YOU LASTED 34.2s', sub = 'Personal best: X' (read Solo Records.getBest for that minigame if available) in Yellow, plus the 'Bring friends!' line. Keep no Wins increment.

**evidence**: Context.lua:357-362, 571-578; Results.lua:85-101.


---

**title**: Knockback restore lifts the root 1.5 studs every time a stun ends tilted (micro-teleport that can pop players onto ledges)

**severity**: minor

**file**: src/shared/Knockback.lua

**line**: 153

**rootCause**: restore() sets root.CFrame = uprightCFrame(root), whose position is root.Position + (0,1.5,0) (Knockback.lua:126-138, 153-155). This happens whenever UpVector.Y < 0.9 when the stun ends. A player lying against a wall or pillar base gets popped up 1.5 studs, which can put him on top of small ledges (relevant to #22's 'small piece of wall you can stand on').

**fix**: Raycast down from the root (exclude the character). Only lift by max(0, standHeight - groundDistance). Otherwise keep the same position and only fix the rotation: root.CFrame = CFrame.lookAt(root.Position, root.Position + flat).

**evidence**: Knockback.lua:126-157.


## briefPlans


---

**briefItem**: #16 Water fall bug: pushed into the water, didn't die, got teleported back

**currentState**: Every code path that rescues/teleports instead of eliminating: (1) Context:_onFall score branch (Context.lua:296-306), the actual trigger: KOTH is kind=score (KingOfTheHill/init.lua:64), bat bonk push (init.lua:273), KillY 25 (Map.lua:392), player frozen mid-air (line 299) with toast 'Oops! Back in 2...' then Teleport.to a random spawn (line 274). (2) Debug_NoEliminate (Context.lua:307-308, 318-321) respawns on every fall if the attribute was left in the place file (not gated by IsStudio). (3) Places.rescueLoop (Places.lua:90-109) teleports anyone not alive in a RUNNING ctx below RESCUE_Y=20 (lobby, stands, Intro/Countdown, End). (4) The _respawning blind spot (Context.lua:388 + Places.lua:96): never fall-checked, can swim forever. (5) Survival elimination itself is an instant teleport to the stands (RoundLoop.lua:272) with no FX, so it reads as 'teleported'. Water vs killY: sea surface -12 (World.lua:14), killY 20/25/26, so nobody can ever reach or swim in the water today. Humanoid Swimming is impossible in the main arena and in Solo (same 62-stud drop, Solo/Backdrop.lua:20). Stunned/PlatformStand doesn't affect the server Y check (_step reads replicated root.Position). Solo vs main: same Context code. Solo has no rescue (InSolo skipped) and KOTH is soloCapable=false.

**plan**: 1) Context.lua _onFall: `if Debug.noEliminate() then self:_respawnNow(p) return end; if self.definition.fallRule == "respawn" then <old score code> return end; self:_eliminate(p, reason)`. Add optional definition field fallRule ("eliminate" default). Remove KOTH from the roulette (Bomb Tag replaces it, #10). 2) Kill at the water: World.SEA_LEVEL = Config.ARENA_CENTER.Y - Config.KILL_DEPTH - 1.5 (18.5). Solo/Backdrop.lua SEA_DROP = Config.KILL_DEPTH + 1.5 (line 20; used at :45 and :87). Raise the low clouds out of the water or delete them (World.lua:212-217, Backdrop.lua:101-106). In Context:_build clamp killY = math.max(mapKillY, center.Y - Config.KILL_DEPTH). 3) Death beat: new src/server/Core/Death.lua. On reason 'fell': position = Vector3.new(root.X, SEA_LEVEL, root.Z), fire remote Core_Death to the victim and Core_Fx('splash', pos) to the round audience. The client plays a splash ParticleEmitter (white/cyan, 30 particles, speed 25-40, up) and Sound rbxasset://sounds/impact_water.mp3. Anchor the root for Config.DEATH_BEAT = 1.0 s (the camera stays on the splash), then park per #17. Reason 'exploded' (Bomb Tag) uses an explosion puff, 'died' a poof. 4) Blind spot: _respawningSince + retry at 3 s, eliminate 'stuck' at 8 s; check Y even while _respawning if not anchored. 5) rescueLoop: during Intro/Countdown call ctx:_respawnNow(p) instead of sendToStands. 6) Gate Debug hooks with RunService:IsStudio() and warn at boot. Verification (critic): Debug_ForceMinigame=LaserTracer, Debug_AutoQueue=true, 2 players (Studio 2-player test), knock yourself off: Eliminated=true, InRound=false, GameState.Alive decrements, splash visible, never placed back on the map; repeat with Debug_NoEliminate=true to confirm the hook still works in Studio.

**risks**: Raising the sea changes every arena backdrop: map undersides (Spin rock island, Sandbox under-discs to y≈27) will dip into the water. Fine visually, but each map owner must check. Without KOTH there is no score minigame, so Scoreboard/ScoresJson paths go untested.


---

**briefItem**: #14 20 seconds in the lobby after every round before the roulette

**currentState**: Order today: End (Config.END_TIME 6 s, on the arena) -> returnToLobby -> Lobby phase Config.LOBBY_TIME = 15 s (Config.lua:9; RoundLoop.lua:392 runPhase(Phase.Lobby, Config.LOBBY_TIME, true, abort)) -> Roulette 5 s -> optional ModifierRoulette 4 s -> Intro. Lobby is 'fastable': with workspace Debug_FastIntermission=true, Debug.phaseTime returns 2 s (Debug.lua:40-45) and runPhase fast-forwards mid-phase (RoundLoop.lua:55-58), so a leftover attribute gives a ~2 s lobby (likely what the owner saw). The lobby abort (eligible()<1) restarts the timer when the only player resets. The client 'NEXT GAME IN' pill (client/UI/Lobby.lua:130-156) just reads PhaseEnd.

**plan**: 1) Config.LOBBY_TIME = 20. 2) RoundLoop.run: the Lobby phase always runs the full LOBBY_TIME right after returnToLobby (and at boot), aborting only when #Places.audience()==0 (not on deaths/resets). 3) After the 20 s, require the join queue (#26): if QueuedCount >= 1 go to the Roulette. Otherwise setPhase(Phase.Lobby, 0) (open-ended; the UI caption becomes 'STEP INTO THE SQUARE TO PLAY!') and poll every 0.25 s. When someone queues, runPhase(Phase.Lobby, Config.JOIN_GRACE_TIME = 5, true, abort if QueuedCount==0) and then the Roulette. 4) Keep Debug_FastIntermission for critics but gate it with IsStudio (Debug.lua). Studio-only behaviour stays 2 s. 5) The lobby UI shows 'NEXT ROUND IN 0:20' plus a 'READY 3/12' sub-line (GameState.QueuedCount). Last 5 s: tick sound (already in Lobby.lua:150-152 for <=3 s). Downtime per cycle becomes End 6 + Lobby 20 + Roulette 5 (+4) + Intro 4 + Countdown 3 ≈ 38-42 s, so the lobby needs activities (wheel, chests, shop): another reason for the permanent lobby.

**risks**: The client Roulette/Hud code assumes Lobby always has PhaseEnd>0 except when waiting. The open-ended Lobby (PhaseEnd 0) must show the queue caption, not 'NEXT GAME SOON!' (Lobby.lua:155).


---

**briefItem**: #17 After dying: choose SPECTATE or GO BACK TO LOBBY

**currentState**: onEliminated (RoundLoop.lua:258-280) sets InRound=false, Spectating=true, teleports to the stands and sends Announce.big 'YOU'RE OUT!'. The Spectate client (client/Spectate/init.client.lua) turns on automatically on Spectating and cycles InRound players (candidates :151-165, Q/E, STOP/WATCH). There is no choice, no remote and no lobby to go to (destroyed during rounds, RoundLoop.lua:296).

**plan**: Server (new src/server/Core/Death.lua, called from RoundLoop's onEliminated): 1) Set Player attr Eliminated=true (new, cleared in returnToLobby) and InRound=false. 2) Death beat per #16 (1.0 s anchored at the impact point), then default park: Spectating=true + Places.sendToStands(p) (current behaviour, so doing nothing = spectating). 3) Fire remote Core_Death (S->C) to the victim with payload {reason: string, placement: number, total: number, survived: number, aliveLeft: number, minigameId: string, revive: {offered: bool, priceRobux: number, endsAt: serverTime, freeTokens: number}}. 4) Remote Core_DeathChoice (C->S, arg 'spectate'|'lobby'): validate the arg is one of the two strings, State.arenaActive, p:GetAttribute("Eliminated")==true or the player is a lobby player asking to watch, not InSolo, rate limit 0.3 s per player. 'lobby': Spectating=false, Places.sendToLobby(p) (requires the permanent lobby), player keeps Eliminated=true so returnToLobby still resets them. 'spectate': Spectating=true, Places.sendToStands(p). Also allow 'spectate' from the lobby for anyone not in the round (a 'WATCH LIVE' button/pad in the lobby) while State.arenaActive. 5) returnToLobby: for players with InRound or Spectating or Eliminated: clear all three and sendToLobby. Players already in the lobby are not touched. Client (UI piece): a DeathScreen in PartyHUD shown on Core_Death after the beat: big 'OUT! #5 of 8', 'lasted 23.4s', three big buttons SPECTATE (default, green), LOBBY (blue), REVIVE R$ N (gold, countdown ring until endsAt, hidden when not offered). Auto-close to SPECTATE after 10 s. The Spectate bar gets a 'LOBBY' button (fires Core_DeathChoice 'lobby'). Spectate client: candidates unchanged (InRound==true); activation stays on Spectating.

**risks**: Needs the permanent lobby (contract change: LOBBY_CENTER). If StreamingEnabled is on, spectators at the stands stream the arena (110 studs away). A lobby player choosing 'spectate' is teleported to the stands, so no ReplicationFocus juggling is needed.


---

**briefItem**: #28 Revive for Robux (re-enter the running round on the map)

**currentState**: Not implemented. Context has no way to make an eliminated player alive again (_eliminate is one-way, Context.lua:314-336). Economy Market.grant (Economy/Market.lua:21-46) only knows coin packs and upgrades. Config.PRODUCTS has no Revive key. CharacterEffect modifiers only listen for InRound -> false (CharacterEffect.lua:91-95), so a revived player would not get Giant/Tiny again.

**plan**: 1) Context:_revive(p): boolean. Return false if self._stopped or not self._running or self._over or self._alive[p] or not self._participant[p] or p.Parent ~= Players. Otherwise: _alive[p]=true; _alivePlayers+=1; _placements[p]=nil; _survived[p]=nil; _revives[p]=(_revives[p] or 0)+1; _deadSince[p] tracked so survived excludes dead time; set character attr ShieldUntil = serverTime+3; if Teleport.to(p, self:_randomSpawnFloor(), false) then _respawning[p]=nil else _respawning[p]=true (the CharacterAdded hook from Context.new already covers all _all players); task.spawn(params.onRevived, p). ctx.knockback (Context.lua:190-195) returns early while ShieldUntil > now. 2) RoundLoop onRevived: InRound=true, Spectating=false, Eliminated=false, GameState.write("Alive", ctx:_aliveCount()), Announce.feed(all, "X was REVIVED!"), Announce.big(p, "REVIVED!"), ForceField-style visual for 3 s, fire Signals.PlayerRevived (new). 3) New src/server/Core/Revive.lua: offers[p] = {ctx=ctx, round=State.roundNumber, expires=os.clock()+Config.REVIVE_WINDOW (10)}, created by Death when def.kind=='survival', reason not 'left'/'stuck', ctx:_aliveCount() >= 2 (the round must still be meaningful), and _revives[p] < Config.REVIVE_MAX_PER_ROUND (1). Player attr ReviveUntil = serverTime+10. Remote Core_ReviveRequest (C->S, no args): if the offer is valid, server calls MarketplaceService:PromptProductPurchase(p, Config.PRODUCTS.Revive) and extends expires by 15 s while the prompt is open (PromptProductPurchaseFinished clears it). If the player owns a free revive token (profile reviveTokens>0), consume it and call Revive.grant directly without a prompt. 4) Revive.grant(p): string?, called by Economy Market.grant when key=='Revive'. If offers[p] is valid and offers[p].ctx == State.ctx and ctx:_revive(p) then return 'REVIVED!'. Otherwise never lose the purchase: Sessions.addReviveToken(p) (new profile field reviveTokens) and return 'Round ended! Free revive saved for next time'. Market.processReceipt records the receipt as usual. 5) CharacterEffect.define: also connect InRound -> true and, when live(player), apply again. 6) Bomb Tag must skip players whose ShieldUntil > now when passing the bomb. Every minigame must tolerate a player re-appearing in ctx.players() (most iterate ctx.players() each tick; Dodgeball/Spin per-player tables need a nil-default check). 7) Price: R$ 15-25 (owner idea: cheap impulse buy). Show the price from MarketplaceService:GetProductInfo on the client.

**risks**: Pay-to-win perception: limit to 1 per round, only while >=2 players are alive, never in the last 1v1 (alive>=2 at purchase time, re-checked in _revive: require _alivePlayers >= 1 and not _over). Signals.PlayerEliminated can fire twice for one player per round (no consumer today, verified by grep). Revive purchases need real product ids (Config.PRODUCTS.Revive = 0 until created; the UI hides the button when 0).


---

**briefItem**: #26 Stand in a join square in the lobby to be queued for the next round

**currentState**: Participants = every player with a live character not in Solo (RoundLoop.eligible :69-77), picked at Intro by pickParticipants (:80-98, longest-waiting first via State.lastPlayed, cap Config.MAX_PLAYERS=12). There is no opt-in, so AFK players are always pulled in.

**plan**: 1) Lobby.lua builds a Model 'JoinZone' with a Part 'Zone' (28x14x28 volume, Transparency 1, CanCollide/CanQuery/CanTouch false, top of floor at lobby Y) plus the visible pad: green (60,215,90) checker floor with a neon border (0.6 studs, (120,255,140)), SurfaceGui 'PLAY' on the Top face, 4 corner light beams and a BillboardGui 'Board' (TextLabels Ready / Timer) 10 studs above. Lobby spawns sit 25-30 studs away in an arc facing the pad, so after every round people land OUTSIDE it. 2) New src/server/Core/Queue.lua, started in Places.init: every 0.2 s for each player in Places.audience(): queued = not InSolo and not InRound and not Spectating and Teleport.parts(p) and not root.Anchored and `local rel = zone.CFrame:PointToObjectSpace(root.Position)` with |rel.X|<=14, |rel.Z|<=14, -2<=rel.Y<=12. Write p:SetAttribute("Queued", queued) only on change, and GameState.write("QueuedCount", n) on change. A spatial check, not Touched (robust on mobile and for client-owned characters). On entering: Announce.toast(p, "You're in! Next round starts soon", Green) plus a client ding. On leaving: a toast. Debug_AutoQueue (Studio only) = everyone counts as queued, for single-player critic tests. 3) RoundLoop: replace eligible() with queued(): Queued==true and alive and not InSolo. At the START of the Roulette (before pickMinigame), snapshot participants = pickParticipants(queued()) (the existing lastPlayed sort, cap 12), so pickMinigame can filter by count (definition.minPlayers, e.g. Bomb Tag 2) and the roulette UI can show who is in. At Intro, drop snapshot players who left the server or are in Solo; dead ones are placed by Context when they respawn. If the snapshot is empty, return. Overflow beyond 12: toast 'Round full! You're first next round' (lastPlayed sort guarantees it). 4) Nobody queued: open-ended Lobby (PhaseEnd 0), no roulette, no map built (see #14). 5) Late joiners spawn in the lobby (move the only SpawnLocation from Stands.lua:161-173 into the lobby) and can queue at any time, even during a running round (they wait in the square). 6) AFK: after every round returnToLobby puts participants on spawns outside the square, so an idle player is never pulled twice. Also unqueue a player whose root hasn't moved more than 1 stud and who has had no humanoid MoveDirection for 90 s while queued (server-side check, no new remote). 7) Client hint (UI piece): when Phase==Lobby and Queued~=true, show 'WALK INTO THE GREEN SQUARE TO PLAY' with an arrow, plus a Beam from the HumanoidRootPart to the pad. Mobile gets the same (spatial).

**risks**: Pulling participants at roulette start instead of Intro changes P10's assumption (RoundLoop.eligible skips InSolo; a player who starts Solo after the snapshot must be dropped at Intro). If someone stands in the square during a round, they are picked next round without having seen the roulette: fine. Requires the permanent lobby.


---

**briefItem**: #2 / #4 / #32 Lobby and world backdrop must look like the references (blocky, bright, very pretty, not blending)

**currentState**: What is built: Lobby.lua is a round floating island at (0,50,0), radius 60: grass rim disc, white 'grout' disc, ~170 8-stud pastel tiles colored by rings from Theme.MapPalette and lerped 22% toward white on a checker (Lobby.lua:129-149), 3 dirt discs, 40 pink/yellow bead balls, yellow/white start pad, 'PARTY DASH' board on candy-cane posts with glass balloons, a 6-band rainbow arc of 132 parts, leaderboard + how-to-play panels (text says CLICK = Swing), lollipops, puff trees, mushrooms and gifts, 32 invisible 60-stud walls. World.lua: Terrain sea 62 studs below, 10 round floating islands and 9 islets far away (230-450 studs), ball clouds and balloons. Why it looks washed out and blending (current-game-koth.jpg): (a) LightingSetup.lua:30-61: Atmosphere Haze 0.6 + Density 0.24 with near-white Color 205,232,255 fogs everything past ~100 studs. ExposureCompensation +0.1, Brightness 3, high OutdoorAmbient 165,165,185 and Ambient 125,120,150 flatten shading (barely any shadows). ColorCorrection Brightness +0.03 and Bloom 0.45/size 26/threshold 1.5 make white and pastel surfaces glow (the white blob on the right of the screenshot). (b) Palette: Theme.MapPalette is pastel (all channels >=120), tiles are lerped toward white, KOTH uses white frosting and mint. The sea (35,200,235, 25% transparent, 0.6 reflectance) reflects the bright sky, so sea ≈ sky ≈ haze: no horizon, one cyan-white field. (c) No surface detail: Build.part/Lobby part() force SmoothPlastic with no Textures, so big flat areas show no scale or speed. The references use bevelled voxel grass, brick dirt cliffs, checker floors and dark seams, with bright top faces over darker side faces. (d) Round 'candy' shapes (discs, balls) against the blocky voxel reference. (e) The world is far away and small (islands 230-450 studs, sea 62 below), while the reference world sits right around the player.

**plan**: 1) LightingSetup.apply: ClockTime 13.6, GeographicLatitude 23, Brightness 2.6, ExposureCompensation 0, Ambient (95,95,115), OutdoorAmbient (128,128,140), ColorShift_Top (255,240,215), EnvironmentDiffuseScale 0.45, EnvironmentSpecularScale 0.25, ShadowSoftness 0.12. Atmosphere Density 0.12, Offset 0.35, Color (190,225,255), Decay (90,150,230), Glare 0, Haze 0.4. ColorCorrection Saturation 0.12, Contrast 0.14, Brightness 0, TintColor white. Bloom Intensity 0.2, Size 16, Threshold 2.4 (only Neon glows). SunRays 0.02. Add workspace.Terrain:FindFirstChildOfClass('Clouds') or a new Clouds instance (Cover 0.55, Density 0.7) and remove the ball clouds near the horizon. Set Lighting.Technology = ShadowMap/Future once in Studio (not settable from game scripts). 2) Water: replace the Terrain sea with a Part ocean: a 4x4 grid of 512x1x512 Parts whose top is World.SEA_LEVEL (18.5), Color (40,165,245), SmoothPlastic, opaque, CanCollide/CanQuery/CanTouch false, each with a Top-face Texture of assets/textures/waves.png tinted (150,220,255), Transparency 0.25, StudsPerTileU/V 40. The Core client scrolls OffsetStudsU/V slowly (0.6 stud/s) for the cartoon wave look of ref1. Around the lobby, a collidable sand shelf 3 studs under the surface so kids can wade (ref1 shows exactly that). Solo/Backdrop must use the same helper (World.ocean(center)). 3) Textures: upload assets/textures/{tile_bevel_2x2,bricks,checker,planks,speckle,studs,waves}.png (generated by tools/gen_textures.py, grayscale so Texture.Color3 tints them) and put the ids in a new shared module src/shared/Art.lua. Add Build.texture(part, key, color, studsPerTile, faces) so every map and the lobby use them: grass tops = bevel tinted (105,205,65)/(90,190,55) alternating per 12-stud block, cliff sides = bricks tinted (165,105,60) over dirt (150,95,55)/(125,78,45), sand = speckle on (245,220,150), wood = planks on (165,110,60), plaza = checker on (205,205,215). 4) Lobby rebuild (Maps/Lobby.lua, permanent at LOBBY_CENTER (0,26,420), floor 7.5 studs above the water): a square voxel island ~150x150 of 6-stud blocks with 2 stepped terraces and a sand beach into shallow water on the camera-facing side. Central checker plaza with the JOIN SQUARE (#26). Ring of stations, each exposed as a named anchor Part for other pieces to mount on: 'ShopAnchor' (stall with a red/white striped awning, ref2 'Boost Shop'), 'WheelAnchor' (20-stud wheel of fortune, #29), 'DailyChestAnchor' and 'GroupChestAnchor' (#27), 'SoloPortalAnchor', 'LeaderboardAnchor' (existing contract for Solo TOP 10), 'WinsBoardAnchor', 'TrailDisplayAnchor' (limited trail pedestal, #31), 'WatchAnchor' (live screen + spectate pad, #17). Wooden voxel fences on the edges (planks) instead of only invisible walls, blocky palms and cube trees (ref1/ref2), gray rock blocks, flower blocks, and a big chunky 'PARTY DASH' sign with an outlined gradient. Remove the rainbow arc, pastel ring tiles, white grout, beads, lollipops and mushrooms (candy theme fights the voxel reference). Keep the part count around 600-900 since it is built once. 5) World backdrop: blocky voxel islands (stacked cubes with bevel grass tops and brick sides), several sitting IN the water between the lobby and the arena so both look grounded. Keep 2 hot-air balloons. Keep the arena 30 studs above the water. 6) Theme (lead-owned): a saturated map palette (Grass 95,200,60 / GrassDark 75,175,50 / Dirt 150,95,55 / DirtDark 115,70,40 / Sand 240,215,140 / Stone 150,155,170 / Wood 165,110,60 / Water 40,165,245, accents Red 235,60,60, Yellow 255,200,40, Blue 45,125,245, Purple 140,80,240, Orange 255,140,30) replacing the pastel MapPalette for maps. Rule for every map: the floor reads against the water by value (darker grass/stone vs light water) and every walkable surface is textured. 7) Stands (Stands.lua): restyle as a wooden voxel grandstand (planks + bricks) and drop the glass balloons.

**risks**: Texture asset ids need an upload step (Studio MCP upload_image or Creator Hub); until then Art.lua must fall back to no texture. Part ocean has no swim physics (intended: water = out in arenas, wading in the lobby). Lighting.Technology cannot be set by scripts.


---

**briefItem**: #18 Fix all bugs (Core-specific list)

**currentState**: See the bugs array: debug hooks live in production, the _respawning blind spot, rescue loop parking alive participants, lobby-abort restart, modifiers not cleared on crash, announcements to everyone, permanent minigame disable, solo red screen, knockback 1.5-stud lift.

**plan**: Builder order (all Core-owned): Debug gate + boot warning -> Context (_onFall rule, killY clamp, _respawningSince, _revive, onRevived, ShieldUntil in knockback) -> Places (permanent lobby, route, per-region rescue: lobby rescue if root.Y < SEA_LEVEL - 10 or out of a 120-stud radius; stands rescue if root.Y < stands floor - 20; arena handled by Context) -> RoundLoop (queue, snapshot at roulette, roundAudience, returnToLobby only for round members, modifier clear on crash, minPlayers filter) -> Death.lua / Revive.lua / Queue.lua -> Knockback restore raycast -> Results solo text. Each item is verifiable in Studio with Debug_ForceMinigame=_Sandbox + Debug_AutoQueue.

**risks**: Several items touch contracts (Config, GameState, Lobby map exports, Signals). The lead must update ARCHITECTURE.md first so parallel pieces (UI death screen, Economy revive product, Bomb Tag) build against the same names.


---

**briefItem**: #10 Bomb Tag (Core support needed)

**currentState**: Core supports survival games with ctx.eliminate(p, reason). There is no per-minigame player minimum, so the roulette can pick a 1-player Bomb Tag. Elimination presentation is generic.

**plan**: 1) Optional definition field minPlayers (default 1). pickMinigame(count) skips ids with minPlayers > #participantsSnapshot (needs the snapshot at roulette start, #26). If nothing fits, fall back to any id. 2) Reason 'exploded' -> Death.lua plays an explosion puff + 'BOOM!' banner and a feed line ('X exploded!'). Signals.PlayerEliminated info gains a reason field. 3) Revive shield: Bomb Tag must not hand the bomb to a player whose character ShieldUntil > now. 4) Survival end rule unchanged (last one standing wins). Bomb Tag should call ctx.finish() itself if it wants a sudden-death cap. Publish MinPlayers on MinigameInfo for the roulette UI.

**risks**: KOTH removal: delete src/server/Minigames/KingOfTheHill and its client folder, or rename to _KingOfTheHill (hidden), so the roulette never lands on it.


---

**briefItem**: #25 Hit sound (Core client is the single place every knockback passes through)

**currentState**: src/client/Core/init.client.lua:111-125 already reacts to every character's Stunned=true with sparkles, a POW! billboard and camera shake for the local player, but plays no sound.

**plan**: In watchCharacter's Stunned handler: play a 3D Sound parented to the HumanoidRootPart (pool one Sound per character: rbxasset://sounds/impact_explosion_03.mp3 at PlaybackSpeed 2.2 or an uploaded 'bonk', Volume 0.6, RollOffMaxDistance 120), and a louder 2D version (SoundService:PlayLocalSound) when the victim is the local player. Route it through a SoundGroup 'SFX' so the settings menu (#23) can mute music separately from SFX.

**risks**: None. Keep one pooled Sound per character, no per-hit Instance.new.

**contractChanges**: Config.lua (values + new keys, lead-owned): LOBBY_TIME 15 -> 20; LOBBY_CENTER (0,50,0) -> (0,26,420) (permanent lobby, no longer == ARENA_CENTER); new SEA_LEVEL = ARENA_CENTER.Y - KILL_DEPTH - 1.5 (18.5, single source for World, Solo Backdrop, Lobby); new JOIN_GRACE_TIME = 5, DEATH_BEAT = 1.0, REVIVE_WINDOW = 10, REVIVE_MAX_PER_ROUND = 1, JOIN_ZONE_SIZE = Vector3.new(28,14,28); PRODUCTS.Revive = 0 (filled from Creator Hub).
GameState attributes (new): QueuedCount (number, players currently in the join square). Lobby phase may now have PhaseEnd = 0 meaning 'waiting for someone to step in the square' (Waiting stays 'no players in server'). Participants is written at Roulette start (snapshot).
Player attributes (new, Core-owned): Queued (bool, standing in the join square), Eliminated (bool, out of the current round; cleared when the round returns to the lobby), ReviveUntil (number, server time when the revive offer expires; 0/nil = none). Spectating keeps its meaning (on the stands watching) but becomes the default after death and opt-in for lobby players. Character attribute ShieldUntil (number, server time; ctx.knockback ignores the player and minigames must not target him).
Remotes (new): Core_Death (S->C victim payload {reason, placement, total, survived, aliveLeft, minigameId, revive={offered, priceRobux, endsAt, freeTokens}}), Core_DeathChoice (C->S 'spectate'|'lobby'; also used by lobby players to watch), Core_ReviveRequest (C->S, no args; server prompts the product or consumes a free token), Core_Fx (S->C ('splash'|'boom'|'poof', position: Vector3) to the round audience).
Signals.lua (frozen, needs lead): PlayerEliminated info += reason; new PlayerRevived(p, {minigameId, roundNumber}). PlayerEliminated may fire twice for a revived player.
Contracts/Minigame.lua (optional fields): fallRule 'eliminate'|'respawn' (default eliminate), minPlayers number (default 1). Minigames must tolerate a player re-entering ctx.players() after a revive and must skip players whose character ShieldUntil > now.
Context API (Core, documented in Context.lua header): ctx:_revive(p): boolean, params.onRevived(p), killY clamped to >= center.Y - KILL_DEPTH.
Maps/Lobby.lua exports (new extension points so Economy/UI/Solo pieces build independently): Model 'JoinZone' with Part 'Zone' + BillboardGui 'Board'; named anchor Parts ShopAnchor, WheelAnchor, DailyChestAnchor, GroupChestAnchor, SoloPortalAnchor, WinsBoardAnchor, TrailDisplayAnchor, WatchAnchor (existing LeaderboardAnchor and Spawns stay); the lobby SpawnLocation moves from Stands into the lobby.
New shared module src/shared/Art.lua (lead-owned): uploaded texture asset ids (Waves, Bevel, Bricks, Checker, Planks, Speckle, Studs) and a Build.texture helper contract. Theme.lua: a saturated map palette replacing the pastel MapPalette.
Debug hooks: all gated by RunService:IsStudio(); new Debug_AutoQueue (bool) = every player counts as queued. ARCHITECTURE.md: update the Player-attribute table, debug hooks, 'Run modes' (lobby persistent, arena separate) and the knockback/shield rules.
UI rule for the P3 owner: Intro/Countdown/Results overlays and Announce countdown only for 'round members' (InRound or Spectating or Eliminated), not for lobby players.

**qualityNotes**: 1) Debug hooks act on live servers (Debug.lua) and survive in the saved place. Gate them with IsStudio and print them at boot (highest-value one-liner). 2) The lobby is rebuilt every round (~500 parts: Lobby.build at RoundLoop.lua:177), which spikes replication at round end and forces Solo/Board.lua to re-mount. A permanent lobby removes this. 3) Solo/Backdrop.lua fills a 1536x1536x16 Terrain water block per Solo slot (up to 12 slots), several million water voxels that are never freed. With the Part ocean helper, share one ocean plane per slot or pool them. 4) Client-authoritative physics: the server trusts replicated root.Position for kills and knockback is applied by the client (Knockback.lua:99). An exploiter can ignore Core_Knockback or hover. Add a cheap server sanity check in Context._step: a player whose root stays > 25 studs above ctx.center.Y for > 3 s, or who has horizontal speed > 3x WalkSpeed outside Dashing/Stunned, gets snapped back or eliminated ('cheat'). 5) Spectate client polls candidates every 0.3 s and rebuilds lists (fine), but the camera hard-cuts between targets. Add a short CFrame lerp when switching. 6) Every Stunned flip creates a BillboardGui + TextLabel + 2 Tweens per character (client/Core/init.client.lua:39-83). Acceptable, but pool one billboard per character if Bomb Tag hits get frequent. 7) The countdown uses task.wait(1) x3 with no abort and Intro has no abort. If everyone leaves during Intro, the round still starts and ends instantly ('lastStanding'). Harmless, but add an abort to skip straight back to the lobby. 8) RoundLoop writes 'Alive' from inside a task.spawned callback. That is fine, but a revive must also write it, and Hud's 'x / y ALIVE' must handle alive going UP (client/UI/Hud.lua:285-292 only flashes on decrease). 9) Places.sendToLobby round-robins nextLobbySpawn and stacks players with random layers when there are more players than spawns. With a permanent lobby, use 16+ spawn points and jitter. 10) Stands boundary walls are 18 studs. With a future higher Jump Boost or a low-gravity spectator bug they could be cleared, so make them 30 studs. 11) Everything in Build.lua defaults to SmoothPlastic with no texture: the main reason maps 'blend'. Add Build.texture and make textured floors the default for map builders. 12) Registry.disableMinigame on one failure is too aggressive for live servers (see bugs).
