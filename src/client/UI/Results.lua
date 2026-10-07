--!nonstrict
-- Results card (Phase End, round members): the result headline exactly ONCE, a 1-2-3 podium (gold / silver /
-- bronze blocks, crown on the winner), the MVP ribbon, and my reward breakdown from Player.LastReward (lines count
-- up, then the total, a coin fly-in with CoinCollect and the XP bar fill). A round played alone shows
-- "Play with friends to earn WINS!" instead of the podium.
-- 2nd / 3rd place come from the order participants dropped out (their InRound turning false during the Round).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Audio = require(ReplicatedStorage.Shared.Audio)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Confetti = require(script.Parent.Confetti)
local Hype = require(script.Parent.Hype)
local Info = require(script.Parent.Info)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Results = {}

local SIZE = Vector2.new(960, 520)
local PODIUM = {
	{ place = 1, color = C.Gold, height = 150, x = 156 },
	{ place = 2, color = C.Silver, height = 112, x = 16 },
	{ place = 3, color = C.Bronze, height = 84, x = 296 },
}
local BLOCK_W = 128
local MAX_LINES = 6

local gui: ScreenGui = nil
local root: Frame = nil
local view = nil -- the open card state
local member = false -- latched: was a round member during this round (Core may clear Eliminated at End)
local played = false -- latched: was alive in this round
local eliminations: { [number]: number } = {} -- userId -> os.clock() when they dropped out
local rewardBaseline: string? = nil -- LastReward when this round began (stale until it changes)
local levelAtStart: number? = nil
local lastPhase = ""

local function winners(): { number }
	local ids = {}
	for _, s in Info.csv(State.get("WinnersCsv")) do
		local id = tonumber(s)
		if id and not table.find(ids, id) then
			table.insert(ids, id)
		end
	end
	return ids
end

local function audience(): boolean
	if State.flag("InSolo") then
		return false
	end
	return member or State.isMember() or table.find(winners(), State.player.UserId) ~= nil
end

-- True while the results card owns this text (the Announce router then drops a duplicate big headline).
function Results.claims(text: string): boolean
	if State.phase() ~= "End" or not audience() then
		return false
	end
	local result = Info.clean(State.str("ResultText"))
	return result ~= "" and Hype.key(result) == Hype.key(text)
end

-- Winners first (WinnersCsv order), then everyone else by how late they dropped out.
local function ranking(): { number }
	local list = winners()
	local rest = {}
	for userId, t in eliminations do
		if not table.find(list, userId) then
			table.insert(rest, { userId, t })
		end
	end
	table.sort(rest, function(a, b)
		return a[2] > b[2]
	end)
	for _, r in rest do
		table.insert(list, r[1])
	end
	return list
end

local function mvp(order: { number }): (Player?, number)
	local best, bestKos, bestRank = nil, 0, math.huge
	for _, p in Players:GetPlayers() do
		local kos = p:GetAttribute("KOs")
		if typeof(kos) == "number" and kos >= 1 then
			local rank = table.find(order, p.UserId) or 99
			if kos > bestKos or (kos == bestKos and rank < bestRank) then
				best, bestKos, bestRank = p, kos, rank
			end
		end
	end
	return best, bestKos
end

local function freshReward()
	local raw = State.player:GetAttribute("LastReward")
	if typeof(raw) ~= "string" or raw == "" or raw == rewardBaseline then
		return nil
	end
	local t = Info.json(raw)
	if not t then
		return nil
	end
	local lines = {}
	if typeof(t.lines) == "table" then
		for _, line in t.lines do
			if typeof(line) == "table" and tonumber(line.coins) then
				table.insert(lines, { label = Info.clean(tostring(line.label or "")), coins = tonumber(line.coins) })
			end
			if #lines >= MAX_LINES then
				break
			end
		end
	end
	local total = tonumber(t.total)
	if not total then
		total = 0
		for _, line in lines do
			total += line.coins
		end
	end
	return { raw = raw, lines = lines, total = total, xp = tonumber(t.xp) or 0 }
