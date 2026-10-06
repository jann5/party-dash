--!strict
-- King of the Hill (client): purely local juice for every King of the Hill arena (keyed by its map Model).
--   * two neon rings that keep pulsing outward from the golden zone edge
--   * the zone fill and the light beam breathe
--   * the leader's crown (BillboardGui tagged "KOTH_Crown") bobs and wiggles
-- Nothing here is replicated: these parts live only on this client inside the server's map Model,
-- so they disappear together with the map.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local WorldFx = {}

local PULSE_PERIOD = 1.4
local PULSE_GROWTH = 0.45

type Arena = {
	map: Model,
	fill: BasePart,
	beam: BasePart?,
	rings: { BasePart },
}

local arenas: { [Model]: Arena } = {}

local function makeRing(parent: Instance): BasePart
	local ring = Instance.new("Part")
	ring.Name = "LocalPulse"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Size = Vector3.new(0.1, 1, 1)
	ring.Transparency = 1
	ring.Parent = parent
	return ring
end

local function track(map: Instance)
	if not map:IsA("Model") or arenas[map] then
		return
	end
	task.spawn(function()
		local zone = map:WaitForChild("Zone", 10)
		local fill = zone and zone:WaitForChild("ZoneFill", 10)
		if not zone or not fill or not fill:IsA("BasePart") or not map.Parent then
			return
		end
		local beam = zone:FindFirstChild("ZoneBeam")
		arenas[map] = {
			map = map,
			fill = fill,
			beam = if beam and beam:IsA("BasePart") then beam else nil,
			rings = { makeRing(zone), makeRing(zone) },
		}
	end)
end

local function untrack(map: Instance)
	local arena = arenas[map :: Model]
	if arena then
		for _, ring in arena.rings do
			ring:Destroy()
		end
		arenas[map :: Model] = nil
	end
end

local function step()
	local now = os.clock()
	for map, arena in arenas do
		if not map.Parent or not arena.fill.Parent then
			untrack(map)
			continue
		end
		local radius = map:GetAttribute("ZoneRadius")
		radius = if type(radius) == "number" and radius > 0 then radius else arena.fill.Size.Y / 2
		local base = arena.fill.CFrame
		for i, ring in arena.rings do
			local phase = ((now / PULSE_PERIOD) + (i - 1) * 0.5) % 1
			local d = radius * 2 * (1 + PULSE_GROWTH * phase)
			ring.Size = Vector3.new(0.1, d, d)
			ring.CFrame = base + Vector3.new(0, 0.12 + 0.02 * i, 0)
			ring.Color = arena.fill.Color:Lerp(Color3.new(1, 1, 1), 0.35)
			ring.Transparency = 0.25 + 0.75 * phase
		end
		arena.fill.Transparency = 0.22 + 0.12 * (0.5 + 0.5 * math.sin(now * 3.2))
		if arena.beam then
			arena.beam.Transparency = 0.86 + 0.06 * (0.5 + 0.5 * math.sin(now * 2.1))
		end
	end

	for _, crown in CollectionService:GetTagged("KOTH_Crown") do
		if crown:IsA("BillboardGui") then
			crown.StudsOffset = Vector3.new(0, 2.9 + 0.3 * math.sin(now * 3), 0)
			local icon = crown:FindFirstChild("Icon")
			if icon and icon:IsA("GuiObject") then
				icon.Rotation = 9 * math.sin(now * 2.2)
			end
			local halo = crown:FindFirstChild("Halo")
			if halo and halo:IsA("GuiObject") then
				halo.BackgroundTransparency = 0.55 + 0.2 * (0.5 + 0.5 * math.sin(now * 4))
			end
		end
	end
end

function WorldFx.start()
	for _, map in CollectionService:GetTagged("KOTH_Map") do
		track(map)
	end
	CollectionService:GetInstanceAddedSignal("KOTH_Map"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("KOTH_Map"):Connect(untrack)
	RunService.RenderStepped:Connect(step)
end

return WorldFx
