--!strict
-- Wheel of Fortune (brief #29, GAME_DESIGN 5.3). Economy_Spin (RemoteFunction) spends today's free spin first,
-- otherwise one Spins token; the server rolls (Rules.WHEEL odds) and grants before answering, so leaving
-- mid-animation never loses a prize. PolicyService decides whether PAID spins may be offered to a player.
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local Feedback = require(script.Parent.Feedback)
local Grants = require(script.Parent.Grants)
local Limiter = require(script.Parent.Limiter)
local Mirror = require(script.Parent.Mirror)
local Sessions = require(script.Parent.Sessions)

local Wheel = {}

local rng = Random.new()

export type SpinResult = {
	ok: boolean,
	index: number?, -- 1-based slice in wheel-face order
	prize: { [string]: any }?,
	spinsLeft: number,
	usedFree: boolean?,
	message: string,
}

-- One spin for `player`. Never yields.
function Wheel.spin(player: Player): SpinResult
	local s = Sessions.get(player)
	if not s then
		return { ok = false, spinsLeft = 0, message = "Your save is still loading..." }
	end
	local d = s.data
	local today = Rules.utcDay()
	local usedFree = false
	if d.freeSpinDay ~= today then
		d.freeSpinDay = today
		usedFree = true
	elseif d.spins > 0 then
		d.spins -= 1
	else
		return { ok = false, spinsLeft = 0, message = "No spins left!" }
	end
	Mirror.spins(s)

	local index = Rules.rollWheel(rng)
	local slice = Rules.WHEEL[index]
	local bundle = table.clone(slice.reward) :: any
	bundle.equip = "empty"
	local granted = Grants.applyBundle(player, bundle, "wheel")
	local prize = {
		id = slice.id,
		label = slice.label,
		icon = slice.icon,
		coins = granted and granted.coins or 0,
		spins = granted and granted.spins or 0,
		boostSeconds = granted and granted.boostSeconds or 0,
		items = granted and granted.items or {},
		converted = granted and granted.converted or {},
	}
	local message = if granted then "You won " .. Grants.describe(granted) else "You won!"
	Feedback.reward(player, "spin", { index = index, prize = prize, usedFree = usedFree })
	Sessions.saveSoon(player)
	return {
		ok = true,
		index = index,
		prize = prize,
		spinsLeft = d.spins,
		usedFree = usedFree,
		message = message,
	}
end

-- PolicyService: hide PAID spins where paid random items are restricted (free spins always work).
function Wheel.checkPolicy(player: Player)
	player:SetAttribute(Rules.Attr.PaidRandomRestricted, false)
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	if ok and type(info) == "table" and player.Parent == Players then
		player:SetAttribute(Rules.Attr.PaidRandomRestricted, info.ArePaidRandomItemsRestricted == true)
	end
end

function Wheel.start()
	Net.func(Rules.Remote.Spin).OnServerInvoke = function(player: Player)
		if not Limiter.allow(player, "spin", 6, 2) then
			return { ok = false, spinsLeft = player:GetAttribute(Rules.Attr.Spins) or 0, message = "Slow down!" }
		end
		local ok, result = pcall(Wheel.spin, player)
		if not ok then
			warn("[Economy] spin failed:", result)
			return { ok = false, spinsLeft = player:GetAttribute(Rules.Attr.Spins) or 0, message = "Try again!" }
		end
		return result
	end
end

return Wheel
