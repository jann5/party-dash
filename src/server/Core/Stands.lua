--[[
Party Dash Core: spectator stands (legacy API). v2 builds NO stands: spectating is camera-only and the character
stays in the lobby (docs/ARCHITECTURE.md "World layout"). The module keeps its API so older callers never error:
	Stands.build()          creates nothing, returns nil
	Stands.randomFloor()    a lobby spawn floor (where a would-be stands visitor stands instead)
	Stands.contains(pos)    always false
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lobby = require(Shared.Maps.Lobby)

local Stands = {}

function Stands.build(): nil
	return nil
end

-- Floor CFrame (top surface, facing +Z toward the PLAY pad) on a random lobby spawn, or the spawn pad centre
-- when the lobby is not built yet.
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
			local spawnPart = spawns[math.random(1, #spawns)]
			return spawnPart.CFrame + Vector3.new(0, spawnPart.Size.Y / 2, 0)
		end
	end
	local pad = Config.LOBBY_CENTER + Lobby.SPAWN_PAD
	return CFrame.lookAt(pad, pad + Vector3.zAxis)
end

function Stands.contains(_position: Vector3): boolean
	return false
end

return Stands
