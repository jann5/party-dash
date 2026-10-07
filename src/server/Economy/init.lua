--!strict
-- Party Dash Economy v2: coins, XP/levels, upgrades, cosmetics, Robux products + passes, wheel of fortune, daily /
-- group / playtime rewards, revive tokens, settings, persistence. Booted by the child Script "Boot".
--
-- Server API (other systems and tests):
--   local Economy = require(ServerScriptService.Server.Economy)
--   Economy.getProfile(player)                      -> profile data table (nil until loaded)
--   Economy.addCoins(player, n, reason?)            -> new balance (nil until loaded)
--   Economy.addXP(player, n)                        -> levels gained (level-ups pay coins/spins)
--   Economy.applyBundle(player, bundle, reason?)    -> granted bundle; bundle = { coins?, xp?, spins?, revives?,
--                                                      boostSeconds?, items? } (owned items turn into coins)
--   Economy.processReceipt(receiptInfo, keyHint?)   -> Enum.ProductPurchaseDecision (idempotent by PurchaseId)
--   Economy.devBuy(player, productKey)              -> boolean (Studio only: same path as a real purchase)
--   Economy.claim(player, "daily"|"group"|"gift")   -> { ok, reward, message }   (same as Economy_Claim)
--   Economy.spin(player)                            -> { ok, index, prize, ... } (same as Economy_Spin)
--   Economy.useRevive(player)                       -> (ok, message)            (same as Economy_UseRevive)
--   Economy.setSettings(player, { music?, sfx?, shake? }) -> boolean
--   Economy.setGiftAt(player, serverTime) / Economy.readyGift(player)   (test hooks for playtime gifts)
--   Economy.roundStarted(info) / roundFinished(result) / soloFinished(player, info)   (the Signals handlers)
--   Economy.buyUpgrade(player, name) / buyCosmetic(player, id) / equip(player, id)  -> (ok, message)
--   Economy.save(player) / reload(player) / peekStored(userId) / storeMode()
--
-- Calls made from another Luau VM (e.g. the Studio command bar, which gets its own copy of every ModuleScript)
-- are forwarded to the live instance through the BindableFunction "EconomyApi". Such a copy also forwards its
-- own VM's Signals (RoundStarted / RoundFinished / SoloFinished), so tests can fire them from anywhere.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local SharedProducts = require(ReplicatedStorage.Shared.Products)

local Server = script.Parent
local Signals = require(Server.Signals)

local Claims = require(script.Claims)
local Grants = require(script.Grants)
local Limiter = require(script.Limiter)
local Products = require(script.Products)
local Remotes = require(script.Remotes)
local Revive = require(script.Revive)
local Rewards = require(script.Rewards)
local Sessions = require(script.Sessions)
local Store = require(script.Store)
local Visuals = require(script.Visuals)
local Wheel = require(script.Wheel)

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
	copy.kos = rekey(result.kos)
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
	return Grants.addCoins(player, amount, reason)
end

function Economy.addXP(player: Player, amount: number): number
	if not started then
		return forward("addXP", player, amount) or 0
	end
	return (Grants.addXP(player, amount))
end

function Economy.applyBundle(player: Player, bundle: any, reason: string?): any
	if not started then
		return forward("applyBundle", player, bundle, reason)
	end
	return Grants.applyBundle(player, bundle, reason)
end

function Economy.processReceipt(receiptInfo: any, keyHint: string?): Enum.ProductPurchaseDecision
	if not started then
		local hint = keyHint
		if not hint and type(receiptInfo) == "table" then
			hint = SharedProducts.keyForProductId(tonumber(receiptInfo.ProductId) or 0)
		end
		return forward("processReceipt", receiptInfo, hint) or Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Products.processReceipt(receiptInfo, keyHint)
end

function Economy.devBuy(player: Player, key: string): boolean
	if not started then
		return forward("devBuy", player, key) == true
	end
	return Products.devBuy(player, key)
end

