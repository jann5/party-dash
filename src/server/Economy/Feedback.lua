--!strict
-- Everything Economy tells a client: toasts, request results (Economy_Result), reveal events (Economy_Reward)
-- and 2D sounds. One place, so no module needs another just to talk to the player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Announce = require(script.Parent.Parent.Announce)

local Feedback = {}

local resultRemote = Net.event(Rules.Remote.Result)
local rewardRemote = Net.event(Rules.Remote.Reward)

local function online(player: Player): boolean
	return player.Parent == Players
end

-- Small transient notice (green by default: good news).
function Feedback.toast(player: Player, text: string, color: Color3?)
	if online(player) then
		Announce.toast(player, text, color or Theme.Colors.Green)
	end
end

-- Answer to a client request: (ok, action, id, message).
function Feedback.result(player: Player, ok: boolean, action: string, id: string, message: string)
	if online(player) then
		resultRemote:FireClient(player, ok, action, id, message)
	end
end

-- Reveal event for the reward UI: kind "spin" | "daily" | "group" | "gift" | "levelup" | "purchase".
function Feedback.reward(player: Player, kind: string, payload: { [string]: any })
	if online(player) then
		rewardRemote:FireClient(player, kind, payload)
	end
end

function Feedback.sound(player: Player, key: string)
	if online(player) then
		Audio.forPlayer(player, key)
	end
end

return Feedback
