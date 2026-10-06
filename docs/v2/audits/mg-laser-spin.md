# Audit: mg-laser-spin

**subsystem**: Minigames: Laser Tracer + Spin (pillars), incl. porting the KOTH bat into Spin

**howItWorks**: LASER TRACER (survival, soloCapable). Server: src/server/Minigames/LaserTracer/init.lua.
- create(ctx) calls Arena.build(center) (Arena.lua:274). The map has:
  - Floor: a collidable Base cylinder r=42, plus about 150 non-collide pastel ring tiles from Theme.MapPalette (Arena.lua:78-133).
  - Rim: 64 non-collide Trim/Glow segments in pink Theme.MinigameColors.LaserTracer (Arena.lua:135-157).
  - Hub, THE CENTER PILLAR: a collidable Column 6.6x13 and a collidable Dome Ball 8, with LowRing/HighRing (Arena.lua:171-209).
  - Emitters: 8 non-collide towers at r=48 with a Lens and an "Angle" attribute.
  - Spawns: 12 at r=21. Lasers: a Folder.
  - Tag "LaserTracerMap"; attributes Center, Hits, LaserSpeed, ActiveLasers, PowerDown.
- Motion math lives in src/client/Minigames/LaserTracer/Motion.lua. The server requires it from StarterPlayerScripts through MotionRef.lua.
  - Each laser is a Model map.Lasers.LaserNNN. Its State string attribute holds pattern|kind|tWarn|tOn|tOff|a|b|t0|s|revAt.
  - "sweep" is a ray from HUB_RADIUS 3.4 to RIM 42.6 that rotates around the CENTER at s rad/s; revAt is a scheduled reversal.
  - "slide" is a full chord that moves along heading a at s studs/s, from -ENTRY to +ENTRY (43.4).
  - Heights: low 1.6, high 4.6. Colors: low pure red (255,30,30), high cyan (0,215,255) (Motion.lua:28,35-38).
- Director.lua scales everything with ctx.intensity():
  - 2 to 4 sweeps that all share one angular speed, 0.55*I^0.75 rad/s capped at 2.4 (sweepSpeed). rekeySweeps changes them together.
  - From I>=2.2, reverseSweeps flips all sweeps at once.
  - Slide waves (single/combo/cross/pincer/comboCross) come every 6.5/I^0.8 s.
  - MAX_LASERS 9, WARN_TIME 1.1 s.
- Lasers.lua (LaserSet) builds each Model and a server-side Telegraph: a neon cylinder preview, chevrons and a BillboardGui "JUMP!"/"SLIDE!". step() sets Live, folds reversals and destroys a laser after tOff+FADE+LINGER. powerDown sets the PowerDown attribute.
- Hits (init.lua:101-136) run every Heartbeat for each alive player:
  - tb = now - clamp(ping/2+0.03, 0, 0.2), ta = tb - dt.
  - Motion.crossed checks whether the perpendicular distance changed sign within HIT_HALF_WIDTH 1.15. Then Hit.check: low hits unless root >= floorY+4.2; high hits unless the Sliding attribute is set (0.15 s grace).
  - On a hit: ctx.knockback (power 95+15(I-1), max 165, stun 0.6) along the beam's motion plus 0.3 outward, a 1 s cooldown, and remote LaserTracer_Zap (unreliable, FireAllClients).
- Client (src/client/Minigames/LaserTracer): init.client.lua keeps one Renderer per tagged map.
  - Renderer.update places every beam each RenderStepped from Motion and GetServerTimeNow. It also pulses telegraphs, lights emitter lenses, flashes the hub rings and plays beeps (Sounds.lua uses rbxasset sounds).
  - Fx.newBeam makes core/glow/floor neon parts, 2 nodes with PointLights and sparks; Fx.zap plays the hit effect.

SPIN (survival, soloCapable). Server: src/server/Minigames/Spin/init.lua.
- Arena.build (Arena.lua:331) creates:
  - 12 Pillar models at RING_RADIUS 36. Each has a Body (slate cylinder r=3.6, 26 tall, y -27..-1), a FOOT (r=4.6, y -27..-24, collidable), neon Band/Glow parts, a white Top (r=4.5, y -1..0) and Ring/Dot.
  - Hub: collidable DiamondPlate r=3, top flush at y=0.
  - Lava basin with top at -23.5 (non-collide), a rock island, a candy rim and embers.
  - Bars/Bar1: neon Core, glass Shell, 2 Tip balls with trails, Cap.
  - Spawns: one per pillar. KillY = center.Y-24. Tag "SpinArena".
- BarMath (client module; the server requires it through Arena.clientModule) stores a segment {a0,t0,w0,w1,ramp,dir,rt} in the bar's "State" attribute. It provides angle(t), velocity(t), timeUntil, and reversals over TURN_TIME 0.5 with TELEGRAPH 1.1.
- updateSpeeds runs every 0.25 s and re-anchors each bar to speedFor(I) = 1+0.75(I-1) rad/s, which is UNBOUNDED. Bar2 (cyan, opposite direction, 0.8x speed) rises from the hub at I>2.2. Random reversals start at I>=3.
- Hits (init.lua:222-264) run every Heartbeat and are SERVER-AUTHORITATIVE:
  - Uses the server-side root position; height = localY - standHeight.
  - Lag = ping/2 (max 0.2). Swept substeps of 0.07 rad.
  - Hit.check: feet < 1.4 and > -5.5 relative to the pillar tops, and |armDistance| <= 2.0/r + speed/60.
  - knock: tangent + 0.65 outward, power 140, stun 0.9.
- Client (Spin/init.client.lua) pivots bars locally each frame. It animates the rising bar, flashes white before a reversal, lights each pillar's Glow 0.55 s before an arm arrives, and plays a whoosh at 0.18 s. The whoosh only runs when the player is InRound.

KOTH bat (to port). Bat.lua holds the pure frontal-cone math. BatTool.lua builds a welded-part Tool (Cos_BatColor parse, trail, whoosh, bonkFx). KOTH init.lua:246-396 has giveBat/trySwing/resolveHits with remotes KingOfTheHill_Swing/_Fx. The client side is KingOfTheHill/Input, Hud, Ui and init.client.lua: a touch SWING button, a hidden backpack and a cooldown chip.


## bugs


---

**title**: Spin: collidable 'Foot' ring at the bottom of every pillar is a safe ledge (immune + never eliminated)

**severity**: critical

**file**: src/server/Minigames/Spin/Arena.lua

**line**: 111

**rootCause**: buildPillar creates disc 'Foot' with its top face at local y = -(PILLAR_HEIGHT-2) = -24, 3 studs tall (y -27..-24), radius BODY_RADIUS+1 = 4.6. It sticks out 1.0 stud from the Body (r 3.6) and is collidable (the part() default CanCollide is true). The lava above it (Arena.lua:163-168) is CanCollide=false and Transparency 0.3, with its surface at -23.5, so the ledge sits 0.5 studs under see-through, non-solid lava. KillY = center.Y - KILL_DEPTH(24) (Arena.lua:32,335), and Core only eliminates when root.Position.Y < killY (Context.lua:395). A character standing on the Foot has its root at about -21, so it is never eliminated. Spin Hit treats heightAboveTop = -24 <= LOW_LIMIT -5.5 as 'bar passes over head' (Hit.lua:17,48), so the bar never hits it either. Walking or being nudged off the pillar edge drops you straight down onto the ring.

