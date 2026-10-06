-- Party Dash Core: a bright, saturated cartoon look (sunny afternoon, punchy colors, soft haze).
-- Starts from the legacy values in Shared/LightingData.lua and brightens them.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LightingData = require(ReplicatedStorage:WaitForChild("Shared").LightingData)

local LightingSetup = {}

local REPLACED = { "Sky", "Atmosphere", "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect", "DepthOfFieldEffect" }

local function make(className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	inst.Parent = Lighting
	return inst
end

function LightingSetup.apply()
	for _, child in Lighting:GetChildren() do
		if table.find(REPLACED, child.ClassName) then
			child:Destroy()
		end
	end

	Lighting.ClockTime = 14.2
	Lighting.GeographicLatitude = LightingData.GeographicLatitude or 0
	Lighting.Brightness = math.max(LightingData.Brightness or 3, 3)
	Lighting.Ambient = Color3.fromRGB(125, 120, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 165, 185)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 245, 225)
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.FogEnd = 100000

	-- Default Roblox sky: bright blue with fluffy clouds.
	make("Sky", { Name = "Sky", SunAngularSize = 14, StarCount = 0, CelestialBodiesShown = true })
	make("Atmosphere", {
		Name = "Atmosphere",
		Density = 0.24,
		Offset = 0.1,
		Color = Color3.fromRGB(205, 232, 255),
		Decay = Color3.fromRGB(120, 175, 255),
		Glare = 0.15,
		Haze = 0.6,
	})
	make("ColorCorrectionEffect", {
		Name = "CartoonColor",
		Saturation = 0.28,
		Contrast = 0.1,
		Brightness = 0.03,
		TintColor = Color3.fromRGB(255, 251, 245),
	})
	make("BloomEffect", { Name = "Bloom", Intensity = 0.45, Size = 26, Threshold = 1.5 })
	make("SunRaysEffect", { Name = "SunRays", Intensity = 0.05, Spread = 0.55 })
end

return LightingSetup
