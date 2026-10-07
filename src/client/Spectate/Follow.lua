--!nonstrict
-- Spectate camera: follows a living participant (a player with InRound = true) and hands the camera back to your
-- own character afterwards. Camera-only: the spectator's character stays safe in the lobby.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Follow = {}

local player = Players.LocalPlayer
local target: Player? = nil

local function humanoidOf(p: Player): Humanoid?
	local character = p.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

-- Living participants, in a stable order so Q / E always step the same way.
function Follow.candidates(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("InRound") == true then
			local humanoid = humanoidOf(p)
			if humanoid and humanoid.Health > 0 then
				table.insert(list, p)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

local function aim()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local humanoid = (target and humanoidOf(target)) or humanoidOf(player)
	if humanoid and camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end
end

function Follow.target(): Player?
	return target
end

-- Keeps the current target if it is still alive in the round, otherwise picks the first one. Returns the target
-- and how many players are alive.
function Follow.refresh(): (Player?, number)
	local list = Follow.candidates()
	if target and not table.find(list, target) then
		target = nil
	end
	if not target then
		target = list[1]
	end
	aim()
	return target, #list
end

-- Steps to the previous (-1) / next (+1) living player.
function Follow.step(dir: number): (Player?, number)
	local list = Follow.candidates()
	if #list == 0 then
		target = nil
	else
		local i = target and table.find(list, target)
		if not i then
			i = dir > 0 and 1 or #list
		else
			i = ((i - 1 + dir) % #list) + 1
		end
		target = list[i]
	end
	aim()
	return target, #list
end

-- Camera back to your own character.
function Follow.stop()
	target = nil
	aim()
end

return Follow
