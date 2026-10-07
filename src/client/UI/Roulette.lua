--!nonstrict
-- Roulette overlays (Phase Roulette / ModifierRoulette): a full-screen reveal with turning light rays and a
-- horizontal reel of chunky cards (RouletteReel / ModifierReel) that decelerates and lands EXACTLY on the
-- chosen id (MinigameId / ModifierId) a beat before PhaseEnd: tick per card, then a pop, confetti and the name.
-- The reel position is a pure function of server time (PhaseStart -> landing), so late joiners stay in sync.
-- Inspection: PD_Roulette attributes Mode, Spinning, CenterId, SelectedId; the centred card has Centered = true.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Audio = require(ReplicatedStorage.Shared.Audio)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Cards = require(script.Parent.Cards)
local Confetti = require(script.Parent.Confetti)
local Info = require(script.Parent.Info)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Roulette = {}

local CARD = Vector2.new(250, 300)
local STRIDE = 290 -- px between card centres
local LEAD = 3 -- filler cards left of the first reel card
local TAIL = 4 -- filler cards right of the winner
local MIN_REEL = 12 -- short reels are repeated so the spin has some travel
local TICK_GAP = 0.045 -- fastest tick rate (s)

local MODES = {
	Roulette = { csv = "RouletteReel", id = "MinigameId", info = Info.minigame, title = "NEXT GAME" },
	ModifierRoulette = { csv = "ModifierReel", id = "ModifierId", info = Info.modifier, title = "SPECIAL ROUND" },
}

local gui: ScreenGui = nil
local root: Frame = nil
local view = nil -- the open overlay (see open())

-- Reel ids (ending on the winner) for a mode.
local function readReel(mode): ({ string }, string)
	local reel = Info.csv(State.get(mode.csv))
	local winner = State.str(mode.id)
	if winner == "" then
		winner = reel[#reel] or ""
	end
	if #reel == 0 then
		local pool = mode == MODES.Roulette and Info.csv(State.get("VoteOptions")) or {}
		if #pool == 0 then
			pool = Info.knownIds(mode == MODES.Roulette and "MinigameInfo" or "ModifierInfo")
		end
		reel = table.clone(pool)
		if winner == "" then
			winner = pool[1] or ""
		end
	end
	if winner == "" then
		return {}, ""
	end
	if reel[#reel] ~= winner then
		table.insert(reel, winner)
	end
	local base = table.clone(reel)
	local i = #base
	while #reel < MIN_REEL do
		table.insert(reel, 1, base[i])
		i = i > 1 and i - 1 or #base
	end
	return reel, winner
end

local function easeOut(u: number): number
	return 1 - (1 - u) ^ 4
end

local function closeView(fade: boolean)
	local v = view
	if not v then
		return
	end
	view = nil
	if v.conn then
		v.conn:Disconnect()
	end
	gui:SetAttribute("Spinning", false)
	if fade then
		Widgets.fadeOut(v.frame, 0.22)
		task.delay(0.24, function()
			v.frame:Destroy()
			if not view then
				gui.Enabled = false
			end
		end)
	else
		v.frame:Destroy()
		gui.Enabled = false
	end
end

-- Builds the backdrop: blue gradient, slowly turning light rays and a soft glow behind the reel.
local function backdrop(frame: Frame)
	local dim = UIKit.new("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.06,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = frame,
	})
	UIKit.gradient(dim, { C.Blue, C.BlueDark, Color3.fromRGB(14, 40, 110) }, 90)
	local rays = UIKit.new("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(2600, 2600),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		ZIndex = 2,
		Parent = frame,
	})
	for i = 0, 11 do
		local holder = UIKit.new("Frame", {
			Name = "Ray",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Rotation = i * 30,
			ZIndex = 2,
			Parent = rays,
		})
		UIKit.new("Frame", {
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 170, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 2,
			Parent = holder,
		})
	end
	-- endless slow turn; the tween dies with the view
	TweenService
		:Create(rays, TweenInfo.new(24, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })
		:Play()
	local glow = Assets.Textures.glow_soft
	if glow and glow ~= "" then
		UIKit.new("ImageLabel", {
			Name = "Glow",
			BackgroundTransparency = 1,
			Image = glow,
			ImageColor3 = C.Yellow,
			ImageTransparency = 0.35,
			Size = UDim2.fromOffset(900, 700),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			ZIndex = 3,
			Parent = frame,
		})
	end
