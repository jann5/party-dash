--!strict
--[[
Laser Tracer: escalation director for ONE session. Decides when and which lasers appear, driven by
ctx.intensity() (1 at the start, +1 every Config.INTENSITY_RAMP_SECONDS, forever).

	Sweeps   rays rotating around the hub. All share one angular speed (map attribute "LaserSpeed"),
	         1 -> 4 of them as intensity grows; at high intensity they all reverse together (telegraphed).
	Slides   straight lasers crossing from any side; singles, then low+high combos, then cross waves.

Fairness rules (frantic but always beatable):
	- every laser is telegraphed WARN_TIME ahead (preview line, emitter flash, warning sound)
	- two sweeps turning in opposite directions are always the same kind (when they meet, one move clears both)
	- reversals flip every sweep at once, so relative motion (and the rule above) never changes
	- the two lasers of a combo are ~COMBO_GAP seconds apart (enough to land a jump, then slide)
	- opposite-side slide pairs are the same kind (they overlap along a whole line when they meet)
]]
local Lasers = require(script.Parent.Lasers)
local Motion = require(script.Parent.MotionRef)

type State = Motion.State
type LaserSet = Lasers.LaserSet

local Director = {}
Director.__index = Director

Director.WARN_TIME = 1.1
Director.COMBO_GAP = 0.95
Director.MAX_LASERS = 9
Director.REVERSE_FROM = 2.2 -- intensity at which sweeps start reversing
Director.REVERSE_WARN = 0.9
Director.FIRST_SWEEP_DELAY = 0.6
Director.FIRST_SLIDE_DELAY = 3.2

-- Angular speed (rad/s) of every sweep: 0.55 at intensity 1, ~1.09 at 2.5, capped so it stays dodgeable.
function Director.sweepSpeed(intensity: number): number
	return math.min(0.55 * math.max(intensity, 0.5) ^ 0.75, 2.4)
end

function Director.slideSpeed(intensity: number): number
	return math.clamp(10 * math.max(intensity, 0.5) ^ 0.55, 10, 24)
end

function Director.slideInterval(intensity: number): number
	return math.clamp(6.5 / math.max(intensity, 0.5) ^ 0.8, 1.9, 6.5)
end

function Director.sweepTarget(intensity: number): number
	if intensity < 1.3 then
		return 1
	elseif intensity < 2.0 then
		return 2
	elseif intensity < 2.9 then
		return 3
	end
	return 4
end

export type Director = typeof(setmetatable(
	{} :: {
		set: LaserSet,
		map: Model,
		rng: Random,
		announce: (string, string?) -> (),
		spin: number,
		speed: number,
		published: number,
		nextSweepAt: number,
		nextSlideAt: number,
		nextReverseAt: number,
		sweepsSpawned: number,
		slidesSpawned: number,
		level: number,
		reversed: boolean,
	},
	Director
))

function Director.new(set: LaserSet, map: Model, rng: Random, announce: (string, string?) -> ()): Director
	local self = setmetatable({
		set = set,
		map = map,
		rng = rng,
		announce = announce,
		spin = if rng:NextNumber() < 0.5 then 1 else -1,
		speed = Director.sweepSpeed(1),
		published = -1,
		nextSweepAt = math.huge,
		nextSlideAt = math.huge,
		nextReverseAt = math.huge,
		sweepsSpawned = 0,
		slidesSpawned = 0,
		level = 1,
		reversed = false,
	}, Director)
	self:publishSpeed()
	return self
end

function Director.publishSpeed(self: Director)
	local rounded = math.floor(self.speed * 1000 + 0.5) / 1000
	if rounded ~= self.published then
		self.published = rounded
		self.map:SetAttribute("LaserSpeed", rounded)
	end
end

function Director.start(self: Director, now: number)
	self.nextSweepAt = now + Director.FIRST_SWEEP_DELAY
	self.nextSlideAt = now + Director.FIRST_SLIDE_DELAY
	self.nextReverseAt = now + 6
end

