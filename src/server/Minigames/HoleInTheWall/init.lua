--[[
Party Dash minigame: HOLE IN THE WALL (survival).

Bright walls with 1-3 color-coded holes slide across a 64 x 64 platform. Run through the green doorways,
JUMP through the yellow windows and SLIDE through the cyan crawl gaps. Walls are not physical: when a wall
plane overtakes a player, Pass.check decides; a miss means a big ctx.knockback in the wall's travel
direction. Walls get faster, closer together, with fewer/narrower/trickier holes, and come from more sides.

Server owns the truth (wall timing is analytic: plane offset = START + speed * (serverTime - enter)); each wall
is replicated as a Configuration in map.Walls, which the client turns into smooth visuals
(src/client/Minigames/HoleInTheWall). Map test attributes: WallsSpawned, Hits, WallSpeed, ActiveDirections.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)
local Trove = require(Shared.Util.Trove)

local Arena = require(script.Arena)
local Pass = require(script.Pass)
local Patterns = require(script.Patterns)

local FX_REMOTE = "HoleInTheWall_Fx"
local FIRST_WALL_DELAY = 1
local ONBOARDING_GAP = 4.5 -- the three tutorial walls never come faster than this
local HIT_COOLDOWN = 0.3 -- one shove per player per this many seconds (overlapping walls)
local KNOCKBACK_LIFT = 0.22
local KNOCKBACK_STUN = 0.7
local SPEED_ATTR_INTERVAL = 0.5
local MAX_CROSS_STEP = 12 -- studs of relative motion per frame that still count as walking into a wall

type Wall = {
	name: string,
	config: Configuration,
	dir: Vector3, -- travel direction (unit, flat)
	right: Vector3, -- wall-local +X
	enter: number, -- server time when it starts moving
	speed: number,
	power: number,
	holes: { Patterns.Hole },
	rel: { [Player]: number }, -- last signed distance of each player in front of the wall plane
}

local definition = {
	id = "HoleInTheWall",
	displayName = "HOLE IN THE WALL",
	rules = "Find the hole in the wall! Jump or slide if you must!",
	keys = { "Dash", "Jump", "Slide" },
	kind = "survival",
	soloCapable = true,
}

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zAxis
end

function definition.create(ctx)
	local rng = Random.new()
	local origin = ctx.center.Position
	local map = Arena.build(ctx.center)
	local wallsFolder = map:FindFirstChild("Walls") :: Folder
	local fxRemote = Net.event(FX_REMOTE)
	local accent = Theme.MinigameColors.HoleInTheWall

	-- Travel directions, in the order they unlock: a random first side, then the opposite one
	-- (walls from behind!), then the two perpendicular sides.
	local look, right = flat(ctx.center.LookVector), flat(ctx.center.RightVector)
	local sides = { look, -look, right, -right }
	local first = rng:NextInteger(1, 4)
	local opposite = if first % 2 == 1 then first + 1 else first - 1
	local order = { first, opposite }
	local perpendicular = if first <= 2 then { 3, 4 } else { 1, 2 }
	if rng:NextNumber() < 0.5 then
		perpendicular[1], perpendicular[2] = perpendicular[2], perpendicular[1]
	end
	table.insert(order, perpendicular[1])
	table.insert(order, perpendicular[2])

	map:SetAttribute("WallsSpawned", 0)
	map:SetAttribute("Hits", 0)
	map:SetAttribute("WallSpeed", Patterns.tuning(1).speed)
	map:SetAttribute("ActiveDirections", 0)

	local runtime = Trove.new() -- loops/connections owned by start(); cleaned in stop()
	ctx.trove:add(runtime)
	local running = false
	local walls: { [Wall]: boolean } = {}
	local wallCount = 0
	local usedSides: { [number]: boolean } = {}
	local usedCount = 0
	local unlocked = 1
	local lastSide = 0
	local lastHit: { [Player]: number } = {}
	local lastSpeedAttr = 0

	local function pickSide(available: number): number
		if available <= 1 then
			return order[1]
		end
		-- Never the same side twice in a row once there is a choice.
		local choices = {}
		for k = 1, available do
			if order[k] ~= lastSide then
				table.insert(choices, order[k])
			end
		end
		return choices[rng:NextInteger(1, #choices)]
	end

	local function spawnWall()
		wallCount += 1
		local tuning = Patterns.tuning(ctx.intensity())

		if tuning.directions > unlocked then
			if wallCount > 1 then
				ctx.announce(string.format("WALLS FROM %d SIDES!", tuning.directions), "Watch your back!", accent)
			end
			unlocked = tuning.directions
		end
		local side = pickSide(unlocked)
		lastSide = side
		if not usedSides[side] then
			usedSides[side] = true
			usedCount += 1
		end

		local dir = sides[side]
		local holes = Patterns.makeHoles(rng, tuning, wallCount)
		local now = workspace:GetServerTimeNow()
		local wall: Wall = {
			name = "Wall" .. wallCount,
			config = Instance.new("Configuration"),
			dir = dir,
			right = dir:Cross(Vector3.yAxis).Unit,
			enter = now + Patterns.TELEGRAPH,
			speed = tuning.speed,
			power = tuning.power,
			holes = holes,
			rel = {},
		}

		-- Everything the client needs to draw and move this wall in sync with the server.
		local config = wall.config
		config.Name = wall.name
		config:SetAttribute("Index", wallCount)
		config:SetAttribute("Origin", origin)
		config:SetAttribute("Dir", dir)
		config:SetAttribute("Telegraph", now)
		config:SetAttribute("Enter", wall.enter)
		config:SetAttribute("Speed", wall.speed)
		config:SetAttribute("Start", Patterns.START_DIST)
		config:SetAttribute("Finish", Patterns.FINISH_DIST)
		config:SetAttribute("Width", Patterns.WALL_WIDTH)
		config:SetAttribute("Height", Patterns.WALL_HEIGHT)
		config:SetAttribute("Thick", Patterns.WALL_THICK)
		config:SetAttribute("Color", Patterns.WALL_COLORS[(wallCount - 1) % #Patterns.WALL_COLORS + 1])
		config:SetAttribute("Holes", Patterns.encodeHoles(holes))
		config.Parent = wallsFolder
		walls[wall] = true

		map:SetAttribute("WallsSpawned", wallCount)
		map:SetAttribute("WallSpeed", tuning.speed)
		map:SetAttribute("ActiveDirections", usedCount)
	end

	local function removeWall(wall: Wall)
		walls[wall] = nil
		wall.config:Destroy()
	end

	-- The wall plane just overtook this player: through a hole, or shoved off the platform.
	local function resolve(wall: Wall, player: Player, root: BasePart, localX: number, height: number, now: number)
		local sliding = root.Parent ~= nil and (root.Parent :: Instance):GetAttribute("Sliding") == true
		local hitPos = root.Position
		for _, hole in wall.holes do
			if Pass.check(hole.kind, hole.minX, hole.maxX, localX, height, sliding) then
				fxRemote:FireAllClients("pass", map, wall.name, hitPos, Patterns.HOLES[hole.kind].code, player.UserId)
				return
			end
		end
		if now - (lastHit[player] or -math.huge) < HIT_COOLDOWN then
			return
		end
		lastHit[player] = now
		map:SetAttribute("Hits", (map:GetAttribute("Hits") or 0) + 1)
		ctx.knockback(player, wall.dir + Vector3.new(0, KNOCKBACK_LIFT, 0), wall.power, KNOCKBACK_STUN)
		fxRemote:FireAllClients("hit", map, wall.name, hitPos, "", player.UserId)
	end

	local function step()
		if not running then
			return
		end
		local now = workspace:GetServerTimeNow()
		if now - lastSpeedAttr >= SPEED_ATTR_INTERVAL then
			lastSpeedAttr = now
			map:SetAttribute("WallSpeed", Patterns.tuning(ctx.intensity()).speed)
		end

		local alive = ctx.players()
		local halfWidth = Patterns.WALL_WIDTH / 2 + 1
		for wall in walls do
			if now >= wall.enter then
				local plane = Patterns.START_DIST + wall.speed * (now - wall.enter)
				if plane > Patterns.FINISH_DIST then
					removeWall(wall)
				else
					for _, player in alive do
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if root then
							local offset = root.Position - origin
							local rel = offset:Dot(wall.dir) - plane
							local prev = wall.rel[player]
							wall.rel[player] = rel
							local localX = offset:Dot(wall.right)
							local height = offset.Y
							if
								prev ~= nil
								and prev > 0
								and rel <= 0
								and prev - rel < MAX_CROSS_STEP -- a bigger jump is a respawn/teleport, not a crossing
								and math.abs(localX) <= halfWidth
								and height > -3 -- already falling below the platform: nothing to hit
								and height < Patterns.WALL_HEIGHT + 0.5 -- sailing over the top
							then
								resolve(wall, player, root, localX, height, now)
							end
						end
					end
				end
			end
		end
	end

	local session = { map = map }

	function session.start(_self)
		running = true
		runtime:connect(RunService.Heartbeat, step)
		runtime:add(task.spawn(function()
			task.wait(FIRST_WALL_DELAY)
			while running do
				spawnWall()
				local gap = Patterns.tuning(ctx.intensity()).gap
				if wallCount <= 3 then
					gap = math.max(gap, ONBOARDING_GAP)
				end
				task.wait(gap)
			end
		end))
	end

	function session.stop(_self)
		running = false
		runtime:clean()
		-- Removing the configs makes every client sink its walls; nothing keeps moving during results.
		for wall in walls do
			removeWall(wall)
		end
		table.clear(lastHit)
	end

	ctx.trove:connect(Players.PlayerRemoving, function(player: Player)
		lastHit[player] = nil
		for wall in walls do
			wall.rel[player] = nil
		end
	end)

	return session
end

return definition
