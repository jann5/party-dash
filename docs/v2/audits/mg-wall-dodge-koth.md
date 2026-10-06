# Audit: mg-wall-dodge-koth

**subsystem**: Minigames: Hole in the Wall + Dodgeball + King of the Hill (to be replaced by Bomb Tag) + Sandbox (+ Contracts/Minigame.lua)

**howItWorks**: CONTRACT (src/shared/Contracts/Minigame.lua): a minigame is src/server/Minigames/<Id>/init.lua returning {id, displayName, rules, keys ⊂ {Jump,Slide,Dash,Swing,Throw}, kind "survival"|"score", duration (score only), soloCapable, create(ctx)->session}. Core's Registry.init (src/server/Core/Registry.lua:68-96) loads every ModuleScript child of Server.Minigames (Folders are ignored, so a `_Lib` Folder is safe) and publishes ReplicatedStorage.MinigameInfo.<Id> {DisplayName, Rules, Keys, Kind, SoloCapable, Duration, Hidden}. session = {map: Model (needs Folder "Spawns", optional KillY attr), start(), stop()}. ctx (src/server/Core/Context.lua:148-207): center, killY, isSolo, modifier, trove, players() (alive copy), allPlayers(), isAlive, elapsed (os.clock based), intensity = (1+elapsed/35)*modMult, eliminate(p, reason), addScore/getScore, knockback(p, dir, power, stun) -> Knockback.apply -> Core_Knockback to owning client (velocity = unit*power + lift clamp(0.4*power,18,75), src/shared/Knockback.lua:43-47), respawn, finish, announce, feed. Context enforces killY/death: survival -> _eliminate; score -> 2 s anchored respawn "Oops! Back in 2..." (Context.lua:295-306). End: survival >=2 players -> alive<=1, 1 player -> alive==0; score -> duration. RoundLoop.onEliminated (RoundLoop.lua:257-281) sets InRound=false, Spectating=true, sendToStands, "YOU'RE OUT!" (ignores reason except "left"). pickMinigame (RoundLoop.lua:102-122) does not know the participant count. Modifiers are chosen independently of the minigame (pickModifier 147-163).

HOLE IN THE WALL (survival, soloCapable). Server: Arena.build (Arena.lua) = 64x64 pastel stripe floor (pastel() lerps MapPalette 30% to white, SmoothPlastic), hazard rim, candy tier underside, 4 wall slots, pylons, 12 spawns, Folder "Walls", tag "HoleInTheWall_Arena", ModelStreamingMode Persistent. init.lua: spawn loop (gap from Patterns.tuning, first 3 walls >= 4.5 s), sides unlock 1->4 by intensity (pickSide never repeats a side). Each wall = Configuration in map.Walls with attrs Index, Origin, Dir, Telegraph, Enter (=now+1.5), Speed, Start(-36), Finish(37), Width 66, Height 14, Thick 2, Color (4-color cycle), Holes ("N:minX:maxX:bottom:top;..."). Walls are NOT physical: Heartbeat step() computes plane = START + speed*(now-enter) and, per alive player, rel = offset·dir - plane; a crossing prev>0 -> rel<=0 (prev-rel<12, |localX|<=34, -3<height<14.5) calls resolve(): Pass.check(kind,minX,maxX,rootX,rootHeight,Sliding) over each hole; pass -> FireAllClients("pass"), miss -> ctx.knockback(dir+0.22y, power 170..240, stun 0.7) + "hit" (0.3 s per-player cooldown). Patterns.makeHoles: 1-3 holes, one per equal segment, kinds NORMAL(w7,0..8)/HIGH(w7,4.5..10.5)/LOW(w8,0..3); wall 2 forces a HIGH, wall 3 a LOW. Pass rules: NORMAL root<=10, HIGH root>=4.3, LOW Sliding or root<=1.6; only the root CENTER X is tested. Client (src/client/Minigames/HoleInTheWall): init.client.lua tracks tagged arenas, WallView.new(config) builds panels around rectangular holes (no CSG), HOLE_STYLE colors + SurfaceGui labels "RUN!/JUMP!/SLIDE!", neon outlines, floor telegraph (shadow strip, colored hole patches, chevrons, "!" billboard, whoosh), moves every wall each RenderStepped with BulkMoveTo from server time; remote HoleInTheWall_Fx (server->client only, lazily connected in pcall) drives Fx.hit/Fx.pass ("NICE!" words). Map attrs: WallsSpawned, Hits, WallSpeed, ActiveDirections.

DODGEBALL (survival, soloCapable). Server init.lua: Map.build = disc court R 37.5 (white slab + orange/gold/pink paint, beads, candy underside, clouds, floating balls), 10 deco cannons at ring 46 (attrs Index/Pivot/BarrelPivot), 12 spawns, Folder Golden. Balls are pure data: Ballistics.plan (parabolic segments, bounces on the disc, fizzle/void) from server time; Heartbeat step(): volleys every Tuning.fireInterval (2.1 s -> 0.45 s), volleySize, chargeTime 0.85, 70% aimed at a player with lead, giants after intensity 2; stepBalls tests Hit.segmentHitsPlayer(lastPos,pos,radius,root) (sphere 2.2 + ball radius) -> ctx.knockback(power 135..210, stun 0.7), non-giant balls pop. Golden ball: first at 7 s, then 12 s after each pickup, pickup by distance 4.5, holder gets character attr HoldingGoldenBall + welded visual; remote Dodgeball_Throw(dirVector) validated + 0.4 s cooldown + 16° aim assist, GOLD_POWER 150. Remote Dodgeball_Fx (shot/pop/golden/grab/clear keyed by session GUID map attr DodgeballSession). Client: Balls.lua evaluates the same segments per frame (pooled parts, shadows, landing markers), Cannons.lua animates cannon models locally (turn, glow, shake, recoil), Effects.lua pooled puffs/pops/rings/sounds on Terrain attachments, Throw.lua (PC click / CAS "PartyDash_Throw" gold touch button left of Jump / R2, floor aim arrow, Highlight lock-on).

KING OF THE HILL (score, 90 s, not solo). Map.lua: 3-tier cake hill (ramps, drips, sprinkles, lollipops), golden zone (rim/fill/beam/core/motes/PointLight) shrinking 11->5 (Zone.radiusAt), KillY center-25, tag KOTH_Map. init.lua: 4 Hz scoreTick adds 0.25 per tick in zone, leader crown BillboardGui (tag KOTH_Crown), zone tint; every player gets a Tool "Bat" (BatTool.build: welded parts, Cos_BatColor parse, trail, whoosh) equipped and re-equipped; swings via Tool.Activated or remote KingOfTheHill_Swing (no args, 1 s cooldown), hit = Bat.findTargets (7.5 stud 70° cone, |dy|<=6) + Bat.power (95*(1+lvl*0.06)*(1+0.6*t)), stock Animate "toolanim"=Slash; KingOfTheHill_Fx ("hit",n) to attacker. Client: Hud (status pill, BAT chip cooldown, +1/BONK pops, avoids PartyHUD.Tutorial), Input (touch SWING button, hides Backpack CoreGui), WorldFx (pulse rings, crown bob), Ui helpers.