end

-- Gold selector frame with notches above and below the centre slot.
local function selector(parent: Frame)
	local sel = UIKit.new("Frame", {
		Name = "Selector",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CARD.X + 40, CARD.Y + 52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		ZIndex = 20,
		Parent = parent,
	})
	UIKit.corner(sel, UDim.new(0, 26))
	UIKit.border(sel, 8, C.Yellow)
	for _, y in { 0, 1 } do
		local notch = UIKit.new("Frame", {
			Name = "Notch",
			BackgroundColor3 = C.Yellow,
			Size = UDim2.fromOffset(34, 34),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, y, y == 0 and -6 or 6),
			Rotation = 45,
			ZIndex = 21,
			Parent = sel,
		})
		UIKit.border(notch, 3)
	end
	return sel
end

local function land(v)
	if v.landed then
		return
	end
	v.landed = true
	gui:SetAttribute("Spinning", false)
	gui:SetAttribute("SelectedId", v.winner)
	local card = v.cards[v.winIdx + 1]
	if card then
		card.holder:SetAttribute("Winner", true)
		UIKit.punch(card.body, 1.28)
	end
	Audio.ui("WheelWin")
	Confetti.burst(Vector2.new(0.5, 0.55), 70)
	local info = v.mode.info(v.winner)
	local name = Widgets.dropText(v.frame, {
		name = "WinnerName",
		text = info.name,
		size = 76,
		font = "hype",
		gold = true,
		frameSize = UDim2.new(1, 0, 0, 96),
		position = UDim2.new(0.5, 0, 0.5, CARD.Y / 2 + 60),
		anchor = Vector2.new(0.5, 0),
		zindex = 30,
	})
	UIKit.pop(name, 0.4, 0.3)
end

local function step(v)
	local now = State.now()
	local c
	if now >= v.landT then
		c = v.winIdx
	else
		local u = math.clamp((now - v.startT) / (v.landT - v.startT), 0, 1)
		c = LEAD + (v.winIdx - LEAD) * easeOut(u)
	end
	v.strip.Position = UDim2.new(0.5, -c * STRIDE, 0.5, 0)
	for i, card in v.cards do
		local d = math.abs((i - 1) - c)
		card.scale.Scale = 1 + 0.14 * math.max(0, 1 - d)
	end
	local idx = math.floor(c + 0.5)
	if idx ~= v.centerIdx then
		local old = v.cards[v.centerIdx + 1]
		if old then
			old.stroke.Color = C.Ink
			old.holder:SetAttribute("Centered", false)
		end
		local new = v.cards[idx + 1]
		if new then
			new.stroke.Color = C.Yellow
			new.holder:SetAttribute("Centered", true)
			gui:SetAttribute("CenterId", new.info.id)
		end
		v.centerIdx = idx
		local t = os.clock()
		if not v.landed and t - v.lastTick >= TICK_GAP then
			v.lastTick = t
			Audio.ui("WheelTick", { pitch = 0.95 + math.random() * 0.1 })
		end
	end
	if not v.landed and now >= v.landT then
		land(v)
	end
end

-- Landing time: a short beat before PhaseEnd so the pop and the name are seen inside the phase.
local function retime(v)
	local phaseEnd = State.num("PhaseEnd")
	local endT = phaseEnd > v.startT + 0.6 and phaseEnd or v.startT + 3
	v.landT = endT - math.min(0.7, (endT - v.startT) * 0.2)
end

