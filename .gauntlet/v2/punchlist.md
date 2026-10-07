# Party Dash v2 overhaul: gauntlet-loop punchlist
Baseline tag: `baseline-pre-v2` (v1 @ 62586fa). Phase 0 (lead contracts) @ 176d28e. Review branch: `review/party-dash`.
Landing mode: worktree-default (critic commits on its piece branch, wave-commit merges into the review branch). Never pushed.

| Piece | Wave | Status | Attempts | Notes |
|---|---|---|---|---|
| V1 Core v2 (permanent lobby, join square, vote, death flow, revive, KO credit) | 1 | passed (static + Studio), NOT merged | 1 | branch worktree-wf_48cb2643-675-1 @ 57cf9de |
| V2 Movement v2 (slide tackle, no slide bar, dash/jump feel, Forgive, mobile pad) | 1 | static passed (attempt 2), Studio test blocked by permission classifier; attempt 3 interrupted | 3 | attempt-2 code: branch worktree-wf_ba0deb1c-2dd-6 @ 32ee52c |
| V3 World & Lobby (lighting, sea, islands, lobby island + stations) | 1 | build interrupted 3x (usage limit / stop), uncommitted partial work | 0 | latest partial: .claude/worktrees/wf_52375f41-a44-1 (and wf_ba0deb1c-2dd-3) |
| V4 Economy v2 (products, wheel, daily/group/gifts, revive, coin formula, cosmetics, settings) | 1 | passed (static + Studio, 12/12), NOT merged | 1 | branch worktree-wf_48cb2643-675-4 @ 6236ea2 |
| V5 HUD v2 (status, vote cards, roulette, intro, death panel, spectate, results) | 1 | passed (static + Studio), NOT merged | 1 | branch worktree-wf_48cb2643-675-5 @ 6cdf56f; GUI polish unverified (screen locked) |
| V6 Boot/Audio/Settings (loading screen, music, click hook, settings) | 1 | accepted with env caveats (lead), NOT merged | 1 | branch worktree-wf_48cb2643-675-6 @ 5136288; click/skip/toggles unverified (screen locked) |
| V7 Bomb Tag (+ remove King of the Hill) | 2 | pending | 0 | |
| V8 Laser Tracer v2 | 2 | pending | 0 | |
| V9 Hole in the Wall v2 | 2 | pending | 0 | |
| V10 Spin v2 + Combat (bat) | 2 | pending | 0 | |
| V11 Dodgeball v2 | 2 | pending | 0 | |
| V12 Shop & Rewards UI | 2 | pending | 0 | |
| V13 Social & Solo (boards, Solo UI) | 2 | pending | 0 | |

## Failure details / judge caveats
Run stopped by the owner on 2026-10-07 ~08:00 before the wave-1 merge. Nothing from V1-V6 is on review/party-dash yet.
- Mac screen locked overnight: Studio Play has no RenderStepped/tweens/input/screen_capture, so GUI polish, input-driven
  behaviour and screenshots are unverified for V5/V6 (verified through remotes, attributes and instance trees instead).
- V2 Studio test: the studio_pull sync was denied once by the permission classifier ("Irreversible Local Destruction");
  tools/studio_pull.luau now archives instead of destroying (0f71537). V2 code passed static review on attempt 2.
- V6 attempt-1 Studio failure was caused by a lead contract bug in Shared.Audio (fixed in 31f0ca7).
- Wave 2 workflow ready (not launched): .gauntlet/v2/wave2-workflow.js (specs for V7-V13; set WAVE_BASE first).
