--[[
Party Dash Core: the permanent lobby and where players stand outside a running round.

	Places.init()                 -- builds workspace.Lobby ONCE (Shared.Maps.Lobby) and starts the water rescue loop
	Places.ensureLobby(): Model   -- the lobby (rebuilt only if it went missing)
	Places.hasLobby(): boolean
	Places.sendToLobby(player)    -- puts the character on a lobby spawn, facing the PLAY square; false if no character
	Places.sendToStands(player)   -- v2 has no stands (spectating is camera-only): same as sendToLobby
	Places.route(player)          -- places a new character: lobby, unless the main round owns it (or it is in Solo)
	Places.setWatchFocus(player, watching)  -- streams the arena to a spectator (camera-only spectating)
	Places.playZoneTop(): CFrame  -- top-center of the PLAY pad (the join box sits on it, Config.JOIN_ZONE_SIZE)
	Places.audience(): {Player}   -- everyone in the main game (not in a Solo run)
	Places.roundAudience()        -- the round's members: participants + Eliminated + Spectating players
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Art)
local Config = require(Shared.Config)
local Lobby = require(Shared.Maps.Lobby)

local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Teleport = require(script.Parent.Teleport)

local Places = {}

Places.RESCUE_Y = Config.SEA_LEVEL - 2 -- below this, anyone outside a running round is pulled out of the water
Places.RESCUE_INTERVAL = 0.2
Places.DEFAULT_ZONE_OFFSET = Vector3.new(0, 0, 36) -- PLAY pad position when the lobby model has no PlayZone part

local SPAWN_LOCATION_NAME = "PD_LobbySpawn"

local lobbyModel: Model? = nil
local lobbySpawns: { BasePart } = {}
local nextLobbySpawn = 0
local warned: { [string]: boolean } = {}

local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn("[Core] " .. message)
	end
end

local function readSpawns(model: Model): { BasePart }
	local list = {}
	local folder = model:FindFirstChild("Spawns")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
	end
	if #list == 0 then
		warnOnce("the lobby has no Spawns; using points around LOBBY_CENTER")
	end
	return list
end

-- Last resort when Lobby.build errors: a plain grass pad, so players always have somewhere to stand.
local function emergencyLobby(): Model
	local model = Instance.new("Model")
	Art.block(
		model,
		"Floor",
		Vector3.new(96, 2, 96),
		CFrame.new(Config.LOBBY_CENTER - Vector3.new(0, 1, 0)),
		"grass_top"
	)
	return model
end

-- A hidden SpawnLocation (inside the lobby model) on the first lobby spawn, so a new or respawned character never
-- appears at the world origin (the arena) before Places.route moves it.
local function addSpawnLocation(model: Model, floor: CFrame)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = SPAWN_LOCATION_NAME
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Size = Vector3.new(6, 1, 6)
	spawnLocation.CFrame = floor - Vector3.new(0, 0.5, 0)
	spawnLocation.Transparency = 1
	spawnLocation.CanCollide = false
	spawnLocation.CanQuery = false
	spawnLocation.CanTouch = false
	spawnLocation.CastShadow = false
	spawnLocation.Parent = model
end

function Places.ensureLobby(): Model
	local current = lobbyModel
	if current and current.Parent == workspace then
		return current
	end
	if current then
		warn("[Core] the lobby went missing; rebuilding it")
		current:Destroy()
	else
		-- A Lobby saved into the place file by an edit-mode build would be a second copy.
		for _, child in workspace:GetChildren() do
			if child.Name == "Lobby" and child:IsA("Model") then
				child:Destroy()
			end
		end
	end
	local ok, built = pcall(Lobby.build, Config.LOBBY_CENTER)
	local model: Model
	if ok and typeof(built) == "Instance" and built:IsA("Model") then
		model = built
	else
		warn("[Core] Lobby.build failed, using an emergency pad: " .. tostring(built))
		model = emergencyLobby()
	end
	model.Name = "Lobby"
	if not model.PrimaryPart then
		model.WorldPivot = CFrame.new(Config.LOBBY_CENTER)
	end
	model.Parent = workspace
	lobbyModel = model
	lobbySpawns = readSpawns(model)
	nextLobbySpawn = 0
	addSpawnLocation(model, Places.lobbyFloor(1, 0))
	return model
end

function Places.hasLobby(): boolean
	return lobbyModel ~= nil and lobbyModel.Parent == workspace
end

function Places.playZoneTop(): CFrame
	local zone = lobbyModel and lobbyModel:FindFirstChild("PlayZone")
	if zone and zone:IsA("BasePart") then
		return zone.CFrame * CFrame.new(0, zone.Size.Y / 2, 0)
	end
	warnOnce("the lobby has no PlayZone part; using a default 30x30 zone")
	return CFrame.new(Config.LOBBY_CENTER + Places.DEFAULT_ZONE_OFFSET)
end

-- Floor CFrame of lobby spawn `index` (players stacked on one spawn get a ring offset by `layer`).
function Places.lobbyFloor(index: number, layer: number): CFrame
	local zone = Places.playZoneTop().Position
	local n = #lobbySpawns
	if n > 0 then
		local part = lobbySpawns[(index - 1) % n + 1]
		if part.Parent then
			return Teleport.spawnFloor(part, layer, zone)
		end
	end
	-- Fallback: a short row south of the lobby center, facing the PLAY square.
	local slot = (index - 1) % 8
	local pos = Config.LOBBY_CENTER + Vector3.new((slot - 3.5) * 5, 0, -24 - layer * 4)
	return Teleport.facing(pos, zone)
end

function Places.sendToLobby(player: Player): boolean
	Places.ensureLobby()
	local count = math.max(#lobbySpawns, 8)
	nextLobbySpawn = nextLobbySpawn % count + 1
	local layer = if #Players:GetPlayers() > count then math.random(0, 2) else 0
	return Teleport.to(player, Places.lobbyFloor(nextLobbySpawn, layer), false)
end

-- v2 builds no spectator stands; kept for callers from v1 (Solo): spectating is camera-only.
function Places.sendToStands(player: Player): boolean
	return Places.sendToLobby(player)
end

-- Everyone in the main game (players in a private Solo run are excluded).
function Places.audience(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InSolo") ~= true then
			table.insert(list, p)
		end
	end
	return list
end

-- Who sees the round's banners and effects: participants, knocked-out players and watchers.
function Places.roundAudience(): { Player }
	local list = {}
	local seen = {}
	local ctx = State.ctx
	if ctx then
		for _, p in ctx.allPlayers() do
			if p.Parent == Players and p:GetAttribute("InSolo") ~= true then
				seen[p] = true
				table.insert(list, p)
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if
			not seen[p]
			and p:GetAttribute("InSolo") ~= true
			and (p:GetAttribute("Eliminated") == true or p:GetAttribute("Spectating") == true)
		then
			table.insert(list, p)
		end
	end
	return list
end

-- Spectating is camera-only (the character stays in the lobby). With instance streaming on, the watcher's
-- replication focus moves to the arena so the round streams in; off (or no round) = back to their character.
function Places.setWatchFocus(player: Player, watching: boolean)
	local ctx = State.ctx
	local map = watching and ctx and ctx.map
	player.ReplicationFocus = if map then map:FindFirstChildWhichIsA("BasePart", true) else nil
end

-- Puts a new character where it belongs: the lobby, unless the main round or a Solo run places it.
function Places.route(player: Player)
	if player:GetAttribute("InSolo") == true or State.mainCtxOwns(player) then
		return
	end
	Places.sendToLobby(player)
end

-- Anyone outside a running round who drops into the sea (lobby water, wandering off) goes back to a lobby spawn.
-- Alive participants of a running round are never touched here: their Context eliminates them.
local function rescueStep()
	Places.ensureLobby()
	local ctx = State.ctx
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InSolo") ~= true and not State.deathBeat[p] then
			local parts = Teleport.parts(p)
			local root = parts and parts.root
			if root and not root.Anchored and root.Position.Y < Places.RESCUE_Y then
				if ctx and ctx:_wantsCharacter(p) then
					if not ctx:_isRunning() then
						ctx:_respawnNow(p) -- Intro/Countdown: back onto the map, still frozen
					end
				else
					local splashAt = Vector3.new(root.Position.X, Config.SEA_LEVEL, root.Position.Z)
					Fx.send("splash", splashAt, Places.audience())
					Places.sendToLobby(p)
				end
			end
		end
	end
end

function Places.init()
	Places.ensureLobby()
	task.spawn(function()
		while true do
			task.wait(Places.RESCUE_INTERVAL)
			local ok, err = pcall(rescueStep)
			if not ok then
				warnOnce("rescue loop error: " .. tostring(err))
			end
		end
	end)
end

return Places
