-- Pętla gry: przerwa -> (głosowanie na event) -> odliczanie -> runda -> zwycięzca.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = require(ReplicatedStorage:WaitForChild("SpinShared"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local hitRemote = remotes:WaitForChild("Hit")
local announceRemote = remotes:WaitForChild("Announce")
local voteRemote = remotes:WaitForChild("Vote")
local jumpFxRemote = remotes:WaitForChild("JumpFx")
local gameState = ReplicatedStorage:WaitForChild("GameState")

local arena = workspace:WaitForChild("Arena")
local bars = { arena:WaitForChild("Bar1"), arena:WaitForChild("Bar2") }
local spawnsFolder = arena:WaitForChild("Spawns")

local INTERMISSION = 8
local VOTE_TIME = 10
local ROUND_LIMIT = 120
local EVENT_EVERY = 5
local MAX_PLAYERS = 8
local NORMAL_GRAVITY = 196.2

local SPEED_NORMAL = { w = 1.0, acc = 0.035, maxW = 3.6 }
local SPEED_TURBO = { w = 2.3, acc = 0.06, maxW = 4.6 }
local SPEED_SECOND = { w = 0.8, acc = 0.03, maxW = 3.0 }
local SPEED_IDLE = { w = 0.35, acc = 0, maxW = 0.35 }

local GOLD = Color3.fromRGB(255, 205, 60)
local RED = Color3.fromRGB(255, 80, 80)
local GREEN = Color3.fromRGB(90, 255, 120)
local ORANGE = Color3.fromRGB(255, 150, 40)

local roundNumber = 0
local roundActive = false
local alive = {}

-- Kije ----------------------------------------------------------------

local barStates = {}

local function setBar(i, s)
	barStates[i] = s
	bars[i]:SetAttribute("State", Shared.encode(s))
end

local function startBar(i, params, dir, a0)
	local now = workspace:GetServerTimeNow()
	setBar(i, { a0 = a0, t0 = now, w = params.w, acc = params.acc, maxW = params.maxW, dir = dir, active = true })
end

local function stopBar(i)
	setBar(i, { a0 = 0, t0 = 0, w = 0, acc = 0, maxW = 0, dir = 1, active = false })
end

local function reverseBar(i)
	local cur = barStates[i]
	if not cur or not cur.active then
		return
	end
	local now = workspace:GetServerTimeNow()
	setBar(i, {
		a0 = Shared.angle(cur, now), t0 = now, w = Shared.speed(cur, now),
		acc = cur.acc, maxW = cur.maxW, dir = -cur.dir, active = true,
	})
end

local function idleBars()
	local cur = barStates[1]
	local a0 = cur and cur.active and Shared.angle(cur, workspace:GetServerTimeNow()) or 0
	startBar(1, SPEED_IDLE, 1, a0)
	stopBar(2)
end

-- Gracze, statystyki, seria ------------------------------------------------

local function stat(p, name)
	local ls = p:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name)
end

local function updateStreakTag(p)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	local streak = stat(p, "Seria")
	if not head or not streak then
		return
	end
	local tag = head:FindFirstChild("StreakTag")
	if streak.Value < 2 then
		if tag then
			tag:Destroy()
		end
		return
	end
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "StreakTag"
		tag.Size = UDim2.fromOffset(150, 34)
		tag.StudsOffset = Vector3.new(0, 2.8, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 200
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = ORANGE
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = tag
		tag.Parent = head
	end
	tag.Text.Text = "🔥 SERIA x" .. streak.Value
end

local function onPlayerAdded(p)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wygrane"
	wins.Parent = ls
	local streak = Instance.new("IntValue")
	streak.Name = "Seria"
	streak.Parent = ls
	ls.Parent = p
	p:SetAttribute("LastPlayed", 0)
	p:SetAttribute("InRound", false)
	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 5)
		updateStreakTag(p)
	end)
end

local function countAlive()
	local n = 0
	for _ in alive do
		n += 1
	end
	return n
end

