export const meta = {
  name: 'partydash-v2-wave2',
  description: 'Party Dash v2 gauntlet wave 2: Bomb Tag, Laser Tracer, Hole in the Wall, Spin+Combat, Dodgeball, Shop/Rewards UI, Social/Solo (builder + static critic + Studio critic per piece)',
  phases: [
    { title: 'Wave 2', detail: 'V7 Bomb Tag, V8 Laser Tracer, V9 Hole in the Wall, V10 Spin+Combat, V11 Dodgeball, V12 Shop UI, V13 Social/Solo' },
    { title: 'Wave-commit', detail: 'merge passed/failed piece branches into review/party-dash' },
  ],
}

const REPO = '/Users/jannawrot/Desktop/roblox-julek-temp'
const BIN = REPO + '/tools/bin'
const WAVE_BASE = '__WAVE2_BASE__'
const REVIEW = 'review/party-dash'
const STUDIO = '1b5de0b8-0002-4356-97ee-cb8249dc889e'
const MAX_ATTEMPTS = 3
const N_PIECES = 7
const AGENTS_PER_ATTEMPT = 3
const N_WAVES = 1
const SPAWN_CEILING_MULTIPLIER = 2
const WORST_CASE_SPAWNS = N_PIECES * MAX_ATTEMPTS * AGENTS_PER_ATTEMPT + N_WAVES
const SPAWN_CEILING = WORST_CASE_SPAWNS * SPAWN_CEILING_MULTIPLIER
let spawnCount = 0
function trackSpawn() {
  spawnCount++
  if (spawnCount > SPAWN_CEILING) {
    log(`SPAWN CEILING EXCEEDED: ${spawnCount} > ${SPAWN_CEILING}. Aborting.`)
    throw new Error('spawn ceiling exceeded')
  }
}
let studioQueue = Promise.resolve()
function withStudio(fn) {
  const run = studioQueue.then(() => fn())
  studioQueue = run.catch(() => null)
  return run
}

const BUILD_SCHEMA = {
  type: 'object',
  properties: {
    diffHash: { type: 'string' }, summary: { type: 'string' },
    branch: { type: 'string' }, worktreePath: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    contractGaps: { type: 'string' }, anomalies: { type: 'string' },
  },
  required: ['diffHash', 'summary', 'branch', 'worktreePath'],
}
const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    pass: { type: 'boolean' }, summary: { type: 'string' },
    failures: { type: 'array', items: { type: 'string' } },
    clauseResults: { type: 'array', items: { type: 'object', properties: { clause: { type: 'string' }, pass: { type: 'boolean' }, evidence: { type: 'string' } }, required: ['clause', 'pass'] } },
    commit: { type: 'string' },
  },
  required: ['pass', 'summary'],
}
const WAVE_SCHEMA = {
  type: 'object',
  properties: { reviewHead: { type: 'string' }, merged: { type: 'array', items: { type: 'string' } }, problems: { type: 'string' } },
  required: ['reviewHead', 'merged'],
}

const BRIEF = `PROJECT: "Party Dash" v2 overhaul, a Roblox party game (English UI, bright blocky saturated Roblox style like the owner's reference screenshots, PC + mobile, max 12 players).
Main repo checkout: ${REPO} (Rojo). The dev bridge tools/devserver.py runs on 127.0.0.1:8765.
The owner played v1 and wants EVERYTHING done PRECISELY: polished, juicy, readable, bug-free, "made by a professional Roblox studio", not AI slop.
MUST READ FIRST (in order): ${REPO}/docs/v2/DECISIONS.md, ${REPO}/docs/BRIEF-v2.md, ${REPO}/docs/ARCHITECTURE.md (v2 contracts: world layout, round flow, attribute + remote tables, Lobby model contract, UI conventions, testing, ownership), then the sections of ${REPO}/docs/v2/GAME_DESIGN.md and ${REPO}/docs/v2/ART_BIBLE.md and the audits in ${REPO}/docs/v2/audits/ that your spec names. Look at the reference screenshots ${REPO}/docs/reference/ref*.jpg (Read them, you can see images).
FROZEN (lead-owned, never edit): src/shared/Config.lua, Net.lua, GameState.lua, Theme.lua, Assets.lua, Art.lua, Audio.lua, UIKit/, Products.lua, Purchase.lua, Util/Trove.lua, Contracts/*, Maps/SpinArenaData.lua, src/server/Signals.lua, src/server/Announce.lua, default.project.json, selene.toml, stylua.toml, tools/, docs/, assets/. Read them to use them.
Tools (binaries only in the main checkout): ${BIN}/rojo, ${BIN}/selene, ${BIN}/stylua. Scene preview tools: ${REPO}/tools/scene_export.luau + ${REPO}/tools/render_scene.py (see ARCHITECTURE "Testing").`

