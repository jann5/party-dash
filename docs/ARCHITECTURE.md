# Party Dash: architecture and conventions (read this before writing any code)

Party Dash is a Roblox party game: players wait in a lobby, a card roulette picks a minigame, everyone plays
it on one shared arena that is rebuilt for every round, then they go back to the lobby. The whole game is in
**English**. Style: bright cartoon (Stumble Guys / Fall Guys) via `src/shared/Theme.lua`. Max 12 players. It runs on
PC and mobile.

## Repo layout (Rojo, see `default.project.json`)
| Repo path | Studio location |
|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |

Rojo file rules: `X.server.lua` → Script, `X.client.lua` → LocalScript, `X.lua` → ModuleScript. A folder with
`init.server.lua` / `init.client.lua` / `init.lua` becomes that script with the folder's other files as children.
**Each system boots itself** through its own `init.server.lua` / `init.client.lua`. Nobody edits a shared boot list.

Legacy game (the old "Spin" minigame) is preserved read-only in `legacy/` (scripts + `legacy/data/*.json`)
and as data in `src/shared/Maps/SpinArenaData.lua` (generated; do not hand-edit).

## Frozen contracts (owned by the lead; pieces MUST NOT edit these files)
- `src/shared/Config.lua`: tuning constants (you may READ any key)
- `src/shared/Net.lua`: `Net.event(name)`, `Net.unreliable(name)`, `Net.func(name)`; remote names are `<Owner>_<Thing>`
- `src/shared/GameState.lua`: replicated round state (attributes on `ReplicatedStorage.GameState`)
- `src/shared/Theme.lua`: colors, fonts, per-minigame accent colors
- `src/shared/Util/Trove.lua`: cleanup bag
- `src/shared/Contracts/Minigame.lua`: **minigame definition / session / ctx API** (read it fully)
- `src/shared/Contracts/Modifier.lua`: modifier API
- `src/server/Signals.lua`: server event bus (RoundStarted, PlayerEliminated, RoundFinished, SoloFinished)
- `src/server/Announce.lua`: `Announce.big/feed/toast(target, ...)` → remote `Core_Announce`
- `src/shared/Maps/SpinArenaData.lua`, `src/shared/LightingData.lua`: generated data
- `default.project.json`, `selene.toml`, `stylua.toml`, `tools/`, `docs/`

If a frozen contract is genuinely insufficient, **do not edit it**. Work around it inside your own files and
report the gap in your summary.

## GameState attributes (`ReplicatedStorage.GameState`, written by Core)
| Attribute | Type | Meaning |
|---|---|---|
| `Phase` | string | one of `GameState.Phase` (Waiting/Lobby/Roulette/ModifierRoulette/Intro/Countdown/Round/End) |
| `PhaseEnd` | number | `workspace:GetServerTimeNow()` when the current phase ends (0 = open-ended) |
| `RoundNumber` | number | increments every round |
| `MinigameId` | string | chosen minigame (set at the START of Roulette, so the client animates toward it) |
| `RouletteReel` | string | CSV of minigame ids in the order the reel shows them (ends on MinigameId) |
| `ModifierId` | string | "" or the active modifier id (set at the start of ModifierRoulette) |
| `ModifierReel` | string | CSV for the modifier roulette |
| `MinigameKind` | string | "survival" or "score" |
| `Alive` | number | alive count (survival) |
| `Participants` | number | how many started the round |
| `ScoresJson` | string | JSON `{ [userId]: score }` (score kind, updated about 4x per second) |
| `WinnersCsv` | string | userIds of winners (set in End) |
| `ResultText` | string | e.g. "Alex WINS!" / "NOBODY SURVIVED!" |

Minigame metadata for the UI (name, rules, keys, accent color) is replicated by Core as attributes on
`ReplicatedStorage.MinigameInfo.<Id>` (Configuration) with `DisplayName`, `Rules`, `Keys` (CSV), `Kind`,
`SoloCapable`. Modifier metadata goes to `ReplicatedStorage.ModifierInfo.<Id>` with `DisplayName` and
`Description`.

## Player / character attributes
| Where | Attribute | Set by | Meaning |
|---|---|---|---|
| Player | `InRound` | Core | currently alive in the main round |
| Player | `Spectating` | Core | eliminated, on the spectator platform |
| Player | `InSolo` | Solo (P10) | playing a private Solo Record run (Core must skip them) |
| Player | `Upg_DashCooldown`, `Upg_DashDistance`, `Upg_BatPower`, `Upg_JumpBoost` | Economy (P9) | upgrade level 0..5 (missing = 0) |
| Player | `Cos_Trail`, `Cos_DashColor`, `Cos_BatColor`, `Cos_WinEffect` | Economy (P9) | equipped cosmetic id ("" = default) |
| Player | `Coins`, `Level`, `XP` | Economy (P9) | for UI |
| Player | `Seen_Tutorial` | UI (P3) via remote | onboarding hints done |
| Character | `Sliding`, `Dashing` | Movement (P2), **server-side** | replicated movement state |
| Character | `Stunned` | Core Knockback | knockback stun active |