-- Smallest angular distance between two angles.
local function angleGap(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	return math.min(d, 2 * math.pi - d)
end

local function pickWeighted(rng: Random, options: { { any } }): any
	local total = 0
	for _, o in options do
		total += o[2]
	end
	local roll = rng:NextNumber() * total
	for _, o in options do
		roll -= o[2]
		if roll <= 0 then
			return o[1]
		end
	end
	return options[#options][1]
end

function Director.spawnSweep(self: Director, now: number, intensity: number)
	local rng = self.rng
	local sweeps = self.set:alive(now, "sweep")
	local tOn = now + Director.WARN_TIME

	-- Direction + kind, compatible with every sweep already out (see the fairness rules above).
	local kind, dir
	if self.sweepsSpawned == 0 then
		kind, dir = "low", self.spin
	else
		local lows, highs = 1, 1
		for _, laser in sweeps do
			if laser.state.kind == "low" then
				lows += 1
			else
				highs += 1
			end
		end
		local options = {}
		for _, d in { self.spin, -self.spin } do
			for _, k in { "low", "high" } do
				local ok = true
				for _, laser in sweeps do
					if Lasers.finalSpin(laser) ~= d and laser.state.kind ~= k then
						ok = false
						break
					end
				end
				-- Counter-rotating sweeps only once things heat up.
				if ok and (d == self.spin or intensity >= 1.6) then
					local weight = (if d == self.spin then 3 else 1.2) / (if k == "low" then lows else highs)
					table.insert(options, { { k, d }, weight })
				end
			end
		end
		if #options == 0 then
			return
		end
		local choice = pickWeighted(rng, options)
		kind, dir = choice[1], choice[2]
	end

	-- Start angle: as far as possible from the other sweeps (where they will be when this one goes live).
	local best, bestGap = rng:NextNumber(0, 2 * math.pi), -1
	for _ = 1, 10 do
		local candidate = rng:NextNumber(0, 2 * math.pi)
		local gap = math.pi
		for _, laser in sweeps do
			gap = math.min(gap, angleGap(candidate, Motion.angle(laser.state, tOn)))
		end
		if gap > bestGap then
			best, bestGap = candidate, gap
		end
	end

	local life = rng:NextNumber(15, 22)
	self.set:add({
		pattern = "sweep",
		kind = kind,
		tWarn = now,
		tOn = tOn,
		tOff = tOn + life,
		a = best,
		b = 0,
		t0 = tOn,
		s = dir * self.speed,
		revAt = 0,
	})
	self.sweepsSpawned += 1
end

function Director.addSlide(self: Director, now: number, kind: string, heading: number, speed: number, delay: number)
	local tOn = now + Director.WARN_TIME
	local start = -Motion.ENTRY - speed * delay -- a delayed combo partner starts further back
	self.set:add({
		pattern = "slide",
		kind = kind,
		tWarn = now,
		tOn = tOn,
		tOff = tOn + (Motion.ENTRY - start) / speed,
		a = heading,
		b = start,
		t0 = tOn,
		s = speed,
		revAt = 0,
	})
end

-- One wave of slide lasers; returns extra seconds to wait before the next wave.
function Director.spawnWave(self: Director, now: number, intensity: number): number
	local rng = self.rng
	local speed = Director.slideSpeed(intensity)
	local heading = rng:NextNumber(0, 2 * math.pi)
	local function anyKind(): string
		return if rng:NextNumber() < 0.5 then "low" else "high"
	end
	-- Keep both colors on screen: a single slide brings the kind that is currently missing, if any.
	local function singleKind(): string
		local seen = { low = false, high = false }
		for _, laser in self.set:alive(now) do
			seen[laser.state.kind] = true
		end
		if seen.low ~= seen.high then
			return if seen.low then "high" else "low"
		end
		return anyKind()
	end

	local wave = "single"
	if self.slidesSpawned > 0 then
		local options = { { "single", 1 } }
		if intensity >= 1.6 then
			table.insert(options, { "combo", 1 })
		end
		if intensity >= 2.4 then
			table.insert(options, { "cross", 0.8 })
			table.insert(options, { "pincer", 0.5 })
		end
		if intensity >= 3.2 then
			table.insert(options, { "comboCross", 0.7 })
		end
		wave = pickWeighted(rng, options)
	end
	self.slidesSpawned += 1

	if wave == "single" then
		-- The opening slide is a HIGH one so players meet both laser types in the first seconds.
		self:addSlide(now, if self.slidesSpawned == 1 then "high" else singleKind(), heading, speed, 0)
		return 0
	elseif wave == "combo" or wave == "comboCross" then
		local first = anyKind()
		self:addSlide(now, first, heading, speed, 0)
		self:addSlide(now, if first == "low" then "high" else "low", heading, speed, Director.COMBO_GAP)
		if wave == "comboCross" then
			self:addSlide(now, anyKind(), heading + math.pi / 2 * (if rng:NextNumber() < 0.5 then 1 else -1), speed, 0)
		end
		return Director.COMBO_GAP
	elseif wave == "cross" then
		self:addSlide(now, anyKind(), heading, speed, 0)
		self:addSlide(now, anyKind(), heading + math.pi / 2, speed, 0)
		return 0.5
	end
	-- pincer: from opposite sides, same kind.
	local kind = anyKind()
	self:addSlide(now, kind, heading, speed * 0.9, 0)
	self:addSlide(now, kind, heading + math.pi, speed * 0.9, 0)
	return 0.5
end

function Director.step(self: Director, now: number, intensity: number)
	-- 1) Speed: every sweep shares one angular speed; re-key when it drifted by more than 3%.
	local target = Director.sweepSpeed(intensity)
	if math.abs(target - self.speed) > self.speed * 0.03 then
		self.speed = target
		self.set:rekeySweeps(now, target)
	end
	self:publishSpeed()

	local total = #self.set:alive(now)

	-- 2) Sweeps: keep the target count out (each lives 15-22 s, then a fresh one replaces it).
	local wanted = Director.sweepTarget(intensity)
	if wanted > self.level then
		self.level = wanted
		self.announce("MORE LASERS!", "They're getting faster...")
	end
	if now >= self.nextSweepAt and total < Director.MAX_LASERS then
		if #self.set:alive(now, "sweep") < wanted then
			self:spawnSweep(now, intensity)
			total += 1
			self.nextSweepAt = now + 2.2
		end
	end

	-- 3) Slides: waves come faster with intensity.
	if now >= self.nextSlideAt and total < Director.MAX_LASERS - 2 then
		local extra = self:spawnWave(now, intensity)
		self.nextSlideAt = now + Director.slideInterval(intensity) + extra
	end

	-- 4) Reversals (telegraphed): all sweeps flip direction together.
	if intensity >= Director.REVERSE_FROM and now >= self.nextReverseAt then
		self.set:reverseSweeps(now, now + Director.REVERSE_WARN)
		self.spin = -self.spin
		if not self.reversed then
			self.reversed = true
			self.announce("REVERSE!", "Lasers can now switch direction")
		end
		local gap = self.rng:NextNumber(4, 8) / math.sqrt(intensity / Director.REVERSE_FROM)
		self.nextReverseAt = now + math.max(gap, 2.8)
	end
end

return Director