const PIECES = {
  V7: {
    id: 'V7', name: 'Bomb Tag (new minigame, replaces King of the Hill)',
    owned: ['src/server/Minigames/BombTag/', 'src/client/Minigames/BombTag/', 'src/shared/Minigames/BombTag/', 'src/server/Minigames/KingOfTheHill/', 'src/client/Minigames/KingOfTheHill/'],
    ownedNote: 'You must DELETE src/server/Minigames/KingOfTheHill/ and src/client/Minigames/KingOfTheHill/ entirely (git rm -r). Another piece (Spin) ports the bat from those files using git show of the wave base, so you do not need to keep anything from them.',
    reads: 'GAME_DESIGN 2 (ALL of Bomb Tag), ART_BIBLE 7.5 + 4.2 (Toy Box palette) + 3.5 (Neon/Highlight budget), DECISIONS (minPlayers 2), Contracts/Minigame.lua v2 (ctx.credit, ctx.isShielded, onRevive, Forgive not needed), ARCHITECTURE, src/shared/Art.lua, src/shared/Economy/Cosmetics.lua (BombSkins table from the Economy piece), src/shared/Movement/CameraFx.lua + ActionButton.lua (if present), a finished minigame for structure (src/server/Minigames/_Sandbox and Dodgeball).',
    spec: `Brief #10: "everyone is teleported onto the map, one person spawns with the bomb, the bomb has a 10-second fuse, when the holder explodes another person gets the bomb; the map must be interesting, dynamic, with obstacles". Make it the most fun mode in the game.
1. DEFINITION (src/server/Minigames/BombTag/init.lua): id "BombTag", displayName "BOMB TAG", rules "Pass the bomb before it blows!", keys {"Dash","Jump","Slide"}, kind "survival", soloCapable false, minPlayers 2, icon "mg_bombtag". Session-safe (no module-level mutable state), everything relative to ctx.center, clean everything in stop().
2. MAP "Toy Box" (ART_BIBLE 7.5 + GAME_DESIGN 2.3): 96x96 floor of foam_mat (Theme.Maps.BombTag floor/floorAlt alternating 8x8 tiles) with 8x8 notched corners, a dark purple edge band then Art.cliffUnder (stone) down into the sea, red/white curb blocks on the rim; obstacles built from toy_block (Red/Yellow/Blue/Green, studs on top): center stage 20x20x4 with 8-wide ramps N and S and an E-W tunnel 6 wide x 3.0 high through it (only a sliding player fits: the Sliding hitbox), 4 corner towers 10x10x8 with step blocks, a 4-wide bridge at height 8 between the north towers, 4 juke walls 12x2.5x2 at (+-20,0)/(0,+-20), 8 columns 3x6x3, 4 jump pads (Lime Neon ring + arrow_jump decal; touching launches Y 70 + 18 toward the nearest tower, 0.8 s per-player cooldown; client applies the velocity for its own character), 2 speed strips (+12 WalkSpeed for 1.2 s). DYNAMIC: (a) a slow sweeper arm (red/white candy, Highlight outline) rotating around the center stage at floor level (bottom 0.6, top 1.8: jumpable; 1.0 rad/s; reverses every 15 s after a 1 s blink; hit -> ctx.knockback 45, stun 0.25, judged with the server position is fine for this slow arm); (b) RING DROPS: outer ring (|x| or |z| > 32) drops when alive <= 3 (and the second ring |x| or |z| > 20 except the center stage when alive == 2) after a 3 s red/white flash warning + rumble sound: tiles unanchor/fade/fall. Folder Spawns: 12 on a circle r 24 facing the center. KillY default.
3. RULES (server, Heartbeat): t=0 "SCATTER!" (ctx.announce), no bomb. t=2.0 s: the bomb goes to a random alive non-shielded player (never the first holder of the previous Bomb Tag round on this server if alternatives exist). Fuse 10.0 s from assignment; passing does NOT reset it. PASS: holder root and a target root within 5.0 studs horizontally and 4.5 vertically, target alive, not shielded, not holding a bomb, not the previous holder within 1.0 s (no tag-back), and the new holder cannot pass on for 0.35 s. Holder: WalkSpeed x1.2 (set on the server humanoid, restored on pass/elimination/stop), red Highlight (FillColor (255,40,40), pulsing FillTransparency, AlwaysOnTop), bomb model welded 3.5 studs above the head (Ball d 2.4, fuse, spark ParticleEmitter, PointLight) using the holder's BombSkin: Player attribute Cos_BombSkin -> require(ReplicatedStorage.Shared.Economy.Cosmetics).BombSkins[id] {color, material, accent} (fallback Classic). EXPLOSION at fuse end: ctx.credit(holder, lastPasser) if someone passed it to them, then ctx.eliminate(holder, "bomb"); shockwave knockback 70 (stun 0.35) to others within 14 studs (never lethal by itself), launch the holder's body up; BombTag_Fx "boom". BREATHER 2.0 s ("NEXT BOMB!" announce) then a new bomb to a random alive non-shielded player. Two bombs while >= 7 alive (second fuse offset +1.5 s; a holder cannot get a second bomb). Holder falls off / is eliminated by Core -> the bomb explodes at once where they were (no extra elimination), normal breather. Holder leaves -> the bomb moves to a random player with fuse = max(remaining, 5 s). onRevive: the revived player never holds a bomb; return a random spawn. With 1 participant (testing): the bomb goes to them and they explode at 10 s.
4. STATE CONTRACT: map attributes BombHolders (CSV UserIds), Explosions (count), Passes (count); character attributes HasBomb (bool), BombFuseEnd (server time); remote BombTag_Fx (server -> all clients; payloads {kind="assign"|"pass"|"boom"|"shrink", map=<map Model>, ...}); NO client -> server remote. Pure rules module src/shared/Minigames/BombTag/Rules.lua: Rules.canPass(holderPos, targetPos, now, info) -> boolean (info = {targetShielded, targetHasBomb, prevHolderId, targetId, lastPassAt, holderSince}), Rules.pickHolder(candidates: {userId}, excluded: {[userId]=true}, rng) -> userId?, Rules.tickInterval(remaining) -> seconds (1.0 above 6 s, 0.5 for 6-3, 0.25 for 3-1, 0.1 under 1).
5. CLIENT (src/client/Minigames/BombTag/, keyed by map Model, works for spectators too): bomb ticking (Audio "BombTick" 3D on the bomb at the Rules.tickInterval rate with pitch rising under 5 s; holder also 2D), blinking bomb body, BillboardGui countdown above the bomb (LuckiestGuy, white > 5 s, yellow 5-3, red < 3, punch every second), top pill per bomb in UIKit.Lanes "Top" (bomb icon + holder name + fuse to 0.1 s), holder screen: red edge vignette intensifying as the fuse runs out + CameraFx.shake under 2 s + banner "YOU HAVE THE BOMB!" when assigned (short) + "PASSED!" green flash for the passer; "TAG!" pop at the contact point + Audio "BombPass"; explosion: cartoon burst (Neon sphere 0->14 studs in 0.25 s then fade, smoke cubes, boom_burst/explosion icon billboard), Audio "Explosion", CameraFx.shake for players within 30 studs; ring-drop warning flash; jump pad launch for the local character. Clean all client objects when the map goes away.`,
    clauses: `Single client in Studio: Debug_ForceMinigame="BombTag" (forced ignores minPlayers), Debug_AutoQueue=true, Debug_FastIntermission=true.
V7-1 Round starts on the Toy Box map. Scene export of the map (root = the map Model) rendered iso + top + eye: purple foam floor, colorful toy blocks, center stage with a tunnel, towers + bridge, jump pads, cliffs into the sea; it looks distinct and fun (judge critically). The map has no part named or textured like v1 KotH.
V7-2 About 2 s after GO: character HasBomb=true, BombFuseEnd within 0.5 of now+10, map BombHolders contains the player's UserId, a bomb model is welded above the head (its position ~3.5 studs above the head while walking), Humanoid.WalkSpeed is ~1.2x the normal value.
V7-3 At fuse end: map Explosions=1, the player is eliminated (InRound=false; Core reason "bomb" if observable), the round ends (single participant). Client: during the fuse the countdown billboard text decreases and a "Top" lane bomb pill was visible (GUI capture), and the holder vignette was visible.
V7-4 Rules unit tests (Server execute_luau, require ReplicatedStorage.Shared.Minigames.BombTag.Rules): canPass true at 4 studs apart same height; false at 6 studs; false at 3 studs horizontal with 6 vertical; false when the target is the previous holder within 1.0 s; true for the previous holder after 1.2 s; false within 0.35 s of the holder receiving it; false when target shielded or already has a bomb. pickHolder never returns an excluded or shielded id when others exist; returns nil for an empty list. tickInterval(8)=1.0, (4)=0.5, (2)=0.25, (0.5)=0.1.
V7-5 Jump pad: teleport the character onto a jump pad -> root Y velocity > 50 within 0.3 s.
V7-6 Sweeper: the arm part rotates (orientation changes over 1 s) and has an outline Highlight.
V7-7 Ring drop: trigger it through your documented test hook (e.g. a map attribute ForceShrink=1 or calling the session API) -> within 4 s outer tiles fall (unanchored or moving down) after a visible warning.
V7-8 KingOfTheHill folders no longer exist in ServerScriptService/StarterPlayerScripts; ReplicatedStorage.MinigameInfo has BombTag (MinPlayers=2, Icon=mg_bombtag) and no KingOfTheHill. No module-level mutable state (code review).
V7-9 After the round the client has no leftover BombTag objects in workspace (other than the next map). No console errors from src/.`,
  },
  V8: {
    id: 'V8', name: 'Laser Tracer v2 (no center pillar, random lasers, both red with low/high shape language)',
    owned: ['src/server/Minigames/LaserTracer/', 'src/client/Minigames/LaserTracer/', 'src/shared/Minigames/LaserTracer/'],
    reads: 'GAME_DESIGN 3.0, 3.1 (ALL), ART_BIBLE 7.1 (the LOW/HIGH table, follow it exactly), 4.2 LT palette, 3.5, audits/mg-laser-spin.md (Laser Tracer parts with file:line), PLAYTEST (laser observations), Contracts/Minigame.lua "HIT JUDGING" + shared code location, src/server/Movement/Forgive.lua (merged), src/shared/Art.lua.',
    spec: `Briefs #13 and #15: lasers must ALL be RED but low vs high must be obvious; NO pillar in the middle; lasers move RANDOMLY.
1. MAP "Laser Lab": voxel disc r 42 (Art.voxelDisc, lt_tile / lt_tile_alt strips, steel cliffs down into the sea), 1.2-stud hazard_trim rim flush with the floor, NO central hub/pillar/dome/rings (delete buildHub and every hub part); the center tile carries a 6x6 decal of Assets icon mg_lasertracer; white emitter towers (3x10x3, dark cap, red Neon lens) on an outer steel rail ring at r 48 that visually slide to where each laser starts. Folder Spawns 12 points spread over the disc.
2. MOTION (shared pure module src/shared/Minigames/LaserTracer/Motion.lua; delete the server MotionRef.lua workaround): deterministic from server time + per-laser parameters encoded in state attributes (so server and every client agree): patterns "rotor" (an infinite line through a RANDOM pivot (px,pz) with |p| <= 14, rotating at +-0.45*I^0.6 rad/s capped 1.5; from intensity 1.8 up to 3 random reversal times encoded, each telegraphed 0.6 s ahead by a white flicker), "chord" (straight laser crossing the disc along a uniform random heading at Director slide speed), "bouncer" (from intensity 1.6: a chord that reflects at offset +-34, 1-2 times). Every heading/pivot/speed/direction/reversal comes from the session Random: two rounds never open the same way. Director schedule: t=0.6 rotor 1 (LOW), t=5 rotor 2 (HIGH) with its pivot on the other side, chords from t=7 every slideInterval, from intensity 1.6 bouncers replace 1 in 3 chords, rotor 3 at intensity 2.6, MAX_LASERS 6. FAIRNESS: before activating a laser simulate 0-3 s ahead (0.1 s steps, 4-stud floor grid, r <= 42): if any point is crossed by the new laser and a live laser of the OTHER kind within 0.9 s, switch the new laser to the same kind; if it still conflicts delay 1 s (max 3 retries) else drop it. Telegraph WARN_TIME 1.1 s.
3. LOOK (ART_BIBLE 7.1 table, both colour Theme.Colors.Laser (255,28,36)): LOW = "hurdle": thick solid red beam (Beam width 0.75), short white end posts 1.6 tall with red Neon caps the beam sits on, a red fence curtain from the floor up to the beam (gradient), one solid red floor line; HIGH = "limbo bar": thinner red beam (0.55) with an overlaid white dashed candy texture (Assets.Textures.laser_dash, scrolling), tall white poles 6.5 tall with a red ring at beam height, a red curtain hanging ABOVE the bar, two thin rails on the floor; telegraph uses arrow_jump (LOW) / arrow_slide (HIGH) icons, NO text. Hum sound pitch 0.9 (low) / 1.15 (high) (Audio "LaserHum" looped near each laser, quiet), zap "LaserZap" on hit.
4. HITS (server, src/shared/Minigames/LaserTracer/Hit.lua pure + server): candidate when the laser segment passes within 1.5 studs (XZ) of a player's root this frame -> Forgive.judge(player, t, clearTest) in a task: LOW clear = sample.feetY >= floorY + 2.0; HIGH clear = sample.sliding or sample.feetY >= floorY + 4.9. On hit: ctx.knockback(player, laser motion direction + outward, 75 scaled 1.0->1.25 with intensity, stun 0.5) + map attribute Hits += 1 + LaserTracer_Zap to clients; per-player hit cooldown 1.0 s; shielded players skipped. Keep map attributes Hits and LaserSpeed (rad/s of rotors).
5. Session-safe (no module-level mutable state; client renderer keyed by map Model, several maps at once), clean everything in stop(); client destroys every laser/curtain/sound when the map is gone.`,
    clauses: `Debug_ForceMinigame="LaserTracer", Debug_AutoQueue=true, Debug_FastIntermission=true, Debug_NoEliminate=true where noted.
V8-1 No center pillar: during a round, no collidable or visible part above floorY+0.6 lies within 8 studs (XZ) of the map center except lasers/beams and the player; no part named Hub/Column/Dome/Beacon exists.
V8-2 Both red: every laser beam/core part or Beam on the client has a Color whose R >= 0.9 and G, B <= 0.25 (the white candy overlay on HIGH is the only white). LOW lasers have short posts + a curtain BELOW the beam; HIGH lasers have tall poles + the dashed overlay + a curtain ABOVE (inspect the client objects for one LOW and one HIGH laser). Render a scene export (iso + eye) with at least one laser of each kind: judge whether you can tell low from high without text.
V8-3 Random: record the first two lasers' encoded parameters (pivot, heading, direction) in two separate rounds: they differ; at least one rotor pivot is >= 3 studs from the center.
V8-4 Shared module: ReplicatedStorage.Shared.Minigames.LaserTracer.Motion exists; the server does not require anything from StarterPlayerScripts (grep).
V8-5 Hits: Debug_NoEliminate=true, standing still: map Hits increases within 25 s and the root velocity spikes (knockback applied). Unit test the clear rules with fake samples through your Hit module API: LOW with feetY=floor+2.5 -> clear; floor+0.1 -> hit; HIGH sliding -> clear; HIGH standing -> hit.
V8-6 Escalation: Debug_IntensityOverride=1 vs 2.6: LaserSpeed at 2.6 >= 1.5x the value at 1; at 2.6 at least 4 lasers are active within 20 s.
V8-7 A falling player is eliminated (Debug_NoEliminate=false), round ends, no LaserTracer objects remain in workspace on the client or server afterwards. No console errors from src/.`,
  },
  V9: {
    id: 'V9', name: 'Hole in the Wall v2 (no text, varied simple hole shapes)',
    owned: ['src/server/Minigames/HoleInTheWall/', 'src/client/Minigames/HoleInTheWall/', 'src/shared/Minigames/HoleInTheWall/'],
    reads: 'GAME_DESIGN 3.0, 3.2 (shape catalog), ART_BIBLE 7.3 (bitmaps, Brick Run look), 4.2, audits/mg-wall-dodge-koth.md (Hole in the Wall parts with file:line), PLAYTEST, Contracts/Minigame.lua "HIT JUDGING", src/server/Movement/Forgive.lua, src/shared/Art.lua.',
    spec: `Brief #21: no "RUN/JUMP/SLIDE" text on walls (nothing written at all); holes are simple SHAPES that are not always the same.
1. SHAPES (pure shared module src/shared/Minigames/HoleInTheWall/Shapes.lua): a catalog of >= 12 pixel-art bitmaps on a 1-stud grid (rows top first, '#' = hole) including the GAME_DESIGN 3.2 set (DOOR, WIDE, ARCH, CROSS, STAIR, WINDOW, PORTHOLE, SLOT, TWIN, DIAMOND) plus ART_BIBLE 7.3 ones (star-man, mouse hole, porthole, heart, star, keyhole, house): each shape = { id, rows, bottom (studs above floor of the bitmap's bottom row), kind = "run" | "jump" | "slide", unlock (intensity) }. Shapes.passRects(shape) = union of row rectangles. Shapes.fits(shape, holeX0, bodyX, posture) where posture = "stand" (feet at 0, height 5.0, half width 0.9), "slide" (height 2.0, half width 1.0), or a jump sample (feet height h, height 5.0): the body rectangle must fit inside the union of pass rects. The bitmap MUST contain the clearance rectangle of its kind.
2. WALLS: 66 x 14 x 2 brick walls (Art brick_wall recipe tinted per wall from Theme.Maps.HoleInTheWall.walls, rotating Red/Blue/Purple/Orange), built from merged rectangles around the hole cells (greedy row merge; <= 60 parts per wall; pooled or destroyed after passing), hole inner faces = wall colour darkened 0.4 (crisp outline), dark Highlight outline on the wall. Per wall 1-3 holes, shapes drawn at random from the unlocked set (by intensity), never the same SET twice in a row; first 3 walls teach by shape only (DOOR/WIDE, then WINDOW, then SLOT). Walls come from 2-4 directions at higher intensity (keep v1 escalation: faster walls, shorter gaps, fewer/narrower holes). Floor telegraph: a strip in the wall colour flashing 2 Hz for TELEGRAPH seconds. NO TEXT anywhere (no SurfaceGui/BillboardGui text on walls, no labels).
3. MAP "Brick Run": 64x64 floor turf_check, 1-stud wood border, Art.cliffUnder dirt_cliff into the sea; delete v1 pastel stripes and candy tiers. Spawns 12.
4. PASS JUDGING (server): when a wall plane crosses a player at server time t: Forgive.judge(player, t, function(s) return Shapes.fits(shape, holeX0, <player X in wall space from s.pos>, posture from s (s.sliding -> "slide", feet above 0.3 -> jump with that feet height, else "stand")) end); hit -> ctx.knockback(player, wall travel direction, 150 scaled with intensity, 0.6) + map Hits; shielded players skipped. Map attributes WallsSpawned, Hits, WallSpeed, ActiveDirections, and per wall attribute ShapeIds (CSV) for testing.
5. Client renderer keyed by map, smooth motion from server time, sounds (Audio "WallWhoosh" as a wall passes near the player), clean everything.`,
    clauses: `Debug_ForceMinigame="HoleInTheWall", Debug_AutoQueue=true, Debug_FastIntermission=true, Debug_IntensityOverride=2.2 unless noted.
V9-1 No text: scan workspace (client and server) during a round: no TextLabel/TextButton/SurfaceGui/BillboardGui with non-empty Text inside any wall or the map. No part named like v1 labels.
V9-2 Variety: over 60 s at intensity 2.2 at least 8 distinct shape ids appear (wall ShapeIds attributes) and no two consecutive walls have the same set.
V9-3 Shapes unit tests (Shared.Minigames.HoleInTheWall.Shapes): every shape contains its kind's clearance rectangle; fits(DOOR, standing inside) true, standing outside false; fits(WINDOW standing) false, with a jump sample (feet 5.0) true; fits(SLOT standing) false, sliding true; >= 12 shapes in the catalog.
V9-4 Hit: Debug_NoEliminate=true, stand where no hole will pass (or in the wall centre between holes): Hits increases and the root velocity spikes.
V9-5 Parts: each wall model has <= 60 parts; WallsSpawned keeps increasing while the number of wall models alive stays bounded (<= 6) over 60 s.
V9-6 Visual: export + render (iso and eye from a spawn facing an incoming wall): brick-textured coloured walls with clearly outlined shaped holes, turf floor, cliff into the sea; judge it.
V9-7 Elimination on fall ends the round cleanly; no leftover client objects; no console errors from src/.`,
  },
  V10: {
    id: 'V10', name: 'Spin v2 + Combat (bat for everyone, no ledge, fair jump hits, Pillar Lagoon)',
    owned: ['src/server/Minigames/Spin/', 'src/client/Minigames/Spin/', 'src/shared/Minigames/Spin/', 'src/server/Combat/', 'src/client/Combat/'],
    reads: 'GAME_DESIGN 3.0, 3.3 (ALL), ART_BIBLE 7.4, 4.2, audits/mg-laser-spin.md (Spin + bat sections with file:line), PLAYTEST (ledge exploit + jump-hit evidence), the old bat code from the wave base: git show '+WAVE_BASE+':src/server/Minigames/KingOfTheHill/Bat.lua, BatTool.lua, and src/client/Minigames/KingOfTheHill/Input.lua (the Bomb Tag piece deletes those folders in parallel; read them via git show), src/server/Movement/Forgive.lua, src/shared/Movement/ActionButton.lua + CameraFx.lua, src/shared/Art.lua.',
    spec: `Brief #22: add a bat; remove the small piece of wall at the pillar bottoms you can stand on; fix "I jumped and it still hit me".
1. COMBAT (reusable by any minigame): src/server/Combat/Bat.lua (pure targeting: Bat.findTargets(attackerCFrame, candidates {{id, position}}, reach 7.5, cone 75 deg) -> ids) and src/server/Combat/BatTool.lua (BatTool.give(player, ctx, opts) -> handle with :Destroy(): a Tool with attribute PD_Bat built from parts (wood handle (176,112,60), red grip tape, bat head), colour from Player Cos_BatColor via the existing parser (port it), auto-equipped; server validates swings (1.0 s cooldown, alive, not stunned), hits = Bat.findTargets over alive non-shielded others -> ctx.knockback(target, away + slight up, 120 * (1 + Upg_BatPower * Config.UPGRADES.BatPower.perLevel), 0.6, attacker) (KO credit), Audio "BatSwing" and "Hit"; remote Combat_Swing (client -> server, rate-limited) ), src/client/Combat/BatInput.lua (LocalScript init or module booted by src/client/Combat/init.client.lua: when the equipped Tool has PD_Bat: LMB / F swing, touch via Shared.Movement.ActionButton.bind("Swing", {icon = "action_swing"}, ...), slash animation + whoosh, hit spark).
2. SPIN uses Combat: every participant gets a bat at start(), removed in stop() and on elimination. Map attribute Swings counts accepted swings.
3. LEDGE FIX: delete the Foot disc; every part below the pillar tops is either the column itself (never wider than the top, no protruding rims) or non-collidable; pillars rise straight out of the sea (no lava basin, no rock island, no candy rim: delete buildLava etc.); KillY = default (Config: 3 studs under the water). No collidable horizontal surface may exist between the sea and the pillar tops except the tops themselves.
4. JUMP HITS: bar hit test through Forgive: candidate when the bar's angular sweep passes a player's angle (and radius) this frame -> Forgive.judge(player, t, function(s) return s.feetY >= topY + 1.0 end) with HALF_WIDTH 1.7; the bar's VISUAL thickness equals the hit band (delete the glass Shell; bar = SmoothPlastic with the awning texture tinted red: red/white candy stripes, yellow Neon tips, dark Highlight outline). Shielded players skipped. Hit -> ctx.knockback tangential + outward (~140, stun 0.6). Keep map attributes Hits, BarSpeed; escalation (second counter-rotating bar at intensity > 2.2, telegraphed reversals).
5. MAP "Pillar Lagoon": 12 stone (Art stone recipe) columns rising out of the sea, square 9x9 tops preferred, tops coloured Color3.fromHSV((i-1)/12, 0.72, 0.95) with a 0.6 rim, foam rings at the waterline; stone hub tower with a yellow cap; spawns = pillar tops. Pillar gap stays jumpable with a dash (keep ring radius/geometry from the audit).
6. Shared math module src/shared/Minigames/Spin/BarMath.lua (+ Hit.lua) used by server and client (delete the server->StarterPlayerScripts require workaround). The client "bar incoming" warning also works when InSolo (punchlist P10 note 4).
7. Session-safe, cleanup, sounds (Audio "WallWhoosh" when a bar passes near you).`,
    clauses: `Debug_ForceMinigame="Spin", Debug_AutoQueue=true, Debug_FastIntermission=true.
V10-1 Ledge gone: during a round, for every pillar no collidable part other than the pillar top/column exists between Y = killY and topY - 0.5 whose XZ footprint extends beyond the column (scan parts); teleport the character to the old Foot ledge position (just outside the column, ~24 studs below the top): it falls and is eliminated (Debug_NoEliminate=false) within 2 s.
V10-2 Bat: the character has an equipped Tool with attribute PD_Bat during the round; Client fires the swing input twice within 0.3 s -> map Swings increments by exactly 1; after the round the Tool is gone. Bat.findTargets unit tests: target 4 studs in front -> hit, behind -> no, 15 studs away -> no, 6 studs at 30 degrees -> hit, at 60 degrees -> no.
V10-3 Fair jumps: Debug_NoEliminate=true, hold Space on a pillar for 20 s (auto-jumping): count hits; then stand still 20 s: count hits. Jumping must produce far fewer hits than standing (at most 1/3), and a hit while the client-side feet were >= topY+1.0 at the bar crossing must not happen (spot-check the Forgive samples around 2 hits).
V10-4 Look: export + render (iso, eye from a pillar top): stone pillars from the sea, colourful tops, candy-striped bar with outline, yellow hub cap; no lava, no glass; judge it.
V10-5 Shared modules exist under ReplicatedStorage.Shared.Minigames.Spin; the server does not require StarterPlayerScripts (grep).
V10-6 BarSpeed at Debug_IntensityOverride=2.5 >= 1.5x the value at 1; a second bar exists when intensity > 2.2. No console errors from src/.`,
  },
  V11: {
    id: 'V11', name: 'Dodgeball v2 (Sports Day look, fair hits, golden ball, cleanup)',
    owned: ['src/server/Minigames/Dodgeball/', 'src/client/Minigames/Dodgeball/', 'src/shared/Minigames/Dodgeball/'],
    reads: 'GAME_DESIGN 3.0, 3.4, ART_BIBLE 7.2, 4.2, audits/mg-wall-dodge-koth.md (Dodgeball parts), PLAYTEST (spawn kill, stacked knockbacks, leftover client container), src/shared/Movement/ActionButton.lua, src/shared/Art.lua.',
    spec: `Make Dodgeball distinct and fair (briefs #4, #6, #18).
1. MAP "Sports Day": voxel disc r 38 of maple planks (Art), white court lines 0.8 wide (center line, center circle r 7.4 blue with a white ring, 16 throw dashes at r 28.5), a 3-stud blue out-band inside the rim, cliff = blue stadium wall band with a white stripe then stone down into the sea. Delete candy beads, candy underside, floating big balls and clouds. Cannons navy (30,40,80) with white bands and a red muzzle ring (keep the googly eyes).
2. BALLS: red rubber (235,48,58) SmoothPlastic with a white seam ring and a dark Highlight outline; golden ball Gold Neon with sparkles.
3. FAIRNESS: per-player hit cooldown 0.8 s (no stacked double knockbacks); never target or hit shielded players (ShieldUntil) and nobody during the first 2.0 s of the round; knockback power 110 * (1 + 0.1 * (intensity - 1)) capped 170, stun 0.5.
4. GOLDEN BALL every 8 s (2 at once while >= 6 alive): pickup = character attribute HoldingGoldenBall; throw with LMB / F on PC and Shared.Movement.ActionButton.bind("Throw", {icon = "action_throw"}, ...) on touch; validated remote Dodgeball_Throw; a golden hit = ctx.knockback(target, dir, 150, 0.6, attacker) (KO credit).
5. CLEANUP: the client container (v1 "PD_DodgeballClient") is destroyed when its map goes away; no leftovers after the round.
6. Keep map test attributes (ShotsFired, Hits, FireInterval, ActiveBalls) and escalation. Session-safe.`,
    clauses: `Debug_ForceMinigame="Dodgeball", Debug_AutoQueue=true, Debug_FastIntermission=true.
V11-1 Look: export + render (iso + eye): maple court with white lines, blue band/stadium wall, navy cannons, red balls; no candy beads; judge it.
V11-2 Spawn grace: no hit on the player during the first 2.0 s of the round (record Hits / velocity spikes).
V11-3 No stacking: Debug_NoEliminate=true standing still for 25 s: log every knockback time on the client; no two within 0.8 s.
V11-4 Golden ball: one appears within ~9 s; teleport onto it -> HoldingGoldenBall=true; Client fires Dodgeball_Throw with a direction -> it flies, HoldingGoldenBall=false.
V11-5 After the round: no PD_DodgeballClient (or any Dodgeball client container) remains in the client workspace; no console errors from src/.`,
  },
  V12: {
    id: 'V12', name: 'Shop & Rewards UI (shop, wheel, daily calendar, group chest, gifts, offers, currency HUD)',
    owned: ['src/client/Shop/', 'src/client/Rewards/'],
    reads: 'GAME_DESIGN 5 (ALL), 6.1, 6.2, ART_BIBLE 8 (ALL; 8.4 panels, 8.5 HUD zones, 8.9 wheel), DECISIONS (money), ARCHITECTURE (Economy remotes Economy_Claim/Spin/UseRevive/Reward/Result/BuyUpgrade/BuyCosmetic/Equip, Player attributes, Lobby prompts PD_Action), src/shared/UIKit (ONLY kit), src/shared/Products.lua + Purchase.lua, src/shared/Economy/Rules.lua + Cosmetics.lua (merged Economy v2: WHEEL slices, calendar, cosmetics, BombSkins), the references ref1/ref3/ref5.',
    spec: `Where kids spend coins/Robux and come back every day (briefs #19, #20, #27, #29-31). Everything with Shared.UIKit, icons from Shared.Assets, prices from Shared.Products, purchases via Shared.Purchase.prompt(key).
1. HUD (lobby): UIKit.Dock "Left": Shop (order 10, Green, icon shop), Spin (20, Purple, icon wheel, badge "!" + timer "FREE" when FreeSpinReady or Spins > 0), Daily (30, Yellow, icon chest_daily, badge when DailyReady). "LeftTop": playtime gift pill (gift icons both sides, countdown to GiftAt, turns green "FREE!" and pulses when claimable; tap claims). "Right": Group chest (10, Cyan, icon chest_group, badge when GroupReady), 2x boost timer tile when BoostUntil > now. "TopOffers": Starter Pack (until StarterOwned; price tag 49), Galaxy Comet LIMITED (icon trail_galaxy, live countdown to FirstJoin + Config.WELCOME_DEAL_SECONDS, "-90%" sticker, struck 199 -> 19; after the deal: 199), VIP (if not owned). "Bottom": coin pill (count-up + "+25" fly-in), level badge with XP bar (Level/XP/XPNext), wins (trophy + leaderstats Wins).
2. SHOP PANEL (ref3/ref5: rainbow header, icon shop, red X): side tabs Featured (Galaxy deal card with countdown + strikethrough, Starter Pack card "ONE-TIME OFFER", spin bundles WheelSpin1 9 / WheelSpin5 39 "SAVE 13%" with an ODDS button), Coins (Coins500/1500/5000 with badges; BEST VALUE ribbon not clipped), Upgrades (4 cards: icon, name, level pips 0-5, effect, coin price button, small "+1 for R$25" Robux button, MAX state), Cosmetics (sub-tabs Trails / Bomb Skins / Bat Colors / Win Effects: grid cards with rarity colour strip, icon or colour swatch, price / OWNED / EQUIPPED states, buy via Economy_BuyCosmetic, equip via Economy_Equip, locked sources ("Wheel only", "VIP", "Robux")), Passes (2X Coins 149, VIP 249 with perks list). Not enough coins -> shake + toast "Need 320 more" + a "Get coins" button switching to Coins.
3. WHEEL PANEL (Purple header, icon wheel): Assets.Art.wheel_face (slice 1 at 12 o'clock clockwise) with prize icons from Rules.WHEEL at 0.62 radius, gold rim + bulbs, red pointer on top; buttons SPIN (FREE) when FreeSpinReady, "SPIN x<Spins>" when tokens, SPIN 9 R$ (WheelSpin1) and 5 SPINS 39 R$ (WheelSpin5) (hidden when PaidRandomRestricted), ODDS button (list of every prize + percent, sums to 100%), "Free spin in 12:34:56" caption. Spinning: InvokeServer Economy_Spin -> animate 4 s ease-out (3+ full turns) so the slice index returned by the server stops under the pointer, WheelTick sound per slice passed, WheelWin + confetti + reward reveal; after buying a spin product (Economy_Result/Reward) auto-offer SPIN.
4. DAILY PANEL (Yellow->Orange header, icon calendar_star): 7 day cards (D1..D7 rewards from Rules), claimed days checked (check_badge), today glowing with CLAIM, future dimmed, streak "12-day streak!" (fire_streak); CLAIM -> InvokeServer Economy_Claim("daily") -> chest-open reveal.
5. GROUP CHEST PANEL (Cyan header, icon chest_group): "Like the game & join the group!" (thumbs_up, group_friends icons), JOIN GROUP button (GroupService:PromptJoinAsync(Config.GROUP_ID) when GROUP_ID ~= 0, else toast "Coming soon!"), CLAIM -> Economy_Claim("group").
6. REWARD REVEAL (src/client/Rewards): one shared popup for Economy_Reward events (daily, spin, gift, level up, starter, purchase): chest/icon pop, items and coins count-up, confetti, ChestOpen/WheelWin/LevelUp sounds; level-up banner "LEVEL 7!".
7. POPUP ETIQUETTE: wait for LocalPlayer ClientReady; Starter Pack auto-popup only after the player's 2nd finished round, never in the first 60 s, only in the Lobby phase, at most 1 auto popup per 5 minutes (track locally).
8. LOBBY PROMPTS: ProximityPromptService.PromptTriggered on the client: PD_Action "Shop" -> Shop panel, "Wheel" -> Wheel panel, "Daily" -> Daily panel, "Group" -> Group panel.
9. Panels cannot open while InRound; open panels close at Intro for participants. Replace every v1 Shop client file (no emoji, no v1 kit). All remotes connected lazily.`,
    clauses: `Economy v2 is merged in this worktree; use Studio dev purchases (Purchase.prompt -> Economy_DevBuy) to test Robux flows.
V12-1 HUD: PD_Docks has Left tiles Shop/Spin/Daily, Right tile Group, LeftTop gift pill with a countdown, TopOffers Starter + Galaxy (with a live countdown and a struck-through 199), Bottom coin pill + level bar; every tile has a non-empty icon Image. screen_capture: looks like ref1/ref2 quality (judge critically).
V12-2 Shop: activating the Shop tile opens the panel; each tab renders without errors; Featured shows the Galaxy card with strikethrough 199 and 19; buying Coins1500 (activate its Robux button) in Studio -> Coins +1500 within 2 s; buying an affordable cosmetic with coins -> OWNED/EQUIP state; an unaffordable one -> "Need ... more" toast.
V12-3 Wheel: with FreeSpinReady, SPIN (FREE) -> Economy_Spin invoked, the wheel animates ~4 s and stops with the returned slice under the pointer (compare the final rotation with the index), the prize is shown and granted; ODDS lists 8 prizes summing to 100%.
V12-4 Daily: Daily tile badge visible when DailyReady; CLAIM -> coins +100 (day 1) and a reveal popup; the badge disappears.
V12-5 Group: CLAIM with GROUP_ID 0 -> "Coming soon!" toast, nothing granted.
V12-6 Gift: when GiftAt passes (set it through the Economy test API) the pill turns FREE; tapping claims and the countdown restarts.
V12-7 Prompts: walk/teleport next to the lobby Shop stall and press E (user_keyboard_input) -> the Shop panel opens (or trigger the prompt via your documented path).
V12-8 InRound=true: Shop tile hidden (dock) and the shop cannot be opened. No emoji in PlayerGui; no console errors from src/.`,
  },
  V13: {
    id: 'V13', name: 'Social & Solo (lobby leaderboards, podium, Solo UI restyle)',
    owned: ['src/server/Solo/', 'src/client/Solo/', 'src/server/Leaderboards/', 'src/client/Leaderboards/'],
    reads: 'GAME_DESIGN 7 (boards, podium), ART_BIBLE 6.3 (boards), 8 (UI), ARCHITECTURE (Lobby model contract anchors, Solo), audits/ui.md (Solo picker issues), PLAYTEST (Solo picker), src/shared/UIKit, src/shared/Art.lua, current src/server/Solo + src/client/Solo code.',
    spec: `Competition (brief #8) and a polished Solo mode.
1. BOARDS (src/server/Leaderboards/): mount SurfaceGui boards on the permanent lobby's anchors: WinsBoardAnchor "TOP WINS" (OrderedDataStore PartyDash_TopWins_v1, written by Economy), LevelBoardAnchor "TOP LEVEL" (PartyDash_TopLevel_v1, value level*1e6+xp -> show "Lv N"), and keep the Solo TOP 10 board on LeaderboardAnchor (restyle it the same way). Header bar Gold/Purple/Orange with a crown/trophy icon, 10 rows: medal icon for top 3 (gold/silver/bronze), headshot thumbnail (Players:GetUserThumbnailAsync HeadShot 48x48, cached), name, value; refresh every 120 s (pcall); when DataStores are unavailable (Studio) show the current server's players from their attributes plus "—" placeholder rows, never an empty box. Boards must survive the lobby being rebuilt (re-mount if the anchor changes).
2. PODIUM (lobby plaza): after each main round (Signals.RoundFinished) show the top 3 (placements) as anchored avatar models (Players:CreateHumanoidModelFromUserId, pcall, posed, scaled to fit) on the podium blocks with name tags; clear when the next round finishes; skip silently if creation fails.
3. SOLO UI (src/client/Solo): rebuild the picker, in-run HUD and result screen with UIKit and Assets icons (mg_* card art, stopwatch, trophy, medal), fixing the v1 issues (PLAY buttons hanging off cards, repeated placeholder text, dead space). Solo entry: UIKit.Dock "Left" tile (order 40, Blue, icon stopwatch, label "Solo") + lobby prompt PD_Action "Solo" (ProximityPromptService.PromptTriggered) open the picker. Remove the v1 PartyHUD MenuRail button code.
4. SOLO SERVER: return players to the PERMANENT lobby spawns (workspace.Lobby.Spawns) after a run (no stands); the Solo backdrop uses Shared.Art (Art.water sea at center.Y - Config.SEA_DROP, a few islands/clouds) instead of v1 pastel islands; everything else as v1 (records, DataStores, slot allocation).`,
    clauses: `V13-1 Boards: in Play, workspace.Lobby WinsBoardAnchor, LevelBoardAnchor and LeaderboardAnchor each carry a SurfaceGui with a header and 10 rows (placeholders allowed in Studio) and the local player appears on TOP WINS/LEVEL; screen_capture of a board (GUI renders; if the 3D is black, inspect the SurfaceGui tree and render a scene export) looks polished.
V13-2 Podium: Server fires Signals.RoundFinished with a fake result (the player 1st) -> within 5 s an avatar model stands on the gold block; the next fake RoundFinished replaces it.
V13-3 Solo: the Solo tile exists in PD_Docks Left; activating it opens the picker (screen_capture: polished cards, buttons inside cards, mg icons); starting LaserTracer solo puts the player in a solo run (InSolo true, near SOLO_ORIGIN); falling ends it, the player returns within LOBBY_RADIUS of LOBBY_CENTER and the result screen shows a time.
V13-4 No emoji in PlayerGui; no v1 MenuRail usage; no console errors from src/.`,
  },
}

