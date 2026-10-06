# Party Dash: gauntlet-loop punchlist
Baseline tag: `baseline-pre-partydash`. Review branch: `review/party-dash`. Landing mode: worktree-default.

| Piece | Wave | Status | Attempts | Notes |
|---|---|---|---|---|
| P1 Core (round loop, maps, lobby, spectator, knockback, sandbox) | 1 | passed | 1 | merged; see contract notes |
| P2 Movement (dash+cooldown bar, slide, animations, mobile) | 1 | passed | 1 | merged; see contract notes |
| P3 UI (roulette, HUD, intro card, onboarding, branding) | 1 | passed | 3 | merged |
| P4 Laser Tracer | 2 | passed | 2 | merged |
| P5 Dodgeball | 2 | passed | 1 | merged |
| P6 Hole in the Wall | 2 | passed | 1 | merged |
| P7 King of the Hill | 2 | passed | 2 | merged |
| P8 Spin port + Modifiers | 2 | passed | 1 | merged |
| P9 Economy (coins, upgrades, cosmetics, Robux) | 3 | pending | | |
| P10 Solo Record + global TOP 10 | 3 | pending | | |

## Failure details / judge caveats
Wave 2: no failures (P4-P8 all passed).
No wave 1 failures (all three pieces passed).

Contract notes from passed pieces (verbatim contractGaps, for later waves):

P1 Core: No frozen-contract edits were needed. Gaps I worked around:
- The Minigame contract never says when the map is destroyed relative to the End phase. Core calls session:stop() when the round ends and destroys the map and ctx.trove only when returning to the lobby, so the results show on the map. After stop, ctx.knockback, eliminate and addScore are no-ops.
- The contract doesn't define who wins a single-participant survival round. Core treats it as no winner.
- ARCHITECTURE.md hides "_" ids from the roulette with no fallback when no visible minigame exists. Core falls back to hidden ids in that case.
- Extra attributes added beyond the docs: MinigameInfo gets Duration and Hidden; characters get StunnedUntil, which backs the server-side Stunned timer.

P2 Movement: ARCHITECTURE.md calls Cos_DashColor an "equipped cosmetic id", but no list of cosmetic ids is frozen anywhere. The parser therefore accepts hex, Theme.Colors names (with an optional "dash" prefix), BrickColor names and "Rainbow"; Economy (P9) should store one of these. No frozen contract says how Core freezes players during Intro/Countdown, so movement also blocks dash/slide while InRound and Phase is Intro or Countdown, and it leaves JumpPower alone when it is 0. Core restoring JumpPower to Config.JUMP_POWER after a freeze would drop the Jump Boost upgrade until the next spawn or upgrade change.

P1 evidence gap: only one early Round screenshot (Studio renderer went black). P2: visual part of P2-4 and P2-9 unverified (no 3D scene in screen_capture).

Wave 2 contract notes from passed pieces (verbatim contractGaps and caveats):

P4 Laser Tracer (lastSummary caveat): in-Play screen_capture did not render the 3D world in this environment, so visuals were verified in Edit mode with the real modules under LightingSetup.apply(). contractGaps: 1. Theme.Colors.Laser (255,40,90) looks pink-magenta and Theme.Colors.LaserAlt looks teal under the lead's lighting. Theme is frozen, so the pure red and cyan laser colours are defined in my own Motion.COLORS. 2. Server and client have no shared folder for minigame code they both need. As in attempt 1, the shared motion math stays in src/client/Minigames/LaserTracer/Motion.lua, and the server loads it from StarterPlayerScripts through MotionRef.lua.

P5 Dodgeball: contractGaps: ctx has no way to ask who is watching this session (spectators in the stands should see the balls too). As a workaround, Dodgeball_Fx goes to all clients with a session id, and clients skip anything more than 900 studs from their camera. There is also no shared place for code used by both server and client in my owned paths, so the client keeps its own copy of the small arc formula from Ballistics.lua. The message carries the full flight plan, so the two cannot drift apart. Notes: client container PD_DodgeballClient (185 descendants) stays in workspace in the Lobby after the round; a solo player standing still is eliminated within about 5 s of the first round starting.

P6 Hole in the Wall: contractGaps: Net.event on the client waits up to 30s and then errors if the remote does not exist. The server only creates the minigame's remote when a session is built, so the client connects to HoleInTheWall_Fx lazily, inside a pcall, when the first arena appears, instead of at boot. Otherwise there were no gaps in the frozen contracts.

P7 King of the Hill: caveats: (1) Studio's screen_capture rendered the 3D viewport black in every capture after the first, so visual polish was not judged. (2) A solo test cannot make WinnersCsv contain the player. Core's Results.apply refuses winners when fewer than 2 players take part. contractGaps: Results.apply in src/server/Core/Results.lua (Core, not a frozen contract but outside my ownership) leaves WinnersCsv empty whenever fewer than 2 players took part. P7-6's "WinnersCsv contains the player" therefore needs a 2-player playtest; a minigame cannot change this, and GameState says only Core writes WinnersCsv. The tutorial-avoidance logic depends on P3's widget name PlayerGui.PartyHUD.Tutorial, which is not part of any contract. If it is missing, the pill stays at its default position.

P8 Spin port + Modifiers: caveat: arena visuals ("polished, cartoon, readable") unverified by eye because Studio's 3D viewport rendered blank in Play and Edit mode. contractGaps: No frozen contract was edited. Two gaps were worked around:
1. There is no shared code location that both a minigame's server code and its client code may write to. For one source of truth, the server requires the client-owned BarMath ModuleScript from StarterPlayerScripts.
2. The Modifier contract gives clear(ctx) only ctx and forbids module-level state, so there is nowhere to remember "this modifier is active". I used a Player attribute (Mod_Active) as that per-round flag, plus character and part attributes that store the original values to restore.
