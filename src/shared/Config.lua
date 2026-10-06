-- Party Dash: global tuning constants shared by server and client.
-- FROZEN CONTRACT (v2): pieces read from here; changing a value is fine, renaming/removing a key is not.
-- v2 notes are in docs/ARCHITECTURE.md ("v2 changes"). New keys are marked [v2].
local Config = {}

Config.GAME_NAME = "Party Dash"
Config.MAX_PLAYERS = 12

-- Phase durations (seconds). Debug_FastIntermission shortens Lobby/Roulette/Intro/End to ~2s (Studio only).
Config.LOBBY_TIME = 20 -- brief #14: 20 s in the lobby after every round, then the vote reveal / roulette
Config.ROULETTE_TIME = 4
Config.MODIFIER_ROULETTE_TIME = 3
Config.INTRO_TIME = 3
Config.COUNTDOWN_TIME = 3
Config.END_TIME = 5
Config.MODIFIER_EVERY = 5 -- every Nth round gets a global modifier
Config.SAFETY_ROUND_LIMIT = 300 -- hard fuse against bugs only; survival rounds normally end by elimination
Config.MIN_LOBBY_PLAYERS = 1 -- rounds start even with a single queued player
Config.SUDDEN_DEATH_AT = 120 -- [v2] seconds into a round: "SUDDEN DEATH!" and ctx.intensity() doubles
Config.LOBBY_HOLD_RESTART = 8 -- [v2] when the lobby was on hold (nobody queued) and someone steps in: countdown restarts at this

-- Escalation: ctx.intensity() = (1 + elapsed / INTENSITY_RAMP_SECONDS) * modifier multiplier (* 2 after SUDDEN_DEATH_AT).
Config.INTENSITY_RAMP_SECONDS = 30

-- World layout. The main arena is built around ARENA_CENTER; maps must position everything relative
-- to ctx.center so the same minigame can also run as a private Solo copy at another origin.
-- [v2] The lobby is PERMANENT and lives at LOBBY_CENTER, far from the arena (it is never destroyed between rounds).
-- Everything floats over one cartoon sea whose surface is at SEA_LEVEL.
Config.ARENA_CENTER = Vector3.new(0, 50, 0)
Config.SEA_LEVEL = 36 -- [v2] world Y of the sea surface = ARENA_CENTER.Y - SEA_DROP (World.lua builds it)
Config.SEA_DROP = 14 -- [v2] map floors sit this far above the sea; cliffs run down to the water (Solo uses it too)
Config.KILL_DEPTH = 17 -- default killY = center.Y - KILL_DEPTH = 3 studs under the water: you splash, then you are OUT
-- (a map may set a HIGHER KillY attribute, never a lower one)
Config.LOBBY_CENTER = Vector3.new(0, 50, -340) -- [v2] lobby grass top surface; the arena island is 340 studs north (+Z),
-- visible from the PLAY square (keep the +Z corridor between them clear)
Config.LOBBY_RADIUS = 96 -- [v2] boundary walls radius (plateau 128x112 + terraces + wading shelf, see ART_BIBLE 6)
Config.SPECTATOR_OFFSET = Vector3.new(0, 45, -110) -- legacy (v1 stands); v2 does not build stands
Config.SOLO_ORIGIN = Vector3.new(6000, 50, 0) -- first private solo copy
Config.SOLO_SPACING = 1500 -- each further solo copy is offset along +Z by this much

