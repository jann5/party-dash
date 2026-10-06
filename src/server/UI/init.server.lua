-- Party Dash UI server side (P3).
--  * makes sure the replicated objects the HUD listens to exist even before Core boots
--    (GameState config + Core_Announce remote; both calls are idempotent "get or create")
--  * handles "UI_TutorialDone": marks the Player with Seen_Tutorial = true
--    (persisting it across sessions is the Economy/persistence piece's job)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Net = require(ReplicatedStorage.Shared.Net)

GameState.get()
Net.event("Core_Announce")

local tutorialDone = Net.event("UI_TutorialDone")

local COOLDOWN = 2 -- seconds between accepted requests per player
local lastRequest: { [Player]: number } = {}

tutorialDone.OnServerEvent:Connect(function(player: Player)
	-- The client sends no payload; anything extra is ignored. Only flag real, present players.
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < COOLDOWN then
		return
	end
	lastRequest[player] = now
	if player:GetAttribute("Seen_Tutorial") ~= true then
		player:SetAttribute("Seen_Tutorial", true)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)