local function eliminate(p, reason)
	if not alive[p] then
		return
	end
	alive[p] = nil
	p:SetAttribute("InRound", false)
	local streak = stat(p, "Seria")
	if streak then
		streak.Value = 0
		updateStreakTag(p)
	end
	gameState:SetAttribute("Alive", countAlive())
	print("[Spin] odpada:", p.Name, reason)
	if p.Parent then
		announceRemote:FireAllClients("feed", "💥 " .. p.DisplayName .. (reason == "hit" and " dostaje kijem!" or " spada!"))
		announceRemote:FireClient(p, "big", "ODPADASZ!", "Oglądaj z trybun — zaraz kolejna runda", RED)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end

local lastFx = {}
Players.PlayerRemoving:Connect(function(p)
	eliminate(p, "left")
	lastFx[p] = nil
end)

-- Trafienia ------------------------------------------------------------

-- Klient sam wykrywa trafienie (płynnie, bez lagów), serwer sprawdza, czy to ma sens.
hitRemote.OnServerEvent:Connect(function(p, barIndex)
	if not roundActive or not alive[p] or typeof(barIndex) ~= "number" then
		return
	end
	local s = barStates[barIndex]
	local char = p.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not s or not s.active or not hrp then
		return
	end
	local now = workspace:GetServerTimeNow()
	local d = math.abs(Shared.armDistance(Shared.angle(s, now), Shared.positionAngle(hrp.Position)))
	if d > 0.35 + Shared.speed(s, now) * 0.35 then
		return
	end
	eliminate(p, "hit")
	task.delay(3, function()
		local hum = char:FindFirstChildOfClass("Humanoid")
		if p.Character == char and hum and hum.Health > 0 then
			hum.Health = 0
		end
	end)
end)

arena:WaitForChild("Lava").Touched:Connect(function(hit)
	local hum = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = 0
	end
end)

RunService.Heartbeat:Connect(function()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp.Position.Y < 6 then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Health = 0
			end
		end
	end
	if not roundActive then
		return
	end
	for p in alive do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or hrp.Position.Y < Shared.PILLAR_TOP - 6 then
			eliminate(p, "fall")
		end
	end
end)

-- Efekty skoku: przekazujemy innym graczom, żeby widzieli salta.
jumpFxRemote.OnServerEvent:Connect(function(p, kind, trick)
	if kind ~= "Jump" and kind ~= "Land" then
		return
	end
	if kind == "Jump" and (typeof(trick) ~= "number" or trick % 1 ~= 0 or trick < 1 or trick > 4) then
		return
	end
	local now = os.clock()
	lastFx[p] = lastFx[p] or {}
	if lastFx[p][kind] and now - lastFx[p][kind] < 0.15 then
		return
	end
	lastFx[p][kind] = now
	for _, other in Players:GetPlayers() do
		if other ~= p then
			jumpFxRemote:FireClient(other, kind, p.Character, trick)
		end
	end
end)

-- Status dla UI ------------------------------------------------------------

local function setPhase(phase, text, duration)
	gameState:SetAttribute("Phase", phase)
	gameState:SetAttribute("Status", text)
	gameState:SetAttribute("TimerEnd", duration and (workspace:GetServerTimeNow() + duration) or 0)
end

-- Głosowanie ------------------------------------------------------------

local votingOpen = false
local voteOptions = {}
local votes = {}

local function publishVotes()
	local counts = {}
	for i = 1, #voteOptions do
		counts[i] = 0
	end
	for _, v in votes do
		counts[v] += 1
	end
	gameState:SetAttribute("VoteCounts", table.concat(counts, ","))
	return counts
end

