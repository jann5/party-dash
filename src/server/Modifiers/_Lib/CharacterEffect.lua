--!strict
--[[
Helper for modifiers that change the participants' characters on the server (Giant, Tiny, Slippery).
Lives in a Folder ("_Lib"), so Core's modifier discovery (ModuleScripts only) skips it.

	CharacterEffect.define({
		id, displayName, description,
		applyTo = function(character: Model) end,   -- must be idempotent (marks what it changed)
		restore = function(character: Model) end,   -- must undo exactly what applyTo changed (idempotent)
	}) -> Modifier definition (Contracts/Modifier.lua)

Rules: only players still in the round (Player.InRound, never InSolo) are affected; a character that
respawns mid-round gets the effect again; a player who is knocked out (InRound -> false) is restored at
once; clear() restores everyone who started the round. The "is this modifier live" flag is a Player
attribute (Mod_Active = id), so nothing is kept at module level and every round is independent.
]]
local Players = game:GetService("Players")

local CharacterEffect = {}

CharacterEffect.ACTIVE_ATTRIBUTE = "Mod_Active"
CharacterEffect.APPEARANCE_TIMEOUT = 3

export type Spec = {
	id: string,
	displayName: string,
	description: string,
	intensityMultiplier: number?,
	applyTo: (Model) -> (),
	restore: (Model) -> (),
}

local function inRound(player: Player): boolean
	return player.Parent == Players and player:GetAttribute("InRound") == true and player:GetAttribute("InSolo") ~= true
end

local function safely(id: string, what: string, fn: (Model) -> (), character: Model)
	local ok, err = pcall(fn, character)
	if not ok then
		warn(("[Modifier %s] %s failed: %s"):format(id, what, tostring(err)))
	end
end

function CharacterEffect.define(spec: Spec)
	local id = spec.id

	local function live(player: Player): boolean
		return player:GetAttribute(CharacterEffect.ACTIVE_ATTRIBUTE) == id and inRound(player)
	end

	-- A fresh character: wait until it is assembled (and its accessories loaded), then apply.
	local function onCharacter(player: Player, character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root then
			return
		end
		local deadline = os.clock() + CharacterEffect.APPEARANCE_TIMEOUT
		while not player:HasAppearanceLoaded() and os.clock() < deadline and character.Parent do
			task.wait(0.1)
		end
		task.wait(0.1) -- let Core put the character back on the map first
		if player.Character == character and character.Parent and live(player) then
			safely(id, "apply", spec.applyTo, character)
		end
	end

	local def = {
		id = id,
		displayName = spec.displayName,
		description = spec.description,
		intensityMultiplier = spec.intensityMultiplier,
	}

	function def.apply(ctx)
		for _, player in ctx.allPlayers() do
			if inRound(player) then
				player:SetAttribute(CharacterEffect.ACTIVE_ATTRIBUTE, id)
				if player.Character then
					safely(id, "apply", spec.applyTo, player.Character)
				end
			end
			ctx.trove:connect(player.CharacterAdded, function(character: Model)
				if live(player) then
					task.spawn(onCharacter, player, character)
				end
			end)
			ctx.trove:connect(player:GetAttributeChangedSignal("InRound"), function()
				if player:GetAttribute("InRound") ~= true and player.Character then
					safely(id, "restore", spec.restore, player.Character)
				end
			end)
		end
	end

	function def.clear(ctx)
		for _, player in ctx.allPlayers() do
			if player:GetAttribute(CharacterEffect.ACTIVE_ATTRIBUTE) == id then
				player:SetAttribute(CharacterEffect.ACTIVE_ATTRIBUTE, nil)
			end
			if player.Character then
				safely(id, "restore", spec.restore, player.Character)
			end
		end
	end

	return def
end

-- Feet-to-root height of a standing humanoid (R15 / R6, any scale).
function CharacterEffect.standHeight(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return 3 * character:GetScale()
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2 * character:GetScale()
end

-- Rescales a character to `target` (absolute scale), keeping its feet on the floor when it grows.
function CharacterEffect.scaleTo(character: Model, target: number)
	local current = character:GetScale()
	if math.abs(current - target) < 1e-3 then
		return
	end
	local rise = if target > current then CharacterEffect.standHeight(character) * (target / current - 1) else 0
	character:ScaleTo(target)
	if rise > 0 then
		character:PivotTo(character:GetPivot() + Vector3.new(0, rise, 0))
	end
end

-- Builds a Giant/Tiny style modifier that multiplies the character scale by `factor`.
function CharacterEffect.scaleModifier(id: string, displayName: string, description: string, factor: number)
	local ORIGINAL = "Mod_OriginalScale"
	return CharacterEffect.define({
		id = id,
		displayName = displayName,
		description = description,
		applyTo = function(character: Model)
			if character:GetAttribute(ORIGINAL) ~= nil then
				return -- already scaled
			end
			local original = character:GetScale()
			character:SetAttribute(ORIGINAL, original)
			CharacterEffect.scaleTo(character, original * factor)
		end,
		restore = function(character: Model)
			local original = character:GetAttribute(ORIGINAL)
			if type(original) ~= "number" then
				return
			end
			character:SetAttribute(ORIGINAL, nil)
			CharacterEffect.scaleTo(character, original)
		end,
	})
end

return CharacterEffect