_SANDBOX (hidden "_" id, "BALL DROP"): disc platform, physics balls dropped with warning rings, distance-based knockback; only used via Debug_ForceMinigame.


## bugs


---

**title**: Hole in the Wall + LOW GRAVITY modifier: players jump clean over every wall

**severity**: critical

**file**: src/server/Minigames/HoleInTheWall/init.lua

**line**: 229

**rootCause**: The crossing test skips anyone whose root is above WALL_HEIGHT + 0.5 (= 14.5 studs) as 'sailing over the top'. The LowGravity modifier (src/client/Modifiers/LowGravity.lua:4, GRAVITY = 70) gives jump height 52^2/(2*70) = 19.3 studs, so the root apex is about 22 studs and stays above 14.5 for about 0.95 s of every jump. Modifiers are rolled independently of the minigame (RoundLoop.pickModifier), so every 5th round can be LowGravity + Hole in the Wall. The JumpBoost upgrade is safe today (apex about 12.1), but this pairing is not.

**evidence**: init.lua:222-231 condition `height < Patterns.WALL_HEIGHT + 0.5`; Patterns.lua:11 WALL_HEIGHT = 14; LowGravity.lua:4 GRAVITY = 70; Config.JUMP_POWER = 52.

**fix**: Remove the over-the-top exemption: any crossing with height >= wall height counts as a miss. Also make the wall height per session: when ctx.modifier == "LowGravity", set Height to 30 on the wall Configuration (WallView already reads Height). Better still, add an optional `incompatibleModifiers = {"LowGravity"}` to the definition and have RoundLoop.pickModifier honor it (contract change).


---

**title**: Hole in the Wall ignores character scale: GIANT players walk through JUMP windows, TINY/GIANT get wrong slide rules

**severity**: major

**file**: src/server/Minigames/HoleInTheWall/Pass.lua

**line**: 20

**rootCause**: Pass uses fixed absolute root-height thresholds (HIGH_MIN_ROOT 4.3, LOW_MAX_ROOT 1.6, NORMAL_MAX_ROOT 10). The Giant modifier scales characters 1.6x with Model:ScaleTo, and _Lib/CharacterEffect.lua:109-118 itself computes stand height as HipHeight + root/2 (about 3 * scale = 4.8). A standing giant has root 4.8 >= 4.3, so it passes HIGH windows without jumping. It also passes 3-stud LOW gaps by sliding, although its body is about 8 studs tall.

**evidence**: Pass.lua:19-21 and 63-70; Modifiers/Giant.lua scale 1.6; CharacterEffect.scaleTo uses standHeight * scale.

