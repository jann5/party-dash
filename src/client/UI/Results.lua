-- Party Dash results card (Phase End): ResultText ribbon + podium.
--   score rounds    -> top 3 from ScoresJson on a 2-1-3 podium with scores
--   survival rounds -> the winner(s) from WinnersCsv on gold blocks
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Confetti = require(script.Parent.Confetti)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors
local Phase = GameState.Phase
local localPlayer = Players.LocalPlayer

local Results = {}

local MEDALS = {
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(200, 210, 230),
	Color3.fromRGB(225, 140, 80),
}
local HEIGHTS = { 0.42, 0.3, 0.2 }

type Entry = { userId: number, place: number, score: number? }

function Results.start(gui: ScreenGui, notify: { setBigLane: (boolean) -> () }?)
	local root = Kit.box({ Name = "Results", Visible = false, ZIndex = 25, Parent = gui })
	local dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 25,
		Parent = root,
	})

	local card = Kit.panel(C.Panel, {
		Name = "Card",
		-- sits low enough for the big winner text above it and high enough for the toast lane below
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.62, 0.52),
		ZIndex = 26,
		Parent = root,
	}, UDim.new(0.07, 0), 5)
	Kit.aspect(1.45).Parent = card
	Kit.sizeLimit(800, 552).Parent = card
	Kit.gradient(Kit.lighten(C.Panel, 0.18), Kit.darken(C.Panel, 0.2)).Parent = card
	local cardScale = Kit.scaler(card)

	local ribbon = Kit.panel(C.Pink, {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(0.92, 0.19),
		ZIndex = 30,
		Parent = card,
	}, UDim.new(0.3, 0), 4)
	Kit.gradient(Kit.lighten(C.Pink, 0.2), Kit.darken(C.Pink, 0.15)).Parent = ribbon
	local ribbonScale = Kit.scaler(ribbon)
	local resultText = Kit.label("", {
		Name = "ResultText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.74),
		ZIndex = 31,
		Parent = ribbon,
	}, { maxText = 70, stroke = 4 })

	local podium = Kit.box({
		Name = "Podium",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromScale(0.92, 0.68),
		ZIndex = 27,
		Parent = card,
	})

	local footer = Kit.label("", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.85),
		Size = UDim2.fromScale(0.8, 0.085),
		TextColor3 = C.Yellow,
		ZIndex = 27,
		Parent = card,
	}, { maxText = 40, stroke = 2.5 })

	-- "LOBBY IN 5" chip hanging off the bottom edge (the HUD pill hides during End)
	local timerChip = Kit.panel(C.Cyan, {
		Name = "TimerChip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.36, 0.11),
		Visible = false,
		ZIndex = 30,
		Parent = card,
	}, UDim.new(0.5, 0), 3.5)
	Kit.gradient(Kit.lighten(C.Cyan, 0.3), C.Blue).Parent = timerChip
	local timerText = Kit.label("", {
		Name = "TimerText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.7),
		ZIndex = 31,
		Parent = timerChip,
	}, { maxText = 34, stroke = 2.5 })
	local timerConn: RBXScriptConnection? = nil
	local lastSecond = -1
	local function tickTimer()
		local phaseEnd = tonumber(GameState.read("PhaseEnd")) or 0
		timerChip.Visible = phaseEnd > 0
		local second = math.ceil(GameState.timeLeft())
		if second ~= lastSecond then
			lastSecond = second
			timerText.Text = "LOBBY IN " .. Data.formatTime(second)
		end
	end

	local function makeColumn(entry: Entry, x: number, height: number, delay: number)
		-- bottom anchor: the pop-in grows each column up out of the podium floor
		local col = Kit.box({
			Name = "Place" .. entry.place,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(x, 1),
			Size = UDim2.fromScale(0.3, 1),
			ZIndex = 27,
			Parent = podium,
		})
		col:SetAttribute("UserId", entry.userId)
		local color = MEDALS[entry.place] or C.Cyan
		local mine = entry.userId == localPlayer.UserId

		local block = Kit.panel(color, {
			Name = "Block",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.94, height),
			ZIndex = 28,
			Parent = col,
		}, UDim.new(0.12, 0), 3.5)
		Kit.gradient(Kit.lighten(color, 0.3), Kit.darken(color, 0.1)).Parent = block
		Kit.label(tostring(entry.place), {
			Name = "Rank",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.06),
			Size = UDim2.fromScale(0.8, entry.score and 0.5 or 0.8),
			ZIndex = 29,
			Parent = block,
		}, { maxText = 80, stroke = 3.5 })
		if entry.score then
			Kit.label(Data.formatScore(entry.score) .. " PTS", {
				Name = "Score",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.94),
				Size = UDim2.fromScale(0.86, 0.3),
				ZIndex = 29,
				Parent = block,
			}, { maxText = 28, stroke = 2 })
		end

		local nameLabel = Kit.label(Data.playerName(entry.userId), {
			Name = "PlayerName",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1 - height - 0.015),
			Size = UDim2.fromScale(1.05, 0.11),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = mine and C.Yellow or C.White,
			ZIndex = 29,
			Parent = col,
		}, { maxText = 30, stroke = 2.5 })
		nameLabel:SetAttribute("UserId", entry.userId)

		local avatar = Kit.new("ImageLabel", {
			Name = "Avatar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1 - height - 0.13),
			Size = UDim2.fromScale(0.52, 0.52),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			BackgroundColor3 = Kit.lighten(color, 0.5),
			Image = Data.headshot(entry.userId) or "",
			ZIndex = 29,
			Parent = col,
		})
		Kit.corner(UDim.new(0.5, 0)).Parent = avatar
		Kit.stroke(4, mine and C.Yellow or C.Ink, true).Parent = avatar
		if avatar.Image == "" then
			Kit.label("🙂", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.7, 0.7),
				ZIndex = 30,
				Parent = avatar,
			}, { maxText = 80, stroke = 0 })
		end
		if entry.place == 1 then
			local crown = Kit.label("👑", {
				Name = "Crown",
				AnchorPoint = Vector2.new(0.5, 0.75),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(0.55, 0.55),
				Rotation = -12,
				ZIndex = 31,
				Parent = avatar,
			}, { maxText = 80, stroke = 0 })
			-- endless wobble; the tween dies with the instance when the podium is rebuilt
			TweenService:Create(
				crown,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Rotation = 12 }
			):Play()
		end

		local scale = Kit.scaler(col, 0)
		task.delay(delay, function()
			if col.Parent then
				Kit.popIn(scale, 0.5)
				Sfx.play("pop", 0.9 + entry.place * 0.1)
			end
		end)
	end

	local visible = false
	local function fill()
		for _, child in podium:GetChildren() do
			child:Destroy()
		end
		local text = GameState.read("ResultText")
		resultText.Text = typeof(text) == "string" and text ~= "" and string.upper(text) or "ROUND OVER!"

		local entries: { Entry } = {}
		local isScore = GameState.read("MinigameKind") == "score"
		if isScore then
			for i, e in Data.rankScores(GameState.scores()) do
				if i > 3 then
					break
				end
				table.insert(entries, { userId = e.userId, place = i, score = e.score })
			end
		end
		if #entries == 0 then
			for _, id in Data.csv(GameState.read("WinnersCsv")) do
				local uid = tonumber(id)
				if uid and #entries < 3 then
					table.insert(entries, { userId = uid, place = 1 })
				end
			end
			isScore = false
		end

		local iWon = false
		local myPlace = nil
		for _, e in entries do
			if e.userId == localPlayer.UserId then
				myPlace = e.place
				iWon = e.place == 1
			end
		end

		if #entries == 0 then
			Kit.label("😵", {
				Name = "Nobody",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromScale(0.4, 0.5),
				ZIndex = 28,
				Parent = podium,
			}, { maxText = 160, stroke = 0 })
			Kit.label("NO WINNERS THIS TIME!", {
				Name = "NobodyText",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.74),
				Size = UDim2.fromScale(0.9, 0.16),
				ZIndex = 28,
				Parent = podium,
			}, { maxText = 44, stroke = 3 })
		elseif isScore then
			-- classic 2-1-3 podium
			local xs = { 0.5, 0.17, 0.83 }
			for _, e in entries do
				makeColumn(e, xs[e.place], HEIGHTS[e.place], 0.25 + (4 - e.place) * 0.2)
			end
		else
			local layouts = { { 0.5 }, { 0.3, 0.7 }, { 0.17, 0.5, 0.83 } }
			local xs = layouts[#entries]
			for i, e in entries do
				makeColumn(e, xs[i], HEIGHTS[1], 0.3 + i * 0.15)
			end
		end

		if iWon then
			footer.Text = "🎉 YOU WON! 🎉"
		elseif myPlace then
			footer.Text = ("YOU PLACED #%d!"):format(myPlace)
		else
			footer.Text = "GOOD GAME, EVERYONE!"
		end
		return #entries > 0, iWon
	end

	local function setVisible(on: boolean)
		if notify then
			notify.setBigLane(on)
		end
		if on == visible then
			if on then
				fill()
			end
			return
		end
		visible = on
		if on then
			local anyWinner, iWon = fill()
			root.Visible = true
			dim.BackgroundTransparency = 1
			Kit.tween(dim, 0.35, { BackgroundTransparency = 0.45 })
			card.Rotation = 6
			Kit.popIn(cardScale, 0.55)
			Kit.tween(card, 0.7, { Rotation = 0 }, Enum.EasingStyle.Elastic)
			Kit.popIn(ribbonScale, 0.6, 0.15)
			Sfx.play("land", 1.1)
			if anyWinner then
				task.delay(0.7, function()
					if visible then
						Confetti.rain(iWon and 120 or 60)
					end
				end)
			end
			if iWon then
				Confetti.burst(Vector2.new(0.5, 0.55), 70)
			end
			lastSecond = -1
			if not timerConn then
				timerConn = RunService.Heartbeat:Connect(tickTimer)
			end
		else
			if timerConn then
				timerConn:Disconnect()
				timerConn = nil
			end
			Kit.tween(dim, 0.25, { BackgroundTransparency = 1 })
			Kit.popOut(cardScale, 0.25).Completed:Connect(function()
				if not visible then
					root.Visible = false
				end
			end)
		end
	end

	-- Core may write ResultText / WinnersCsv a moment after switching to End: coalesce + refill.
	local scheduled = false
	local function schedule()
		if scheduled then
			return
		end
		scheduled = true
		task.defer(function()
			scheduled = false
			setVisible(GameState.read("Phase") == Phase.End)
		end)
	end
	for _, key in { "Phase", "ResultText", "WinnersCsv" } do
		GameState.onChanged(key, schedule)
	end
	-- names of players who already left resolve asynchronously: patch the labels in place
	Data.NameResolved:Connect(function(userId: number)
		for _, d in podium:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "PlayerName" and d:GetAttribute("UserId") == userId then
				d.Text = Data.playerName(userId)
			end
		end
	end)
	schedule()
end

return Results