**evidence**: Arena.lua:111-113: disc(model, center, "Foot", top - Vector3.new(0, PILLAR_HEIGHT - 2, 0), 3, BODY_RADIUS + 1, SLATE_DARK, {Material=Slate}) with no CanCollide=false. Root on the ledge is about -24+3 = -21 > KillY -24. In a 2+ player round, the ledge camper wins once everyone else falls. In a 1-player round it lasts until SAFETY_ROUND_LIMIT 300 s. Matches brief #22 'small piece of wall at the bottom of the pillars you can stand on'.

**fix**: Delete the Foot disc (Arena.lua:111-113). Change Arena.KILL_DEPTH from 24 to 21, so root.Y < center.Y-21 means the feet are about 0.5 into the lava and you die on touching it. Set Hub CanCollide=false as well (see the hub bug). Add a build-time invariant in Arena.build: every BasePart under the map with CanCollide=true must be named 'Top' or 'Body'. Studio test: put a character at pillarTop + (4.3, -21, 0) and expect elimination within 0.3 s. Raycast down at r=4.2 around each pillar from y=-5 and expect no hit above y=-30.


---

**title**: Spin: 'I jumped but the bar still hit me': server-side hit check compares a stale root height against a bar that is ahead in time

**severity**: critical

**file**: src/server/Minigames/Spin/init.lua

**line**: 242

**rootCause**: Hits are server-authoritative on the server's copy of a CLIENT-OWNED character. That position reaches the server about ping/2 plus the physics-replication interpolation buffer (roughly 50-120 ms) late. checkPlayer rewinds the bar only by ping*0.5 (init.lua:242-244), so each height sample is compared with the bar E = 0.05-0.12 s further along than what the player saw. Jump physics: JumpPower 52, gravity 196.2. Apex is 6.89 studs at 0.265 s, total airtime 0.53 s, and feet >= CLEAR_HEIGHT 1.4 only from t = 0.028 s to t = 0.502 s. A jump therefore has to start at least E + 0.028 s + (HALF_WIDTH 2.0 + speed*SWEEP_WINDOW*r)/(w*r) before the bar reaches the player. At w = 2.5 rad/s (I = 3, 90 studs/s at the ring) that is about 0.12+0.03+0.04 = 0.19 s. Any late jump that clears on screen counts as a hit. The error is one-sided: late jumps are punished, early jumps are forgiven, because the stale sample still shows the player in the air. Unbounded bar speed (bug below) makes it worse. The legacy game had no such complaint: it detected hits on the CLIENT and the server only checked plausibility.

**evidence**: init.lua:242-244: lag = clamp(ping*0.5, 0, MAX_LAG 0.2), t1,t0 = now-lag, prev-lag. Height uses the current server sample root.Position (init.lua:232,237). Hit.lua:16 CLEAR_HEIGHT 1.4, :19 HALF_WIDTH 2.0, :21-22 SWEEP_WINDOW 1/60 up to MAX_SWEEP 0.2 rad. Legacy: legacy/scripts/SpinnerClient.client.lua:17-43,60-72 (client swept hit, then FireServer) and legacy/scripts/GameServer.server.lua:179-202 (server accepts the hit if |armDistance| <= 0.35 + speed*0.35).

**fix**: Make the client authoritative for the local hit, as legacy did, and have the server validate it. Server authority buys no anti-cheat here: Core_Knockback is applied by the owning client anyway (Knockback.lua:159-195). Spec:
(1) Client: in Spin/init.client.lua RenderStepped, keep view.prevAngle per bar. If the local root is inside this arena (r <= BAR_HALF_LEN+2, |localY| <= 12) and the player is InRound or InSolo, alive, not anchored and not Stunned, run the swept Hit.check between prevAngle and the current angle using feet = localY - standHeight. Debounce 1 s, then Spin_Hit:FireServer(barModel.Name, workspace:GetServerTimeNow()) and play local juice.
(2) Server: create Net.event('Spin_Hit') at module load. In create(), connect it through ctx.trove. Accept only when running, ctx.isAlive(player), barName is a string <= 8 characters that names a bar of THIS session, t is a finite number, tt = clamp(t, now-0.6, now), the 1 s lastHit cooldown has passed, and |BarMath.armDistance(BarMath.angle(bar.state, tt), angle(server root))| <= 0.45 + 0.15*|velocity|. Then call knock().
(3) Server fallback for clients that never report: keep checkPlayer, but use lag = clamp(ping*0.5 + 0.12, 0.05, 0.35). Only knock if the player has been grounded (feet < 0.4) for the last 0.35 s, and defer by task.delay(0.3). Skip the knock if a Spin_Hit from that player arrived in the meantime or the player went airborne.
Also: set CLEAR_HEIGHT to 1.6, set client SWEEP_WINDOW to 0 (frames are already swept), and cap bar speed. Server-only alternative B (no remote): use lag = ping/2 + 0.1 and defer each hit by 0.12 s, forgiving it if any sample in that window shows feet >= 0.4.


---

**title**: Spin: standing on the hub top makes you immune to the bar

**severity**: major

**file**: src/server/Minigames/Spin/Arena.lua

**line**: 143

**rootCause**: The Hub is a collidable cylinder of radius 3 whose top is flush with the pillar tops (y=0). Hit.check returns false for any player with r < Hit.MIN_RADIUS = 3. The bar's Cap that sits on the hub is non-collidable. The gap from a pillar's inner edge (r 31.5) to the hub edge (r 3) is 28.5 studs. A jump covers about 20*0.53 = 10.6 studs and an air dash adds about 18 (Controller.lua air dash with AIR_DASH_RISE), which is borderline at about 28.6. With the Jump Boost or Dash Distance upgrades, or the LowGravity modifier, it is easily reachable.

**evidence**: Arena.lua:143 disc(map, center, "Hub", Vector3.zero, 26, HUB_RADIUS(3), HUB, {Material=DiamondPlate}), no CanCollide=false. Hit.lua:20 MIN_RADIUS = 3, Hit.lua:52-54 return false if r < MIN_RADIUS. Spin keys include Dash (init.lua:77). Verdict: plausible (exact reach depends on upgrades and modifiers).

**fix**: Set the Hub and HubRim/HubBand parts to CanCollide=false and CanQuery=false (purely decorative axle). Anyone who lands there falls into the lava. Also set Hit.MIN_RADIUS = 0 and measure the hit by perpendicular distance to the bar line (|r*sin(armDistance)| <= halfWidth) instead of angle/r, so the center is not a singular safe zone.


---

**title**: Laser Tracer: removing the hub geometry alone would create a safe spot: sweeps never hit r < 3

**severity**: major

**file**: src/client/Minigames/LaserTracer/Motion.lua

**line**: 171

**rootCause**: Sweep beams start at HUB_RADIUS 3.4, and Motion.probe only counts a point when along >= HUB_RADIUS-0.4. Today the collidable hub column (r 3.3) physically blocks that zone. Brief #15 asks to remove the center pillar. If a builder deletes only Arena.buildHub, the center becomes immune to every sweep. In general, the whole sweep pattern is anchored to the center, so the hub cannot be removed without replacing the motion model.

