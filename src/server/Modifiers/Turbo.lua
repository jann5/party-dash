-- Modifier TURBO: hazards escalate 1.6x faster. Core folds intensityMultiplier into ctx.intensity(),
-- so there is nothing to apply or restore here.
return {
	id = "Turbo",
	displayName = "TURBO",
	description = "Hazards speed up 60% faster than usual!",
	intensityMultiplier = 1.6,
	apply = function(_ctx) end,
	clear = function(_ctx) end,
}
