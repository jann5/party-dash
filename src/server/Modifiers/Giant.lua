-- Modifier GIANT: every player in the round is scaled up 1.6x (Model:ScaleTo), restored when knocked out
-- or when the round ends. Respawned characters are scaled again.
local CharacterEffect = require(script.Parent:WaitForChild("_Lib").CharacterEffect)

return CharacterEffect.scaleModifier("Giant", "GIANT", "Everyone is HUGE! Big bodies, big targets.", 1.6)
