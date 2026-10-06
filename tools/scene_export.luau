-- Exports the BaseParts of a scene to JSON through tools/devserver.py so tools/render_scene.py can draw a preview
-- WITHOUT Studio's 3D viewport (Studio stops rendering 3D while the Mac screen is locked).
-- Usage (Studio MCP execute_luau, any datamodel: Edit, or Server during Play):
--   replace __OUT__ with an absolute output path (e.g. /tmp/pd_scene.json),
--   __ROOT__ with an expression returning the Instance to export (e.g. workspace, workspace.Lobby,
--   workspace:FindFirstChild("LaserTracerMap")), and __CENTER__/__RADIUS__ with a Vector3 and a number to
--   keep only parts whose position is within RADIUS studs of CENTER (use 1e9 for "everything").
-- Terrain water is exported as a flat "sea" entry when Config.SEA_LEVEL exists.
local HttpService = game:GetService("HttpService")
local OUT = "__OUT__"
local root = __ROOT__
local CENTER = __CENTER__
local RADIUS = __RADIUS__

local parts = {}
local function num(x)
	return math.floor(x * 1000 + 0.5) / 1000
end
local function textureOf(p)
	for _, c in p:GetChildren() do
		if c:IsA("Texture") then
			return { key = c.Texture, face = c.Face.Name, color = { c.Color3.R, c.Color3.G, c.Color3.B }, su = c.StudsPerTileU, sv = c.StudsPerTileV, tr = c.Transparency }
		end
	end
	return nil
end
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 0.98 and (d.Position - CENTER).Magnitude <= RADIUS then
		local cf = d.CFrame
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
		local shape = "Block"
		if d:IsA("Part") then
			shape = d.Shape.Name
		elseif d:IsA("WedgePart") then
			shape = "Wedge"
		elseif d:IsA("CornerWedgePart") then
			shape = "CornerWedge"
		elseif d:IsA("MeshPart") then
			shape = "Mesh"
		end
		table.insert(parts, {
			n = d.Name,
			cf = { num(x), num(y), num(z), num(r00), num(r01), num(r02), num(r10), num(r11), num(r12), num(r20), num(r21), num(r22) },
			s = { num(d.Size.X), num(d.Size.Y), num(d.Size.Z) },
			c = { num(d.Color.R), num(d.Color.G), num(d.Color.B) },
			m = d.Material.Name,
			t = num(d.Transparency),
			sh = shape,
			tex = textureOf(d),
		})
	end
end
local okCfg, Config = pcall(function()
	return require(game:GetService("ReplicatedStorage").Shared.Config)
end)
local payload = {
	parts = parts,
	sea = okCfg and Config.SEA_LEVEL or nil,
	center = { CENTER.X, CENTER.Y, CENTER.Z },
}
local body = HttpService:JSONEncode(payload)
HttpService:PostAsync("http://127.0.0.1:8765/save?path=" .. HttpService:UrlEncode(OUT), body)
return ("exported %d parts (%d bytes) to %s"):format(#parts, #body, OUT)
