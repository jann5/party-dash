--!strict
--[[
Laser Tracer renderer for ONE arena Model (the boot script keeps one Renderer per map, keyed by the Model,
so the main round and any number of Solo copies render side by side).

Every frame it reads workspace:GetServerTimeNow() and places each beam with the shared Motion math, so the
beams move smoothly and exactly where the server checks hits. It also animates the telegraphs (pulsing
preview line, flashing emitter lenses, hub rings, warning beeps) and plays zaps on hit players.

All visuals are client-local parts parented inside the map, so they vanish with it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))

local Fx = require(script.Parent.Fx)
local Motion = require(script.Parent.Motion)
local Sounds = require(script.Parent.Sounds)

type State = Motion.State
type Beam = Fx.Beam

local Renderer = {}
Renderer.__index = Renderer

local AUDIBLE_DISTANCE = 170 -- camera this close to the arena center hears its warnings
local BEEPS = 3
local BEEP_GAP = 0.3
local POP_TIME = 0.14
local LENS_DIM = Color3.fromRGB(70, 55, 120)
local LENS_SIZE = 2.6

type Visual = {
	model: Model,
	state: State?,
	beam: Beam,
	beeps: number,
	poweredOn: boolean,
	revWarned: number,
	flicker: boolean,
	conn: RBXScriptConnection,
}

type Tower = { lens: BasePart, angle: number, lit: boolean }

export type Renderer = typeof(setmetatable(
	{} :: {
		map: Model,
		center: CFrame,
		sounds: Sounds.Sounds,
		rng: Random,
		fxFolder: Folder,
		visuals: { [Model]: Visual },
		towers: { Tower },
		hubRings: { [string]: BasePart },
		powerDown: number,
		connections: { RBXScriptConnection },
		lastBeep: number,
		destroyed: boolean,
	},
	Renderer
))

