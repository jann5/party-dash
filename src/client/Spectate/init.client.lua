--!nonstrict
-- Party Dash spectating (V5), camera-only:
--   * Player.Spectating (set by Core after a "spectate" choice) -> the camera follows a living participant and the
--     spectate bar shows the target, prev / next (Q / E), LOBBY (Core_DeathChoice "lobby") and REVIVE while the
--     offer is open. "Nobody left" when the round has no one else alive. Spectating = false gives the camera back.
--   * Lobby players get a "Watch" tile (UIKit.Dock "Right") during a Round, and the lobby's LIVE TV prompt
--     (PD_Action "Watch"): both ask Core to spectate.
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local UIKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIKit"))

local UI = script.Parent:WaitForChild("UI")
local Remotes = require(UI:WaitForChild("Remotes"))
local State = require(UI:WaitForChild("State"))
local Widgets = require(UI:WaitForChild("Widgets"))

local Bar = require(script:WaitForChild("Bar"))
local Follow = require(script:WaitForChild("Follow"))

local player = State.player
local REFRESH = 0.4 -- seconds between target checks (deaths, leavers, respawns)
local KEY_PRIORITY = Enum.ContextActionPriority.High.Value + 100 -- above movement, so Q never dashes while watching

local active = false
local stopped = false -- LOBBY pressed: stop locally right away, even before the server answers
local serial = 0
local bar
local sync

local function cycle(dir: number)
	if active then
		bar.setTarget(Follow.step(dir))
	end
end

bar = Bar.new({
	onPrev = function()
		cycle(-1)
	end,
	onNext = function()
		cycle(1)
	end,
	onLobby = function()
		stopped = true
		Remotes.fire("Core_DeathChoice", "lobby")
		sync()
	end,
})

local function keyHandler(dir: number)
	return function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			UIKit.sound("UiClick")
			cycle(dir)
		end
		return Enum.ContextActionResult.Sink
	end
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	serial += 1
	local mine = serial
	if on then
		bar.show()
		ContextActionService:BindActionAtPriority(
			"PD_SpectatePrev",
			keyHandler(-1),
			false,
			KEY_PRIORITY,
			Enum.KeyCode.Q,
			Enum.KeyCode.ButtonL1
		)
		ContextActionService:BindActionAtPriority(
			"PD_SpectateNext",
			keyHandler(1),
			false,
			KEY_PRIORITY,
			Enum.KeyCode.E,
			Enum.KeyCode.ButtonR1
		)
		local beat = RunService.Heartbeat:Connect(function()
			bar.update()
		end)
		task.spawn(function()
			while mine == serial do
				bar.setTarget(Follow.refresh())
				task.wait(REFRESH)
			end
			beat:Disconnect()
		end)
	else
		ContextActionService:UnbindAction("PD_SpectatePrev")
		ContextActionService:UnbindAction("PD_SpectateNext")
		bar.hide()
		Follow.stop()
	end
end

-- ===== Watch tile (lobby players during a Round) =====
local watch = UIKit.Dock.add("Right", {
	id = "Watch",
	order = 5,
	icon = "spectate_eye",
	label = "Watch",
	color = "Red",
	onClick = function()
		stopped = false
		Remotes.fire("Core_DeathChoice", "spectate")
	end,
})
Widgets.fillHitArea(watch.button)
watch.setTimer("LIVE")
watch.button.Visible = false

sync = function()
	local inRound = State.flag("InRound")
	local solo = State.flag("InSolo")
	local spectating = State.flag("Spectating")
	setActive(spectating and not stopped and not inRound and not solo)

	local wantWatch = State.phase() == "Round" and not inRound and not solo and (not spectating or stopped)
	if watch.button.Visible ~= wantWatch then
		watch.button.Visible = wantWatch
		if wantWatch then
			Widgets.popButton(watch)
		end
	end
end

-- a new Spectating value from the server always wins over the local LOBBY shortcut
player:GetAttributeChangedSignal("Spectating"):Connect(function()
	stopped = false
end)
State.watch({ "Phase" }, { "Spectating", "InRound", "Eliminated", "InSolo" }, sync)

-- the lobby's LIVE TV (Lobby model: ProximityPrompt with PD_Action "Watch")
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player or prompt:GetAttribute("PD_Action") ~= "Watch" then
		return
	end
	if State.phase() == "Round" and not State.flag("InRound") then
		stopped = false
		Remotes.fire("Core_DeathChoice", "spectate")
	else
		UIKit.toast("Nothing live yet!", nil, "spectate_eye")
	end
end)
