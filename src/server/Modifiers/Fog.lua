-- Modifier FOG: visibility drops to ~45 studs. Lighting is per client, so the effect lives in
-- src/client/Modifiers/Fog.lua (only for players InRound; spectators keep a clear view).
return {
	id = "Fog",
	displayName = "FOG",
	description = "Thick fog rolls in. You can barely see a thing!",
	apply = function(_ctx) end,
	clear = function(_ctx) end,
}
