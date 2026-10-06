-- King of the Hill (client boot). Boots itself; see the child modules:
--   WorldFx  local zone pulse rings, breathing beam, bobbing crown (every arena, keyed by map Model)
--   Hud      status pill + bat cooldown chip + "+1" / "BONK!" pops while you hold a bat
--   Input    touch SWING button, hidden hotbar, swing fallback remote, hit confirm
-- A King of the Hill bat is a Tool with the attribute "KOTH_Bat" and an ObjectValue "KOTH_Map".
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Hud = require(script:WaitForChild("Hud"))
local Input = require(script:WaitForChild("Input"))
local WorldFx = require(script:WaitForChild("WorldFx"))

local localPlayer = Players.LocalPlayer

local okFx, errFx = pcall(WorldFx.start)
if not okFx then
	warn("[KingOfTheHill] WorldFx failed to start:", errFx)
end

local hud = Hud.new()
Input.start(hud)

local current: Tool? = nil

local function isBat(inst: Instance?): boolean
	return inst ~= nil and inst:IsA("Tool") and inst:GetAttribute("KOTH_Bat") == true
end

-- The bat we currently own: in hand first, then in the backpack.
local function findBat(): Tool?
	local character = localPlayer.Character
	if character then
		for _, child in character:GetChildren() do
			if isBat(child) then
				return child :: Tool
			end
		end
	end
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if isBat(child) then
				return child :: Tool
			end
		end
	end
	return nil
end

local function mapOf(tool: Tool): Model?
	local ref = tool:FindFirstChild("KOTH_Map")
	local value = if ref and ref:IsA("ObjectValue") then ref.Value else nil
	return if value and value:IsA("Model") then value else nil
end

local scanTimer = 0
RunService.Heartbeat:Connect(function(dt: number)
	scanTimer += dt
	if scanTimer >= 0.15 then
		scanTimer = 0
		local bat = findBat()
		if bat ~= current then
			current = bat
			if bat then
				Input.bind(bat)
				hud:show(bat, mapOf(bat))
			else
				Input.unbind()
				hud:hide()
			end
		elseif bat and not hud.map then
			hud.map = mapOf(bat) -- the map reference can replicate a moment after the tool
		end
	end
	if current then
		local now = os.clock()
		hud:update(now)
		Input.update(now)
	end
end)
