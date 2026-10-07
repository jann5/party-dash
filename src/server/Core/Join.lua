--[[
Party Dash Core: the PLAY square (brief #26). Standing in it = queued for the next round.

	Join.start()                  -- 0.2 s spatial check (no Touched events: robust on mobile and for client physics)
	Join.count(): number          -- players currently queued (also GameState QueuedCount)
	Join.onChanged(fn(player, queued))

A player is queued while their HumanoidRootPart is inside the box Config.JOIN_ZONE_SIZE sitting on the PlayZone pad
(|x|, |z| <= half size, 0..height above the pad top), they are not playing the main round and not in a Solo run.
Debug_AutoQueue (Studio) queues everyone who is not playing.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local GameState = require(Shared.GameState)

local Debug = require(script.Parent.Debug)
local Places = require(script.Parent.Places)
local Teleport = require(script.Parent.Teleport)

local Join = {}

Join.INTERVAL = 0.2
Join.FLOOR_TOLERANCE = 1 -- studs below the pad top still counted (crouched/sliding roots)

local listeners: { (Player, boolean) -> () } = {}
local count = 0
local started = false

function Join.onChanged(fn: (Player, boolean) -> ())
	table.insert(listeners, fn)
end

function Join.count(): number
	return count
end

local function inBox(zoneTop: CFrame, position: Vector3): boolean
	local size = Config.JOIN_ZONE_SIZE
	local rel = zoneTop:PointToObjectSpace(position)
	return math.abs(rel.X) <= size.X / 2
		and math.abs(rel.Z) <= size.Z / 2
		and rel.Y >= -Join.FLOOR_TOLERANCE
		and rel.Y <= size.Y
end

local function shouldQueue(player: Player, zoneTop: CFrame, auto: boolean): boolean
	if player:GetAttribute("InSolo") == true or player:GetAttribute("InRound") == true then
		return false
	end
	if auto then
		return true
	end
	local parts = Teleport.parts(player)
	return parts ~= nil and inBox(zoneTop, parts.root.Position)
end

local function step()
	local zoneTop = Places.playZoneTop()
	local auto = Debug.autoQueue()
	local n = 0
	for _, p in Players:GetPlayers() do
		local queued = shouldQueue(p, zoneTop, auto)
		if queued then
			n += 1
		end
		if (p:GetAttribute("Queued") == true) ~= queued then
			p:SetAttribute("Queued", queued)
			for _, fn in listeners do
				task.spawn(fn, p, queued)
			end
		end
	end
	if n ~= count then
		count = n
		GameState.write("QueuedCount", n)
	end
end

function Join.start()
	if started then
		return
	end
	started = true
	GameState.write("QueuedCount", 0)
	task.spawn(function()
		local reported = false
		while true do
			task.wait(Join.INTERVAL)
			local ok, err = pcall(step)
			if not ok and not reported then
				reported = true
				warn("[Core] join square check failed: " .. tostring(err))
			end
		end
	end)
end

return Join
