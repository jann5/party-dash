-- Party Dash Core: discovers minigames and modifiers and publishes their metadata for the UI.
--   ServerScriptService.Server.Minigames.<Id>  (ModuleScript -> Contracts/Minigame definition)
--   ServerScriptService.Server.Modifiers.<Id>  (ModuleScript -> Contracts/Modifier definition)
-- Metadata goes to ReplicatedStorage.MinigameInfo.<Id> / ModifierInfo.<Id> (Configuration attributes):
--   minigames: DisplayName, Rules, Keys (CSV), Kind, SoloCapable, Duration, Hidden, MinPlayers, Icon, Color
--   (+ Disabled after Registry.MAX_BUILD_FAILURES build errors in a row).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MinigameContract = require(Shared.Contracts.Minigame)
local ModifierContract = require(Shared.Contracts.Modifier)
local Theme = require(Shared.Theme)

local Registry = {}

Registry.MAX_BUILD_FAILURES = 3 -- consecutive build errors before a minigame leaves the pool for this server

Registry.minigames = {} :: { [string]: any }
Registry.modifiers = {} :: { [string]: any }
Registry.minigameOrder = {} :: { string } -- sorted ids (stable roulette order)
Registry.modifierOrder = {} :: { string }

local failures: { [string]: number } = {}

local function ensureFolder(parent: Instance, name: string): Instance
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function publish(folder: Instance, id: string, attributes: { [string]: any })
	local config = folder:FindFirstChild(id)
	if not config then
		config = Instance.new("Configuration")
		config.Name = id
	end
	for key, value in attributes do
		config:SetAttribute(key, value)
	end
	config.Parent = folder
end

-- Requires a ModuleScript safely; returns the definition or nil (with a warning).
local function load(module: ModuleScript, kind: string, validate: (any) -> (boolean, string?)): any
	local ok, def = pcall(require, module)
	if not ok then
		warn(("[Core] %s %s failed to load: %s"):format(kind, module.Name, tostring(def)))
		return nil
	end
	local valid, why = validate(def)
	if not valid then
		warn(("[Core] skipping %s %s: %s"):format(kind, module.Name, tostring(why)))
		return nil
	end
	if def.id ~= module.Name then
		warn(("[Core] %s %s declares id %q; using the module name"):format(kind, module.Name, tostring(def.id)))
	end
	return def
end

function Registry.isHidden(id: string): boolean
	return string.sub(id, 1, 1) == "_"
end

-- Fewest queued players for this game to be offered/picked (definition.minPlayers, default 1).
function Registry.minPlayers(id: string): number
	local def = Registry.minigames[id]
	local n = def and def.minPlayers
	if type(n) == "number" and n == n and n >= 1 then
		return math.floor(n)
	end
	return 1
end

local function minigameAttributes(id: string, def: any): { [string]: any }
	local keys = {}
	for _, k in def.keys do
		table.insert(keys, tostring(k))
	end
	local color = if typeof(def.color) == "Color3" then def.color else Theme.MinigameColors[id]
	return {
		DisplayName = def.displayName,
		Rules = def.rules,
		Keys = table.concat(keys, ","),
		Kind = def.kind,
		SoloCapable = def.soloCapable == true,
		Duration = if type(def.duration) == "number" then def.duration else 0,
		Hidden = Registry.isHidden(id),
		MinPlayers = Registry.minPlayers(id),
		Icon = if type(def.icon) == "string" and def.icon ~= "" then def.icon else "mg_" .. string.lower(id),
		Color = color or Theme.Colors.Purple,
		Disabled = false,
	}
end

function Registry.init(serverFolder: Instance)
	local minigameFolder = ensureFolder(serverFolder, "Minigames")
	local modifierFolder = ensureFolder(serverFolder, "Modifiers")
	local minigameInfo = ensureFolder(ReplicatedStorage, "MinigameInfo")
	local modifierInfo = ensureFolder(ReplicatedStorage, "ModifierInfo")

	for _, child in minigameFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local def = load(child, "minigame", MinigameContract.validate)
			if def then
				local id = child.Name
				Registry.minigames[id] = def
				table.insert(Registry.minigameOrder, id)
				publish(minigameInfo, id, minigameAttributes(id, def))
			end
		end
	end

	for _, child in modifierFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local def = load(child, "modifier", ModifierContract.validate)
			if def then
				local id = child.Name
				Registry.modifiers[id] = def
				table.insert(Registry.modifierOrder, id)
				publish(modifierInfo, id, {
					DisplayName = def.displayName,
					Description = def.description,
				})
			end
		end
	end

	table.sort(Registry.minigameOrder)
	table.sort(Registry.modifierOrder)
	print(
		("[Core] registry: %d minigame(s) [%s], %d modifier(s) [%s]"):format(
			#Registry.minigameOrder,
			table.concat(Registry.minigameOrder, ", "),
			#Registry.modifierOrder,
			table.concat(Registry.modifierOrder, ", ")
		)
	)
end

-- Ids the vote may offer (hidden "_" ids excluded).
function Registry.visibleMinigames(): { string }
	local list = {}
	for _, id in Registry.minigameOrder do
		if not Registry.isHidden(id) then
			table.insert(list, id)
		end
	end
	return list
end

-- The vote pool: visible ids, or the hidden test ids when nothing else is loaded (early development).
function Registry.votePool(): { string }
	local pool = Registry.visibleMinigames()
	if #pool == 0 then
		pool = table.clone(Registry.minigameOrder)
	end
	return pool
end

-- Build bookkeeping: one broken build is retried next time; MAX_BUILD_FAILURES in a row disable the game.
function Registry.reportBuild(id: string, ok: boolean)
	if ok then
		failures[id] = nil
		return
	end
	failures[id] = (failures[id] or 0) + 1
	if failures[id] < Registry.MAX_BUILD_FAILURES then
		return
	end
	warn(("[Core] %s failed to build %d times in a row; removing it from the pool"):format(id, failures[id]))
	Registry.minigames[id] = nil
	local index = table.find(Registry.minigameOrder, id)
	if index then
		table.remove(Registry.minigameOrder, index)
	end
	local info = ReplicatedStorage:FindFirstChild("MinigameInfo")
	local config = info and info:FindFirstChild(id)
	if config then
		config:SetAttribute("Disabled", true)
	end
end

return Registry