Upgrade effect = `level * Config.UPGRADES[name].perLevel` (e.g. DashCooldown lvl 3 → -18% cooldown).

`leaderstats`: Core creates `Wins` and `Streak` IntValues. Economy adds `Coins` to the same folder and persists Wins.

## Debug hooks (critics use these; Core MUST honor them)
Workspace attributes:
- `Debug_ForceMinigame` (string): the roulette always lands on this id
- `Debug_ForceModifier` (string): force this modifier on every round ("" = normal rule)
- `Debug_FastIntermission` (bool): Lobby/Roulette/Intro/End take ~2s each
- `Debug_NoEliminate` (bool): falling below killY respawns you on the map instead of eliminating you
- `Debug_IntensityOverride` (number): ctx.intensity() returns this instead

## Run modes in one server
The **main round** (Core) and any number of **Solo Record** copies (P10) run at the same time. A minigame module
must therefore support several concurrent sessions: no module-level mutable state, everything relative to
`ctx.center`, client visuals keyed by their map Model. Solo copies live at `Config.SOLO_ORIGIN + k * SOLO_SPACING * Z`.

## Knockback
Server: `ctx.knockback(player, dir, power, stun?)`, implemented in Core's `src/shared/Knockback.lua` (P1).
The server fires `Core_Knockback` to the owning client, which applies the velocity (the client owns its character's
physics) and a short stun (PlatformStand plus a ragdoll-ish tumble). The server sets `Stunned` for the stun time.

## UI conventions
- Every ScreenGui: `ResetOnSpawn = false`, `IgnoreGuiInset = true` where full-screen, scales from phone (~800x360)
  up to 1080p. Use Scale sizing + `UIAspectRatioConstraint` / `UISizeConstraint` and `TextScaled` with `UITextSizeConstraint`.
- Font `Theme.Font`. Rounded panels (`UICorner` with `Theme.CornerRadius`), thick dark outlines (`UIStroke`, `Theme.Colors.Ink`).
- **Menu rail**: UI (P3) creates `PlayerGui.PartyHUD.MenuRail` (a vertical Frame with UIListLayout, left-middle of
  the screen). Other systems add their own big round buttons into it: Shop `LayoutOrder = 10`, Solo `LayoutOrder = 20`.
- Mobile action buttons (Dash, Slide, Swing, Throw) go through `ContextActionService:BindAction(..., true)` and
  get a visible title/image. They are positioned bottom-right above the jump button and must not overlap.

## Testing in Studio (how critics verify)
1. `python3 tools/devserver.py` is already running on 127.0.0.1:8765 (the lead keeps it alive).
2. Studio must be in Edit mode. Take `tools/studio_pull.luau`, replace `__ROOT__` with the ABSOLUTE path of the
   worktree/repo to test, run it with the Studio MCP `execute_luau` (datamodel `Edit`). It rebuilds
   `ReplicatedStorage.Shared`, `ServerScriptService.Server` and `StarterPlayerScripts.Client` from that tree.
3. Set debug hooks with `execute_luau` in Edit (e.g. `workspace:SetAttribute("Debug_ForceMinigame","LaserTracer")`),
   then `start_stop_play` → play. Inspect with `execute_luau` (Server / Client datamodels), `get_console_output`,
   `screen_capture`, `character_navigation`, `user_keyboard_input`. Stop play when done.
4. Studio is a single shared resource: only one critic uses it at a time (the workflow serializes this).

## Builder rules
- Touch only the files your piece owns (listed in your prompt). Never delete or revert a file you did not create.
  If `git status` shows unexpected changes outside your ownership, report them and do not "clean them up".
- Strict Luau is welcome (`--!strict` optional). Run `tools/bin/selene src/` and `tools/bin/stylua --check src/`
  from the repo root before you finish (tools/bin may live only in the main checkout:
  `/Users/jannawrot/Desktop/roblox-julek-temp/tools/bin/`).
- `tools/bin/rojo build default.project.json -o /tmp/<piece>.rbxl` must succeed.
- All player-facing text is English. No Polish strings.
- Never trust the client: validate remote arguments, rate-limit, keep authority on the server.
- Performance: no per-frame `Instance.new`, use `task.wait`/Heartbeat responsibly, pool projectiles where sensible.

## Sandbox minigame
Core (P1) ships `src/server/Minigames/_Sandbox/`, a trivial survival minigame (round platform plus slowly falling
balls) used to test the round loop before the real minigames exist. Core skips any minigame whose id starts with
`_` in the roulette, unless `Debug_ForceMinigame` names it explicitly.
