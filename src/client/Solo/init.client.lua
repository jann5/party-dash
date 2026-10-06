--!strict
--[[
Party Dash: Solo Record (P10), client boot.

	SOLO button (PartyHUD.MenuRail, LayoutOrder 20) -> picker -> Solo_Start(id)
	server "intro"  -> in-run HUD (personal 3-2-1 comes through Core_Announce)
	server "go"     -> the clock runs
	server "result" -> result card (NEW RECORD! + confetti, or your time vs. your best)

While Player.InSolo is true the shared round UI (PartyHUD / PartyOverlay: roulette reels, intro cards,
round results of the main game) is hidden so it never covers the private run; it comes back afterwards.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Confetti = require(script.Confetti)
local Data = require(script.Data)
local Picker = require(script.Picker)
local RailButton = require(script.RailButton)
local Result = require(script.Result)
local RunHud = require(script.RunHud)
local Ui = require(script.Ui)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local PENDING_TIMEOUT = 6
-- Shared round UI that steps aside during a private run.
local MAIN_GUIS = { "PartyHUD", "PartyOverlay" }

-- ScreenGuis ------------------------------------------------------------------------------------------

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
		pcall(function()
			gui.ScreenInsets = Enum.ScreenInsets.None
		end)
	end
	gui.Parent = playerGui
	return gui
end

local hudGui = screenGui("SoloHud", 12, false)
local overlayGui = screenGui("SoloOverlay", 15, true)

local function onResize()
	Ui.setViewport(overlayGui.AbsoluteSize)
end
overlayGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize)
onResize()
Confetti.init(overlayGui)

-- Remotes -------------------------------------------------------------------------------------------

local startRemote = Net.event("Solo_Start")
local quitRemote = Net.event("Solo_Quit")
local stateRemote = Net.event("Solo_State")

-- State ---------------------------------------------------------------------------------------------

local pending = false
local pendingToken = 0
local lastPick = "RANDOM"

local function inRound(): boolean
	return localPlayer:GetAttribute("InRound") == true
end

local function inSolo(): boolean
	return localPlayer:GetAttribute("InSolo") == true
end

local function canStart(): boolean
	return not inRound() and not inSolo() and not pending
end

local rail: RailButton.Api
local picker: Picker.Api
local hud: RunHud.Api
local result: Result.Api

local function refreshButton()
	if rail then
		rail.setEnabled(not inRound() and not inSolo())
	end
end

local function requestStart(id: string)
	if not canStart() then
		return
	end
	lastPick = id
	pending = true
	pendingToken += 1
	local myToken = pendingToken
	startRemote:FireServer(id)
	task.delay(PENDING_TIMEOUT, function()
		if pendingToken == myToken then
			pending = false
		end
	end)
end

picker = Picker.new(overlayGui, function(id: string)
	picker.close()
	requestStart(id)
end)

hud = RunHud.new(hudGui, function()
	quitRemote:FireServer()
end)

result = Result.new(overlayGui)

rail = RailButton.mount(hudGui, function()
	if not inRound() and not inSolo() then
		result.hide()
		picker.open()
	end
end)

-- Shared UI hiding while in a private run -------------------------------------------------------------

local hiddenGuis: { [ScreenGui]: boolean } = {}

local function setMainUiHidden(hidden: boolean)
	if hidden then
		for _, name in MAIN_GUIS do
			local gui = playerGui:FindFirstChild(name)
			if gui and gui:IsA("ScreenGui") and hiddenGuis[gui] == nil then
				hiddenGuis[gui] = gui.Enabled
				gui.Enabled = false
			end
		end
	else
		for gui, wasEnabled in hiddenGuis do
			if gui.Parent then
				gui.Enabled = wasEnabled
			end
		end
		table.clear(hiddenGuis)
	end
end

local function onSoloChanged()
	local solo = inSolo()
	setMainUiHidden(solo)
	if solo then
		picker.close()
	elseif hud.isShown() then
		-- Safety: the run ended without a result message (e.g. the server cleaned up).
		hud.hide()
	end
	refreshButton()
end

local function onRoundChanged()
	if inRound() then
		picker.close()
		result.hide()
	end
	refreshButton()
end

localPlayer:GetAttributeChangedSignal("InSolo"):Connect(onSoloChanged)
localPlayer:GetAttributeChangedSignal("InRound"):Connect(onRoundChanged)
onSoloChanged()
onRoundChanged()

-- Server messages -------------------------------------------------------------------------------------

stateRemote.OnClientEvent:Connect(function(kind: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "intro" then
		pending = false
		pendingToken += 1
		picker.close()
		result.hide()
		setMainUiHidden(true)
		local id = tostring(payload.minigameId)
		local name = if type(payload.displayName) == "string" then payload.displayName else Data.gameName(id)
		hud.show(id, name, if type(payload.best) == "number" then payload.best else nil)
	elseif kind == "go" then
		if type(payload.startedAt) == "number" then
			hud.go(payload.startedAt)
		end
	elseif kind == "result" then
		pending = false
		hud.freeze()
		hud.hide()
		setMainUiHidden(false)
		-- PLAY AGAIN repeats the pick: the same minigame, or a fresh roll when RANDOM was chosen.
		local again = if lastPick == "RANDOM" then "RANDOM" else tostring(payload.minigameId)
		result.show(
			{
				minigameId = tostring(payload.minigameId),
				displayName = if type(payload.displayName) == "string"
					then payload.displayName
					else Data.gameName(tostring(payload.minigameId)),
				seconds = tonumber(payload.seconds) or 0,
				best = tonumber(payload.best),
				previous = tonumber(payload.previous),
				isRecord = payload.isRecord == true,
				reason = tostring(payload.reason),
				rank = tonumber(payload.rank),
				started = payload.started == true,
			},
			if inRound()
				then nil
				else function()
					requestStart(again)
				end
		)
		refreshButton()
	elseif kind == "rejected" then
		pending = false
		pendingToken += 1
		refreshButton()
	end
end)
