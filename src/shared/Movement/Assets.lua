-- Asset ids used only by the movement system. Sounds are NOT here: they are played through Shared.Audio with the
-- keys in Shared.Assets.Sounds ("Dash", "Slide", ...), so the settings menu can mute them.
local Assets = {}

-- Official "Cartoony" animation package (R15). Keys match the StringValue slots of the stock Animate
-- script; idle has two variants (main idle + look-around). The slide is a procedural pose, not an animation.
Assets.Animations = {
	idle = { 742637544, 742638445 }, -- Cartoony_Idle, Cartoony_Lookaround
	walk = { 742640026 }, -- Cartoony_Walk
	run = { 742638842 }, -- Cartoony_Run
	jump = { 742637942 }, -- Cartoony_Jump
	fall = { 742637151 }, -- Cartoony_Fall (real falls only; the slide is never an animation)
	climb = { 742636889 }, -- Cartoony_Climb
	swim = { 742639220 }, -- Cartoony_Swim
	swimidle = { 742639812 }, -- Cartoony_SwimIdle
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
