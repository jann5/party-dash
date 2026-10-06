# Party Dash v2: architecture and conventions (read this before writing any code)

Party Dash is a Roblox party game. Players hang out on a **permanent lobby island**, step into the **PLAY square**
to queue, **vote** for one of 3 minigames, a quick roulette reveals the winner, everyone queued plays it on the
**arena** (one shared map rebuilt per round, far away from the lobby), and eliminated players go back to the lobby
where they can **spectate**, stay in the lobby, or **revive** (Robux). The whole game is in **English**. PC + mobile,
max 12 players.

**v2 is an overhaul** requested by the owner after playing v1. Read, in this order:
0. `docs/v2/DECISIONS.md` — the lead's final calls where the docs below disagree (short; read it first).
1. `docs/BRIEF-v2.md` — the owner's 33 requirements (translated). Every one matters.
2. `docs/v2/GAME_DESIGN.md` — the design spec (numbers, rules, prices). Section 10 = what is built tonight.
3. `docs/v2/ART_BIBLE.md` — look & feel: lighting, palette, materials/textures, lobby layout, UI style guide.
4. `docs/v2/audits/*.md` — code audits of v1 per subsystem (bugs with file:line, plans). Read the ones for your piece.
5. `docs/v2/PLAYTEST.md` — what a QA playtest of v1 found.
6. This file (contracts), then the frozen modules it lists.
Reference screenshots of the wanted style: `docs/reference/ref*.jpg` (open them, you can see images).

## Repo layout (Rojo, see `default.project.json`)
| Repo path | Studio location |
|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` |
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/first/` | `ReplicatedFirst.PartyDashFirst` (v2: the loading screen) |

Rojo file rules: `X.server.lua` → Script, `X.client.lua` → LocalScript, `X.lua` → ModuleScript. A folder with
`init.server.lua` / `init.client.lua` / `init.lua` becomes that script with the folder's other files as children.
**Each system boots itself** through its own `init.server.lua` / `init.client.lua`. Nobody edits a shared boot list.
Assets (generated art, textures) live in `assets/` (not synced); their uploaded ids are in `src/shared/Assets.lua`.

## Frozen contracts (lead-owned; pieces MUST NOT edit these files)
- `src/shared/Config.lua`: tuning constants (read any key; v2 keys marked `[v2]`)
- `src/shared/Net.lua`: `Net.event(name)`, `Net.unreliable(name)`, `Net.func(name)`; remote names `<Owner>_<Thing>`
- `src/shared/GameState.lua`: replicated round state (attributes on `ReplicatedStorage.GameState`)
- `src/shared/Theme.lua`: colors, fonts, per-minigame accents, per-map palettes (v2)
- `src/shared/Assets.lua` (GENERATED): icon / art / texture / sound ids. Use `Assets.icon(key)` for images.
- `src/shared/Art.lua` (v2): world-building helpers (textured voxel blocks, water, outlines). Use it for maps.
- `src/shared/Audio.lua` (v2): the ONLY way to play sounds (SoundGroups Music/SFX/UI, settings mute).
- `src/shared/UIKit/` (v2): the ONLY UI kit (buttons, icon tiles, panels, pills, toasts, docks, lanes, scaling).
- `src/shared/Products.lua` (v2): Robux catalog display data (titles, prices, icons, badges).
- `src/shared/Purchase.lua` (v2): client `Purchase.prompt(key)` (real prompt, Studio dev path, or "Coming soon").
- `src/shared/Util/Trove.lua`, `src/shared/Contracts/Minigame.lua` (v2), `src/shared/Contracts/Modifier.lua`
- `src/server/Signals.lua` (v2), `src/server/Announce.lua`
- `src/shared/Maps/SpinArenaData.lua` (generated data), `default.project.json`, `selene.toml`, `stylua.toml`,
  `tools/`, `docs/`, `assets/`
If a frozen contract is genuinely insufficient, **do not edit it**. Work around it inside your own files and report
the gap in your summary (`contractGaps`).

## World layout (v2) — ART_BIBLE section 5 is the visual spec
- **Islands IN one cartoon sea.** Sea surface `Config.SEA_LEVEL` (36) = `ARENA_CENTER.Y - Config.SEA_DROP` (14). The
  sea is made of non-collidable Parts with two scrolling wave textures (World piece); nobody can swim. No terrain
  water, no gray baseplate. Every walkable top has a dark textured cliff band running down into the water.
