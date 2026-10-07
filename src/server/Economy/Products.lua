--!strict
-- Robux: developer products (ProcessReceipt), gamepasses (2X Coins, VIP) and the Studio test-purchase path.
-- Catalog + prices: Shared.Products. Every key there has exactly one handler here (checked at start).
--
-- ProcessReceipt is assigned ONLY here. It is idempotent by PurchaseId: the id is stored in the profile and saved
-- before PurchaseGranted is returned; a handler that errors is rolled back and Roblox retries later. Handlers mutate
-- synchronously and never yield; anything that yields (a Core revive) runs after the receipt save.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local SharedProducts = require(ReplicatedStorage.Shared.Products)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Feedback = require(script.Parent.Feedback)
local Grants = require(script.Parent.Grants)
local Limiter = require(script.Parent.Limiter)
local Mirror = require(script.Parent.Mirror)
local Profile = require(script.Parent.Profile)
local Revive = require(script.Parent.Revive)
local Sessions = require(script.Parent.Sessions)
local Types = require(script.Parent.Types)

type Session = Types.Session
-- A product handler returns the toast text and an optional action to run after the receipt is saved.
type Handler = (player: Player, s: Session) -> (string, (() -> ())?)

local Products = {}

local Decision = Enum.ProductPurchaseDecision
local HANDLERS: { [string]: Handler } = {}

-- Developer products ---------------------------------------------------------------------------------

local function coinPack(coins: number): Handler
	return function(player)
		Grants.applyBundle(player, { coins = coins }, "robux")
		return ("+%s coins! Thanks for the support!"):format(Rules.formatNumber(coins))
	end
end

for key, coins in Rules.COIN_PACKS do
	HANDLERS[key] = coinPack(coins)
end

