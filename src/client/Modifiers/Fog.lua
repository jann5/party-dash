--!strict
-- FOG (client): thick pastel fog, about 45 studs of visibility. Lighting.Fog* is ignored while an
-- Atmosphere exists, so the Atmosphere is taken out locally and put back exactly as it was.
local Lighting = game:GetService("Lighting")

local FOG_COLOR = Color3.fromRGB(214, 214, 236)
local FOG_START = 6
local FOG_END = 45

return {
	enable = function(): () -> ()
		local saved = {
			start = Lighting.FogStart,
			finish = Lighting.FogEnd,
			color = Lighting.FogColor,
		}
		local hidden: { Instance } = {}
		local function hide(child: Instance)
			if child:IsA("Atmosphere") then
				table.insert(hidden, child)
				child.Parent = nil
			end
		end
		for _, child in Lighting:GetChildren() do
			hide(child)
		end
		-- If the server (re)adds an Atmosphere mid-round, keep the fog readable.
		local conn = Lighting.ChildAdded:Connect(function(child)
			task.defer(hide, child)
		end)

		Lighting.FogColor = FOG_COLOR
		Lighting.FogStart = FOG_START
		Lighting.FogEnd = FOG_END

		return function()
			conn:Disconnect()
			Lighting.FogStart = saved.start
			Lighting.FogEnd = saved.finish
			Lighting.FogColor = saved.color
			for _, atmosphere in hidden do
				atmosphere.Parent = Lighting
			end
		end
	end,
}