local function angleGap(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	return math.min(d, 2 * math.pi - d)
end

local function easeOutBack(x: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

function Renderer.new(map: Model, sounds: Sounds.Sounds): Renderer
	local center = map:GetAttribute("Center")
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalFx"
	fxFolder.Parent = map
	local self = setmetatable({
		map = map,
		center = if typeof(center) == "CFrame" then center else map:GetPivot(),
		sounds = sounds,
		rng = Random.new(),
		fxFolder = fxFolder,
		visuals = {},
		towers = {},
		hubRings = {},
		powerDown = 0,
		connections = {},
		lastBeep = 0,
		destroyed = false,
	}, Renderer)

	self:readPowerDown()
	table.insert(
		self.connections,
		map:GetAttributeChangedSignal("PowerDown"):Connect(function()
			self:readPowerDown()
		end)
	)
	task.spawn(function()
		self:bindChildren()
	end)
	return self
end

function Renderer.readPowerDown(self: Renderer)
	local v = self.map:GetAttribute("PowerDown")
	self.powerDown = if type(v) == "number" then v else 0
end

-- Waits for the map's pieces (they normally arrive together with the Model) and hooks the laser folder.
function Renderer.bindChildren(self: Renderer)
	local map = self.map
	local emitters = map:WaitForChild("Emitters", 10)
	if self.destroyed then
		return
	end
	if emitters then
		for _, tower in emitters:GetChildren() do
			local lens = tower:FindFirstChild("Lens")
			local angle = tower:GetAttribute("Angle")
			if lens and lens:IsA("BasePart") and type(angle) == "number" then
				table.insert(self.towers, { lens = lens, angle = angle, lit = false })
			end
		end
	end
	local hub = map:FindFirstChild("Hub")
	if hub then
		for kind, name in { low = "LowRing", high = "HighRing" } do
			local ring = hub:FindFirstChild(name)
			if ring and ring:IsA("BasePart") then
				self.hubRings[kind] = ring
			end
		end
	end
	local lasers = map:WaitForChild("Lasers", 10)
	if not lasers or self.destroyed then
		return
	end
	table.insert(
		self.connections,
		lasers.ChildAdded:Connect(function(child)
			self:addLaser(child)
		end)
	)
	table.insert(
		self.connections,
		lasers.ChildRemoved:Connect(function(child)
			self:removeLaser(child)
		end)
	)
	for _, child in lasers:GetChildren() do
		self:addLaser(child)
	end
end

function Renderer.addLaser(self: Renderer, model: Instance)
	if self.destroyed or not model:IsA("Model") or self.visuals[model] then
		return
	end
	local kind = model:GetAttribute("Kind")
	local visual: Visual = {
		model = model,
		state = Motion.decode(model:GetAttribute("State")),
		beam = Fx.newBeam(model, if kind == "high" then "high" else "low"),
		beeps = 0,
		poweredOn = false,
		revWarned = 0,
		flicker = false,
		conn = model:GetAttributeChangedSignal("State"):Connect(function()
			local v = self.visuals[model]
			if v then
				v.state = Motion.decode(model:GetAttribute("State")) or v.state
			end
		end),
	}
	-- A laser that is already past its warning when we first see it (late join) stays silent.
	local st = visual.state
	if st and workspace:GetServerTimeNow() > st.tWarn + BEEPS * BEEP_GAP then
		visual.beeps = BEEPS
		visual.poweredOn = workspace:GetServerTimeNow() > st.tOn + 0.3
	end
	self.visuals[model] = visual
end

function Renderer.removeLaser(self: Renderer, model: Instance)
	local visual = self.visuals[model :: Model]
	if not visual then
		return
	end
	self.visuals[model :: Model] = nil
	visual.conn:Disconnect()
	for _, part in { visual.beam.core, visual.beam.glow, visual.beam.floor, visual.beam.nodeA, visual.beam.nodeB } do
		part:Destroy()
	end
end

-- Warnings and juice are only audible when our camera is at this arena.
function Renderer.isNear(self: Renderer): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	return (camera.CFrame.Position - self.center.Position).Magnitude <= AUDIBLE_DISTANCE
end

-- Places one beam for time t. scale = thickness multiplier (pop-in / fade-out).
function Renderer.placeBeam(self: Renderer, beam: Beam, st: State, t: number, scale: number)
	local x1, z1, x2, z2 = Motion.segment(st, t)
	local length = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	if length < 0.3 or scale <= 0.01 then
		Fx.setVisible(beam, false)
		return
	end
	Fx.setVisible(beam, true)
	local center = self.center
	local y = Motion.HEIGHT[st.kind] or 1.6
	local p1 = center * Vector3.new(x1, y, z1)
	local p2 = center * Vector3.new(x2, y, z2)
	local along = CFrame.lookAt((p1 + p2) / 2, p2, center.UpVector) * CFrame.Angles(0, math.pi / 2, 0)
	local core = Fx.CORE_THICKNESS * scale
	local glow = Fx.GLOW_THICKNESS * scale
	beam.core.Size = Vector3.new(length, core, core)
	beam.core.CFrame = along
	beam.glow.Size = Vector3.new(length + 0.4, glow, glow)
	beam.glow.CFrame = along
	beam.floor.Size = Vector3.new(length, 0.06, 0.55 * scale)
	beam.floor.CFrame = along - center.UpVector * (y - 0.09)
	beam.nodeA.CFrame = CFrame.new(p1)
	beam.nodeB.CFrame = CFrame.new(p2)
	beam.lengthSparks.Rate = math.clamp(length * 0.7, 4, 32)
end

-- Endpoint angles of a live beam on the rim (towers near them glow as the beam passes).
local function rimAngles(st: State, t: number): { number }
	local x1, z1, x2, z2 = Motion.segment(st, t)
	if st.pattern == "sweep" then
		return { math.atan2(z2, x2) }
	end
	if math.abs(x2 - x1) + math.abs(z2 - z1) < 0.3 then
		return {}
	end
	return { math.atan2(z1, x1), math.atan2(z2, x2) }
end

function Renderer.update(self: Renderer, now: number)
	if self.destroyed then
		return
	end
	local near = self:isNear()
	local towerGlow: { [number]: number } = {}
	local towerColor: { [number]: Color3 } = {}
	local hubFlash: { [string]: boolean } = {}

	local function lightTowers(angle: number, level: number, color: Color3)
		for i, tower in self.towers do
			local gap = angleGap(tower.angle, angle)
			if gap < 0.42 then
				local v = level * (1 - gap / 0.42)
				if v > (towerGlow[i] or 0) then
					towerGlow[i] = v
					towerColor[i] = color
				end
			end
		end
	end

	for _, visual in self.visuals do
		local st = visual.state
		if not st then
			continue
		end
		local beam = visual.beam
		local tOff = if self.powerDown > 0 then math.min(st.tOff, self.powerDown) else st.tOff
		local scale = 0
		local cancelled = self.powerDown > 0 and st.tOn >= self.powerDown -- never went live

		if cancelled then
			scale = 0
		elseif now < st.tOn then
			-- TELEGRAPH: pulsing preview (server part), flashing emitters, rising beeps.
			local pulse = 0.5 + 0.5 * math.sin(now * 20)
			local telegraph = visual.model:FindFirstChild("Telegraph")
			if telegraph and telegraph:IsA("BasePart") then
				telegraph.Transparency = 0.15 + 0.5 * pulse
			end
			for _, angle in Motion.emitterAngles(st) do
				lightTowers(angle, 0.55 + 0.45 * pulse, beam.color)
			end
			if st.pattern == "sweep" then
				hubFlash[st.kind] = true
			end
			if self.powerDown <= 0 and visual.beeps < BEEPS and now >= st.tWarn + visual.beeps * BEEP_GAP then
				visual.beeps += 1
				-- Lasers announced in the same instant (combos) share one beep.
				if near and now - self.lastBeep > 0.08 then
					self.lastBeep = now
					self.sounds:play("beep", 1 + 0.18 * visual.beeps)
				end
			end
		elseif now <= tOff + Motion.FADE_TIME then
			if now <= tOff then
				scale = if now - st.tOn < POP_TIME then easeOutBack((now - st.tOn) / POP_TIME) else 1
				if not visual.poweredOn then
					visual.poweredOn = true
					if near then
						self.sounds:play("powerOn", if st.kind == "high" then 1.15 else 1)
					end
				end
			else
				scale = 1 - (now - tOff) / Motion.FADE_TIME
			end
			for _, angle in rimAngles(st, now) do
				lightTowers(angle, 0.45 * scale, beam.color)
			end
		end

		-- Reversal warning: the beam flickers white and swells for a moment before it flips.
		local flicker = false
		if st.revAt > 0 and now >= st.revAt - 0.9 and now <= st.revAt and scale > 0 then
			flicker = math.floor(now * 14) % 2 == 0
			scale *= 1.35
			if visual.revWarned ~= st.revAt then
				visual.revWarned = st.revAt
				if near then
					self.sounds:play("reverse")
				end
			end
		end
		if flicker ~= visual.flicker then
			visual.flicker = flicker
			beam.core.Color = if flicker then Theme.Colors.White else beam.coreColor
			beam.glow.Color = if flicker then beam.coreColor else beam.color
		end

		self:placeBeam(beam, st, now, scale)
	end

	-- Emitter lenses: dim unless a nearby laser is telegraphed (bright pulse) or passing by (soft glow).
	for i, tower in self.towers do
		local level = towerGlow[i]
		if level then
			tower.lit = true
			tower.lens.Color = LENS_DIM:Lerp(towerColor[i], math.clamp(level, 0, 1))
			tower.lens.Size = Vector3.one * (LENS_SIZE + 0.9 * level)
		elseif tower.lit then
			tower.lit = false
			tower.lens.Color = LENS_DIM
			tower.lens.Size = Vector3.one * LENS_SIZE
		end
	end
	for kind, ring in self.hubRings do
		local base = Fx.COLORS[kind]
		ring.Color = if hubFlash[kind] and math.floor(now * 10) % 2 == 0 then Theme.Colors.White else base
	end
end

-- A player got zapped by a laser of this arena.
function Renderer.zap(self: Renderer, player: Player, position: Vector3, kind: string)
	if self.destroyed then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then root.Position else position
	local flash = Fx.zap(self.fxFolder, at, kind, self.rng)
	if player == Players.LocalPlayer then
		self.sounds:play("zap")
		self.sounds:play("crackle")
	elseif self:isNear() then
		self.sounds:playAt("zap", flash)
	end
end

function Renderer.destroy(self: Renderer)
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	for model in self.visuals do
		self:removeLaser(model)
	end
	self.fxFolder:Destroy()
end

return Renderer
