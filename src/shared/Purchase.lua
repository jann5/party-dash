-- Party Dash: client-side purchase helper. FROZEN CONTRACT v2 (lead-owned). Every Robux button calls this.
--
--   local Purchase = require(ReplicatedStorage.Shared.Purchase)
--   local how = Purchase.prompt("WheelSpin1")  --> "prompted" | "dev" | "unavailable" | "owned"
--
-- * id configured  -> MarketplaceService prompt (developer product or gamepass). The grant happens on the server
--                     (Economy ProcessReceipt / gamepass check); listen to Economy_Result / Economy_Reward for the
--                     outcome.
-- * id == 0 in Studio -> fires Economy_DevBuy(key): Economy grants exactly as if a receipt arrived (testing path).
-- * id == 0 live    -> toast "Coming soon!" (the owner has not created the product yet).
-- * a gamepass the player already owns -> "owned" (no prompt).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Products = require(ReplicatedStorage.Shared.Products)

local Purchase = {}

local lastPrompt = 0

local function toast(text: string)
	local ok, UIKit = pcall(require, ReplicatedStorage.Shared.UIKit)
	if ok and UIKit and UIKit.toast then
		UIKit.toast(text)
	end
end

function Purchase.prompt(key: string): string
	assert(RunService:IsClient(), "Purchase.prompt is client-only")
	local info = Products.INFO[key]
	if not info then
		warn("[Purchase] unknown product key " .. tostring(key))
		return "unavailable"
	end
	-- debounce double taps
	local now = os.clock()
	if now - lastPrompt < 0.6 then
		return "prompted"
	end
	lastPrompt = now
	local player = Players.LocalPlayer
	if info.kind == "gamepass" and player:GetAttribute("Pass_" .. key) == true then
		toast("You already own " .. info.title .. "!")
		return "owned"
	end
	local id = Products.id(key)
	if id == 0 then
		if RunService:IsStudio() then
			local folder = ReplicatedStorage:FindFirstChild("Remotes")
			local remote = folder and folder:FindFirstChild("Economy_DevBuy")
			if remote and remote:IsA("RemoteEvent") then
				remote:FireServer(key)
				toast("[Studio] Test purchase: " .. info.title)
				return "dev"
			end
		end
		toast("Coming soon!")
		return "unavailable"
	end
	if info.kind == "gamepass" then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
	return "prompted"
end

-- Price text for a product key: live price is not fetched here (keep UI instant); Products.INFO price is shown.
function Purchase.price(key: string): number
	local info = Products.INFO[key]
	return info and info.price or 0
end

return Purchase
