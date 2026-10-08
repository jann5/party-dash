--[[
Party Dash Core: spectator stands. v2 builds NO stands: spectating is camera-only and the spectator's character
stays in the lobby (docs/ARCHITECTURE.md "World layout"). The v1 API stays so older callers never error:

	Stands.build()        -- does nothing, returns nil
	Stands.randomFloor()  -- a floor CFrame on the lobby spawn pad (facing the PLAY square)
	Stands.contains(pos)  -- always false
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lobby = require(Shared.Maps.Lobby)

local Stands = {}

function Stands.build(): nil
	return nil
end

-- Anyone v1 code would send "to the stands" lands on a lobby spawn instead.
function Stands.randomFloor(): CFrame
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Spawns")
	if folder then
		local spawns = {}
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(spawns, child)
			end
		end
		if #spawns > 0 then
			local spawn = spawns[math.random(1, #spawns)]
			return spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2, 0)
		end
	end
	local pad = Config.LOBBY_CENTER + Lobby.SPAWN_PAD_OFFSET + Vector3.new(0, Lobby.SPAWN_PAD_TOP, 0)
	return CFrame.lookAt(pad, pad + Vector3.zAxis)
end

function Stands.contains(_position: Vector3): boolean
	return false
end

return Stands
