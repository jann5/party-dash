-- Party Dash Core: where players stand outside of a running minigame (lobby island or spectator stands),
-- plus a light watcher that rescues anyone who falls while not inside a running context.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Lobby = require(Shared.Maps.Lobby)

local Stands = require(script.Parent.Stands)
local State = require(script.Parent.State)
local Teleport = require(script.Parent.Teleport)

local Places = {}

Places.RESCUE_Y = math.min(Config.LOBBY_CENTER.Y, Config.ARENA_CENTER.Y) - Config.KILL_DEPTH

local lobbyModel: Model? = nil
local lobbySpawns: { BasePart } = {}
local nextLobbySpawn = 0

function Places.buildLobby()
	if lobbyModel then
		return
	end
	local m = Lobby.build(Config.LOBBY_CENTER)
	lobbySpawns = {}
	local folder = m:FindFirstChild("Spawns")
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(lobbySpawns, child)
			end
		end
	end
	m.Parent = workspace
	lobbyModel = m
end

function Places.destroyLobby()
	if lobbyModel then
		lobbyModel:Destroy()
		lobbyModel = nil
		lobbySpawns = {}
	end
end

function Places.hasLobby(): boolean
	return lobbyModel ~= nil
end

function Places.sendToStands(player: Player): boolean
	return Teleport.to(player, Stands.randomFloor(), false)
end

function Places.sendToLobby(player: Player): boolean
	if not lobbyModel or #lobbySpawns == 0 then
		return Places.sendToStands(player)
	end
	nextLobbySpawn = nextLobbySpawn % #lobbySpawns + 1
	local spawnPart = lobbySpawns[nextLobbySpawn]
	local layer = if #Players:GetPlayers() > #lobbySpawns then math.random(0, 2) else 0
	return Teleport.to(player, Teleport.spawnFloor(spawnPart, layer), false)
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

-- Puts a player who is NOT alive in the main round where they belong right now.
function Places.route(player: Player)
	if player:GetAttribute("InSolo") == true or State.mainCtxOwns(player) then
		return
	end
	if State.arenaActive then
		player:SetAttribute("Spectating", true)
		Places.sendToStands(player)
	else
		Places.sendToLobby(player)
	end
end

local function rescueLoop()
	while true do
		task.wait(0.2)
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("InSolo") ~= true then
				local ctx = State.ctx
				local inRunningRound = ctx ~= nil and ctx._running and ctx.isAlive(p)
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if not inRunningRound and root and root:IsA("BasePart") and root.Position.Y < Places.RESCUE_Y then
					if ctx ~= nil and ctx.isAlive(p) and State.arenaActive then
						-- Still "alive" in a frozen/ended round (e.g. fell during End): just watch from the stands.
						Places.sendToStands(p)
					else
						Places.route(p)
					end
				end
			end
		end
	end
end

function Places.init()
	Stands.build()
	Places.buildLobby()
	task.spawn(rescueLoop)
end

return Places
