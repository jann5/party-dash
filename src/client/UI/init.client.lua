-- Party Dash UI boot (P3). Builds three ScreenGuis and starts every HUD module:
--   PartyHUD     (safe-area aware)  status pill + timer, alive counter, MenuRail, lobby logo, TOP 3, hints
--   PartyOverlay (full screen)      roulettes, intro card, results, confetti
--   PartyNotify  (safe-area aware)  Core_Announce big text / kill feed / toasts (always on top)
-- Every module only reads GameState / MinigameInfo / ModifierInfo, so the UI works without Core code.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- make sure the shared modules the HUD requires have replicated before anything indexes them
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local shared = ReplicatedStorage:WaitForChild("Shared")
for _, name in { "Config", "GameState", "Net", "Theme" } do
	shared:WaitForChild(name)
end

local Confetti = require(script.Confetti)
local Hud = require(script.Hud)
local Intro = require(script.Intro)
local Kit = require(script.Kit)
local Lobby = require(script.Lobby)
local Notify = require(script.Notify)
local Results = require(script.Results)
local Roulette = require(script.Roulette)
local Scoreboard = require(script.Scoreboard)
local Tutorial = require(script.Tutorial)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function screenGui(name: string, order: number, fullScreen: boolean): ScreenGui
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = fullScreen
	if fullScreen then
		-- cover the whole screen (dims), content inside is centered so notches don't matter
		pcall(function()
			gui.ScreenInsets = Enum.ScreenInsets.None
		end)
	end
	gui.Parent = playerGui
	return gui
end

local hud = screenGui("PartyHUD", 5, false)
local overlay = screenGui("PartyOverlay", 10, true)
local notifyGui = screenGui("PartyNotify", 20, false)

-- keep cartoon outlines proportional to the screen size
local function onResize()
	Kit.setViewport(overlay.AbsoluteSize)
end
overlay:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize)
onResize()

local function run(name: string, fn: () -> ())
	-- one broken module must never take the rest of the HUD down with it
	local ok, err = pcall(fn)
	if not ok then
		warn(("[PartyUI] %s failed to start: %s"):format(name, tostring(err)))
	end
end

Confetti.init(overlay)
local notify = nil
run("Notify", function()
	notify = Notify.start(notifyGui)
end)
run("Hud", function()
	Hud.start(hud)
end)
run("Lobby", function()
	Lobby.start(hud)
end)
run("Scoreboard", function()
	Scoreboard.start(hud)
end)
run("Tutorial", function()
	Tutorial.start(hud)
end)
run("Roulette", function()
	Roulette.start(overlay)
end)
run("Intro", function()
	Intro.start(overlay)
end)
run("Results", function()
	Results.start(overlay, notify)
end)
