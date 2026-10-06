# Party Dash v2: game design spec

Author: senior game designer pass. Scope: what to build and the exact numbers. File:line references point at `review/party-dash @ 62586fa`. "MUST" means build it tonight and get it to pass. "NICE" means do not start it tonight. Section 10 has the priority list.

---

## 0. Design pillars (hard rules for every builder)

1. **Readable in one second.** During play, no on-screen instruction is longer than 4 words. Shapes, colors and generated icon art carry the meaning. Emoji icons go away everywhere: `UI/Data.lua:24-30`, `Economy/Rules.lua:29-34` and `Cosmetics.lua` win-effect icons all become image assets (art list in section 12).
2. **A reward moment at least every 30 s.** Every round ends with a coin breakdown that counts up, coins that fly to the counter, and something that fills (round-streak bar, gift timer, XP bar).
3. **Death to the next fun action in 3 s or less.** The death panel offers Spectate, Lobby or Revive. The lobby always has something to do.
4. **Short loop.** Rounds last 45-100 s. A full cycle (lobby to lobby) takes about 2 minutes or less.
5. **Fair.** Robux buys cosmetics, coins, convenience, one capped revive and small capped upgrades. XP comes from base coins before any multiplier, so the Level leaderboard cannot be bought.
6. **Precision over breadth.** Only the MUST list in section 10 gets built tonight. Each piece must pass before anything NICE starts. The owner's own words: "did everything, nothing precisely" is the failure mode.

Why a kid plays one more round:
- They choose the next game (vote).
- The round-streak multiplier climbs to x1.5.
- KO and MVP credits make them feel strong.
- The playtime gift timer is always about to pop.

Why they come back tomorrow:
- The daily chest calendar (streak resets if they miss a day).
- The free daily wheel spin.
- The group chest.
- "First win of the day +100".
- The Galaxy Comet countdown.
- Leaderboards in the lobby.

---

## 1. Core loop

