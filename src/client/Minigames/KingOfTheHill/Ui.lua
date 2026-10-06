--!strict
-- King of the Hill (client): tiny GUI builders in the Party Dash cartoon style.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared").Theme)

local Ui = {}

function Ui.new(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(parent: Instance, radius: UDim?): UICorner
	return Ui.new("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

function Ui.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return Ui.new("UIStroke", {
		Thickness = thickness or Theme.StrokeThickness,
		Color = color or Theme.Colors.Ink,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- Big outlined cartoon text that scales with its box.
function Ui.label(parent: Instance, name: string, text: string, maxSize: number?): TextLabel
	local label = Ui.new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = Theme.FontFace,
		Text = text,
		TextColor3 = Theme.Colors.White,
		TextScaled = true,
		TextStrokeTransparency = 1,
	}, parent)
	Ui.new("UITextSizeConstraint", { MaxTextSize = maxSize or 40, MinTextSize = 8 }, label)
	Ui.new("UIStroke", {
		Thickness = 2.5,
		Color = Theme.Colors.Ink,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	return label
end

return Ui