local function open(phase: string, mode, reel: { string }, winner: string, key: string)
	local keepStart = view and view.phase == phase and view.startT or nil
	closeView(false)
	gui.Enabled = true
	gui:SetAttribute("Mode", phase)
	gui:SetAttribute("Spinning", true)
	gui:SetAttribute("SelectedId", "")
	gui:SetAttribute("CenterId", "")

	local frame =
		UIKit.new("Frame", { Name = "View", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	backdrop(frame)
	local title = Widgets.dropText(frame, {
		name = "Title",
		text = mode.title,
		size = 84,
		font = "hype",
		gold = true,
		frameSize = UDim2.new(1, 0, 0, 104),
		position = UDim2.fromScale(0.5, 0.13),
		anchor = Vector2.new(0.5, 0.5),
		zindex = 30,
	})
	UIKit.pop(title, 0.5, 0.35)
	if phase == "ModifierRoulette" then
		-- "2x COINS" sticker right of the title (never over the reel, even on short phone screens)
		local titleW = Widgets.textWidth(mode.title, 84, Enum.Font.LuckiestGuy)
		local badge = Widgets.pill(frame, {
			name = "Bonus",
			icon = "coins_x2",
			text = "2x COINS",
			height = 62,
			fill = C.Green,
			position = UDim2.new(0.5, math.floor(titleW / 2) + 24, 0.13, 0),
			anchor = Vector2.new(0, 0.5),
			zindex = 30,
		})
		badge.frame.Rotation = -8
		UIKit.pop(badge.frame, 0.5, 0.35)
		task.delay(0.4, function()
			if badge.frame.Parent then
				UIKit.pulse(badge.frame, 1.06, 0.8)
			end
		end)
	end

	local window = UIKit.new("Frame", {
		Name = "Reel",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CARD.Y + 80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		ZIndex = 10,
		Parent = frame,
	})
	local strip = UIKit.new("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 10,
		Parent = window,
	})
	-- fillers cycle the reel's own ids so the edges of the screen are never empty
	local ids = {}
	for i = 1, LEAD do
		table.insert(ids, reel[((#reel - LEAD + i - 1) % #reel) + 1])
	end
	for _, id in reel do
		table.insert(ids, id)
	end
	for i = 1, TAIL do
		table.insert(ids, reel[((i - 1) % #reel) + 1])
	end
	local cards = {}
	for i, id in ids do
		local card = Cards.build(strip, mode.info(id), CARD, {
			name = "Card_" .. i,
			position = UDim2.fromOffset((i - 1) * STRIDE, 0),
			anchor = Vector2.new(0.5, 0.5),
			iconScale = 0.74,
			radius = 22,
			nameSize = 30,
		})
		card.scale = UIKit.new("UIScale", { Name = "ReelScale", Parent = card.holder })
		table.insert(cards, card)
	end
	selector(window)

	local now = State.now()
	local startT = keepStart
	if not startT then
		-- trust PhaseStart only when it belongs to this phase; otherwise start from the moment we saw it
		local ps = State.num("PhaseStart")
		local pe = State.num("PhaseEnd")
		startT = (ps > 0 and ps <= now + 0.5 and now - ps < 8 and pe - ps > 0.5 and pe - ps < 20) and ps or now
	end
	local v = {
		phase = phase,
		mode = mode,
		key = key,
		frame = frame,
		strip = strip,
		cards = cards,
		winner = winner,
		winIdx = LEAD + #reel - 1,
		startT = startT,
		landT = startT + 3,
		centerIdx = -1,
		lastTick = 0,
		landed = false,
	}
	retime(v)
	view = v
	step(v)
	v.conn = RunService.RenderStepped:Connect(function()
		step(v)
	end)
end

local function sync()
	local phase = State.phase()
	local mode = MODES[phase]
	if not mode or State.flag("InSolo") then
		closeView(true)
		return
	end
	local reel, winner = readReel(mode)
	if winner == "" then
		closeView(true)
		return
	end
	local key = phase .. "|" .. table.concat(reel, ",") .. "|" .. winner
	if not view or view.key ~= key then
		open(phase, mode, reel, winner, key)
	else
		retime(view)
	end
end

function Roulette.start()
	gui, root = UIKit.screen("PD_Roulette", "Overlay", { fullscreen = true })
	gui.Enabled = false
	gui:SetAttribute("Spinning", false)
	State.watch(
		{ "Phase", "PhaseEnd", "PhaseStart", "RouletteReel", "MinigameId", "ModifierReel", "ModifierId" },
		{ "InSolo" },
		sync
	)
end

return Roulette