- **Arena**: maps are built around `Config.ARENA_CENTER` (0,50,0): the floor top is at center.Y. Default
  `killY = center.Y - Config.KILL_DEPTH` (17) = 3 studs UNDER the water, so a fall is a visible splash, then OUT.
  A map may set a **higher** `KillY` attribute (never lower). Core plays the splash FX when a player crosses the sea.
- **Lobby**: permanent island at `Config.LOBBY_CENTER` (0,50,-340) (grass top), 340 studs SOUTH of the arena; players
  spawn facing +Z (north) and see the arena island behind the PLAY arch. Built ONCE at server start by Core
  (`Places`) from `src/shared/Maps/Lobby.lua`, never destroyed between rounds. Boundary walls at `LOBBY_RADIUS`;
  falling into the lobby water respawns you on the lobby spawns (Core rescue).
- **Solo copies**: `Config.SOLO_ORIGIN + k * SOLO_SPACING * Z` (Solo piece builds their backdrop with the same recipe).
- **No spectator stands** in v2. Spectating is camera-only; the spectator's character stays in the lobby.

## Round flow (v2) — Core owns it
| Phase | Duration | What happens |
|---|---|---|
| Waiting | — | no players in the server |
| Lobby | `LOBBY_TIME` 20 s | Players walk around. Standing in the PLAY square (`Lobby.PlayZone`) = queued (Player `Queued`). Queued players vote between `VoteOptions` (3 minigames). When the timer ends with nobody queued: `LobbyHold = true`, `PhaseEnd = 0` (open-ended); the first player to step in restarts a `LOBBY_HOLD_RESTART` s countdown. |
| Roulette | `ROULETTE_TIME` 4 s | `MinigameId` = vote winner (most votes, ties random, none = random eligible). `RouletteReel` cycles only the vote options and ends on `MinigameId`. Participants = queued players at lobby end (max 12, longest-waiting first), snapshotted in GameState `Participants`. |
| ModifierRoulette | 3 s | every `MODIFIER_EVERY`-th round (unchanged) |
| Intro | 3 s | map built at ARENA_CENTER, participants teleported to Spawns and frozen, rules card |
| Countdown | 3 s | 3-2-1-GO |
| Round | open | survival: last one standing (alone: until you fall). `SUDDEN_DEATH_AT` 120 s → intensity x2 + banner |
| End | 5 s | results on the map, then survivors go back to the lobby spawns |