function ownedList(part) { return part.owned.map(p => `  - ${p}`).join('\n') }

function builderPrompt(part, feedback, attempt) {
  return `${BRIEF}

YOU ARE THE BUILDER for piece ${part.id}: ${part.name}. Attempt ${attempt}/${MAX_ATTEMPTS}.

STEP ZERO (mandatory, every attempt): run pwd and git rev-parse --show-toplevel: you must be inside a git worktree under ${REPO}/.claude/worktrees/ (NOT the main checkout ${REPO}). If you are in the main checkout, STOP and report that without changing anything. Make sure your branch contains the wave base: git merge-base --is-ancestor ${WAVE_BASE} HEAD || git merge --no-edit ${WAVE_BASE} (merge only, never reset).
${attempt > 1 ? `\nTHIS IS A RETRY. Your worktree branch may already contain committed-but-failing work from the previous attempt (critics commit after every verdict). Build on it and fix it; do not start over unless the approach is fundamentally wrong. Never git reset --hard.\n\nCRITIC FEEDBACK FROM THE PREVIOUS ATTEMPT (fix EVERY item, they were verified by running the game):\n${feedback}\n` : ''}
YOU OWN ONLY THESE PATHS (create/modify/delete files only here):
${ownedList(part)}
${part.ownedNote || ''}
Never edit, delete or revert anything else (especially frozen contracts). If git status shows changes outside your paths, report them in "anomalies" and leave them alone.

READ FOR THIS PIECE: ${part.reads}

SPEC (every numbered item is required):
${part.spec}

HOW THE CRITICS WILL JUDGE YOU (frozen clauses; a static code critic and a Studio test critic; make sure each clause will pass):
${part.clauses}
Plus common clauses: C1 only your paths changed vs ${WAVE_BASE}; C2 "${BIN}/rojo build default.project.json -o /tmp/${part.id}.rbxl" succeeds, "${BIN}/selene src/" reports 0 errors, "${BIN}/stylua --check src/" passes; C3 no console errors from src/ in a live Studio test; C4 English only, no emoji, no Polish; C5 quality: idiomatic, well-structured Luau with short helpful comments, no dead v1 code left behind in your files, remotes validated server-side, no per-frame Instance.new, everything cleaned up; C6 the result is genuinely polished and matches ART_BIBLE / GAME_DESIGN, not a prototype.

RULES: Do NOT use Roblox Studio or any Roblox_Studio MCP tool (one shared Studio is reserved for critics). Do NOT commit (the critic commits). Think through runtime behavior carefully since you cannot run the game: trace every code path, nil-check, handle late-replicating instances (WaitForChild with timeouts), and simulate the logic in your head against each clause. Prefer simple, robust code.

BEFORE FINISHING: format with "${BIN}/stylua" on your files, run the C2 commands from your worktree root and fix everything they report. Then stage your paths and compute the progress hash:
  git add -A -- ${part.owned.join(' ')} && git diff --cached ${WAVE_BASE} -- ${part.owned.join(' ')} | shasum | cut -d' ' -f1
Return: diffHash (that hash), summary (what you built, how each clause is satisfied, anything risky), branch (git branch --show-current), worktreePath (absolute toplevel), filesChanged, contractGaps (frozen-contract problems you had to work around, or ""), anomalies.`
}

