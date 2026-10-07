-- Body measurements shared by the server (Forgive hit judging) and the client (pose, effects).
-- Rig-aware (R15 / R6) and scale-aware: everything is read from the live parts and Humanoid.HipHeight.
--   R15: root center = feet + HipHeight + root.Size.Y / 2
--   R6:  root center = feet + leg length + HipHeight (an extra offset, normally 0) + root.Size.Y / 2
local Body = {}

function Body.isR15(humanoid: Humanoid): boolean
	return humanoid.RigType == Enum.HumanoidRigType.R15
end

-- Distance from the bottom of the root part to the soles while standing.
function Body.legLength(character: Model, humanoid: Humanoid): number
	if Body.isR15(humanoid) then
		return humanoid.HipHeight
	end
	local leg = character:FindFirstChild("Left Leg") or character:FindFirstChild("Right Leg")
	local length = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
	return length + humanoid.HipHeight
end

-- Distance from the root part's center down to the soles while standing.
function Body.rootToFeet(character: Model, humanoid: Humanoid, root: BasePart): number
	return root.Size.Y / 2 + Body.legLength(character, humanoid)
end

-- Live pieces of a character, or nil when it has no Humanoid / HumanoidRootPart yet.
function Body.parts(character: Model?): (Humanoid?, BasePart?)
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

-- World Y of the soles right now (standing pose), or nil.
function Body.feetY(character: Model?): number?
	local humanoid, root = Body.parts(character)
	if not humanoid or not root then
		return nil
	end
	return root.Position.Y - Body.rootToFeet(character :: Model, humanoid, root)
end

return Body
