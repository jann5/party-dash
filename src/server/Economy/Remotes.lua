--!strict
-- Coin-shop requests (buy upgrade, buy cosmetic, equip) and player settings. Everything is validated here; the
-- client only ever asks. Shop requests are answered on Economy_Result (ok, action, id, message).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local Feedback = require(script.Parent.Feedback)
local Grants = require(script.Parent.Grants)
local Limiter = require(script.Parent.Limiter)
local Mirror = require(script.Parent.Mirror)
local Sessions = require(script.Parent.Sessions)

local Remotes = {}

local MAX_ID_LENGTH = 40
local SETTINGS_GAP = 0.5 -- seconds between applied Economy_Settings calls (the latest one always wins)
local SETTING_KEYS = { "music", "sfx", "shake" }

-- Where an item that can't be bought with coins comes from.
local SOURCE_TEXT = {
	vip = "VIP only! Get the VIP pass in the Shop",
	robux = "Get it in the Shop's Featured deals!",
	wheel = "Win it on the Wheel of Fortune!",
	reward = "Find it in a reward chest!",
}

local function validId(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

local function needMore(price: number, coins: number): string
	return ("Not enough coins! You need %s more"):format(Rules.formatNumber(price - coins))
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
		return false, needMore(price, s.data.coins)
	end
	Grants.addCoins(player, -price, "upgrade:" .. name)
	Grants.setUpgrade(s, name, level + 1)
	Sessions.saveSoon(player)
	return true, ("%s Lv %d!"):format(string.upper(Config.UPGRADES[name].name), level + 1)
end

function Remotes.buyCosmetic(player: Player, id: any): (boolean, string)
	local item = if validId(id) then Cosmetics.get(id) else nil
	if not item then
		return false, "Unknown item"
	end
	local s = Sessions.get(player)
	if not s then
		return false, "Your save is still loading..."
	end
	if Mirror.owns(s, item) then
		-- already owned: treat "buy" as "equip" so a double tap never feels broken
		Grants.equip(s, item.slot, item.id)
		Sessions.saveSoon(player)
		return true, "Equipped " .. item.name
	end
	if item.source ~= "coins" then
		return false, SOURCE_TEXT[item.source] or "Not for sale"
	end
	if s.data.coins < item.price then
		return false, needMore(item.price, s.data.coins)
	end
	Grants.addCoins(player, -item.price, "cosmetic:" .. item.id)
	Grants.giveItem(s, item.id)
	Grants.equip(s, item.slot, item.id) -- new toys go on right away (also re-mirrors Owned_Cosmetics)
	Sessions.saveSoon(player)
	return true, "Unlocked " .. item.name .. "!"
end

-- equip(id) or equip(slot, id); id "" (or nil with a slot) = back to the default look.
-- Returns (ok, message, id echoed for the client's request key).
function Remotes.equip(player: Player, a: any, b: any): (boolean, string, string)
	local slot: string? = nil
	local id = ""
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
		Grants.equip(s, slot :: string, "")
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
	if not Mirror.owns(s, item) then
		return false, if item.source == "vip" then "VIP only!" else "You don't own that yet", id
	end
	Grants.equip(s, item.slot, item.id)
	Sessions.saveSoon(player)
	return true, "Equipped " .. item.name, id
end

-- Settings ------------------------------------------------------------------------------------------

-- Keeps only boolean music/sfx/shake fields; nil when nothing valid is left (garbage is ignored).
local function sanitizeSettings(payload: any): { [string]: boolean }?
	if type(payload) ~= "table" then
		return nil
	end
	local clean: { [string]: boolean } = {}
	local found = false
	for _, key in SETTING_KEYS do
		local value = payload[key]
		if type(value) == "boolean" then
			clean[key] = value
			found = true
		end
	end
	return if found then clean else nil
end

-- Applies settings now (API + remote). Returns false for garbage / while loading.
function Remotes.setSettings(player: Player, payload: any): boolean
	local clean = sanitizeSettings(payload)
	local s = Sessions.get(player)
	if not clean or not s then
		return false
	end
	local settings = s.data.settings :: any
	local changed = false
	for key, value in clean do
		if settings[key] ~= value then
			settings[key] = value
			changed = true
		end
	end
	Mirror.settings(s)
	if changed then
		Sessions.saveSoon(player)
	end
	return true
end

-- Rate limit without losing the final state: calls inside the gap are held and the latest one is applied
-- when the gap ends.
local lastSettingsAt: { [Player]: number } = {}
local heldSettings: { [Player]: { [string]: boolean } } = {}

local function onSettings(player: Player, payload: any)
	local clean = sanitizeSettings(payload)
	if not clean then
		return
	end
	local t = os.clock()
	local remaining = (lastSettingsAt[player] or -math.huge) + SETTINGS_GAP - t
	if remaining <= 0 then
		lastSettingsAt[player] = t
		Remotes.setSettings(player, clean)
		return
	end
	local queued = heldSettings[player] ~= nil
	heldSettings[player] = clean
	if queued then
		return
	end
	task.delay(remaining, function()
		local held = heldSettings[player]
		heldSettings[player] = nil
		if held and player.Parent == Players then
			lastSettingsAt[player] = os.clock()
			Remotes.setSettings(player, held)
		end
	end)
end

function Remotes.start()
	Net.event(Rules.Remote.BuyUpgrade).OnServerEvent:Connect(function(player: Player, name: any)
		if not Limiter.allow(player, "shop", 10, 4) then
			return
		end
		local ok, message = Remotes.buyUpgrade(player, name)
		Feedback.result(player, ok, "upgrade", if validId(name) then name else "", message)
	end)

	Net.event(Rules.Remote.BuyCosmetic).OnServerEvent:Connect(function(player: Player, id: any)
		if not Limiter.allow(player, "shop", 10, 4) then
			return
		end
		local ok, message = Remotes.buyCosmetic(player, id)
		Feedback.result(player, ok, "cosmetic", if validId(id) then id else "", message)
	end)

	Net.event(Rules.Remote.Equip).OnServerEvent:Connect(function(player: Player, a: any, b: any)
		if not Limiter.allow(player, "shop", 10, 4) then
			return
		end
		local ok, message, id = Remotes.equip(player, a, b)
		Feedback.result(player, ok, "equip", id, message)
	end)

	Net.event(Rules.Remote.Settings).OnServerEvent:Connect(onSettings)

	Players.PlayerRemoving:Connect(function(player)
		lastSettingsAt[player] = nil
		heldSettings[player] = nil
	end)
end

return Remotes
