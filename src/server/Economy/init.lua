--!strict
-- Party Dash Economy (P9): coins, XP/levels, upgrades, cosmetics, Robux, persistence.
-- Booted by the child Script "Boot" (Economy.start()). Server-side API for other systems and tests:
--
--   local Economy = require(ServerScriptService.Server.Economy)
--   Economy.getProfile(player)              -> profile data table (nil until loaded)
--   Economy.addCoins(player, n, reason?)    -> new balance (nil until loaded)
--   Economy.addXP(player, n)                -> levels gained
--   Economy.processReceipt(receiptInfo)     -> Enum.ProductPurchaseDecision (also MarketplaceService.ProcessReceipt)
--   Economy.save(player)                    -> boolean (session-locked UpdateAsync, or in-memory fallback)
--   Economy.reload(player)                  -> profile data re-read from the store (save + release + load)
--   Economy.peekStored(userId)              -> raw stored record (read-only)
--   Economy.roundFinished(result) / Economy.soloFinished(player, info)  (same as the Signals handlers)
--   Economy.buyUpgrade(player, name) / buyCosmetic(player, id) / equip(player, id)  -> (ok, message)
--   Economy.storeMode()                     -> "datastore" | "memory"
--
-- Calls made from another Luau VM (e.g. the Studio command bar, which gets its own copy of every
-- ModuleScript) are forwarded to the live instance through the BindableFunction "EconomyApi".
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Economy.Rules)

local Server = script.Parent
local Signals = require(Server.Signals)

local Market = require(script.Market)
local Remotes = require(script.Remotes)
local Rewards = require(script.Rewards)
local Sessions = require(script.Sessions)
local Store = require(script.Store)
local Visuals = require(script.Visuals)

local Economy = {}

local API_NAME = "EconomyApi"
local started = false
-- A live instance already exists when this copy is required: this is another VM's copy.
local isRemoteCopy = script:FindFirstChild(API_NAME) ~= nil

local function forward(method: string, ...: any): ...any
	local bridge = script:FindFirstChild(API_NAME) or script:WaitForChild(API_NAME, 10)
	if not (bridge and bridge:IsA("BindableFunction")) then
		warn("[Economy] not running yet; call ignored:", method)
		return nil
	end
	return bridge:Invoke(method, ...)
end

-- Result tables are keyed by Player; Bindables mangle Instance keys, so re-key by userId string.
local function rekey(map: any): { [string]: any }?
	if type(map) ~= "table" then
		return nil
	end
	local out = {}
	for k, v in map do
		if typeof(k) == "Instance" and k:IsA("Player") then
			out[tostring(k.UserId)] = v
		elseif type(k) == "string" or type(k) == "number" then
			out[tostring(k)] = v
		end
	end
	return out
end

local function portableResult(result: any): any
	if type(result) ~= "table" then
		return result
	end
	local copy = table.clone(result)
	copy.survived = rekey(result.survived)
	copy.placements = rekey(result.placements)
	copy.scores = rekey(result.scores)
	return copy
end

-- Public API ---------------------------------------------------------------------------------------

function Economy.getProfile(player: Player): any
	if not started then
		return forward("getProfile", player)
	end
	local s = Sessions.get(player)
	return s and s.data
end

function Economy.isLoaded(player: Player): boolean
	if not started then
		return forward("isLoaded", player) == true
	end
	return Sessions.get(player) ~= nil
end

function Economy.addCoins(player: Player, amount: number, reason: string?): number?
	if not started then
		return forward("addCoins", player, amount, reason)
	end
	return Sessions.addCoins(player, amount, reason)
end

function Economy.addXP(player: Player, amount: number): number
	if not started then
		return forward("addXP", player, amount) or 0
	end
	return Sessions.addXP(player, amount)
end

function Economy.processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	if not started then
		local hint = if type(receiptInfo) == "table" then Rules.productKey(receiptInfo.ProductId) else nil
		return forward("processReceipt", receiptInfo, hint) or Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Market.processReceipt(receiptInfo)
end

function Economy.save(player: Player): boolean
	if not started then
		return forward("save", player) == true
	end
	return Sessions.save(player)
