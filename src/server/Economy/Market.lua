--!strict
-- Robux: developer products (ProcessReceipt) and gamepasses (DoubleCoins, VIP).
-- Ids come from Config.PRODUCTS / Config.GAMEPASSES; 0 = not configured (never prompted, never matched).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cosmetics = require(ReplicatedStorage.Shared.Economy.Cosmetics)
local Rules = require(ReplicatedStorage.Shared.Economy.Rules)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Announce = require(script.Parent.Parent.Announce)
local Profile = require(script.Parent.Profile)
local Sessions = require(script.Parent.Sessions)

local Market = {}

local Decision = Enum.ProductPurchaseDecision

-- Applies one product to a loaded session. Returns a toast text, or nil if the product is unknown.
local function grant(player: Player, key: string): string?
	local coins = Rules.COIN_PACKS[key]
	if coins then
		Sessions.addCoins(player, coins, "robux:" .. key)
		return ("+%s coins! Thanks for the support!"):format(Rules.formatNumber(coins))
	end
	local upgrade = Rules.upgradeFromProduct(key)
	if upgrade then
		local s = Sessions.get(player)
		if not s then
			return nil
		end
		local level = s.data.upgrades[upgrade] or 0
		local def = Config.UPGRADES[upgrade]
		if level >= Config.UPGRADE_MAX_LEVEL then
			-- already maxed (bought in two windows at once): never lose a purchase, refund in coins
			local refund = def.prices[#def.prices]
			Sessions.addCoins(player, refund, "robux:refund")
			return ("%s is maxed: +%s coins instead"):format(def.name, Rules.formatNumber(refund))
		end
		Sessions.setUpgrade(player, upgrade, level + 1)
		return ("%s upgraded to Lv %d!"):format(def.name, level + 1)
	end
	return nil
end

-- MarketplaceService.ProcessReceipt. Idempotent by PurchaseId: the id is recorded in the profile and
-- saved before PurchaseGranted is returned. `keyHint` lets a cross-VM test caller pass the product key
-- it resolved with its own (temporarily remapped) Config.
function Market.processReceipt(receiptInfo: { [string]: any }, keyHint: string?): Enum.ProductPurchaseDecision
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

	local key = Rules.productKey(receiptInfo.ProductId)
	if not key and type(keyHint) == "string" and (Rules.COIN_PACKS[keyHint] or Rules.upgradeFromProduct(keyHint)) then
		key = keyHint
	end
	if not key then
		warn(("[Economy] Unknown developer product %s"):format(tostring(receiptInfo.ProductId)))
		return Decision.NotProcessedYet
	end

	local text = grant(player, key)
	if not text then
		return Decision.NotProcessedYet
	end
	Profile.addReceipt(s.data, purchaseId)
	s.pendingReceipts[purchaseId] = true
	Announce.toast(player, text, Theme.Colors.Green)
	if Sessions.save(player) then
		return Decision.PurchaseGranted
	end
	return Decision.NotProcessedYet
end

-- Gamepasses ----------------------------------------------------------------------------------------

local function passName(passId: number): string?
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

local function onPassGranted(player: Player, name: string)
	Sessions.setPass(player, name, true)
	local s = Sessions.get(player)
	if name == "VIP" and s and s.data.equipped.Trail == "" then
		-- show off the new gold trail right away
		for _, item in Cosmetics.list("Trail") do
			if item.vip then
				Sessions.equip(player, "Trail", item.id)
				break
			end
		end
	end
end

-- Checks ownership once per join (cached on the session).
function Market.refreshPasses(player: Player)
	for name, id in Config.GAMEPASSES do
		local owned = false
		if id ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			owned = ok and result == true
		end
		if player.Parent then
			Sessions.setPass(player, name, owned)
		end
	end
end

function Market.start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			local name = purchased and passName(passId)
			if name and player.Parent then
				onPassGranted(player, name)
				local info = Rules.PASS_INFO[name]
				Announce.toast(player, ("%s unlocked! Enjoy!"):format(info and info.title or name), Theme.Colors.Yellow)
			end
		end
	)
end

return Market