function staticCriticPrompt(part, build, attempt) {
  return `${BRIEF}

YOU ARE THE STATIC (code) CRITIC for piece ${part.id}: ${part.name} (attempt ${attempt}/${MAX_ATTEMPTS}). You did not write this code. Do NOT edit any code. Do NOT use Roblox Studio (a separate Studio critic runs the game after you).
The builder worked in worktree ${build.worktreePath} on branch ${build.branch}. Builder's summary (untrusted): ${String(build.summary).slice(0, 2500)}

OWNED PATHS:
${ownedList(part)}
${part.ownedNote || ''}

SPEC the code must implement (read it carefully):
${part.spec}

FROZEN CLAUSES the Studio critic will run later (check the code can satisfy them):
${part.clauses}

PROCEDURE
1. cd ${build.worktreePath}; confirm git branch --show-current == ${build.branch}.
PREP (mandatory, before any check): cd ${build.worktreePath}. If git merge-base --is-ancestor ${WAVE_BASE} HEAD fails (the builder worked on an older base): first commit the builder's work if anything is staged/modified in the owned paths: git add -A -- ${part.owned.join(' ')} && git commit -m "${part.id}: builder work attempt ${attempt} (pre-review snapshot)" ; then git merge --no-edit ${WAVE_BASE} (brings in lead-only commits to frozen files; never resolve conflicts by editing piece files: if it conflicts, git merge --abort and FAIL with details).
2. C1 ownership: git status --porcelain and git diff --name-only ${WAVE_BASE} (include staged and untracked): every changed path must be inside the owned paths. Nothing outside may differ from ${WAVE_BASE}.
3. C2: "${BIN}/rojo build default.project.json -o /tmp/${part.id}-static.rbxl", "${BIN}/selene src/", "${BIN}/stylua --check src/" must all pass.
4. C4: grep the owned files for Polish characters, emoji (codepoints above U+2000 other than U+E002) and non-English player-facing strings.
5. SPEC REVIEW: go through EVERY numbered spec item and verify in the code that it is implemented correctly and completely (cite file:line). Hunt for runtime bugs: nil indexing, wrong attribute/remote names vs ARCHITECTURE.md, blocking WaitForChild on things that may not exist, missing cleanup, race conditions, server trusting the client, module-level mutable state where forbidden, Luau type/syntax mistakes that would error at runtime, wrong use of frozen modules (read UIKit/Art/Audio/Products APIs to check calls match their real signatures).
6. Judge strictly: a missing or half-done spec item is a FAIL. Cosmetic nits alone are not.
7. If you FAIL the piece you are the commit actor (the Studio critic will not run): in ${build.worktreePath} run
   git add -A -- ${part.owned.join(' ')} && git commit -m "${part.id} ${part.name}: attempt ${attempt}/${MAX_ATTEMPTS} FAIL static review (incomplete - needs manual follow-up)" --allow-empty
   and report the hash. If you PASS, do not commit.
Return pass, summary, failures (one per problem: spec item / clause, file:line, what is wrong, what correct looks like; be specific so the builder can fix it in one go), clauseResults, commit.`
}

