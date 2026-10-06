--!strict
-- The local player's economy state, read from the Player attributes Economy mirrors, plus the
-- request -> result round trip for shop actions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local player = Players.LocalPlayer

local State = {}

State.player = player

local changedEvent = Instance.new("BindableEvent")
-- Fires (attributeName) whenever an economy attribute changes. Coalesced UI refreshes listen here.
State.changed = changedEvent.Event

local WATCHED: { [string]: boolean } = {
	Coins = true,
	Level = true,
	XP = true,
	[Rules.Attr.XPNext] = true,
	[Rules.Attr.Owned] = true,
	[Rules.Attr.Loaded] = true,
}
for name in Config.UPGRADES do
	WATCHED["Upg_" .. name] = true
end
for _, slot in Cosmetics.SLOTS do
	WATCHED[Cosmetics.SLOT_INFO[slot].attr] = true
end
for name in Config.GAMEPASSES do
	WATCHED[Rules.Attr.PassPrefix .. name] = true
end

local ownedCache: { [string]: boolean } = {}
local ownedRaw: string? = nil

player.AttributeChanged:Connect(function(name)
	if WATCHED[name] then
		changedEvent:Fire(name)
	end
end)

local function num(name: string, default: number): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else default
end

function State.loaded(): boolean
	return player:GetAttribute(Rules.Attr.Loaded) == true
end

function State.coins(): number
	return num("Coins", 0)
end

function State.level(): number
	return num("Level", 1)
end

function State.xp(): number
	return num("XP", 0)
end

function State.xpNext(): number
	return num(Rules.Attr.XPNext, Rules.xpForLevel(State.level()))
end

function State.upgradeLevel(name: string): number
	return Rules.upgradeLevelOf(player:GetAttribute("Upg_" .. name))
end

function State.owns(item: Cosmetics.Item): boolean
	local raw = player:GetAttribute(Rules.Attr.Owned)
	if raw ~= ownedRaw then
		ownedRaw = if type(raw) == "string" then raw else ""
		table.clear(ownedCache)
		for _, id in string.split(ownedRaw :: string, ",") do
			if id ~= "" then
				ownedCache[id] = true
			end
		end
	end
	return ownedCache[item.id] == true
end

function State.equipped(slot: string): string
	local v = player:GetAttribute(Cosmetics.SLOT_INFO[slot].attr)
	return if type(v) == "string" then v else ""
end

function State.hasPass(name: string): boolean
	return player:GetAttribute(Rules.Attr.PassPrefix .. name) == true
end

-- True when at least one upgrade is affordable (drives the SHOP button badge).
function State.canAffordUpgrade(): boolean
	local coins = State.coins()
	for name in Config.UPGRADES do
		local price = Rules.upgradePrice(name, State.upgradeLevel(name))
		if price and coins >= price then
			return true
		end
	end
	return false
end

-- Requests ------------------------------------------------------------------------------------------

type Callback = (ok: boolean, message: string) -> ()
local pending: { [string]: { Callback } } = {}
local fallback: Callback? = nil
local remotes: { [string]: RemoteEvent } = {}

local function remote(name: string): RemoteEvent
	local r = remotes[name]
	if not r then
		r = Net.event(name)
		remotes[name] = r
	end
	return r
end

-- Called for results nobody is waiting for (e.g. the window toast).
function State.onUnhandledResult(fn: Callback)
	fallback = fn
end

local function keyOf(action: string, id: string): string
	return action .. ":" .. id
end

-- Sends a request; `callback(ok, message)` runs when the server answers (or after a timeout).
function State.request(action: "upgrade" | "cosmetic" | "equip", id: string, callback: Callback, ...: any)
	local key = keyOf(action, id)
	local list = pending[key]
	if not list then
		list = {}
		pending[key] = list
	end
	table.insert(list, callback)
	local args = table.pack(...)
	task.spawn(function()
		local name = if action == "upgrade"
			then Rules.Remote.BuyUpgrade
			elseif action == "cosmetic" then Rules.Remote.BuyCosmetic
			else Rules.Remote.Equip
		if args.n > 0 then
			remote(name):FireServer(table.unpack(args, 1, args.n))
		else
			remote(name):FireServer(id)
		end
	end)
	-- never leave a button hanging if the server dropped the request (rate limit)
	task.delay(4, function()
		local l = pending[key]
		local i = l and table.find(l, callback)
		if l and i then
			table.remove(l, i)
			callback(false, "No answer from the server, try again")
		end
	end)
end

function State.start()
	task.spawn(function()
		remote(Rules.Remote.Result).OnClientEvent:Connect(function(ok: any, action: any, id: any, message: any)
			local text = if type(message) == "string" then message else ""
			local key = keyOf(tostring(action), tostring(id))
			local list = pending[key]
			local cb = list and table.remove(list, 1)
			if cb then
				cb(ok == true, text)
			elseif fallback then
				fallback(ok == true, text)
			end
		end)
	end)
end

return State