end

-- ===== podium =====

local function podiumSlot(area: Frame, slot, userId: number, delay: number)
	local column = UIKit.new("Frame", {
		Name = "Place" .. slot.place,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BLOCK_W, 330),
		Position = UDim2.fromOffset(slot.x, 0),
		ZIndex = 4,
		Parent = area,
	})
	column:SetAttribute("UserId", userId)
	local block = UIKit.new("Frame", {
		Name = "Block",
		Size = UDim2.fromOffset(BLOCK_W, 0),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		ClipsDescendants = true, -- the number rises with the block
		ZIndex = 4,
		Parent = column,
	})
	UIKit.corner(block, UDim.new(0, 12))
	UIKit.border(block, 4)
	Widgets.paint(block, slot.color)
	local studs = Assets.Textures.studs
	if studs and studs ~= "" then
		local pattern = UIKit.new("ImageLabel", {
			Name = "Pattern",
			BackgroundTransparency = 1,
			Image = studs,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(32, 32),
			ImageTransparency = 0.82,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = block,
		})
		UIKit.corner(pattern, UDim.new(0, 12))
	end
	UIKit.text(block, {
		name = "Number",
		text = tostring(slot.place),
		size = 68,
		font = "hype",
		frameSize = UDim2.new(1, 0, 0, 80),
		position = UDim2.new(0.5, 0, 0, 8),
		anchor = Vector2.new(0.5, 0),
		zindex = 6,
	})
	local nameLabel = UIKit.text(column, {
		name = "Name",
		text = "",
		size = 24,
		frameSize = UDim2.new(1, 24, 0, 30),
		position = UDim2.new(0.5, 0, 1, -(slot.height + 6)),
		anchor = Vector2.new(0.5, 1),
		zindex = 7,
	})
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Info.nameInto(nameLabel, userId)
	local avatar = Widgets.avatar(column, userId, 86, {
		position = UDim2.new(0.5, 0, 1, -(slot.height + 40)),
		anchor = Vector2.new(0.5, 1),
		zindex = 7,
		ringColor = slot.color,
		fallback = slot.place == 1 and "trophy" or "medal",
	})
	if slot.place == 1 then
		UIKit.icon(avatar, "crown", {
			name = "Crown",
			size = UDim2.fromOffset(78, 78),
			position = UDim2.new(0.5, 0, 0, -20),
			rotation = -12,
			zindex = 9,
		})
	end
	if userId == State.player.UserId then
		local ring = avatar:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Color = C.Yellow -- that's you
			ring.Thickness = 4
		end
	end
	nameLabel.Visible = false
	avatar.Visible = false
	task.delay(delay, function()
		if not block.Parent then
			return
		end
		UIKit.tween(block, 0.45, { Size = UDim2.fromOffset(BLOCK_W, slot.height) }, Enum.EasingStyle.Back)
		task.wait(0.3)
		if avatar.Parent then
			nameLabel.Visible = true
			avatar.Visible = true
			UIKit.pop(avatar, 0.3, 0.3)
			if slot.place == 1 then
				UIKit.shine(block, 2.5)
			end
		end
	end)
end

local function buildPodium(area: Frame, order: { number })
	if State.num("Participants") == 1 then
		UIKit.icon(area, "group_friends", {
			size = UDim2.fromOffset(170, 170),
			position = UDim2.fromScale(0.5, 0.36),
			zindex = 5,
		})
		local hint = UIKit.text(area, {
			name = "SoloHint",
			text = "Play with friends to earn WINS!",
			size = 34,
			wrap = true,
			frameSize = UDim2.new(1, -20, 0, 90),
			position = UDim2.fromScale(0.5, 0.78),
			anchor = Vector2.new(0.5, 0.5),
			zindex = 5,
		})
		UIKit.pop(hint, 0.6, 0.3)
		return
	end
	if #order == 0 then
		UIKit.icon(area, "party_popper", {
			size = UDim2.fromOffset(190, 190),
			position = UDim2.fromScale(0.5, 0.45),
			zindex = 5,
		})
		return
	end
	local delays = { 0.55, 0.35, 0.15 } -- 1st rises last
	for i, slot in PODIUM do
		local userId = order[slot.place]
		if userId then
			podiumSlot(area, slot, userId, delays[i])
		end
	end
