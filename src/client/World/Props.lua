--[[
World client: animated lobby props (ART_BIBLE 6.3).
	Lucky wheel  slow idle spin of "WheelDisc" plus a marquee chase on the 16 rim bulbs (0.12 s step); the chase runs
	             green while this player has a free spin (Player FreeSpinReady). Another system may drive the disc
	             itself (e.g. a real spin): it sets WheelDisc attribute "PD_Spinning" = true and the idle spin pauses.
	Chests       the Neon "ReadyRing" pulses (Transparency 0.2 <-> 0.6, 1 Hz) and a "!" bubble wobbles while Player
	             DailyReady / GroupReady is true; otherwise the ring stays dim (0.85). When it flips true -> false
	             (claimed) the lid pops open with a sparkle burst and closes again.

	Props.bind(lobbyModel, trove)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("Theme"))

local Props = {}

local C = Theme.Colors
local player = Players.LocalPlayer

local IDLE_SPIN = math.rad(14) -- radians per second
local CHASE_STEP = 0.12
local CHASE_FREE = Color3.fromRGB(60, 255, 90)
local RESOLVE_STEP = 0.25
local RING_STEP = 1 / 30
local LID_OPEN = math.rad(70)
local LID_TIMES = { open = 0.35, hold = 1.5, close = 1.85 }

local CHESTS = {
	{ model = "DailyChest", attribute = "DailyReady" },
	{ model = "GroupChest", attribute = "GroupReady" },
}

type Chest = {
	model: string,
	attribute: string,
	rings: { BasePart },
	lid: BasePart?,
	lidBase: CFrame,
	hinge: Vector3,
	burst: ParticleEmitter?,
	badge: BillboardGui?,
	ready: boolean?,
	openedAt: number?,
}

-- Lid angle for an opening that started `t` seconds ago (nil when the animation is over).
local function lidAngle(t: number): number?
	if t < LID_TIMES.open then
		return LID_OPEN * TweenService:GetValue(t / LID_TIMES.open, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	elseif t < LID_TIMES.hold then
		return LID_OPEN
	elseif t < LID_TIMES.close then
		local a = (t - LID_TIMES.hold) / (LID_TIMES.close - LID_TIMES.hold)
		return LID_OPEN * (1 - TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	end
	return nil
end

local function makeBurst(trove: any, lid: BasePart): ParticleEmitter
	local attachment = trove:add(Instance.new("Attachment"))
	attachment.Name = "ClaimBurst"
	attachment.Position = Vector3.new(0, 0.5, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(C.Yellow, C.Gold)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -30, 0)
	emitter.Parent = attachment
	attachment.Parent = lid
	return emitter
end

local function bindWheel(lobby: Model, trove: any)
	local disc: BasePart? = nil
	local discBase = CFrame.identity
	local bulbs: { [number]: BasePart } = {}
	local angle, chase = 0, 0
	local resolveWait, chaseWait = RESOLVE_STEP, 0

	local function resolve()
		local wheel = lobby:FindFirstChild("Wheel")
		if not wheel then
			return
		end
		if disc == nil or disc.Parent == nil then
			local found = wheel:FindFirstChild("WheelDisc")
			disc = if found and found:IsA("BasePart") then found else nil
			if disc then
				discBase = disc.CFrame
			end
		end
		for _, d in wheel:GetChildren() do
			local index = d:GetAttribute("Index")
			if d.Name == "Bulb" and d:IsA("BasePart") and typeof(index) == "number" then
				bulbs[index] = d
			end
		end
	end

	local function paintBulbs()
		local lit = if player:GetAttribute("FreeSpinReady") == true then CHASE_FREE else C.Yellow
		for index, bulb in bulbs do
			if bulb.Parent then
				local on = (index - chase) % 4 < 2
				bulb.Color = if on then lit else C.White
				bulb.Transparency = if on then 0 else 0.35
			end
		end
	end

	trove:connect(RunService.Heartbeat, function(dt)
		resolveWait += dt
		if resolveWait >= RESOLVE_STEP then
			resolveWait = 0
			resolve()
		end
		angle = (angle + IDLE_SPIN * dt) % (2 * math.pi)
		if disc and disc.Parent and disc:GetAttribute("PD_Spinning") ~= true then
			disc.CFrame = discBase * CFrame.Angles(angle, 0, 0) -- the cylinder's axis is its local X
		end
		chaseWait += dt
		if chaseWait >= CHASE_STEP then
			chaseWait = 0
			chase += 1
			paintBulbs()
		end
	end)
end

local function bindChests(lobby: Model, trove: any)
	local chests: { Chest } = {}
	for _, spec in CHESTS do
		table.insert(chests, {
			model = spec.model,
			attribute = spec.attribute,
			rings = {},
			lid = nil,
			lidBase = CFrame.identity,
			hinge = Vector3.zero,
			burst = nil,
			badge = nil,
			ready = nil,
			openedAt = nil,
		})
	end

	local function resolve(chest: Chest)
		if chest.badge == nil or chest.badge.Parent == nil then
			local anchor = lobby:FindFirstChild(chest.model .. "Anchor")
			local badge = anchor and anchor:FindFirstChild("ReadyBadge")
			chest.badge = if badge and badge:IsA("BillboardGui") then badge else nil
		end
		local model = lobby:FindFirstChild(chest.model)
		if not model then
			return
		end
		table.clear(chest.rings)
		for _, d in model:GetChildren() do
			if d.Name == "ReadyRing" and d:IsA("BasePart") then
				table.insert(chest.rings, d)
			end
		end
		if chest.lid == nil or chest.lid.Parent == nil then
			local lid = model:FindFirstChild("Lid")
			if lid and lid:IsA("BasePart") then
				chest.lid = lid
				chest.lidBase = lid.CFrame
				local hinge = lid:GetAttribute("HingeOffset")
				chest.hinge = if typeof(hinge) == "Vector3"
					then hinge
					else Vector3.new(0, -lid.Size.Y / 2, lid.Size.Z / 2)
				chest.burst = makeBurst(trove, lid)
			end
		end
	end

	local resolveWait, ringWait = RESOLVE_STEP, RING_STEP
	trove:connect(RunService.Heartbeat, function(dt)
		local now = os.clock()
		resolveWait += dt
		ringWait += dt
		local doResolve = resolveWait >= RESOLVE_STEP
		local doRings = ringWait >= RING_STEP
		if doResolve then
			resolveWait = 0
		end
		if doRings then
			ringWait = 0
		end
		for _, chest in chests do
			if doResolve then
				resolve(chest)
			end
			local ready = player:GetAttribute(chest.attribute) == true
			if chest.ready == true and not ready then
				chest.openedAt = now -- just claimed
				if chest.burst then
					chest.burst:Emit(36)
				end
			end
			chest.ready = ready
			if doRings then
				local transparency = if ready then 0.4 - 0.2 * math.sin(now * 2 * math.pi) else 0.85
				for _, ring in chest.rings do
					ring.Transparency = transparency
				end
				local badge = chest.badge
				if badge then
					badge.Enabled = ready
					local dot = badge:FindFirstChild("Dot")
					if ready and dot and dot:IsA("GuiObject") then
						dot.Rotation = 10 * math.sin(now * 5) -- wobbling "!" bubble
					end
				end
			end
			local lid = chest.lid
			if chest.openedAt and lid and lid.Parent then
				local a = lidAngle(now - chest.openedAt)
				if a == nil then
					chest.openedAt = nil
					a = 0
				end
				lid.CFrame = chest.lidBase * CFrame.new(chest.hinge) * CFrame.Angles(a, 0, 0) * CFrame.new(-chest.hinge)
			end
		end
	end)
end

function Props.bind(lobby: Model, trove: any)
	bindWheel(lobby, trove)
	bindChests(lobby, trove)
end

return Props
