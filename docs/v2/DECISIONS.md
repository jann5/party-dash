# v2 lead decisions (these OVERRIDE GAME_DESIGN.md / ART_BIBLE.md / audits wherever they disagree)

The frozen contracts (`src/shared/Config.lua`, `Theme.lua`, `Assets.lua`, `Art.lua`, `Audio.lua`, `UIKit/`,
`Products.lua`, `Purchase.lua`, `Contracts/Minigame.lua`, `server/Signals.lua`, `docs/ARCHITECTURE.md`) are the truth.

## World
- `ARENA_CENTER = (0,50,0)` (unchanged). `LOBBY_CENTER = (0,50,-340)`: the lobby is 340 studs SOUTH of the arena, so
  players spawn facing +Z and see the arena island behind the PLAY arch. (ART_BIBLE 5.1 proposed the mirror image:
  lobby at 0 and arena at +340. Same layout, our numbers win.)
- `SEA_LEVEL = 36`, `SEA_DROP = 14`, `KILL_DEPTH = 17` (killY 3 studs under the water). No stands are built.
- The world-building helper is `src/shared/Art.lua` (ART_BIBLE calls it WorldKit). Recipe names = ART_BIBLE 3.3
  names: `grass_top, grass_lip, dirt_cliff, dirt_cliff_low, stone, stone_top, stone_all, wood, wood_rail, sand,
  paver, hazard_trim, toy_block, lt_tile, lt_tile_alt, steel, maple, turf_check, brick_wall, foam_mat, leaf,
  leaf_dark, trunk, awning, checker_pad, plain, cloud, water`. Override the tint per call with `{ color = ... }`.
- Textures available (`Assets.Textures`): tile_bevel, tile_bevel_2x2, studs, checker, checker_soft, bricks, planks,
  waves, hazard, speckle, grass_top, stone_blocks, awning, laser_dash, stripes_diag, glow_soft.
  Art: `Assets.Art.logo`, `Assets.Art.loading_bg`, `Assets.Art.wheel_face` (8 wedges, wedge 1 at 12 o'clock, clockwise).
- Lighting: ART_BIBLE 2.2 values. Studio-only settings (Technology) cannot be set by scripts; leave them.

## Rules
- Bomb Tag `minPlayers = 2` (GAME_DESIGN says 3). Fuse 10 s, pass on touch (server-side proximity), no tag-back 1 s.
- All v2 minigames are survival. KO credit through `ctx.knockback(..., attacker)` / `ctx.credit`.
- Dash cooldown 2.0 s, slide cooldown 0.9 s (no bar), coyote 0.10 s, jump buffer 0.12 s (see Config).
- Vote: 3 options, `Debug_ForceVote` / `Debug_ForceMinigame` for tests.

## Money (Shared.Products is the catalog; prices are final)
Wheel 9 R$ (1 spin) / 39 R$ (5 spins); Revive 19 R$; Starter Pack 49 R$ (1,000 coins + Starter Spark trail + 2x coins
30 min, one-time); Galaxy Comet trail 19 R$ welcome deal for 48 h after first join, otherwise 199 R$ (LIMITED, honest
strikethrough); coins 25/65/179 R$ for 500/1,500/5,000; upgrade levels 25 R$; 2X Coins pass 149 R$; VIP pass 249 R$.
Paid spins are paid random items: show ODDS before buying and hide paid spin buttons when
`PaidRandomRestricted` (PolicyService). Free spins always work.

## Icons
Use `Assets.icon(key)`. Real icons exist for: shop, chest_daily, chest_group, wheel, gift, settings, trophy,
stopwatch, crown, coin, coin_stack, coin_sack, coin_chest, xp_star, lightning, revive_heart, spectate_eye, home, bomb,
bat, trail_rainbow, speed_shoe, spring, hourglass, party_popper, music, speaker, mg_lasertracer, mg_dodgeball,
mg_holeinthewall, mg_spin, mg_bombtag, mg_random, medal, join_pad, lock, starter_pack, trail_fire, trail_galaxy,
trail_gold, trail_ice, explosion, coins_x2, vip_ticket, potion.
PLANNED keys (usable now; they show a similar icon until the lead generates the real one tonight): fire_streak,
calendar_star, thumbs_up, group_friends, check_badge, sale_tag, alarm_clock, spin_ticket, skull_out, mod_low_gravity,
mod_turbo, mod_fog, mod_giant, mod_tiny, mod_slippery, podium, boost_xp, vip_badge, hit_star, splash, arrow_jump,
arrow_slide, trail_hearts, trail_lightning, trail_bubbles, win_fireworks, win_crown_rain, win_star_sparkles,
action_dash, action_slide, action_swing, action_throw, mega_chest, coin_mountain, target_lock.
Minigame card icons: `mg_<lowercase id>` (mg_bombtag, mg_lasertracer, mg_dodgeball, mg_holeinthewall, mg_spin,
mg_random). The minigame definition's `icon` field uses these keys.

## Sounds (`Assets.Sounds`, play through `Shared.Audio`)
MusicLobby1, MusicLobby2, MusicRound (+ *Alt backups), UiClick, UiHover, UiOpen, UiError, Purchase, CoinCollect,
LevelUp, ChestOpen, WheelTick, WheelWin, Countdown, Go, Win, Eliminated, Hit, BatSwing, Dash, Slide, Jump, Land,
BombTick, BombFuse, BombPass, Explosion, LaserHum, LaserZap, WallWhoosh, Cannon, Splash (each also has `<Key>Alt`).