function Economy.claim(player: Player, kind: string): any
	if not started then
		return forward("claim", player, kind)
	end
	return Claims.claim(player, kind)
end

function Economy.spin(player: Player): any
	if not started then
		return forward("spin", player)
	end
	return Wheel.spin(player)
end

function Economy.useRevive(player: Player): (boolean, string)
	if not started then
		return forward("useRevive", player)
	end
	return Revive.use(player)
end

function Economy.setSettings(player: Player, settings: any): boolean
	if not started then
		return forward("setSettings", player, settings) == true
	end
	return Remotes.setSettings(player, settings)
end

function Economy.setGiftAt(player: Player, serverTime: number): boolean
	if not started then
		return forward("setGiftAt", player, serverTime) == true
	end
	return Claims.setGiftAt(player, serverTime)
end

-- Makes the next playtime gift claimable right now (tests).
function Economy.readyGift(player: Player): boolean
	return Economy.setGiftAt(player, workspace:GetServerTimeNow() - 1)
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

function Economy.roundStarted(info: any)
	if not started then
		forward("roundStarted", info)
		return
	end
	Rewards.roundStarted(info)
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
	player:SetAttribute(Rules.Attr.RoundStreak, 0)
	task.spawn(Sessions.load, player) -- creates the session synchronously, then yields on the store
	task.spawn(Products.refreshPasses, player)
	task.spawn(Wheel.checkPolicy, player)
end

local function saveAll(release: boolean)
	local pending = 0
	for _, player in Sessions.players() do
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

-- Autosave (also refreshes the session lock), spread out so writes don't burst.
local function autosaveLoop()
	while true do
		task.wait(Sessions.AUTOSAVE)
		for _, player in Sessions.players() do
			if Sessions.get(player) then
				task.spawn(Sessions.save, player)
				task.wait(0.2)
			end
		end
	end
end

-- UTC midnight: daily chest, free spin, group chest and VIP spin become available again for long sessions.
local function dayLoop()
	local day = Rules.utcDay()
	while true do
		task.wait(10)
		local today = Rules.utcDay()
		if today ~= day then
			day = today
			for _, player in Sessions.players() do
				local s = Sessions.get(player)
				if s then
					local ok, err = pcall(Sessions.refreshDay, s)
					if not ok then
						warn("[Economy] day rollover failed:", err)
					end
				end
			end
		end
	end
end

local function startBridge()
	local methods: { [string]: (...any) -> ...any } = {
		getProfile = Economy.getProfile,
		isLoaded = Economy.isLoaded,
		addCoins = Economy.addCoins,
		addXP = Economy.addXP,
		applyBundle = Economy.applyBundle,
		processReceipt = Economy.processReceipt,
		devBuy = Economy.devBuy,
		claim = Economy.claim,
		spin = Economy.spin,
		useRevive = Economy.useRevive,
		setSettings = Economy.setSettings,
		setGiftAt = Economy.setGiftAt,
		save = Economy.save,
		reload = Economy.reload,
		peekStored = Economy.peekStored,
		roundStarted = Economy.roundStarted,
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

function Economy.start()
	if started or isRemoteCopy then
		return
	end
	started = true

	task.spawn(Store.init)
	Limiter.start()
	Remotes.start()
	Claims.start()
	Wheel.start()
	Revive.start()
	Products.start()
	Visuals.start()

	Signals.RoundStarted:Connect(Rewards.roundStarted)
	Signals.RoundFinished:Connect(Rewards.roundFinished)
	Signals.SoloFinished:Connect(Rewards.soloFinished)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(Sessions.unload)
	game:BindToClose(function()
		saveAll(true)
	end)

	task.spawn(autosaveLoop)
	task.spawn(dayLoop)
	startBridge()
end

-- Another VM's copy: forward its Signals (the command bar has its own Signals table too).
if isRemoteCopy then
	Signals.RoundStarted:Connect(Economy.roundStarted)
	Signals.RoundFinished:Connect(Economy.roundFinished)
	Signals.SoloFinished:Connect(Economy.soloFinished)
end

return Economy
