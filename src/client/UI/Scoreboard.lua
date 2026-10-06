-- Party Dash live TOP 3 for score rounds (MinigameKind == "score"), fed by GameState.ScoresJson.
-- Your own row is highlighted; if you are outside the top 3 a "YOU #n" row appears underneath.
-- Rows are reused (ScoresJson updates ~4x per second), only their text/colors change.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)

local C = Theme.Colors
local Phase = GameState.Phase
local localPlayer = Players.LocalPlayer

local Scoreboard = {}

local MEDALS = {
	Color3.fromRGB(255, 205, 60), -- gold
	Color3.fromRGB(200, 210, 230), -- silver
	Color3.fromRGB(225, 140, 80), -- bronze
}

type Row = {
	frame: Frame,
	scale: UIScale,
	rank: TextLabel,
	medal: Frame,
	name: TextLabel,
	score: TextLabel,
	userId: number?,
	value: number?,
}

function Scoreboard.start(gui: ScreenGui)
	local panel = Kit.panel(C.Panel, {
		Name = "Top3",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0.34, 0),
		Size = UDim2.fromScale(0.22, 0.32),
		BackgroundTransparency = 0.08,
		Visible = false,
		ZIndex = 4,
		Parent = gui,
	}, UDim.new(0, 16), 3.5)
	Kit.aspect(1.45).Parent = panel
	Kit.sizeLimit(340, 235).Parent = panel
	Kit.gradient(Kit.lighten(C.Panel, 0.12), C.Panel).Parent = panel
	local panelScale = Kit.scaler(panel)

	Kit.label("🏆 TOP 3", {
		Name = "Header",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.9, 0.18),
		TextColor3 = C.Yellow,
		ZIndex = 5,
		Parent = panel,
	}, { maxText = 36, stroke = 2.5 })

	local function makeRow(i: number, parent: Instance, y: number): Row
		local frame = Kit.panel(C.White, {
			Name = "Row" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromScale(0.92, 0.22),
			BackgroundTransparency = 0.85,
			ZIndex = 5,
			Parent = parent,
		}, UDim.new(0.3, 0), 0)
		local medal = Kit.panel(MEDALS[i] or C.Cyan, {
			Name = "Medal",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.03, 0.5),
			Size = UDim2.fromScale(0.82, 0.82),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 6,
			Parent = frame,
		}, UDim.new(0.5, 0), 2.5)
		local rank = Kit.label(tostring(i), {
			Name = "Rank",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.8),
			ZIndex = 7,
			Parent = medal,
		}, { maxText = 30, stroke = 2 })
		local name = Kit.label("", {
			Name = "PlayerName",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.2, 0.5),
			Size = UDim2.fromScale(0.54, 0.62),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6,
			Parent = frame,
		}, { maxText = 28, stroke = 2 })
		local score = Kit.label("0", {
			Name = "Score",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.96, 0.5),
			Size = UDim2.fromScale(0.22, 0.7),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.Yellow,
			ZIndex = 6,
			Parent = frame,
		}, { maxText = 30, stroke = 2 })
		return { frame = frame, scale = Kit.scaler(frame), rank = rank, medal = medal, name = name, score = score }
	end

	local rows: { Row } = {}
	for i = 1, 3 do
		rows[i] = makeRow(i, panel, 0.25 + (i - 1) * 0.245)
	end
	-- "you" row under the panel when you're not in the top 3
	local meHolder = Kit.box({
		Name = "MeHolder",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1.04),
		Size = UDim2.fromScale(1, 0.24),
		Visible = false,
		ZIndex = 5,
		Parent = panel,
	})
	local me = makeRow(4, meHolder, 0)
	me.frame.Size = UDim2.fromScale(1, 1)
	me.frame.BackgroundColor3 = C.Yellow
	me.frame.BackgroundTransparency = 0
	me.medal.BackgroundColor3 = C.Cyan
	Kit.stroke(3, C.Ink, true).Parent = me.frame

	local function paintRow(row: Row, entry: { userId: number, score: number }?, rank: number)
		if not entry then
			row.frame.Visible = false
			row.userId = nil
			return
		end
		row.frame.Visible = true
		local mine = entry.userId == localPlayer.UserId
		row.rank.Text = tostring(rank)
		row.name.Text = Data.playerName(entry.userId)
		row.score.Text = Data.formatScore(entry.score)
		row.frame:SetAttribute("UserId", entry.userId)
		row.frame:SetAttribute("Score", entry.score)
		if rank <= 3 then
			row.frame.BackgroundColor3 = mine and C.Yellow or C.White
			row.frame.BackgroundTransparency = mine and 0 or 0.85
			row.score.TextColor3 = mine and C.White or C.Yellow
		end
		if row.userId ~= entry.userId then
			Kit.punch(row.scale, 0.15)
		elseif row.value ~= entry.score then
			Kit.punch(row.scale, 0.06, 0.2)
		end
		row.userId = entry.userId
		row.value = entry.score
	end

	local visible = false
	local function render()
		local ranked = Data.rankScores(GameState.scores())
		local myRank = nil
		for i, entry in ranked do
			if entry.userId == localPlayer.UserId then
				myRank = i
			end
		end
		for i = 1, 3 do
			paintRow(rows[i], ranked[i], i)
		end
		local showMe = myRank ~= nil and myRank > 3
		meHolder.Visible = showMe
		if showMe and myRank then
			paintRow(me, ranked[myRank], myRank)
			me.rank.Text = "#" .. myRank
		end
	end

	local function refresh()
		local show = GameState.read("Phase") == Phase.Round and GameState.read("MinigameKind") == "score"
		if show ~= visible then
			visible = show
			if show then
				panel.Visible = true
				panel.Position = UDim2.fromScale(1.4, 0.34)
				Kit.tween(panel, 0.45, { Position = UDim2.new(1, -10, 0.34, 0) }, Enum.EasingStyle.Back)
				Kit.popIn(panelScale, 0.4)
			else
				Kit.popOut(panelScale, 0.25).Completed:Connect(function()
					if not visible then
						panel.Visible = false
					end
				end)
			end
		end
		if show then
			render()
		end
	end

	GameState.onChanged("Phase", refresh)
	GameState.onChanged("MinigameKind", refresh)
	GameState.onChanged("ScoresJson", function()
		if visible then
			render()
		end
	end)
	Data.NameResolved:Connect(function()
		if visible then
			render()
		end
	end)
	refresh()
end

return Scoreboard