**fix**: Replace the root-height thresholds with a posture hitbox scaled by s = character:GetScale(): standing/jumping span [h - 2.3s, h + 1.5s], half-width 0.7s; sliding span [0.3, 2.0s], half-width 0.9s. Sample the hitbox against the hole mask (see the briefPlans #21 plan).


---

**title**: Hazard verdicts compare a CURRENT hazard with a STALE root position, so players feel 'I jumped/slid but still got hit'

**severity**: major

**file**: src/server/Minigames/HoleInTheWall/init.lua

**line**: 208

**rootCause**: The client owns its character, so the server's HumanoidRootPart lags the player's screen by about one-way latency plus a replication frame. Hole in the Wall compares plane(now) with that stale root (init.lua:208-231), and the server-side Sliding attribute only flips when the Movement_Slide remote arrives. Dodgeball does the same: Ballistics.position(t) against the stale root (Dodgeball/init.lua:500-505). Hazards are pure functions of server time, so the server can cheaply rewind the hazard to what the client saw, but neither minigame does. This is the same class of bug as the owner's Spin complaint (#22, 'sometimes when I jump the bar still hits me').

**evidence**: HitW init.lua:208 `local plane = Patterns.START_DIST + wall.speed * (now - wall.enter)` used against root.Position at 216; Dodgeball init.lua:500 `Ballistics.position(b.segments, b.g, math.min(t, b.endAt))` vs root.Position at 505.

**fix**: Add src/server/Minigames/_Lib/Lag.lua: `Lag.rewind(player) = math.clamp(player:GetNetworkPing() * 0.5 + 1/60, 0, 0.2)` (GetNetworkPing is round trip). HitW: compute rel per player with plane(now - rewind), and defer the verdict about 0.1 s while keeping a per-player ring buffer of the last 0.3 s of {t, rootPos, Sliding, scale}. The player passes if any sample in [tCross - 0.15, tCross + 0.1] fits the hole. Dodgeball: test each player against the segment ballPos(t - rewind - dt) -> ballPos(t - rewind). Reuse the same helper in Spin and LaserTracer.


---

**title**: Dodgeball: every hit is an instant elimination (one mistake = out), so a lone player dies in ~5 s

**severity**: major

**file**: src/server/Minigames/Dodgeball/Tuning.lua

**line**: 91

**rootCause**: knockPower starts at 135 (giant 1.2x, cap 210). Knockback.velocity gives 135 studs/s horizontal plus 54 lift (about 0.55 s of air, roughly 70+ studs of travel), while the court radius is 37.5 with no walls. AIM_AT_PLAYER 0.7 with lead and a 2.1 s volley interval mean one cannon hit almost always ends the run. The punchlist confirms 'a solo player standing still is eliminated within about 5 s'. The design leaves nothing to manage and no comeback, which matches the owner's 'boring/not engaging'.

**evidence**: Tuning.lua:89-96; Tuning.lua:6 ARENA_RADIUS 37.5; Knockback.lua:43-47; .gauntlet/punchlist.md P5 note.

**fix**: Use Smash-style damage %: session table damage[player] starts at 0, and each hit adds +30% (giant +50%, golden/player throw +45%). Knock power = 60 * (1 + damage), clamped to 220. Replicate it as character attribute "DodgeDamage" (0..3) for a head billboard and HUD. The first one or two hits then stay on the court and the third or fourth launches you.


---

**title**: Hole in the Wall still writes RUN!/JUMP!/SLIDE! on the walls and has only 3 rectangular hole kinds

**severity**: major

**file**: src/client/Minigames/HoleInTheWall/WallView.lua

**line**: 23

**rootCause**: HOLE_STYLE carries labels (WallView.lua:23-27), and label() adds two SurfaceGuis per hole (89-114, placed at 192-197). Patterns.HOLES has only NORMAL/HIGH/LOW rectangles (Patterns.lua:19-23), and makeHoles always places one rectangle per equal segment, so every wall looks the same. This breaks brief #21.

**evidence**: WallView.lua:24-26 `label = "RUN!"/"JUMP!"/"SLIDE!"`; Patterns.lua:19-23.

**fix**: Delete label(), HOLE_STYLE.label and the action color-coding. Replace hole kinds with the shared shape library described in briefPlans #21. Fx.pass (init.client.lua:86) must then take the color from the wall/shape instead of HOLE_STYLE[code].


---

**title**: Root cause of brief #16 ('fell in the water, got teleported back instead of dying'): King of the Hill is a score-kind round

**severity**: major

**file**: src/server/Core/Context.lua

**line**: 296

**rootCause**: For kind == "score", _onFall anchors the player, toasts "Oops! Back in 2..." and calls _respawnNow after SCORE_RESPAWN_DELAY = 2 s. KotH is the only score minigame (KingOfTheHill/init.lua:64), and its plate floats over World's sea (World.SEA_LEVEL = 50 - 62), which matches the owner's screenshot. Deleting KotH makes the symptom go away, but any future score mode brings it back, and Scoreboard/TOP 3 becomes dead UI.

**evidence**: Context.lua:295-306; KingOfTheHill/init.lua:64-65; docs/reference/current-game-koth.jpg (KotH over water, empty TOP 3 panel).

**fix**: Make Bomb Tag survival. If a score mode is ever added again, a fall should cost points visibly (e.g. -3 with a "SPLASH!" toast) or eliminate, not silently teleport. Show the score-kind respawn as a clear 'RESPAWNING 2..1' overlay.


---

**title**: Roulette can pick a 2+ player mode with a single participant (blocks Bomb Tag)

**severity**: major

**file**: src/server/Core/RoundLoop.lua

**line**: 102

**rootCause**: pickMinigame() runs before pickParticipants() (line 240) and filters only hidden ids and the last minigame. MIN_LOBBY_PLAYERS = 1, so Bomb Tag with one player would just explode them after 10 s (an 'allOut' result with no winner).

**evidence**: RoundLoop.lua:102-122, 240; Config.lua:17.

**fix**: Contract: optional `minPlayers: number?` in the definition. Registry publishes MinPlayers. pickMinigame(n) filters `(def.minPlayers or 1) <= #eligible()`, and the reel uses only the same filtered pool. Bomb Tag sets minPlayers = 2.


---

**title**: Core elimination text ignores the reason, so Bomb Tag cannot say BOOM and the feed duplicates

**severity**: minor

**file**: src/server/Core/RoundLoop.lua

**line**: 257

**rootCause**: onEliminated always shows "YOU'RE OUT!" and feeds "%s got knocked out! #%d". info.reason is only checked for "left". A minigame that feeds its own line ("X EXPLODED!") gets a second generic line.

**evidence**: RoundLoop.lua:266-280.

**fix**: Map reasons to text in RoundLoop, e.g. REASON_TEXT = {exploded = {big = "BOOM!", feed = "%s EXPLODED! #%d"}, fell = ..., hit = ...}, with a default. Bomb Tag calls ctx.eliminate(p, "exploded").


---

**title**: Dodgeball hit sphere is generous and ignores character scale

**severity**: minor

**file**: src/server/Minigames/Dodgeball/Hit.lua

**line**: 10

**rootCause**: A fixed PLAYER_RADIUS of 2.2 sphere around the root plus the ball radius (2) registers a hit when the ball centre is within 4.2 studs. An R15 torso is about 1 stud half-width, so balls that visibly miss by 1-2 studs still knock you out. Giant/Tiny ("Big bodies, big targets") have no effect on the hitbox.

**evidence**: Hit.lua:10-14; Dodgeball/init.lua:505.

**fix**: Use a capsule test: the vertical segment root-2.3s .. root+1.5s with radius 1.1s (s = character:GetScale()), tested against the ball segment (closest points between two segments). Combine it with the rewind from the latency bug.


---

**title**: Hole in the Wall pass check tests only the root centre, and backward crossings are never checked

**severity**: minor

**file**: src/server/Minigames/HoleInTheWall/Pass.lua

**line**: 59

**rootCause**: Pass.check accepts any root X inside [minX, maxX], so half the body can be inside solid wall. step() only resolves prev > 0 -> rel <= 0, so a player behind a wall can walk back through solid wall without any check (init.lua:223-225).

**evidence**: Pass.lua:58-61; init.lua:222-231.

**fix**: Use the hitbox sampling from the #21 plan. Also resolve crossings in the reverse direction (prev < 0 -> rel >= 0) with the same rule.


---

**title**: Hole in the Wall crossing can be skipped entirely during a server hitch

**severity**: minor

**file**: src/server/Minigames/HoleInTheWall/init.lua

**line**: 226

**rootCause**: MAX_CROSS_STEP = 12 studs per frame treats bigger relative jumps as teleports. Late-game walls move at 45 studs/s and a dash at about 82 studs/s, so a ~0.1 s server stall makes the crossing invisible and gives a free pass.

**evidence**: init.lua:33 and 226.

**fix**: Detect teleports from Context instead (respawn/Teleport sets a 'Teleported' timestamp), or scale the limit with dt: maxStep = (wall.speed + 90) * dt + 2.


---

**title**: No sound in these minigames goes through a SoundGroup, so a settings mute/volume cannot reach them

**severity**: minor

**file**: src/client/Minigames/Dodgeball/Effects.lua

**line**: 57

**rootCause**: Every Sound is created bare: HitW Fx.lua:25-34 and WallView.lua:314-321, Dodgeball Effects.lua:57-67 and Cannons.lua:97-106, KotH BatTool.lua:110-120 and Input.lua:72-78. `grep SoundGroup src/` returns nothing.

**evidence**: grep -rn SoundGroup src/ -> no matches.

**fix**: Add a shared Audio helper (src/shared/Audio.lua: Audio.sfxGroup() / Audio.musicGroup(), creating SoundService.PD_SFX / PD_Music) and set `sound.SoundGroup = Audio.sfxGroup()` in every constructor listed.


---

**title**: All four arenas reuse the same washed-out 'floating candy disc' template (maps blend together, brief #4)

**severity**: minor

**file**: src/server/Minigames/HoleInTheWall/Arena.lua

**line**: 41

**rootCause**: pastel() lerps every floor color 30% toward white, everything is SmoothPlastic, and every map has the same stacked pastel underside: HitW Arena.lua:102-111, Dodgeball Map.lua:151-155, KotH Map.lua:214-221, Sandbox init.lua:58-60. These all sit over the same sea and floating islands.

**evidence**: Arena.lua:41-43, 63; Dodgeball Map.lua:20-21, 106-155.

**fix**: Give each map its own palette and materials (see the map plan): saturated two-tone checker floors, a blocky dirt/grass island underside instead of candy tiers, no pastel lerp.


---

**title**: KotH bat swing uses the stock R15 'Slash' tool animation (barely visible); reusing it as-is in Spin would carry the weakness over

**severity**: minor

**file**: src/server/Minigames/KingOfTheHill/BatTool.lua

**line**: 246

**rootCause**: playSwing inserts StringValue toolanim = "Slash", which the stock Animate script turns into a small arm chop. Combined with a 7.5-stud cone and a 1 s cooldown, the bonk feels weak, which fits the owner's 'KotH very weak'.

**evidence**: BatTool.lua:246-251; Movement/Animations.lua keeps the stock Animate script.

**fix**: If the bat is reused (Spin #22), every client poses the swinging character's right arm procedurally when the tool attribute LastSwing changes (wind-up 0.08 s, 150° horizontal sweep 0.12 s, recover 0.2 s), instead of using toolanim. Motor6D.Transform does not replicate, so each client animates every bat holder locally.


---

**title**: Cannon hiss uses a different built-in sound extension than Hole in the Wall (verify the asset exists)

**severity**: minor

**file**: src/client/Minigames/Dodgeball/Cannons.lua

**line**: 99

**rootCause**: Cannons uses rbxasset://sounds/action_falling.ogg while HoleInTheWall/WallView.lua:315 uses rbxasset://sounds/action_falling.mp3. One of them may be silent, depending on which file the client ships.

**evidence**: Cannons.lua:99 vs WallView.lua:315.

**fix**: Check in Studio (Sound.IsLoaded / TimeLength > 0) and standardize both on the one that loads, or on uploaded SFX.


---

**title**: Dodgeball golden ball can be held forever

**severity**: minor

**file**: src/server/Minigames/Dodgeball/init.lua

**line**: 361

**rootCause**: pickUp has no expiry. A holder who never throws keeps the HUD and arrow forever. nextGoldenAt is set at pickup, so a second golden ball spawns anyway.

**evidence**: init.lua:361-373, 535-558.

**fix**: Add HOLD_LIMIT = 6 s, then auto-throw along the holder's LookVector, with a 3-2-1 shake on the held ball.


## briefPlans


---

**briefItem**: #21 Hole in the Wall: no text on walls, varied simple SHAPES (not always the same)

**currentState**: Three rectangular kinds (Patterns.HOLES N/H/L) with RUN!/JUMP!/SLIDE! SurfaceGui labels and green/yellow/cyan coding (WallView.lua:23-27, 89-114, 186-223). Pass.check uses fixed root thresholds and root-centre X only. Wire format "N:minX:maxX:bottom:top".

**plan**: FILES. New src/shared/Minigames/HoleInTheWall/Shapes.lua (pure, used by server AND client; needs the shared-minigame folder, see contractChanges). Fallback: keep it at src/client/Minigames/HoleInTheWall/Shapes.lua and require it from the server through a MotionRef-style ref, as LaserTracer does. Rewrite Patterns.makeHoles/encodeHoles and Pass.lua, update WallView.lua and Fx.pass, delete HOLE_STYLE labels.

SHAPE LIBRARY. Shapes.CELL = 0.5 studs. A shape is {id, class: "run"|"jump"|"slide"|"mixed", w, h, baseV (bottom offset, may be negative so the floor crops it, e.g. the heart tip), tier 1..3, weight, inside(u, v) -> boolean in shape-local studs, where u = lateral offset from the shape centre and v = height above the floor}. Shapes.isOpen(hole, u, v) snaps (u, v) to the raster cell centre (floor(u/CELL)+0.5)*CELL before calling inside(), so the server test matches the client's staircase exactly. Catalog at scale 1:
- RUN (floor-reaching, open >= 6.5 tall, lane >= 2.6 wide): ARCH (rect w7, v0..5.5 + semicircle r3.5 at v5.5), DOOR (w6, h8, tier 1 only), HEART (w10, h10, tip at v=-2.5), TENT triangle (base 11 at v0, apex v11), KEYHOLE (circle r3 at v7.5 + trapezoid w4->w2.6 from v0 to v6), CROSS (vertical bar w3 v0..11 + arms w11 v4.5..7.5).
- JUMP (sill >= 3.6, open span >= 6.5 tall): CIRCLE (r3.8 centred v8.2), DIAMOND (half-diagonals 3.6 x 4.6, centre v8.6), STAR (outer r6, inner r2.6, centre v9.2, tier 3), HIGH SLOT (w10, v4.4..11.2), OCTAGON (w7.5, centre v8.2).
- SLIDE (floor-reaching, top <= 3.0, width >= 4): TUNNEL (w9, v0..2.8, rounded top), MOUSEHOLE (half-disc r3 at the floor, w6), LOW WAVE (w12, top scalloped 2.4..2.9).
- MIXED (two valid postures): L (vertical w3 v0..10 + foot w9 v0..2.8), T-inverted.
Wall: WIDTH 66, HEIGHT 16 (raised from 14), THICK 2.

GENERATION (Patterns.makeHoles(rng, tuning, wallIndex, history)): 1-3 holes, each placed by centre cx in its segment. Walls 1-3 are a no-text tutorial: wall 1 two RUN shapes, wall 2 one JUMP shape + one RUN, wall 3 one SLIDE + one RUN. After that, pick by weight from tiers unlocked by intensity (tier 2 at i >= 1.6, tier 3 at i >= 2.4). Never reuse a shape id seen in the last 3 holes. At most 2 holes of the same class per wall. scale = clamp(1.1 - 0.12*(i-1), 0.82, 1.1) times a per-hole random factor 0.95..1.05. Wire format: Holes = "id:cx:scale" joined by ";" (bottom comes from the catalog). The client validates id against the catalog, |cx| <= 30, scale in [0.7, 1.3].

PASS CHECK (Pass.check(hole, localX, rootH, sliding, charScale) -> boolean, pure). Hitbox samples: 3 columns (u = x-0.7s, x, x+0.7s) by rows every 0.5 studs over the span: standing/jumping [h - 2.3s, h + 1.5s]; sliding [0.3, 2.0s] with columns at +-0.9s. Pass when every centre-column sample is open and at most 2 outer-column samples are blocked (forgiveness). With several holes, the player passes if any hole passes. Verdict window: init.lua keeps a ring buffer (24 entries) per player of {t, rootPos, Sliding, GetScale()} written every Heartbeat. On crossing (computed with the rewound plane, see the lag bug), queue {wall, player, tCross} and resolve at tCross + 0.1. Pass if any buffered sample with t in [tCross - 0.15, tCross + 0.1] passes at its own localX. Otherwise knockback.

VALIDATION (must ship). Shapes.selfTest() simulates standing (h = 3s), a jump arc h(t) = 3 + 52t - 98.1t^2 for s in {0.6, 1, 1.6}, and sliding, at every x in steps of 0.25, for scales {0.82, 1, 1.1}. It asserts: RUN shapes pass standing; JUMP shapes do NOT pass standing and have a passable jump window >= 0.22 s; SLIDE shapes pass only when sliding; MIXED shapes pass via both declared postures. The critic runs it through execute_luau.

READING JUMP/SLIDE FROM THE SHAPE (no text): position encodes the action. A floor-reaching tall hole means run, a floating hole (sill about 4 studs, clearly above the white base band) means jump, and a flat wide slot at floor level means slide. Reinforce without text: (1) a 0.35-stud white neon rim around every hole (build the front panel from the mask dilated by 1 cell, plus a thin recessed white backing layer from the exact mask, about 1.6x parts); (2) the floor telegraph patch is the shape's real footprint, a filled glow strip for floor shapes and a hollow 0.3-stud outline floating 0.2 studs up for jump shapes; (3) wall colour is random per wall from a saturated palette {(255,64,64), (255,149,0), (255,214,10), (52,199,89), (10,132,255), (191,90,242), (255,55,140)}, never encoding the action.

RENDERING / PERFORMANCE (WallView). Split the wall into solid vertical strips between hole bounding boxes (1 part each) plus, per hole bbox, a 0.5-cell raster meshed by row runs with vertical merging of identical runs, plus 1 rect above and 1 below the bbox. Expect about 30-45 parts per shape, so a 3-hole wall is about 110-140 parts (about 200 with rims). Keep a per-arena pool of Parts (WallView.acquire/release, up to 800) instead of Instance.new per wall. Keep BulkMoveTo, which handles about 1000 parts per frame. Rasterize and mesh once per wall in WallView.new; nothing happens per frame except BulkMoveTo.

**risks**: Shapes must be validated numerically or kids hit 'impossible' holes; selfTest is mandatory. The rim layer doubles part count, so make it a flag. Shared-folder contract approval is needed, otherwise use the MotionRef pattern. Changing WALL_HEIGHT also changes the client telegraph and pylons (Arena.lua:138-149).


---

**briefItem**: #6/#12 Hole in the Wall made dynamic and addictive

**currentState**: One wall pattern loop. Speed, gap and sides ramp. Every miss is lethal (power 170-240), including the tutorial walls. A pass only gets a 'NICE!' word.

**plan**: In init.lua/Patterns.lua: (1) SWAY walls at intensity >= 1.8: the wall translates sideways, lateral(t) = A*sin(w*(t - enter)) with A 6..12 and w 0.9..1.6 rad/s. Send SwayAmp/SwayFreq attributes, the client adds self.right*lateral in WallView:update, and the server uses localX - lateral(tCross). Widen the wall to 66 + 2A so it always covers the platform. (2) DOUBLE walls at intensity >= 2.2: two walls 0.55 s apart from the same side with complementary classes (jump then slide). (3) Streak and PERFECT: count consecutive passes per player. A centre-lane pass (|u - laneCentre| < 0.6) fires "pass" with extra args (streak, perfect). The client shows a big combo counter (x2..x20) and a PERFECT pop with a rising pitch ding. Expose the streak as player attribute HitW_Streak for Economy bonus coins later. (4) Gentle onboarding: walls 1-3 knock with power 70, stun 0.4 (survivable shove), and the 'WALLS FROM N SIDES' announce stays. (5) A late-game 'speed wall' every 6th wall at 1.6x speed with a red telegraph.

**risks**: Sway plus 4 sides can get unreadable. Keep sway to 1 axis at a time and cap simultaneous walls at 4.


---

**briefItem**: #6/#12/#8 Dodgeball made dynamic and engaging (competition, choices)

**currentState**: Passive: run and jump while cannons fire. One hit = out (bug above). One golden ball every 12 s is the only interaction.

**plan**: Server Dodgeball/init.lua + Tuning.lua: (1) DAMAGE %: damage[player] += 0.30 (giant 0.50, thrown 0.45). power = min(220, 60*(1+damage)). Character attribute DodgeDamage (number). Client billboard above each head showing the percentage, white -> yellow -> red, wobbling on change. (2) EVERYONE CAN THROW: when a normal ball fizzles inside the court, spawn a pickup (pooled part, 5 s life, pulsing ring) at plan end. Generalize holders[p] = {kind = "gold"|"ball", ...} and replace the character attribute with HoldingBall = ""|"gold"|"ball". Throw.lua keys off it (button colour by kind). Thrown normal ball: speed 120, power base 70 + damage scaling, aim assist 12°. Keep GOLD as the super ball (power +60%). Rate limits stay (THROW_COOLDOWN 0.4, one held ball). Add HOLD_LIMIT 6 s auto-throw. (3) SHRINKING COURT: build the court floor as a centre disc of radius 25 + two rings of 16 radial block segments each (25..31, 31..37.5). At 40 s the outer ring flashes red for 2.5 s and drops (the client tweens it down, the server sets CanCollide=false and Transparency=1). At 75 s the middle ring does the same. Update floor.radius used by Ballistics.plan for new shots and the client marker/shadow (map attr ArenaRadius already replicated). (4) CLOSE CALL: when a ball passes within hitRadius + 1.5 without a hit, fire a local 'CLOSE!' pop and whoosh for that player (FireClient). (5) Tuning: GRACE 2.5 s, first 10 s volleySize 1 and fireInterval >= 1.6 s, AIM_AT_PLAYER 0.55 for the first 15 s.

**risks**: Pickup throws add a client->server path (already validated). Ring segments need care so cannon ballistics do not bounce on 'air'; plan with radius = min(current, the radius at landing time).


---

**briefItem**: #10 Replace King of the Hill with BOMB TAG (10 s fuse, holder explodes, next player gets it, dynamic map with obstacles)

**currentState**: No Bomb Tag exists. KotH folders exist (to delete). The contract has no minPlayers and no reason-aware elimination text.

**plan**: FILES: src/server/Minigames/BombTag/{init.lua, Map.lua, Rules.lua (pure), Tuning.lua}; src/client/Minigames/BombTag/{init.client.lua, Hud.lua, Fx.lua, Pads.lua}.

DEFINITION: id "BombTag", displayName "BOMB TAG", rules "Got the bomb? Tag someone before it blows!", keys {"Dash","Jump","Slide"}, kind "survival", soloCapable false, minPlayers 2 (contract).

TUNING: FUSE 10 (fuse continues across passes, hot-potato), FIRST_ASSIGN_DELAY 2.5 s after GO (client spotlight roulette sweeps over players), NEXT_BOMB_DELAY 3.0 s after a boom, TAG_RANGE 5.0 studs flat with |dy| <= 5 (server auto-tag on Heartbeat), CLAIM_RANGE 8.5 (client claim validated with server positions), PASS_LOCK 0.4 s (new holder cannot pass back instantly), NO_TAG_BACK 1.5 s (previous holder cannot receive it), HOLDER_SPEED_MULT 1.12 on Humanoid.WalkSpeed (store the original in character attr BombBaseSpeed; no modifier touches WalkSpeed today), PASS_BUMP power 40, stun 0.15, on the new holder along the pass direction, EXPLOSION_RADIUS 14 with outward power 75 and stun 0.35 on others (non-lethal), HOLDER_LAUNCH ctx.knockback(holder, up + random flat, 140, 1.0) then ctx.eliminate(holder, "exploded") after 0.7 s (holder cleared immediately so they cannot tag in between).

STATE MACHINE in create() closure: state "wait"|"live"|"boom", holder: Player?, prevHolder, noTagBackUntil, passLockUntil, fuseEnd (server time). Heartbeat: if state == live and (not ctx.isAlive(holder) or holder.Parent == nil), reassign to a random alive player with fuseEnd = max(fuseEnd, now + 4). Then auto-tag scan (holder vs ctx.players()). If now >= fuseEnd, explode. After a boom, wait NEXT_BOMB_DELAY, then if #ctx.players() >= 2 assign a random alive player (Rules.pickNext(rng, alive, lastHolder) never picks the same player twice in a row when there is a choice). Core ends the round at alive <= 1 (lastStanding).

REPLICATION: map attrs BombHolder (userId, 0 = none), FuseEnd (server time), BombState, Passes, Booms. Character attr HasBomb = true on the holder. Server-made visuals: bomb ball welded above the head (pattern from Dodgeball Map.heldBall: massless, no collide), a red Highlight on the holder, and a BillboardGui countdown driven by the clients from FuseEnd (no per-tick remotes). Remotes: BombTag_Fx (server -> all: "assign"/"pass"/"boom", map, args) and BombTag_Tag (client -> server: targetPlayer; validate sender == holder, target alive and in session, server distance <= CLAIM_RANGE, PASS_LOCK and NO_TAG_BACK, rate limit 8/s). Map tag "BombTag_Arena" (CollectionService) for client discovery.

MAP (Map.lua, everything relative to ctx.center): square 96x96 floor, two-tone grass checker 8x8 tiles ((98,200,72)/(84,182,60), Plastic), 5-stud border wall with orange/brown checker blocks (ref4) so nobody falls by accident. KillY = center.Y - 20 as a safety. Obstacles: central tower 16x16 raised 6 studs with 2 ramps (reuse the KotH Map.ramp builder, KingOfTheHill/Map.lua:91-130) and a 3-stud slide tunnel through its base (rewards the slide). 4 L-shaped crate walls (4x4x4 blocks, 1-2 high) at the quadrants to juke around. 6 knee-high hurdles (1.6 studs, jumpable). DYNAMIC: 4 pop-up pillars 6x6 at (+-22, +-22) rise 0 -> 7 studs every 8 s with a 1.2 s yellow flash first (server TweenService on anchored parts). 4 bounce pads at (0, +-38) and (+-38, 0): client Pads.lua checks the local root within 3.2 studs flat and <= 3.5 above the pad and sets AssemblyLinearVelocity.Y = 85 with a spring FX. 2 conveyor lanes along the east and west edges (anchored part with AssemblyLinearVelocity = 18 along the lane). Spawns: 12 on a ring of radius 32 facing the centre.

CLIENT: Hud.lua shows, when you hold the bomb, a huge top-centre countdown (FuseEnd - GetServerTimeNow, one decimal under 3 s), a pulsing red edge vignette, an accelerating tick (PlaybackSpeed 1 -> 2.2) and an arrow to the nearest player. Otherwise it shows an edge arrow to the bomb holder and a 'DANGER' pulse within 15 studs. Fx.lua: assign spotlight sweep, 'TAGGED!' pop on pass, explosion (neon sphere burst + shockwave ring + debris + local camera shake within 35 studs + boom), all sounds via the SFX SoundGroup. The client sends a BombTag_Tag claim when the local holder sees a character within 5.5 studs.

FEED/ANNOUNCE: ctx.announce("BOMB!", name .. " has the bomb!") on assign; feed "A tagged B!" (throttled 1/s); feed "BOOM! X exploded" once Core is reason-aware.

**risks**: Without minPlayers the roulette can pick it solo. A Debug_NoEliminate respawn keeps the exploded player alive (fine, the next bomb is assigned anyway). A revive (#28) must re-enter the alive set cleanly (needs a contract hook). Server-tweened pistons must not crush or stick players: make them rise only when nobody is within 4 studs of the pillar (skip that cycle).


---

**briefItem**: #10 (cleanup) Delete King of the Hill, keep what is reusable

**currentState**: KotH lives in 10 files; references outside its folders listed below.

**plan**: MOVE before deleting: src/server/Minigames/KingOfTheHill/Bat.lua and BatTool.lua -> src/server/Minigames/_Lib/Bat.lua and _Lib/BatTool.lua (a Folder without init is ignored by Registry, like Modifiers/_Lib). Rename the tool attribute KOTH_Bat -> PD_Bat and the ObjectValue KOTH_Map -> PD_Map. Reuse in Spin (#22) and optionally Bomb Tag. Client: KingOfTheHill/Input.lua (touch SWING button skin, layout left of Jump, Backpack hide, hit confirm) and Ui.lua -> src/client/Minigames/_Lib/BatInput.lua + _Lib/Ui.lua. The Hud.lua status-pill pattern (+1/BONK pops, Tutorial avoidance) -> template for the Bomb Tag HUD. KotH Map helpers part/decor/disc/cylinderCFrame/ramp (Map.lua:49-130) -> src/server/Minigames/_Lib/Build.lua for all map builders. Crown BillboardGui + WorldFx bob -> bomb-holder marker. PLAYER_COLORS (init.lua:40-53) -> _Lib.
DELETE: src/server/Minigames/KingOfTheHill/{init.lua, Map.lua, Zone.lua} and src/client/Minigames/KingOfTheHill/{init.client.lua, Hud.lua, WorldFx.lua} (after moving Bat, BatTool, Input, Ui). This also removes remotes KingOfTheHill_Swing/_Fx, tags KOTH_Map/KOTH_Crown, ScreenGui KingOfTheHillHUD and CAS action KingOfTheHill_Swing.
UPDATE: src/shared/Theme.lua:28 (frozen, lead) replace KingOfTheHill with BombTag = Color3.fromRGB(255, 70, 40); Data.knownIds (src/client/UI/Data.lua:146) falls back to MinigameColors keys, so a stale KotH entry would put a KotH card in the reel. src/client/UI/Data.lua:28 icon -> BombTag = "💣" (and the comment at :68). src/client/Shop/CosmeticsTab.lua:108 default bat swatch Theme.MinigameColors.KingOfTheHill -> Theme.Colors.Orange (it would be nil and crash or blank otherwise). src/shared/Economy/Cosmetics.lua:7 and :89 comments -> 'read by _Lib/BatTool (Spin bat)'. Keep the BatColor slot and Config.UPGRADES.BatPower / Config.PRODUCTS.UpgradeBatPower / Economy/Rules.lua:28,33 ONLY if Spin gets the bat (#22); otherwise drop BatPower from Rules.UPGRADE_ORDER (Config keys are frozen, so leave them). src/shared/Maps/Lobby.lua:340 'CLICK Swing / Throw' stays valid with a Spin bat. src/client/UI/Data.lua:175 KEYS.Swing stays. No KotH reference in Tutorial.lua, Solo (KotH not soloCapable, Emblems.lua has no entry) or Economy Rewards. After deletion no score-kind minigame remains, so UI/Scoreboard.lua (TOP 3) and the score branches of Hud/Results/Intro become dormant (keep them, they are kind-generic).

**risks**: Moving BatTool changes the require paths for whoever builds the Spin bat, so coordinate the order: the move lands first.


---

**briefItem**: #2/#4/#7/#9 Map look for these modes (simple blocky bright Roblox style, maps must not blend)

**currentState**: HitW: pastel stripes (30% white) + candy tiers. Dodgeball: orange/gold disc + candy underside + clouds + floating balls. KotH: pastel cake. Sandbox: pastel discs. Everything is SmoothPlastic and the same floating-candy silhouette.

**plan**: Shared builder _Lib/Build.lua: checker(parent, cframe, sizeX, sizeZ, tile, colorA, colorB) builds tile parts (8-stud tiles, so a 64x64 floor is 64 parts) in Plastic. voxelIsland(parent, center, halfSize) builds a stepped dirt/grass underside of 4-6 block layers (Ground/Grass materials, brown (150,96,56) / dirt (124,78,44), top lip grass (96,196,72)), replacing every candy tier stack. HitW = 'TV game show': blue checker floor (40,120,255)/(28,98,220), yellow/ink hazard rim (keep), white pylons, saturated walls. Dodgeball = 'sports court': grass island, red/blue court halves (232,62,62)/(52,120,232) with white Plastic lines, a ring of voxel bleachers (decor), navy cannons with team-coloured barrels; drop the clouds and floating balls. Bomb Tag = 'toy plaza': green checker + orange/brown checker border walls (ref4), red/black hazard accents, wooden crates. Lead-level: if MaterialVariants or uploaded checker textures (generated per #5) become available, swap tile parts for one Part plus Texture to cut part count.

**risks**: Part count: checker tiles plus voxel island add about 150-250 parts per map, acceptable. Do not let decor CanCollide (keep the decor() helper).


---

**briefItem**: #18/#22 (fairness) Lag-compensated hazard verdicts shared by all hazard minigames

**currentState**: HitW and Dodgeball judge the current hazard against a stale server root (bug above). Spin has the same complaint in the brief.

**plan**: src/server/Minigames/_Lib/Lag.lua: Lag.rewind(player): number (clamp(GetNetworkPing()*0.5 + 1/60, 0, 0.2)); Lag.History.new(maxAge = 0.4) with :record(player, t, root, sliding, scale) called from each session's Heartbeat and :samples(player, t0, t1). HitW: rel uses plane(now - rewind) and the verdict is deferred 0.1 s with the window check. Dodgeball: per player, test the segment ballPos(t - r - dt) -> ballPos(t - r) against the capsule. Document in ARCHITECTURE.md that hazards defined as functions of server time must be rewound, not players.

**risks**: High-ping exploiters gain up to 0.2 s of grace (capped). Acceptable for a kids' party game.


---

**briefItem**: #23/#25 Sounds in these minigames: mutable via settings, hit sound

**currentState**: Sounds are bare (no SoundGroup). The hit sound exists (HitW Fx thud/crash, Dodgeball pop, KotH bonk) but uses stock rbxasset sounds.

**plan**: After a shared Audio helper exists (contract), set sound.SoundGroup = Audio.sfxGroup() in HoleInTheWall/Fx.lua sound() and WallView whoosh, Dodgeball Effects.makeSlot and Cannons hiss, Throw whoosh, and every Bomb Tag sound. Use one consistent 'hit' SFX id (from Audio.Ids.Hit) for HitW hit, Dodgeball pop on a player, and the Bomb Tag pass bump, so 'hit sound' is recognisable across modes.

**risks**: Needs the Audio module before these edits.


---

**briefItem**: #3 Controls inside these modes

**currentState**: Dodgeball THROW: PC left click, mobile gold CAS button placed left of Jump (Throw.lua:159-221), gamepad R2. KotH SWING: same layout with its own copy of the layout code (Input.lua:95-126). HitW and Bomb Tag rely on jump/slide/dash.

**plan**: Move the duplicated jumpButtonRect/layout/skin code (Throw.lua:159-221 and KotH Input.lua:95-187) into src/client/Minigames/_Lib/ActionButton.lua: ActionButton.bind(actionName, title, color, callback, keys) returns a handle with :setCooldown(frac) and :destroy(). Same size rule (0.86 x jump size), placed left of Jump, press-scale tween. Dodgeball throw: also accept E/F on PC. Throw on input Begin with a 0.1 s client buffer while a held ball is about to arrive. Bomb Tag needs no extra button.

**risks**: Coordinate with Movement's own Dash/Slide button placement so nothing overlaps on 800x360.


---

**briefItem**: #17 Spectating these modes

**currentState**: HitW renders every tagged arena for every client. Dodgeball fires Fx to all clients with a 900-stud cull, and stands are about 120 studs away, so spectators see the balls.

**plan**: Bomb Tag: BombTag_Fx FireAllClients plus a map tag so spectators see the bomb, countdown billboard and explosions. The HUD shows the holder name and fuse for spectators too (spectator mode: no vignette, holder-cam suggestion). Expose map attr BombHolder so the Spectate system can offer 'watch bomb holder'.

**risks**: none


---

**briefItem**: #19/#28 Monetization hooks inside these modes

**currentState**: No mode-specific hooks. There is no revive API in ctx.

**plan**: Bomb Tag: a cosmetic slot 'BombSkin' (Cos_BombSkin read by BombTag init when building the held bomb: classic, watermelon, gift box, rainbow), priced in Robux or coins via Economy. HitW: HitW_Streak attribute for an Economy streak bonus. Revive (#28): minigames need a session:onRevive(player) hook (HitW: clear the ring buffer and wall.rel; Dodgeball: reset damage to 0; Bomb Tag: give 1.5 s NO_TAG immunity, never assign the bomb within 2 s of a revive).

**risks**: Revive requires a Core change (Context:_revive) owned by the lead.


---

**briefItem**: _Sandbox (Core test fixture)

**currentState**: Hidden 'BALL DROP' survival, physics balls with SetNetworkOwner(nil), distance-based knockback, pastel discs. Only reachable through Debug_ForceMinigame=_Sandbox.

**plan**: Leave it functionally as is (it is the Core loop fixture). Optionally switch its map to _Lib/Build helpers so it does not drag in old palette code. No player-facing work.

**risks**: none

**contractChanges**: 1. Contracts/Minigame.lua: add optional `minPlayers: number?` (default 1). Registry publishes it as MinigameInfo attr MinPlayers. RoundLoop.pickMinigame filters the pool by `#eligible() >= minPlayers` (and builds the reel from the same filtered pool). Bomb Tag = 2.
2. Contracts/Minigame.lua: add optional `incompatibleModifiers: {string}?`, honored by RoundLoop.pickModifier for the chosen minigame. HoleInTheWall lists "LowGravity" unless it implements the tall-wall fallback. Bomb Tag may list "Slippery".
3. Elimination reasons: document reason strings ("exploded", "hit", "fell"...) and make RoundLoop.onEliminated (RoundLoop.lua:257-281) choose big/feed text from a reason table (default: current text) so minigames do not double-feed.
4. Revive (#28): add Context:_revive(player) (Core) plus an optional session hook `onRevive: (self, player) -> ()` so minigames can reset per-player state (HitW ring buffer/rel, Dodgeball damage %, Bomb Tag immunity).
5. Shared minigame code location: allow `src/shared/Minigames/<Id>/` (ReplicatedStorage.Shared.Minigames.<Id>) owned by that minigame's piece, so pure modules used by both server and client (HitW Shapes.lua) live there instead of the MotionRef/BarMath 'server requires StarterPlayerScripts' workaround. Update ARCHITECTURE.md.
6. Server shared helpers: bless `src/server/Minigames/_Lib/` (a Folder that Registry ignores, like Modifiers/_Lib) for Bat.lua, BatTool.lua (moved from KotH), Build.lua (map builders: part/decor/disc/ramp/checker/voxelIsland), Lag.lua (rewind + history). Client counterpart `src/client/Minigames/_Lib/` for ActionButton.lua (touch action button left of Jump) and BatInput.lua.
7. Theme.lua (frozen): remove MinigameColors.KingOfTheHill and add BombTag = Color3.fromRGB(255,70,40). Brief #7 also implies a new saturated palette (drop pastel MapPalette usage).
8. Audio: new shared src/shared/Audio.lua with Audio.sfxGroup()/musicGroup() (SoundGroups under SoundService, with volumes driven by the settings mute) and Audio.Ids for common SFX (Click, Hit, Whoosh, Boom). All minigame sounds must set SoundGroup.
9. ARCHITECTURE.md: document the attributes added here: character HasBomb, BombBaseSpeed, DodgeDamage, HoldingBall ("", "gold", "ball", replaces HoldingGoldenBall); map BombHolder/FuseEnd/BombState; player HitW_Streak. Note that after KotH removal no score-kind minigame remains.
10. Contract docs: Minigame.lua says jump detection uses "root >= ~4.5 studs above floor". Replace it with "use character:GetScale()-aware posture hitboxes plus Lag.rewind"; the fixed thresholds are wrong for Giant/Tiny.

**qualityNotes**: - Part pooling: HitW WallView does Instance.new for every wall (about 15 parts and 2-6 SurfaceGuis today; shapes push it to 100-200), so add a per-arena Part pool. Dodgeball Balls/Effects already pool well; HitW Fx creates one shockwave Part per hit, which is acceptable.
- HitW client connects HoleInTheWall_Fx lazily inside pcall because Net.event waits 30 s. Bomb Tag should create its remotes at module load (like Dodgeball/init.lua:35-36 and KotH init.lua:56-57) so clients can connect at boot.
- Dodgeball client creates a permanent workspace.PD_DodgeballClient folder (185 descendants) even in the lobby. It is harmless but could be parented under the first arena or created lazily.
- ctx.players() allocates a new table per call; Dodgeball calls it several times per Heartbeat (stepBalls, stepGolden, volley, pickTarget). Cache once per step.
- Exploit surface: Dodgeball_Throw is validated (holder check, finite vector, 0.4 s cooldown). BombTag_Tag must validate the sender is the holder, the target is alive in the same session, the server distance is <= 8.5, PASS_LOCK/NO_TAG_BACK, and rate-limit 8/s. Never trust a client-sent position.
- KotH Input hides the Backpack CoreGui globally. If the bat moves to Spin, keep the hide/restore logic in one owner (BatInput) to avoid fights with other systems.
- KotH swing feel: the stock 'Slash' toolanim is weak. Any reused bat needs a proper swing (procedural arm pose on every client, keyed off the tool attribute LastSwing).
- Hit/pass verdicts should all use one shared posture hitbox helper (scale-aware) so HitW, Dodgeball, LaserTracer and Spin agree on what 'jumping' and 'sliding' mean.
- Telegraph 'whoosh' (WallView.lua:314) and cannon 'hiss' use stock rbxasset sounds with mismatched extensions (.mp3 vs .ogg); verify both load or replace them with uploaded SFX.
- Owner screenshot (docs/reference/current-game-koth.jpg) shows an empty dark 'TOP 3' panel during KotH; that is UI/Scoreboard's job, but it is dormant once no score mode exists.
- HitW pickSide with 2 unlocked sides strictly alternates (it excludes lastSide), so it is predictable. Allow a repeat with 30% chance.
- Bomb Tag: never use Touched for tagging (client-owned characters make server Touched unreliable). Use the Heartbeat distance scan plus the validated client claim.
