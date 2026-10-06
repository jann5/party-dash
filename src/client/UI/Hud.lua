-- Party Dash HUD: top-center status pill + big timer (from PhaseEnd), "7 / 12 ALIVE" counter,
-- active modifier tag and the left-side MenuRail other systems plug their buttons into.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameState = require(ReplicatedStorage.Shared.GameState)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors
local Phase = GameState.Phase

local Hud = {}

-- Phases where the top cluster steps aside: the lobby logo or a full-screen overlay owns the screen.
-- Overlay phases hide it instantly so no ghost pill/timer ever shows through the overlay dim.
local OVERLAY_PHASES = {
	[Phase.Roulette] = true,
	[Phase.ModifierRoulette] = true,
	[Phase.Intro] = true,
	[Phase.End] = true,
}
local HIDDEN_PHASES = table.clone(OVERLAY_PHASES)
HIDDEN_PHASES[Phase.Lobby] = true
HIDDEN_PHASES[Phase.Waiting] = true
-- The menu rail slides off-screen while a roulette reel spans the whole width.
local RAIL_AWAY_PHASES = { [Phase.Roulette] = true, [Phase.ModifierRoulette] = true }
local RAIL_HOME = UDim2.new(0, 10, 0.5, 0)
local RAIL_AWAY = UDim2.new(0, -170, 0.5, 0)

local function statusFor(phase: string?): (string, Color3)
	local minigameId = GameState.read("MinigameId")
	local name = typeof(minigameId) == "string" and minigameId ~= "" and Data.minigame(minigameId).name or "PARTY DASH"
	if phase == Phase.Roulette then
		return "PICKING A GAME...", C.Purple
	elseif phase == Phase.ModifierRoulette then
		return "SPECIAL ROUND!", C.Pink
	elseif phase == Phase.Intro then
		return name, C.Blue
	elseif phase == Phase.Countdown then
		return "GET READY!", C.Orange
	elseif phase == Phase.Round then
		return name, C.Blue
	elseif phase == Phase.End then
		return "RESULTS", C.Purple
	end
	return "PARTY DASH", C.Purple
end

local function buildMenuRail(gui: ScreenGui): Frame
	-- Vertical rail at the left-middle. Shop (LayoutOrder 10) and Solo (20) add buttons here.
	-- Width follows screen HEIGHT so buttons stay thumb-sized on phones and modest on 1080p.
	local rail = Kit.new("Frame", {
		Name = "MenuRail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = RAIL_HOME,
		Size = UDim2.fromScale(0.11, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = gui,
	})
	Kit.corner(UDim.new(0, 18)).Parent = rail
	local stroke = Kit.stroke(3, C.Ink, true)
	stroke.Transparency = 1
	stroke.Parent = rail
	Kit.sizeLimit(112, 2000, 60, 0).Parent = rail
	Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = rail,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = rail,
	})
	-- The translucent backing only shows once something is docked, so an empty rail is invisible.
	local function refresh()
		local count = 0
		for _, child in rail:GetChildren() do
			if child:IsA("GuiObject") then
				count += 1
			end
		end
		local show = count > 0
		rail.BackgroundTransparency = show and 0.35 or 1
		stroke.Transparency = show and 0.2 or 1
	end
	rail.ChildAdded:Connect(refresh)
	rail.ChildRemoved:Connect(refresh)
	refresh()
	return rail
end