**Elimination flow** (brief #16/#17/#28): fall below killY (or Humanoid death, or a minigame `ctx.eliminate`) →
Core: Player `InRound=false`, `Eliminated=true`; `Core_Fx` "splash"/"boom"/"poof" at the spot; `Announce.big`
"OUT! #5 of 9" to the victim; KO credit check; after `DEATH_BEAT` (1 s) the character is teleported to a lobby spawn
and the victim gets `Core_Death` (payload below) → the client shows the **death panel**: SPECTATE (default after
6 s), LOBBY, REVIVE (when offered). Choosing goes through `Core_DeathChoice`. `Eliminated` is cleared when the round
ends. There is no respawn on falls in v2 (the v1 score-kind "Oops! Back in 2" is unused: no score games remain).

**Revive** (brief #28): offered when the round started with ≥ `REVIVE_MIN_PARTICIPANTS`, ≥ `REVIVE_MIN_OTHERS_ALIVE`
others are still alive, the player has not been revived this round (`REVIVE_MAX_PER_ROUND`) and the window
(`REVIVE_WINDOW` s, Player `ReviveUntil`) is open. Paths: (a) the player has `ReviveTokens` > 0 → client fires
`Economy_UseRevive`; (b) otherwise `Purchase.prompt("Revive")` (Studio: dev path). Economy then calls
`Core.Revive.revive(player)`; if that fails (window closed/round over) Economy grants a token instead. A purchase is
never lost. Revived players get `ShieldUntil = now + SPAWN_SHIELD` and are placed by `session:onRevive` or a spawn.
With `Debug_FreeRevive` (Studio) the revive button works without Robux or tokens.

**KO credit**: `ctx.knockback(victim, dir, power, stun, attacker)` / `ctx.credit(victim, attacker)` set Player
`LastHitBy`/`LastHitAt`. A fall within `KO_CREDIT_WINDOW` s credits the attacker: feed line, `PlayerEliminated.killer`,
`RoundFinished.kos` / `.mvp`, coins via Economy.

## GameState attributes (`ReplicatedStorage.GameState`, written by Core)
| Attribute | Type | Meaning |
|---|---|---|
| `Phase` | string | one of `GameState.Phase` (Waiting/Lobby/Roulette/ModifierRoulette/Intro/Countdown/Round/End) |
| `PhaseEnd` | number | `workspace:GetServerTimeNow()` when the phase ends (0 = open-ended, e.g. LobbyHold) |
| `PhaseStart` | number | [v2] server time the current phase began |
| `RoundNumber` | number | increments every round |
| `MinigameId` | string | chosen minigame (set at the START of Roulette) |
| `RouletteReel` | string | CSV of minigame ids in reel order (ends on MinigameId) |
| `ModifierId` / `ModifierReel` | string | as v1 |
| `MinigameKind` | string | "survival" (v2: always) |
| `Alive` / `Participants` | number | alive count / how many started the round |
| `ScoresJson` | string | score kind only (unused in v2) |
| `WinnersCsv` / `ResultText` | string | set in End |
| `QueuedCount` | number | [v2] players currently in the PLAY square |
| `LobbyHold` | bool | [v2] lobby timer ran out with nobody queued; waiting for someone to step in |
| `VoteOptions` | string | [v2] CSV of the 3 minigame ids offered this lobby |
| `VoteCounts` | string | [v2] JSON `{ [minigameId]: votes }` |
| `SuddenDeath` | bool | [v2] the round passed `SUDDEN_DEATH_AT` |

Minigame metadata: `ReplicatedStorage.MinigameInfo.<Id>` (Configuration) attributes `DisplayName`, `Rules`, `Keys`
(CSV), `Kind`, `SoloCapable`, `Duration`, `Hidden`, [v2] `MinPlayers`, `Icon` (Assets key), `Color` (Color3).
Modifier metadata: `ReplicatedStorage.ModifierInfo.<Id>` `DisplayName`, `Description`.

## Player / character attributes (v2 complete list)
| Where | Attribute | Owner | Meaning |
|---|---|---|---|
| Player | `InRound` | Core | currently ALIVE in the main round |
| Player | `Eliminated` | Core | [v2] was knocked out of the current main round (cleared at round end) |
| Player | `Spectating` | Core | [v2] camera is following the round (chosen via `Core_DeathChoice` / WATCH) |
| Player | `Queued` | Core | [v2] standing in the PLAY square (will play the next round) |
| Player | `Vote` | Core | [v2] minigame id this player voted for ("" = none) |
| Player | `ReviveUntil` | Core | [v2] server time the revive offer expires (0 = no offer) |
| Player | `LastHitBy` / `LastHitAt` | Core | [v2] KO credit bookkeeping (UserId / server time) |
| Player | `KOs` | Core | [v2] KO credits this round (reset at round start) |
| Player | `InSolo` | Solo | playing a private Solo Record run (Core skips them) |
| Player | `Upg_*` | Economy | upgrade levels 0..5 |
| Player | `Cos_Trail`, `Cos_DashColor`, `Cos_BatColor`, `Cos_WinEffect`, `Cos_BombSkin` | Economy | equipped cosmetic id ("" = default) |
| Player | `Coins`, `Level`, `XP`, `XPNext`, `EconomyLoaded`, `Owned_Cosmetics`, `Pass_*` | Economy | as v1 |
| Player | `Spins` | Economy | [v2] wheel spin tokens (free + bought) |
| Player | `FreeSpinReady` | Economy | [v2] today's free spin not used yet |
| Player | `DailyReady`, `CalendarDay`, `LoginStreak` | Economy | [v2] daily chest calendar (day 1..7) |
| Player | `GroupReady` | Economy | [v2] group chest claimable today (member) |
| Player | `GiftIndex`, `GiftAt` | Economy | [v2] next playtime gift index (1-based) and server time it becomes claimable |
| Player | `BoostUntil` | Economy | [v2] server time a 2x coins boost ends |
| Player | `ReviveTokens` | Economy | [v2] free revives owned |
| Player | `StarterOwned`, `FirstJoin` | Economy | [v2] starter pack bought; first join time (Galaxy welcome deal = 48 h after) |
| Player | `RoundStreak` | Economy | [v2] consecutive main rounds played (coin multiplier) |
| Player | `PaidRandomRestricted` | Economy | [v2] PolicyService: hide PAID spins (free spins still work) |
| Player | `LastReward` | Economy | [v2] JSON of the last round's coin breakdown `{ total, xp, lines = { {label, coins} } }` |
| Player | `Set_Music`, `Set_SFX`, `Set_Shake` | Economy | [v2] settings (missing = true), persisted |
| Player | `Seen_Tutorial` | UI/Economy | onboarding done |
| Character | `Sliding`, `Dashing`, `DashCount` | Movement | server-side movement state |
| Character | `SlideStartAt`, `SlideEndAt` | Movement | [v2] client-reported slide window (server time, clamped) |
| Character | `Stunned`, `StunnedUntil` | Core | knockback stun |
| Character | `ShieldUntil` | Core | [v2] server time; hazards/knockback/bomb ignore the player before it |
| Character | `HasBomb`, `BombFuseEnd` | Bomb Tag | [v2] |
`leaderstats`: Core creates `Wins` and `Streak`; Economy adds `Coins` and persists Wins.

## Remotes (v2 complete list; all via `Shared.Net`)
| Name | Dir | Owner | Payload |
|---|---|---|---|
| `Core_Announce` | S→C | Core | (kind "big"/"feed"/"toast", text, sub?, colorHex?) |
| `Core_Knockback` | S→C | Core | knockback to the owner (Knockback.lua) |
| `Core_Vote` | C→S | Core | [v2] (minigameId) — must be in VoteOptions, player Queued, rate limited |
| `Core_Death` | S→C | Core | [v2] to the victim: `{ reason, placement, total, survived, aliveLeft, minigameId, killerName?, revive = { offered: bool, endsAt: number, tokens: number } }` |
| `Core_DeathChoice` | C→S | Core | [v2] ("spectate" \| "lobby") — also used by lobby players to watch ("spectate") / stop ("lobby") |
| `Core_Fx` | S→C | Core | [v2] (kind "splash"/"boom"/"poof"/"ko", position: Vector3) to the round audience |
| `Movement_Dash` | C→S | Movement | [v2] (t: number client server-time) |
| `Movement_Slide` | C→S | Movement | [v2] (active: boolean, t: number) |
| `Movement_JumpFx` | C↔S | Movement | visual tricks (unreliable) |
| `Audio_Play` | S→C | Audio | (key, opts?) one client's 2D sound |
| `UI_TutorialDone` | C→S | UI | as v1 |
| `Economy_BuyUpgrade` / `_BuyCosmetic` / `_Equip` / `_Result` | | Economy | as v1 |
| `Economy_Claim` | C→S func | Economy | [v2] (kind "daily" \| "group" \| "gift") → `{ ok, reward = { coins?, spins?, items?, boostSeconds? }, message }` |
| `Economy_Spin` | C→S func | Economy | [v2] () → `{ ok, index (1-based slice), prize = {...}, spinsLeft, message }`; server RNG |
| `Economy_UseRevive` | C→S | Economy | [v2] () — consume a token and revive; reply via `Economy_Result` action "revive" |
| `Economy_Settings` | C→S | Economy | [v2] ({ music: bool, sfx: bool, shake: bool }) rate limited |
| `Economy_DevBuy` | C→S | Economy | [v2] (productKey) — ONLY created/handled when `RunService:IsStudio()`; grants as a purchase |
| `Economy_Reward` | S→C | Economy | [v2] (kind, reward table) for reveal animations (chest open, spin result, level up) |
| `Solo_Start` / `Solo_Quit` / `Solo_State` | | Solo | as v1 |
| `<Minigame>_*` | | that minigame | e.g. `BombTag_Fx`, `LaserTracer_Zap` |

## Server APIs other pieces may call (same server VM)
- `require(ServerScriptService.Server.Core.Revive)`: `Revive.status(player) -> "ok"|"noOffer"|"expired"|"used"|"notEligible"`,
  `Revive.revive(player) -> boolean` (Core).
- `require(ServerScriptService.Server.Movement.Forgive)`: see Contracts/Minigame.lua "HIT JUDGING" (Movement).
- `require(ServerScriptService.Server.Economy)`: `getProfile(player)`, `addCoins(player, n, reason)` (+ v2
  `applyBundle(player, bundle, reason)`) (Economy).
- `require(ServerScriptService.Server.Combat.Bat)` / `.BatTool` (Spin piece; any minigame may give bats).

## Lobby model contract (`src/shared/Maps/Lobby.lua` → Model `workspace.Lobby`)
Children the other systems rely on (exact names): Folder `Spawns` (12 BaseParts, facing the PLAY square); Part
`PlayZone` (the 30x30 PLAY pad, top surface at LOBBY_CENTER.Y; Core detects players in `JOIN_ZONE_SIZE` above it);
BillboardGui/SurfaceGui stations are decorated by the World piece; anchor Parts `WheelAnchor`, `ShopAnchor`,
`DailyChestAnchor`, `GroupChestAnchor`, `SoloPortalAnchor`, `WatchAnchor` (live TV), `LeaderboardAnchor` (solo TOP 10),
`WinsBoardAnchor`, `LevelBoardAnchor` (16x10 board faces). Interactive stations carry a `ProximityPrompt` with
attribute `PD_Action` ∈ {"Shop","Wheel","Daily","Group","Solo","Watch"} (ActionText one word, HoldDuration 0,
MaxActivationDistance 10). The CLIENT system that owns each panel opens it on
`ProximityPromptService.PromptTriggered` when `prompt:GetAttribute("PD_Action")` matches (Shop/Wheel/Daily/Group →
Shop UI piece, Solo → Solo piece, Watch → HUD piece).

## UI conventions (v2)
- Use `Shared.UIKit` for everything (it encodes the ART_BIBLE style: chunky outlined text, gradient buttons with a
  3D bottom edge, icon tiles with labels straddling the bottom, rainbow-header panels with a big red X, pills,
  badges, toasts, Robux price tags with optional strikethrough). Never hand-roll another kit. **No emoji** anywhere:
  images come from `Shared.Assets` (`Assets.icon("coin")`).
- Layout = docks + lanes from UIKit: `UIKit.Dock.add("Left"|"Right"|"TopOffers"|"TopRight", def)` places icon
  tiles; bottom-center content goes through `UIKit.Lanes` (Toast / Action / Bottom). Display orders come from
  `UIKit.Style.Layers`. Every ScreenGui comes from `UIKit.screen(name, layer)` (ResetOnSpawn false, IgnoreGuiInset,
  UIScale for phones). Design at 1080p pixel sizes; UIKit scales down to phones (800x360) automatically.
- Every button plays the click sound (UIKit buttons do it; any other GuiButton gets it from the global hook in the
  Audio client piece). Panels close with Escape / the X / tapping the dim background.
- HUD visibility rules: round overlays (intro, countdown, alive pill, results) only for round members
  (`InRound` or `Eliminated` or `Spectating`). Lobby HUD (docks, offers, timers) hidden while `InRound`.
  Shop/panels cannot be opened while `InRound`; open panels close at Intro if you are a participant.
- The default Roblox PlayerList is disabled (custom HUD).

## Audio (v2)
`Shared.Audio` only. Keys in `Shared.Assets.Sounds` (see `assets/sounds.json`). Music: the Audio client piece
crossfades lobby / round / Bomb Tag tracks by context; everyone else only plays SFX keys. Settings mute via Player
attributes `Set_Music`, `Set_SFX` (Audio applies them to the SoundGroups).

## Art conventions (v2) — see docs/v2/ART_BIBLE.md
Build maps with `Shared.Art` (voxel blocks with tinted seamless textures: bevel tiles, studs, checker, bricks,
planks; cartoon water). Every map has its own palette (`Theme.Maps.<Id>`), and **no floor may be close to the sea or
sky colour**. Hazards are readable by shape/colour, never by text. No pastel wash, no white glare.

## Debug hooks (workspace attributes; honored ONLY when `RunService:IsStudio()`)
`Debug_ForceMinigame` (string), `Debug_ForceModifier` (string), `Debug_FastIntermission` (bool, ~2 s phases),
`Debug_NoEliminate` (bool: falls put you back on the map), `Debug_IntensityOverride` (number),
[v2] `Debug_AutoQueue` (bool: every player counts as queued), `Debug_FreeRevive` (bool: revive without Robux/tokens,
and offered even with 1 participant), `Debug_ForceVote` (string: the vote resolves to this id).

## Run modes in one server
The main round (Core) and any number of Solo copies run at the same time: no module-level mutable state in
minigames, everything relative to `ctx.center`, client visuals keyed by their map Model.

## Knockback
Server `ctx.knockback(player, dir, power, stun?, attacker?)` → `Knockback.apply` → `Core_Knockback` to the owner →
the client applies velocity + a short tumble, then recovers cleanly. Shielded players are ignored.

## Testing in Studio (how critics and the lead verify)
1. `python3 tools/devserver.py` runs on 127.0.0.1:8765 (the lead keeps it alive).
2. **Studio is a single shared resource. Before ANY Studio tool call run `tools/lock.sh acquire studio <you>`
   (repeat while it exits 2) and ALWAYS `tools/lock.sh release studio <you>` when done** (also on failure).
3. Edit mode: run `tools/studio_pull.luau` (replace `__ROOT__` with the absolute worktree path) through
   `execute_luau` (datamodel Edit). It rebuilds Shared/Server/Client/ReplicatedFirst from that tree.
4. Set debug hooks in Edit, `start_stop_play` → play, inspect with `execute_luau` (Server/Client), `get_console_output`,
   `screen_capture`, `user_keyboard_input`, `character_navigation`. Stop play when done; leave Studio in Edit mode.
5. **The Mac screen is locked overnight: Studio renders the GUI but the 3D viewport is BLACK.** To look at a map, export
   it with `tools/scene_export.luau` (execute_luau; writes JSON through the devserver) and render previews with
   `python3 tools/render_scene.py scene.json out.png --view iso|top|eye|low` (then Read the PNG). GUI screens can be
   judged from `screen_capture` directly.
6. Only one Studio play session at a time; keep sessions short and scripted (batch checks in one execute_luau).

## Builder rules
- Touch only the files your piece owns (listed in your prompt). Never delete or revert a file you did not create.
  If `git status` shows unexpected changes outside your ownership, report them and do not "clean them up".
- Builders do NOT use Roblox Studio (critics do). Builders may use `tools/render_scene.py` on exported scenes.
- Run `tools/bin/selene src/` and `tools/bin/stylua --check src/` (binaries in the MAIN checkout
  `/Users/jannawrot/Desktop/roblox-julek-temp/tools/bin/`), and `tools/bin/rojo build default.project.json -o /tmp/<piece>.rbxl`.
- All player-facing text is English. No emoji. No Polish strings. Short words on screen (≤ 4 words during play).
- Never trust the client: validate remote arguments, rate-limit, keep authority on the server.
- Performance: no per-frame `Instance.new`, pool where sensible, clean everything you create.
- Quality bar: "made by a professional Roblox studio". Juicy (tweens, pops, sounds), readable, consistent, bug-free.

## Piece ownership (v2 gauntlet)
| Piece | Owns |
|---|---|
| V1 Core | `src/server/Core/` except LightingSetup.lua/World.lua/Stands.lua; `src/server/Main.server.lua`; `src/shared/Knockback.lua`; `src/client/Core/`; `src/server/Minigames/_Sandbox/` |
| V2 Movement | `src/client/Movement/`, `src/server/Movement/`, `src/shared/Movement/` |
| V3 World & Lobby | `src/server/Core/LightingSetup.lua`, `src/server/Core/World.lua`, `src/server/Core/Stands.lua`, `src/shared/Maps/Lobby.lua`, `src/shared/LightingData.lua`, `src/client/World/` |
| V4 Economy | `src/server/Economy/`, `src/shared/Economy/` |
| V5 HUD | `src/client/UI/`, `src/server/UI/`, `src/client/Spectate/` |
| V6 Boot/Audio/Settings | `src/first/`, `src/client/Audio/`, `src/client/Settings/` |
| V7 Bomb Tag | `src/server/Minigames/BombTag/`, `src/client/Minigames/BombTag/`, `src/shared/Minigames/BombTag/`, deletes `src/*/Minigames/KingOfTheHill/` |
| V8 Laser Tracer | `src/server/Minigames/LaserTracer/`, `src/client/Minigames/LaserTracer/`, `src/shared/Minigames/LaserTracer/` |
| V9 Hole in the Wall | `src/server/Minigames/HoleInTheWall/`, `src/client/Minigames/HoleInTheWall/`, `src/shared/Minigames/HoleInTheWall/` |
| V10 Spin + Combat | `src/server/Minigames/Spin/`, `src/client/Minigames/Spin/`, `src/shared/Minigames/Spin/`, `src/server/Combat/`, `src/client/Combat/` |
| V11 Dodgeball | `src/server/Minigames/Dodgeball/`, `src/client/Minigames/Dodgeball/`, `src/shared/Minigames/Dodgeball/` |
| V12 Shop & Rewards UI | `src/client/Shop/`, `src/client/Rewards/` |
| V13 Social & Solo | `src/server/Solo/`, `src/client/Solo/`, `src/server/Leaderboards/`, `src/client/Leaderboards/` |