### 1.1 Phase timeline (Config values)
| Phase | Now | v2 | Config key |
|---|---|---|---|
| Lobby | 15 s | **20 s** (brief #14) | `LOBBY_TIME` (Config.lua:9) |
| Roulette (vote reveal) | 5 | **4** | `ROULETTE_TIME` |
| ModifierRoulette (every 5th round, unchanged) | 4 | **3** | `MODIFIER_ROULETTE_TIME` |
| Intro | 4 | **3** | `INTRO_TIME` |
| Countdown | 3 | 3 | `COUNTDOWN_TIME` |
| Round | open | target 45-100 s | `INTENSITY_RAMP_SECONDS` 35 -> **30** |
| End (results on the map) | 6 | **5** | `END_TIME` |

- **Sudden death**: at 120 s of round time, Core announces "SUDDEN DEATH!" and `ctx.intensity()` is multiplied by 2. This lives in Core's `Context.lua`, which is not a frozen file. `SAFETY_ROUND_LIMIT = 300` stays as the bug fuse only.
- Overhead between rounds: 20 + 4 + 3 + 3 + 5 = 35 s.

### 1.2 Permanent lobby (architecture change; it unblocks #17, #26, the wheel and the chests)
- Today `LOBBY_CENTER == ARENA_CENTER` (Config.lua:24,26). The lobby is destroyed every round (`RoundLoop.lua:296 Places.destroyLobby()`) and rebuilt in `returnToLobby` (`RoundLoop.lua:170-185`). As a result:
  - there is no lobby to "go back to" during a round;
  - eliminated players sit on the stands (`RoundLoop.lua:271-272`);
  - the Solo board has to re-mount every round (`Solo/Board.lua` header).
- **v2:**
  - Set `Config.LOBBY_CENTER = Vector3.new(-460, 50, 0)`. That is at least 350 studs from the arena, with the same sea and sky backdrop.
  - Remove any `World.lua` floating island or islet within 130 studs of the new lobby (island list at `World.lua:177-188`, islets at :195-202).
  - `Places.buildLobby()` runs once in `Places.init`. It is never destroyed, so drop the per-round destroy and rebuild.
  - Stands (`Stands.lua`) are no longer a destination. Keep the module but do not build it.
- Survivors teleport back to the lobby spawns at the end of End. Eliminated players go there immediately (1.4).

### 1.3 Join square and vote (#26, plus the "choices" ask)
- **PLAY ZONE**: a 30x30 stud pad at the lobby center (layout in 1.7).
  - Every 0.2 s the server checks whether each player's HumanoidRootPart is inside the zone box: |x|,|z| <= 15 from the pad center and 0-10 studs above the pad.
  - Result goes to Player attribute `Queued` (bool) and GameState `QueuedCount` (number).
  - A queued player gets a green check bubble over their head and a HUD pill "YOU'RE IN!".
- **Lobby end rule:**
  - When the 20 s timer reaches 0 and `QueuedCount == 0`: stay in Lobby, add 20 s and set GameState `LobbyHold = true`. The HUD shows a bouncing arrow toward the square and "Step in to play!".
  - Otherwise, resolve the vote, then Roulette.
- **Participants**: players with `Queued == true` at lobby end, capped at 12, longest-waiting first. Reuse the `pickParticipants` tiebreak (`RoundLoop.lua:80-98`) over the queued list instead of `eligible()`.
- **Vote:**
  - At Lobby start, Core picks 3 options at random from the visible pool, excluding last round's game. Written to GameState `VoteOptions` (CSV).
  - Queued players see 3 cards bottom-center: card art, name, vote count and voter avatar bubbles. Tapping a card fires remote `Core_Vote(minigameId)`.
  - Server validation: the id is in `VoteOptions`, the player is Queued, and at most 4 calls per second.
  - Results go to Player attribute `Vote` and GameState `VoteCounts` (JSON `{id: n}`). Leaving the square clears your vote.
- **Eligibility**: a minigame may declare `minPlayers` (optional definition field; `Contracts/Minigame.validate` ignores unknown fields). Core mirrors it to `MinigameInfo.<Id>.MinPlayers`. Bomb Tag = 3, everything else 1. When `QueuedCount < MinPlayers` the card is greyed out and shows "3+ PLAYERS".
- **Resolution**:
  - The eligible option with the most votes wins. A tie is broken at random among the tied options. No votes means a random eligible option.
  - Eligibility is re-checked with the final queued count.
  - The Roulette reel cycles only the 3 options (`makeReel(..., candidates = options)`, `RoundLoop.lua:127`) for 4 s, slows down while passing the runner-up, then lands on the winner.
- With a single player in the server, their vote always wins. Rounds still run (`MIN_LOBBY_PLAYERS = 1`), with no Bomb Tag.

### 1.4 Elimination flow (#16, #17, #28)
- **t = 0.**
  - KO moment (splash, explosion or bonk FX plus sound).
  - Card "OUT! #5 of 9".
  - `Announce.big` already exists (`RoundLoop.lua:278`).
- **t = 1.0 s.**
  - The character teleports to a lobby spawn (`Places.sendToLobby`).
  - The **death panel** slides up (bottom center) with three buttons:
    - **SPECTATE**: the primary button, and the auto choice after 6 s. Camera only; the character stays safe in the lobby. Sets Player `Spectating = true`. Reuse the Spectate bar (`src/client/Spectate/init.client.lua`, Q/E to cycle) and add a **LOBBY** button on the bar.
    - **LOBBY**: closes the panel and gives the camera back.
    - **REVIVE 19 R$**: only shown when eligible (rules below), with a 10 s radial timer on the button.
- Lobby players can watch at any time with a "WATCH LIVE" HUD button during Round, or the LIVE TV prompt in the lobby.
- **Revive rules:**
  - Survival rounds only, and only when there were 3 or more participants.
  - At grant time at least 2 *other* players are still alive, so a 1v1 final is never bought.
  - At most 1 revive per player per round.
  - The offer window is 10 s after elimination (Player attribute `ReviveUntil`, server time).
  - **On grant:**
    - The player comes back on a random spawn with Character attribute `SpawnShield` for 3 s (protection rules in 3.0).
    - Their placement entry is removed.
  - **Granted but no longer eligible** (the round ended, or it is the final 2):
    - profile `reviveTokens += 1`;
    - toast "Revive saved for next round!";
    - the next death panel shows "REVIVE (1 FREE)".
    - Never lose a purchase.
  - Core API: `Context:_revive(player)`. Context is Core-owned, not a frozen contract.

### 1.5 Reward moments per round
- **KO credit**:
  - A minigame that lets one player hit another sets these Player attributes on the victim: `LastHitBy` (attacker UserId) and `LastHitAt` (`workspace:GetServerTimeNow()`).
  - Core's `onEliminated` credits the attacker when `LastHitAt` is within 4.0 s.
  - Credit = attacker toast "You knocked out Sam! +5" and a kill feed line "Alex [bat icon] Sam".
  - Pass the attacker to Economy as an extra `killer` field in the `PlayerEliminated` info table. That is additive and does not break the frozen `Signals` contract.
  - Sources: Spin bat, Dodgeball golden ball, Bomb Tag (the last passer of the bomb that exploded).
  - Paid KOs are capped at 5 per round.
- **MVP**: the most KOs in the round (at least 1). Ties go to the better placement. +10 coins and an MVP ribbon on the results card. No MVP when nobody got a KO.
- **First win of the day**: +100 coins, flat, with the banner "FIRST WIN OF THE DAY!". New profile field `firstWinDay` (UTC day).
- **Round streak (session hook, ref1 "Streak Rewards" bar)**:
  - Counts consecutive main rounds you took part in.
  - Coin multiplier by streak: rounds 1/2/3/4/5+ = x1.0 / x1.1 / x1.2 / x1.3 / x1.5.
  - It resets when a round starts while you are in the server, not InSolo and not a participant, and when you leave.
  - Shown as a top-right bar with 5 segments and "x1.3". Player attribute `RoundStreak`.
- **Win streak** (already in leaderstats as `Streak`, `Results.lua:46-63`):
  - The winner gets +5 x (streak - 1), max +20.
  - Feed line "Alex: 3 WIN STREAK!".
  - Flame icon on the nameplate when the streak is 2 or more.

### 1.6 Coin formula v2 (replaces `Rules.roundCoins`, Rules.lua:92-110)
```
base  = 5 (played)
      + floor(survivedSeconds / 10)
      + placement   -- participants >= 3: 1st 25, 2nd 12, 3rd 6; exactly 2: winner 25
      + 5 * min(KOs, 5)
      + (MVP and 10 or 0)
      + winStreakBonus   -- 5 * (streak - 1), max 20, winners only
coins = floor(base * roundStreakMult * (modifierRound and 2 or 1)
              * (has2xPass or boostActive and 2 or 1)   -- one 2x only, never x4
              * (VIP and 1.2 or 1))
      + (firstWinToday and 100 or 0)
XP    = base + 10   -- before multipliers; today Rewards.grant (Rewards.lua:38-47) gives XP = granted coins
```
Typical: an average player in a 6-player round earns about 20 base. At a x1.3 streak that is about 26 coins per round, roughly 900-1,000 coins per hour before gifts and chests. All cosmetic prices in 6.1 are sized for this rate.

### 1.7 Lobby layout: making 20 s fun (brief #26, #32)
Island with walkable radius 90 (`Lobby.RADIUS` 60 -> 90). Voxel style like ref1, ref2 and ref4: brick-textured grass top, brick dirt cliffs, sand ring, turquoise cartoon water. Positions are studs from `LOBBY_CENTER`, with +Z = north. Every interaction is a ProximityPrompt with HoldDuration 0, MaxActivationDistance 10 and one-word ActionText.

| # | Feature | Position | Spec |
|---|---|---|---|
| 1 | PLAY ZONE | (0,0,0), 30x30 | 0.4-stud pad in a white and green checker. Rim of 24 Neon chase-light bulbs: green while the timer runs, yellow at 5 s or less. Floor arrow decals lead from the spawns. Billboard 18x6 at y=14: "NEXT GAME 0:14 - 6/12 READY". |
| 2 | Spawns | 12 on an arc r=22 at z -18..-26 (south) | All face the zone. This is the return point after rounds and the join point. |
| 3 | Wheel of Fortune (#29) | (0,0,42), diameter 22, faces south | Physical wheel that mirrors every UI spin and shows the spinner's name. Prompt "SPIN" opens the wheel panel. The rim lights chase green while the viewer has a free spin. |
| 4 | LIVE TV | (0,12,24), 24x13 SurfaceGui | During Round: "LIVE - BOMB TAG - 4 ALIVE" plus the names, and a "WATCH" prompt. During Lobby: the 3 vote options and their counts. |
| 5 | Shop stall | (46,0,10) | Red and white awning like ref2 "Boost Shop". A podium with a dummy wearing the Galaxy Comet trail and circling. Prompt "SHOP". |
| 6 | Leaderboard wall | (-48,0,10), facing east | 3 boards, 16x10 each: TOP WINS / TOP LEVEL / SOLO TOP 10 (the existing `LeaderboardAnchor`). |
| 7 | Daily chest (#27) | (24,0,-40) | Gold chest with a "!" bubble when claimable. Prompt "OPEN" opens the calendar panel. |
| 8 | Group chest (#27) | (36,0,-32) | Sign like ref1: "GROUP CHEST - Like the game & join the group!". |
| 9 | Trampolines | (-30,0,-36), (-40,0,-26), (-22,0,-46), radius 5 | Launch Y velocity 110 (about 31-stud apex), boing SFX, 0.3 s per-player cooldown. |
| 10 | Solo portal | (-40,0,38), 12x14 arch | Prompt "SOLO" opens the existing Solo picker. |
| 11 | Beach and palms | sand r 80-90, water beyond | Cartoon wave Texture (generated), scrolled on the client. |
| 12 | VIP island (NICE) | (52,6,46) | Gold platform with a gate that checks `Pass_VIP`. |
| 13 | Obby ring with a chest (NICE) | around the island | |

Dash and slide stay enabled in the lobby. In the 20 s a kid can bounce on a trampoline, spin the free wheel, open the chests or check the boards, and still reach the square: every spot is within 50 studs, about 2.5 s at WalkSpeed 20.

### 1.8 Return hooks summary
Daily chest calendar (5.4), free daily spin (5.3), group chest (5.5), playtime gifts (5.6), first win of the day (1.5), Galaxy Comet countdown (5.7), leaderboards (7). NICE later: 3 daily quests.

---

## 2. BOMB TAG (replaces King of the Hill; brief #10)

### 2.1 Definition
- id `BombTag`, displayName `BOMB TAG`, rules `Don't hold the bomb when it blows!`
- keys `{ "Dash", "Jump", "Slide" }`, kind `survival`, `soloCapable = false`, `minPlayers = 3`
- Accent: add `Theme.MinigameColors.BombTag = Color3.fromRGB(255, 90, 40)` (lead-owned Theme). Remove the `KingOfTheHill` entry (Theme.lua:28).

### 2.2 Rules and timeline
1. **t = 0 (GO):** "SCATTER!" and no bomb yet.
2. **t = 1.0 s:** a highlight flickers across random players (client FX).
3. **t = 2.0 s:** the bomb lands on a random alive player.
   - Never the same player who got the first bomb in the previous Bomb Tag round on this server.
   - The holder sees the banner "YOU HAVE THE BOMB!". Everyone else sees the top pill "[bomb] ALEX".
4. **Fuse:** 10.0 s per bomb, counted from the assignment. Passing does **not** reset it.
5. **Pass**, checked by the server on Heartbeat with no client remote, so there is nothing to exploit:
   - The holder's root and a target's root are within 5.0 studs horizontally and 4.5 studs vertically.
   - The target is alive, holds no bomb and has no `SpawnShield`.
   - The target is not the previous holder within 1.0 s (no tag-back).
   - A new holder cannot pass on for 0.35 s.
6. **Holder:**
   - WalkSpeed x1.2 (24 at the base 20, multiplied on top of modifiers).
   - Red `Highlight` with `DepthMode = AlwaysOnTop`.
   - Bomb model welded 3.5 studs above the head on the server, so it replicates for free.
7. **Explosion at fuse end:**
   - The holder is eliminated with reason `"bomb"`.
   - A shockwave hits everyone else within radius 14: knockback power 70, stun 0.35. It is never lethal by itself.
   - The holder's body is launched up (power 180).
   - KO credit (+5) goes to the last player who passed this bomb, if anyone did.
8. **Breather:** 2.0 s with "NEXT BOMB IN 2...", then a new bomb goes to a random alive player without a shield (brief: "the next person gets the bomb").
9. **Bomb count:** the target is 2 bombs while 7 or more players are alive, otherwise 1. The second bomb's fuse is offset by +1.5 s so explosions never coincide. A holder cannot receive a second bomb.
10. **Edge cases:**
    - Holder falls off after a shrink: instant splash explosion and elimination, then the normal breather.
    - Holder leaves: the bomb moves at once to a random player with fuse = max(remaining, 5 s).
11. **End:** last one alive wins (Context `lastStanding`). Revive is allowed under the rules in 1.4. A revived player never arrives holding a bomb.

Estimated round length (fuse plus breather is about 12 s): 3 players about 26 s, 6 players about 62 s, 12 players about 100 s (two bombs early).

### 2.3 Map "BOOM PARK" (center = `ctx.center`, floor top y = 0, +Z = north)
The floor is a 100x100 square split into rings that drop as the game goes on:
- **R0** = |x| and |z| at most 30. Permanent.
- **R1** = 30-40. Drops when 2 players are alive.
- **R2** = 40-50. Drops at the 2nd explosion.
- When 2 players are alive, every remaining outer ring drops together.
- A drop is warned for 3 s (tiles flash red and white, rumble SFX), then the tiles unanchor, fade and fall.
- `KillY = center.Y - 10`, with water below.

| Element | Where (x,z) | Numbers |
|---|---|---|
| Floor | -50..50 | 10-stud checker tiles, grass (110,215,95)/(92,196,78) like ref4 |
| Fence | outer border (part of R2) | 3 high, orange-brown checker (214,128,62)/(176,98,46) like ref4 |
| Fountain dome | (0,0) | radius 5, height 5. Smooth dome cap so nobody can camp on it. It is the chase loop to run around. |
| Sweeper | around the fountain | Arm from r 5.5 to 16, bottom 0.6, top 1.8 (jumpable). 1.0 rad/s; reverses every 15 s after a 1 s blink. Knockback 45, stun 0.25. Red and white stripes. |
| Crates | (+-18, +-18) | 6x6x6 (climbable: jump apex 6.9) |
| Low walls | (0, +-24) along X, (+-24, 0) along Z | 14 long, 4 high, 2 thick, orange checker |
| Tunnel hill | R1 north: x -12..12, z 30..40 | Hill 8 high with 30-degree ramps. Tube through it 6 wide x 3.0 high: you must slide (the Sliding hitbox fits, standing does not). |
| Towers and bridge | R1 south: towers 8x8x10 at (+-20,-35) | Stairs on the outer faces. Bridge 32 long, 6 wide, at y 10, with rails. Purple (150,100,255) with white trim. |
| Jump pads | (+-10,-28) | Yellow, radius 2.5. Launch Y 70 plus 18 toward the tower (apex 12.5 lands on the 10-high bridge). 0.8 s per-player cooldown. |
| Corner bounce pads | R2 (+-44,+-44) | Y 80, 0.8 s cooldown |
| Speed strips | R2 east and west: x +-45, z -30..30 | 4 wide, +12 WalkSpeed for 1.2 s, scrolling arrow decal |
| Spawns | 12 on a circle r 24 (R0), facing the center | |

### 2.4 Tension: visuals and audio
- **Tick sound**:
  - 3D on the bomb (RollOffMaxDistance 90), plus 2D for the holder.
  - Interval 1.0 s with 10-6 s left, 0.5 s at 6-3 s, 0.25 s at 3-1 s, then a continuous beep in the last second.
  - Pitch +5% per second under 5 s.
- **Bomb body**: blinks black/red at the tick rate. The fuse spark ParticleEmitter grows as time runs out.
- **Countdown above the bomb**: BillboardGui, 3 studs, AlwaysOnTop. White above 5, yellow 5-3, red under 3, with a 1.0 -> 1.25 pulse.
- **Holder's screen**:
  - Red edge vignette: ImageTransparency 0.7 -> 0.25 as the fuse runs down.
  - FOV +4 under 3 s.
  - Camera shake of 0.15 studs under 2 s.
- **Everyone**: top pill per bomb with the bomb icon, holder name and fuse to 0.1 s, colored on the same ramp.
- **Pass**:
  - "TAG!" pop text at the contact point and a whoosh SFX.
  - New holder: red screen flash 0.15 s.
  - Passer: green flash and "PASSED!".
- **Explosion**:
  - Cartoon burst: about 40 orange and yellow particles, a white shock ring, smoke puffs.
  - Boom SFX.
  - Camera shake for anyone within 30 studs.
- **Music**: Bomb Tag gets its own tense-funny track. NICE: a low-pass dip in the last 3 s of a fuse.

### 2.5 Fairness
- 2-12 players: the second bomb keeps 12-player rounds near 100 s. The ring drops stop camping in small games.
- With fewer than 3 players the card is disabled (2 players would mean a 12 s coin flip).
- **No tag-back** (1.0 s) and **catch delay** (0.35 s) stop ping-pong.
- The server-side pass radius of 5.0 studs gives latency forgiveness without letting tags happen from across a wall.
- The holder's +20% speed plus Dash means a fleeing player gets caught in the open within about 3-6 s. Obstacles, the tunnel (slide) and the fountain loop let skilled kids juke.
- Not Solo: it needs people.

### 2.6 Contract
- Map attributes: `BombHolders` (CSV of UserIds), `Explosions`, `Passes`.
- Character attributes: `HasBomb` (bool), `BombFuseEnd` (server time).
- Remote `BombTag_Fx` (server to all clients, keyed by the session/map). Events:
  - `"assign"` {holder, fuseEnd}
  - `"pass"` {from, to, pos}
  - `"boom"` {userId, pos}
  - `"shrink"` {ring, at}
- No client-to-server remote.
- Session rules as in ARCHITECTURE: no module-level state, everything relative to `ctx.center`, `ctx.knockback` only.

---

## 3. Existing minigames: v2 changes

### 3.0 Shared rules (all minigames)
- **Everything is survival.** A fall below KillY eliminates you; there are no respawns apart from a paid revive. Default KillY = floor - 10 so falls end fast. Falling into water plays a splash FX and "SPLASH!".
- **Hit forgiveness ("favor the jumper")** fixes the #22 "I jumped and still got hit" bug. Laser and wall hits use the same check.
  - **Why it happens:** characters are client-owned and their position reaches the server about one ping late. Clients render the bars, lasers and walls from `GetServerTimeNow()`, so a kid jumps on time on their own screen, but the server still holds their old grounded position.
  - **The fix** is a Core module `Forgive`:
    - It keeps 1.0 s of Heartbeat samples per alive player: `(serverTime, rootY, Sliding, HumanoidState)`.
    - A hazard that detects a crossing at server time T calls `Forgive.judge(player, T, clearTest)`.
    - The verdict is taken at `T + clamp(player:GetNetworkPing(), 0.05, 0.25) + 0.03`.
    - If any sample in `[T - 0.05, verdictTime]` passes `clearTest`, there is no hit.
- **SpawnShield** (Character attribute = server time until it expires): every hazard, knockback and bomb pass ignores a shielded player.
- **No words on hazards**, ever.

### 3.1 Laser Tracer (#13, #15)
- **Remove the center pillar**:
  - delete `buildHub` (`LaserTracer/Arena.lua:171`, called at :279) and the hub rings;
  - fill the center disc with normal tiles;
  - drop the hub-ray "sweep" pattern (`Motion.lua:26 HUB_RADIUS`).
- **Random motion.** New deterministic patterns, encoded in `State` so server and client stay in sync:
  - **rotor**: an infinite line through a random pivot (px,pz) with |p| <= 14, rotating at s = +-0.45 * I^0.6 rad/s (cap 1.5). The visible beam is the chord of the rim circle (r 42.6).
    - From intensity 1.8 it reverses at random times every 4-8 s.
    - Each reversal is telegraphed 0.6 s ahead: the beam flickers white 3 times.
    - Up to 3 reversal times are encoded in State.
  - **chord** (the existing "slide" pattern): uniform random heading over 0-360 degrees, crossing at `Director.slideSpeed`.
  - **bouncer** (intensity 1.6 and up): a chord that reflects at offset +-34, 1-2 times.
  - Add `px, pz, r1, r2, r3` to the `Motion.encode` format.
- **Director schedule:**
  - t = 0.6 s: rotor 1 (LOW).
  - t = 5 s: rotor 2 (HIGH), pivot on the opposite side.
  - Chords from t = 7 s, every `slideInterval`. From intensity 1.6, bouncers replace 1 in 3 chords.
  - Rotor 3 at intensity 2.6.
  - `Director.MAX_LASERS` 9 -> 6.
  - Every heading, pivot, speed, direction and reversal time comes from the session's `Random`, so no two rounds open the same way.
- **Fairness (replaces the hub-based rules in the Director header):**
  - Before a new laser L activates, simulate 0-3 s ahead in 0.1 s steps on a 4-stud floor grid (r <= 42).
  - If any point is crossed by L and by a live laser M of the *other* kind within 0.9 s, make L the same kind as M.
  - If it still conflicts, delay L by 1 s (up to 3 retries), else drop it.
  - The `WARN_TIME 1.1` telegraph stays.
- **Both red, and you can see which is low and which is high (#13).** `Motion.COLORS.high` (Motion.lua:37, currently cyan) becomes red as well:

| | LOW (jump it) | HIGH (slide under) |
|---|---|---|
| Height | 1.6 (`Motion.HEIGHT`, :28) | 4.6 |
| Beam | **thick**, diameter 0.9, solid red Neon (255,35,35) with a white core of 0.3 | **thin**, diameter 0.55, **red and white segments** of 1.5 studs scrolling at 6 studs/s |
| Floor cue | bright red glow strip right under the beam: width 2.4, Neon, transparency 0.45, up-chevrons scrolling | thin dashed dark-red shadow line: width 0.5, transparency 0.6, down-chevrons |
| End caps | short red ground posts (1.6 tall) | hovering drones at 4.6 |
| Telegraph | dashed line on the floor plus a big up-arrow icon | dashed line at head height plus a big down-arrow icon |

- **Floor**: cool mid-tone checker, lilac-grey (175,180,215)/(140,145,190), with a white rim. Red pops against it, and there is no cyan anywhere (the sea is cyan).
- Hits keep `Hit.JUMP_CLEAR 4.2` (`LaserTracer/Hit.lua:19`) and go through `Forgive`.

### 3.2 Hole in the Wall (#21)
- Delete the labels and type colors: `WallView.lua:22-26` (`RUN!/JUMP!/SLIDE!`) and the `label()` call (:89). All hole rims become plain white trim, 0.4 studs.
- **Shapes on a 1-stud grid.** The wall is 66 x 14 (`Patterns.lua` WALL_WIDTH / WALL_HEIGHT).
  - Each hole is a shape from the catalog below.
  - The client merges the cut cells into rectangles (greedy row merge), at most 40 parts per wall.
  - The server pass test uses each shape's `pass` rectangles. The body rectangle (x +-0.9, feet up to feet + body height, using `Pass.lua`'s sliding height) must fit inside one of them.
  - The shape itself says jump, slide or run, with no text.

| Shape | Size (w x h) @ bottom | Pass rect | Implied move | Unlocked at intensity |
|---|---|---|---|---|
| DOOR | 8x8 @0 | same | run | 1.0 |
| WIDE | 12x8 @0 | same | run | 1.0 (until 1.6) |
| ARCH | 8x9 @0, 2-cell rounded top | 8x7 @0 | run | 1.0 |
| CROSS | 4x10 @0 plus a 10x3 bar @4 | 4x10 @0 | run | 1.0 |
| STAIR | 9 wide @0, stepping down to 3 wide @9 | 5x6 @0 | run | 1.0 |
| WINDOW | 8x6 @4.5 (matches the HIGH hole, Patterns.lua:21) | same | jump | 1.3 |
| PORTHOLE | circle diameter 7 @3.5 | 4.9x4.9 @4.5 | jump | 1.3 |
| SLOT | 9x3 @0 (matches the LOW hole) | same | slide | 1.3 |
| TWIN | two 4x8 doors, 3 apart | each door | run (aim) | 1.6 |
| DIAMOND | rotated square, side 7 @2 | 5x5 @3.5 | jump | 2.2 |

- **Per wall**: 1-3 holes (existing `tuning.holeCount`), shapes drawn at random from the unlocked set. Two walls in a row never have the same set of shapes. `HOLE_EDGE_MARGIN 1.5` stays.
- **Tutorial walls**: `makeHoles` walls 1-3 still teach, through shapes only: DOOR/WIDE, then WINDOW, then SLOT.
- **Colors**:
  - Walls cycle through 6 bright solid colors (pink, blue, green, orange, purple, yellow) with a slight voxel bevel.
  - Floor: sand checker (245,205,120)/(230,180,95) with an orange rim.
  - The floor warning (`TELEGRAPH 1.5`) stays as a color stripe only.
- Wall hits go through `Forgive`.

### 3.3 Spin (#22)
- **Bat for everyone:**
  - Move KOTH's `src/server/Minigames/KingOfTheHill/Bat.lua` and `BatTool.lua` to `src/server/Combat/`.
  - Move `src/client/Minigames/KingOfTheHill/Input.lua` to `src/client/Combat/BatInput.lua`. It switches on when the equipped Tool has attribute `PD_Bat`.
  - Spin gives every participant a bat at Intro and removes it at `stop()`.
  - Swing: LMB, F, or the mobile SWING button (icon). Cooldown 1.0 s, reach 7.5 studs, 75-degree cone.
  - Knockback 120 x (1 + 0.06 x BatPower level), stun 0.6.
  - A hit sets `LastHitBy` / `LastHitAt`. `Cos_BatColor` applies.
- **Pillar hopping (bat fights) is possible but risky:**
  - Gap between pillar tops = 2 x 36 x sin(15 deg) - 9 = 9.6 studs (`BarMath` RING_RADIUS 36, 12 pillars, TOP_RADIUS 4.5).
  - A running jump covers about 10.6 studs and a dash 18.
  - Keep this geometry.
- **Ledge exploit, root cause:**
  - The pillar `Foot` disc (`Spin/Arena.lua:111`) is radius `BODY_RADIUS + 1`, so it leaves a 1-stud ledge with its top at -24.
  - `KILL_DEPTH = 24` (:32), so a player standing on the ledge has their root at about -21, which is never eliminated.
  - `Hit.LOW_LIMIT = -5.5` (`Spin/Hit.lua:17`) means the bar never hits them either.
- **Ledge exploit, fix:**
  - `Foot` becomes `CanCollide = false`, or is removed.
  - `KILL_DEPTH` 24 -> **8**: any fall off a pillar is OUT within about 0.3 s.
  - Check that every part below the pillar tops except `Body` is non-collidable.
- **Jump still gets hit, fix:**
  - `Hit.CLEAR_HEIGHT` 1.4 -> **1.0** (:16).
  - `HALF_WIDTH` 2.0 -> **1.7** (:19).
  - Route the hit through `Forgive`.
  - The bar's look must match its hitbox: red and white candy stripes, with thickness equal to the hit band.
- **Solo bug (punchlist P10 note 4)**: the "bar incoming" warning only works while `InRound`. Also compute it when `InSolo`.
- NICE: eliminated players' pillars sink 30 studs over 2 s.

### 3.4 Dodgeball (small, MUST-lite)
- Golden ball every 8 s (now about 12 s); 2 golden balls while 6 or more are alive. A golden hit sets `LastHitBy` (KO credit).
- Bug from the punchlist (P5): the `PD_DodgeballClient` container stays in workspace after the round. Destroy it when the map goes away.
- NICE: court shrink and mobile aim assist (25-degree cone).

### 3.5 Remove King of the Hill
- After moving the bat, delete `src/server/Minigames/KingOfTheHill/` and `src/client/Minigames/KingOfTheHill/`.
- Update the references: `Theme.lua:28`, `UI/Data.lua:28`, `Shop/CosmeticsTab.lua:108`.
- It was the only `score`-kind game (`KingOfTheHill/init.lua:64`), so the score-kind respawn path is no longer reached by any game.

---

## 4. Controls and feel (#3, #11)
- **Slide = football slide tackle:**
  - Feet first, not the current head-first belly dive (`Pose.lua:25 SLIDE_PITCH = -78 deg` plus `Assets.SlidePose = Cartoony_Fall`, `Assets.lua:19`).
  - Procedural Motor6D pose in `Pose.lua`:
    - torso leans **back** 55 degrees;
    - lead leg straight forward with the hip flexed 80 degrees;
    - trailing leg tucked under with the knee bent 100 degrees;
    - trailing-side hand back on the ground, other arm forward and up.
  - Dust and grass-streak particles at the lead heel. Keep the SFX (`Assets.lua:23`).
  - Duration stays 0.75 s.
- **Slide cooldown 1.0 s, no bar:**
  - `Config.SLIDE_COOLDOWN` 0.4 -> 1.0.
  - Delete the "C SLIDE" chip (`Movement/Hud.lua:173-188`) and the slide button shade fill (:390-395).
  - The mobile slide button only drops to 45% opacity while cooling and pops (scale 1.15 -> 1) when ready.
  - The existing input buffer (`SLIDE_BUFFER 0.22`) remains, so an early press still slides.
- **Dash:**
  - Keep the 2.5 s cooldown and a small dash indicator: a radial ring on the mobile button, and on PC a compact pill at half the current bar size.
  - **Shift Lock conflict:** dash is LeftShift (`Controller.lua:469`), which Roblox Shift Lock also uses. Set `StarterPlayer.EnableMouseLockOption = false` and add **Q** as a second dash key.
- **Jump**: coyote time 0.10 s (you can still jump 0.1 s after walking off an edge) and a jump buffer of 0.12 s.
- **Mobile**:
  - Icon buttons (generated art), at least 84 px on phones and 1.15x on tablets: Jump (default), Dash above Jump, Slide to the left of Jump, ACTION (Swing/Throw) to the left of Dash.
  - No overlaps. A press scales to 0.9 and plays the click.
- **Camera**: default distance 18, FOV 72, dash FOV kick +6 for 0.25 s, small shake on hits and explosions. Shake can be turned off in Settings.

---

## 5. Monetization

### 5.1 Product list (Robux)
| Key (Config.PRODUCTS / GAMEPASSES) | Name | Price | Grants | Limit |
|---|---|---|---|---|
| `WheelSpin1` (new) | 1 Spin | **9 R$** (#29) | 1 spin token, auto-spins | |
| `WheelSpin5` (new) | 5 Spins | **39 R$** ("SAVE 13%", which is true: 5 x 9 = 45) | 5 tokens | |
| `Revive` (new) | Revive | **19 R$** (#28) | revive now, or a token if no longer eligible | 1 per round |
| `StarterPack` (new) | Starter Pack | **49 R$** (#30) | 1,000 coins + "Starter Spark" trail (exclusive) + 2x coins for 30 min | once per account |
| `GalaxyTrail19` (new) | Galaxy Comet, Welcome Deal | **19 R$** (#31) | Limited trail | first 48 h after first join |
| `GalaxyTrail199` (new) | Galaxy Comet | **199 R$** | same trail | Season 1 only |
| `Coins500` | 500 coins | **25 R$** | | |
| `Coins1500` | 1,500 coins ("+15%") | **65 R$** | | |
| `Coins5000` | 5,000 coins ("BEST VALUE +40%") | **179 R$** | | |
| `Upgrade*` (existing 4) | +1 upgrade level | **25 R$** | secondary button in the Upgrades tab only | cap Lv 5 |
| `DoubleCoins` (pass) | 2X COINS | **149 R$** | x2 round coins forever | |
| `VIP` (pass) | VIP | **249 R$** | gold nametag, VIP Gold trail, +1 free spin per day, +20% coins, (NICE) VIP island | |

- Product ids stay 0 until the owner creates them in Creator Hub. Add a display table `Rules.PRODUCT_INFO[key] = { price, title, ... }`:
  - the UI shows that price when the id is 0;
  - a tap on an unconfigured product shows the toast "Coming soon!";
  - when the id is set, `RobuxTab` already fetches the live price, so prefer that.
- Never refuse a receipt: unknown or expired products still grant (pattern in `Market.lua:22`).

### 5.2 Where each offer appears (ref1 / ref3 / ref5)
| Surface | When | Content |
|---|---|---|
| **Top offer bar**, 3 colorful buttons with price under them (ref1 "NUKE! 9") | Lobby/Waiting only | `SPIN! 9 R$` (red); `STARTER PACK 49 R$` (yellow; once bought becomes `2X COINS 149`); `GALAXY TRAIL 19 R$` with a live timer (purple; after the deal `199`) |
| **Left 2x2 grid** (ref1 Items/Shop/Index/Daily) | always; shrinks to 1 row during Round | SHOP, ITEMS, DAILY ("!" when ready), SOLO. **Gift pill** above: "[gift] 03:12", turns green "FREE!" and pulses when ready (ref1/ref3) |
| **Right column** (ref1 icons with timers) | lobby | Group chest ("!"), Wheel (free spin badge), VIP (if not owned), 2x boost timer (if active) |
| **Death panel** | after elimination | REVIVE 19 R$ |
| **Results card** | End | Coin breakdown. Every 3rd round, if the player lacks 2x: "+26 more with 2X COINS" chip (an honest computed number) |
| **Shop, Featured tab** (ref5) | shop | Galaxy deal card: "New!" tag, "LIMITED", countdown "1d 23h 12m 09s", ~~199~~ **19 R$**. Starter Pack card. Spin bundles with an **ODDS** button. |
| **Wheel panel** | wheel prompt or top button | Big wheel; `SPIN (FREE)` or `SPIN 9 R$` / `5 SPINS 39 R$`; token count; **ODDS** |
| **Not enough coins** | tapping an unaffordable item | "Need 320 more" plus `[Get coins]` to the coin packs |

Popup etiquette:
- At most 1 automatic popup per 5 minutes, only in the Lobby phase, never in the first 60 s of a session.
- The close X is at least 64 px.
- The Starter Pack auto-shows after the player's 2nd finished round, and once more 24 h later: 2 auto-shows ever.

### 5.3 Wheel of Fortune (#29)
- **Free spin sources:** 1 per UTC day for everyone, +1 per day for VIP, calendar Day 3, playtime gift #3, every 5th level.
- Tokens live in profile `spins`.
- **Spin flow:**
  - The client sends `Economy_Spin()`.
  - The server checks the token, rolls the prize and grants it.
  - The server replies `Economy_SpinResult(sliceIndex, prize)`.
  - The client animates the wheel to that slice (4 s, ease-out) with a tick per slice and a win jingle.
- **Slice arc sizes are proportional to the odds** (honest):

| # | Prize | Odds |
|---|---|---|
| 1 | 50 coins | 30% |
| 2 | 100 coins | 22% |
| 3 | 250 coins | 14% |
| 4 | 2x Coins (15 min) | 12% |
| 5 | +1 Free Spin token | 8% |
| 6 | Wheel trail: Lightning / Bubbles / Lava / Snowflake (2% each; 400 coins instead if owned) | 8% |
| 7 | 1,000 coins | 4% |
| 8 | **Golden Bomb** (Legendary bomb skin; 2,500 coins instead if owned) | 2% |
| | **Total** | **100%** |

Expected value is about 112 coins plus the boost, tokens and items, for 9 R$ (the coin pack rate makes 9 R$ worth about 180 coins). The wheel is a fun buy, not a ripoff.

### 5.4 Daily chest calendar (#27, part 1)
- One claim per UTC day. Missing a UTC day resets the calendar to Day 1. Profile fields: `calendarDay` (1-7), `lastDaily` (reuse), `loginStreak`.
- Claiming is a moment: chest opening animation and fanfare. **Remove the silent auto-grant** in `Sessions.checkDaily` (`Sessions.lua:334-353`); set Player `DailyReady = true` instead.
- Rewards: D1 100 coins, D2 150, D3 1 spin, D4 250, **D5 Rare Chest**, D6 400, **D7 Epic Chest** + 2x coins for 30 min. After D7 it starts again at D1 while `loginStreak` keeps counting ("12-day streak!").
  - Rare Chest: a random Rare cosmetic you don't own, else 500 coins.
  - Epic Chest: a random Epic you don't own, else 1,200 coins.
  - These are free random items, so showing odds is not required, but show the "Possible items" list anyway.
- `Config.DAILY_REWARD = 50` (Config.lua:48) is no longer used.

### 5.5 Group chest (#27, part 2)
- One claim per UTC day for group members: `player:IsInGroup(Config.GROUP_ID)`.
  - Add `GROUP_ID` to Config. The owner creates the group.
- If the player is not a member, the button says "JOIN GROUP". It calls `GroupService:PromptJoinAsync(GROUP_ID)`; a result of `Joined` or `AlreadyMember` counts as proof (IsInGroup is cached per session).
- Reward: 150 coins per day, plus 1 spin on the first claim ever.
- "Like the game" is sign copy only. No API exposes an individual player's like or favorite, so never gate on it.

### 5.6 Playtime gifts (ref1 "00:46")
- Based on cumulative minutes in the current session; they reset on rejoin. The player must tap to claim.
- Schedule:
  - #1 at 2 min: 40 coins
  - #2 at 5 min: 60 coins
  - #3 at 10 min: 1 spin
  - #4 at 15 min: 120 coins
  - #5 at 25 min: Rare Chest
  - #6 at 40 min: 250 coins + 2x coins for 15 min
  - After that, every 20 min: 150 coins
- Player attributes: `GiftIndex`, `GiftAt` (server time when the next gift is ready).

### 5.7 Starter Pack and limited trail, with honest pricing (#30, #31)
- **Starter Pack 49 R$**: 1,000 coins, Starter Spark trail (exclusive Rare) and 2x coins for 30 min. No random contents, so no odds work is needed. Profile `boughtStarter`. Badge "ONE-TIME OFFER". No made-up "worth X" claims.
- **Galaxy Comet** (Limited trail: purple-blue starfield gradient with sparkle particles):
  - The regular price is a **real** 199 R$ for all of Season 1: `Config.SEASON1_END`, a unix time, for example launch + 30 days. After that it can no longer be bought, which is what "LIMITED" means.
  - Each player gets a **Welcome Deal: 19 R$ for their first 48 h** (profile `firstJoin`). The card shows ~~199~~ 19 R$ and a real countdown.
  - The strikethrough is truthful only because 199 is the real price everywhere outside the deal. A University of Sydney study of top Roblox games flagged "timed false reference pricing" (permanent "daily deals") as deceptive, so never show a crossed-out price that nobody can actually pay.

### 5.8 Compliance (paid random items)
- The 9 R$ spin, the 39 R$ bundle and any Robux-bought chest are **paid random items**. Roblox requires:
  - all outcomes and their percentages shown **before** purchase;
  - percentages that sum to 100%;
  - a button with a **descriptive word** ("ODDS"), because a bare (i) icon is not enough.
- Call `PolicyService:GetPolicyInfoForPlayerAsync(player)`. When `ArePaidRandomItemsRestricted` is true, hide the paid spin buttons for that player. Free spins still work.
- Nothing paid gives a competitive edge beyond the capped upgrades (+30% at most per stat) and one revive that is never available in the final 2.

---

## 6. Progression

### 6.1 Cosmetics and what coins buy
- Rarity colors: Common (150,170,200), Rare (70,140,255), Epic (170,90,255), Legendary (255,195,40), Limited (pink-red gradient).
- **Coin prices: Common 300 / Rare 800 / Epic 2,000 / Legendary 5,000.** Today's prices (`Cosmetics.lua:71-101`, 120-750) are too cheap for v2 income.

| Slot (attr) | Items |
|---|---|
| Trail (`Cos_Trail`) | Bubblegum, Ice Blast, Sunshine (C); Lime Zoom, Grape Rush, Hot Sauce (R); Rainbow (E); VIP Gold (VIP); Starter Spark (Starter Pack); **Galaxy Comet (Limited, R$)**; Lightning, Bubbles, Lava, Snowflake (wheel only) |
| **BombSkin (new, `Cos_BombSkin`)** | Classic (free), Watermelon (C), Disco (R), Pumpkin (R), Gift Box (E), Rainbow (L), **Golden Bomb (wheel only)**. These are recolors and material swaps of the one bomb model. |
| BatColor (`Cos_BatColor`, used in Spin now) | Pink, Frost, Swamp (C); Pumpkin, Royal, Fire (R); Rainbow Bonk (E) |
| DashColor (`Cos_DashColor`) | same C/R/E split, existing ids |
| WinEffect (`Cos_WinEffect`) | Confetti Storm (R), Star Sparkles (E), Fireworks (L) |

Keep every existing id, because profiles store them. Add the new ids and the BombSkin slot to `Cosmetics.SLOTS` and `SLOT_INFO`. NICE: an Explosion FX slot (`Cos_Boom`).

### 6.2 Levels
- Keep `xpForLevel(n) = 50 + 25n` (`Rules.lua:51`). XP = base coins (before multipliers) + 10 per round.
- Level-up: banner, fanfare and 20 + 5 x level coins. Every 5th level also gives +1 spin.
- The nameplate shows "Lv N" (exists in `Economy/Visuals.lua:80 buildTag`).

### 6.3 Upgrades
- Keep the 4 upgrades x 5 levels and their prices (`Config.UPGRADES`). That is about 2,500 coins per upgrade, roughly 10 h to max all four at v2 rates.
- BatPower now powers the Spin bat. The dash upgrades apply in Bomb Tag (a small edge, which the owner accepts).
- Bug from the punchlist (P2): Core restores `JumpPower` to `Config.JUMP_POWER` after the freeze, which drops the JumpBoost upgrade. Restore `Stats.jumpPower(player)` instead.

---

## 7. Social and competition
- **Lobby boards**:
  - TOP WINS: OrderedDataStore `PartyDash_TopWins_v1`, value = wins, written on profile save when it changed.
  - TOP LEVEL: `PartyDash_TopLevel_v1`.
  - SOLO TOP 10: exists in `Solo/Board.lua`.
  - Refresh every 120 s. Rows show medal, headshot (`Players:GetUserThumbnailAsync`, HeadShot 48x48), name and value. Highlight the viewer's own row.
- **Nameplate**: row 1 is the DisplayName. Row 2 holds pills: [Lv 12], [trophy 34 wins], [flame 3] when the win streak is 2 or more, and [VIP]. `MaxDistance` 60.
- **Kill feed** with icon images (bat, bomb, ball, laser, splash).
- **Results card**:
  - podium 1-2-3;
  - MVP ribbon;
  - "+coins" chips: Played +5, Survived +4, Place +12, KOs x2 +10, Streak x1.3, First win +100;
  - counter count-up;
  - the XP bar fills.
- NICE: crown on the server's top winner, titles and achievements, rank crests by wins (Bronze 0 / Silver 10 / Gold 50 / Diamond 150 / Champion 500), weekly boards, friend bonus (+10% coins per friend in the server, max +30%) and an invite button (`SocialService:PromptGameInvite`).

---

## 8. Audio, loading screen, settings (#23, #24, #25)
- **Music**:
  - SoundGroups `Music` (0.35) and `SFX` (0.6).
  - Tracks from Roblox's licensed Creator Store music library: lobby is calm and tropical/lofi; rounds are upbeat but light; Bomb Tag is tense-funny.
  - Crossfade 1.5 s whenever the player's context changes (lobby vs InRound/Spectating).
- **SFX**:
  - **Click on every GuiButton.Activated** through one global hook (PlayerGui DescendantAdded).
  - **Hit**: the receiver hears it when `Core_Knockback` arrives; the attacker hears a bonk.
  - Coin chime when coins arrive, plus: dash whoosh, slide scrape, bomb tick and boom, wheel tick and jingle, chest fanfare, level-up jingle, water splash.
- **Settings** (gear button, top right): Music on/off, SFX on/off, Camera shake on/off. Saved in profile `settings` and sent with remote `Economy_Settings`.
- **Fake loading screen** (`ReplicatedFirst`):
  - Logo art, a big progress bar and a tip line.
  - Status lines every 0.9 s: "Loading assets...", "Building the lobby...", "Inflating balloons...", "Painting lasers red...", "Lighting the fuses...", "Almost ready!".
  - The fake progress runs 6.5 s (ease-out) while `ContentProvider:PreloadAsync` loads UI images in parallel.
  - A **SKIP** button appears after 1.0 s, then a 0.4 s fade. Once per session.

---

## 9. Bugs found in the code (#16, #18 and the punchlist)
1. **#16 "pushed into water and teleported back instead of dying"**:
   - KOTH was a `score` game, and `Context:_onFall` (`Context.lua:295-306`) respawns score-kind players after 2 s ("Oops! Back in 2...").
   - Second path: any live server where the `Debug_NoEliminate` workspace attribute is set also respawns (`Context.lua:307-308, 318-320`).
   - Fix: KOTH is removed, so every game is survival. `Debug.lua` returns defaults unless `RunService:IsStudio()`. KillY = floor - 10 in every map.
2. **#22 Spin ledge**: `Spin/Arena.lua:111` Foot ledge, `:32 KILL_DEPTH 24` and `Hit.lua:17 LOW_LIMIT`, as in 3.3.
3. **#22 jump still hit**: server-side lag and `CLEAR_HEIGHT 1.4`; the fix is `Forgive` (3.0).
4. **#11 slide**: head-first pose (`Pose.lua:25`, `Assets.lua:19`); cooldown 0.4 shown with a bar (`Movement/Hud.lua:173-188, 390-395`).
5. **#13 laser colors**: `Motion.lua:35-37`, high laser is cyan.
6. **#15 laser pillar**: `LaserTracer/Arena.lua:171,279` Hub plus hub-anchored sweeps.
7. **#21 wall text**: `HoleInTheWall/WallView.lua:22-26, 89`.
8. **Washed-out look (#4, #7)**:
   - Causes in `LightingSetup.lua`: Brightness forced to at least 3 (:30), Exposure +0.1 (:37), Atmosphere Haze 0.6 / Density 0.24 (:46, :51), Bloom 0.45.
   - Retune to: Brightness 2.2, Exposure -0.1, Atmosphere Density 0.18 / Haze 0 / Glare 0, Bloom Intensity 0.25 / Threshold 2, ColorCorrection Saturation 0.2 / Contrast 0.15.
   - Rule: no map floor may use a color close to the sea (35,200,235) or the sky. The current KOTH map is pale mint and cyan on cyan water, which is exactly the "everything blends" complaint.
9. **Punchlist bugs**:
   - JumpBoost lost after the freeze (6.3).
   - `PD_DodgeballClient` left over (3.4).
   - Spin warning broken in Solo (3.3).
   - Shop "BEST VALUE" badge clipped and muddy coin tiles: superseded by the shop redesign, but verify.
10. **Single-player rounds give no Win** (`Results.lua:35`). Keep it (anti-farm), but show "Play with friends to earn WINS!" on the result card.

---

## 10. Priorities

### MUST tonight (in dependency order; each one is a gauntlet piece)
| # | Piece | Contents | Done when |
|---|---|---|---|
| A | **Core v2** | Permanent lobby at the new LOBBY_CENTER; Lobby 20 s; join square + `Queued` + LobbyHold; 3-card vote + vote reel; death panel flow (Spectate/Lobby) + `Context:_revive` + SpawnShield; `Forgive` module; KO attributes and killer credit; sudden death at 120 s; Debug hooks only in Studio; KOTH removed from the pool | A full loop with 2 players: lobby -> vote -> game -> death -> lobby -> next round, with no stands and no respawn on falls |
| B | **Bomb Tag** | Section 2, complete: rules, Boom Park, tension FX/audio, KO credit, BombSkin rendering | 3-player and 6-player tests: passes, no tag-back, explosions, shrink, winner |
| C | **Laser Tracer v2** | No hub, rotor/chord/bouncer random patterns, conflict rule, both red with the LOW/HIGH cues, Forgive | No center pillar; two rounds never open the same way; low and high readable at a glance |
| D | **Hole in the Wall v2** | No text, shape catalog, grid renderer, pass rects, Forgive | No labels; at least 8 shapes seen in one round; never the same set twice in a row |
| E | **Spin v2** | Bat (moved to Combat/), ledge fix, KILL_DEPTH 8, CLEAR/HALF_WIDTH + Forgive, Solo warning | Standing on the old ledge is impossible; jump-on-time is never hit at 150 ms simulated ping |
| F | **Movement v2** | Slide tackle pose, slide cooldown 1.0 s with no bar, Q dash + Shift Lock off, coyote time and jump buffer, mobile icon buttons, camera | Slide reads as a football tackle; no slide bar anywhere |
| G | **Economy v2** | New products and display prices; wheel (free, 9, 39) with ODDS and PolicyService; calendar chest; group chest; playtime gifts; Starter Pack; Galaxy 19/199 with firstJoin and season end; revive purchase + tokens; coin formula v2 + XP change; repricing; BombSkin slot; TOP WINS and TOP LEVEL boards; profile v2 | All grants idempotent; odds sum to 100; nothing purchasable is lost |
| H | **UI v2** (ref style) | HUD layout from 5.2; shop with a Featured tab (ref5); wheel, calendar and death panels; vote cards; results breakdown; settings; loading screen with Skip; global click SFX; all icons generated as images (no emoji) | Phone (800x360) and 1080p screenshots match the ref1/ref3/ref5 feel |
| I | **Audio** | Music with crossfades and mute, the SFX list | Music toggles persist across rejoin |
| J | **World/visual** | Lighting retune; new lobby (1.7 #1-11); per-map identity colors; cartoon water | No map floor blends with the sea or sky; the lobby matches ref1/ref2 |
| K | **Dodgeball small** | Golden-ball cadence, KO credit, client container leak | |

### NICE later (do not start tonight)
Daily quests (3 a day); titles and achievements; rank crests; VIP island; lobby obby ring and obby chest; friend bonus and invite button; weekly boards; emotes; explosion FX slot; a 2x-coins 30-min product; a pre-round power-up choice (cut: it needs balance work in 5 games); Spin pillar sinking; Dodgeball shrink and aim assist; Boom Park pusher blocks; rewarded-video revive; season pass; a crown for the server's top winner.

---

## 11. Data contract additions (for the lead to freeze)
- **GameState**: `VoteOptions` (CSV), `VoteCounts` (JSON), `QueuedCount` (number), `LobbyHold` (bool).
- **MinigameInfo.<Id>**: `MinPlayers`.
- **Player attributes**: `Queued`, `Vote`, `RoundStreak`, `LastHitBy`, `LastHitAt`, `ReviveUntil`, `Spins`, `DailyReady`, `CalendarDay`, `GroupReady`, `GiftIndex`, `GiftAt`, `BoostUntil`, `Cos_BombSkin`.
- **Character attributes**: `SpawnShield`, `HasBomb`, `BombFuseEnd`.
- **Remotes**:
  - `Core_Vote`
  - `Economy_Claim` ("daily" / "group" / "gift")
  - `Economy_Spin`
  - `Economy_SpinResult`
  - `Economy_Settings`
  - `BombTag_Fx`
- **Profile v2** (`Profile.VERSION` 1 -> 2; `reconcile` fills defaults):
  - `spins`, `freeSpinDay`, `calendarDay`, `loginStreak`, `groupChestDay`, `reviveTokens`
  - `boughtStarter`, `firstJoin`, `boostUntil`, `firstWinDay`
  - `settings = { music, sfx, shake }`
  - `stats.kos`, `stats.bombPasses`
  - `equipped.BombSkin`
- **Config additions**: the products in 5.1, `GROUP_ID`, `SEASON1_END`, the timings in 1.1, `SLIDE_COOLDOWN = 1.0`, `LOBBY_CENTER`.
- **Owner to-do in Creator Hub**:
  - create the 6 new developer products with the exact prices above and paste their ids;
  - set the 2 pass prices (149 / 249);
  - create the group;
  - upload the generated images.

## 12. Art to generate (one consistent style)
Style prompt for every image: "glossy 3D cartoon icon, chunky shapes, thick dark outline, saturated colors, soft top light, transparent background, Roblox simulator UI style".
- **HUD icons**: Shop basket, Items backpack, Daily calendar gift, Solo stopwatch, Wheel, Gift box, Group chest, VIP crown, 2x coin, Coin, Trophy, Revive heart, Bomb, Bat, Laser, Splash, Settings gear, Music note, Speaker, Check.
- **Mobile action buttons**: Dash, Slide, Swing/Throw.
- **Minigame card art (5)**: Bomb Tag, Laser Tracer, Hole in the Wall, Spin, Dodgeball.
- **Product art**: Starter Pack box, Galaxy Comet trail, Spin token, Rare chest, Epic chest.
- **Logo and loading screen**: "PARTY DASH" logo and loading key art.
- **Textures**: cartoon water waves, grass and wall checker textures.

Sources consulted: Roblox paid random items policy (create.roblox.com/docs/production/monetization/paid-random-items); GroupMembershipStatus / PromptJoinAsync (create.roblox.com/docs/en-us/reference/engine/enums/GroupMembershipStatus.md); DevForum "How can I tell who likes my game?" (devforum.roblox.com/t/how-can-i-tell-who-likes-my-game/1842778); University of Sydney study on Roblox monetization (ia.acs.org.au/article/2026/roblox-sucking-up-money-from-young-players--study.html).
