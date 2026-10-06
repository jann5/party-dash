-- Interfejs: status rundy, event, duże komunikaty, kill feed i głosowanie na event.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = require(ReplicatedStorage:WaitForChild("SpinShared"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local gameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local DARK = Color3.fromRGB(18, 18, 28)
local ORANGE = Color3.fromRGB(255, 150, 40)
local CYAN = Color3.fromRGB(90, 200, 255)

local gui = Instance.new("ScreenGui")
gui.Name = "SpinGameUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color, thickness, mode)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual,
	})
end

local function text(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.GothamBold
	if props.TextScaled == nil then
		props.TextScaled = true
	end
	return make("TextLabel", props)
end

-- Pasek statusu u góry
local top = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(340, 56),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.2,
	Parent = gui,
}, { corner(14), stroke(CYAN, 2, Enum.ApplyStrokeMode.Border) })
local statusLabel = text({ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 4), Font = Enum.Font.FredokaOne, Text = "", Parent = top })
local subLabel = text({ Size = UDim2.new(1, -20, 0, 17), Position = UDim2.fromOffset(10, 34), Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(190, 200, 220), Text = "", Parent = top })

local badge = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 68),
	Size = UDim2.fromOffset(260, 30),
	BackgroundColor3 = ORANGE,
	Visible = false,
	Parent = gui,
}, { corner(15) })
local badgeLabel = text({ Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), Font = Enum.Font.FredokaOne, TextColor3 = DARK, Text = "", Parent = badge })

-- Duży komunikat na środku
local bannerHolder = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.33),
	Size = UDim2.fromScale(0.8, 0.2),
	BackgroundTransparency = 1,
	Parent = gui,
})
local bannerScale = make("UIScale", { Parent = bannerHolder })
local bannerStroke = stroke(Color3.new(0, 0, 0), 3)
local bannerTitle = text({ Size = UDim2.fromScale(1, 0.65), Font = Enum.Font.FredokaOne, Text = "", TextTransparency = 1, Parent = bannerHolder }, nil)
bannerStroke.Parent = bannerTitle
bannerStroke.Transparency = 1
local bannerSubStroke = stroke(Color3.new(0, 0, 0), 2)
local bannerSub = text({ Position = UDim2.fromScale(0.1, 0.68), Size = UDim2.fromScale(0.8, 0.28), Font = Enum.Font.GothamBold, Text = "", TextTransparency = 1, Parent = bannerHolder })
bannerSubStroke.Parent = bannerSub
bannerSubStroke.Transparency = 1

local bannerToken = 0
local function fadeBanner(target, time)
	local info = TweenInfo.new(time)
	TweenService:Create(bannerTitle, info, { TextTransparency = target }):Play()
	TweenService:Create(bannerSub, info, { TextTransparency = target }):Play()
	TweenService:Create(bannerStroke, info, { Transparency = target }):Play()
	TweenService:Create(bannerSubStroke, info, { Transparency = target }):Play()
end

local function showBanner(title, sub, color)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color or Color3.new(1, 1, 1)
	bannerSub.Text = sub or ""
	fadeBanner(0, 0.08)
	bannerScale.Scale = 1.5
	TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.8, function()
		if bannerToken == token then
			fadeBanner(1, 0.4)
		end
	end)
end

-- Kill feed w lewym dolnym rogu
local feed = make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.fromOffset(320, 180),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local feedOrder = 0
local function pushFeed(message)
	feedOrder += 1
	local item = make("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.3,
		LayoutOrder = feedOrder,
		Parent = feed,
	}, { corner(8) })
	local label = text({
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextScaled = false,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = message,
		Parent = item,
	})
	task.delay(4, function()
		TweenService:Create(item, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		task.wait(0.45)
		item:Destroy()
	end)
	local items = {}
	for _, c in feed:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	if #items > 5 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		items[1]:Destroy()
	end
end

-- Głosowanie
local votePanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0.92, 0, 0, 170),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.15,
	Visible = false,
	Parent = gui,
}, { corner(16), stroke(ORANGE, 2, Enum.ApplyStrokeMode.Border), make("UISizeConstraint", { MaxSize = Vector2.new(620, 170) }) })
local voteTitle = text({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), Font = Enum.Font.FredokaOne, TextColor3 = ORANGE, Text = "GŁOSUJ NA EVENT!", Parent = votePanel })
local voteRow = make("Frame", { Position = UDim2.fromOffset(10, 46), Size = UDim2.new(1, -20, 1, -56), BackgroundTransparency = 1, Parent = votePanel }, {
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})

