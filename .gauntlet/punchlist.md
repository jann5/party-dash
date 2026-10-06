# Party Dash: gauntlet-loop punchlist
Baseline tag: `baseline-pre-partydash`. Review branch: `review/party-dash`. Landing mode: worktree-default.

| Piece | Wave | Status | Attempts | Notes |
|---|---|---|---|---|
| P1 Core (round loop, maps, lobby, spectator, knockback, sandbox) | 1 | passed | 1 | merged; see contract notes |
| P2 Movement (dash+cooldown bar, slide, animations, mobile) | 1 | passed | 1 | merged; see contract notes |
| P3 UI (roulette, HUD, intro card, onboarding, branding) | 1 | passed | 3 | merged |
| P4 Laser Tracer | 2 | pending | | |
| P5 Dodgeball | 2 | pending | | |
| P6 Hole in the Wall | 2 | pending | | |
| P7 King of the Hill | 2 | pending | | |
| P8 Spin port + Modifiers | 2 | pending | | |
| P9 Economy (coins, upgrades, cosmetics, Robux) | 3 | pending | | |
| P10 Solo Record + global TOP 10 | 3 | pending | | |

## Failure details / judge caveats
No wave 1 failures (all three pieces passed).

Contract notes from passed pieces (verbatim contractGaps, for later waves):

P1 Core: No frozen-contract edits were needed. Gaps I worked around:
- The Minigame contract never says when the map is destroyed relative to the End phase. Core calls session:stop() when the round ends and destroys the map and ctx.trove only when returning to the lobby, so the results show on the map. After stop, ctx.knockback, eliminate and addScore are no-ops.
- The contract doesn't define who wins a single-participant survival round. Core treats it as no winner.
- ARCHITECTURE.md hides "_" ids from the roulette with no fallback when no visible minigame exists. Core falls back to hidden ids in that case.
- Extra attributes added beyond the docs: MinigameInfo gets Duration and Hidden; characters get StunnedUntil, which backs the server-side Stunned timer.

P2 Movement: ARCHITECTURE.md calls Cos_DashColor an "equipped cosmetic id", but no list of cosmetic ids is frozen anywhere. The parser therefore accepts hex, Theme.Colors names (with an optional "dash" prefix), BrickColor names and "Rainbow"; Economy (P9) should store one of these. No frozen contract says how Core freezes players during Intro/Countdown, so movement also blocks dash/slide while InRound and Phase is Intro or Countdown, and it leaves JumpPower alone when it is 0. Core restoring JumpPower to Config.JUMP_POWER after a freeze would drop the Jump Boost upgrade until the next spawn or upgrade change.

P1 evidence gap: only one early Round screenshot (Studio renderer went black). P2: visual part of P2-4 and P2-9 unverified (no 3D scene in screen_capture).
