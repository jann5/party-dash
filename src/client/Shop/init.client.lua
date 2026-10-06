-- Party Dash economy client (P9): the EconomyHUD coin counter + level bar, the SHOP button in
-- PartyHUD.MenuRail, and the shop window (UPGRADES / COSMETICS / ROBUX). Boots itself.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local shared = ReplicatedStorage:WaitForChild("Shared")
for _, name in { "Config", "GameState", "Net", "Theme", "Economy" } do
	shared:WaitForChild(name)
end

local CosmeticsTab = require(script.CosmeticsTab)
local Hud = require(script.Hud)
local MenuButton = require(script.MenuButton)
local RobuxTab = require(script.RobuxTab)
local State = require(script.State)
local UpgradesTab = require(script.UpgradesTab)
local Window = require(script.Window)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

State.start()

local shop = Window.new(playerGui)
local ctx = {
	toast = shop.toast,
	switch = function(tab: string)
		shop.switch(tab)
	end,
	onSwitched = shop.onSwitched,
}

local function run(name: string, fn: () -> ())
	-- one broken tab must never take the whole shop down
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Shop] %s failed to build: %s"):format(name, tostring(err)))
	end
end

run("Upgrades", function()
	UpgradesTab.build(shop.pages.Upgrades, ctx)
end)
run("Cosmetics", function()
	CosmeticsTab.build(shop.pages.Cosmetics, ctx)
end)
run("Robux", function()
	RobuxTab.build(shop.pages.Robux, ctx)
end)

-- Results nobody waits for (e.g. a request that timed out on the client) still get feedback.
State.onUnhandledResult(function(ok: boolean, message: string)
	if shop.isOpen() and message ~= "" then
		shop.toast(message, ok)
	end
end)

run("Hud", function()
	Hud.start(playerGui, function(tab: string?)
		shop.open(tab)
	end)
end)
run("MenuButton", function()
	MenuButton.start(playerGui, function()
		shop.toggle()
	end)
end)
