--[[
Party Dash Core: lighting preset "PD_Day" (docs/v2/ART_BIBLE.md 2.2): crisp, saturated and readable.
No haze, no glare, a mild warm sun, cool shadows, a light grade, Bloom only for the few Neon parts.
Lighting.Technology (ShadowMap) is a Studio-only setting saved in the place; scripts cannot set it.
]]
local Lighting = game:GetService("Lighting")

local LightingSetup = {}

-- Players spawn in the lobby looking +Z, so the sun must sit BEHIND them and fairly high (ART_BIBLE 2.3 check 1):
-- Lighting:GetSunDirection() needs Z < -0.2 and 0.6 <= Y <= 0.85. The first (clock time, latitude) pair below
-- that passes, with a small safety margin, is used; ART_BIBLE's 14:00 / 25 degrees comes first.
local CLOCK_TIMES = { 14, 13.5, 14.5, 13, 15, 15.5 }
local LATITUDES = { 25, -25, 35, -35, 15, -15, 45, -45, 55, -55, 5, -5 }
local SUN_Z_MAX = -0.25
local SUN_Y_MIN, SUN_Y_MAX = 0.63, 0.82

local function make(className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = Lighting
	return inst
end

local function sunBehindLobbyCamera(): boolean
	local ok, dir = pcall(Lighting.GetSunDirection, Lighting)
	return ok and dir.Z < SUN_Z_MAX and dir.Y >= SUN_Y_MIN and dir.Y <= SUN_Y_MAX
end

local function placeSun(): boolean
	for _, clock in CLOCK_TIMES do
		for _, latitude in LATITUDES do
			Lighting.ClockTime = clock
			Lighting.GeographicLatitude = latitude
			if sunBehindLobbyCamera() then
				return true
			end
		end
	end
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 25
	return false
end

function LightingSetup.apply()
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	-- Terrain clouds read as realistic (and cost on mobile); the backdrop has blocky clouds instead.
	local terrainClouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if terrainClouds then
		terrainClouds:Destroy()
	end

	if not placeSun() then
		warn("[LightingSetup] no sun position passed the lobby check; using 14:00 at 25 degrees")
	end
	Lighting.Brightness = 2.2
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = Color3.fromRGB(64, 66, 84)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 124, 148) -- slightly cool shadows
	Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 205) -- mild warm sun
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.15 -- no grazing-angle white sheen on plastic
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.12
	Lighting.FogStart = 0
	Lighting.FogEnd = 100000

	-- No skybox ids: the classic Roblox blue sky with cartoon cumulus (ref4).
	make("Sky", { Name = "Sky", SunAngularSize = 12, MoonAngularSize = 11, StarCount = 0, CelestialBodiesShown = true })
	make("Atmosphere", {
		Name = "Atmosphere",
		Density = 0.12,
		Offset = 0.05,
		Color = Color3.fromRGB(170, 218, 255),
		Decay = Color3.fromRGB(110, 170, 235),
		Glare = 0,
		Haze = 0,
	})
	make("BloomEffect", { Name = "Bloom", Intensity = 0.3, Size = 16, Threshold = 1.8 })
	make("ColorCorrectionEffect", {
		Name = "Grade",
		Brightness = 0,
		Contrast = 0.08,
		Saturation = 0.12,
		TintColor = Color3.fromRGB(255, 255, 255),
	})
	-- Deliberately no SunRaysEffect, DepthOfFieldEffect or Terrain Clouds (ART_BIBLE 2.2).
end

return LightingSetup