**evidence**: Motion.lua:26 HUB_RADIUS=3.4. Motion.lua:146 the segment starts at c*HUB_RADIUS. Motion.lua:171 inside = along >= HUB_RADIUS-0.4. Arena.lua:171-209 buildHub (Column and Dome collidable through part() defaults). Renderer.lua:129-137 and 354-357 hubRings.

**fix**: Replace the 'sweep' pattern with the line-based Motion v2 described in briefPlans #15, where every laser is a full chord with no hub radius, and delete buildHub, HUB_HEIGHT, Motion.HUB_RADIUS, Renderer.hubRings and Lasers.finalSpin/rekeySweeps/reverseSweeps together.


---

**title**: Laser Tracer: low and high lasers differ only by hue (red vs cyan); the brief requires all red

**severity**: major

**file**: src/client/Minigames/LaserTracer/Motion.lua

**line**: 35

**rootCause**: Kind is communicated almost entirely by color (Motion.COLORS low red, high cyan). Every visual uses it: beams (Fx.newBeam), telegraphs (Lasers.buildTelegraph), emitter and hub rings. Shape language is only a 3-stud height difference and the BillboardGui text 'JUMP!'/'SLIDE!'. Making high lasers red (brief #13) with no other change makes the two kinds indistinguishable from the usual third-person camera.

**evidence**: Motion.lua:35-38 COLORS. Fx.lua:76-84 (identical geometry for both kinds, only the color differs). Lasers.lua:32 LABELS, :96-117 text BillboardGui.

**fix**: Use the kind-specific geometry language in briefPlans #13: low is a hurdle (thick solid beam, fence pickets, solid floor strip, short pylons with an up arrow), high is a limbo bar (twin stacked beams with a hazard-stripe Beam between them, hanging tassels, a dashed hollow floor lane, tall posts with a down arrow). All of it in red.


---

**title**: Laser Tracer: lasers are predictable center sweeps that all share one speed and reverse together

**severity**: major

**file**: src/server/Minigames/LaserTracer/Director.lua

**line**: 284

**rootCause**: By design (Director header lines 6-17), every sweep rotates around the center at one common angular speed (rekeySweeps), and reversals flip all sweeps at once (reverseSweeps). Slides move at constant speed along straight headings. That reads as a rotating clock, not 'random' (brief #15).

**evidence**: Director.lua:37-40 sweepSpeed, :286-290 rekey, :315-325 reverse all. Lasers.lua:201-230.

**fix**: Rewrite Director and Motion as a knot-based random walk (briefPlans #15). It stays deterministic for clients because the server pre-bakes the random knots into the State string.


---

**title**: Bat cosmetics (7 items) and the BatPower upgrade become dead purchases once King of the Hill is deleted

**severity**: major

**file**: src/shared/Economy/Cosmetics.lua

**line**: 89

**rootCause**: Only KOTH reads Cos_BatColor (BatTool.parseColor) and Upg_BatPower (KOTH init.lua:79-85,269). The brief deletes KOTH (#10), so these purchases do nothing unless the bat moves to Spin (#22).

**evidence**: Cosmetics.lua:89-96 (BatPink...BatRainbow, 120-600 coins). Rules.lua:28,33 UPGRADE_ORDER includes BatPower ('Bonk harder'). Config.lua:53 BatPower prices 80-900.

**fix**: Port the bat to Spin with the same attributes (briefPlans #22c). Update the Cosmetics.lua:7,89 comments and the shop blurbs to say Spin, and have the Bomb Tag builder decide whether its bonk also reads Upg_BatPower and Cos_BatColor.


---

**title**: Laser Tracer: same stale-position problem for jumping low lasers; JUMP_CLEAR ignores avatar size

**severity**: minor

**file**: src/server/Minigames/LaserTracer/init.lua

**line**: 60

**rootCause**: Like Spin, the root height is a delayed server sample, and lagOf only adds 0.03 s on top of ping/2, so late jumps over a low beam can be zapped. The low rule is absolute: root >= floorY + 4.2 (Hit.lua:19,42) assumes a standing root at about 3. Scaled R15 avatars (HipHeight 1.6-2.6) need different jump heights. Spin already does this correctly with standHeight (Spin/init.lua:66-71).

**evidence**: init.lua:60-66 lagOf. init.lua:119-128 uses root.Position.Y directly. Hit.lua:19 JUMP_CLEAR = 4.2.

**fix**: Use feet = root.Y - floorY - standHeight(humanoid, root, character) and clear the low beam when feet >= 1.1. Move to the same client-report pattern as Spin: remote LaserTracer_Hit(laserName, serverTime), client-side detection with the local Movement State.sliding (src/client/Movement/State.lua) and feet height, server validation (laser live at t, |Motion dist| <= 4 studs from the server root), plus a deferred server fallback.


---

**title**: Spin: bar speed grows without limit

**severity**: minor

**file**: src/server/Minigames/Spin/init.lua

**line**: 57

**rootCause**: speedFor(I) = 1 + 0.75*(I-1) never caps. At I = 5 (about 140 s) it is 4 rad/s, which is 144 studs/s at the pillar ring. Pillar glow WARN_TIME 0.55 s then covers more than 2 rad, so every pillar glows all the time and the warning means nothing. Server sampling error grows with speed. Legacy capped maxW at 3.6 (GameServer.server.lua:26).

**evidence**: init.lua:57-59. Client WARN_TIME at Spin/init.client.lua:23.

**fix**: Use speedFor = math.min(1.25 + 0.6*(I-1), 3.4). Escalate through the second bar at I >= 1.8, reversals at I >= 2.5, the bat ramp and pillar collapse instead.


---

**title**: Spin client: whoosh/'bar incoming' warning never works in Solo

**severity**: minor

**file**: src/client/Minigames/Spin/init.client.lua

**line**: 164

**rootCause**: localAngle() returns nil unless the Player attribute InRound is true. Solo runs set InSolo, not InRound (P10 contract gap #4).

**evidence**: init.client.lua:163-166.

**fix**: Accept InRound == true or InSolo == true. The existing radius and height checks (lines 172-176) already make sure the player is at this arena.


---

**title**: Spin: what you see does not match the hitbox (glass Shell, CLEAR_HEIGHT below the bar top)

**severity**: minor

**file**: src/server/Minigames/Spin/Arena.lua

**line**: 280

**rootCause**: The bar core spans 0.8 to 2.2 above the tops (BAR_HEIGHT 1.5, BAR_THICK 1.4). The glass Shell is thick+0.7, which makes the visible bar 0.45 to 2.55 and the tips reach 2.9. A hit only needs feet < 1.4. Players see their feet pass through a bar that looks thick and do not know the real rule. The washed-out Glass shell also lowers contrast.

**evidence**: Arena.lua:280-287 Shell, :288-298 Tip size 2.8. BarMath.lua:24-25. Hit.lua:16.

**fix**: Remove the Shell. Draw the bar as a 1.4-thick red/white candy-striped core with 1.8-diameter tips. Use CLEAR_HEIGHT 1.6 (client authoritative, slightly lenient).


---

**title**: Spin: players are placed on ADJACENT pillars (bunched), bad with a bat

**severity**: minor

**file**: src/server/Minigames/Spin/Arena.lua

**line**: 354

**rootCause**: Arena builds 12 spawns, one per pillar, and Core's Context:_place assigns them round-robin from a random offset. With n < 12 players they end up on n consecutive pillars. Legacy spread them evenly (GameServer.server.lua:407-410).

**evidence**: Arena.lua:354-369. Context.lua _place: (i-1+offset) % n + 1.

**fix**: In create(ctx), call Arena.build(center, #ctx.allPlayers()) and create Spawns only on pillars floor((k-1)*12/n)+1 for k = 1..n. Core's round-robin then spreads players evenly.


---

**title**: Laser Tracer: a combo's delayed partner draws its telegraph on top of the first laser's

**severity**: minor

**file**: src/server/Minigames/LaserTracer/Lasers.lua

**line**: 137

**rootCause**: buildTelegraph always previews slides at b = -PREVIEW_OFFSET, whatever the laser's start offset. The combo partner (Director.addSlide with delay COMBO_GAP, start = -ENTRY - speed*delay) therefore gets the exact same preview chord and arrows as the first laser, and the JUMP!/SLIDE! tags overlap. 'cross' and 'comboCross' waves (Director.lua:268-276) pick independent kinds, so a low and a high laser can sweep the same diagonal points at the same instant, which is a double threat.

**evidence**: Lasers.lua:136-139 preview.b = -LaserSet.PREVIEW_OFFSET. Director.lua:207-222,264-276.

**fix**: Moot after the Director v2 rewrite. Its fairness checker rejects low/high crossings at the same grid point within 0.6 s, and pair telegraphs are drawn offset by the real spacing.


## briefPlans


---

**briefItem**: #22a Spin: remove the small piece of wall at the bottom of the pillars you can stand on

**currentState**: The collidable 'Foot' disc (Arena.lua:111-113, r 4.6 vs Body r 3.6, top at local y -24) sits under non-collidable lava (top -23.5). KillY is center.Y-24, so a player standing on the Foot has root about -21 and is never eliminated. Hit LOW_LIMIT -5.5 makes them bar-immune too. SpinArenaData.lua is NOT used at runtime (only cited in a comment), so the ledge comes only from Arena.lua.

**plan**: 1) Arena.lua: delete lines 111-113 (Foot). Keep Body r 3.6 from y -1 to -27. Any new decorative strata or bands on the body must be CanCollide=false, CanQuery=false and r <= BODY_RADIUS+0.15.
2) Arena.KILL_DEPTH: change 24 to 21 (root < center.Y-21 means feet about 0.5 into the lava).
3) Hub, HubRim, HubBand: CanCollide=false.
4) Add Arena.assertNoLedges(map), called at the end of Arena.build. It errors if any BasePart with CanCollide=true is not named 'Top' or 'Body'.
5) Client: lava splash FX (orange neon burst plus 'blorp' sound) when a character's root crosses center.Y + LAVA_TOP + 3, so death reads clearly.
6) Critic test: teleport onto pillarTop + (4.3, -21, 0) and expect the Spectating attribute within 0.5 s. Raycast check around each pillar.

**risks**: Raising KillY means a player falling from a large knockback near the edge is eliminated slightly sooner. That is fine: nobody can recover from below the tops anyway (vertical pillars).


---

**briefItem**: #22b Spin: sometimes when I jump the bar still hits me

**currentState**: Server-authoritative Hit.check on a stale server copy of a client-owned root (lag compensation only ping/2). Late on-screen-successful jumps (within about 0.12-0.19 s of the bar) are punished. CLEAR_HEIGHT 1.4. Speed is unbounded.

**plan**: Recommended A (legacy-proven, no frozen-contract change):
- Move BarMath.lua and Hit.lua to a shared location (see contractChanges), or keep the clientModule() require.
- Client, Spin/init.client.lua: add view.prevAngle (BarView). In RenderStepped, after computing angle, call detectHit(view, prevAngle, angle, velocity, now) when all of these hold:
  - (localPlayer InRound or InSolo)
  - the character root is in this arena (r in [RING_RADIUS-10, BAR_HALF_LEN+2], |localY| <= 12)
  - humanoid.Health > 0, not root.Anchored
  - character:GetAttribute('Stunned') ~= true
  - the bar is not rising
  - os.clock()-lastLocalHit > 1.0
- feet = localY - (R15: HipHeight + root.Size.Y/2; R6: root.Size.Y/2 + 2*scale). Swept substeps of 0.07 rad. Hit.check(a, myAngle, feet, 0, r, 1.8*scale) with CLEAR_HEIGHT 1.6.
- On a hit: Spin_Hit:FireServer(model.Name, workspace:GetServerTimeNow()), local camera shake (0.25 s, 0.6 studs) and the hit sound.
- Server, init.lua: top-level local hitRemote = Net.event('Spin_Hit'). In create(): ctx.trove:connect(hitRemote.OnServerEvent, function(player, barName, t)). Validation:
  - running, ctx.isAlive(player)
  - type(barName) == 'string' and #barName <= 8
  - bar = the bar in this session's bars whose model.Name == barName
  - t finite; tt = math.clamp(t, now-0.6, now)
  - now - (lastHit[player] or -inf) >= 1
  - server root radius in [24, 46]
  - |BarMath.armDistance(BarMath.angle(bar.state, tt), BarMath.positionAngle(localPos))| <= 0.45 + 0.15*|BarMath.velocity(bar.state, tt)|
  Then lastHit[player] = now and knock(player, playerAngle, BarMath.velocity(bar.state, tt)).
- Server fallback (anti 'never report'), in checkPlayer:
  - lag = clamp(ping*0.5 + 0.12, 0.05, 0.35)
  - track lastAir[player] = now whenever heightAboveTop >= 0.4
  - candidate hit only if now - lastAir[player] >= 0.35
  - pending[player] = now; task.delay(0.3, ...) then knock only if no Spin_Hit was accepted from that player after pending and lastAir is still older than pending
- Speed: speedFor = math.min(1.25 + 0.6*(I-1), 3.4).
- Remove the glass Shell (Arena.lua:280-287).
- Test: Debug_IntensityOverride = 3. A client harness presses Jump when BarMath.timeUntil(angle, vel, myAngle) <= 0.08 s; 30 passes must give 0 hits. Standing still must always be hit within one revolution.
- Optional, better feel: contract addition Knockback.predict(direction, power, stun) on the client plus a ctx.knockback 'predicted' flag (server sets Stunned without FireClient), so the launch happens on the same frame as the visual hit. Without it the launch comes about 1 RTT (60-150 ms) after the hit.

**risks**: Client-reported hits let an exploiter skip hits. They can already ignore Core_Knockback today, so nothing is lost, and the deferred fallback still catches players who never jump. RemoteEvent ordering: use Net.event (reliable). The fallback must use the same 1 s cooldown so a valid report and the fallback never double-knock.


---

**briefItem**: #22c Spin: ADD A BAT (port from KingOfTheHill, which will be deleted)

**currentState**: The bat only exists in KOTH: server Bat.lua (cone math), BatTool.lua (Tool builder, Cos_BatColor, swing FX, bonkFx), init.lua:246-396 (giveBat/trySwing/resolveHits, remotes KingOfTheHill_Swing/_Fx). Client KingOfTheHill/Input.lua (touch SWING button, hidden backpack, Tool.Activated -> remote), Hud.lua (cooldown chip, BONK pops), Ui.lua, init.client.lua:25-80 (scans for a Tool with attribute KOTH_Bat every 0.15 s). Spin has no bat; keys = {Jump, Dash}.

**plan**: SERVER (owned by Spin):
1) Copy KingOfTheHill/Bat.lua to Spin/Bat.lua and retune:
  - RANGE 8.5, HALF_ANGLE rad(65)
  - MAX_HEIGHT_DIFF 3.0 (a jumping target dodges the bonk; same skill as the bar)
  - COOLDOWN 1.3, BASE_POWER 62, RAMP 0.5, ROUND_SECONDS 120
  - New Bat.direction(attackerCF, targetPos, center): flatAway*0.65 + outwardFromArenaCenter*0.35, plus 0.28 up, then .Unit, so bonks push toward the lava and not into the hub.
