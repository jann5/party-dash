-- Party Dash Core: per-player setup (leaderstats, attributes) and placing every new character.
local Players = game:GetService("Players")

local Places = require(script.Parent.Places)
local State = require(script.Parent.State)

local PlayerSetup = {}

local function intValue(parent: Instance, name: string)
	if not parent:FindFirstChild(name) then
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = 0
		v.Parent = parent
	end
end

local function onCharacter(player: Player, character: Model)
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		task.wait() -- let the default spawn finish first
		if player.Character ~= character then
			return
		end
		Places.route(player)
	end)
end

local function onPlayerAdded(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	intValue(stats, "Wins")
	intValue(stats, "Streak")
	player:SetAttribute("InRound", false)
	player:SetAttribute("Spectating", State.arenaActive)

	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

function PlayerSetup.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		State.lastPlayed[p] = nil
	end)
end

function PlayerSetup.stat(player: Player, name: string): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		return v
	end
	return nil
end

return PlayerSetup
