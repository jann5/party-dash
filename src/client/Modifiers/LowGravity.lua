--!strict
-- LOW GRAVITY (client): our character is simulated on this client, so lowering the local
-- workspace.Gravity gives floaty moon jumps for us only (spectators and Solo players are unaffected).
local GRAVITY = 70
local DEFAULT_GRAVITY = 196.2

return {
	enable = function(): () -> ()
		local previous = workspace.Gravity
		if math.abs(previous - GRAVITY) < 1e-3 then
			previous = DEFAULT_GRAVITY -- never "restore" to the low value itself
		end
		workspace.Gravity = GRAVITY
		return function()
			workspace.Gravity = previous
		end
	end,
}
