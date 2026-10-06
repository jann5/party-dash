--[[
Party Dash: client side of the global modifiers (see src/shared/Contracts/Modifier.lua).
An effect module here (LowGravity, Fog, Slippery) returns { enable = function(): () -> () } where enable()
changes the local client and returns its restore function. Exactly one effect runs at a time, and only
while ALL of these hold:
	GameState.ModifierId names an effect here
	GameState.Phase is Intro, Countdown or Round
	the local player is InRound (alive in the main round) and not InSolo
The moment any of them stops holding (knocked out, round over, Solo run) the effect is restored.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage:WaitForChild("Shared").GameState)

type Effect = { enable: () -> () -> () }

local ACTIVE_PHASES = {
	[GameState.Phase.Intro] = true,
	[GameState.Phase.Countdown] = true,
	[GameState.Phase.Round] = true,
}

local localPlayer = Players.LocalPlayer

local effects: { [string]: Effect } = {}
for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, effect = pcall(require, child)
		if ok and type(effect) == "table" and type(effect.enable) == "function" then
			effects[child.Name] = effect
		else
			warn(("[Modifiers] client effect %s failed to load: %s"):format(child.Name, tostring(effect)))
		end
	end
end

local currentId: string? = nil
local restore: (() -> ())? = nil

local function wanted(): string?
	local id = GameState.read("ModifierId")
	if type(id) ~= "string" or effects[id] == nil then
		return nil
	end
	if not ACTIVE_PHASES[GameState.read("Phase")] then
		return nil
	end
	if localPlayer:GetAttribute("InRound") ~= true or localPlayer:GetAttribute("InSolo") == true then
		return nil
	end
	return id
end

local function refresh()
	local id = wanted()
	if id == currentId then
		return
	end
	if restore then
		local ok, err = pcall(restore)
		if not ok then
			warn(("[Modifiers] restoring %s failed: %s"):format(tostring(currentId), tostring(err)))
		end
		restore = nil
	end
	currentId = id
	if id then
		local ok, result = pcall(effects[id].enable)
		if ok and type(result) == "function" then
			restore = result
		elseif not ok then
			warn(("[Modifiers] enabling %s failed: %s"):format(id, tostring(result)))
		end
	end
end

GameState.onChanged("ModifierId", refresh)
GameState.onChanged("Phase", refresh)
localPlayer:GetAttributeChangedSignal("InRound"):Connect(refresh)
localPlayer:GetAttributeChangedSignal("InSolo"):Connect(refresh)
refresh()
