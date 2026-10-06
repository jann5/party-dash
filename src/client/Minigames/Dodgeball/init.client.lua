-- Dodgeball (client boot): renders every running Dodgeball session (main arena and Solo copies).
-- Listens to "Dodgeball_Fx" (server -> clients), keyed by the session id stored on each map as the
-- attribute "DodgeballSession":
--   shot   (sid, id, kind, cannonIndex, launchAt, endAt, fizzle, g, radius, color, segments, target?)
--   pop    (sid, id, pos, kind)       a ball burst on a player
--   golden (sid, pos)                 a golden ball appeared
--   grab   (sid, pos, userId)         somebody picked it up
--   clear  (sid)                      the round ended
-- Also starts the golden-ball throw controls (Throw.lua).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Balls = require(script.Balls)
local Cannons = require(script.Cannons)
local Effects = require(script.Effects)
local Throw = require(script.Throw)

local okFx, fxRemote = pcall(Net.event, "Dodgeball_Fx")
local okThrow, throwRemote = pcall(Net.event, "Dodgeball_Throw")
if not okFx or not okThrow then
	return -- the Dodgeball minigame is not installed on this server
end

local GOLD = Color3.fromRGB(255, 208, 64)
local SESSION_ATTRIBUTE = "DodgeballSession"

local folder = Instance.new("Folder")
folder.Name = "PD_DodgeballClient"
folder.Parent = workspace

local effects = Effects.new(folder)
local balls = Balls.new(folder)
local cannons = Cannons.new()

type Session = { map: Model, floor: Balls.FloorInfo }
local sessions: { [string]: Session } = {}

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function isMap(inst: Instance, sid: string): boolean
	return inst:IsA("Model") and inst:GetAttribute(SESSION_ATTRIBUTE) == sid
end

-- Finds the map of a session (a direct child of workspace, or one level inside a folder/model).
local function session(sid: string): Session?
	local known = sessions[sid]
	if known and known.map.Parent then
		return known
	end
	local found: Model? = nil
	for _, child in workspace:GetChildren() do
		if isMap(child, sid) then
			found = child :: Model
			break
		end
		if (child:IsA("Folder") or child:IsA("Model")) and child ~= folder then
			for _, inner in child:GetChildren() do
				if isMap(inner, sid) then
					found = inner :: Model
					break
				end
			end
			if found then
				break
			end
		end
	end
	if not found then
		return nil
	end
	local center = found:GetAttribute("ArenaCenter")
	local radius = found:GetAttribute("ArenaRadius")
	if typeof(center) ~= "Vector3" or not isFinite(radius) then
		return nil
	end
	local s = { map = found, floor = { y = center.Y, center = center, radius = radius } }
	sessions[sid] = s
	return s
end

local function cameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function onShot(sid: string, ...)
	local id, kind, cannonIndex, launchAt, endAt, fizzle, g, radius, color, packed, target = ...
	if
		type(id) ~= "number"
		or type(kind) ~= "string"
		or type(cannonIndex) ~= "number"
		or not isFinite(launchAt)
		or not isFinite(endAt)
		or not isFinite(g)
		or not isFinite(radius)
		or typeof(color) ~= "Color3"
		or type(packed) ~= "table"
	then
		return
	end
	if target ~= nil and typeof(target) ~= "Vector3" then
		target = nil
	end
	local info = session(sid)
	local visual = balls:spawn(
		sid,
		id,
		kind,
		cannonIndex,
		launchAt,
		endAt,
		fizzle == true,
		g,
		radius,
		color,
		packed,
		target,
		if info then info.floor else nil,
		cameraPosition()
	)
	if visual and cannonIndex > 0 and info then
		local cannonsFolder = info.map:FindFirstChild("Cannons")
		local model = cannonsFolder and cannonsFolder:FindFirstChild(("Cannon%02d"):format(cannonIndex))
		if model and model:IsA("Model") then
			cannons:charge(model, workspace:GetServerTimeNow(), launchAt, visual.segments[1].v0)
		end
	end
end

local function onLaunch(v: Balls.Visual)
	local first = v.segments[1]
	if v.cannon > 0 then
		effects:puff(first.p0, first.v0, v.color)
	else
		effects:sound("whoosh", first.p0, 1.1)
	end
end

local function onBounce(v: Balls.Visual)
	local seg = v.segments[v.segment]
	if not seg then
		return
	end
	local ground = seg.p0 - Vector3.new(0, v.radius - 0.2, 0)
	effects:bounce(ground, v.color, v.radius * 2, v.kind == "giant")
end

local function onEnd(v: Balls.Visual)
	if v.fizzle then
		effects:fizzle(v.pos, v.color, v.radius * 2)
	end
end

local function clearSession(sid: string)
	local info = sessions[sid]
	balls:clear(sid)
	if info then
		cannons:clear(info.map)
	end
	sessions[sid] = nil
end

fxRemote.OnClientEvent:Connect(function(kind: any, sid: any, ...)
	if type(kind) ~= "string" or type(sid) ~= "string" then
		return
	end
	if kind == "shot" then
		onShot(sid, ...)
	elseif kind == "pop" then
		local id, pos = ...
		if type(id) ~= "number" or typeof(pos) ~= "Vector3" then
			return
		end
		local v = balls:remove(sid, id)
		local color = if v then v.color else GOLD
		local size = if v then v.radius * 2 else 4
		if (pos - cameraPosition()).Magnitude < 900 then
			effects:pop(pos, color, size)
		end
	elseif kind == "golden" then
		local pos = ...
		if typeof(pos) == "Vector3" and (pos - cameraPosition()).Magnitude < 900 then
			session(sid)
			effects:beam(pos)
		end
	elseif kind == "grab" then
		local pos = ...
		if typeof(pos) == "Vector3" and (pos - cameraPosition()).Magnitude < 900 then
			effects:grab(pos)
		end
	elseif kind == "clear" then
		clearSession(sid)
	end
end)

-- Golden ball waiting on the floor: a happy local bob + spin (the server only checks its base spot).
local function bobGolden(info: Session, t: number)
	local golden = info.map:FindFirstChild("Golden")
	if not golden then
		return
	end
	for _, child in golden:GetChildren() do
		local base = child:GetAttribute("Base")
		if child:IsA("BasePart") and typeof(base) == "Vector3" then
			child.CFrame = CFrame.new(base + Vector3.new(0, 0.45 * math.sin(t * 3), 0)) * CFrame.Angles(0, t * 2, 0)
		end
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	local t = workspace:GetServerTimeNow()
	balls:update(t, dt, onLaunch, onBounce, onEnd)
	cannons:update(t)
	for sid, info in sessions do
		if not info.map.Parent then
			clearSession(sid)
		else
			bobGolden(info, os.clock())
		end
	end
end)

Throw.start(throwRemote, function()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		effects:sound("whoosh", root.Position, 1.3)
	end
end)