2) Copy BatTool.lua to Spin/BatTool.lua: TAG_ATTRIBUTE = 'Spin_Bat', ObjectValue 'Spin_Map'. Keep parseColor/Cos_BatColor and bonkFx; swap rbxasset sounds for the global hit sound when it exists (brief #25).
3) Spin/init.lua:
  - Module-level Net.event('Spin_Swing') and Net.event('Spin_Fx').
  - Port giveBat/equip/removeBats/trySwing/resolveHits from KOTH init.lua:246-396 into create() closure state: bats, lastSwing, lastBonk[target] = {attacker, t}.
  - Drop crown, leader and score logic. HIT_DELAY 0.12 (a visible wind-up gives counterplay), BONK_STUN 0.5.
  - Hand out bats in session.start ONLY when #ctx.allPlayers() >= 2 (no bat in Solo).
  - removeBats in session.stop. Keep the CharacterAdded re-give and the Heartbeat retry.
  - KO credit: each Heartbeat, for every player with lastBonk within 3 s who is no longer ctx.isAlive, call ctx.feed(('%s bonked %s into the lava!'):format(a.DisplayName, t.DisplayName)) and award coins through the bonus hook (contractChanges).
  - definition.keys = {'Jump','Swing','Dash'}; rules = 'Jump the bar! Bonk others off their pillars!'.
