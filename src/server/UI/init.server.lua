--!nonstrict
-- Party Dash HUD, server side (V5).
--  * Makes sure what the HUD listens to exists even before Core boots: the GameState configuration, the
--    Core_Announce remote and the Audio sound groups / Audio_Play remote (all idempotent "get or create").
--  * UI_TutorialDone: the client finished the DASH / SLIDE / JUMP hints -> Player.Seen_Tutorial = true
--    (Economy persists it). No payload is accepted; requests are rate limited per player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Net = require(ReplicatedStorage.Shared.Net)
require(ReplicatedStorage.Shared.Audio) -- creates the SoundGroups and Audio_Play the client sounds rely on

GameState.get()
Net.event("Core_Announce")

local tutorialDone = Net.event("UI_TutorialDone")

local COOLDOWN = 2 -- seconds between accepted requests per player
local lastRequest: { [Player]: number } = {}

tutorialDone.OnServerEvent:Connect(function(player: Player)
	if player.Parent ~= Players then
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
