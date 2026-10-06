--!strict
-- Client requests: buy upgrade, buy cosmetic, equip. Everything is validated here; the client only
-- ever asks. Each request is answered on Economy_Result (ok, action, id, message) for UI feedback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local Sessions = require(script.Parent.Sessions)

local Remotes = {}

local MAX_ID_LENGTH = 40

-- Token bucket per player: bursts of BURST requests, refilling RATE per second.
local BURST = 10
local RATE = 4
local buckets: { [Player]: { tokens: number, at: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = BURST, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(BURST, b.tokens + (now - b.at) * RATE)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

local resultRemote: RemoteEvent

local function reply(player: Player, ok: boolean, action: string, id: string, message: string)
	if player.Parent == Players then
		resultRemote:FireClient(player, ok, action, id, message)
	end
end

-- Returns (ok, message). Also used by tests through the module API.
function Remotes.buyUpgrade(player: Player, name: any): (boolean, string)
	if not validId(name) or not Config.UPGRADES[name] then
		return false, "Unknown upgrade"
	end
	local s = Sessions.get(player)
	if not s then
		return false, "Your save is still loading..."
	end
	local level = s.data.upgrades[name] or 0
	local price = Rules.upgradePrice(name, level)
	if not price then
		return false, "Already maxed out!"
	end
	if s.data.coins < price then
		return false, ("Not enough coins! You need %s more"):format(Rules.formatNumber(price - s.data.coins))
	end
	Sessions.addCoins(player, -price, "upgrade:" .. name)
	Sessions.setUpgrade(player, name, level + 1)
	Sessions.saveSoon(player)
	return true, ("%s Lv %d!"):format(string.upper(Config.UPGRADES[name].name), level + 1)
end

function Remotes.buyCosmetic(player: Player, id: any): (boolean, string)
	local item = validId(id) and Cosmetics.get(id) or nil
	if not item then
		return false, "Unknown item"
	end
	local s = Sessions.get(player)
	if not s then
		return false, "Your save is still loading..."
	end
	if Sessions.owns(s, item) then
		-- already owned: treat "buy" as "equip" so a double tap never feels broken
		Sessions.equip(player, item.slot, item.id)
		return true, "Equipped " .. item.name
	end
	if item.vip then
		return false, "VIP only! Get the VIP pass in the ROBUX tab"
	end
	if s.data.coins < item.price then
		return false, ("Not enough coins! You need %s more"):format(Rules.formatNumber(item.price - s.data.coins))
	end
	Sessions.addCoins(player, -item.price, "cosmetic:" .. item.id)
	Sessions.grantCosmetic(player, item.id)
	Sessions.equip(player, item.slot, item.id) -- new toys go on right away
	Sessions.saveSoon(player)
	return true, "Unlocked " .. item.name .. "!"
end

-- equip(id) or equip(slot, id); id "" (or nil with a slot) = back to the default look.
function Remotes.equip(player: Player, a: any, b: any): (boolean, string, string)
	local slot: string? = nil
	local id: string = ""
	if Cosmetics.isSlot(a) and (b == nil or type(b) == "string") then
		slot = a
		id = b or ""
	elseif validId(a) then
		id = a
	else
		return false, "Unknown item", ""
	end
	local s = Sessions.get(player)
	if not s then
		return false, "Your save is still loading...", if id == "" then slot :: string else id
	end
	if id == "" then
		Sessions.equip(player, slot :: string, "")
		Sessions.saveSoon(player)
		return true, "Back to default", slot :: string -- the client keys default cards by slot name
	end
	if #id > MAX_ID_LENGTH then
		return false, "Unknown item", ""
	end
	local item = Cosmetics.get(id)
	if not item or (slot and item.slot ~= slot) then
		return false, "Unknown item", id
	end
	if not Sessions.owns(s, item) then
		return false, if item.vip then "VIP only!" else "You don't own that yet", id
	end
	Sessions.equip(player, item.slot, item.id)
	Sessions.saveSoon(player)
	return true, "Equipped " .. item.name, id
end

function Remotes.start()
	resultRemote = Net.event(Rules.Remote.Result)

	Net.event(Rules.Remote.BuyUpgrade).OnServerEvent:Connect(function(player: Player, name: any)
		if not allow(player) then
			return
		end
		local ok, message = Remotes.buyUpgrade(player, name)
		reply(player, ok, "upgrade", if validId(name) then name else "", message)
	end)

	Net.event(Rules.Remote.BuyCosmetic).OnServerEvent:Connect(function(player: Player, id: any)
		if not allow(player) then
			return
		end
		local ok, message = Remotes.buyCosmetic(player, id)
		reply(player, ok, "cosmetic", if validId(id) then id else "", message)
	end)

	Net.event(Rules.Remote.Equip).OnServerEvent:Connect(function(player: Player, a: any, b: any)
		if not allow(player) then
			return
		end
		local ok, message, id = Remotes.equip(player, a, b)
		reply(player, ok, "equip", id, message)
	end)

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Remotes