-- [v2] Lobby join square (brief #26) and vote.
Config.JOIN_ZONE_SIZE = Vector3.new(30, 12, 30) -- detection box above the PlayZone pad (X, height, Z)
Config.VOTE_OPTIONS = 3 -- minigame cards offered each lobby
Config.VOTE_RATE_LIMIT = 0.25 -- seconds between accepted Core_Vote calls per player

-- [v2] Death flow, revive and protection.
Config.DEATH_BEAT = 1.0 -- seconds between the knock-out moment and the teleport to the lobby + death panel
Config.REVIVE_WINDOW = 10 -- seconds the revive offer stays open after elimination
Config.REVIVE_MAX_PER_ROUND = 1
Config.REVIVE_MIN_PARTICIPANTS = 3 -- revive is offered only when the round started with at least this many
Config.REVIVE_MIN_OTHERS_ALIVE = 2 -- and at least this many OTHER players are still alive (never buy a 1v1 final)
Config.SPAWN_SHIELD = 3 -- seconds of character attribute ShieldUntil after a revive (hazards and knockback ignore you)
Config.KO_CREDIT_WINDOW = 4 -- seconds: a fall within this time after a player-caused hit credits the attacker

-- Movement (P2 / v2). Upgrade attributes on the Player modify these (see docs/ARCHITECTURE.md).
Config.WALK_SPEED = 20
Config.JUMP_POWER = 52
Config.DASH_COOLDOWN = 2.0
Config.DASH_DISTANCE = 16
Config.DASH_DURATION = 0.18
Config.SLIDE_DURATION = 0.7
Config.SLIDE_COOLDOWN = 0.9 -- brief #11: the slide has a cooldown but NO bar
Config.COYOTE_TIME = 0.10 -- [v2] you can still jump this long after running off a ledge
Config.JUMP_BUFFER = 0.12 -- [v2] a jump pressed this long before landing still fires
Config.CAMERA_FOV = 72 -- [v2]

-- [v2] Hit forgiveness (server Movement/Forgive.lua): how far around a hazard crossing we look for a dodge.
Config.FORGIVE_PAST = 0.06 -- seconds before the crossing
Config.FORGIVE_INTERP = 0.12 -- replication interpolation buffer added on top of the player's ping
Config.FORGIVE_MAX_LAG = 0.30 -- ping is clamped to this

-- Knockback defaults (Core Knockback module).
Config.KNOCKBACK_STUN = 0.6

-- Economy.
Config.COINS_PARTICIPATE = 5
Config.COINS_PER_SURVIVAL_10S = 1
Config.COINS_WIN = 25
Config.COINS_SECOND = 12 -- [v2] placement bonus (3+ participants)
Config.COINS_THIRD = 6 -- [v2]
Config.COINS_PER_KO = 5 -- [v2] max COINS_KO_CAP KOs paid per round
Config.COINS_KO_CAP = 5 -- [v2]
Config.COINS_MVP = 10 -- [v2]
Config.COINS_FIRST_WIN_OF_DAY = 100 -- [v2]
Config.ROUND_STREAK_MULT = { 1.0, 1.1, 1.2, 1.3, 1.5 } -- [v2] coin multiplier by consecutive rounds played (5+ = last)
Config.MODIFIER_COIN_MULTIPLIER = 2
Config.DAILY_REWARD = 50 -- legacy; v2 uses the daily calendar in src/shared/Economy/Rules.lua
Config.UPGRADE_MAX_LEVEL = 5
Config.UPGRADES = {
	DashCooldown = { name = "Dash Cooldown", perLevel = -0.06, prices = { 100, 200, 400, 700, 1100 } },
	DashDistance = { name = "Dash Distance", perLevel = 0.06, prices = { 100, 200, 400, 700, 1100 } },
	BatPower = { name = "Bat Power", perLevel = 0.06, prices = { 80, 160, 320, 560, 900 } },
	JumpBoost = { name = "Jump Boost", perLevel = 0.03, prices = { 80, 160, 320, 560, 900 } },
}

-- [v2] Roblox group for the group chest (brief #27). 0 = not created yet: the group chest then says "Coming soon".
Config.GROUP_ID = 0
-- [v2] End of Season 1 (unix seconds, UTC). The Galaxy Comet trail is sold for 199 R$ until then (19 R$ for each
-- player's first 48 h: the honest "was 199" welcome deal, brief #31). 0 = no season end yet (always on sale).
Config.SEASON1_END = 0
Config.WELCOME_DEAL_SECONDS = 48 * 3600 -- [v2]

-- Robux products. 0 = not created yet; the owner fills these in from Creator Hub (see docs/OWNER_TODO.md).
-- Display prices (shown while an id is 0, and the price to create the product at) live in
-- src/shared/Economy/Products.lua (PRODUCT_INFO). In Studio an id of 0 is bought through the dev path
-- (Economy_DevBuy) so every purchase flow is testable without real ids.
Config.PRODUCTS = {
	Coins500 = 0,
	Coins1500 = 0,
	Coins5000 = 0,
	-- each buys the next level of that upgrade directly
	UpgradeDashCooldown = 0,
	UpgradeDashDistance = 0,
	UpgradeBatPower = 0,
	UpgradeJumpBoost = 0,
	-- [v2]
	WheelSpin1 = 0, -- 9 R$  (brief #29)
	WheelSpin5 = 0, -- 39 R$
	Revive = 0, -- 19 R$ (brief #28)
	StarterPack = 0, -- 49 R$ (brief #30) one-time
	GalaxyTrail19 = 0, -- 19 R$ welcome deal (brief #31)
	GalaxyTrail199 = 0, -- 199 R$ regular Season 1 price
}
Config.GAMEPASSES = {
	DoubleCoins = 0, -- 149 R$
	VIP = 0, -- 249 R$
}

return Config
