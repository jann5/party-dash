--!strict
--[[
Party Dash minigame: LASER TRACER (survival).
Jump the low (red) lasers, slide under the high (cyan) ones. Sweeping lasers rotate around the central hub,
straight lasers cross the platform from any side, and everything speeds up forever with ctx.intensity().
A laser never kills: it knocks you back (ctx.knockback); you are out when you fall off.

Files
	Arena.lua      map builder
	Lasers.lua     the laser Models of one session (state attribute, telegraph previews, lifecycle)
	Director.lua   escalation: what spawns when
	Hit.lua        pure vertical hit rule (low = jump it, high = slide under it)
	MotionRef.lua  the shared motion math (src/client/Minigames/LaserTracer/Motion.lua)

Map attributes (for clients and tests): "Hits" (total hits), "LaserSpeed" (rad/s of the sweeps),
"ActiveLasers" (live beams), "Center" (CFrame), "PowerDown" (server time the round ended, 0 = running).

Session-safe: all state lives in create()'s closure; everything is positioned relative to ctx.center.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Theme = require(Shared:WaitForChild("Theme"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local Arena = require(script.Arena)
local Director = require(script.Director)
local Hit = require(script.Hit)
local Lasers = require(script.Lasers)
local Motion = require(script.MotionRef)

local HIT_COOLDOWN = 1 -- per player
local SLIDE_GRACE = 0.15 -- a slide that ended this recently still counts (replication jitter)
-- Knockback: a hit is a big, readable launch (~40 studs of flight at the start) that you can survive near
-- the middle but not near the edge; it grows with intensity until late hits throw anyone off the map.
local KNOCK_POWER = 95
local KNOCK_PER_INTENSITY = 15
local KNOCK_MAX = 165
local KNOCK_STUN = 0.6
local OUTWARD = 0.3 -- share of "away from the center" mixed into the beam's push direction
local MAX_LAG = 0.2

-- Fired to everyone; clients draw the zap on the hit player (ignoring maps they cannot see).
local zapRemote = Net.unreliable("LaserTracer_Zap")

local definition = {
	id = "LaserTracer",
	displayName = "LASER TRACER",
	rules = "Jump the low lasers, slide under the high ones!",
	keys = { "Jump", "Slide", "Dash" },
	kind = "survival",
	soloCapable = true,
}

-- How far behind the server clock this player's replicated position is (seconds). The beam is checked
-- where the player SAW it, so a jump that cleared it on their screen also clears it here.
local function lagOf(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	if ok and type(ping) == "number" and ping == ping then
		return math.clamp(ping * 0.5 + 0.03, 0, MAX_LAG)
	end
	return 0.05
end

function definition.create(ctx: any)
	local center: CFrame = ctx.center
	local floorY = center.Position.Y
	local map = Arena.build(center)
	local rng = Random.new()
	local set = Lasers.new(map, center)
	local director = Director.new(set, map, rng, function(text: string, sub: string?)
		ctx.announce(text, sub, Theme.MinigameColors.LaserTracer)
	end)
	local trove = Trove.new()
	ctx.trove:add(trove)

	local hits = 0
	local lastHit: { [Player]: number } = {}
	local slideSeen: { [Player]: number } = {}
	local lastStep: number? = nil
	local liveCount = -1

	local function onHit(player: Player, root: BasePart, rel: Vector3, kind: string, mx: number, mz: number)
		hits += 1
		map:SetAttribute("Hits", hits)
		-- Pushed the way the beam travels, plus a little outward.
		local flat = Vector3.new(rel.X, 0, rel.Z)
		local outward = if flat.Magnitude > 0.5 then flat.Unit else Vector3.zero
		local push = Vector3.new(mx, 0, mz) + outward * OUTWARD
		if push.Magnitude < 1e-3 then
			push = Vector3.new(mx, 0, mz)
		end
		local power = math.min(KNOCK_POWER + KNOCK_PER_INTENSITY * (ctx.intensity() - 1), KNOCK_MAX)
		ctx.knockback(player, center:VectorToWorldSpace(push), power, KNOCK_STUN)
		zapRemote:FireAllClients(map, player, root.Position, kind)
	end

	local function checkPlayers(now: number, dt: number)
		for _, player in ctx.players() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (character and root and root:IsA("BasePart") and humanoid) then
				continue
			end
			if humanoid.Health <= 0 or root.Anchored then
				continue
			end
			if character:GetAttribute("Sliding") == true then
				slideSeen[player] = now
			end
			if now - (lastHit[player] or -math.huge) < HIT_COOLDOWN then
				continue
			end
			local sliding = now - (slideSeen[player] or -math.huge) <= SLIDE_GRACE
			local rel = center:PointToObjectSpace(root.Position)
			local tb = now - lagOf(player)
			local ta = tb - dt
			for _, laser in set.list do
				local st = laser.state
				if tb >= st.tOn and ta <= st.tOff then
					local crossed, inside, mx, mz =
						Motion.crossed(st, math.max(ta, st.tOn), math.min(tb, st.tOff), rel.X, rel.Z)
					local laserY = floorY + Motion.HEIGHT[st.kind]
					if Hit.check(st.kind, laserY, floorY, root.Position.Y, sliding, crossed and inside) then
						lastHit[player] = now
						onHit(player, root, rel, st.kind, mx, mz)
						break
					end
				end
			end
		end
	end

	local function step()
		local now = workspace:GetServerTimeNow()
		local dt = if lastStep then math.clamp(now - lastStep, 0, 0.1) else 0
		lastStep = now
		director:step(now, ctx.intensity())
		local live = set:step(now)
		if live ~= liveCount then
			liveCount = live
			map:SetAttribute("ActiveLasers", live)
		end
		checkPlayers(now, dt)
	end

	local session = { map = map }

	function session.start(_self)
		director:start(workspace:GetServerTimeNow())
		trove:connect(RunService.Heartbeat, step)
		trove:connect(Players.PlayerRemoving, function(player: Player)
			lastHit[player] = nil
			slideSeen[player] = nil
		end)
	end

	function session.stop(_self)
		trove:clean()
		set:powerDown(workspace:GetServerTimeNow())
		table.clear(lastHit)
		table.clear(slideSeen)
	end

	return session
end

return definition
