--[[
Party Dash Forgive: lag-fair hit judging (Contracts/Minigame.lua "HIT JUDGING", brief #22 "I jumped and still got hit").

The server sees a client-owned character about one ping (+ an interpolation buffer) late, so "did they jump over /
slide under it?" must never be decided from the current server position alone. Forgive samples every character on
Heartbeat into a ~1.5 s ring buffer and judges against the whole lag window:

	local Forgive = require(ServerScriptService.Server.Movement.Forgive)
	task.spawn(function()
		-- yields until the lag window after t has been sampled (<= 0.5 s). true = HIT, false = dodged.
		local hit = Forgive.judge(player, t, function(s) return s.feetY >= floorY + 1 end)
		if hit and ctx.isAlive(player) then ctx.knockback(player, dir, power) end
	end)

	sample = { t, pos: Vector3, rootY, feetY, sliding, dashing, grounded }   (t = workspace:GetServerTimeNow())
	Forgive.samples(player, t0, t1) -> { sample }   copies, oldest first, never yields
	Forgive.feetY(player) -> number?                world Y of the soles right now (rig and scale aware)
	Forgive.judge(player, t, isClear) -> boolean    see above; a player without samples is always a hit

A sample counts as sliding when the Sliding attribute was set OR a client-reported slide window
[SlideStartAt, SlideEndAt + 0.05] covers it (windows are kept here, so earlier slides still count).
The pure helpers (Forgive.verdictTime, Forgive.evaluate) take plain numbers / tables, for unit tests.

One sampler per server: the first copy of this module that starts owns it and exposes a BindableFunction, so a copy
required from another context (Studio command bar, tests) reads the same live samples.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Body = require(ReplicatedStorage.Shared.Movement.Body)
local Stats = require(ReplicatedStorage.Shared.Movement.Stats)

local Forgive = {}

export type Sample = {
	t: number,
	pos: Vector3,
	rootY: number,
	feetY: number,
	sliding: boolean,
	dashing: boolean,
	grounded: boolean,
}
type Window = { startAt: number, endAt: number }
type Track = {
	character: Model?,
	ring: { Sample },
	head: number, -- index of the newest sample
	count: number,
	slides: { Window },
	dashes: { Window },
	params: RaycastParams,
	lastGroundedAt: number,
}

Forgive.HISTORY = 1.5 -- seconds of samples kept
Forgive.MAX_WAIT = 0.5 -- judge() never yields longer than this
Forgive.GROUND_PROBE = 1.2 -- studs below the soles that still count as standing

local CAPACITY = 100 -- ~1.6 s of Heartbeat samples at 60 Hz
local MAX_WINDOWS = 6
local BRIDGE_NAME = "ForgiveBridge"

local tracks: { [Player]: Track } = {}
local role = "none" -- "none" | "sampler" | "proxy"
local bridge: BindableFunction? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function newTrack(): Track
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true -- the cartoon sea parts and decorations are not ground
	return {
		character = nil,
		ring = {},
		head = 0,
		count = 0,
		slides = {},
		dashes = {},
		params = params,
		lastGroundedAt = -math.huge,
	}
end

local function inWindows(windows: { Window }, t: number, grace: number): boolean
	for _, w in windows do
		if t >= w.startAt and t <= w.endAt + grace then
			return true
		end
	end
	return false
end

local function pushWindow(windows: { Window }, startAt: number, endAt: number)
	table.insert(windows, { startAt = startAt, endAt = endAt })
	while #windows > MAX_WINDOWS do
		table.remove(windows, 1)
	end
end

-- One sample of a character right now (nil when it has no root yet).
local function measure(track: Track, character: Model, t: number): Sample?
	local humanoid, root = Body.parts(character)
	if not humanoid or not root then
		return nil
	end
	local rootPos = root.Position
	local feet = rootPos.Y - Body.rootToFeet(character, humanoid, root)
	if track.character ~= character then
		track.params.FilterDescendantsInstances = { character }
	end
	local reach = rootPos.Y - feet + Forgive.GROUND_PROBE
	local grounded = workspace:Raycast(rootPos, Vector3.new(0, -reach, 0), track.params) ~= nil
	return {
		t = t,
		pos = rootPos,
		rootY = rootPos.Y,
		feetY = feet,
		sliding = character:GetAttribute("Sliding") == true,
		dashing = character:GetAttribute("Dashing") == true,
		grounded = grounded,
	}
end

local function store(track: Track, sample: Sample)
	track.head = track.head % CAPACITY + 1
	track.ring[track.head] = sample
	track.count = math.min(track.count + 1, CAPACITY)
	if sample.grounded then
		track.lastGroundedAt = sample.t
	end
end

-- Copies of the stored samples in [t0, t1], oldest first, with the slide/dash windows resolved.
local function collect(track: Track, t0: number, t1: number): { Sample }
	local out = {}
	for i = track.count - 1, 0, -1 do
		local index = (track.head - 1 - i) % CAPACITY + 1
		local s = track.ring[index]
		if s and s.t >= t0 and s.t <= t1 then
			table.insert(out, {
				t = s.t,
				pos = s.pos,
				rootY = s.rootY,
				feetY = s.feetY,
				sliding = s.sliding or inWindows(track.slides, s.t, Stats.SLIDE_WINDOW_GRACE),
				dashing = s.dashing or inWindows(track.dashes, s.t, 0),
				grounded = s.grounded,
			})
		end
	end
	return out
end

local function sampleAll()
	local t = now()
	for player, track in tracks do
		local character = player.Character
		if character and character.Parent then
			if track.character ~= character then
				-- A new body: old samples describe somewhere else entirely.
				track.ring = {}
				track.head = 0
				track.count = 0
				track.slides = {}
				track.dashes = {}
				track.lastGroundedAt = -math.huge
			end
			local sample = measure(track, character, t)
			track.character = character
			if sample then
				store(track, sample)
			end
		end
	end
end

local function trackOf(player: Player): Track
	local track = tracks[player]
	if not track then
		track = newTrack()
		tracks[player] = track
	end
	return track
end

-- The sampler-side implementation of samples() (also served to other copies through the bridge).
local function localSamples(player: Player, t0: number, t1: number): { Sample }
	local track = tracks[player]
	if not track then
		return {}
	end
	return collect(track, t0, t1)
end

-- Starts the Heartbeat sampler (Movement's server script calls this at boot; idempotent).
function Forgive.start()
	if role ~= "none" or not RunService:IsServer() then
		return
	end
	local existing = script:FindFirstChild(BRIDGE_NAME)
	if existing and existing:IsA("BindableFunction") then
		role = "proxy"
		bridge = existing
		return
	end
	role = "sampler"
	for _, player in Players:GetPlayers() do
		trackOf(player)
	end
	Players.PlayerAdded:Connect(trackOf)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	RunService.Heartbeat:Connect(sampleAll)
	local fn = Instance.new("BindableFunction")
	fn.Name = BRIDGE_NAME
	fn.OnInvoke = function(player: any, t0: any, t1: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return {}
		end
		if not Stats.isFinite(t0) or not Stats.isFinite(t1) then
			return {}
		end
		return localSamples(player, t0, t1)
	end
	fn.Parent = script
	bridge = fn
end

-- Samples of `player` with t0 <= t <= t1 (oldest first). Never yields.
function Forgive.samples(player: Player, t0: number, t1: number): { Sample }
	if role == "none" then
		Forgive.start()
	end
	if role == "proxy" and bridge then
		local ok, result = pcall(bridge.Invoke, bridge, player, t0, t1)
		return if ok and type(result) == "table" then result else {}
	end
	return localSamples(player, t0, t1)
end

-- World Y of the player's soles right now (standing pose; rig and scale aware), or nil without a character.
function Forgive.feetY(player: Player): number?
	return Body.feetY(player.Character)
end

-- Server time at which a crossing at `t` can be judged: the client's reaction has reached us by then.
function Forgive.verdictTime(t: number, ping: number): number
	return t + math.clamp(ping, 0, Config.FORGIVE_MAX_LAG) + Config.FORGIVE_INTERP
end

-- Pure verdict: false (dodged) when ANY sample in [t0, t1] is clear, true (hit) otherwise (also with no samples).
function Forgive.evaluate(samples: { Sample }, t0: number, t1: number, isClear: (Sample) -> boolean): boolean
	for _, s in samples do
		if s.t >= t0 and s.t <= t1 and isClear(s) then
			return false
		end
	end
	return true
end

--[[ Judges a hazard crossing `player` at server time `t`. YIELDS until the lag window after t has been sampled
(at most MAX_WAIT), then returns false if any sample in [t - FORGIVE_PAST, verdict time] satisfies isClear. ]]
function Forgive.judge(player: Player, t: number, isClear: (Sample) -> boolean): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not Stats.isFinite(t) then
		return true
	end
	if type(isClear) ~= "function" then
		warn("[Forgive] judge needs an isClear(sample) function")
		return true
	end
	local ok, ping = pcall(player.GetNetworkPing, player)
	local verdictAt = Forgive.verdictTime(t, if ok and Stats.isFinite(ping) then ping else 0)
	local wait = math.min(verdictAt - now(), Forgive.MAX_WAIT)
	if wait > 0 then
		task.wait(wait)
	end
	local t1 = math.min(verdictAt, now())
	local list = Forgive.samples(player, t - Config.FORGIVE_PAST, t1)
	-- The freshest state too (Heartbeat may not have sampled since we resumed).
	if role == "sampler" then
		local track = tracks[player]
		local character = player.Character
		if track and character and track.character == character then
			local fresh = measure(track, character, now())
			if fresh then
				fresh.sliding = fresh.sliding or inWindows(track.slides, fresh.t, Stats.SLIDE_WINDOW_GRACE)
				fresh.dashing = fresh.dashing or inWindows(track.dashes, fresh.t, 0)
				fresh.t = math.min(fresh.t, t1)
				table.insert(list, fresh)
			end
		end
	end
	if #list == 0 then
		return true
	end
	return Forgive.evaluate(list, t - Config.FORGIVE_PAST, t1, isClear)
end

-- Movement (same VM): a client-reported slide window [startAt, endAt] (server time). Updating the newest
-- window with the same startAt shortens it when the slide ends early.
function Forgive.noteSlide(player: Player, startAt: number, endAt: number)
	local track = tracks[player]
	if not track then
		return
	end
	local last = track.slides[#track.slides]
	if last and last.startAt == startAt then
		last.endAt = endAt
	else
		pushWindow(track.slides, startAt, endAt)
	end
end

function Forgive.noteDash(player: Player, startAt: number, endAt: number)
	local track = tracks[player]
	if track then
		pushWindow(track.dashes, startAt, endAt)
	end
end

-- Movement (same VM): seconds since the last grounded sample (math.huge when never grounded).
function Forgive.airTime(player: Player): number
	local track = tracks[player]
	if not track then
		return math.huge
	end
	return now() - track.lastGroundedAt
end

-- Movement (same VM): was the player grounded in any sample of [t0, now]?
function Forgive.wasGrounded(player: Player, t0: number): boolean
	local track = tracks[player]
	return track ~= nil and track.lastGroundedAt >= t0
end

return Forgive
