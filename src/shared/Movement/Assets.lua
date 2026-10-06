-- Asset ids used by the movement system. All are public Roblox-owned assets (verified against the
-- Roblox catalog: creator "Roblox", asset type Animation / Audio), so they load in any experience.
local Assets = {}

-- Official "Cartoony" animation package (R15). Keys match the StringValue slots of the stock Animate
-- script; idle has two variants (main idle + look-around).
Assets.Animations = {
	idle = { 742637544, 742638445 }, -- Cartoony_Idle, Cartoony_Lookaround
	walk = { 742640026 }, -- Cartoony_Walk
	run = { 742638842 }, -- Cartoony_Run
	jump = { 742637942 }, -- Cartoony_Jump
	fall = { 742637151 }, -- Cartoony_Fall
	climb = { 742636889 }, -- Cartoony_Climb
	swim = { 742639220 }, -- Cartoony_Swim
	swimidle = { 742639812 }, -- Cartoony_SwimIdle
}

-- Arms-up pose layered over the procedural belly-slide tilt (reads as a "superman" dive).
Assets.SlidePose = 742637151 -- Cartoony_Fall

Assets.Sounds = {
	Dash = "rbxassetid://15675024286", -- Roblox_UI_Whoosh_01
	Slide = "rbxassetid://9118771226", -- Sand Slide 7 (SFX)
	Ready = "rbxassetid://15675059323", -- Roblox_UI_Bright_Click
}

-- Particle textures shipped with every Roblox client.
Assets.Textures = {
	Puff = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
}

function Assets.animationId(id: number): string
	return "rbxassetid://" .. tostring(id)
end

return Assets