CLIENT (owned by Spin):
4) Copy KingOfTheHill/Input.lua, Hud.lua and Ui.lua to src/client/Minigames/Spin/BatInput.lua, BatHud.lua and Ui.lua:
  - ACTION 'Spin_Swing', remotes 'Spin_Swing'/'Spin_Fx', attribute 'Spin_Bat'.
  - BatHud drops the zone/king pill and keeps only the 'BONK!' pop. Show the cooldown ONLY as a radial shade on the touch button: no separate bar (consistent with brief #11).
  - Also bind Enum.KeyCode.F and gamepad ButtonR2. PC left click already triggers Tool.Activated.
5) In Spin/init.client.lua add the bat scanner loop from KOTH init.client.lua:25-80 (isBat checks the 'Spin_Bat' attribute).
6) Swing animation: on the replicated tool attribute 'LastSwing', play a procedural swing on the holder's right shoulder Motor6D on every client (R15 RightShoulder / R6 'Right Shoulder'), reusing Movement/Pose.lua's Transform approach: wind-up yaw -70 deg over 0.08 s, strike +110 deg over 0.10 s, recover over 0.12 s. This replaces the weak stock 'toolanim Slash'.
7) After the port, delete src/server/Minigames/KingOfTheHill and src/client/Minigames/KingOfTheHill as one change (the Bomb Tag piece), and update the Economy text (Cosmetics.lua:7,89 comments; BatPower blurb).

**risks**: Bat plus bar can feel like whoever swings first wins on 9-stud pillars. The 0.12 s wind-up, MAX_HEIGHT_DIFF 3 (jump dodges) and moderate power keep counterplay. Playtest power 55-70. Tool equip can fight Movement's slide/dash (AutoRotate). KOTH coexisted with Movement, so the same code should be safe.


---

**briefItem**: #13 Laser Tracer: all lasers red, but low vs high instantly distinguishable

**currentState**: Kind = color (low red 255,30,30; high cyan 0,215,255; Motion.lua:35-38). Beams are geometrically identical (Fx.newBeam). Telegraph BillboardGui text 'JUMP!'/'SLIDE!'. Heights 1.6 / 4.6.

**plan**: Shared constants (Motion v2):
- HEIGHT = {low = 1.4, high = 4.8}
- COLORS: RED = (255,35,35), HOT = (255,190,180) core tint, both kinds
- Hit thresholds relative to feet: low clears at feet >= 1.1; high hits unless sliding
LOW = 'HURDLE' (Fx.newBeam(kind='low')):
- Core: neon cylinder 0.65 thick, glow cylinder 1.5 thick at Transparency 0.55.
- Solid floor strip directly under it: Neon RED, 2.2 wide, 0.05 tall, Transparency 0.25.
- Fence pickets: a pool of 28 neon parts (0.22 x 1.4 x 0.22, RED, Transparency 0.15), one every 3 studs along the chord from the floor up to the beam. Unused pickets are hidden.
- End posts: squat 1.6 x 1.0 x 1.6 blocks on the floor with a yellow up-arrow SurfaceGui icon.
- Particles rise upward.
HIGH = 'LIMBO BAR' (Fx.newBeam(kind='high')):
- Two thin neon cylinders (0.35 thick) at 4.5 and 5.1.
- Between them, a Roblox Beam instance (Width 0.6, FaceCamera false, LightEmission 1) with a red/white diagonal hazard-stripe texture (generated asset; fallback alternating 2-stud red/white segments), TextureSpeed 1.
- Tassels: a pool of 30 thin red strips (0.15 x 1.2 x 0.4) every 2.5 studs, hanging from 4.5 down to 3.3, swaying +/-8 deg.
- Floor: NO glow. A hollow dashed lane: two parallel dashed red lines 1.8 apart (dash pool, 1.5-stud dashes) on a dark Ink band (Transparency 0.65).
- End posts: tall 0.8 x 5.4 x 0.8 posts with red/white stripes and a down-arrow icon on top.
- Sparks drip downward.
This gives three cues: top-down, solid strip vs hollow dashed lane; side view, fence vs hanging fringe; silhouette, short vs tall end posts.
TELEGRAPH (Lasers.buildTelegraph rewrite):
- Only the kind's floor marking (solid or dashed), pulsing, plus the end posts rising out of the floor over 0.4 s.
- Small arrow icons (up / down) every 8 studs at beam height: icons, no words.
- Remove LABELS and the text BillboardGui.
HUD PROMPT (client):
- If a live laser will cross the local player within 0.8 s (Motion lookahead), show a big centered-bottom icon: an up arrow with [Space]/[A] glyph, or a down arrow with [C]/[B] glyph (or the mobile Slide button glyph), with a pop-in tween.
- Audio: low = high-pitched rising blip, high = low-pitched falling 'whum'.
The arena gets no other red or pink anywhere (the rim becomes navy/yellow hazard), so red always means laser.

**risks**: Part count: about 60 parts per high laser x 7 live = 420 client-local anchored parts. Pool them per laser (create once at addLaser, never per frame). Updating CFrames every frame is fine. Use BulkMoveTo (workspace:BulkMoveTo with Enum.BulkMoveMode.FireCFrameChanged off) for pickets and tassels.


---

**briefItem**: #15 Laser Tracer: no pillar in the middle + lasers move RANDOMLY

