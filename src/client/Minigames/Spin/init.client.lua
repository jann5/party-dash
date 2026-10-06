--[[
Party Dash: SPIN client renderer. For every Spin arena (CollectionService tag "SpinArena": the main round
and any Solo copies) it spins the bars locally every frame from the server's deterministic segments
(BarMath), so motion is perfectly smooth. Juice:
	- a new bar rises out of the hub, flashing, before it can hit anyone
	- a bar flashes white before it reverses direction
	- each pillar's neon rim lights up just before an arm sweeps over it ("jump now!")
	- a whoosh when an arm is about to pass your own pillar
Everything is keyed by the map Model and cleaned up with it.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)
local Trove = require(Shared.Util.Trove)
local BarMath = require(script:WaitForChild("BarMath"))

local TAG = "SpinArena"
local WARN_TIME = 0.55 -- pillar rims glow this long before an arm arrives
local WHOOSH_LEAD = 0.18 -- seconds before the arm reaches us
local FLASH_HZ = 9
local RENDER_DISTANCE = 900 -- skip arenas this far from the camera (e.g. other Solo copies)
local HIDDEN_DEPTH = -12

local localPlayer = Players.LocalPlayer
local WHITE = Theme.Colors.White

type BarView = {
	model: Model,
	state: any,
	core: BasePart?,
	tips: { BasePart },
	baseColor: Color3,
	flashing: boolean,
	bright: boolean,
	whooshArmed: boolean,
	landed: boolean,
}

type PillarView = {
	glow: BasePart,
	baseColor: Color3,
	angle: number,
	glowK: number,
}

local function makeSound(parent: Instance, id: string, volume: number, speed: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Parent = parent
	return s
end

local function play(sound: Sound, speed: number?)
	if speed then
		sound.PlaybackSpeed = speed
	end
	pcall(SoundService.PlayLocalSound, SoundService, sound)
end

local function watchArena(map: Model)
	local trove = Trove.new()
	local pillarsFolder = map:WaitForChild("Pillars", 10)
	local barsFolder = map:WaitForChild("Bars", 10)
	if not pillarsFolder or not barsFolder then
		return trove
	end

	local sounds = Instance.new("Folder")
	sounds.Name = "SpinSounds"
	sounds.Parent = script
	trove:add(sounds)
	local whoosh = makeSound(sounds, "rbxasset://sounds/action_swim.mp3", 0.45, 1.6)
	local boom = makeSound(sounds, "rbxasset://sounds/impact_explosion_03.mp3", 0.25, 1.2)
	local tickSound = makeSound(sounds, "rbxasset://sounds/volume_slider.ogg", 0.5, 1.4)

	local pillars: { PillarView } = {}
	local function addPillar(model: Instance)
		local glow = model:FindFirstChild("Glow")
		local angle = model:GetAttribute("Angle")
		if glow and glow:IsA("BasePart") and type(angle) == "number" then
			local base = glow:GetAttribute("BaseColor")
			table.insert(pillars, {
				glow = glow,
				baseColor = if typeof(base) == "Color3" then base else glow.Color,
				angle = angle,
				glowK = 0,
			})
		end
	end
	for _, model in pillarsFolder:GetChildren() do
		addPillar(model)
	end

	local bars: { [Model]: BarView } = {}
	local function addBar(model: Instance)
		if not model:IsA("Model") or bars[model] then
			return
		end
		local core = model:WaitForChild("Core", 5)
		if bars[model :: Model] or not model.Parent then
			return -- added meanwhile by the other path, or already gone
		end
		local tips = {}
		for _, child in model:GetChildren() do
			if child.Name == "Tip" and child:IsA("BasePart") then
				table.insert(tips, child)
			end
		end
		local color = model:GetAttribute("Color")
		local appearAt = model:GetAttribute("AppearAt")
		local view: BarView = {
			model = model,
			state = BarMath.decode(model:GetAttribute("State")),
			core = if core and core:IsA("BasePart") then core else nil,
			tips = tips,
			baseColor = if typeof(color) == "Color3" then color else Theme.Colors.Red,
			flashing = false,
			bright = false,
			whooshArmed = true,
			-- only bars that rise while we watch get the landing boom
			landed = type(appearAt) ~= "number" or workspace:GetServerTimeNow() > appearAt + BarMath.APPEAR_TIME + 0.5,
		}
		bars[model] = view
		trove:connect(model:GetAttributeChangedSignal("State"), function()
			view.state = BarMath.decode(model:GetAttribute("State"))
		end)
	end
	for _, model in barsFolder:GetChildren() do
		task.spawn(addBar, model)
	end
	trove:connect(barsFolder.ChildAdded, addBar)
	trove:connect(barsFolder.ChildRemoved, function(model)
		bars[model :: Model] = nil
	end)

	local function setFlash(view: BarView, on: boolean, bright: boolean)
		local core = view.core
		if not core then
			return
		end
		if on then
			core.Color = if bright then WHITE else view.baseColor
			for _, tip in view.tips do
				tip.Size = Vector3.one * (if bright then 3.6 else 2.8)
			end
		elseif view.flashing then
			core.Color = view.baseColor
			for _, tip in view.tips do
				tip.Size = Vector3.one * 2.8
			end
		end
		view.flashing = on
	end

	-- Local player's position on the ring (nil when not standing among the pillars).
	local function localAngle(center: CFrame): number?
		if localPlayer:GetAttribute("InRound") ~= true then
			return nil
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return nil
		end
		local p = center:PointToObjectSpace(root.Position)
		local r = Vector2.new(p.X, p.Z).Magnitude
		if r < BarMath.RING_RADIUS - 10 or r > BarMath.BAR_HALF_LEN + 2 or math.abs(p.Y) > 10 then
			return nil
		end
		return BarMath.positionAngle(p)
	end

	local warnK = table.create(#pillars, 0)
	trove:connect(RunService.RenderStepped, function()
		local center = map:GetAttribute("Center")
		if typeof(center) ~= "CFrame" then
			return
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - center.Position).Magnitude > RENDER_DISTANCE then
			return
		end
		local now = workspace:GetServerTimeNow()
		local myAngle = localAngle(center)
		table.clear(warnK)

		for model, view in bars do
			local s = view.state
			if s and model.Parent then
				local angle = BarMath.angle(s, now)
				local velocity = BarMath.velocity(s, now)

				-- A late bar rises out of the hub, flashing, until its segment starts.
				local lift = 0
				local appearAt = model:GetAttribute("AppearAt")
				local rising = false
				if type(appearAt) == "number" and now < appearAt + BarMath.APPEAR_TIME then
					local k = math.clamp((now - appearAt) / BarMath.APPEAR_TIME, 0, 1)
					lift = HIDDEN_DEPTH * (1 - k) ^ 3
					rising = true
				elseif not view.landed then
					view.landed = true
					play(boom)
				end
				model:PivotTo(BarMath.barCFrame(center, angle, lift))

				-- Flash: while rising, and during the telegraph before a reversal.
				local telegraph = s.rt > 0 and now >= s.rt - BarMath.TELEGRAPH and now < s.rt + BarMath.TURN_TIME * 0.5
				if rising or telegraph then
					local bright = (now * FLASH_HZ) % 1 < 0.5
					if telegraph and bright and not view.bright then
						play(tickSound, 1.4 + (now - (s.rt - BarMath.TELEGRAPH)) * 0.6)
					end
					view.bright = bright
					setFlash(view, true, bright)
				elseif view.flashing then
					view.bright = false
					setFlash(view, false, false)
				end

				if not rising then
					for i, pillar in pillars do
						local t = BarMath.timeUntil(angle, velocity, pillar.angle)
						local k = math.clamp(1 - t / WARN_TIME, 0, 1)
						if k > (warnK[i] or 0) then
							warnK[i] = k
						end
					end
					if myAngle then
						local t = BarMath.timeUntil(angle, velocity, myAngle)
						if t < WHOOSH_LEAD and view.whooshArmed then
							view.whooshArmed = false
							play(whoosh, 1.4 + math.min(math.abs(velocity), 6) * 0.08)
						elseif t > WHOOSH_LEAD * 2 then
							view.whooshArmed = true
						end
					end
				end
			end
		end

		for i, pillar in pillars do
			local k = warnK[i] or 0
			if math.abs(k - pillar.glowK) > 0.03 or (k == 0 and pillar.glowK ~= 0) then
				pillar.glowK = k
				pillar.glow.Color = pillar.baseColor:Lerp(WHITE, k)
			end
		end
	end)

	return trove
end

local watched: { [Instance]: any } = {}

local function onAdded(map: Instance)
	if not map:IsA("Model") or watched[map] then
		return
	end
	watched[map] = true
	task.spawn(function()
		local trove = watchArena(map)
		if watched[map] and map.Parent then
			watched[map] = trove
		else
			trove:clean()
		end
	end)
end

local function onRemoved(map: Instance)
	local trove = watched[map]
	watched[map] = nil
	if type(trove) == "table" then
		trove:clean()
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(onAdded)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(onRemoved)
for _, map in CollectionService:GetTagged(TAG) do
	onAdded(map)
end