end

function Economy.reload(player: Player): any
	if not started then
		return forward("reload", player)
	end
	return Sessions.reload(player)
end

function Economy.peekStored(userId: number): any
	if not started then
		return forward("peekStored", userId)
	end
	return Sessions.peekStored(userId)
end

function Economy.roundFinished(result: any): { [Player]: number }
	if not started then
		return forward("roundFinished", portableResult(result)) or {}
	end
	return Rewards.roundFinished(result)
end

function Economy.soloFinished(player: Player, info: any): number
	if not started then
		return forward("soloFinished", player, info) or 0
	end
	return Rewards.soloFinished(player, info)
end

function Economy.buyUpgrade(player: Player, name: string): (boolean, string)
	if not started then
		return forward("buyUpgrade", player, name)
	end
	return Remotes.buyUpgrade(player, name)
end

function Economy.buyCosmetic(player: Player, id: string): (boolean, string)
	if not started then
		return forward("buyCosmetic", player, id)
	end
	return Remotes.buyCosmetic(player, id)
end

function Economy.equip(player: Player, a: string, b: string?): (boolean, string)
	if not started then
		return forward("equip", player, a, b)
	end
	local ok, message = Remotes.equip(player, a, b)
	return ok, message
end

function Economy.storeMode(): string
	if not started then
		return forward("storeMode") or "pending"
	end
	return Store.mode()
end

-- Boot ---------------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	task.spawn(Sessions.load, player) -- creates the session synchronously, then yields on the store
	task.spawn(Market.refreshPasses, player)
end

local function saveAll(release: boolean)
	local pending = 0
	for player in Sessions.all() do
		pending += 1
		task.spawn(function()
			if release then
				Sessions.unload(player)
			else
				Sessions.save(player)
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function Economy.start()
	if started or isRemoteCopy then
		return
	end
	started = true

	task.spawn(Store.init)
	Remotes.start()
	Market.start()
	Visuals.start()

	MarketplaceService.ProcessReceipt = Economy.processReceipt

	Sessions.Loaded:Connect(function(player: Player)
		Sessions.checkDaily(player, 3) -- once the HUD is listening, so the coins fly in with the toast
	end)

	Signals.RoundFinished:Connect(Rewards.roundFinished)
	Signals.SoloFinished:Connect(Rewards.soloFinished)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		Sessions.unload(player)
	end)
	game:BindToClose(function()
		saveAll(true)
	end)

	-- Autosave (also refreshes the session lock) + daily rollover for long sessions.
	task.spawn(function()
		while true do
			task.wait(Sessions.AUTOSAVE)
			for player in Sessions.all() do
				if Sessions.get(player) then
					Sessions.checkDaily(player)
					task.spawn(Sessions.save, player)
					task.wait(0.2) -- spread writes out
				end
			end
		end
	end)

	-- Bridge for other VMs (see header).
	local methods: { [string]: (...any) -> ...any } = {
		getProfile = Economy.getProfile,
		isLoaded = Economy.isLoaded,
		addCoins = Economy.addCoins,
		addXP = Economy.addXP,
		processReceipt = Market.processReceipt,
		save = Economy.save,
		reload = Economy.reload,
		peekStored = Economy.peekStored,
		roundFinished = Economy.roundFinished,
		soloFinished = Economy.soloFinished,
		buyUpgrade = Economy.buyUpgrade,
		buyCosmetic = Economy.buyCosmetic,
		equip = Economy.equip,
		storeMode = Economy.storeMode,
	}
	local bridge = Instance.new("BindableFunction")
	bridge.Name = API_NAME
	bridge.OnInvoke = function(method: any, ...: any)
		local fn = type(method) == "string" and methods[method]
		if fn then
			return fn(...)
		end
		return nil
	end
	bridge.Parent = script
end

-- Another VM's copy: forward its Signals (the command bar has its own Signals table too).
if isRemoteCopy then
	Signals.RoundFinished:Connect(function(result)
		Economy.roundFinished(result)
	end)
	Signals.SoloFinished:Connect(function(player, info)
		Economy.soloFinished(player, info)
	end)
end

return Economy
