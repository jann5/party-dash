--[[
Party Dash Core: lighting preset "PD_Day" (docs/v2/ART_BIBLE.md 2.2). Crisp, saturated and readable: no haze, no
glare, mild bloom that only Neon crosses, slightly cool shadows so blocks keep their form shading.

	LightingSetup.apply()   -- once at server boot (Main.server.lua)

Sun placement (ART_BIBLE 2.3 check 1): players spawn in the lobby looking +Z, so the sun must sit BEHIND them
(GetSunDirection().Z < -0.2) and high enough (0.6 <= Y <= 0.85) for lit, saturated faces. Roblox does not document
which hemisphere/axis convention its sun model uses, so we try the ART_BIBLE preset (14:00, latitude 25), then its
mirror (latitude -25), and only fall back to a small search around 14:00 if neither passes. A deferred re-check
covers the (unlikely) case that GetSunDirection() lags one frame behind ClockTime changes.
]]
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LightingSetup = {}

local PROPERTIES = {
	Brightness = 2.2,
	ExposureCompensation = 0,
	Ambient = Color3.fromRGB(64, 66, 84),
	OutdoorAmbient = Color3.fromRGB(118, 124, 148), -- slightly cool shadows
	ColorShift_Top = Color3.fromRGB(255, 236, 205), -- mild warm sun
	ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale = 0.35,
	EnvironmentSpecularScale = 0.15, -- kills the grazing-angle white sheen on plastic
	GlobalShadows = true,
	ShadowSoftness = 0.12,
	FogStart = 0,
	FogEnd = 100000,
}

-- Children of Lighting this preset owns (everything else, e.g. a client modifier's effect, is left alone).
local EFFECTS = {
	{
		className = "Sky",
		props = { Name = "Sky", SunAngularSize = 12, MoonAngularSize = 11, StarCount = 0, CelestialBodiesShown = true },
	},
	{
		className = "Atmosphere",
		props = {
			Name = "Atmosphere",
			Density = 0.12,
			Offset = 0.05,
			Color = Color3.fromRGB(170, 218, 255),
			Decay = Color3.fromRGB(110, 170, 235),
			Glare = 0,
			Haze = 0,
		},
	},
	{ className = "BloomEffect", props = { Name = "Bloom", Intensity = 0.3, Size = 16, Threshold = 1.8 } },
	{
		className = "ColorCorrectionEffect",
		props = {
			Name = "Grade",
			Brightness = 0,
			Contrast = 0.08,
			Saturation = 0.12,
			TintColor = Color3.fromRGB(255, 255, 255),
		},
	},
}

local PREFERRED_CLOCK = 14
local PREFERRED_LATITUDE = 25

local function make(className: string, props: { [string]: any })
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = Lighting
end

local function sunDirection(): Vector3?
	local ok, dir = pcall(Lighting.GetSunDirection, Lighting)
	return if ok and typeof(dir) == "Vector3" then dir else nil
end

-- ART_BIBLE 2.3 check 1, optionally with a safety margin inside the band.
local function sunBehindSpawn(dir: Vector3, margin: number): boolean
	return dir.Z < -0.2 - margin and dir.Y >= 0.6 + margin and dir.Y <= 0.85 - margin
end

-- Candidates in order of preference: the ART_BIBLE preset, its mirror, then a search close to 14:00.
local function candidates(): { { clock: number, latitude: number } }
	local list = {
		{ clock = PREFERRED_CLOCK, latitude = PREFERRED_LATITUDE },
		{ clock = PREFERRED_CLOCK, latitude = -PREFERRED_LATITUDE },
	}
	local search = {}
	for clock = 12, 16, 0.25 do
		for latitude = -60, 60, 5 do
			table.insert(search, { clock = clock, latitude = latitude })
		end
	end
	local function cost(c)
		return math.abs(c.clock - PREFERRED_CLOCK) * 4 + math.abs(math.abs(c.latitude) - PREFERRED_LATITUDE) / 10
	end
	table.sort(search, function(a, b)
		return cost(a) < cost(b)
	end)
	table.move(search, 1, #search, #list + 1, list)
	return list
end

local function trySun(clock: number, latitude: number, margin: number, settle: boolean): boolean
	Lighting.ClockTime = clock
	Lighting.GeographicLatitude = latitude
	if settle then
		RunService.Heartbeat:Wait()
	end
	local dir = sunDirection()
	return dir ~= nil and sunBehindSpawn(dir, margin)
end

-- Places the sun behind the spawn view. `settle` waits a frame before every read (deferred re-check only).
local function placeSun(settle: boolean): boolean
	local list = candidates()
	for _, margin in { 0.03, 0 } do
		for _, c in list do
			if trySun(c.clock, c.latitude, margin, settle) then
				return true
			end
		end
	end
	Lighting.ClockTime = PREFERRED_CLOCK
	Lighting.GeographicLatitude = PREFERRED_LATITUDE
	return false
end

function LightingSetup.apply()
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	for key, value in PROPERTIES do
		(Lighting :: any)[key] = value
	end
	for _, effect in EFFECTS do
		make(effect.className, effect.props)
	end

	if not placeSun(false) then
		warn("[LightingSetup] no ClockTime/latitude puts the sun behind the lobby spawn view")
	end
	task.delay(0.5, function()
		local dir = sunDirection()
		if dir and not sunBehindSpawn(dir, 0) then
			placeSun(true)
		end
	end)
end

return LightingSetup
