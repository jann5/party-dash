-- Party Dash Core: tiny helpers for building cartoon geometry out of Parts.
local Build = {}

-- Anchored, smooth part. `props` may set any Part property; Parent is applied last.
function Build.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- Vertical cylinder whose TOP face is at `top` (a world position), so stacking layers is easy.
function Build.disc(parent: Instance, name: string, top: Vector3, height: number, radius: number, color: Color3): Part
	return Build.part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Parent = parent,
	})
end

-- Vertical cylinder centered at `center`.
function Build.pillar(
	parent: Instance,
	name: string,
	center: Vector3,
	height: number,
	radius: number,
	color: Color3
): Part
	return Build.part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Parent = parent,
	})
end

function Build.ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3): Part
	return Build.part({
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(center),
		Color = color,
		Parent = parent,
	})
end

-- Squashed/stretched sphere (SpecialMesh); collision stays a box, so use it for decoration.
function Build.ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3): Part
	local p = Build.part({ Name = name, Size = size, CFrame = cf, Color = color, Parent = parent })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A fluffy cloud: a cluster of white balls around `center`.
function Build.cloud(parent: Instance, center: Vector3, scale: number, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Cloud"
	local puffs = rng:NextInteger(4, 6)
	for i = 1, puffs do
		local t = (i - 1) / math.max(puffs - 1, 1) - 0.5
		local d = scale * rng:NextNumber(0.7, 1.15) * (1 - math.abs(t) * 0.6)
		local offset =
			Vector3.new(t * scale * 2.2, rng:NextNumber(-0.1, 0.25) * scale, rng:NextNumber(-0.3, 0.3) * scale)
		local puff = Build.ball(model, "Puff", center + offset, d, Color3.fromRGB(255, 255, 255))
		puff.CastShadow = false
	end
	model.Parent = parent
	return model
end

-- Makes every BasePart under `root` purely decorative (no collisions/touches/queries).
function Build.decorative(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
end

-- A SurfaceGui text sign on `part`'s face.
function Build.sign(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	color: Color3,
	font: Font,
	pixelsPerStud: number?
): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 30
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.92, 0.84)
	label.Position = UDim2.fromScale(0.04, 0.08)
	label.FontFace = font
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(30, 25, 50)
	stroke.Parent = label
	return label
end

return Build
