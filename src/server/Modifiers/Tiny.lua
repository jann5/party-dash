-- Modifier TINY: every player in the round is scaled down to 0.6x (Model:ScaleTo), restored when knocked
-- out or when the round ends. Respawned characters are scaled again.
local CharacterEffect = require(script.Parent:WaitForChild("_Lib").CharacterEffect)

return CharacterEffect.scaleModifier("Tiny", "TINY", "Everyone is teeny tiny! Watch your step.", 0.6)
