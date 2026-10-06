-- Dodgeball (client): animates the server's cannon models locally (the server never moves them).
-- Each CannonNN model has Carriage (turns) and Barrel (turns + pitches) sub-models plus the attributes
-- Pivot / BarrelPivot (CFrames as built). We cache every part's offset from those pivots once, then pose:
--   charge  : turn toward the target, pitch to the launch angle, glow brighter, shake harder, fuse sparks
--   fire    : recoil kick and settle (the muzzle puff/boom is played by the caller at launch)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Cannons = {}
Cannons.__index = Cannons

local TURN_SHARE = 0.4 -- fraction of the charge spent turning toward the target
local RECOIL_TIME = 0.4
local RECOIL_DISTANCE = 2
local MAX_PITCH = math.rad(35)
local MIN_PITCH = math.rad(-6)

type PartOffset = { part: BasePart, offset: CFrame }

type Rig = {
	model: Model,
	pivot: CFrame,
	trunnion: CFrame, -- barrel pivot relative to the cannon pivot (translation only)
	carriage: { PartOffset },
	barrel: { PartOffset },
	glow: BasePart?,
	sparks: ParticleEmitter?,
	hiss: Sound?,
	yaw: number, -- current aim, radians (CFrame.lookAt convention)
	pitch: number,
}

type Anim = {
	rig: Rig,
	chargeStart: number,
	fireAt: number,
	fromYaw: number,
	toYaw: number,
	fromPitch: number,
	toPitch: number,
	fired: boolean,
}

local function yawOf(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function angleLerp(a: number, b: number, k: number): number
	local delta = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + delta * k
end

local function easeOut(k: number): number
	return 1 - (1 - k) * (1 - k)
end

local function collect(container: Instance?, pivot: CFrame): { PartOffset }
	local list = {}
	if container then
		for _, d in container:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, { part = d, offset = pivot:ToObjectSpace(d.CFrame) })
			end
		end
	end
	return list
end

function Cannons.new()
	local self = setmetatable({}, Cannons)
	self.rigs = setmetatable({}, { __mode = "k" }) :: { [Model]: Rig }
	self.anims = {} :: { [Rig]: Anim }
	return self
end

function Cannons:_rig(model: Model): Rig?
	local rig = self.rigs[model]
	if rig then
		return rig
	end
	local pivot = model:GetAttribute("Pivot")
	local barrelPivot = model:GetAttribute("BarrelPivot")
	if typeof(pivot) ~= "CFrame" or typeof(barrelPivot) ~= "CFrame" then
		return nil
	end
	local barrelModel = model:FindFirstChild("Barrel")
	local barrel = collect(barrelModel, barrelPivot)
	if #barrel == 0 then
		return nil -- not streamed in yet
	end
	local glow = barrelModel and barrelModel:FindFirstChild("Glow")
	local spark = barrelModel and barrelModel:FindFirstChild("Spark")
	local sparks = spark and spark:FindFirstChild("FuseSparks")
	local hiss: Sound? = nil
	if spark then
		local s = Instance.new("Sound")
		s.Name = "Hiss"
		s.SoundId = "rbxasset://sounds/action_falling.ogg"
		s.Looped = true
		s.Volume = 0.35
		s.PlaybackSpeed = 2.6
		s.RollOffMinDistance = 15
		s.RollOffMaxDistance = 160
		s.Parent = spark
		hiss = s
	end
	local look = pivot.LookVector
	rig = {
		model = model,
		pivot = pivot,
		trunnion = CFrame.new(pivot:PointToObjectSpace(barrelPivot.Position)),
		carriage = collect(model:FindFirstChild("Carriage"), pivot),
		barrel = barrel,
		glow = if glow and glow:IsA("BasePart") then glow else nil,
		sparks = if sparks and sparks:IsA("ParticleEmitter") then sparks else nil,
		hiss = hiss,
		yaw = yawOf(look),
		pitch = math.asin(math.clamp(barrelPivot.LookVector.Y, -1, 1)),
	}
	self.rigs[model] = rig
	return rig
end

