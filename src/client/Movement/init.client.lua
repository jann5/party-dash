-- Party Dash movement (client boot). Boots itself; see the child modules:
--   Controller  dash / slide input + motion (LeftShift, C / LeftCtrl, touch buttons)
--   Hud         MovementHUD: dash cooldown bar, mobile button skins, speed lines
--   Pose        procedural lean / dash lean / slide pose for every character
--   Effects     dust, trails, afterimages, rings, sounds, FOV punch
--   JumpFx      jump flips + rainbow trail + landing ring (ported from the legacy game)
--   Animations  official "Cartoony" animation package on the local character
local Rigs = require(script.Rigs)

local function boot(name: string)
	local ok, err = pcall(function()
		require(script:WaitForChild(name)).start()
	end)
	if not ok then
		warn(("[Movement] %s failed to start: %s"):format(name, tostring(err)))
	end
end

-- Listeners register first, then the rig tracker starts emitting characters.
boot("Hud")
boot("Pose")
boot("Effects")
boot("JumpFx")
boot("Animations")
boot("Controller")
Rigs.start()
