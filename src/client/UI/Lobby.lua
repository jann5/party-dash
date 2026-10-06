-- Party Dash lobby branding: bouncing "PARTY DASH" logo with a "NEXT GAME IN 12" countdown pill.
-- Shown in Lobby / Waiting (and before Core has written any phase at all).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors
local Phase = GameState.Phase

local Lobby = {}

local LETTER_COLORS = { C.Yellow, C.Orange, C.Pink, C.Cyan, C.Green, C.Yellow, C.Pink, C.Cyan, C.Green }

function Lobby.start(gui: ScreenGui)
	local logo = Kit.box({
		Name = "LobbyLogo",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromScale(0.62, 0.36),
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	})
	Kit.aspect(3.1).Parent = logo
	Kit.sizeLimit(800, 258).Parent = logo
	local logoScale = Kit.scaler(logo)

	local lettersRow = Kit.box({
		Name = "Letters",
		Size = UDim2.fromScale(1, 0.68),
		ZIndex = 3,
		Parent = logo,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = lettersRow,
	})

	type Letter = { label: TextLabel, scale: UIScale, baseRot: number }
	local letters: { Letter } = {}
	local colorIndex = 0
	for i, ch in string.split("PARTY DASH", "") do
		if ch == " " then
			Kit.box({ Name = "Space", Size = UDim2.fromScale(0.05, 1), LayoutOrder = i, Parent = lettersRow })
			continue
		end
		colorIndex += 1
		local holder = Kit.box({
			Name = "L" .. i,
			Size = UDim2.fromScale(0.1, 1),
			LayoutOrder = i,
			ZIndex = 3,
			Parent = lettersRow,
		})
		local label = Kit.label(ch, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.25, 1.1),
			ZIndex = 3,
			Parent = holder,
		}, { maxText = 200, stroke = 7 })
		local color = LETTER_COLORS[colorIndex]
		Kit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Kit.lighten(color, 0.65)),
				ColorSequenceKeypoint.new(0.45, color),
				ColorSequenceKeypoint.new(1, Kit.darken(color, 0.15)),
			}),
			Rotation = 90,
			Parent = label,
		})
		local baseRot = (colorIndex % 2 == 0) and 4 or -4
		label.Rotation = baseRot
		table.insert(letters, { label = label, scale = Kit.scaler(label), baseRot = baseRot })
	end

	-- "NEXT GAME IN 12" pill under the logo
	local pill = Kit.panel(C.Panel, {
		Name = "NextGamePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromScale(0.5, 0.28),
		ZIndex = 4,
		Parent = logo,
	}, UDim.new(0.5, 0), 3.5)
	Kit.gradient(Kit.lighten(C.Panel, 0.15), C.Panel).Parent = pill
	local pillScale = Kit.scaler(pill)
	local caption = Kit.label("NEXT GAME IN", {
		Name = "Caption",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.07, 0.5),
		Size = UDim2.fromScale(0.62, 0.62),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Parent = pill,
	}, { maxText = 40, stroke = 2.5 })
	local numberText = Kit.label("--", {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.71, 0.5),
		Size = UDim2.fromScale(0.22, 0.86),
		TextColor3 = C.Yellow,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = pill,
	}, { maxText = 60, stroke = 3 })
	local numberScale = Kit.scaler(numberText)

	local visible = false
	local lastSecond = -1
	local animConn: RBXScriptConnection? = nil
	local t0 = os.clock()

	local function animate()
		local t = os.clock() - t0
		for i, letter in letters do
			local bob = math.sin(t * 3.2 - i * 0.6)
			letter.label.Position = UDim2.fromScale(0.5, 0.5 - bob * 0.06)
			letter.label.Rotation = letter.baseRot + math.sin(t * 2 + i) * 3
		end
		logo.Rotation = math.sin(t * 0.9) * 1.2

		-- countdown
		local phase = GameState.read("Phase")
		local phaseEnd = tonumber(GameState.read("PhaseEnd")) or 0
		local counting = phase == Phase.Lobby and phaseEnd > 0
		if counting then
			local left = GameState.timeLeft()
			local second = math.ceil(left)
			if second ~= lastSecond then
				lastSecond = second
				caption.Text = "NEXT GAME IN"
				caption.Size = UDim2.fromScale(0.62, 0.62)
				numberText.Visible = true
				numberText.Text = Data.formatTime(left)
				local urgent = second <= 3
				numberText.TextColor3 = urgent and C.Red or C.Yellow
				Kit.punch(numberScale, urgent and 0.4 or 0.2)
				if urgent and second > 0 then
					Sfx.play("tick", 1.2 + (3 - second) * 0.15)
				end
			end
		elseif lastSecond ~= -2 then
			lastSecond = -2
			numberText.Visible = false
			caption.Size = UDim2.fromScale(0.86, 0.6)
			caption.Text = phase == Phase.Lobby and "NEXT GAME SOON!" or "WAITING FOR PLAYERS..."
		end
		if not counting then
			-- gentle breathing so the waiting state never looks frozen
			pillScale.Scale = 1 + math.sin(t * 3) * 0.03
		end
	end

	local function setVisible(on: boolean)
		if on == visible then
			return
		end
		visible = on
		if on then
			logo.Visible = true
			lastSecond = -1
			t0 = os.clock()
			Kit.popIn(logoScale, 0.5)
			for i, letter in letters do
				Kit.popIn(letter.scale, 0.55, 0.15 + i * 0.06)
			end
			Kit.popIn(pillScale, 0.45, 0.5)
			if not animConn then
				animConn = RunService.RenderStepped:Connect(animate)
			end
		else
			local tw = Kit.popOut(logoScale, 0.25)
			tw.Completed:Connect(function()
				if not visible then
					logo.Visible = false
					if animConn then
						animConn:Disconnect()
						animConn = nil
					end
				end
			end)
		end
	end

	local function refresh()
		local phase = GameState.read("Phase")
		setVisible(phase == nil or phase == "" or phase == Phase.Lobby or phase == Phase.Waiting)
		lastSecond = -1
	end
	GameState.onChanged("Phase", refresh)
	GameState.onChanged("PhaseEnd", function()
		lastSecond = -1
	end)
	refresh()
end

return Lobby