for name, def in Config.UPGRADES do
	HANDLERS["Upgrade" .. name] = function(player, s)
		local level = s.data.upgrades[name] or 0
		if level >= Config.UPGRADE_MAX_LEVEL then
			-- already maxed (bought in two windows at once): never lose a purchase, refund in coins
			local refund = def.prices[#def.prices]
			Grants.applyBundle(player, { coins = refund }, "robux:refund")
			return ("%s is maxed: +%s coins instead"):format(def.name, Rules.formatNumber(refund))
		end
		Grants.setUpgrade(s, name, level + 1)
		return ("%s upgraded to Lv %d!"):format(def.name, level + 1)
	end
end

local function spinPack(count: number): Handler
	return function(player)
		Grants.applyBundle(player, { spins = count }, "robux")
		return ("+%d spin%s! Go spin the wheel!"):format(count, if count == 1 then "" else "s")
	end
end

HANDLERS.WheelSpin1 = spinPack(1)
HANDLERS.WheelSpin5 = spinPack(5)

-- The token is granted with the receipt (so it is never lost); after the save it is used right away if the
-- player can still come back into the round, otherwise it stays for next time.
HANDLERS.Revive = function(player)
	Grants.applyBundle(player, { revives = 1 }, "robux")
	return "Revive bought!", function()
		Revive.afterPurchase(player)
	end
end

HANDLERS.StarterPack = function(player, s)
	local starter = Rules.STARTER
	if s.data.boughtStarter then
		Grants.applyBundle(player, { coins = starter.refundCoins }, "robux:refund")
		return ("Starter Pack already owned: +%s coins"):format(Rules.formatNumber(starter.refundCoins))
	end
	s.data.boughtStarter = true
	Grants.applyBundle(player, {
		coins = starter.coins,
		items = { starter.item },
		boostSeconds = starter.boostSeconds,
		equip = true,
	}, "robux:starter")
	Mirror.starter(s)
	return "Starter Pack unlocked! 2x coins for 30 min!"
end

local function galaxy(player: Player, _s: Session): string
	local granted = Grants.applyBundle(player, {
		items = { Rules.GALAXY.item },
		dupCoins = Rules.GALAXY.dupCoins,
		equip = true,
	}, "robux:galaxy")
	if granted and #granted.items == 0 then
		return ("Galaxy Comet already owned: +%s coins"):format(Rules.formatNumber(Rules.GALAXY.dupCoins))
	end
	return "Galaxy Comet trail unlocked!"
end

HANDLERS.GalaxyTrail19 = galaxy
HANDLERS.GalaxyTrail199 = galaxy

-- Receipts ------------------------------------------------------------------------------------------

-- MarketplaceService.ProcessReceipt. `keyHint` (server-side callers only) names the product when its id is not
-- configured: the Studio dev path, or a test VM that remapped Config.PRODUCTS locally.
function Products.processReceipt(receiptInfo: any, keyHint: string?): Enum.ProductPurchaseDecision
	if type(receiptInfo) ~= "table" then
		return Decision.NotProcessedYet
	end
	local userId = tonumber(receiptInfo.PlayerId)
	local purchaseId = receiptInfo.PurchaseId
	if not userId or type(purchaseId) ~= "string" or purchaseId == "" then
		return Decision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(userId)
	local s = player and Sessions.get(player)
	if not player or not s or not s.persistent or s.lost then
		return Decision.NotProcessedYet -- Roblox retries when the player is back with a loaded profile
	end

	if Profile.hasReceipt(s.data, purchaseId) then
		if s.pendingReceipts[purchaseId] then
			-- granted earlier but that save failed: only confirm once it is on disk
			return if Sessions.save(player) then Decision.PurchaseGranted else Decision.NotProcessedYet
		end
		return Decision.PurchaseGranted
	end

	local key = SharedProducts.keyForProductId(tonumber(receiptInfo.ProductId) or 0)
	if not key and type(keyHint) == "string" and HANDLERS[keyHint] then
		key = keyHint
	end
	local handler = key and HANDLERS[key]
	if not key or not handler then
		warn(("[Economy] Unknown developer product %s"):format(tostring(receiptInfo.ProductId)))
		return Decision.NotProcessedYet
	end

	local backup = Profile.clone(s.data)
	local ok, text, after = pcall(handler, player, s)
	if not ok then
		s.data = backup
		Mirror.all(s)
		warn(("[Economy] %s grant failed, rolled back: %s"):format(key, tostring(text)))
		return Decision.NotProcessedYet
	end
	Profile.addReceipt(s.data, purchaseId)
	s.data.stats.robuxSpent += math.max(0, math.floor(tonumber(receiptInfo.CurrencySpent) or 0))
	s.pendingReceipts[purchaseId] = true
	Feedback.toast(player, text, Theme.Colors.Green)
	Feedback.sound(player, "Purchase")
	Feedback.reward(player, "purchase", { key = key, message = text })
	if not Sessions.save(player) then
		return Decision.NotProcessedYet
	end
	if after then
		task.defer(after)
	end
	return Decision.PurchaseGranted
end

-- Gamepasses ----------------------------------------------------------------------------------------

-- Perks are read live elsewhere (Rewards: 2x / +20% coins, Visuals: gold tag); owning a pass also unlocks
-- its cosmetics and, for VIP, today's bonus spin.
local function setPass(player: Player, name: string, owned: boolean, fresh: boolean)
	local s = Sessions.raw(player)
	if not s then
		return
	end
	s.passes[name] = owned
	player:SetAttribute(Rules.Attr.PassPrefix .. name, owned)
	if not s.loaded then
		return -- applied with the profile (Mirror.all + refreshDay)
	end
	Mirror.cosmetics(s)
	if owned and name == "VIP" then
		if fresh and (s.data.equipped.Trail or "") == "" then
			Grants.equip(s, "Trail", "TrailVIP") -- show off the new gold trail right away
		end
		Sessions.refreshDay(s)
	end
end

local function passGranted(player: Player, name: string)
	setPass(player, name, true, true)
	local info = SharedProducts.INFO[name]
	Feedback.toast(player, ("%s unlocked! Enjoy!"):format(info and info.title or name), Theme.Colors.Gold)
	Feedback.sound(player, "Purchase")
	Feedback.reward(player, "purchase", { key = name })
end

-- Checks ownership once per join (cached on the session; purchases arrive through the prompt event).
function Products.refreshPasses(player: Player)
	for name, id in Config.GAMEPASSES do
		local s = Sessions.raw(player)
		if id ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok and player.Parent == Players then
				setPass(player, name, result == true, false)
			end
		elseif s and s.passes[name] == nil then
			setPass(player, name, false, false)
		end
	end
end

local function passKey(passId: number): string?
	if passId == 0 then
		return nil
	end
	for name, id in Config.GAMEPASSES do
		if id == passId then
			return name
		end
	end
	return nil
end

-- Studio test purchases ------------------------------------------------------------------------------

-- Same grant path as a real purchase, with a unique fake PurchaseId. Only exists in Studio.
function Products.devBuy(player: Player, key: any): boolean
	if not RunService:IsStudio() or type(key) ~= "string" then
		return false
	end
	local info = SharedProducts.INFO[key]
	if not info then
		return false
	end
	if info.kind == "gamepass" then
		passGranted(player, key)
		return true
	end
	local decision = Products.processReceipt({
		PlayerId = player.UserId,
		ProductId = SharedProducts.id(key),
		PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
		CurrencySpent = 0,
	}, key)
	return decision == Decision.PurchaseGranted
end

function Products.start()
	for key, info in SharedProducts.INFO do
		if info.kind == "product" and not HANDLERS[key] then
			warn("[Economy] no grant handler for product " .. key)
		end
	end

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return Products.processReceipt(receiptInfo)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local name = purchased and passKey(passId)
			if name and player.Parent == Players then
				passGranted(player, name)
			end
		end
	)

	if RunService:IsStudio() then
		Net.event(Rules.Remote.DevBuy).OnServerEvent:Connect(function(player: Player, key: any)
			if Limiter.allow(player, "devbuy", 5, 2) and not Products.devBuy(player, key) then
				Feedback.toast(player, "Test purchase failed (save still loading?)", Theme.Colors.Red)
			end
		end)
	end
end

return Products