**currentState**: A central collidable Hub (Arena.lua:171-209) fires 'sweep' rays rotating around the center at one shared speed with synchronized reversals. Slides are constant-speed chords. Everything is deterministic from State + server time, and the server requires the client Motion module through MotionRef.

**plan**: REMOVE:
- Arena.buildHub and HUB_HEIGHT, and the call at Arena.lua:279.
- Motion.HUB_RADIUS and the 'sweep' pattern.
- Director spawnSweep/sweepSpeed/sweepTarget/reverse.
- Lasers.finalSpin/rekeySweeps/reverseSweeps.
- Renderer hubRings (129-137, 354-357).
- Map attribute LaserSpeed; publish 'Intensity' and 'LiveLasers' instead.
- Add a flush non-collide center emblem (decal/Texture) as a landmark.
MOTION v2 (shared module; every laser is a LINE {p : p.n(a) = b}, n = (cos a, sin a), clipped to the rim circle R = 42.6):
- State string: 'v2|<pattern>|<kind>|<tWarn>|<tOn>|<tOff>|<px>|<pz>|<ease>|t1,a1,b1;t2,a2,b2;...' with at most 12 knots, absolute server times.
- pattern 'line': a and b both come from the knots. pattern 'pivot': a comes from the knots and b = px*cos a + pz*sin a (rotation around a NON-center pivot).
- ease 's': per segment u = (t-ti)/(ti+1-ti), w = u^3(u(6u-15)+10) (smootherstep, stop-and-go 'darting'). ease 'c': Catmull-Rom through the knots (flowing).
- a is interpolated along the shortest arc.
- API:
  - Motion.eval(st, t) -> a, b
  - Motion.segment(st, t) -> chord (center n*b, direction (-sin a, cos a), half = sqrt(R^2 - b^2))
  - Motion.probe(st, t, px, pz) -> dist = px*cos a + pz*sin a - b; inside = |b| < R and |along| <= half + 0.6; motion dir = sign(d dist/dt) * n via eval(t+0.03)
  - Motion.crossed(st, ta, tb, px, pz): sign change or |d| <= HIT_HALF_WIDTH 1.15; subdivide when |da| > 0.08 or |db| > 1
  - Motion.velocityAt(st, t) and Motion.nextKnot(st, t) for client chevrons and reversal flicker
DIRECTOR v2 (server owns all randomness; Random.new()):
- Patterns:
  - SLIDE: random heading a in [0, 2pi), b walks from -43.4 to +43.4 in knots. Segment db in [6, 18]; 20% chance of a back-step of -4..-8 when I >= 1.5; pauses (db = 0, 0.3-0.6 s) with probability 0.25 at I < 2, 0.15 above.
  - PIVOT (I >= 1.3): P random with |P| in [12, 30] (never the center) or a rim 'wiper' with |P| = 41. Angle knots: da = +/-[25, 70] deg, 70% chance to keep direction. Life 7-12 s.
  - DRIFT (I >= 2.0): a and b both random-walk; |b| <= 30, da +/-[10, 45] deg, db +/-[5, 15].
  - PAIR (I >= 1.8): low plus high, same knots, b offset 4.5 studs (jump then slide).
  - WIPERS (I >= 2.6): two rim pivots at opposite points, same kind, mirrored knots.
- Speed caps (enforced while generating knots, using the smootherstep peak factor 1.875):
  - peak linear speed of any in-platform point on slide/drift <= vmax(I) = clamp(10 + 3.5(I-1), 10, 24) studs/s
  - pivot far-tip speed <= clamp(22 + 5(I-1), 22, 40)
- Segment durations: 1.2-2.4 s at I = 1, down to 0.7-1.4 s at I >= 4.
- Live target: 2 (I<1.4), 3 (<2.0), 4 (<2.6), 5 (<3.3), 6 (<4.2), 7. MAX incl. telegraphed 9. Spawn gap 1.6 s at I = 1, down to 0.9 s.
- WARN = clamp(1.3 - 0.12(I-1), 0.85, 1.3). Opening sequence: low slide at 0.6 s, high slide at 2.4 s.
- Rolling horizon: each laser always has >= 3 s of future knots. Director.extend appends knots and republishes State at most once per second; knots older than t - 0.5 are dropped. A reversal is always preceded by a >= 0.35 s pause knot, so the client flickers the beam for 0.3 s before it moves again.
- FAIRNESS (reject the candidate and retry up to 10 times, else skip this spawn tick):
  (1) at tOn the chord is >= 4 studs from every alive root
  (2) 37-point grid (center + rings r = 10/20/32 with 6/12/18 points), times tOn..tOn+4 s in 0.1 s steps: no grid point gets a low crossing and a high crossing within 0.6 s (except the deliberate PAIR), and no point gets >= 3 crossings within 1.2 s
  (3) at every sampled time >= 25% of grid points have no crossing within +/-0.8 s (always a calm zone)
  Cache existing lasers' crossing times per grid point to keep this around 1-2 ms.
- Events: 'MORE LASERS!' when the live target rises. 'LASER STORM!' at I >= 3 every 30 s: 5 s at vmax*1.2 with +2 quick slides from random sides, then 4 s with no spawns.
CLIENT RENDER:
- Renderer evaluates Motion v2 each RenderStepped.
- Floor chevrons (3 flat arrows) on the side the beam is moving toward, opacity proportional to speed. Before a reversal knot they flip and flash.
- End posts slide along the rim with the chord ends; the 12 rim pylons light up as an endpoint passes (existing lightTowers logic, angleGap < 0.42).
HIT:
- Hit.check(kind, feetAboveFloor, sliding, inside) with feet = root.Y - floorY - standHeight.
- Client-report pattern as in Spin (remote 'LaserTracer_Hit'(laserModelName, serverTime); server validates |Motion dist at clamp(t, now-0.6, now)| <= 4 studs and the laser was live) plus a deferred server fallback.

**risks**: Knot interpolation has to be bit-identical on server and client: use one shared module only, no per-side copies. A State string with 12 knots is about 300 chars: fine for attributes. Fairness sampling cost must stay bounded (cap 10 candidates per spawn tick, spawns at most about 1 per second). Players at the exact center are no longer protected by anything: intended.


---

**briefItem**: #4 / #2 / #7 / #9 Maps: distinct, beautiful, simple bright Roblox style, not blending (Laser Tracer + Spin)

**currentState**: Laser Tracer: pastel Theme.MapPalette ring tiles on a purple grout disc, pink rim, purple/cyan lasers, generic towers. Spin: slate-purple pillars, rainbow neon bands, white candy tops, purple hub, a lava basin 23 studs down with a glass-shelled bar. Both sit in the same tropical sea backdrop under Lighting with Atmosphere Haze 0.6, Density 0.24, Bloom 0.45 / Threshold 1.5 and Brightness 3 (LightingSetup.lua:28-61). Pastels plus haze give the washed-out look in current-game-koth.jpg. The references (ref1/ref2/ref4) use saturated, opaque, two-tone checker/brick surfaces, dark outlines at edges, and strong figure/ground (green tops, brown/orange sides).