local function pose(rig: Rig, yaw: number, pitch: number, shake: Vector3, recoil: number)
	local base = CFrame.new(rig.pivot.Position) * CFrame.Angles(0, yaw, 0)
	for _, po in rig.carriage do
		po.part.CFrame = base * po.offset
	end
	local barrel = base * rig.trunnion * CFrame.Angles(pitch, 0, 0) * CFrame.new(shake.X, shake.Y, recoil)
	for _, po in rig.barrel do
		po.part.CFrame = barrel * po.offset
	end
	rig.yaw = yaw
	rig.pitch = pitch
end

-- Starts a telegraph: the cannon fires a ball with initial velocity `velocity` at server time `fireAt`.
function Cannons:charge(model: Model, now: number, fireAt: number, velocity: Vector3)
	local rig = self:_rig(model)
	if not rig then
		return
	end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local pitch = math.clamp(math.atan2(velocity.Y, flat.Magnitude), MIN_PITCH, MAX_PITCH)
	self.anims[rig] = {
		rig = rig,
		chargeStart = math.min(now, fireAt - 0.05),
		fireAt = fireAt,
		fromYaw = rig.yaw,
		toYaw = yawOf(flat.Unit),
		fromPitch = rig.pitch,
		toPitch = pitch,
		fired = false,
	}
	if rig.sparks then
		rig.sparks.Enabled = true
	end
	if rig.hiss then
		rig.hiss.TimePosition = 0
		rig.hiss:Play()
	end
end

local function setGlow(rig: Rig, transparency: number, color: Color3)
	local glow = rig.glow
	if glow then
		glow.Transparency = transparency
		glow.Color = color
	end
end

local function finishCharge(rig: Rig)
	if rig.sparks then
		rig.sparks.Enabled = false
	end
	if rig.hiss then
		rig.hiss:Stop()
	end
end

function Cannons:update(t: number)
	for rig, anim in self.anims do
		if not rig.model.Parent then
			self.anims[rig] = nil
			continue
		end
		if t < anim.fireAt then
			local span = math.max(anim.fireAt - anim.chargeStart, 0.05)
			local k = math.clamp((t - anim.chargeStart) / span, 0, 1)
			local turn = easeOut(math.clamp(k / TURN_SHARE, 0, 1))
			local yaw = angleLerp(anim.fromYaw, anim.toYaw, turn)
			local pitch = anim.fromPitch + (anim.toPitch - anim.fromPitch) * turn
			local amp = 0.04 + 0.32 * k * k
			local shake = Vector3.new((math.random() - 0.5) * 2 * amp, (math.random() - 0.5) * 2 * amp, 0)
			pose(rig, yaw, pitch, shake, 0)
			-- Glow ramps up and flickers white right before the shot.
			local flicker = if k > 0.7 and math.floor(t * 24) % 2 == 0 then Theme.Colors.White else Theme.Colors.Yellow
			setGlow(rig, 1 - 0.85 * math.min(k * 1.2, 1), flicker)
		else
			if not anim.fired then
				anim.fired = true
				finishCharge(rig)
			end
			local u = math.clamp((t - anim.fireAt) / RECOIL_TIME, 0, 1)
			-- Instant kick back, springy return.
			local recoil = RECOIL_DISTANCE * (1 - u) ^ 2 * math.cos(u * math.pi * 1.5)
			pose(rig, anim.toYaw, anim.toPitch, Vector3.zero, recoil)
			setGlow(rig, math.min(1, 0.15 + u * 3), Theme.Colors.Orange)
			if u >= 1 then
				setGlow(rig, 1, Theme.Colors.Yellow)
				self.anims[rig] = nil
			end
		end
	end
end

-- Stops every animation of one arena (or all when nil) and drops cached rigs of destroyed maps.
function Cannons:clear(map: Instance?)
	for rig in self.anims do
		if map == nil or rig.model:IsDescendantOf(map) or not rig.model.Parent then
			finishCharge(rig)
			setGlow(rig, 1, Theme.Colors.Yellow)
			self.anims[rig] = nil
		end
	end
end

return Cannons
