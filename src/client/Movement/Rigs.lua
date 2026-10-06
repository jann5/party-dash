-- Tracks every player's character on this client as a "rig" record so the movement modules can
-- attach per-character visuals (pose, trails, dust) to local and remote characters alike.
-- Each rig has a Trove that is cleaned when the character dies, respawns or leaves.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove = require(ReplicatedStorage.Shared.Util.Trove)

export type Rig = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	isLocal: boolean,
	isR15: boolean,
	alive: boolean,
	trove: any,
}

local Rigs = {}

local localPlayer = Players.LocalPlayer
local rigs: { [Model]: Rig } = {}
local addedListeners: { (Rig) -> () } = {}
local started = false

-- fn(rig) runs for every current and future rig.
function Rigs.onAdded(fn: (Rig) -> ())
	table.insert(addedListeners, fn)
	for _, rig in rigs do
		task.spawn(fn, rig)
	end
end

function Rigs.get(character: Instance?): Rig?
	if typeof(character) ~= "Instance" then
		return nil
	end
	return rigs[character :: Model]
end

function Rigs.all(): { [Model]: Rig }
	return rigs
end

function Rigs.localRig(): Rig?
	local character = localPlayer.Character
	return character and rigs[character] or nil
end

local function build(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 15)
	local root = character:WaitForChild("HumanoidRootPart", 15)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	-- CharacterAdded can fire a moment before the model is parented into the workspace.
	local waitedSince = os.clock()
	while not character:IsDescendantOf(workspace) and player.Character == character do
		if os.clock() - waitedSince > 10 then
			return
		end
		task.wait()
	end
	if player.Character ~= character or rigs[character] then
		return
	end
	if humanoid.Health <= 0 then
		return
	end

	local rig: Rig = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		isLocal = player == localPlayer,
		isR15 = humanoid.RigType == Enum.HumanoidRigType.R15,
		alive = true,
		trove = Trove.new(),
	}
	rigs[character] = rig

	local function dispose()
		if not rig.alive then
			return
		end
		rig.alive = false
		rigs[character] = nil
		rig.trove:clean()
	end
	-- These connections live outside the trove (cleaning the trove must not disconnect itself mid-call).
	local connections = {}
	local function disposeAll()
		for _, c in connections do
			c:Disconnect()
		end
		dispose()
	end
	table.insert(connections, humanoid.Died:Connect(disposeAll))
	table.insert(connections, character.Destroying:Connect(disposeAll))
	table.insert(
		connections,
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				disposeAll()
			end
		end)
	)
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function(old)
			if old == character then
				disposeAll()
			end
		end)
	)

	for _, fn in addedListeners do
		task.spawn(fn, rig)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		build(player, character)
	end)
	if player.Character then
		task.spawn(build, player, player.Character)
	end
end

function Rigs.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
end

return Rigs
