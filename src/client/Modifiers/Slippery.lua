--!strict
-- SLIPPERY (client): icy momentum for our own character. The Humanoid snaps to its walk velocity every
-- step, so after physics we blend the horizontal velocity toward that target slowly: speeding up, braking
-- and turning all glide. The server also drops the character parts' friction (Modifiers/Slippery.lua).
-- Dash / slide movers and knockback stuns are left alone (they own the velocity while they run).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GRIP = 2.6 -- 1/s; lower = icier

local function moverActive(root: BasePart): boolean
	for _, child in root:GetChildren() do
		if child:IsA("LinearVelocity") and child.Enabled then
			return true
		end
	end
	return false
end

return {
	enable = function(): () -> ()
		local player = Players.LocalPlayer
		local glide: Vector3? = nil
		local conn = RunService.Heartbeat:Connect(function(dt: number)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
				glide = nil
				return
			end
			local v = root.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z)
			if
				root.Anchored
				or humanoid.PlatformStand
				or character:GetAttribute("Stunned") == true
				or moverActive(root)
			then
				glide = flat -- keep the momentum these systems produced
				return
			end
			if glide == nil then
				glide = flat
				return
			end
			local blended = (glide :: Vector3):Lerp(flat, 1 - math.exp(-GRIP * dt))
			glide = blended
			root.AssemblyLinearVelocity = Vector3.new(blended.X, v.Y, blended.Z)
		end)
		return function()
			conn:Disconnect()
		end
	end,
}