function studioCriticPrompt(part, build, attempt) {
  return `${BRIEF}

YOU ARE THE STUDIO TEST CRITIC for piece ${part.id}: ${part.name} (attempt ${attempt}/${MAX_ATTEMPTS}). You did not write this code and must not edit it. A static code critic already passed it; your job is to RUN the game and verify the frozen clauses by doing. Do not pass anything because a summary claims it works.
The builder worked in worktree ${build.worktreePath} on branch ${build.branch}. Builder's summary (untrusted): ${String(build.summary).slice(0, 2000)}

FROZEN CLAUSES:
${part.clauses}
Common: C3 no console errors from src/ during the test; C6 polish: judge screenshots (GUI) and scene renders (3D) critically against ART_BIBLE and the reference screenshots.

ENVIRONMENT (measured this morning; the Mac screen is LOCKED and nobody can unlock it): in Play, RenderStepped never fires, TweenService tweens do not advance, Camera.ViewportSize is 1x1, screen_capture and user_mouse_input / user_keyboard_input time out, VirtualInputManager is blocked. Heartbeat, physics, remotes, attributes and server logic work. Do NOT fail a clause only because of this. Verify the same behavior another way: (a) fire the remotes the client would fire (Client execute_luau) and check the server-side effects; (b) call the piece's modules / test hooks / BindableFunctions directly when they exist (a fresh require from execute_luau may be a separate module instance from the running LocalScript's: prefer observing attributes, instances and remotes); (c) inspect the instance trees and properties (existence, sizes, images, texts, visibility flags, layout math); (d) for behavior driven by RenderStepped / tweens / input, read the code path carefully and check the initial/static state; (e) 3D visuals via tools/scene_export.luau + tools/render_scene.py. Mark such clauses pass=true with evidence starting "ENV-ALT:" when the alternative verification is convincing, and list them in the summary under "environment caveats (re-check with the screen unlocked)". FAIL only on real defects you can demonstrate (console errors, wrong state, missing instances, wrong logic in the code).
PROCEDURE (be efficient: target <= 20 minutes of Studio time; batch many checks into one execute_luau; poll with short loops inside Luau instead of many tool calls)
PREP (mandatory, before any check): cd ${build.worktreePath}. If git merge-base --is-ancestor ${WAVE_BASE} HEAD fails (the builder worked on an older base): first commit the builder's work if anything is staged/modified in the owned paths: git add -A -- ${part.owned.join(' ')} && git commit -m "${part.id}: builder work attempt ${attempt} (pre-review snapshot)" ; then git merge --no-edit ${WAVE_BASE} (brings in lead-only commits to frozen files; never resolve conflicts by editing piece files: if it conflicts, git merge --abort and FAIL with details).
1. cd ${build.worktreePath}. Acquire the Studio lock: "${REPO}/tools/lock.sh acquire studio critic-${part.id}" (repeat while it exits 2). ALWAYS release it at the end with "${REPO}/tools/lock.sh release studio critic-${part.id}", even when something fails.
2. Load Studio tools: ToolSearch "select:mcp__Roblox_Studio__get_studio_state,mcp__Roblox_Studio__execute_luau,mcp__Roblox_Studio__start_stop_play,mcp__Roblox_Studio__get_console_output,mcp__Roblox_Studio__screen_capture,mcp__Roblox_Studio__user_keyboard_input,mcp__Roblox_Studio__character_navigation,mcp__Roblox_Studio__user_mouse_input". studio_id = "${STUDIO}".
3. If Studio is in Play mode, stop it. In Edit mode: read ${REPO}/tools/studio_pull.luau, replace __ROOT__ with ${build.worktreePath}, run it via execute_luau (datamodel Edit); it reports the synced script count.
4. In Edit set workspace attributes: Debug_FastIntermission=true, Debug_ForceMinigame="", Debug_ForceModifier="", Debug_NoEliminate=false, Debug_AutoQueue=true, Debug_FreeRevive=false, Debug_ForceVote="", Debug_IntensityOverride=nil, Debug_SuddenDeathAt=nil; then the ones the clauses need (you can also change them from the Server datamodel during play).
5. start_stop_play to play; run every clause with execute_luau (Server/Client), keyboard/mouse input, get_console_output. GUI: screen_capture works. 3D: the Mac screen may be locked so the 3D viewport renders black; for 3D visuals export scenes with ${REPO}/tools/scene_export.luau (fill __OUT__/__ROOT__/__CENTER__/__RADIUS__) and render with python3 ${REPO}/tools/render_scene.py <json> <png> --view iso|top|eye|low, then Read the PNG.
6. Stop play at the end and leave Studio in Edit mode. Release the lock.
7. COMMIT (you are the designated commit actor, PASS or FAIL): in ${build.worktreePath} run
   git add -A -- ${part.owned.join(' ')} && git commit -m "${part.id} ${part.name}: attempt ${attempt}/${MAX_ATTEMPTS} <PASS or FAIL (incomplete - needs manual follow-up)>" --allow-empty
   Never commit files outside the owned paths. Report the commit hash.
Return pass (true only if EVERY clause passes), summary, failures (one item per failing clause: clause id, exactly what you did, observed vs expected, console errors verbatim, file/line if known; maximally specific), clauseResults, commit.`
}

