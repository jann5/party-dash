--[[
Party Dash: KING OF THE HILL (score minigame, 90 s).
Climb the frosted cake hill and stand in the glowing golden zone on the summit: every 0.25 s inside it is
worth 0.25 points. Everybody carries a bat; a swing bonks the players in front of you off the hill.
The zone shrinks from 11 to 5 studs over the round and bat hits get stronger, so the end is a brawl.

Session state lives in create()'s closure (several copies may run at once). Map attributes for tests/UI:
	ZoneRadius (number)  current zone radius        Swings (number)  accepted swings so far
	LeaderId (number)    userId wearing the crown   InZone (string)  CSV of userIds inside the zone
	SummitY (number)     summit floor height        KillY (number)   fall height (read by Core)
Client visuals: src/client/Minigames/KingOfTheHill (keyed by the map's "KOTH_Map" tag).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Bat = require(script.Bat)
local BatTool = require(script.BatTool)
local Map = require(script.Map)
local Zone = require(script.Zone)

local SCORE_TICK = 0.25 -- seconds between zone checks
local SCORE_PER_TICK = 0.25
local SWING_TOLERANCE = 0.05 -- forgive a little network jitter on the 1 s cooldown
local HIT_DELAY = 0.08 -- lines the hit up with the start of the slash animation
local BONK_STUN = 0.7
local LEADER_FEED_GAP = 2.5
local KING_BONK_FEED_GAP = 3

local REMOTE_SWING = "KingOfTheHill_Swing" -- client -> server: "I swung" (no arguments trusted)
local REMOTE_FX = "KingOfTheHill_Fx" -- server -> client: ("hit", count) confirm for the attacker

-- Distinct round colors (bats default to these, the zone tints toward the leader's).
local PLAYER_COLORS = {
	Color3.fromRGB(255, 95, 160),
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(150, 100, 255),
	Color3.fromRGB(90, 210, 255),
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(60, 255, 230),
	Color3.fromRGB(255, 120, 220),
	Color3.fromRGB(170, 230, 60),
	Color3.fromRGB(255, 190, 120),
	Color3.fromRGB(120, 120, 255),
}

-- Create remotes when the server boots so clients never have to wait for them.
Net.event(REMOTE_SWING)
Net.event(REMOTE_FX)

local definition = {
	id = "KingOfTheHill",
	displayName = "KING OF THE HILL",
	rules = "Stand in the golden zone on top of the hill! Bonk others off!",
	keys = { "Swing", "Dash", "Jump" },
	kind = "score",
	duration = 90,
	soloCapable = false,
}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function batPowerLevel(player: Player): number
	local value = player:GetAttribute("Upg_BatPower")
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, Config.UPGRADE_MAX_LEVEL)
end

local function makeCrown(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "KOTH_Crown"
	gui.Size = UDim2.fromScale(3.4, 3.4)
	gui.StudsOffset = Vector3.new(0, 2.9, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 300

	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.55)
	halo.Size = UDim2.fromScale(0.95, 0.95)
	halo.BackgroundColor3 = Map.GOLD
	halo.BackgroundTransparency = 0.6
	halo.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = halo
	halo.Parent = gui

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1, 1)
	icon.Text = utf8.char(0x1F451) -- crown emoji
	icon.TextScaled = true
	icon.Parent = gui

	CollectionService:AddTag(gui, "KOTH_Crown")
	return gui
end

function definition.create(ctx)
	local refs = Map.build(ctx.center)
	local map = refs.map
	CollectionService:AddTag(map, "KOTH_Map")
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "Fx"
	fxFolder.Parent = map

	local swingRemote = Net.event(REMOTE_SWING)
	local fxRemote = Net.event(REMOTE_FX)

	local running = false
	local swings = 0
	local accumulator = 0
	local bats: { [Player]: Tool } = {}
	local lastSwing: { [Player]: number } = {}
	local colors: { [Player]: Color3 } = {}
	local leader: Player? = nil
	local crown: BillboardGui? = nil
	local lastLeaderFeed = -math.huge
	local lastKingBonkFeed = -math.huge
	local zoneColor = Map.GOLD
	local announcedFinal = false

	for i, p in ctx.allPlayers() do
		colors[p] = PLAYER_COLORS[(i - 1) % #PLAYER_COLORS + 1]
	end

	-- Crown ----------------------------------------------------------------------------------------
	local function removeCrown()
		if crown then
			crown:Destroy()
			crown = nil
		end
	end

	local function placeCrown()
		if not leader then
			removeCrown()
			return
		end
		local character = leader.Character
		local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
		if not head or not head:IsA("BasePart") then
			return
		end
		if crown and crown.Parent == head then
			return
		end
		removeCrown()
		local gui = makeCrown()
		gui.Adornee = head
		gui.Parent = head
		crown = gui
	end

	local function tintZone()
		local target = if leader and colors[leader] then Map.GOLD:Lerp(colors[leader], 0.45) else Map.GOLD
		if target == zoneColor then
			return
		end
		zoneColor = target
		local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad)
		TweenService:Create(refs.fill, info, { Color = target }):Play()
		TweenService:Create(refs.beam, info, { Color = target }):Play()
		TweenService:Create(refs.light, info, { Color = target }):Play()
	end

	local function updateLeader()
		local best: Player? = nil
		local bestScore = 0
		-- The current king keeps the crown on ties, so it never flickers.
		if leader and ctx.isAlive(leader) and leader.Parent == Players then
			best = leader
			bestScore = ctx.getScore(leader)
		end
		for _, p in ctx.players() do
			local s = ctx.getScore(p)
			if s > bestScore + 1e-6 then
				best = p
				bestScore = s
			end
		end
		if bestScore <= 0 then
			best = nil
		end
		if best ~= leader then
			leader = best
			map:SetAttribute("LeaderId", if best then best.UserId else 0)
			removeCrown()
			local now = os.clock()
			if best and now - lastLeaderFeed >= LEADER_FEED_GAP then
				lastLeaderFeed = now
				ctx.feed(("%s is the new King!"):format(best.DisplayName))
			end
			tintZone()
		end
		placeCrown() -- also re-attaches after the king respawns
	end

	-- Scoring --------------------------------------------------------------------------------------
	local function scoreTick()
		local elapsed = ctx.elapsed()
		local radius = Zone.radiusAt(elapsed)
		Map.setZoneRadius(refs, radius)

		local inside = {}
		for _, p in ctx.players() do
			local root = rootOf(p)
			if root and Zone.contains(refs.zoneCenter, radius, refs.summitY, root.Position) then
				ctx.addScore(p, SCORE_PER_TICK)
				table.insert(inside, tostring(p.UserId))
			end
		end
		map:SetAttribute("InZone", table.concat(inside, ","))
		updateLeader()

		if not announcedFinal and elapsed >= definition.duration - 30 then
			announcedFinal = true
			ctx.announce("30 SECONDS LEFT!", "The zone is shrinking!", Map.GOLD)
		end
	end

	-- Bat ------------------------------------------------------------------------------------------
	local function resolveHits(attacker: Player)
		if not running or not ctx.isAlive(attacker) then
			return
		end
		local root = rootOf(attacker)
		if not root then
			return
		end
		local attackerCFrame = root.CFrame
		local candidates = {}
		for _, other in ctx.players() do
			if other ~= attacker then
				local r = rootOf(other)
				if r then
					table.insert(candidates, { id = other, position = r.Position })
				end
			end
		end
		local targets = Bat.findTargets(attackerCFrame, candidates)
		if #targets == 0 then
			return
		end
		local power = Bat.power(batPowerLevel(attacker), ctx.elapsed(), Config.UPGRADES.BatPower.perLevel)
		for _, target in targets do
			local r = rootOf(target)
			if r then
				ctx.knockback(target, Bat.direction(attackerCFrame, r.Position), power, BONK_STUN)
				BatTool.bonkFx(fxFolder, r.Position + Vector3.new(0, 1, 0), colors[attacker] or Map.GOLD)
				local now = os.clock()
				if target == leader and now - lastKingBonkFeed >= KING_BONK_FEED_GAP then
					lastKingBonkFeed = now
					ctx.feed(("%s bonked the King!"):format(attacker.DisplayName))
				end
			end
		end
		if attacker.Parent == Players then
			fxRemote:FireClient(attacker, "hit", #targets)
		end
	end

	-- Single entry point for both Tool.Activated (server) and the swing remote; the cooldown dedupes.
	local function trySwing(player: Player)
		local tool = bats[player]
		if not running or not tool or not ctx.isAlive(player) then
			return
		end
		local character = player.Character
		if not character or tool.Parent ~= character then
			return -- must be holding it
		end
		local now = os.clock()
		if now - (lastSwing[player] or -math.huge) < Bat.COOLDOWN - SWING_TOLERANCE then
			return
		end
		lastSwing[player] = now
		swings += 1
		map:SetAttribute("Swings", swings)
		tool:SetAttribute("LastSwing", workspace:GetServerTimeNow())
		BatTool.playSwing(tool)
		task.delay(HIT_DELAY, resolveHits, player)
	end

	local function findBackpack(player: Player): Backpack?
		return player:FindFirstChildOfClass("Backpack")
	end

	local function equip(player: Player, tool: Tool)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and tool.Parent ~= character then
			humanoid:EquipTool(tool)
		end
	end

	local function giveBat(player: Player)
		if not running or not ctx.isAlive(player) then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local backpack = findBackpack(player)
		if not humanoid or humanoid.Health <= 0 or not backpack then
			return
		end
		local old = bats[player]
		if old and (old.Parent == character or old.Parent == backpack) then
			equip(player, old)
			return
		end
		if old then
			old:Destroy()
		end
		local tool = BatTool.build(player, colors[player] or Map.GOLD, map)
		bats[player] = tool
		tool.Activated:Connect(function()
			trySwing(player)
		end)
		-- Keep the bat in hand: if it gets unequipped (hotbar key), put it straight back.
		tool.Unequipped:Connect(function()
			task.defer(function()
				if running and bats[player] == tool and tool.Parent and tool.Parent:IsA("Backpack") then
					equip(player, tool)
				end
			end)
		end)
		tool.Parent = backpack
		equip(player, tool)
	end

	local function removeBats()
		for _, tool in bats do
			tool:Destroy()
		end
		table.clear(bats)
	end

	-- A respawned character (death) gets a fresh backpack: hand out a new bat.
	for _, p in ctx.allPlayers() do
		ctx.trove:connect(p.CharacterAdded, function(character: Model)
			if not running then
				return
			end
			task.spawn(function()
				character:WaitForChild("Humanoid", 5)
				task.wait(0.2) -- let Core place the character first
				if running and p.Character == character then
					giveBat(p)
				end
			end)
		end)
	end
	ctx.trove:connect(Players.PlayerRemoving, function(p: Player)
		local tool = bats[p]
		if tool then
			tool:Destroy()
			bats[p] = nil
		end
		lastSwing[p] = nil
		if leader == p then
			leader = nil
			removeCrown()
			map:SetAttribute("LeaderId", 0)
		end
	end)
	ctx.trove:connect(swingRemote.OnServerEvent, function(player: Player)
		-- No arguments are read: the server decides everything from its own state.
		if bats[player] then
			trySwing(player)
		end
	end)

	local session = { map = map }

	function session.start(_self)
		running = true
		for _, p in ctx.players() do
			giveBat(p)
		end
		ctx.trove:connect(RunService.Heartbeat, function(dt: number)
			if not running then
				return
			end
			accumulator += dt
			-- Fixed-rate ticks: exactly 4 checks per second regardless of frame rate.
			local steps = 0
			while accumulator >= SCORE_TICK and steps < 8 do
				accumulator -= SCORE_TICK
				steps += 1
				scoreTick()
			end
			-- Retry players who are missing a bat (e.g. character loaded late).
			for _, p in ctx.players() do
				local tool = bats[p]
				if not tool or not tool.Parent then
					giveBat(p)
				end
			end
		end)
	end

	function session.stop(_self)
		running = false
		removeBats()
		removeCrown()
		leader = nil
		map:SetAttribute("InZone", "")
	end

	return session
end

return definition