**plan**: RULES for both maps: walkable surfaces are light and saturated. Hazard colors are reserved (Laser Tracer: red = laser only; Spin: red/white = bar only). Every platform edge gets a 0.3-stud dark trim (Ink 30,25,50 or a darker shade of the surface) for readability. No Glass. Neon only on hazards and small accents. No Theme.MapPalette pastels.
LASER TRACER 'Laser Lab Deck':
- Floor: collidable Base disc r 42, SmoothPlastic, with a 6-stud square checker: A (232,240,250), B (178,210,236). Use a Texture with a generated checker asset (StudsPerTileU/V 12) or, until the asset exists, a grid of 6x6 tiles (ghost parts, about 190) clipped to the circle.
- Danger rim r 39.5-42: 24 flush non-collide segments alternating hazard yellow (255,196,30) and Ink (34,30,52). Outer dark edge trim (40,48,80).
- Underside: stepped metal discs (82,94,130) and (52,60,92) with Neon cyan (60,220,255) vent rings.
- 12 rim pylons at r 47, alternating short 'hurdle' (6 tall) and tall 'limbo' (9 tall): body (240,242,248), cap (40,48,80), red lens.
- Center: flush emblem decal.
- Backdrop (non-collide, r 110-170): 4 floating white/navy 'server tower' blocks with blinking red beacons, plus a huge thin neon-cyan holo ring at Transparency 0.6 behind the arena.
SPIN 'Volcano Pillars':
- Pillar top r 4.5: grass (106,200,66) with a darker rim ring (80,170,50) of 0.5 stud.
- Body: dirt strata in two tones (176,112,62)/(150,92,50), 3-stud bands as non-collide skins on the collidable core, plus a stone base band (110,105,115).
- Each pillar gets one small colored flag or number tile for 'my pillar' identity.
- Lava: opaque SmoothPlastic (255,115,25) plus 12 pooled client-side Neon (255,190,60) bubble discs that grow and pop, and the embers.
- Crater: voxel ring of basalt blocks (58,50,62)/(78,66,80) at r 60-75, stepped tops from -22 to -6, with Neon (255,140,30) lava-fall strips. ALL non-collide.
- Hub: dark iron (52,48,64) DiamondPlate with a yellow/black hazard ring, CanCollide=false.
- Bar: candy stripes alternating 3-stud red (240,40,40) Neon and white (250,250,250) SmoothPlastic segments, yellow (255,215,60) tips 1.8 in diameter, red trail. No shell.
LIGHTING per map (see contractChanges, LightingProfiles):
- LaserLab: ClockTime 14, Saturation 0.15, Contrast 0.15, Haze 0.1, Density 0.15, Bloom Threshold 2.2 (only lasers bloom).
- Volcano: ClockTime 16.5, Tint (255,238,220), Atmosphere Color (255,214,180), Decay (200,110,80), Haze 0.2.
- The global base (Core) should drop to Haze 0.15, Density 0.18, Bloom Intensity 0.25, Threshold 2.2, which fixes 'everything blends' across all maps.
ASSETS to generate (brief #5): checker floor tile, hazard stripe, grass top tile, dirt-strata side tile, cartoon lava tile, laser hazard-stripe beam texture, up/down arrow icons.

**risks**: Texture asset IDs need uploading (the owner's account). Ship a part-based fallback first so the map works without assets. Watch the client part count for Spin's crater (keep it under about 400 parts and merge where possible).


---

**briefItem**: #6 / #8 / #12 / #19 Make these two modes dynamic, competitive and addictive

**currentState**: Spin: one bar slowly spinning up (1 rad/s at start), second bar only after about 42 s, reversals after about 70 s, no player-vs-player. Laser Tracer: survive only, no rewards for skill, no reason to move around.

**plan**: SPIN:
(1) Bat plus KO credit feed and coins (+3 per KO via the bonus hook).
(2) Faster opening: speed 1.25 rad/s, Bar2 at I >= 1.8 (about 28 s), reversals at I >= 2.5, cap 3.4 rad/s.
(3) PILLAR COLLAPSE from I >= 2.0: every 15 s one random EMPTY pillar shakes and flashes red for 2 s, then tweens down 30 studs over 1.2 s (server TweenService on the pillar Model; collidable Top moves with it). Always keep >= alive+2 pillars.
(4) SHIELD ORB every 20 s on a random empty pillar (gold Neon ball at +3). First touch (server distance check < 4 studs) gives one ignored bar or bat hit, shown as a bubble. A race worth jumping between pillars for.
(5) DODGE COMBO: every bar pass under your airborne feet (client-detected, reported in batches) +1. Combo pop at bottom center (x5, x10...) with rising pitch. +1 coin per 10.
LASER TRACER:
(1) COIN BITS: up to 4 gold coins spawned on the floor in or near laser lanes (server-owned, CanCollide=false, touch-radius check 3 studs each Heartbeat). +1 coin and +1 score each; respawn 2 s later elsewhere. Risk/reward makes kids move.
(2) DODGE COMBO (each laser correctly cleared within 0.25 s of it crossing you: 'PERFECT!').
(3) LASER STORM events (see #15).
(4) 'FINAL 3!' banner and faster music when 3 remain.
BOTH: an end-of-round personal stat line ('12 dodges, 2 KOs, best combo 9') for the results screen through a session attribute (e.g. player attribute 'RoundStats' JSON). The UI piece renders it.

**risks**: Rewards need an Economy entry point that does not couple minigames to Economy internals (see contractChanges, Signals.Bonus). Keep coin totals small so the economy is not inflated.


---

**briefItem**: #18 Fix all bugs (subsystem-specific list)

**currentState**: See bugs[]: Foot ledge, server-side jump hits, hub immunity (Spin), hub removal trap, color-only kinds, combo telegraph overlap, absolute JUMP_CLEAR (Laser), unbounded speed, Solo warnings, adjacent spawns, glass shell mismatch.

**plan**: Apply each bug's fix. Additional cleanups:
- Spin/init.client.lua:164: accept InSolo.
- Arena.build(center, playerCount): evenly spread spawns floor((k-1)*12/n)+1.
- Laser Tracer knockback: start at 80 (instead of 95), +12 per intensity, max 150, so one early mistake near the middle is survivable.
- Both modes: every hit plays the global HIT sound (brief #25) and a 0.15 s camera shake for the victim.
Critic verification:
- Debug_ForceMinigame = 'Spin' / 'LaserTracer'.
- Ledge raycast test.
- Scripted late-jump test (30/30 clear).
- Hub/center-standing test (must be hit or fall).
- Solo run whoosh test.
- 2-player bat KO feed.

**risks**: Do not change Core files from the minigame pieces. Anything Core-side (lighting base, Knockback.predict, revive) goes through the lead's contract changes.


---

**briefItem**: #3 Controls (as they apply to Spin and Laser Tracer)

**currentState**: Spin has jump plus dash only. KOTH's bat input is click/tap only. Laser Tracer depends on the Movement slide (C/Ctrl) and jump, with no in-world input prompt.

**plan**: 1) Bat: left click, F key, gamepad R2, and a touch SWING button left of Jump (KOTH layout logic, Input.lua:107-126). Cooldown is shown as a radial shade on the button only. Client prediction: play the swing animation and whoosh immediately on press; the server confirms the hit through Spin_Fx.
2) Laser Tracer: the HUD action prompt (up/down icon with key glyph) 0.8 s before a crossing.
3) Spin: jump buffering is Movement's job (ask P2: buffer a Jump press for 0.15 s before landing, coyote time 0.1 s). With client-authoritative hits, the timing the player sees is the timing that counts.
4) Mobile: Spin shows only Jump, Dash and Swing. Hide the Slide button while a Spin bat is equipped (Movement can read a player attribute 'HideSlide' = true; minor Movement change).

