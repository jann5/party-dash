-- Applies the official Roblox "Cartoony" animation package to the local character's stock Animate
-- script (idle / walk / run / jump / fall / climb / swim). The animations replicate to everyone because
-- the owning client plays them.
--
-- Safety: every package animation is preloaded first; a slot whose asset fails to load keeps its
-- stock animation. R6 characters keep the stock R6 set (the package is R15 only).
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Movement.Assets)

local Rigs = require(script.Parent.Rigs)

type Rig = Rigs.Rig

local Animations = {}

-- Priorities used by the stock Animate script's tracks.
local BASE_LAYER = {
	[Enum.AnimationPriority.Core] = true,
	[Enum.AnimationPriority.Idle] = true,
	[Enum.AnimationPriority.Movement] = true,
}

-- Returns { [slotName] = { animationId, ... } } for the slots whose assets loaded.
local function verifiedPackage(): { [string]: { string } }
	local probes = {}
	local idsBySlot = {}
	for slot, ids in Assets.Animations do
		idsBySlot[slot] = {}
		for _, id in ids do
			local contentId = Assets.animationId(id)
			table.insert(idsBySlot[slot], contentId)
			local probe = Instance.new("Animation")
			probe.AnimationId = contentId
			table.insert(probes, probe)
		end
	end

	local failed: { [string]: boolean } = {}
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(probes, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				failed[contentId] = true
			end
		end)
	end)
	if not ok then
		warn("[Movement] animation preload failed, using the package anyway:", err)
	end
	for _, probe in probes do
		probe:Destroy()
	end

	local result = {}
	for slot, ids in idsBySlot do
		local usable = true
		for _, contentId in ids do
			if failed[contentId] then
				usable = false
			end
		end
		if usable then
			result[slot] = ids
		else
			warn("[Movement] keeping the default animation for slot", slot)
		end
	end
	return result
end

local cachedPackage: { [string]: { string } }? = nil

local function apply(rig: Rig)
	if not rig.isLocal or not rig.isR15 then
		return
	end
	local animate = rig.character:WaitForChild("Animate", 10)
	if not animate or not rig.alive then
		return
	end
	if not cachedPackage then
		cachedPackage = verifiedPackage()
	end
	local package = cachedPackage :: { [string]: { string } }
	if not rig.alive or next(package) == nil then
		return
	end

	local changed = false
	for slot, ids in package do
		local holder = animate:FindFirstChild(slot)
		if holder and holder:IsA("StringValue") then
			local index = 0
			for _, child in holder:GetChildren() do
				if child:IsA("Animation") then
					index += 1
					local id = ids[math.min(index, #ids)]
					if child.AnimationId ~= id then
						child.AnimationId = id
						changed = true
					end
				end
			end
		end
	end
	if not changed or not animate:IsA("BaseScript") then
		return
	end

	-- Restart Animate so it rebuilds its tables from the new ids. Only the stock base-layer tracks are
	-- stopped (never Action tracks such as our slide pose or emotes).
	animate.Enabled = false
	local animator = rig.humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			if BASE_LAYER[track.Priority] then
				track:Stop(0.15)
			end
		end
	end
	animate.Enabled = true
end

function Animations.start()
	Rigs.onAdded(function(rig)
		local ok, err = pcall(apply, rig)
		if not ok then
			warn("[Movement] could not apply the animation package:", err)
		end
	end)
end

return Animations