function Hud.start(gui: ScreenGui)
	local rail = buildMenuRail(gui)
	local railAway = false
	local function refreshRail()
		local away = RAIL_AWAY_PHASES[GameState.read("Phase")] == true
		if away == railAway then
			return
		end
		railAway = away
		Kit.tween(
			rail,
			away and 0.25 or 0.45,
			{ Position = away and RAIL_AWAY or RAIL_HOME },
			away and Enum.EasingStyle.Quad or Enum.EasingStyle.Back,
			away and Enum.EasingDirection.In or Enum.EasingDirection.Out
		)
	end

	-- Top-center cluster ------------------------------------------------------------------------
	local top = Kit.box({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromScale(0.5, 0.26),
		ZIndex = 4,
		Parent = gui,
	})
	Kit.aspect(2.9).Parent = top
	Kit.sizeLimit(520, 180).Parent = top
	local topScale = Kit.scaler(top, 0)

	local pill = Kit.panel(C.Panel, {
		Name = "StatusPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(0.9, 0.36),
		ZIndex = 4,
		Parent = top,
	}, UDim.new(0.5, 0), 3.5)
	local pillGradient = Kit.gradient(C.Purple, Kit.darken(C.Purple, 0.35))
	pillGradient.Parent = pill
	local pillScale = Kit.scaler(pill)
	local statusText = Kit.label("PARTY DASH", {
		Name = "StatusText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.88, 0.7),
		ZIndex = 5,
		Parent = pill,
	}, { maxText = 40, stroke = 2.5 })

	-- a clear gap under the pill (strokes included) so the badges never tuck under it
	local row = Kit.box({
		Name = "BadgeRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(1, 0.34),
		ZIndex = 6,
		Parent = top,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.025, 0),
		Parent = row,
	})

	local timerBadge = Kit.panel(C.Yellow, {
		Name = "TimerBadge",
		Size = UDim2.fromScale(0.3, 1),
		LayoutOrder = 1,
		Visible = false,
		ZIndex = 6,
		Parent = row,
	}, UDim.new(0.35, 0), 3.5)
	local timerGradient = Kit.gradient(C.Yellow, C.Orange)
	timerGradient.Parent = timerBadge
	local timerScale = Kit.scaler(timerBadge)
	local timerText = Kit.label("0", {
		Name = "TimerText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86),
		ZIndex = 7,
		Parent = timerBadge,
	}, { maxText = 64, stroke = 3 })

	local aliveBadge = Kit.panel(C.Green, {
		Name = "AliveBadge",
		Size = UDim2.fromScale(0.56, 1),
		LayoutOrder = 2,
		Visible = false,
		ZIndex = 6,
		Parent = row,
	}, UDim.new(0.35, 0), 3.5)
	Kit.gradient(C.Green, Kit.darken(C.Green, 0.25)).Parent = aliveBadge
	local aliveScale = Kit.scaler(aliveBadge)
	local aliveText = Kit.label("0 / 0 ALIVE", {
		Name = "AliveText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.88, 0.7),
		ZIndex = 7,
		Parent = aliveBadge,
	}, { maxText = 40, stroke = 2.5 })

	local modTag = Kit.panel(C.Pink, {
		Name = "ModifierTag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.72, 0.14),
		Visible = false,
		ZIndex = 6,
		Parent = top,
	}, UDim.new(0.5, 0), 2.5)
	Kit.gradient(C.Pink, C.Purple, 0).Parent = modTag
	local modText = Kit.label("", {
		Name = "ModifierText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.8),
		ZIndex = 7,
		Parent = modTag,
	}, { maxText = 26, stroke = 2 })

	-- State -------------------------------------------------------------------------------------
	local shown = false
	local lastSecond = -1
	local lastAlive: number? = nil

	local hideTween: Tween? = nil
	local function setShown(on: boolean, instant: boolean?)
		if on == shown then
			if not on and instant and top.Visible then
				-- an overlay just took over mid pop-out: vanish now
				if hideTween then
					hideTween:Cancel()
				end
				top.Visible = false
			end
			return
		end
		shown = on
		if hideTween then
			hideTween:Cancel()
			hideTween = nil
		end
		if on then
			top.Visible = true
			Kit.popIn(topScale, 0.4)
		elseif instant then
			topScale.Scale = 0
			top.Visible = false
		else
			local tw = Kit.popOut(topScale, 0.2)
			hideTween = tw
			tw.Completed:Connect(function()
				if not shown then
					top.Visible = false
				end
			end)
		end
	end

	local function refreshAlive()
		local phase = GameState.read("Phase")
		local survival = GameState.read("MinigameKind") ~= "score"
		local alive = tonumber(GameState.read("Alive"))
		local total = tonumber(GameState.read("Participants"))
		local show = (phase == Phase.Round or phase == Phase.Countdown) and survival and alive ~= nil
		aliveBadge.Visible = show
		if not show or not alive then
			lastAlive = nil
			return
		end
		aliveText.Text = ("%d / %d ALIVE"):format(alive, math.max(total or alive, alive))
		if lastAlive and alive < lastAlive then
			-- someone dropped: red flash + punch
			aliveBadge.BackgroundColor3 = C.Red
			Kit.tween(aliveBadge, 0.5, { BackgroundColor3 = C.Green })
			Kit.punch(aliveScale, 0.25)
		end
		lastAlive = alive
	end

	local function refreshModifier()
		local id = GameState.read("ModifierId")
		local phase = GameState.read("Phase")
		local active = typeof(id) == "string"
			and id ~= ""
			and (phase == Phase.Intro or phase == Phase.Countdown or phase == Phase.Round)
		modTag.Visible = active
		if active then
			modText.Text = ("✨ %s  ·  %dx COINS"):format(Data.modifier(id).name, Config.MODIFIER_COIN_MULTIPLIER)
		end
	end

	local function refreshStatus()
		local phase = GameState.read("Phase")
		local text, color = statusFor(phase)
		if statusText.Text ~= text then
			statusText.Text = text
			Kit.punch(pillScale, 0.12)
		end
		pillGradient.Color = ColorSequence.new(Kit.lighten(color, 0.1), Kit.darken(color, 0.4))
		setShown(typeof(phase) == "string" and phase ~= "" and not HIDDEN_PHASES[phase], OVERLAY_PHASES[phase] == true)
		refreshRail()
		refreshAlive()
		refreshModifier()
	end

	top.Visible = false
	GameState.onChanged("Phase", function()
		lastSecond = -1
		refreshStatus()
	end)
	GameState.onChanged("MinigameId", refreshStatus)
	GameState.onChanged("Alive", refreshAlive)
	GameState.onChanged("Participants", refreshAlive)
	GameState.onChanged("MinigameKind", refreshAlive)
	GameState.onChanged("ModifierId", refreshModifier)
	refreshStatus()

	-- Timer: recomputed every frame from PhaseEnd so it never drifts.
	RunService.Heartbeat:Connect(function()
		if not shown then
			return
		end
		-- no badge for open-ended phases, stale/elapsed PhaseEnds (no frozen "0"), or the Countdown,
		-- where the huge centered 3-2-1 already is the timer
		local phaseEnd = tonumber(GameState.read("PhaseEnd")) or 0
		local hasTimer = phaseEnd > workspace:GetServerTimeNow() and GameState.read("Phase") ~= Phase.Countdown
		if timerBadge.Visible ~= hasTimer then
			timerBadge.Visible = hasTimer
			if hasTimer then
				Kit.popIn(timerScale, 0.35)
			end
		end
		if not hasTimer then
			return
		end
		local left = GameState.timeLeft()
		local second = math.ceil(left)
		if second ~= lastSecond then
			lastSecond = second
			timerText.Text = Data.formatTime(left)
			local urgent = second <= 5 and second > 0
			timerGradient.Color = urgent and ColorSequence.new(C.Red, Kit.darken(C.Red, 0.3))
				or ColorSequence.new(C.Yellow, C.Orange)
			Kit.punch(timerScale, urgent and 0.22 or 0.08)
			if urgent and GameState.read("Phase") == Phase.Round then
				Sfx.play("tick", 1 + (5 - second) * 0.08)
			end
		end
	end)
end

return Hud
