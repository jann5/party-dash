--!strict
--[[
Laser Tracer: the set of lasers of ONE running session (server side).

Each laser is a Model in map.Lasers with:
	attribute "State"   Motion-encoded string (the only thing clients need to render it)
	attributes "Kind" ("low"/"high"), "Pattern" ("sweep"/"slide") and "Live" (false while telegraphed)
	                    for humans and tests
	child "Telegraph"   a faint preview line (+ direction arrows and a JUMP!/SLIDE! tag) that exists from
	                    tWarn until the beam goes live at tOn, then is destroyed

The beams themselves are drawn by the clients (src/client/Minigames/LaserTracer) every frame.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Theme"))
local Motion = require(script.Parent.MotionRef)

type State = Motion.State

export type Laser = {
	id: number,
	model: Model,
	state: State,
	telegraph: BasePart?,
}

local LaserSet = {}
LaserSet.__index = LaserSet

LaserSet.COLORS = Motion.COLORS
LaserSet.LABELS = { low = "JUMP!", high = "SLIDE!" } :: { [string]: string }
LaserSet.PREVIEW_OFFSET = Motion.RADIUS - 5 -- slide previews show the first chord inside the rim
LaserSet.LINGER = 0.3 -- keep the Model this long after the client fade so the fade can play

export type LaserSet = typeof(setmetatable(
	{} :: {
		map: Model,
		center: CFrame,
		folder: Folder,
		list: { Laser },
		nextId: number,
		poweredDown: boolean,
	},
	LaserSet
))

function LaserSet.new(map: Model, center: CFrame): LaserSet
	return setmetatable({
		map = map,
		center = center,
		folder = map:FindFirstChild("Lasers") :: Folder,
		list = {},
		nextId = 0,
		poweredDown = false,
	}, LaserSet)
end

local function ghost(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- World CFrame of a beam segment (local floor coords) whose X axis runs along the beam.
local function segmentCFrame(center: CFrame, x1: number, z1: number, x2: number, z2: number, y: number): CFrame
	local p1 = center * Vector3.new(x1, y, z1)
	local p2 = center * Vector3.new(x2, y, z2)
	return CFrame.lookAt((p1 + p2) / 2, p2, center.UpVector) * CFrame.Angles(0, math.pi / 2, 0)
end

-- A flat ">" chevron at local (x, z) pointing along local direction (dx, dz).
local function chevron(parent: Instance, center: CFrame, x: number, y: number, z: number, dx: number, dz: number, color)
	local heading = math.atan2(dz, dx)
	local base = center * CFrame.new(x, y, z) * CFrame.Angles(0, -heading, 0)
	for _, side in { 1, -1 } do
		ghost(parent, {
			Name = "Arrow",
			Size = Vector3.new(2.2, 0.25, 0.35),
			CFrame = base * CFrame.Angles(0, side * math.rad(40), 0) * CFrame.new(-1, 0, 0),
			Color = color,
			Transparency = 0.25,
		})
	end
end

local function label(parent: BasePart, kind: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromScale(7, 2.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if kind == "high" then 2.4 else 1.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.FontFace = Theme.FontFace
	text.Text = LaserSet.LABELS[kind] or ""
	text.TextScaled = true
	text.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Ink
	stroke.Thickness = 3
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = parent
end

-- The preview: where the beam will appear, which way it will move, and what to do about it.
function LaserSet.buildTelegraph(self: LaserSet, model: Model, st: State): BasePart
	local center = self.center
	local color = LaserSet.COLORS[st.kind]
	local y = Motion.HEIGHT[st.kind]
	local x1, z1, x2, z2
	local arrows = {} :: { { number } }
	if st.pattern == "sweep" then
		x1, z1, x2, z2 = Motion.segment(st, st.tOn)
		local a = Motion.angle(st, st.tOn)
		local sign = if st.s >= 0 then 1 else -1
		-- Chevrons ahead of the beam, pointing the way it will rotate.
		for _, r in { 16, 28, 38 } do
			local ahead = a + sign * 2.4 / r
			table.insert(arrows, { math.cos(ahead) * r, math.sin(ahead) * r, -math.sin(a) * sign, math.cos(a) * sign })
		end
	else
		local preview = table.clone(st)
		preview.b = -LaserSet.PREVIEW_OFFSET
		preview.t0 = 0
		x1, z1, x2, z2 = Motion.segment(preview, 0)
		local vx, vz = math.cos(st.a), math.sin(st.a)
		for _, f in { 0.3, 0.5, 0.7 } do
			local px, pz = x1 + (x2 - x1) * f + vx * 2.5, z1 + (z2 - z1) * f + vz * 2.5
			table.insert(arrows, { px, pz, vx, vz })
		end
	end
	local length = math.max(0.5, math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2))
	local line = ghost(model, {
		Name = "Telegraph",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, 0.35, 0.35),
		CFrame = segmentCFrame(center, x1, z1, x2, z2, y),
		Color = color,
		Transparency = 0.45,
	})
	for _, arrow in arrows do
		chevron(line, center, arrow[1], y, arrow[2], arrow[3], arrow[4], color)
	end
	label(line, st.kind, color)
	return line
end

function LaserSet.add(self: LaserSet, st: State): Laser
	self.nextId += 1
	local model = Instance.new("Model")
	model.Name = ("Laser%03d"):format(self.nextId)
	model:SetAttribute("Kind", st.kind)
	model:SetAttribute("Pattern", st.pattern)
	model:SetAttribute("Live", false)
	model:SetAttribute("State", Motion.encode(st))
	local laser: Laser = { id = self.nextId, model = model, state = st, telegraph = nil }
	laser.telegraph = self:buildTelegraph(model, st)
	model.Parent = self.folder
	table.insert(self.list, laser)
	return laser
end

function LaserSet.publish(_self: LaserSet, laser: Laser)
	laser.model:SetAttribute("State", Motion.encode(laser.state))
end

-- Lasers that still matter at time `now` (telegraphed or live), optionally filtered by pattern.
function LaserSet.alive(self: LaserSet, now: number, pattern: string?): { Laser }
	local out = {}
	for _, laser in self.list do
		if laser.state.tOff > now and (pattern == nil or laser.state.pattern == pattern) then
			table.insert(out, laser)
		end
	end
	return out
end

-- Direction a sweep will be turning once any pending reversal has happened (+1 / -1).
function LaserSet.finalSpin(laser: Laser): number
	local st = laser.state
	local sign = if st.s >= 0 then 1 else -1
	return if st.revAt > 0 then -sign else sign
end

-- New angular speed for every sweep, keeping each one exactly where it is (continuous motion). A pending
-- reversal stays scheduled: only the speed before and after it changes.
function LaserSet.rekeySweeps(self: LaserSet, now: number, speed: number)
	for _, laser in self:alive(now, "sweep") do
		local st = laser.state
		local t = math.max(now, st.t0)
		local sign = if Motion.angularVelocity(st, t) >= 0 then 1 else -1
		st.a = Motion.angle(st, t)
		st.t0 = t
		st.s = sign * speed
		if st.revAt > 0 and t >= st.revAt then
			st.revAt = 0
		end
		self:publish(laser)
	end
end

-- Telegraphed direction reversal of every sweep at time `at` (all together, so sweeps that never
-- crossed each other never start crossing).
function LaserSet.reverseSweeps(self: LaserSet, now: number, at: number)
	for _, laser in self:alive(now, "sweep") do
		local st = laser.state
		if st.revAt <= 0 then
			if at <= st.tOn then
				st.s = -st.s -- not live yet: just start the other way
			else
				st.revAt = at
			end
			self:publish(laser)
		end
	end
end

-- Lifecycle: remove previews when beams go live, fold finished reversals, destroy expired lasers.
function LaserSet.step(self: LaserSet, now: number): number
	local live = 0
	for i = #self.list, 1, -1 do
		local laser = self.list[i]
		local st = laser.state
		if laser.telegraph and now >= st.tOn then
			laser.telegraph:Destroy()
			laser.telegraph = nil
			laser.model:SetAttribute("Live", true)
		end
		if st.pattern == "sweep" and st.revAt > 0 and now > st.revAt + 0.1 then
			st.a = Motion.angle(st, now)
			st.t0 = now
			st.s = -st.s
			st.revAt = 0
			self:publish(laser)
		end
		if now > st.tOff + Motion.FADE_TIME + LaserSet.LINGER then
			laser.model:Destroy()
			table.remove(self.list, i)
		elseif now >= st.tOn and now <= st.tOff then
			live += 1
		end
	end
	return live
end

-- Round over: every beam fades out on the clients (map attribute PowerDown), previews vanish now.
function LaserSet.powerDown(self: LaserSet, now: number)
	if self.poweredDown then
		return
	end
	self.poweredDown = true
	for _, laser in self.list do
		if laser.telegraph then
			laser.telegraph:Destroy()
			laser.telegraph = nil
		end
	end
	self.map:SetAttribute("PowerDown", now)
end

return LaserSet