end

-- ===== rewards =====

local function rewardRow(parent: Instance, order: number, label: string, coins: number, height: number)
	local row = UIKit.new("Frame", {
		Name = "Line",
		BackgroundColor3 = C.PanelLight,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	})
	UIKit.corner(row, UDim.new(0, 10))
	UIKit.border(row, 2.5)
	UIKit.text(row, {
		name = "Label",
		text = label,
		size = 24,
		font = "bodyHeavy",
		xalign = "left",
		frameSize = UDim2.new(1, -150, 1, 0),
		position = UDim2.fromOffset(14, 0),
		zindex = 6,
	})
	UIKit.icon(row, "coin", { size = UDim2.fromOffset(38, 38), position = UDim2.new(1, -26, 0.5, 0), zindex = 6 })
	local value = UIKit.text(row, {
		name = "Coins",
		text = "+0",
		size = 28,
		color = C.Yellow,
		xalign = "right",
		frameSize = UDim2.fromOffset(110, 40),
		position = UDim2.new(1, -50, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		zindex = 6,
	})
	row.Visible = false
	return row, value, coins
end

local function plus(n: number): string
	return "+" .. UIKit.fmt.number(n)
end

-- Coins fly from `from` (a GuiObject on the card) to the bottom-left currency corner.
local function coinFlight(v, from: GuiObject)
	local scale = UIKit.scale()
	local rootPos = root.AbsolutePosition
	local start = (from.AbsolutePosition + from.AbsoluteSize / 2 - rootPos) / scale
	local target = Vector2.new(80, root.AbsoluteSize.Y / scale - 110)
	for i = 1, 8 do
		local coin = UIKit.icon(v.frame, "coin", {
			name = "FlyingCoin",
			size = UDim2.fromOffset(54, 54),
			position = UDim2.fromOffset(start.X, start.Y),
			zindex = 40,
		})
		task.delay(i * 0.05, function()
			if not coin.Parent then
				return
			end
			local mid = start:Lerp(target, 0.5) + Vector2.new(math.random(-120, 120), -160)
			UIKit.tween(coin, 0.28, { Position = UDim2.fromOffset(mid.X, mid.Y) }, Enum.EasingStyle.Quad)
			task.wait(0.28)
			if coin.Parent then
				UIKit.tween(coin, 0.32, {
					Position = UDim2.fromOffset(target.X, target.Y),
					Size = UDim2.fromOffset(30, 30),
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.wait(0.32)
				coin:Destroy()
				if i == 1 or i == 8 then
					Audio.ui("CoinCollect", { pitch = i == 1 and 1 or 1.15 })
				end
			end
		end)
	end
end

local function xpBar(parent: Instance, gain: number, layoutOrder: number)
	local level = State.player:GetAttribute("Level")
	local xp = State.player:GetAttribute("XP")
	local nextXp = State.player:GetAttribute("XPNext")
	if typeof(level) ~= "number" or typeof(xp) ~= "number" or typeof(nextXp) ~= "number" or nextXp <= 0 then
		return nil
	end
	local leveledUp = levelAtStart ~= nil and level > levelAtStart
	local row = UIKit.new("Frame", {
		Name = "XP",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = layoutOrder,
		ZIndex = 5,
		Parent = parent,
	})
	local badge = UIKit.new("Frame", {
		Name = "Level",
		Size = UDim2.fromOffset(56, 56),
		ZIndex = 6,
		Parent = row,
	})
	UIKit.corner(badge, UDim.new(0.5, 0))
	UIKit.border(badge, 3)
	Widgets.paint(badge, C.Purple)
	UIKit.text(badge, { text = tostring(level), size = 28, frameSize = UDim2.fromScale(1, 1), zindex = 7 })
	local track = UIKit.new("Frame", {
		Name = "Track",
		BackgroundColor3 = C.PanelDeep,
		Size = UDim2.new(1, -190, 0, 28),
		Position = UDim2.new(0, 68, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 6,
		Parent = row,
	})
	UIKit.corner(track, UDim.new(0.5, 0))
	UIKit.border(track, 3)
	local from = leveledUp and 0 or math.clamp((xp - gain) / nextXp, 0, 1)
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(from, 1),
		ZIndex = 7,
		Parent = track,
	})
	UIKit.corner(fill, UDim.new(0.5, 0))
	Widgets.paint(fill, C.Cyan)
	UIKit.icon(row, "xp_star", { size = UDim2.fromOffset(44, 44), position = UDim2.new(1, -100, 0.5, 0), zindex = 7 })
	UIKit.text(row, {
		name = "Gain",
		text = leveledUp and "LEVEL UP!" or ("+%d XP"):format(math.floor(gain)),
		size = 22,
		color = leveledUp and C.Yellow or C.White,
		xalign = "left",
		frameSize = UDim2.fromOffset(110, 40),
		position = UDim2.new(1, -76, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		zindex = 7,
	})
	return function()
		UIKit.tween(fill, 0.8, { Size = UDim2.fromScale(math.clamp(xp / nextXp, 0, 1), 1) }, Enum.EasingStyle.Quad)
		if leveledUp then
			UIKit.punch(badge, 1.35)
			Audio.ui("LevelUp")
		end
	end
end

local function buildRewards(v, data)
	local col = v.rewards
	for _, child in col:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	v.rewardRaw = data and data.raw or nil
	local list =
		UIKit.new("Frame", { Name = "List", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = col })
	UIKit.list(list, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	Widgets.dropText(list, {
		name = "Title",
		text = "YOUR REWARDS",
		size = 34,
		color = C.Yellow,
		frameSize = UDim2.new(1, 0, 0, 44),
		layoutOrder = 0,
		zindex = 6,
	})

	if not data then
		local waiting = played or State.isMember()
		local pill = Widgets.pill(list, {
			name = "Waiting",
			icon = waiting and "coin_stack" or "join_pad",
			text = waiting and "Counting coins..." or "Join next round!",
			height = 60,
			layoutOrder = 1,
		})
		if waiting then
			UIKit.pulse(pill.frame, 1.05, 0.9)
		end
		return
	end

	local rows = {}
	local rowHeight = #data.lines > 4 and 36 or 44 -- long breakdowns get slimmer rows to stay on the card
	for i, line in data.lines do
		table.insert(rows, { rewardRow(list, i, line.label, line.coins, rowHeight) })
	end
	local totalRow = UIKit.new("Frame", {
		Name = "Total",
		Size = UDim2.new(1, 0, 0, 64),
		LayoutOrder = 50,
		Visible = false,
		ZIndex = 5,
		Parent = list,
	})
	UIKit.corner(totalRow, UDim.new(0, 14))
	UIKit.border(totalRow, 3)
	Widgets.paint(totalRow, C.Green)
	UIKit.text(totalRow, {
		name = "Label",
		text = "TOTAL",
		size = 32,
		xalign = "left",
		frameSize = UDim2.fromScale(0.5, 1),
		position = UDim2.fromOffset(16, 0),
		zindex = 6,
	})
	local totalIcon = UIKit.icon(totalRow, "coin_stack", {
		size = UDim2.fromOffset(70, 70),
		position = UDim2.new(1, -34, 0.5, -4),
		zindex = 7,
	})
	local totalValue = UIKit.text(totalRow, {
		name = "Coins",
		text = "+0",
		size = 44,
		color = C.Yellow,
		xalign = "right",
		frameSize = UDim2.fromOffset(200, 56),
		position = UDim2.new(1, -74, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		zindex = 7,
	})
	local fillXp = xpBar(list, data.xp, 60)

	-- reveal: lines one by one, then the total with the coin flight, then the XP bar
	task.spawn(function()
		task.wait(0.5)
		for _, r in rows do
			if not totalRow.Parent then
				return
			end
			local row, value, coins = r[1], r[2], r[3]
			row.Visible = true
			UIKit.pop(row, 0.7, 0.2)
			UIKit.countUp(value, 0, coins, 0.25, plus)
			Audio.ui("UiHover", { pitch = 1.1 })
			task.wait(0.16)
		end
		task.wait(0.1)
		if not totalRow.Parent then
			return
		end
		totalRow.Visible = true
		UIKit.pop(totalRow, 0.6, 0.3)
		UIKit.countUp(totalValue, 0, data.total, 0.6, plus)
		task.wait(0.15)
		if totalRow.Parent and data.total > 0 then
			coinFlight(v, totalIcon)
		end
		if fillXp then
			fillXp()
		end
	end)
end

-- ===== card =====

local function close()
	local v = view
	if not v then
		return
	end
	view = nil
	v.conn:Disconnect()
	Widgets.fadeOut(v.frame, 0.2)
	task.delay(0.22, function()
		v.frame:Destroy()
		if not view then
			gui.Enabled = false
		end
	end)
end

local function open()
	local order = ranking()
	local resultText = Info.clean(State.str("ResultText"))
	local frame =
		UIKit.new("Frame", { Name = "View", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	local dim = UIKit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = frame,
	})
	UIKit.tween(dim, 0.25, { BackgroundTransparency = 0.5 })
	local card = Widgets.card(frame, {
		name = "Card",
		size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		position = UDim2.fromScale(0.5, 0.54),
		anchor = Vector2.new(0.5, 0.5),
		radius = 26,
	})

	-- headline ribbon (the only place the result text appears)
	local ribbon = UIKit.new("Frame", {
		Name = "Ribbon",
		Size = UDim2.fromOffset(780, 108),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.62),
		ZIndex = 10,
		Parent = card,
	})
	UIKit.corner(ribbon, UDim.new(0, 26))
	UIKit.border(ribbon, 4)
	Widgets.paint(ribbon, C.Purple)
	local headlineText = resultText ~= "" and resultText or "ROUND OVER"
	local n = math.max(1, utf8.len(headlineText) or #headlineText)
	local headline = UIKit.text(ribbon, {
		name = "Headline",
		text = headlineText,
		size = math.clamp(math.floor(740 / (0.7 * n)), 34, 70),
		font = "hype",
		gold = true,
		frameSize = UDim2.new(1, -30, 1, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		zindex = 12,
	})
	gui:SetAttribute("Headline", headlineText)
	Hype.clearIf(headlineText)

	local podium = UIKit.new("Frame", {
		Name = "Podium",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(440, 330),
		Position = UDim2.fromOffset(34, 92),
		ZIndex = 4,
		Parent = card,
	})
	buildPodium(podium, order)

	UIKit.new("Frame", {
		Name = "Divider",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(4, SIZE.Y - 150),
		Position = UDim2.fromOffset(500, 90),
		ZIndex = 4,
		Parent = card,
	})
	local rewards = UIKit.new("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(410, SIZE.Y - 120),
		Position = UDim2.fromOffset(526, 84),
		ZIndex = 4,
		Parent = card,
	})

	local mvpPlayer, mvpKos = mvp(order)
	if mvpPlayer then
		local tag = Widgets.pill(card, {
			name = "MVP",
			icon = "medal",
			text = ("MVP  %s  %d KO%s"):format(mvpPlayer.DisplayName, math.floor(mvpKos), mvpKos == 1 and "" or "s"),
			height = 54,
			fill = C.Orange,
			position = UDim2.fromOffset(254, SIZE.Y - 52),
			anchor = Vector2.new(0.5, 0.5),
			zindex = 9,
		})
		tag.frame.Rotation = -3
		tag.frame.Visible = false
		task.delay(1.1, function()
			if tag.frame.Parent then
				tag.frame.Visible = true
				UIKit.pop(tag.frame, 0.3, 0.3)
			end
		end)
	end

	-- "LOBBY IN 4" chip on the bottom edge
	local timer = Widgets.pill(card, {
		name = "Timer",
		icon = "hourglass",
		text = "LOBBY IN 0",
		height = 50,
		position = UDim2.new(0.5, 0, 1, 4),
		anchor = Vector2.new(0.5, 0.5),
		zindex = 9,
	})

	local v = {
		frame = frame,
		card = card,
		rewards = rewards,
		headline = headline,
		key = resultText .. "|" .. State.str("WinnersCsv"),
		rewardRaw = nil,
	}
	buildRewards(v, freshReward())
	local lastSecs = -1
	v.conn = RunService.Heartbeat:Connect(function()
		local secs = math.ceil(State.timeLeft())
		if secs ~= lastSecs then
			lastSecs = secs
			timer.label.Text = "LOBBY IN " .. secs
			timer.frame.Visible = State.num("PhaseEnd") > 0
		end
	end)

	UIKit.pop(card, 0.75, 0.32)
	UIKit.pop(ribbon, 1.6, 0.3)
	if table.find(winners(), State.player.UserId) then
		Audio.ui("Win")
		Confetti.rain(110)
	end
	return v
end

local function sync()
	local phase = State.phase()
	if phase ~= lastPhase then
		-- round bookkeeping: a new round resets the podium order and the reward baseline
		if phase == "Intro" or (phase == "Countdown" and lastPhase ~= "Intro") then
			eliminations = {}
			rewardBaseline = State.player:GetAttribute("LastReward")
			levelAtStart = State.player:GetAttribute("Level")
		elseif phase == "Lobby" or phase == "Waiting" or phase == "Roulette" then
			member = false
			played = false
		end
		lastPhase = phase
	end
	if phase == "Intro" or phase == "Countdown" or phase == "Round" then
		if State.isMember() then
			member = true
		end
		if State.flag("InRound") then
			played = true
		end
	end

	local want = phase == "End" and audience()
	if not want then
		close()
		return
	end
	gui.Enabled = true
	local key = Info.clean(State.str("ResultText")) .. "|" .. State.str("WinnersCsv")
	if not view or view.key ~= key then
		if view then
			view.conn:Disconnect()
			view.frame:Destroy()
			view = nil
		end
		view = open()
	else
		local data = freshReward()
		if data and data.raw ~= view.rewardRaw then
			buildRewards(view, data)
		end
	end
end

local function trackPlayer(p: Player)
	p:GetAttributeChangedSignal("InRound"):Connect(function()
		if State.phase() ~= "Round" then
			return
		end
		if p:GetAttribute("InRound") == true then
			eliminations[p.UserId] = nil -- revived
		else
			eliminations[p.UserId] = os.clock()
		end
	end)
end

function Results.start()
	gui, root = UIKit.screen("PD_Results", "Popup")
	gui.Enabled = false
	for _, p in Players:GetPlayers() do
		trackPlayer(p)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(function(p)
		if State.phase() == "Round" and p:GetAttribute("InRound") == true then
			eliminations[p.UserId] = os.clock()
		end
	end)
	State.watch(
		{ "Phase", "WinnersCsv", "ResultText", "PhaseEnd" },
		{ "InRound", "Eliminated", "Spectating", "InSolo", "LastReward" },
		sync
	)
end

return Results
