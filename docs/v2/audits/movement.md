# Audit: movement

**subsystem**: Movement / controls (client Movement/*, server Movement, shared Movement/Stats+Assets, Knockback client side, movement-related Config keys)

**howItWorks**: BOOT: src/client/Movement/init.client.lua starts Hud, Pose, Effects, JumpFx, Animations and Controller (each `.start()` inside a pcall), then calls Rigs.start(). Rigs.lua turns every player's character into a Rig {player, character, humanoid, root, isLocal, isR15, alive, trove}. The trove is cleaned on Died, Destroying, AncestryChanged or CharacterRemoving. State.lua holds the local predicted flags (dashing, sliding, airDashUsed, dashCooldown, dashReadyAt, slideReadyAt) and a small event hub: Dash, DashEnd, DashDenied, SlideStart, SlideEnd.
INPUT (Controller.lua:464-478): ContextActionService binds "PartyDash_Dash" to LeftShift and "PartyDash_Slide" to C and LeftControl, at priority High+50 with Sink, and creates touch buttons (createTouchButton=true). There are no gamepad keys and no RightShift. Jumping is left entirely to the stock Humanoid and ControlModule, so there is no coyote time, no jump buffer and no variable height.
MOTION (Controller, RunService.PreSimulation): each local character gets Attachment "MovementAttachment" and LinearVelocity "MovementVelocity" (World, MaxForce 1e7, disabled at rest).
- DASH: DASH_DURATION 0.22 s and DASH_DISTANCE 18, so the peak speed is 18/(0.22*0.8167) ≈ 100 studs/s with profile v = peak*(1-0.55t²). Direction is MoveDirection, or root.LookVector when standing still. A ground dash uses Plane mode, so gravity still acts. An air dash uses Vector mode with Y forced to +2 (AIR_DASH_RISE) and is allowed once per airtime. When a dash ends naturally, one velocity write sets WalkSpeed*1.05 (ground) or *1.2 (air). The cooldown is Stats.dashCooldown = 2.5*(1-0.06*Upg_DashCooldown), counted from dash start.
- SLIDE: ground only; a press in the air or during a dash is buffered for 0.22 s. Speed: speed0 = min(max(horizontal speed, WalkSpeed)+22, 48), decaying to 0.8*WalkSpeed over SLIDE_DURATION 0.75 s along (1-t)^1.6. Steering turns toward MoveDirection at 2.4 rad/s. AutoRotate is turned off and root.CFrame is rewritten every frame. The slide ends on time, on Humanoid Jumping (horizontal speed capped at 36), on dash, or on cancel (stun, PlatformStand, blocking states, anchored, or InRound during Intro/Countdown). SLIDE_COOLDOWN is 0.4 s from the END of the slide. On R15 only, the slide also plays Assets.SlidePose = 742637151 (Cartoony_Fall) as a looped Action track (Controller.lua:264-283, 309-311).
- REMOTES: Movement_Dash() and Movement_Slide(true/false), with no timestamps. "time" ends are not sent; the server times them out itself.
POSE (Pose.lua, RunService.PreRender, every rig): writes an ADDITIVE left-multiplied offset on the root joint C0 only (LowerTorso.Root on R15, HumanoidRootPart.RootJoint on R6, or AnimationConstraint.Attachment0). The offset combines run pitch -5°, turn roll up to 17°, dash pitch -24° and slide pitch -78° (head first). Blend rates are 16/s in and 11/s out. On a local R15 rig the slide also lowers Humanoid.HipHeight so the hips sit 0.95 above the floor (minimum HipHeight 0.25, so the root ends up about 1.25 above the floor, a real low hitbox) and raises CameraOffset by 55% of that drop. On R6 the drop is visual only: a C0 shift of about 2.05 studs while the root stays 3 studs up. No limb joint is posed. Remote rigs are posed from the replicated Sliding/Dashing attributes.
FX:
- Effects.lua: run/slide dust from an attachment under the root; a dash Trail colored by Cos_DashColor; neon afterimage clones; a shock ring; sparkles; whoosh and sand-slide sounds; and an additive local FOV punch of +13° on dash and +6° while sliding.
- JumpFx.lua: on EVERY local jump, picks a weighted random 0.45 s flip (front/pirouette/back/cartwheel) applied to the root joint Transform in PreSimulation, plus a rainbow trail. Landing shows a ring. Both are relayed through the reliable Movement_JumpFx remote (server rate limit 0.15 s per kind).
- Animations.lua: swaps the local R15 Animate ids to the Cartoony package; R6 keeps the stock animations.
HUD (Hud.lua): ScreenGui MovementHUD.
- DashCooldownBar at bottom center (y offset -92), with key chips "SHIFT" and "C SLIDE", a ready flash and a shake when the dash is denied.
- The CAS touch buttons are reskinned as circles: DASH sits above jump, SLIDE to its left, size clamp(jump*0.86, 58, 104). Each has a cooldown "Shade" overlay.
- Screen-space speed lines.
SERVER (src/server/Movement/init.server.lua):
- Sets StarterPlayer CharacterWalkSpeed 20 and JumpPower 52; Upg_JumpBoost adds 3% per level.
- Dash: accepted if elapsed >= cooldown-0.3. It sets "Dashing" for 0.22 s and increments DashCount; otherwise it replies ("Reject", remaining).
- Slide(true): needs a living character that is not anchored and not Stunned, plus end-to-start >= 0.25 s. It sets "Sliding" for 0.75 s (token-guarded). Slide(false) ends it early.
- Stunned clears both flags.
- There is NO grounded, height, speed or position validation.
KNOCKBACK (src/shared/Knockback.lua, client side): Core_Knockback triggers PlatformStand plus a 5 rad/s tumble for the stun time, with velocity = dir*power + lift (18..75). Restore: PlatformStand off; if the body is tilted, a CFrame snap upright (+1.5 Y); then GettingUp. A watchdog runs every 0.25 s.
RIG TYPE: not pinned anywhere in the repo; it is the place's Avatar setting in Studio. The code supports R15 and R6, but the Cartoony package and the slide track are R15-only.
CONSUMERS of these states and heights:
- LaserTracer init.lua:112: Sliding plus SLIDE_GRACE 0.15 and ping/2 lag compensation. Hit.lua: JUMP_CLEAR 4.2 (root), REACH_ABOVE 8.
- HoleInTheWall init.lua:177: raw Sliding with no grace. Pass.lua: NORMAL_MAX_ROOT 10, HIGH_MIN_ROOT 4.3, LOW_MAX_ROOT 1.6.
- Spin Hit.lua: CLEAR_HEIGHT 1.4 on feet = rootY - server HipHeight - root/2, with ping/2 lag compensation.
- UI/Tutorial.lua: Dashing/Sliding attributes.
Default jump: apex ≈ 6.89 studs (root ≈ 9.89), airtime ≈ 0.53 s.


## bugs


---

**title**: Slide pose is a head-first 'superman' belly flop, not a slide tackle (owner's #11 complaint)

**severity**: major

**file**: src/client/Movement/Pose.lua

**line**: 25

**rootCause**: Two layers produce it. (1) Pose.lua:25 SLIDE_PITCH = -math.rad(78) tilts the whole body forward around the root joint (applied at Pose.lua:174 and 199-207), so the character lies face down, head first. (2) On R15 only, Controller.lua:264-283 loads Assets.SlidePose = 742637151 (Cartoony_Fall, Assets.lua:18-19), a looped Action track with the arms up, played at Controller.lua:309-311. No limb joint is ever posed. On R6 there is no track, so the stock run cycle keeps swinging the legs while the body lies flat.

**fix**: Delete Assets.SlidePose and every slideTrack use in Controller (lines 54, 240-242, 264-283, 309-311, 407, 411). Take SLIDE_PITCH out of the C0 path. Add a procedural full-body Transform override in PreSimulation (see briefPlans #11 for the joint tables), keeping the R15 HipHeight drop.

**evidence**: Pose.lua header comment says 'the belly-slide pose (body tilted flat, head first...)'; Assets.lua:18 says 'Arms-up pose layered over the procedural belly-slide tilt (reads as a "superman" dive)'.


---

**title**: Air dash kills the jump arc, so a jump followed quickly by a dash gets hit by Spin bars and low lasers

**severity**: major

**file**: src/client/Movement/Controller.lua

**line**: 185

**rootCause**: In the air the mover switches to Vector mode with VectorVelocity = dir*peak + (0, AIR_DASH_RISE=2, 0) for the full 0.22 s (lines 183-186, 208-210). This overwrites the jump's +52 vertical velocity. Example: dash 0.02 s after takeoff. The feet are only about 1 stud up and stay there for 0.22 s, below Spin's Hit.CLEAR_HEIGHT 1.4 and below LaserTracer's Hit.JUMP_CLEAR 4.2 (root). The player jumped but is counted as on the ground. This is a direct contributor to brief #22 ('sometimes when I jump the bar still hits me').

**fix**: Run the air dash in Plane mode too (horizontal only), so gravity and the jump arc continue. At start set vy = math.max(vy, 6) for a small hop, never lower. Keep one air dash per airtime.

**evidence**: Controller.lua:183-186 (Vector mode); stepDash 207-211 re-applies the +2 Y every frame.


---

**title**: No jump buffer and no coyote time: jumps pressed just before landing or just after leaving an edge are dropped

**severity**: major

**file**: src/client/Movement/Controller.lua

**line**: 451

**rootCause**: Movement never reads jump input. Grep finds no JumpRequest, humanoid.Jump or ChangeState(Jumping) anywhere in src/client/Movement. The stock Humanoid only jumps from Running/Landed while on the floor. Re-jump timing on Spin pillars and laser hops feels unreliable, which adds to #22.

**fix**: Add a JumpAssist inside Controller's PreSimulation step. Detect the rising edge of humanoid.Jump; the ControlModule sets it every RenderStepped for keyboard, touch and gamepad, so this covers all inputs. Coyote: if the state is Freefall, now - lastGroundedAt <= 0.10 and the player has not jumped since leaving the ground, call humanoid:ChangeState(Enum.HumanoidStateType.Jumping). Buffer: otherwise set bufferUntil = now + 0.12; on the first grounded frame (Running/Landed) with bufferUntil > now, call ChangeState(Jumping). Never act while stunned, PlatformStand or anchored.

**evidence**: grep -rn 'JumpRequest\|ChangeState' src/client/Movement -> no matches.


---

**title**: Server trusts a client-asserted Sliding flag: exploiters pass high lasers and LOW holes while standing or mid-jump

**severity**: major

**file**: src/server/Movement/init.server.lua

**line**: 196

**rootCause**: Movement_Slide(true) is accepted with no grounded, height or speed check (lines 185-210). It only checks alive, not anchored, not Stunned and a 0.25 s cooldown. LaserTracer/init.lua:112 then treats a high beam as harmless whenever Sliding is true, and HoleInTheWall/init.lua:177 passes LOW holes on Sliding alone. A client that never fires false and re-fires every 1.0 s keeps Sliding true about 75% of the time while standing upright.

**fix**: On start, require the character to be grounded: a server raycast from the root, down root.Size.Y/2 + standLeg + 1.5, must hit. Then publish SlideStartAt/SlideEndAt. In the minigame checks (via the new Query.slidingAt) also require R15 root height above floor <= 2.2. The R15 slide root is about 1.25 because of the HipHeight drop. R6 cannot lower its root, so R6 relies on the flag plus the grounded-at-start check. Rate-limit the remote to 8 calls/s.

**evidence**: init.server.lua:196-204; LaserTracer/Hit.lua:49 `return not sliding and rootY <= laserY + Hit.REACH_ABOVE`.


---

**title**: No server-side movement sanity at all (speed, teleport, fly) for client-owned characters

**severity**: major

**file**: src/server/Movement/init.server.lua

**line**: 1

**rootCause**: The client owns its physics, and the server only validates dash/slide cooldowns. Nothing compares root displacement against WalkSpeed, dash or slide allowances. A local WalkSpeed/JumpPower edit, flying, or hovering over Spin lava or HitW walls goes unnoticed. Every survival minigame decides winners from these positions.

**fix**: Add src/server/Movement/Sanity.lua, sampling every Heartbeat. Allowed horizontal speed = WalkSpeed*1.35 + 110 if Dashing + 52 if Sliding + Knockback.MAX_POWER if Stunned within 1 s. Use windows of 0.25 s. After 3 violations within 5 s, rubber-band to the last valid position (Teleport-style PivotTo) and log; do not kick. Fly check: no floor within 40 studs below while vertical velocity >= 0 for more than 2.5 s triggers a pull-down plus rubber-band. Skip when anchored, InSolo is in a countdown, or Debug attributes are set.

**evidence**: grep -rn 'WalkSpeed' src/server shows only spawn-default writes (Movement init.server.lua:55-57, 113-114).


---

**title**: Gamepad and console players cannot dash or slide

**severity**: major

**file**: src/client/Movement/Controller.lua

**line**: 464

**rootCause**: BindActionAtPriority for Dash binds only Enum.KeyCode.LeftShift, and Slide binds only C and LeftControl. No gamepad KeyCode is bound, and UI/Data.lua KEYS has no gamepad hints.

**fix**: Dash: LeftShift, RightShift, ButtonX (and ButtonR1). Slide: C, LeftControl, ButtonB (and ButtonL1). Add gamepad glyph hints in UI Data.keyHint. Add a 0.08 s HapticService:SetMotor(Gamepad1, Small, 0.6) pulse on dash and on knockback.

**evidence**: Controller.lua:464-478.


---

**title**: Dash and slide-jump 'momentum' is discarded within a few frames, so dashes stop dead and the long jump does not exist

**severity**: major

**file**: src/client/Movement/Controller.lua

**line**: 145

**rootCause**: finishDash (145-148) and endSlide 'jump' (248-252) write AssemblyLinearVelocity once and disable the mover. The Humanoid controller then pulls the velocity back to MoveDirection*WalkSpeed: almost instantly on the ground, and within about 0.1-0.2 s in the air while a key is held. The DASH_EXIT_* and SLIDE_JUMP_CAP 36 constants therefore have almost no effect, and the movement feels stiff.

**fix**: Add a 'tail' phase that keeps the LinearVelocity in Plane mode with decaying speed and steering. Dash tail: 0.15 s, from 1.35*WS down to WS. Long-jump tail: while airborne up to 0.45 s, from min(speed, 36) down to WS (ease-out). Steer at 3-4 rad/s toward MoveDirection. Cancel on landing (long jump), on pull-back (MoveDirection·dir < -0.3), on stun, or on a new dash or slide.

**evidence**: Controller.lua:145-148, 248-252.


---

**title**: Dash cooldown bar plus 'C SLIDE' chip always on screen, and the mobile slide button shows a cooldown shade, which the owner explicitly does not want (#11)

**severity**: minor

**file**: src/client/Movement/Hud.lua

**line**: 88

**rootCause**: buildBar (88-194) creates PlayerGui.MovementHUD.DashCooldownBar at the bottom center (UDim2(0.5,0,1,-92)), with the 'SHIFT' and 'C SLIDE' chips. It stays visible in the lobby, while spectating, and on top of minigame pills (the current-game screenshot shows 'CLIMB TO THE GOLDEN ZONE' stacked over it). skinButton (305-321) gives the SLIDE touch button a vertical cooldown shade that fills from the top (updateButtons 390-396), which is effectively a bar.

**fix**: See briefPlans #11 (cooldown without a bar). Delete the bar, the chips, updateBar, flashReady, shakeDenied and onDash. Remove the slide shade. Dim the slide button while it recharges. Dash feedback becomes a radial ring on the mobile button and in-world cues on PC. Grep confirms nothing outside Movement references MovementHUD or DashCooldownBar.

**evidence**: docs/reference/current-game-koth.jpg bottom: SHIFT [DASH bar] C SLIDE.


---

**title**: Slide keeps running in mid-air after sliding off a ledge (pose, forced velocity and Sliding flag all stay on)

**severity**: minor

**file**: src/client/Movement/Controller.lua

**line**: 317

**rootCause**: stepSlide only ends on time, and trySlide checks isGrounded only at start. Off a ledge the Plane mover keeps forcing horizontal speed and the tackle pose stays on while falling. The server keeps Sliding=true in the air, which also makes LaserTracer high beams harmless at any height up to laserY+8.

**fix**: In stepSlide, track airTime. If FloorMaterial == Air for more than 0.12 s, call endSlide(rig, 'air'): fire false, hand over to the momentum tail, and play the normal fall animation. Also end with reason 'blocked' when actual horizontal speed stays below 35% of the commanded speed for 0.08 s (slid into a wall).

**evidence**: Controller.lua:317-333 has no grounded test.


---

**title**: Dash/slide ignore the floor's velocity, so players get yanked off moving or rotating platforms (planned Bomb Tag obstacles)

**severity**: minor

**file**: src/client/Movement/Controller.lua

**line**: 305

**rootCause**: The LinearVelocity uses RelativeTo World with absolute PlaneVelocity (lines 181, 208, 306, 330). On a moving floor, walking is carried by friction, but the mover overrides that, so the platform's velocity is lost for the length of the dash or slide.

**fix**: Each step, raycast down from the root (Exclude the character). If the hit part is not anchored or has non-zero AssemblyLinearVelocity/AssemblyAngularVelocity, add hit.Instance:GetVelocityAtPosition(hit.Position) (flattened) to PlaneVelocity.

**evidence**: Controller.lua:379-388 creates a world-relative mover.


---

**title**: Jump Boost upgrade and the LowGravity modifier break minigame jump thresholds

**severity**: minor

**file**: src/server/Minigames/HoleInTheWall/Pass.lua

**line**: 20

**rootCause**: NORMAL_MAX_ROOT = 10, but the default apex root is already 9.89. Jump Boost level 1 (JumpPower 53.56) gives an apex root of 10.31, so buying an upgrade makes doorway jumps FAIL. LowGravity (client gravity 70, src/client/Modifiers/LowGravity.lua:6) gives an apex of 19.3 and a root of 22.3, above WALL_HEIGHT+0.5 = 14.5, so walls can be jumped over (HoleInTheWall/init.lua:229). It also clears LaserTracer high beams, whose REACH_ABOVE 8 caps the root at 12.6, even though 'high cannot be jumped'.

**fix**: Have hit rules read a shared Query.jumpApex(player) (from JumpPower and effective gravity) instead of constants: NORMAL_MAX_ROOT = standRoot + apex + 0.5. Alternatively exclude LowGravity from HoleInTheWall and LaserTracer in Core's modifier pick. Movement should also publish the effective jump height as a character attribute 'JumpApex'.

**evidence**: apex = JumpPower²/(2*196.2); Config.UPGRADES.JumpBoost perLevel 0.03.


---

**title**: Knockback recovery pops: upright snap +1.5 studs, GettingUp forced even in mid-air, and the tumble usually ends upside down

**severity**: minor

**file**: src/shared/Knockback.lua

**line**: 153

**rootCause**: restore() sets root.CFrame = uprightCFrame(root), and uprightCFrame adds Vector3(0,1.5,0) (line 136). It then calls ChangeState(GettingUp) even when airborne. With TUMBLE_SPEED 5 rad/s over the 0.6-0.9 s stuns, the body turns 172-258°, so the snap is almost always visible.

**fix**: Set TUMBLE_SPEED to 3. Replace the snap with an AlignOrientation (OneAttachment on the root, Responsiveness 40, MaxTorque 1e6, yaw kept) enabled for 0.2 s with no position offset. Use ChangeState(Freefall) when FloorMaterial == Air, otherwise GettingUp. Movement should reset State.airDashUsed = false when Stunned goes false, which allows the clutch-save air dash.

**evidence**: Knockback.lua:136, 146-157, 183.


---

**title**: Random flip on every jump physically rotates the owner's collidable torso and head and hides jump timing

**severity**: minor

**file**: src/client/Movement/JumpFx.lua

**line**: 157

**rootCause**: Every Jumping state plays a 0.45 s front/back flip, pirouette or cartwheel on the root joint Transform. For the owner, Transform also moves the collidable Head/UpperTorso (R15) or Torso/Head (R6), so flips can bump walls or ceilings. Constant spinning also makes the jump apex hard to read in Spin and Laser.

**fix**: Normal jumps: no flip, just the Cartoony jump animation plus the landing ring. Play a single front flip only on a long jump (jump out of a slide) and optionally on an air dash. Compose it inside the new Pose PreSimulation pass, after the slide layer.

**evidence**: JumpFx.lua:20-25 weights, 157-161.


---

**title**: Mobile auto-jump left on

**severity**: minor

**file**: src/server/Movement/init.server.lua

**line**: 55

**rootCause**: StarterPlayer.AutoJumpEnabled is never set (default true), so phone players auto-jump whenever they walk into an obstacle, which causes unintended jumps on pillars and obstacle maps.

**fix**: Set StarterPlayer.AutoJumpEnabled = false next to lines 55-57, and humanoid.AutoJumpEnabled = false in onCharacter.

**evidence**: grep AutoJumpEnabled src -> none.


---

**title**: Core camera shake overwrites Humanoid.CameraOffset every frame and zeroes it at the end, fighting Pose's additive slide offset

**severity**: minor

**file**: src/client/Core/init.client.lua

**line**: 84

**rootCause**: shakeCamera (84-108) writes a random CameraOffset every RenderStepped for 0.3 s, then sets Vector3.zero, while Pose.lua:219-229 maintains its own additive CameraOffset. Overlapping hits spawn parallel shake loops.

**fix**: Move all camera effects into a single Movement-owned CameraFx module (trauma shake, FOV punch, slide offset, landing dip) and have Core call CameraFx.shake(0.6).

**evidence**: init.client.lua:98-107; Pose.lua:219-229.


---

**title**: RightShift is advertised and accepted as dash but toggles shift-lock instead

**severity**: minor

**file**: src/client/Movement/Controller.lua

**line**: 469

**rootCause**: Only LeftShift is bound. UI/Tutorial.lua:38 lists RightShift and completes the Dash step on that key, and the default MouseLockController binds LeftShift and RightShift.

**fix**: Bind Enum.KeyCode.RightShift to the dash action as well.

**evidence**: Tutorial.lua:38 keys = { LeftShift, RightShift }.


---

**title**: Hole in the Wall LOW check reads the raw Sliding boolean with no grace window

**severity**: minor

**file**: src/server/Minigames/HoleInTheWall/init.lua

**line**: 177

**rootCause**: LaserTracer allows SLIDE_GRACE 0.15 for replication jitter, but HitW samples the attribute at the crossing frame only. A slide that ends 1-2 frames early on the server, because the server timer started at receive time, fails a LOW hole that the player saw themselves clear.

**fix**: Use the shared Query.slidingAt(character, now - lag, 0.12) based on the new SlideStartAt/SlideEndAt attributes.

**evidence**: HoleInTheWall/init.lua:177 vs LaserTracer/init.lua:113-118.


---

**title**: Every rejected dash gets a reliable reply (no rate limit)

**severity**: minor

**file**: src/server/Movement/init.server.lua

**line**: 161

**rootCause**: Spamming Movement_Dash produces one FireClient('Reject') per call.

**fix**: Keep a per-player token bucket (10/s) and drop silently above it. Reply with Reject at most once per 0.2 s.

**evidence**: init.server.lua:161-165.


## briefPlans


---

**briefItem**: #3 Controls must be 10x better (feel, jump, dash, slide, knockback, mobile, camera, input, latency)

**currentState**: Stock Humanoid walking and jumping (WS 20, JumpPower 52: apex 6.89 studs, airtime 0.53 s). No coyote time or jump buffer. Dash: 0.22 s, 18 studs, 100 studs/s peak, 2.5 s cooldown; the air dash freezes Y. Slide: 0.75 s, +22 boost, 0.4 s cooldown. Momentum after dash and slide is lost within frames. The slide continues in mid-air. No gamepad bindings. Strong FOV punch (+13°). Knockback recovery pops. Flips on every jump. Auto-jump is on for mobile. No server sanity checks.

**plan**: Files: src/client/Movement/Controller.lua (motion), a new src/client/Movement/JumpAssist.lua required by Controller, Pose.lua, Effects.lua, a new src/client/Movement/CameraFx.lua, Hud.lua (buttons only), src/server/Movement/init.server.lua, and new src/server/Movement/Sanity.lua and History.lua. Core-owned src/shared/Knockback.lua needs a coordinated edit.

A. INPUT
- Dash: LeftShift, RightShift, ButtonX, ButtonR1.
- Slide: C, LeftControl, ButtonB, ButtonL1.
- Keep priority High+50 with Sink.
- DASH_BUFFER 0.15 s: a dash pressed up to 0.15 s before the cooldown ends fires automatically.
- SLIDE_BUFFER 0.22 → 0.18. While a dash is active, buffer until dash end + 0.1.
- Set StarterPlayer.AutoJumpEnabled = false.

B. JUMP (JumpAssist, run in Controller's PreSimulation before dash/slide)
- Track lastGroundedAt from FloorMaterial ~= Air, and jumpedSinceGround.
- Detect the rising edge of humanoid.Jump.
- Coyote 0.10 s: ChangeState(Jumping) from Freefall.
- Buffer 0.12 s: ChangeState(Jumping) on the first grounded frame.
- Keep JumpPower 52. All minigame thresholds assume apex root ≈ 9.9, so do NOT add variable jump height: short taps on mobile would fail the Spin and Laser clear heights.
- Optional fall-gravity multiplier 1.25: VectorForce on MovementAttachment, Force = (0, -AssemblyMass*workspace.Gravity*0.25, 0). Enable only while vy < -1, state is Freefall, not stunned, not dashing, and no tail is active. Scale with workspace.Gravity so LowGravity stays proportional. This cuts descent time by about 0.03 s while the clear windows stay ≥ 0.44 s.

C. DASH
- Config.DASH_COOLDOWN 2.5 → 1.6 (upgrade lvl 5 = 1.12 s).
- Config.DASH_DISTANCE 18 → 16 and DASH_DURATION 0.22 → 0.18, giving a peak of 16/(0.18*0.8167) ≈ 109 studs/s.
- Keep the profile drop at 0.55.
- Air dash: Plane mode; at start set vy = max(vy, 6); one per airtime; refunded on landing (already) and on knockback recovery (new).
- Exit tail: 0.15 s, Plane mode, speed from 1.35*WS down to WS (ease-out quad), steer 4 rad/s.
- Dash is cancellable into a jump (Plane mode already allows this).
- Optional dash→slide: a slide pressed after 60% of a ground dash cancels into a slide with speed0 = min(current speed*0.55 + 20, 46).
- MOVER_FORCE 1e7 → AssemblyMass*6000 (re-read on Giant/Tiny), to avoid tunnelling and jitter against walls.

D. SLIDE
- Config.SLIDE_DURATION 0.75 → 0.7 and SLIDE_COOLDOWN 0.4 → 0.5, so start-to-start is 1.2 s, just above LaserTracer COMBO_GAP 0.95.
- SLIDE_BOOST 22 → 20, SLIDE_MAX_SPEED 48 → 44, SLIDE_END_SPEED 0.8 → 0.9.
- Curve exponent 1.6 → 2.0 (front-loaded kick).
- Steer 3.0 rad/s for t < 0.35, then 1.8.
- Slopes: raycast the floor normal. If normal.Y < 0.97, add 0.6*g*sin(angle)*dt along the downhill direction, capped at 52. Uphill gets the opposite.
- End the slide when airborne for more than 0.12 s (reason 'air') or when blocked (actual speed < 35% of commanded for 0.08 s).
- Long jump: on Humanoid Jumping during a slide, keep the mover as a tail at speed min(current, 36) decaying to WS over 0.45 s (steer 3 rad/s). Cancel on landing. Play a single front flip.
- Add floor velocity on moving platforms, in both dash and slide.
- Replace the per-frame root.CFrame writes (faceDirection) with an AlignOrientation (OneAttachment, RigidityEnabled=true, only while sliding).

E. KNOCKBACK RECOVERY (Knockback.lua)
- TUMBLE_SPEED 5 → 3.
- Replace the upright snap (no +1.5 Y) with AlignOrientation for 0.2 s.
- Use Freefall if airborne, else GettingUp.
- Movement listens for Stunned true→false: sets State.airDashUsed=false and plays a soft recovery puff.
- Local hit sound plus a 0.12 s white Highlight on hit (brief #25).

F. CAMERA (new CameraFx.lua; Effects stepFov moves there)
- Base FOV Config.CAMERA_FOV = 72, applied once per CurrentCamera.
- Dash punch +13 → +8 (attack 0.05 s, decay exp rate 7). Slide +6 → +4.
- Landing dip: CameraOffset.Y -0.3*clamp((fallSpeed-50)/60, 0, 1), springing back in 0.15 s.
- Trauma shake: offset = trauma²*0.45 studs*noise(t*25) plus up to 1.2° roll; trauma decays 1.6/s. Hit adds 0.6; the bomb explosion adds 1.0 scaled by distance.
- Pose's slide CameraOffset becomes a CameraFx channel, and Core's shakeCamera calls CameraFx.shake.
- StarterPlayer.CameraMaxZoomDistance 128 → 45 and CameraMinZoomDistance → 6.

G. MOBILE (Hud.lua → ActionPad, see #20)
- Dash size clamp(jump*0.9, 64, 112); Slide size clamp(jump*0.82, 60, 100).
- Arc around the jump button with r = jump/2 + 10 + size/2: Slide at 180° (left), Dash at 125° (up-left), minigame action at 80° (above).
- Press scale 0.88 over 60 ms, release with Back easing over 180 ms; ready pop 1.12.

H. LATENCY
- The client sends workspace:GetServerTimeNow() with Movement_Dash(t) and Movement_Slide(true, t). The server clamps t to [now-0.25, now] and publishes SlideStartAt, SlideEndAt (= start + SLIDE_DURATION, or the early-end time) and DashStartAt, alongside the Sliding/Dashing booleans.
- Minigames use Query.slidingAt(char, now - lag, 0.12).
- History.lua samples each character's root position and vertical velocity on every Heartbeat (0.6 s ring buffer), so hit checks can ask whether the root was above height h during [t0, t1].
- Sanity.lua handles speed and fly checks (see bugs).

I. FEEL EXTRAS
- Turn-around skid: when the dot of the velocity direction with MoveDirection drops below -0.5 at speed above 15, emit 6 dust puffs and briefly raise the lean.
- Landing squash is camera-only.
- Keep run lean/roll.

**risks**: Changes to DASH_DISTANCE/SLIDE_DURATION shift every minigame's balance, so playtest Laser combos and Hole in the Wall LOW holes. ChangeState(Jumping) from Freefall must be verified in Studio (it is the standard double-jump approach). The fall-gravity VectorForce must be disabled during PlatformStand and LowGravity scaling must be checked. Config is frozen, so the lead must apply the value changes and new keys. Knockback.lua belongs to Core.


---

**briefItem**: #11 Slide animation: football slide tackle (procedural, R15 + R6)

**currentState**: Current implementation: (a) Pose.lua tilts only the root joint C0 by -78° (head first), blended at 16/s in and 11/s out, and on a local R15 rig lowers HipHeight so the root sits about 1.25 above the floor (R6 gets a visual-only C0 drop of 2.05). (b) R15 additionally plays animation 742637151 (Cartoony_Fall, arms up) as a looped Action track. (c) R6 limbs keep the stock run cycle. No limb joints are posed procedurally. The rig type is not pinned in the repo; it comes from the place Avatar setting.

**plan**: 1) DELETE: Assets.SlidePose (Assets.lua:18-19); slideTrack in Controller.lua (lines 54, 240-242, 264-283, 309-311, 407, 411); SLIDE_PITCH in Pose.lua (line 25 and its use in line 174: pitch = ... + p.slide*SLIDE_PITCH becomes just the lean layer times (1-w)).

2) NEW src/client/Movement/TacklePose.lua: pure data plus math.
- Joint lookup by name.
  - R15 (joint name, under its Part1): LowerTorso.Root, UpperTorso.Waist, Head.Neck, LeftUpperLeg.LeftHip, LeftLowerLeg.LeftKnee, LeftFoot.LeftAnkle, RightUpperLeg.RightHip, RightLowerLeg.RightKnee, RightFoot.RightAnkle, LeftUpperArm.LeftShoulder, LeftLowerArm.LeftElbow, LeftHand.LeftWrist, RightUpperArm.RightShoulder, RightLowerArm.RightElbow, RightHand.RightWrist.
  - R6: HumanoidRootPart.RootJoint, Torso.Neck, Torso['Left Shoulder'], Torso['Right Shoulder'], Torso['Left Hip'], Torso['Right Hip'].
  - Accept Motor6D (frame = C0) or AnimationConstraint (frame = Attachment0.CFrame); both expose .Transform.
- Angles are degrees in the PARENT part's rest frame (X right, Y up, -Z forward):
  - +rx swings a hanging limb forward and tilts a torso back.
  - +rz swings a hanging limb toward +X (right).
  - ry is a twist about the limb's own axis (+ = counter-clockwise seen from above).
  - Build R = CFrame.Angles(rad(rx),0,0) * CFrame.Angles(0,0,rad(rz)) * CFrame.Angles(0,rad(ry),0), so the twist is applied first.
  - Target Transform per limb: T = C0rot:Inverse() * R * C0rot, where C0rot = frame - frame.Position. The rotation-only form is scale-invariant, so Giant/Tiny work.
  - Root: T = C0:Inverse() * M * C0, with M = CFrame.new(0,-drop,0) * CFrame.new(q) * R * CFrame.new(-q) in HRP space.
- R15 table (right leg leads):
  - Root: rx +62, rz +10 (lean back, weight on the left hip); q = C0.Position; drop = 0 (the existing HipHeight drop does it physically; set SLIDE_PIVOT_HEIGHT 0.95 → 0.85).
  - Waist: rx -14, rz -4, ry +8. Neck: rx -36, ry -8.
  - RightHip: rx +20, rz -4 (leg straight forward, about 8° below horizontal). RightKnee: rx -3. RightAnkle: rx +25 (toes up, studs showing).
  - LeftHip: rx +8, rz -30, ry +55. LeftKnee: rx -100. LeftAnkle: rx -15. This is a figure-4 tuck: the shin lies flat across, under the leading leg.
  - LeftShoulder: rx -62, rz -20. LeftElbow: rx +8. LeftWrist: rx -50 (the support hand reaches the floor behind-left).
  - RightShoulder: rx +72, rz +30. RightElbow: rx +35 (balance arm forward-up, about 26° above horizontal).
- R6 table (no knees, elbows or waist):
  - RootJoint: rx +55, rz +6; q = (0,-1,0) in HRP space (bottom of the torso); drop 1.4, visual for all clients. Hips end about 0.6 above the floor and the torso never dips below the floor.
  - Neck: rx -40.
  - Right Hip: rx +27, rz -4. Left Hip: rx +15, rz -40 (splayed out to the side, foot on the floor).
  - Left Shoulder: rx -70, rz -20. Right Shoulder: rx +65, rz +30.
- Mirror helper (left-leg lead): swap the Left/Right entries and negate ry and rz, including the root rz. Default is always the right leg, which is consistent and readable.

3) Pose.lua: add RunService.PreSimulation (after the Animator writes Transform) for every rig.
- w = smoothstep(p.slide), where p.slide smooths in at 30/s (≈0.1 s to 95%) and out at 13/s (≈0.23 s), or 20/s after a jump-out.
- Entry accent: for the first 0.08 s add +6° root rx with easeOutBack.
- For each joint: j.Transform = j.Transform:Lerp(T, w). The root uses its own M with drop*w.
- Keep the run/dash lean C0 layer times (1-w).
- Move JumpFx's flip write into this same pass, after the slide layer, to fix write ordering. Skip flips while w > 0.05.
- Remote rigs use the same code from the Sliding attribute; all clients pose all rigs, and Transform is not replicated.
- R15 local rig keeps the physical HipHeight drop (root about 1.15-1.25 above the floor, which is the low hitbox Laser and HitW rely on).

4) Collision safety: in Studio, check that min(Y of Head, UpperTorso, LowerTorso / Torso, Head) - floor >= 0.05 while sliding. If it fails, raise the pivot by 0.1. Optional hard guarantee: the server registers a 'PD_SlideBody' collision group (PhysicsService:RegisterCollisionGroup plus CollisionGroupSetCollidable('PD_SlideBody','Default',false)). The owning client sets those parts' CollisionGroup while w > 0 and restores 'Default' afterwards.

5) Dust trail (Effects.lua):
- New attachments: TackleHeel on the leading foot (R15 RightFoot (0,-0.3,-0.4); R6 'Right Leg' (0,-1,-0.5)) and TackleHip at the bottom-left of LowerTorso or Torso.
- During the slide:
  - Heel emitter: Rate 45/s for the first 0.25 s, then 22/s.
  - Hip emitter: 15/s.
  - Dust color = floor color (raycast Instance.Color, or the Terrain material color) lerped 35% toward white. Size 0.5 → 1.8, Lifetime 0.35-0.55, Speed 3-6.
  - Burst of 10 small 'turf' bits in the floor color at the start.
  - Skid ribbon: Trail between two attachments at the heel X ±0.35, FaceCamera=false, Lifetime 0.45, Transparency 0.35 → 1, color = floor*0.75, enabled only while grounded.
- Keep the 'Sand Slide 7' sound and add a short whoosh at the start.
- Rigs: also pin Avatar Type to R15 in Game Settings (knees and elbows make the tackle read far better), but keep the R6 table as a fallback.

**risks**: Exact R15 C0 positions vary between body types (Rthro), so angles may need ±10° tuning in Studio. Transform writes must happen in PreSimulation or the Animator overwrites them. Studio screen_capture has been unreliable for 3D in earlier runs, so verify by measuring part positions in execute_luau, not by screenshots alone. AnimationConstraint rigs must be tested if the place has the avatar joint upgrade enabled.


---

**briefItem**: #11 Slide cooldown with NO bar (subtle feedback only)

**currentState**: Hud.lua draws DashCooldownBar with 'SHIFT' and 'C SLIDE' chips at the bottom center at all times. The mobile SLIDE button has a dark 'Cooldown' CanvasGroup shade that fills while recharging. The slide cooldown is 0.4 s after the slide ends.

**plan**: REMOVE from Hud.lua:
- buildBar (88-194): DashCooldownBar, Glow, Fill, Gloss, Flash, Label, KeyHint 'SHIFT', SlideHint 'C SLIDE'.
- flashReady (196-208), shakeDenied (210-221), the bar part of onDash (223-232) and updateBar (234-251).
- updateBar from the PreRender loop (505).
- The State.on('DashDenied', shakeDenied) hookup.
The slide button keeps no shade: skinButton(actionName, title, color, withShade) passes withShade=false for Slide, and lines 390-396 are deleted.

SUBTLE FEEDBACK:
- Mobile slide button: while os.clock() < State.slideReadyAt or State.sliding, tween BackgroundTransparency to 0.45 and icon/title transparency to 0.5 over 0.08 s. On becoming ready, tween back over 0.12 s with a scale pop 1.0 → 1.08 → 1.0. No numbers, no fill.
- PC: nothing on screen for slide. The 0.18 s input buffer makes early presses still fire, so the cooldown feels like 'responsive', not 'blocked'.
- Dash (not covered by the no-bar rule, but the bar goes too):
  - Mobile dash button: thin radial ring, using the two-half-frame UIGradient technique.
  - PC: no HUD. When the dash recharges, play the existing DashReady click at 0.25 volume plus a small sparkle burst (Effects sparkles:Emit(6)) at the character's feet.
  - DashDenied: soft 'tick' sound at 0.2 volume.
- Config.SLIDE_COOLDOWN 0.4 → 0.5 and SLIDE_DURATION 0.75 → 0.7 (start-to-start 1.2 s).
- Keep State.slideReadyAt as the single source.
- Update ARCHITECTURE.md: P2 'dash+cooldown bar' is gone.

**risks**: Without a PC dash indicator, new players may not know the dash cooldown. The Tutorial (UI) already teaches keys; the sparkle-on-ready cue must be visible enough.


---

**briefItem**: #22 Spin: 'sometimes when I jump the bar still hits me' (movement-side contributors) + general jump fairness

**currentState**: Spin Hit: feet = rootY - (server HipHeight + root.Size.Y/2), cleared if >= 1.4, lag compensated by ping/2 with MAX_LAG 0.2. Movement contributors found: (1) the air dash forces vy=+2 for 0.22 s, cutting the jump; (2) no jump buffer or coyote time, so presses are dropped; (3) a slide-jump starts from a root lowered by 1.75 (R15 HipHeight drop), which narrows the clear window to about 0.39 s; (4) flips on every jump make the apex unreadable; (5) the server sees the client-owned root later than ping/2 assumes (physics replication buffering).

**plan**: Movement side:
- Air dash in Plane mode with vy = max(vy, 6) (Controller.lua:183-186, 208-210).
- JumpAssist coyote 0.10 s and buffer 0.12 s.
- Flips only on long jumps.
- Restore HipHeight faster at slide end: smoothing out at 13/s, and a jump-out snaps HipHeight back within 0.1 s.
- New server History.lua: each Heartbeat, push (serverTime, root.Position.Y, root.AssemblyLinearVelocity.Y) per player into a 0.6 s ring buffer. API: History.maxRootY(player, t0, t1) and History.wasRising(player, t0, t1).
Shared helper src/shared/Movement/Query.lua with standRootHeight(humanoid, root, character) for R15/R6 and scale, replacing the copies in Teleport.lua:25-30, Spin/init.lua:66-71 and CharacterEffect.lua:110-119.
Recommendation for the Spin owner: treat the player as cleared if maxRootY over [t-lag-0.10, t-lag+0.03] minus standHeight >= CLEAR_HEIGHT, i.e. a 100 ms jump grace.

**risks**: A grace window makes Spin slightly easier, so retune bar speed. The History module must be the one live instance (require it from the Movement script folder in the same VM).


---

**briefItem**: #10 Bomb Tag: movement hooks the new mode needs

**currentState**: No speed-modifier contract exists: minigames would have to write WalkSpeed directly and fight Movement's spawn defaults. Dash and slide ignore moving platforms. There is no server-side 'tackle' query.

**plan**: - New character attribute Move_SpeedMul (number, default 1), written by minigames on the server. The Movement server applies WalkSpeed = Config.WALK_SPEED * mul, re-applied on spawn and on change, and the client exit/tail speeds read humanoid.WalkSpeed. Example: Bomb Tag holder 1.12.
- Optional Move_DashCooldownMul, read by Stats.dashCooldown on both client and server (holder 0.7, so they can chase).
- Signature move: Query.isTackling(character, t) is true during the first 0.45 s after SlideStartAt. Bomb Tag passes the bomb when the holder's root is within 3.5 studs of a target, or within 5.5 studs while tackling. The tackled target gets ctx.knockback(power 45, stun 0.25) and a 'TACKLED!' popup.
- Add floor velocity to the dash and slide mover so moving and rotating obstacles on the Bomb Tag map work.
- Bomb explosion → CameraFx.shake(1.0 * falloff).

**risks**: Move_SpeedMul must be cleared by Core or the minigame on round end. Movement should reset it to 1 on InRound=false.


---

**briefItem**: #17 Spectate / back to lobby after death: movement UI state

**currentState**: The touch Dash/Slide buttons and the dash bar stay visible while spectating. State.dashReadyAt and slideReadyAt are not reset on a new character.

**plan**: - Hud/ActionPad: hide all action buttons while Player.Spectating == true or the local character is anchored on the spectator platform. Listen to GetAttributeChangedSignal('Spectating'); set Visible = false on the CAS buttons and keep the bindings.
- attach() in Controller: reset State.dashReadyAt = 0 and slideReadyAt = 0 on a revive (#28) or respawn, so a fresh life starts ready.

**risks**: The CAS button can be recreated by CAS, so re-apply visibility in the layout pass.


---

**briefItem**: #18 Fix all bugs: movement exploits and server validation

**currentState**: Only dash/slide cooldowns are validated. The Sliding flag is trusted. There are no speed, fly or teleport checks and no remote rate limits.

**plan**: - Server Movement:
  - Grounded check on slide start.
  - Clamped client timestamps.
  - SlideStartAt, SlideEndAt and DashStartAt attributes.
  - Token-bucket rate limit of 10 calls/s per remote; Reject replies at most once per 0.2 s.
- Sanity.lua: speed allowance per 0.25 s window = WS*1.35 + 110 if Dashing + 52 if Sliding + 400 if Stunned within 1 s. 3 strikes within 5 s trigger a rubber-band; fly detection after 2.5 s of hover.
- Query.slidingAt for R15 also requires the root to be no more than 2.2 above the floor.
- Switch the JumpFx relay to Net.unreliable (client and server together).
- Fix the bug list above in severity order.

**risks**: False positives on moving platforms and Slippery, so add the platform velocity and Slippery allowance (1.6x WS). Never kick; only rubber-band and log.


---

**briefItem**: #20 / #9 UI 10x better + modern: mobile action buttons and a minimal movement HUD

**currentState**: Three systems lay out CAS touch buttons independently with copied jumpButtonRect code: Movement Hud.lua:334-376, Dodgeball Throw.lua:158-215 and KOTH Input.lua:94-121. Buttons are text-only circles ('DASH', 'SLIDE').

**plan**: - New src/client/Movement/ActionPad.lua as the single owner of touch action-button layout.
  - API: ActionPad.bind(actionName, {slot='move1'|'move2'|'primary', icon=assetId?, label, color}, handler, keys...).
  - Slots on an arc around JumpButton with r = jump/2 + 10 + size/2: move2 Slide at 180°, move1 Dash at 125°, primary minigame action (Throw / Bomb pass) at 80°.
- Style matches the references: chunky 3D-looking circles, 3 px Ink stroke, gloss, a bold icon from the ChatGPT art set (dash = speed arrow, slide = cleat/shoe) with a small outlined label under it, press squash 0.88, ready pop.
- The dash cooldown is a radial ring; slide only dims.
- On PC, no permanent HUD at all for movement.
- Dodgeball and Bomb Tag client code call ActionPad instead of positioning CAS buttons themselves.

**risks**: CAS recreates buttons on rotation, so ActionPad must re-skin idempotently (the PartyDashSkin marker pattern already exists). Requires the icon assets from the art pipeline; use a text fallback.


---

**briefItem**: #25 Click / hit sounds: movement and knockback audio

**currentState**: Dash whoosh (15675024286), slide sand (9118771226) and DashReady click exist. There is no hit sound on knockback; Core client shows only sparkles and a pop word.

**plan**: - Knockback client: local 'impact' sound at 0.8 volume on Core_Knockback.
- Remote players: a 3D hit sound at the root on Stunned true, with RollOffMaxDistance 80. The best place is Core's watchCharacter (src/client/Core/init.client.lua:110-125).
- DashDenied: a soft tick at 0.2.
- Slide start whoosh at 0.35.
- Landing thud only when fallSpeed > 60.
- All movement sounds go through a SoundGroup 'SFX' so the settings menu (#23) can mute or scale them.

**risks**: Sound asset ids must be public Roblox-owned ones (Assets.lua already uses those).


---

**briefItem**: #12 / #6 Addictive: skill expression through movement

**currentState**: Movement is functional but flat: no combos, no rewarding 'clutch' moments, flips are random noise.

**plan**: - Long jump (slide → jump keeps momentum, with a front flip).
- Dash → slide cancel.
- Air-dash save after being knocked back (airDashUsed reset on recovery).
- Slide-tackle bomb pass in Bomb Tag.
- 'NICE DODGE!' hook: Movement publishes SlideStartAt and jump times (History). Minigames that detect a near miss (hazard passes within 0.15 s of the dodge start) call a shared reward (popup plus +1 coin through Economy) for a learnable mastery loop.
- Optional dash/trail cosmetics already exist (Cos_DashColor); add a Robux slide-dust color cosmetic (Cos_SlideDust), read by Effects in the same way as the dash color.

**risks**: Rewards need Economy rate limits so exploits cannot farm coins.


---

**briefItem**: #13 / #15 Laser Tracer redesign: slide/jump interplay constraints for the new random red lasers

**currentState**: Hit.lua: low beam at 1.6 (jump: root >= floor+4.2), high beam at 4.6 (slide only, any root up to laserY+8). SLIDE_GRACE 0.15. COMBO_GAP 0.95.

**plan**: - Keep beam heights compatible with movement: an R15 slide root of about 1.2 and a visual head of about 2.6 in the new tackle pose stay well under 4.6; the jump apex root is 9.9.
- Use Query.slidingAt with SlideStartAt/SlideEndAt instead of the slideSeen bookkeeping.
- Random laser motion must keep the gap between two 'high' passes at a given spot >= 1.25 s (slide start-to-start 1.2 s) and between low → high >= 0.95 s.
- Exclude LowGravity from Laser and HitW, or make REACH_ABOVE follow Query.jumpApex.

**risks**: Owned by the Laser auditor; listed here so the slide timing constants stay in sync.

**contractChanges**: 1. Config.lua (frozen; the lead edits it):
   - Changed values: DASH_COOLDOWN 2.5→1.6, DASH_DISTANCE 18→16, DASH_DURATION 0.22→0.18, SLIDE_DURATION 0.75→0.7, SLIDE_COOLDOWN 0.4→0.5.
   - New keys: COYOTE_TIME=0.10, JUMP_BUFFER=0.12, DASH_BUFFER=0.15, CAMERA_FOV=72, FALL_GRAVITY_MULT=1.25 (optional), SLIDE_GRACE=0.12 (shared by all minigames).
2. New character attributes written by server Movement, to be documented in ARCHITECTURE.md:
   - SlideStartAt, SlideEndAt, DashStartAt: numbers, workspace:GetServerTimeNow() based on the client-sent timestamp clamped to [now-0.25, now].
   - SlideCount: int.
   - JumpApex: studs; the effective jump height from JumpPower and gravity.
   - Sliding, Dashing and DashCount stay for compatibility.
   - Remote signatures change: Movement_Dash(t: number) and Movement_Slide(active: boolean, t: number). The server must reject non-finite t.
3. New shared module src/shared/Movement/Query.lua (pure):
   - slidingAt(character, t, grace?), dashingAt(character, t), isTackling(character, t).
   - standRootHeight(humanoid, root, character): R15/R6 and scale. Replaces the three private copies in Core/Teleport.lua:25-30, Spin/init.lua:66-71 and Modifiers/_Lib/CharacterEffect.lua:110-119.
   - jumpApex(player).
   - Minigames (Laser, HitW, Spin, Bomb Tag) must use it instead of raw GetAttribute('Sliding').
4. New server module ServerScriptService.Server.Movement.History (src/server/Movement/History.lua). It is a child of the Movement Script, sampled by it, and minigames require it in the same VM. API: maxRootY(player, t0, t1) and wasRising(player, t0, t1).
5. Speed/cooldown modifier contract: character attributes Move_SpeedMul (default 1) and optional Move_DashCooldownMul, written by minigames and reset by Movement when InRound goes false. Only Movement writes WalkSpeed, which removes the WalkSpeed race with Core and modifiers.
6. Mobile action buttons: replace the ARCHITECTURE.md rule 'positioned bottom-right above the jump button and must not overlap' with a contract. src/client/Movement/ActionPad.lua owns the layout; the slots are move1 (Dash), move2 (Slide) and primary (minigame action: Throw / Bomb pass). Dodgeball/Throw.lua:158-215 and KOTH/Input.lua:94-121 lose their private jumpButtonRect/layout code.
7. Camera: src/client/Movement/CameraFx.lua becomes the only writer of Camera.FieldOfView offsets and Humanoid.CameraOffset. Core's client shakeCamera (src/client/Core/init.client.lua:84-108) must call CameraFx.shake(trauma) instead of writing CameraOffset.
8. Optional collision group 'PD_SlideBody' (non-colliding with Default), registered by server Movement via PhysicsService. It is used only by the owning client during the slide pose.
9. Movement_JumpFx switches from RemoteEvent to Net.unreliable (same name). Server and client must change together.
10. Knockback.lua (Core-owned, not frozen) needs:
   - TUMBLE_SPEED 5→3.
   - AlignOrientation recovery with no +1.5 Y snap.
   - Freefall when airborne.
   - A local hit sound.
   Movement only watches Stunned true→false, so no new API is needed.
11. ARCHITECTURE.md cleanup: drop 'dash+cooldown bar' and PlayerGui.MovementHUD.DashCooldownBar (grep shows no external references). Add gamepad bindings (Dash ButtonX/R1, Slide ButtonB/L1) and the UI Data.keyHint gamepad glyphs.
12. Place setting (Studio, not in repo): set Avatar Type to R15 in Game Settings. The code keeps R6 support, but the slide tackle reads best on R15. StarterPlayer properties set by server Movement at boot: AutoJumpEnabled=false, CameraMaxZoomDistance=45, CameraMinZoomDistance=6.

**qualityNotes**: - Joint ownership is fragile. Pose writes the root C0 in PreRender, JumpFx writes the root Transform in PreSimulation through a new connection on every jump, and the Core shake and Pose both write CameraOffset. Consolidate into one PreSimulation 'pose stack' (lean C0 layer, slide Transform override, flip) and one CameraFx.
- Controller rewrites root.CFrame every frame while sliding (faceDirection, Controller.lua:332). That is a teleport-style write on a physics root; use AlignOrientation with RigidityEnabled instead.
- MOVER_FORCE 1e7 (Controller.lua:40) is excessive. Dashing into thin parts at about 100 studs/s risks tunnelling and jitter; scale it to AssemblyMass*6000.
- Effects.ghost (Effects.lua:113-151) clones every body part of every rig on each dash (about 15 Instance clones and 15 tweens per observer per dash). Pool 1-2 ghost models per rig. Effects.isGrounded allocates a RaycastParams on every call (every 0.1 s per remote rig); cache one.
- The JumpFx relay sends every jump and landing reliably to all other players (12 bunny-hopping players means hundreds of events per second). Switch to Net.unreliable.
- Server Movement has no remote rate limits. Dash rejects reply on every call.
- Hud's touch layout loop is a forever task.wait(1) loop; make it event-driven (JumpButton AbsolutePosition/Size changes plus CAS button recreation).
- Unverifiable here, check in Studio: (a) the R15 Root C0 Y offset, which determines whether the physical HipHeight drop reaches the MIN_HIP_HEIGHT cap (root about 1.25); (b) whether the R15 HipHeight restore at slide end briefly lifts the character, which would trigger a spurious Landed ring and Movement_JumpFx 'Land' after each slide; (c) the place's actual RigType (check Players.LocalPlayer.Character.Humanoid.RigType in Play).
- Brief #16 ('fell in water but got teleported back') is very likely not a movement bug. King of the Hill is a score-kind minigame, and Context.lua:57-58 respawns score-kind players after a fall by design. Debug_NoEliminate also respawns. Bomb Tag should be survival-kind, so falls eliminate.
- Tutorial.lua:38 completes the Dash step on RightShift even though RightShift does not dash; it is fixed by binding RightShift.
- Selene/stylua must run after the rewrite. Do not use per-frame Instance.new in the dust code; emit from pre-made emitters by setting Rate, as Effects already does.
