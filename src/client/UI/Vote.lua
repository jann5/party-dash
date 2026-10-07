--!nonstrict
-- Vote cards (GAME_DESIGN 1.3): while you stand in the PLAY square during the Lobby, three chunky cards in the
-- Action lane let you pick the next game. Each card shows its vote count, the avatars of who voted for it and a
-- "MY PICK" ribbon on yours; a game that needs more players than are queued is locked ("2+ PLAYERS").
-- Tapping fires Core_Vote(id) (connected lazily: Core may create the remote later).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Cards = require(script.Parent.Cards)
local Info = require(script.Parent.Info)
local Remotes = require(script.Parent.Remotes)
local State = require(script.Parent.State)
local Widgets = require(script.Parent.Widgets)

local C = UIKit.Style.Colors

local Vote = {}

local CARD = Vector2.new(236, 168)
local GAP = 22
local AVATAR = 32
local MAX_AVATARS = 4

function Vote.start()
	local lane = UIKit.Lanes.get("Action")
	local holder = UIKit.new("Frame", {
		Name = "PD_Vote",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(800, 228),
		Visible = false,
		LayoutOrder = 10,
		Parent = lane,
	})
	local slide = UIKit.new("Frame", {
		Name = "Slide",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	UIKit.text(slide, {
		name = "Title",
		text = "VOTE NEXT GAME",
		size = 30,
		drop = true,
		frameSize = UDim2.new(1, 0, 0, 36),
		position = UDim2.fromScale(0.5, 0),
		anchor = Vector2.new(0.5, 0),
		zindex = 3,
	})
	local row = UIKit.new("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CARD.Y + 12),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		Parent = slide,
	})
	UIKit.list(row, Enum.FillDirection.Horizontal, GAP, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)

	local entries = {} -- id -> card entry
	local optionsKey = ""
	local localPick: string? = nil -- optimistic until the server mirrors it in Player.Vote
	local shown = false
	local schedule

	local function myPick(): string
		if localPick then
			return localPick
		end
		local v = State.player:GetAttribute("Vote")
		return typeof(v) == "string" and v or ""
	end

	local function votersFor(id: string): { number }
		local ids = {}
		for _, p in Players:GetPlayers() do
			local v = if p == State.player then myPick() else p:GetAttribute("Vote")
			if v == id then
				table.insert(ids, p.UserId)
			end
		end
		table.sort(ids, function(a, b)
			if a == State.player.UserId or b == State.player.UserId then
				return a == State.player.UserId
			end
			return a < b
		end)
		return ids
	end

	local function buildCard(id: string, order: number)
		local info = Info.minigame(id)
		local card =
			Cards.build(row, info, CARD, { className = "TextButton", layoutOrder = order, name = "Vote_" .. id })
		Cards.pressable(card)
		local face = card.face

		local bubble = UIKit.new("Frame", {
			Name = "Count",
			BackgroundColor3 = C.White,
			Size = UDim2.fromOffset(54, 54),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(10, 10),
			ZIndex = 9,
			Parent = face,
		})
		UIKit.corner(bubble, UDim.new(0.5, 0))
		UIKit.border(bubble, 3)
		local count = UIKit.text(bubble, {
			name = "Votes",
			text = "0",
			size = 34,
			font = "hype",
			color = C.Ink,
			stroke = 0,
			frameSize = UDim2.fromScale(1, 1),
			zindex = 10,
		})

		local voters = UIKit.new("Frame", {
			Name = "Voters",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -20, 0, AVATAR),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -(card.band.Size.Y.Offset + 10)),
			ZIndex = 9,
			Parent = face,
		})
		UIKit.list(voters, Enum.FillDirection.Horizontal, -8, Enum.HorizontalAlignment.Center)

		local ribbon = UIKit.new("Frame", {
			Name = "MyPick",
			Size = UDim2.fromOffset(122, 36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -22, 0, 8),
			Rotation = 12,
			ZIndex = 11,
			Visible = false,
			Parent = face,
		})
		UIKit.corner(ribbon, UDim.new(0, 9))
		UIKit.border(ribbon, 3)
		Widgets.paint(ribbon, C.Gold)
		UIKit.text(
			ribbon,
			{ name = "Text", text = "MY PICK", size = 22, frameSize = UDim2.fromScale(1, 1), zindex = 12 }
		)

		local lock = UIKit.new("Frame", {
			Name = "Locked",
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 13,
			Visible = false,
			Parent = face,
		})
		UIKit.corner(lock, UDim.new(0, 18))
		UIKit.icon(
			lock,
			"lock",
			{ size = UDim2.fromOffset(64, 64), position = UDim2.fromScale(0.5, 0.36), zindex = 14 }
		)
		local lockText = UIKit.text(lock, {
			name = "Need",
			text = "2+ PLAYERS",
			size = 26,
			frameSize = UDim2.new(1, -10, 0, 32),
			position = UDim2.fromScale(0.5, 0.74),
			anchor = Vector2.new(0.5, 0.5),
			zindex = 14,
		})

		local entry = {
			card = card,
			count = count,
			bubble = bubble,
			voters = voters,
			votersKey = "",
			ribbon = ribbon,
			lock = lock,
			lockText = lockText,
			locked = false,
			votes = -1,
			picked = false,
		}
		card.holder.Activated:Connect(function()
			if entry.locked then
				UIKit.sound("UiError")
				UIKit.shake(card.body, 5)
				return
			end
			UIKit.sound("UiClick", { pitch = 0.95 + math.random() * 0.1 })
			UIKit.punch(card.body, 1.1)
			if myPick() ~= id then
				localPick = id
				Remotes.fire("Core_Vote", id)
				schedule()
			end
		end)
		entries[id] = entry
	end

	local function rebuild(ids: { string })
		for _, entry in entries do
			entry.card.holder:Destroy()
		end
		entries = {}
		for i, id in ids do
			buildCard(id, i)
		end
	end

	local function setVoters(entry, userIds: { number })
		local key = table.concat(userIds, ",")
		if key == entry.votersKey then
			return
		end
		entry.votersKey = key
		for _, child in entry.voters:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, userId in userIds do
			if i > MAX_AVATARS then
				local more = UIKit.new("Frame", {
					Name = "More",
					BackgroundColor3 = C.PanelDeep,
					Size = UDim2.fromOffset(AVATAR + 8, AVATAR),
					LayoutOrder = i,
					ZIndex = 10,
					Parent = entry.voters,
				})
				UIKit.corner(more, UDim.new(0.5, 0))
				UIKit.border(more, 2)
				UIKit.text(more, {
					text = "+" .. (#userIds - MAX_AVATARS),
					size = 18,
					frameSize = UDim2.fromScale(1, 1),
					zindex = 11,
				})
				break
			end
			local ring = Widgets.avatar(entry.voters, userId, AVATAR, { layoutOrder = i, zindex = 10, stroke = 2 })
			UIKit.pop(ring, 0.4)
		end
	end

	local function update()
		local counts = Info.json(State.get("VoteCounts")) or {}
		local queuedCount = State.num("QueuedCount")
		local pick = myPick()
		for id, entry in entries do
			local votes = tonumber(counts[id]) or 0
			if votes ~= entry.votes then
				if entry.votes >= 0 then
					UIKit.punch(entry.bubble, 1.3)
				end
				entry.votes = votes
				entry.count.Text = tostring(votes)
			end
			local need = Info.minigame(id).minPlayers
			entry.locked = need > math.max(queuedCount, 1)
			entry.lock.Visible = entry.locked
			entry.lockText.Text = ("%d+ PLAYERS"):format(math.floor(need))
			entry.card.setGrey(entry.locked)
			local picked = pick == id and not entry.locked
			if picked ~= entry.picked then
				entry.picked = picked
				entry.ribbon.Visible = picked
				if picked then
					UIKit.pop(entry.ribbon, 0.3)
				end
			end
			entry.card.stroke.Color = picked and C.Yellow or C.Ink
			entry.card.stroke.Thickness = picked and 6 or 4
			entry.card.holder:SetAttribute("Votes", votes)
			entry.card.holder:SetAttribute("Picked", picked)
			setVoters(entry, votersFor(id))
		end
	end

	local function setShown(on: boolean)
		if on == shown then
			return
		end
		shown = on
		holder:SetAttribute("Shown", on)
		if on then
			holder.Visible = true
			slide.Position = UDim2.fromOffset(0, 280)
			UIKit.tween(slide, 0.4, { Position = UDim2.new() }, Enum.EasingStyle.Back)
			local i = 0
			for _, entry in entries do
				i += 1
				task.delay(0.06 * i, function()
					if entry.card.body.Parent then
						UIKit.pop(entry.card.body, 0.6, 0.3)
					end
				end)
			end
			Audio.ui("UiOpen")
		else
			UIKit.tween(
				slide,
				0.25,
				{ Position = UDim2.fromOffset(0, 300) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			task.delay(0.26, function()
				if not shown then
					holder.Visible = false
				end
			end)
		end
	end

	local function refresh()
		local ids = Info.csv(State.get("VoteOptions"))
		local key = table.concat(ids, ",")
		if key ~= optionsKey then
			optionsKey = key
			localPick = nil
			rebuild(ids)
		end
		local queued = State.flag("Queued")
		if not queued then
			localPick = nil
		end
		local want = State.phase() == "Lobby" and queued and not State.flag("InSolo") and #ids > 0
		if want then
			update()
		end
		setShown(want)
	end

	local pending = false
	schedule = function()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			refresh()
		end)
	end

	State.watch({ "Phase", "VoteOptions", "VoteCounts", "QueuedCount" }, { "Queued", "InSolo" }, schedule)
	State.player:GetAttributeChangedSignal("Vote"):Connect(function()
		localPick = nil -- the server's answer wins
		schedule()
	end)
	local function watchPlayer(p: Player)
		if p ~= State.player then
			p:GetAttributeChangedSignal("Vote"):Connect(schedule)
		end
	end
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(schedule)

	-- card names / icons / player minimums come from MinigameInfo: rebuild when it (re)publishes
	local function infoChanged()
		optionsKey = ""
		schedule()
	end
	local function watchInfo(folder: Instance)
		for _, cfg in folder:GetChildren() do
			cfg.AttributeChanged:Connect(infoChanged)
		end
		folder.ChildAdded:Connect(function(cfg)
			cfg.AttributeChanged:Connect(infoChanged)
			infoChanged()
		end)
		infoChanged()
	end
	local infoFolder = ReplicatedStorage:FindFirstChild("MinigameInfo")
	if infoFolder then
		watchInfo(infoFolder)
	else
		local conn
		conn = ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == "MinigameInfo" then
				conn:Disconnect()
				watchInfo(child)
			end
		end)
	end
end

return Vote
