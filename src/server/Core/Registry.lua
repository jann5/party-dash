-- Party Dash Core: discovers minigames and modifiers and publishes their metadata for the UI.
--   ServerScriptService.Server.Minigames.<Id>  (ModuleScript -> Contracts/Minigame definition)
--   ServerScriptService.Server.Modifiers.<Id>  (ModuleScript -> Contracts/Modifier definition)
-- Metadata goes to ReplicatedStorage.MinigameInfo.<Id> / ModifierInfo.<Id> (Configuration attributes).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MinigameContract = require(Shared.Contracts.Minigame)
local ModifierContract = require(Shared.Contracts.Modifier)

local Registry = {}

Registry.minigames = {} :: { [string]: any }
Registry.modifiers = {} :: { [string]: any }
Registry.minigameOrder = {} :: { string } -- sorted ids (stable roulette order)
Registry.modifierOrder = {} :: { string }

local function ensureFolder(parent: Instance, name: string): Instance
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function infoFolder(name: string): Instance
	local folder = ReplicatedStorage:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = ReplicatedStorage
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

function Registry.init(serverFolder: Instance)
	local minigameFolder = ensureFolder(serverFolder, "Minigames")
	local modifierFolder = ensureFolder(serverFolder, "Modifiers")
	local minigameInfo = infoFolder("MinigameInfo")
	local modifierInfo = infoFolder("ModifierInfo")

	for _, child in minigameFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local def = load(child, "minigame", MinigameContract.validate)
			if def then
				local id = child.Name
				Registry.minigames[id] = def
				table.insert(Registry.minigameOrder, id)
				local keys = {}
				for _, k in def.keys do
					table.insert(keys, tostring(k))
				end
				publish(minigameInfo, id, {
					DisplayName = def.displayName,
					Rules = def.rules,
					Keys = table.concat(keys, ","),
					Kind = def.kind,
					SoloCapable = def.soloCapable == true,
					Duration = if type(def.duration) == "number" then def.duration else 0,
					Hidden = string.sub(id, 1, 1) == "_",
				})
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

function Registry.isHidden(id: string): boolean
	return string.sub(id, 1, 1) == "_"
end

-- Ids the roulette may land on (hidden "_" ids excluded unless nothing else exists).
function Registry.visibleMinigames(): { string }
	local list = {}
	for _, id in Registry.minigameOrder do
		if not Registry.isHidden(id) then
			table.insert(list, id)
		end
	end
	return list
end

function Registry.disableMinigame(id: string)
	Registry.minigames[id] = nil
	local index = table.find(Registry.minigameOrder, id)
	if index then
		table.remove(Registry.minigameOrder, index)
	end
end

return Registry