async function buildPart(part, waveTitle) {
  let feedback = ''
  let lastVerdict = null
  let lastDiffHash = null
  let wastedAttempts = 0
  let lastBuild = null
  let attemptsUsed = 0
  const history = []
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    attemptsUsed = attempt
    log(`${part.id} attempt ${attempt}/${MAX_ATTEMPTS}: building`)
    trackSpawn()
    const build = await agent(builderPrompt(part, feedback, attempt), {
      label: `build:${part.id}#${attempt}`, phase: waveTitle, model: 'opus', isolation: 'worktree', schema: BUILD_SCHEMA,
    })
    if (build == null) {
      feedback = 'Builder agent did not return a result (possible error) - retry the build.'
      log(`${part.id} attempt ${attempt}/${MAX_ATTEMPTS}: BUILDER returned null - failed attempt, critics not run`)
      history.push({ attempt, result: 'builder-null' })
      continue
    }
    lastBuild = build
    const diffHash = build.diffHash ? String(build.diffHash).trim() : ''
    if (!diffHash || diffHash === lastDiffHash) {
      wastedAttempts++
      log(`${part.id} attempt ${attempt}/${MAX_ATTEMPTS}: NO PROGRESS (diff hash unchanged/empty) - stopping retries for this piece`)
      history.push({ attempt, result: 'no-progress' })
      break
    }
    lastDiffHash = diffHash
    trackSpawn()
    const sv = await agent(staticCriticPrompt(part, build, attempt), {
      label: `static:${part.id}#${attempt}`, phase: waveTitle, model: 'opus', schema: VERDICT_SCHEMA,
    })
    lastVerdict = sv
    if (!sv || !sv.pass) {
      feedback = sv
        ? `STATIC REVIEW FAILED: ${sv.summary}\nFailures:\n- ${(sv.failures || []).join('\n- ')}`
        : 'Static critic did not return a verdict (possible error) - re-check every spec item yourself.'
      log(`${part.id} attempt ${attempt}/${MAX_ATTEMPTS}: static FAIL: ${feedback.slice(0, 220)}`)
      history.push({ attempt, result: 'static-fail', summary: sv ? sv.summary : 'null', failures: sv ? sv.failures : [] })
      continue
    }
    log(`${part.id} attempt ${attempt}/${MAX_ATTEMPTS}: static PASS, queued for Studio`)
    trackSpawn()
    const verdict = await withStudio(() => agent(studioCriticPrompt(part, build, attempt), {
      label: `studio:${part.id}#${attempt}`, phase: waveTitle, model: 'sonnet', schema: VERDICT_SCHEMA,
    }))
    lastVerdict = verdict
    if (verdict && verdict.pass) {
      log(`${part.id} PASSED on attempt ${attempt}/${MAX_ATTEMPTS}`)
      history.push({ attempt, result: 'pass' })
      return { id: part.id, name: part.name, pass: true, attempts: attempt, wastedAttempts, branch: build.branch, worktreePath: build.worktreePath, lastSummary: verdict.summary, lastFailures: [], contractGaps: build.contractGaps || '', anomalies: build.anomalies || '', history }
    }
    feedback = verdict
      ? `STUDIO TEST FAILED: ${verdict.summary}\nFailures:\n- ${(verdict.failures || []).join('\n- ')}`
      : 'Studio critic did not return a verdict (possible error) - re-verify against the clauses from scratch.'
    log(`${part.id} attempt ${attempt}/${MAX_ATTEMPTS}: studio FAIL: ${feedback.slice(0, 220)}`)
    history.push({ attempt, result: 'studio-fail', summary: verdict ? verdict.summary : 'null', failures: verdict ? verdict.failures : [] })
  }
  log(`${part.id} FAILED after ${attemptsUsed} attempt(s) (${wastedAttempts} wasted) - committed anyway, flagged incomplete`)
  return {
    id: part.id, name: part.name, pass: false, attempts: attemptsUsed, wastedAttempts,
    branch: lastBuild ? lastBuild.branch : '', worktreePath: lastBuild ? lastBuild.worktreePath : '',
    lastSummary: lastVerdict ? lastVerdict.summary : 'Critic never returned a verdict.',
    lastFailures: lastVerdict ? (lastVerdict.failures || []) : [],
    contractGaps: lastBuild ? (lastBuild.contractGaps || '') : '', anomalies: lastBuild ? (lastBuild.anomalies || '') : '', history,
  }
}

