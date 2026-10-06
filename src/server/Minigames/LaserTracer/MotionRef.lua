--!strict
--[[
Laser Tracer: gives the server the SAME motion math the clients render with.

The math lives in src/client/Minigames/LaserTracer/Motion.lua (StarterPlayerScripts), the only folder this
piece owns that both sides can reach, so the beams a player sees are exactly the beams the server checks.
]]
local StarterPlayer = game:GetService("StarterPlayer")

export type State = {
	pattern: string, -- "sweep" | "slide"
	kind: string, -- "low" | "high"
	tWarn: number,
	tOn: number,
	tOff: number,
	a: number,
	b: number,
	t0: number,
	s: number,
	revAt: number,
}

local PATH = { "StarterPlayerScripts", "Client", "Minigames", "LaserTracer", "Motion" }

local node: Instance = StarterPlayer
for _, name in PATH do
	local child = node:WaitForChild(name, 10)
	if not child then
		error(("LaserTracer: shared module StarterPlayer.%s is missing"):format(table.concat(PATH, ".")))
	end
	node = child
end

return require(node :: ModuleScript) :: any
