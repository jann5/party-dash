--!nonstrict
-- Top-center status (UIKit.Lanes "Top"), one glance tells you what is going on:
--   Lobby      [stopwatch NEXT GAME 0:14]  then  [join pad  Step on the PLAY pad!]  or  [YOU'RE IN!] [3/12 READY]
--   LobbyHold  [join pad  Step in to play!]                      (nobody queued: the timer waits for you)
--   Round      [game icon  BOMB TAG] [players 7/12] [modifier] [SUDDEN DEATH]   (round members, Countdown/Round)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Info = require(script.Parent.Info)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Status = {}

local function row(parent: Instance, order: number, height: number): Frame
	local f = UIKit.new("Frame", {
		Name = "Row" .. order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.list(f, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	return f
end

-- Shows/hides a pill; a pill that appears pops in.
local function show(pill, on: boolean)
	local f = pill.frame
	if f.Visible ~= on then
		f.Visible = on
		if on then
			UIKit.pop(f, 0.6, 0.25)
		end
	end
end

function Status.start()
	local lane = UIKit.Lanes.get("Top")
	local holder = UIKit.new("Frame", {
		Name = "PD_Status",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(900, 136),
		LayoutOrder = 10,
		Parent = lane,
	})
	UIKit.list(holder, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local row1 = row(holder, 1, 66)
	local row2 = row(holder, 2, 60)

	-- sized for the widest timer text so the pill never jitters as the digits change
	local nextPill =
		Widgets.pill(row1, { name = "NextGame", icon = "stopwatch", text = "NEXT GAME 00:00", height = 64 })
	local holdPill = Widgets.pill(row1, {
		name = "Hold",
		icon = "join_pad",
		text = "Step in to play!",
		height = 64,
		fill = C.Yellow,
		layoutOrder = 2,
	})
	local gamePill =
		Widgets.pill(row1, { name = "Minigame", icon = "mg_random", text = "GAME", height = 64, fill = C.Blue })
	local alivePill =
		Widgets.pill(row1, { name = "Alive", icon = "group_friends", text = "0/0", height = 64, layoutOrder = 2 })
	local modPill = Widgets.pill(row1, {
		name = "Modifier",
		icon = "lightning",
		text = "MODIFIER",
		height = 64,
		fill = C.Purple,
		layoutOrder = 3,
	})
	local suddenPill = Widgets.pill(row1, {
		name = "SuddenDeath",
		icon = "alarm_clock",
		text = "SUDDEN DEATH",
		height = 64,
		fill = C.Red,
		layoutOrder = 4,
	})
	local hintPill = Widgets.pill(row2, {
		name = "JoinHint",
		icon = "join_pad",
		text = "Step on the PLAY pad!",
		height = 58,
		fill = C.Yellow,
	})
	local inPill =
		Widgets.pill(row2, { name = "YoureIn", icon = "check_badge", text = "YOU'RE IN!", height = 58, fill = C.Green })
	local readyPill = Widgets.pill(
		row2,
		{ name = "Ready", icon = "group_friends", text = "0/12 READY", height = 58, layoutOrder = 2 }
	)

	local pills = { nextPill, holdPill, gamePill, alivePill, modPill, suddenPill, hintPill, inPill, readyPill }
	for _, pill in pills do
		pill.frame.Visible = false
	end
	-- the join hints bounce their pad icon toward the player (the "go there" arrow)
	UIKit.bob(hintPill.icon, 7)
	UIKit.bob(holdPill.icon, 7)
	local stopSudden: (() -> ())? = nil

	local lastAlive = -1
	local lastQueued = false
	local function refresh()
		local phase = State.phase()
		local solo = State.flag("InSolo")
		local queued = State.flag("Queued")
		local lobby = phase == "Lobby" and not solo
		local hold = lobby and (State.get("LobbyHold") == true or State.num("PhaseEnd") <= 0)
		local roundView = not solo and State.isMember() and (phase == "Countdown" or phase == "Round")
		local modifierId = State.str("ModifierId")
		local sudden = roundView and State.get("SuddenDeath") == true

		show(nextPill, lobby and not hold)
		show(holdPill, hold and not queued)
		show(hintPill, lobby and not hold and not queued)
		show(inPill, lobby and queued)
		show(readyPill, lobby and queued)
		show(gamePill, roundView and State.str("MinigameId") ~= "")
		show(alivePill, roundView)
		show(modPill, roundView and modifierId ~= "")
		show(suddenPill, sudden)
		holder:SetAttribute(
			"State",
			if roundView then "Round" elseif hold then "Hold" elseif lobby then "Lobby" else ""
		)

		if lobby and queued and not lastQueued then
			UIKit.punch(inPill.frame, 1.2)
			Audio.ui("UiOpen")
		end
		lastQueued = lobby and queued
		readyPill.fit(("%d/%d READY"):format(math.floor(State.num("QueuedCount")), Config.MAX_PLAYERS))

		if roundView then
			local mg = Info.minigame(State.str("MinigameId"))
			gamePill.setIcon(mg.icon)
			gamePill.fit(mg.name)
			Widgets.paint(gamePill.frame, mg.color)
			local alive, total = math.floor(State.num("Alive")), math.floor(State.num("Participants"))
			alivePill.fit(total > 0 and ("%d/%d"):format(alive, total) or tostring(alive))
			if lastAlive >= 0 and alive ~= lastAlive then
				UIKit.punch(alivePill.frame, alive < lastAlive and 1.25 or 1.12)
			end
			lastAlive = alive
			if modifierId ~= "" then
				local mod = Info.modifier(modifierId)
				modPill.setIcon(mod.icon)
				modPill.fit(mod.name)
			end
		else
			lastAlive = -1
		end
		if sudden and not stopSudden then
			stopSudden = UIKit.pulse(suddenPill.frame, 1.08, 0.7)
		elseif not sudden and stopSudden then
			stopSudden()
			stopSudden = nil
		end
	end
	State.watch({
		"Phase",
		"PhaseEnd",
		"LobbyHold",
		"QueuedCount",
		"MinigameId",
		"ModifierId",
		"Alive",
		"Participants",
		"SuddenDeath",
	}, { "Queued", "InRound", "Eliminated", "Spectating", "InSolo" }, refresh)

	-- lobby timer: text changes once per second; the last 5 s turn yellow, punch and tick for queued players
	local lastSecond = -1
	RunService.Heartbeat:Connect(function()
		if not nextPill.frame.Visible then
			lastSecond = -1
			return
		end
		local secs = math.ceil(State.timeLeft())
		if secs == lastSecond then
			return
		end
		lastSecond = secs
		nextPill.label.Text = "NEXT GAME " .. UIKit.fmt.clock(secs)
		local urgent = secs <= 5
		nextPill.label.TextColor3 = urgent and C.Yellow or C.White
		if urgent and secs > 0 then
			UIKit.punch(nextPill.frame, 1.1)
			if State.flag("Queued") then
				Audio.ui("WheelTick", { pitch = 1 + (5 - secs) * 0.05 })
			end
		end
	end)
end

return Status
