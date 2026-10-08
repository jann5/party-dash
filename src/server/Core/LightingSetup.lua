--[[
Party Dash Core: lighting preset "PD_Day" (docs/v2/ART_BIBLE.md 2.2). Crisp, saturated and readable: no haze, no
glare, a mild bloom that only Neon crosses, slightly cool shadows so blocks keep their form shading.

	LightingSetup.apply()   -- once at server boot (Main.server.lua); Lighting replicates to every client

Sun placement (ART_BIBLE 2.3 check 1): players spawn in the lobby looking +Z, so the sun must sit BEHIND them
(GetSunDirection().Z < -0.2) and high (0.6 <= Y <= 0.85) for lit, saturated faces. Roblox does not document its
sun model's hemisphere convention, so apply() verifies the direction instead of trusting one pair of numbers: the
ART_BIBLE preset (14:00, latitude 25), its mirror (latitude -25), then a small search within ClockTime 13-15.5.
Studio-only settings (Lighting.Technology) cannot be set from scripts and are left alone.
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

-- No Skybox ids: the classic Roblox blue sky with cartoon cumulus (ref4). No SunRays, no DepthOfField, no
-- Terrain clouds (mobile cost, and they read as realistic rather than cartoon).
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

local PRESET = { clock = 14, latitude = 25 }

-- Sun candidates in order of preference: the preset, its mirror, then afternoon times (ART_BIBLE: 13-15.5) at
-- moderate latitudes, and finally late-morning times in case the sun's daily path runs along Z.
local CANDIDATES = { PRESET, { clock = PRESET.clock, latitude = -PRESET.latitude } }
for _, clock in { 14, 13.5, 14.5, 13, 15, 15.5, 12.5, 11.5, 11, 10.5, 10 } do
	for _, latitude in { 20, 30, 15, 35, 10, 40, 45, 5, 0 } do
		table.insert(CANDIDATES, { clock = clock, latitude = latitude })
		if latitude ~= 0 then
			table.insert(CANDIDATES, { clock = clock, latitude = -latitude })
		end
	end
end

local function make(className: string, props: { [string]: any })
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = Lighting
end

-- ART_BIBLE 2.3 check 1, optionally with a safety margin inside the band.
local function sunBehindSpawn(margin: number): boolean
	local ok, dir = pcall(Lighting.GetSunDirection, Lighting)
	if not ok or typeof(dir) ~= "Vector3" then
		return false
	end
	return dir.Z < -0.2 - margin and dir.Y >= 0.6 + margin and dir.Y <= 0.85 - margin
end

-- Tries the candidates; `settle` waits one frame before each read (only used by the deferred re-check, in case
-- GetSunDirection lags behind a ClockTime change).
local function placeSun(settle: boolean): boolean
	for _, margin in { 0.02, 0 } do
		for _, c in CANDIDATES do
			Lighting.ClockTime = c.clock
			Lighting.GeographicLatitude = c.latitude
			if settle then
				RunService.Heartbeat:Wait()
			end
			if sunBehindSpawn(margin) then
				return true
			end
		end
	end
	Lighting.ClockTime = PRESET.clock
	Lighting.GeographicLatitude = PRESET.latitude
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
		warn("[LightingSetup] no ClockTime / latitude puts the sun behind the lobby spawn view")
	end
	task.delay(0.5, function()
		if not sunBehindSpawn(0) then
			placeSun(true)
		end
	end)
end

return LightingSetup
