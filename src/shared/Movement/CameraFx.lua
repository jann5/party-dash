--[[
Party Dash CameraFx (client only): the ONE writer of Camera.FieldOfView offsets and Humanoid.CameraOffset.

	local CameraFx = require(ReplicatedStorage.Shared.Movement.CameraFx)
	CameraFx.shake(0.6)              -- add trauma 0..1 (decays at 1.6/s); does nothing when Player.Set_Shake == false
	CameraFx.fovKick(6, 0.25)        -- short additive FOV punch (the dash uses +6 for 0.25 s)
	CameraFx.setFov("slide", 3)      -- held additive FOV offset for a named channel (nil clears it)
	CameraFx.setOffset("slide", v3)  -- held additive CameraOffset for a named channel (nil clears it)
	CameraFx.trauma() -> number      -- current shake trauma (0 = no shake running)

The base FOV is Config.CAMERA_FOV (set on every new CurrentCamera), and the camera starts Stats.CAMERA_START_ZOOM
studs behind the character once per session. Everything is ADDITIVE: when another script changes FieldOfView / CameraOffset, its
value becomes the new base and our offsets ride on top, so nothing is ever left shaken, zoomed or lifted. Trauma is
a function of time (value + timestamp), so it decays correctly even on frames the camera step does not run.
One driver per client: the first copy of this module that is used owns the render step; any other copy (for example
one required from a test context) forwards its calls through a BindableEvent and reads the trauma from its attributes.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(script.Parent.Stats)

local CameraFx = {}

local BRIDGE_NAME = "CameraFxBridge"
local STEP_NAME = "PD_CameraFx"
local TRAUMA_DECAY = 1.6 -- trauma lost per second
local SHAKE_STUDS = 0.9 -- CameraOffset amplitude at trauma 1 (scaled by trauma^2)
local SHAKE_FREQUENCY = 22
local KICK_ATTACK = 0.04 -- seconds to reach the full kick
local MAX_KICKS = 6

type Kick = { amount: number, start: number, duration: number }

local IS_CLIENT = RunService:IsClient()

local role: string = "none" -- "none" | "driver" | "proxy"
local bridge: BindableEvent? = nil

-- Driver state.
local trauma = 0 -- trauma at `traumaAt` (os.clock); it decays linearly from there
local traumaAt = 0
local kicks: { Kick } = {}
local fovChannels: { [string]: number } = {}
local offsetChannels: { [string]: Vector3 } = {}
local fovState = { camera = nil :: Camera?, wrote = nil :: number?, applied = 0 }
local offsetState = { humanoid = nil :: Humanoid?, wrote = nil :: Vector3?, applied = Vector3.zero }
local seed = 10 + math.random() * 100

local function shakeAllowed(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("Set_Shake") ~= false
end

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function decayed(value: number, at: number, now: number): number
	if value <= 0 then
		return 0
	end
	return math.max(0, value - TRAUMA_DECAY * (now - at))
end

-- Publishes the trauma on the bridge so every copy of this module can read it (CameraFx.trauma()).
local function setTrauma(value: number, now: number)
	trauma = value
	traumaAt = now
	if bridge then
		bridge:SetAttribute("Trauma", value)
		bridge:SetAttribute("TraumaAt", now)
	end
end

-- 0 -> 1 over KICK_ATTACK, then an ease-out back to 0 at `duration`.
local function kickEnvelope(t: number, duration: number): number
	if t < KICK_ATTACK then
		return t / KICK_ATTACK
	end
	local u = math.clamp((t - KICK_ATTACK) / math.max(duration - KICK_ATTACK, 1e-3), 0, 1)
	return (1 - u) * (1 - u)
end

local handlers = {}

function handlers.shake(amount: any)
	if isFinite(amount) and shakeAllowed() then
		local now = os.clock()
		setTrauma(math.clamp(decayed(trauma, traumaAt, now) + amount, 0, 1), now)
	end
end

function handlers.fovKick(amount: any, seconds: any)
	if not isFinite(amount) or not isFinite(seconds) or seconds <= 0 then
		return
	end
	if #kicks >= MAX_KICKS then
		table.remove(kicks, 1)
	end
	table.insert(kicks, { amount = math.clamp(amount, -30, 30), start = os.clock(), duration = seconds })
end

function handlers.setFov(channel: any, amount: any)
	if type(channel) == "string" then
		fovChannels[channel] = if isFinite(amount) and amount ~= 0 then math.clamp(amount, -30, 30) else nil
	end
end

function handlers.setOffset(channel: any, offset: any)
	if type(channel) == "string" then
		offsetChannels[channel] = if typeof(offset) == "Vector3" and offset.Magnitude > 1e-4 then offset else nil
	end
end

-- A new camera starts from the game's base FOV.
local function adoptCamera(camera: Camera)
	fovState.camera = camera
	fovState.wrote = nil
	fovState.applied = 0
	camera.FieldOfView = Config.CAMERA_FOV
end

local function stepFov(now: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera ~= fovState.camera then
		adoptCamera(camera)
	end
	local offset = 0
	for _, amount in fovChannels do
		offset += amount
	end
	for i = #kicks, 1, -1 do
		local kick = kicks[i]
		local t = now - kick.start
		if t >= kick.duration then
			table.remove(kicks, i)
		else
			offset += kick.amount * kickEnvelope(t, kick.duration)
		end
	end
	if math.abs(offset) < 1e-3 then
		offset = 0
	end
	if offset == 0 and fovState.applied == 0 then
		return
	end
	local current = camera.FieldOfView
	local base = if fovState.wrote and math.abs(current - fovState.wrote) < 1e-3
		then current - fovState.applied
		else current
	local value = math.clamp(base + offset, 1, 120)
	camera.FieldOfView = value
	fovState.wrote = value
	fovState.applied = value - base
end

local function stepOffset(now: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= offsetState.humanoid then
		offsetState.humanoid = humanoid
		offsetState.wrote = nil
		offsetState.applied = Vector3.zero
	end
	if not humanoid then
		return
	end
	local offset = Vector3.zero
	for _, v in offsetChannels do
		offset += v
	end
	local shake = decayed(trauma, traumaAt, now)
	if shake > 0 then
		local amplitude = shake * shake * SHAKE_STUDS
		local t = now * SHAKE_FREQUENCY
		offset += Vector3.new(math.noise(t, seed), math.noise(seed, t), math.noise(t + seed, seed * 0.5)) * amplitude
	end
	if offset.Magnitude < 1e-4 then
		offset = Vector3.zero
	end
	if offset == Vector3.zero and offsetState.applied == Vector3.zero then
		return
	end
	local current = humanoid.CameraOffset
	local base = current
	if offsetState.wrote and (current - offsetState.wrote).Magnitude < 1e-4 then
		base = current - offsetState.applied
	end
	local value = base + offset
	humanoid.CameraOffset = value
	offsetState.wrote = value
	offsetState.applied = offset
end

local function step()
	local now = os.clock()
	if trauma > 0 and (not shakeAllowed() or decayed(trauma, traumaAt, now) <= 0) then
		setTrauma(0, now) -- finished, or shake was switched off in Settings mid-shake
	end
	stepFov(now)
	stepOffset(now)
end

-- Once per session: start the camera Stats.CAMERA_START_ZOOM studs out. Raising the minimum zoom pushes the camera
-- out to it; putting the minimum back keeps that distance and the player can zoom freely again.
local function applyStartZoom()
	local player = Players.LocalPlayer
	local start = Stats.CAMERA_START_ZOOM
	if player.CameraMinZoomDistance >= start or player.CameraMaxZoomDistance < start then
		return
	end
	local restore = math.max(player.CameraMinZoomDistance, Stats.CAMERA_MIN_ZOOM)
	player.CameraMinZoomDistance = start
	task.delay(0.2, function()
		if player.CameraMinZoomDistance == start then
			player.CameraMinZoomDistance = restore
		end
	end)
end

-- Becomes the driver (first copy on this client) or a proxy that forwards to it.
local function ensureRole(): boolean
	if role ~= "none" then
		return true
	end
	if not IS_CLIENT then
		return false
	end
	local existing = script:FindFirstChild(BRIDGE_NAME)
	if existing and existing:IsA("BindableEvent") then
		role = "proxy"
		bridge = existing
		return true
	end
	role = "driver"
	local event = Instance.new("BindableEvent")
	event.Name = BRIDGE_NAME
	event.Event:Connect(function(kind: any, a: any, b: any)
		local handler = handlers[kind]
		if handler then
			handler(a, b)
		end
	end)
	event.Parent = script
	bridge = event
	-- The base FOV goes on right away (and on every new camera), not only when the camera step runs.
	if workspace.CurrentCamera then
		adoptCamera(workspace.CurrentCamera)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local camera = workspace.CurrentCamera
		if camera and camera ~= fovState.camera then
			adoptCamera(camera)
		end
	end)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value - 1, step)
	return true
end

local function send(kind: string, a: any, b: any)
	if not ensureRole() then
		return
	end
	if role == "driver" then
		handlers[kind](a, b)
	elseif bridge then
		bridge:Fire(kind, a, b)
	end
end

-- Starts the driver early (Movement client boot): base FOV now, default camera distance on the first character.
function CameraFx.start()
	if not ensureRole() or role ~= "driver" then
		return
	end
	local player = Players.LocalPlayer
	if player.Character then
		task.delay(0.1, applyStartZoom)
	else
		player.CharacterAdded:Once(function()
			task.delay(0.1, applyStartZoom)
		end)
	end
end

-- Adds camera trauma (0..1). The shake decays on its own; Set_Shake == false turns it off completely.
function CameraFx.shake(trauma01: number)
	if not IS_CLIENT or not isFinite(trauma01) or trauma01 <= 0 or not shakeAllowed() then
		return
	end
	send("shake", math.clamp(trauma01, 0, 1))
end

-- Short additive FOV punch: reaches `amount` degrees almost instantly, eases back to 0 over `seconds`.
function CameraFx.fovKick(amount: number, seconds: number)
	if IS_CLIENT then
		send("fovKick", amount, seconds)
	end
end

-- Held FOV offset in degrees for a channel ("slide"); nil or 0 clears it.
function CameraFx.setFov(channel: string, amount: number?)
	if IS_CLIENT then
		send("setFov", channel, amount)
	end
end

-- Held CameraOffset for a channel ("slide"); nil clears it.
function CameraFx.setOffset(channel: string, offset: Vector3?)
	if IS_CLIENT then
		send("setOffset", channel, offset)
	end
end

-- Current camera trauma on this client (0 = no shake running). For tests and debugging.
function CameraFx.trauma(): number
	if not ensureRole() then
		return 0
	end
	local now = os.clock()
	if role == "driver" then
		return decayed(trauma, traumaAt, now)
	end
	local value = bridge and bridge:GetAttribute("Trauma")
	local at = bridge and bridge:GetAttribute("TraumaAt")
	if type(value) ~= "number" or type(at) ~= "number" then
		return 0
	end
	return decayed(value, at, now)
end

return CameraFx