**risks**: Overlapping mobile buttons: reuse the KOTH layout rule (SWING directly left of Jump, Dash above Jump, Slide above-left).


---

**briefItem**: #28 Revive for Robux (minigame side)

**currentState**: Survival elimination is final. No API exists to put a player back into a running session.

**plan**: Needs a contract addition (see contractChanges): optional session.reviveSpot(player): CFrame?.
- Spin: an occupied-free pillar whose BarMath.timeUntil(angle, vel, pillarAngle) > 1.2 s for every bar, preferring the one farthest from other players. Returns the CFrame of that pillar's top + (0, 0.5, 0).
- Laser Tracer: a grid point (the 37-point fairness grid) with no crossing within the next 1.5 s and >= 6 studs from any live chord.
- Both: Core grants 1.5 s of spawn protection (character attribute 'ReviveShield') which Hit.check honors (skip hits while set).

**risks**: Core owns elimination state (Context._alive). The revive must restore _alive and the counts in Core, not in the minigame.

**contractChanges**: 1) A shared code location for server+client minigame math. P4 and P8 both reported this gap: MotionRef.lua and Spin Arena.clientModule() require ModuleScripts out of StarterPlayerScripts. Add src/shared/Minigames/<Id>/ (ReplicatedStorage.Shared.Minigames.<Id>), owned by that minigame's piece:
- move LaserTracer/Motion.lua and Hit.lua there
- move Spin/BarMath.lua and Spin/Hit.lua there
- delete src/server/Minigames/LaserTracer/MotionRef.lua and Spin/Arena.lua:17-25
Document it in ARCHITECTURE.md.

2) Knockback client prediction (optional, recommended for hit feel), in src/shared/Knockback.lua (Core):
- client API Knockback.predict(direction, power, stun): the same velocity and tumble as the Core_Knockback handler; factor the handler body into it
- server: Knockback.apply(player, dir, power, stun, opts?) with opts.predicted = true, which sets Stunned/StunnedUntil but skips FireClient
- ctx.knockback gets the same optional 5th argument
Without this, client-detected hits go through ctx.knockback with about 1 RTT delay (acceptable fallback).

3) New remotes, module-level Net.event, documented in ARCHITECTURE:
- Spin_Hit (client to server: barName: string, serverTime: number)
- Spin_Swing (no args)
- Spin_Fx (server to attacker: 'hit', count)
- LaserTracer_Hit (client to server: laserModelName: string, serverTime: number)
- Remove KingOfTheHill_Swing/_Fx together with KOTH.

4) A per-map lighting profile:
- map attribute 'LightingProfile' (string) on session.map
- new src/shared/LightingProfiles.lua (Core-owned) holds a table of profiles (ClockTime, ColorCorrection, Atmosphere, Bloom)
- a Core client module applies the profile, tweened over 0.6 s, while the local camera is within 350 studs of a map carrying the attribute, and restores the base otherwise
- also lower the global base in LightingSetup.lua: Atmosphere Haze 0.6 to 0.15, Density 0.24 to 0.18, Bloom Intensity 0.45 to 0.25, Threshold 1.5 to 2.2

5) Theme additions (frozen file, lead edits):
- Theme.Colors.LaserRed (255,35,35) and LaserHot (255,190,180)
- Theme.Colors.Hazard (255,196,30)
- Theme.Maps = { LaserTracer = {floorA, floorB, rim, metal}, Spin = {grass, grassDark, dirt, dirtDark, lava, lavaHot, basalt} }
- change Theme.MinigameColors.LaserTracer to LaserRed (roulette card matches the lasers)
- stop using the pastel Theme.MapPalette on maps

6) A reward hook: Signals.Bonus(player, reason: string, coins: number), with Economy listening, so minigames can pay for KOs, coins and dodge combos without requiring Economy directly. Economy.addCoins already exists (src/server/Economy/init.lua:95).

7) Revive (brief #28):
- optional session.reviveSpot(player): CFrame? in Contracts/Minigame.lua
- Core-side ctx:_revive(player), which restores _alive and the counts and teleports to reviveSpot
- character attribute 'ReviveShield' (server time until which hazards must not hit)

8) An optional Movement player attribute 'HideSlide' (bool), so modes without slide can hide the mobile Slide button.

9) Delete KOTH only after the Spin bat port lands. Economy Cosmetics.lua:7,89 and the Rules blurbs must point to Spin (and Bomb Tag, if it uses a bonk).

**qualityNotes**: - Server-side hit detection on client-owned characters is the root of most 'unfair hit' feelings in both modes. Standardize one pattern: client detects, server validates, deferred server fallback. Put it in a small shared helper, e.g. src/shared/Util/HitReport.lua, with the cooldown, clamp(t, now-0.6, now) and the rate limit, so the Bomb Tag and Dodgeball pieces can reuse it.
- Laser Tracer Renderer.update builds new closures and tables every frame (the lightTowers closure, Motion.emitterAngles, rimAngles return fresh tables, towerGlow/towerColor/hubFlash maps). Hoist them and reuse arrays to avoid GC churn on mobile.
- Fx.newBeam gives every laser 2 PointLights and 3 ParticleEmitters (9 lasers = 18 lights). Use at most 1 light per beam (mid-point) on mobile, or none and rely on the neon floor strip.
- Every sound is a bundled rbxasset placeholder (volume_slider.ogg as a beep, action_swim.mp3 as a power-on). They sound cheap. Replace them with the generated or curated SFX set (brief #25) through one shared Sounds module with a master SFX volume, to respect the brief #23 settings.
- Lasers.label uses an AlwaysOnTop BillboardGui with English text. Per the owner's 'no text, shapes' direction (#21), use icon-only tags.
- Spin client addBar yields (WaitForChild) inside a ChildAdded handler. Use task.spawn like the initial loop.
- Spin's server bar models never move on the server (only clients PivotTo). That is fine because hits are math-based, but any future server raycast or collision against bars would be wrong. Document it.
- KOTH remotes are created at require time (init.lua:56-57). The Spin port should do the same, so clients never wait 30 s in Net.event (the P6 gap).
- Bat in Solo: skip it (no targets). Bats must be removed in session.stop and on PlayerRemoving (as in KOTH).
- Brief #16 (pushed into water, teleported back instead of dying) is NOT caused by these two modes. Likely sources: (a) KOTH is kind 'score', and Context._onFall (src/server/Core/Context.lua:295-306) respawns fallers with the toast 'Oops! Back in 2...'; (b) Places.rescueLoop (Places.lua:90-109) routes non-alive fallers back to the lobby; (c) Debug_NoEliminate left on (Context.lua:307-308, 318-321). Both survival modes eliminate correctly, except for the Spin Foot ledge above.
- After the Foot removal, Spin lava and crater decor must stay non-collidable. Enforce it with the Arena.assertNoLedges invariant so future visual passes cannot reintroduce ledges.
- Laser Tracer Hit.check has an odd heuristic, 'if laserY < floorY then laserY += floorY' (Hit.lua:35-37). It goes away with the feet-relative v2 rule.