local voteButtons = {}
local myVote = nil
for i = 1, 3 do
	local btnStroke = stroke(Color3.fromRGB(70, 70, 90), 2, Enum.ApplyStrokeMode.Border)
	local btn = make("TextButton", {
		Size = UDim2.new(1 / 3, -6, 1, 0),
		BackgroundColor3 = Color3.fromRGB(38, 38, 55),
		Text = "",
		AutoButtonColor = true,
		Parent = voteRow,
	}, { corner(12), btnStroke })
	local name = text({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 26), Font = Enum.Font.FredokaOne, Text = "", Parent = btn })
	local desc = text({ Position = UDim2.fromOffset(8, 38), Size = UDim2.new(1, -16, 0, 34), Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(190, 200, 220), TextWrapped = true, Text = "", Parent = btn })
	local count = text({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -6), Size = UDim2.new(1, -16, 0, 20), Font = Enum.Font.GothamBold, TextColor3 = ORANGE, Text = "", Parent = btn })
	btn.Activated:Connect(function()
		myVote = i
		remotes.Vote:FireServer(i)
	end)
	voteButtons[i] = { button = btn, stroke = btnStroke, name = name, desc = desc, count = count }
end

local lastOptions = ""
local function refreshVote()
	local optionsStr = gameState:GetAttribute("VoteOptions") or ""
	if optionsStr ~= lastOptions then
		lastOptions = optionsStr
		myVote = nil
	end
	if optionsStr == "" then
		votePanel.Visible = false
		return
	end
	votePanel.Visible = true
	local ids = string.split(optionsStr, ",")
	local counts = string.split(gameState:GetAttribute("VoteCounts") or "", ",")
	for i, ui in voteButtons do
		local event = Shared.getEvent(ids[i])
		ui.button.Visible = event ~= nil
		if event then
			ui.name.Text = event.name
			ui.desc.Text = event.desc
			local n = tonumber(counts[i]) or 0
			ui.count.Text = n == 1 and "1 głos" or (n .. " głosów")
			ui.stroke.Color = myVote == i and ORANGE or Color3.fromRGB(70, 70, 90)
			ui.stroke.Thickness = myVote == i and 3 or 2
		end
	end
end

-- Pętla odświeżania
local function formatTime(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

RunService.Heartbeat:Connect(function()
	local phase = gameState:GetAttribute("Phase") or ""
	local timerEnd = gameState:GetAttribute("TimerEnd") or 0
	local left = timerEnd - workspace:GetServerTimeNow()
	local round = gameState:GetAttribute("Round") or 0
	statusLabel.Text = gameState:GetAttribute("Status") or ""

	if phase == "Round" then
		local alive = gameState:GetAttribute("Alive") or 0
		local who = player:GetAttribute("InRound") and "Skacz!" or "Oglądasz"
		subLabel.Text = string.format("%s · Na filarach: %d · %s", who, alive, formatTime(left))
	elseif phase == "Intermission" then
		local nextEvent = gameState:GetAttribute("NextIsEvent")
		subLabel.Text = string.format("Runda %d%s za %s", round, nextEvent and " (EVENT!)" or "", formatTime(left))
	elseif phase == "Vote" then
		subLabel.Text = "Koniec głosowania za " .. formatTime(left)
		voteTitle.Text = "GŁOSUJ NA EVENT! " .. formatTime(left)
	elseif phase == "Waiting" then
		subLabel.Text = ""
	else
		subLabel.Text = timerEnd > 0 and formatTime(left) or ""
	end

	local event = Shared.getEvent(gameState:GetAttribute("Event") or "")
	badge.Visible = event ~= nil
	if event then
		badgeLabel.Text = "⚡ EVENT: " .. event.name
	end

	refreshVote()
end)

remotes.Announce.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "big" then
		showBanner(a, b, c)
	elseif kind == "feed" then
		pushFeed(a)
	elseif kind == "focus" then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		if hrp and camera then
			local flat = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
			local out = flat.Magnitude > 0 and flat.Unit or Vector3.new(0, 0, 1)
			camera.CFrame = CFrame.lookAt(hrp.Position + out * 14 + Vector3.new(0, 6, 0), Vector3.new(0, Shared.BAR_Y, 0))
		end
	end
end)
