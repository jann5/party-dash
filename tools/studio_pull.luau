-- Pulls the repo's src/ tree into Roblox Studio (Edit datamodel) through tools/devserver.py.
-- Usage: replace __ROOT__ with the absolute repo (or worktree) path, then run via the Studio MCP
-- execute_luau tool with datamodel_type = "Edit". Studio must NOT be in Play mode.
-- The managed containers (ReplicatedStorage.Shared, ServerScriptService.Server,
-- StarterPlayerScripts.Client) are replaced wholesale. The legacy Spin objects are moved
-- (disabled) into ServerStorage.LegacyBackup the first time this runs.
local ROOT = "__ROOT__"
local Http = game:GetService("HttpService")
Http.HttpEnabled = true

local backup = game.ServerStorage:FindFirstChild("LegacyBackup")
if not backup then
	backup = Instance.new("Folder")
	backup.Name = "LegacyBackup"
	backup.Parent = game.ServerStorage
end
local legacy = {
	game.ServerScriptService:FindFirstChild("GameServer"),
	game.ReplicatedStorage:FindFirstChild("SpinShared"),
	game.ReplicatedStorage:FindFirstChild("Remotes"),
	game.ReplicatedStorage:FindFirstChild("GameState"),
	game.StarterPlayer.StarterPlayerScripts:FindFirstChild("SpinnerClient"),
	game.StarterPlayer.StarterPlayerScripts:FindFirstChild("JumpFx"),
	game.StarterPlayer.StarterPlayerScripts:FindFirstChild("GameUI"),
	workspace:FindFirstChild("Arena"),
}
for _, inst in legacy do
	if inst then
		for _, d in inst:GetDescendants() do
			if d:IsA("BaseScript") then
				d.Disabled = true
			end
		end
		if inst:IsA("BaseScript") then
			inst.Disabled = true
		end
		inst.Parent = backup
	end
end

local tree = Http:JSONDecode(Http:GetAsync("http://127.0.0.1:8765/tree?root=" .. Http:UrlEncode(ROOT), true))
local count = 0
local function make(node, parent)
	local inst = Instance.new(node.class)
	inst.Name = node.name
	if node.source then
		inst.Source = node.source
		count += 1
	end
	for _, c in node.children do
		make(c, inst)
	end
	inst.Parent = parent
	return inst
end
for _, entry in tree do
	local parent = game
	local parts = string.split(entry.dest, "/")
	for i = 1, #parts - 1 do
		parent = parent:FindFirstChild(parts[i]) or game:GetService(parts[i])
	end
	local old = parent:FindFirstChild(parts[#parts])
	if old then
		old:Destroy()
	end
	make(entry.node, parent)
end
return ("synced %d scripts from %s"):format(count, ROOT)
