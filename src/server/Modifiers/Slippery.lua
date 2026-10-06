-- Modifier SLIPPERY: participants' character parts get near-zero friction (CustomPhysicalProperties) and
-- their client adds icy momentum (src/client/Modifiers/Slippery.lua). Original properties are stored on
-- each part and restored exactly when the player is knocked out or the round ends.
local CharacterEffect = require(script.Parent:WaitForChild("_Lib").CharacterEffect)

local MARK = "Mod_SlipOriginal" -- "" = had no CustomPhysicalProperties, else "d,f,e,fw,ew"
local FRICTION = 0.01
local FRICTION_WEIGHT = 100

local function encode(props: PhysicalProperties?): string
	if not props then
		return ""
	end
	return ("%.6g,%.6g,%.6g,%.6g,%.6g"):format(
		props.Density,
		props.Friction,
		props.Elasticity,
		props.FrictionWeight,
		props.ElasticityWeight
	)
end

local function decode(raw: string): PhysicalProperties?
	local n = string.split(raw, ",")
	if #n ~= 5 then
		return nil
	end
	local d, f, e, fw, ew = tonumber(n[1]), tonumber(n[2]), tonumber(n[3]), tonumber(n[4]), tonumber(n[5])
	if not (d and f and e and fw and ew) then
		return nil
	end
	return PhysicalProperties.new(d, f, e, fw, ew)
end

return CharacterEffect.define({
	id = "Slippery",
	displayName = "SLIPPERY",
	description = "Everything is ice. Good luck stopping!",
	applyTo = function(character: Model)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part:GetAttribute(MARK) == nil then
				part:SetAttribute(MARK, encode(part.CustomPhysicalProperties))
				local current = part.CurrentPhysicalProperties
				part.CustomPhysicalProperties = PhysicalProperties.new(current.Density, FRICTION, 0, FRICTION_WEIGHT, 1)
			end
		end
	end,
	restore = function(character: Model)
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				local raw = part:GetAttribute(MARK)
				if type(raw) == "string" then
					part.CustomPhysicalProperties = if raw == "" then nil else decode(raw)
					part:SetAttribute(MARK, nil)
				end
			end
		end
	end,
})