phase('Wave 2')
const ids = ['V7', 'V8', 'V9', 'V10', 'V11', 'V12', 'V13']
log(`Wave 2: ${ids.length} pieces, worst case ${WORST_CASE_SPAWNS} agents, ceiling ${SPAWN_CEILING}`)
const results = await parallel(ids.map(id => () => buildPart(PIECES[id], 'Wave 2')))
const clean = results.map((r, i) => r || { id: ids[i], name: PIECES[ids[i]].name, pass: false, attempts: 0, lastSummary: 'buildPart crashed', lastFailures: [], branch: '', worktreePath: '' })

phase('Wave-commit')
trackSpawn()
const wave = await agent(`You are the WAVE-COMMIT agent for wave 2 of the Party Dash v2 gauntlet loop. Landing mode: worktree-default: critics already committed each piece inline on its own worktree branch; you merge those branches into the review branch ${REVIEW} in the main checkout ${REPO}.
Before touching git in the main checkout acquire the git lock: "${REPO}/tools/lock.sh acquire git wave2" (repeat while it exits 2) and release it at the end ("${REPO}/tools/lock.sh release git wave2").

Piece results (use the failure details VERBATIM, do not summarize them away):
${JSON.stringify(clean, null, 2)}

Steps:
1. cd ${REPO}; git status --porcelain must be clean (untracked files under .claude/ are fine). If there are unexplained tracked changes, STOP: report them in problems and merge nothing. Verify git branch --show-current == ${REVIEW} (if not, git checkout ${REVIEW}; never touch main, never push, never touch any remote).
2. For each piece with a non-empty branch (in order V7..V13): check its last commit exists; verify the diff of that branch vs ${WAVE_BASE} only touches that piece's owned paths (V7 also deletes the KingOfTheHill folders); then git merge --no-ff --no-edit <branch> -m "Merge <id> <name> (<PASS|FAIL incomplete>)". If a merge conflicts, git merge --abort and report it (do not hand-resolve). Failed pieces are merged too (flagged incomplete), never discarded.
3. After each successful merge: git worktree remove --force <worktreePath> (exact path from git worktree list) then git branch -D <branch>, only after git merge-base --is-ancestor <branch> HEAD succeeds.
4. Run "${BIN}/rojo build default.project.json -o /tmp/wave2-merged.rbxl" and "${BIN}/selene src/" on the merged tree and report failures in problems (do not fix code).
5. Update ${REPO}/.gauntlet/v2/punchlist.md (wave-2 rows: Status passed/FAILED - incomplete, Attempts, Notes = contractGaps + anomalies in one line; add a "Wave 2" section under "Failure details / judge caveats" with verbatim lastSummary + every lastFailures item for failed pieces and every piece's contractGaps verbatim) and ${REPO}/.gauntlet/v2/manifest.json pieces {wave, status, attempts, wastedAttempts}. Commit: git add .gauntlet/v2 && git commit -m "Gauntlet v2 wave 2: punchlist update".
6. Do NOT push. Release the git lock.
Return reviewHead (git rev-parse HEAD), merged (piece ids merged), problems ("" if none).`, { label: 'wave-commit:2', phase: 'Wave-commit', model: 'sonnet', schema: WAVE_SCHEMA })

return { results: clean, wave, spawnCount }
