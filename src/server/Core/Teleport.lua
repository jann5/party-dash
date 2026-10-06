-- Party Dash Core: moving characters around safely (shared by Core, Context and Solo).
local Teleport = {}

export type CharacterParts = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
}

-- Returns the live character pieces or nil (no character, no root, or dead).
function Teleport.parts(player: Player): CharacterParts?
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return nil
	end
	return { character = character, humanoid = humanoid, root = root }
end

-- Height of the root center above the floor when standing.
local function rootHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2 + 0.2
	end
	return 3.2
end

-- A flat (yaw-only) CFrame at `position` looking toward `target`.
function Teleport.facing(position: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	if flat.Magnitude < 0.05 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

-- Yaw-only version of a CFrame (keeps position and heading, drops tilt).
function Teleport.flatten(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		return CFrame.new(cf.Position)
	end
	return CFrame.lookAt(cf.Position, cf.Position + flat.Unit)
end

-- Puts the player's character standing on `floor` (a CFrame on the floor surface; its heading is kept).
-- anchor: true/false sets HumanoidRootPart.Anchored, nil leaves it unchanged.
function Teleport.to(player: Player, floor: CFrame, anchor: boolean?): boolean
	local parts = Teleport.parts(player)
	if not parts then
		return false
	end
	local root = parts.root
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	parts.character:PivotTo(Teleport.flatten(floor) + Vector3.new(0, rootHeight(parts.humanoid, root), 0))
	if anchor ~= nil then
		root.Anchored = anchor
	end
	return true
end

function Teleport.setAnchored(player: Player, anchored: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = anchored
		if not anchored then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

-- Floor CFrame on top of a spawn part (with an optional ring offset when several players share it).
function Teleport.spawnFloor(spawnPart: BasePart, layer: number?, facingTarget: Vector3?): CFrame
	local top = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2, 0)
	local k = layer or 0
	if k > 0 then
		local angle = k * 2.399 -- golden angle spreads stacked players nicely
		top += Vector3.new(math.cos(angle), 0, math.sin(angle)) * (2.5 + k * 0.4)
	end
	if facingTarget then
		local flatDist = Vector3.new(facingTarget.X - top.X, 0, facingTarget.Z - top.Z).Magnitude
		if flatDist > 2 then
			return Teleport.facing(top, facingTarget)
		end
	end
	return Teleport.flatten(spawnPart.CFrame - spawnPart.Position + top)
end

return Teleport
