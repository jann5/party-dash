-- Modifier LOW GRAVITY: floaty moon jumps. Characters are simulated by their own client, so the effect
-- lives in src/client/Modifiers/LowGravity.lua (local workspace.Gravity while the player is InRound).
-- The server has nothing to change, which also keeps Solo copies and spectators untouched.
return {
	id = "LowGravity",
	displayName = "LOW GRAVITY",
	description = "Moon jumps! Gravity is way down.",
	apply = function(_ctx) end,
	clear = function(_ctx) end,
}
