-- Party Dash: global tuning constants shared by server and client.
-- FROZEN CONTRACT: pieces read from here; changing a value is fine, renaming/removing a key is not.
local Config = {}

Config.GAME_NAME = "Party Dash"
Config.MAX_PLAYERS = 12

-- Phase durations (seconds). Debug_FastIntermission shortens Lobby/Roulette/Intro/End to ~2s.
Config.LOBBY_TIME = 15
Config.ROULETTE_TIME = 5
Config.MODIFIER_ROULETTE_TIME = 4
Config.INTRO_TIME = 4
Config.COUNTDOWN_TIME = 3
Config.END_TIME = 6
Config.MODIFIER_EVERY = 5 -- every Nth round gets a global modifier
Config.SAFETY_ROUND_LIMIT = 300 -- hard fuse against bugs only; survival rounds normally end by elimination
Config.MIN_LOBBY_PLAYERS = 1 -- rounds start even with a single player

-- Escalation: ctx.intensity() = (1 + elapsed / INTENSITY_RAMP_SECONDS) * modifier multiplier.
Config.INTENSITY_RAMP_SECONDS = 35

-- World layout. The main arena is built around ARENA_CENTER; maps must position everything relative
-- to ctx.center so the same minigame can also run as a private Solo copy at another origin.
Config.ARENA_CENTER = Vector3.new(0, 50, 0)
Config.KILL_DEPTH = 30 -- default killY = center.Y - KILL_DEPTH (a map may override with a KillY attribute)
Config.LOBBY_CENTER = Vector3.new(0, 50, 0) -- the lobby is a "map" loaded in the same spot between rounds
Config.SPECTATOR_OFFSET = Vector3.new(0, 45, -110) -- spectator platform position relative to ARENA_CENTER
Config.SOLO_ORIGIN = Vector3.new(6000, 50, 0) -- first private solo copy
Config.SOLO_SPACING = 1500 -- each further solo copy is offset along +Z by this much

-- Movement (P2). Upgrade attributes on the Player modify these (see docs/ARCHITECTURE.md).
Config.WALK_SPEED = 20
Config.JUMP_POWER = 52
Config.DASH_COOLDOWN = 2.5
Config.DASH_DISTANCE = 18
Config.DASH_DURATION = 0.22
Config.SLIDE_DURATION = 0.75
Config.SLIDE_COOLDOWN = 0.4

-- Knockback defaults (P1 Knockback module).
Config.KNOCKBACK_STUN = 0.6

-- Economy (P9).
Config.COINS_PARTICIPATE = 5
Config.COINS_PER_SURVIVAL_10S = 1
Config.COINS_WIN = 25
Config.MODIFIER_COIN_MULTIPLIER = 2
Config.DAILY_REWARD = 50
Config.UPGRADE_MAX_LEVEL = 5
Config.UPGRADES = {
	DashCooldown = { name = "Dash Cooldown", perLevel = -0.06, prices = { 100, 200, 400, 700, 1100 } },
	DashDistance = { name = "Dash Distance", perLevel = 0.06, prices = { 100, 200, 400, 700, 1100 } },
	BatPower = { name = "Bat Power", perLevel = 0.06, prices = { 80, 160, 320, 560, 900 } },
	JumpBoost = { name = "Jump Boost", perLevel = 0.03, prices = { 80, 160, 320, 560, 900 } },
}

-- Robux products. 0 = not created yet; the user fills these in from Creator Hub.
Config.PRODUCTS = {
	Coins500 = 0,
	Coins1500 = 0,
	Coins5000 = 0,
	-- each buys the next level of that upgrade directly
	UpgradeDashCooldown = 0,
	UpgradeDashDistance = 0,
	UpgradeBatPower = 0,
	UpgradeJumpBoost = 0,
}
Config.GAMEPASSES = {
	DoubleCoins = 0,
	VIP = 0,
}

return Config