voteRemote.OnServerEvent:Connect(function(p, index)
	if not votingOpen or typeof(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #voteOptions then
		return
	end
	votes[p] = index
	publishVotes()
end)

local function runVote()
	local pool = table.clone(Shared.EVENTS)
	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	voteOptions = {}
	for i = 1, math.min(3, #pool) do
		voteOptions[i] = pool[i].id
	end
	votes = {}
	votingOpen = true
	publishVotes()
	gameState:SetAttribute("VoteOptions", table.concat(voteOptions, ","))
	setPhase("Vote", "GŁOSUJ NA EVENT!", VOTE_TIME)
	task.wait(VOTE_TIME)
	votingOpen = false
	local counts = publishVotes()
	local best, winners = -1, {}
	for i, c in counts do
		if c > best then
			best, winners = c, { i }
		elseif c == best then
			table.insert(winners, i)
		end
	end
	gameState:SetAttribute("VoteOptions", "")
	return voteOptions[winners[math.random(#winners)]]
end

-- Eventy ------------------------------------------------------------

local fogBackup = nil

local function applyEvent(id)
	if id == "Fog" then
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		fogBackup = {
			atmosphere = atmosphere,
			FogStart = Lighting.FogStart,
			FogEnd = Lighting.FogEnd,
			FogColor = Lighting.FogColor,
		}
		-- Lighting.Fog działa tylko bez Atmosphere, więc chowamy ją na czas eventu.
		if atmosphere then
			atmosphere.Parent = nil
		end
		Lighting.FogColor = Color3.fromRGB(185, 190, 200)
		Lighting.FogStart = 4
		Lighting.FogEnd = 42
	elseif id == "LowGravity" then
		workspace.Gravity = 65
	end
end

local function clearEvent()
	if fogBackup then
		Lighting.FogStart = fogBackup.FogStart
		Lighting.FogEnd = fogBackup.FogEnd
		Lighting.FogColor = fogBackup.FogColor
		if fogBackup.atmosphere then
			fogBackup.atmosphere.Parent = Lighting
		end
		fogBackup = nil
	end
	workspace.Gravity = NORMAL_GRAVITY
	gameState:SetAttribute("Event", "")
end

-- Runda ------------------------------------------------------------

local function sendToStands(p)
	local char = p.Character
	if not char then
		return
	end
	local list = spawnsFolder:GetChildren()
	char:PivotTo(list[math.random(#list)].CFrame + Vector3.new(0, 4, 0))
end

local function pickParticipants()
	local list = {}
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	-- Najpierw ci, którzy najdłużej czekali.
	table.sort(list, function(a, b)
		return (a:GetAttribute("LastPlayed") or 0) < (b:GetAttribute("LastPlayed") or 0)
	end)
	local chosen = {}
	for i = 1, math.min(MAX_PLAYERS, #list) do
		chosen[i] = list[i]
	end
	return chosen
end

local function runRound(eventId)
	local participants = pickParticipants()
	if #participants == 0 then
		return
	end

	local START_ANGLE = math.pi / 8 -- między filarami
	stopBar(2)
	startBar(1, { w = 0, acc = 0, maxW = 0 }, 1, START_ANGLE)

	alive = {}
	local connections = {}
	local n = #participants
	local offset = math.random(0, Shared.PILLAR_COUNT - 1)
	for k, p in participants do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum then
			local pillar = (math.floor((k - 1) * Shared.PILLAR_COUNT / n) + offset) % Shared.PILLAR_COUNT + 1
			char:PivotTo(Shared.pillarCFrame(pillar) + Vector3.new(0, 3.2, 0))
			hrp.Anchored = true
			announceRemote:FireClient(p, "focus")
			alive[p] = true
			p:SetAttribute("LastPlayed", roundNumber)
			table.insert(connections, hum.Died:Connect(function()
				eliminate(p, "fall")
			end))
		end
	end
	local startCount = countAlive()
	gameState:SetAttribute("Alive", startCount)

	local event = eventId and Shared.getEvent(eventId)
	gameState:SetAttribute("Event", event and event.id or "")
	if event then
		announceRemote:FireAllClients("big", "EVENT: " .. event.name, event.desc, ORANGE)
		setPhase("Countdown", "EVENT: " .. event.name, 3)
		task.wait(2.5)
	end

	setPhase("Countdown", "PRZYGOTUJ SIĘ", 3)
	for i = 3, 1, -1 do
		announceRemote:FireAllClients("big", tostring(i), nil, Color3.new(1, 1, 1))
		task.wait(1)
	end

	for p in alive do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = false
		end
		p:SetAttribute("InRound", true)
	end
	applyEvent(eventId)
	local dir = math.random(2) == 1 and 1 or -1
	startBar(1, eventId == "Turbo" and SPEED_TURBO or SPEED_NORMAL, dir, START_ANGLE)
	if eventId == "TwoBars" then
		startBar(2, SPEED_SECOND, -dir, START_ANGLE + math.pi / 2)
	end
	roundActive = true
	announceRemote:FireAllClients("big", "SKACZ!", nil, GREEN)
	setPhase("Round", "RUNDA " .. roundNumber, ROUND_LIMIT)

	if eventId == "Crazy" then
		task.spawn(function()
			while roundActive do
				task.wait(math.random(25, 50) / 10)
				if not roundActive then
					break
				end
				announceRemote:FireAllClients("feed", "⚠️ Kij zmienia kierunek!")
				task.wait(0.5)
				if roundActive then
					reverseBar(1)
				end
			end
		end)
	end

	-- Solo: przetrwaj do końca czasu. W grupie: ostatni na filarze wygrywa.
	local needed = startCount >= 2 and 1 or 0
	local started = os.clock()
	while countAlive() > needed and os.clock() - started < ROUND_LIMIT do
		task.wait(0.1)
	end
	roundActive = false
	print("[Spin] koniec rundy", roundNumber, "zostało:", countAlive())

	for _, c in connections do
		c:Disconnect()
	end

	local winners = {}
	for p in alive do
		table.insert(winners, p)
	end
	for _, p in winners do
		local wins, streak = stat(p, "Wygrane"), stat(p, "Seria")
		if wins then
			wins.Value += 1
		end
		if streak then
			streak.Value += 1
		end
		updateStreakTag(p)
	end

	idleBars()
	clearEvent()
	setPhase("End", "KONIEC RUNDY", 4)
	if #winners == 1 then
		local streak = stat(winners[1], "Seria")
		announceRemote:FireAllClients("big", "🏆 " .. winners[1].DisplayName .. " WYGRYWA!",
			streak and streak.Value >= 2 and ("🔥 Seria: " .. streak.Value) or nil, GOLD)
	elseif #winners > 1 then
		local names = {}
		for _, p in winners do
			table.insert(names, p.DisplayName)
		end
		announceRemote:FireAllClients("big", "🏆 PRZETRWALI!", table.concat(names, ", "), GOLD)
	else
		announceRemote:FireAllClients("big", "NIKT NIE PRZETRWAŁ!", nil, RED)
	end
	task.wait(3)
	for _, p in winners do
		p:SetAttribute("InRound", false)
		sendToStands(p)
	end
	alive = {}
	gameState:SetAttribute("Alive", 0)
end

-- Główna pętla ------------------------------------------------------------

clearEvent()
idleBars()
gameState:SetAttribute("Round", 0)
gameState:SetAttribute("VoteOptions", "")

while true do
	if #Players:GetPlayers() == 0 then
		setPhase("Waiting", "CZEKAM NA GRACZY")
		repeat
			task.wait(1)
		until #Players:GetPlayers() > 0
	end

	roundNumber += 1
	gameState:SetAttribute("Round", roundNumber)
	local isEventRound = roundNumber % EVENT_EVERY == 0 or script:GetAttribute("EventEveryRound") == true
	gameState:SetAttribute("NextIsEvent", isEventRound)

	local eventId = nil
	local forced = script:GetAttribute("ForceEvent")
	if typeof(forced) == "string" and Shared.getEvent(forced) then
		eventId = forced
		setPhase("Intermission", "PRZERWA", 3)
		task.wait(3)
	elseif isEventRound then
		setPhase("Intermission", "PRZERWA", 3)
		task.wait(3)
		eventId = runVote()
		local event = Shared.getEvent(eventId)
		announceRemote:FireAllClients("big", "WYGRAŁ: " .. event.name, event.desc, ORANGE)
		task.wait(2)
	else
		setPhase("Intermission", "PRZERWA", INTERMISSION)
		task.wait(INTERMISSION)
	end

	local ok, err = pcall(runRound, eventId)
	if not ok then
		warn("Błąd rundy:", err)
		roundActive = false
		clearEvent()
		idleBars()
		for _, p in Players:GetPlayers() do
			p:SetAttribute("InRound", false)
			local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.Anchored = false
			end
		end
	end
end
