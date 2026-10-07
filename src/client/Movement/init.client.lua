-- Party Dash movement (client boot). Boots itself; see the child modules:
--   Controller  dash / slide input + motion (LeftShift / Q / C / LeftCtrl / gamepad X, B / touch pad) + jump assist
--   JumpAssist  coyote time + jump buffer
--   Pose        procedural joint layers for every character: turn / dash lean, slide tackle (Tackle), jump tricks
--   Effects     dust, heel streaks, dash trail / afterimage / rings, dash + slide sounds
--   JumpFx      jump tricks + rainbow trail + landing ring (relayed through an unreliable remote)
--   Hud         PC dash indicator, mobile action pad feedback, speed lines (no slide bar anywhere)
--   Animations  official "Cartoony" animation package on the local character
-- Shared.Movement.CameraFx (camera shake / FOV) and Shared.Movement.ActionButton (mobile pad) are started here too.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraFx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Movement"):WaitForChild("CameraFx"))

local Rigs = require(script.Rigs)

local function boot(name: string)
	local ok, err = pcall(function()
		require(script:WaitForChild(name)).start()
	end)
	if not ok then
		warn(("[Movement] %s failed to start: %s"):format(name, tostring(err)))
	end
end

CameraFx.start()
-- Listeners register first, then the rig tracker starts emitting characters.
boot("Pose")
boot("Effects")
boot("JumpFx")
boot("Animations")
boot("Controller")
boot("Hud")
Rigs.start()
