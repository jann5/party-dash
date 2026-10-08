-- Tiny styling kit for the loading screen. It mirrors Shared.Theme and the UIKit look (ink outlines, gradients,
-- gloss) without requiring them: this runs from ReplicatedFirst, before Shared has replicated.
local TweenService = game:GetService("TweenService")

local Kit = {}

-- Palette and fonts (same values as Shared.Theme)
Kit.INK = Color3.fromRGB(22, 18, 36)
Kit.PANEL_DEEP = Color3.fromRGB(26, 23, 40)
Kit.WHITE = Color3.new(1, 1, 1)
Kit.YELLOW = Color3.fromRGB(255, 211, 38)
Kit.ORANGE = Color3.fromRGB(255, 138, 28)
Kit.BLUE = Color3.fromRGB(36, 122, 246)
Kit.BLUE_DARK = Color3.fromRGB(18, 72, 182)
Kit.CYAN = Color3.fromRGB(28, 196, 245)
Kit.FONT_DISPLAY = Font.new("rbxasset://fonts/families/FredokaOne.json")
Kit.FONT_BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
Kit.PILL = UDim.new(0.5, 0)

-- Kit.new("Frame", { Size = ..., Parent = ... }): properties first, Parent last.
function Kit.new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	inst.Parent = parent
	return inst
end

function Kit.corner(parent: Instance, radius: UDim)
	Kit.new("UICorner", { CornerRadius = radius, Parent = parent })
end

-- Ink border around a frame.
function Kit.border(parent: Instance, thickness: number)
	Kit.new("UIStroke", {
		Thickness = thickness,
		Color = Kit.INK,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Ink outline around text.
function Kit.outline(label: Instance, thickness: number): UIStroke
	return Kit.new("UIStroke", {
		Thickness = thickness,
		Color = Kit.INK,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = label,
	})
end

function Kit.gradient(parent: Instance, colors: ColorSequence, rotation: number)
	Kit.new("UIGradient", { Color = colors, Rotation = rotation, Parent = parent })
end

-- White sheen over the top half (`from` = transparency at the top edge).
function Kit.gloss(parent: Instance, zindex: number, from: number): Frame
	local g = Kit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Kit.WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0.46),
		ZIndex = zindex,
		Parent = parent,
	})
	Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(from, 1), Parent = g })
	return g
end

-- Lighter (t > 0) or darker (t < 0) version of a color.
function Kit.shade(c: Color3, t: number): Color3
	return c:Lerp(t > 0 and Kit.WHITE or Color3.new(), math.abs(t))
end

function Kit.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?): Tween
	local info = TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

-- Endless tween (idle motion). It stops by itself when the instance is destroyed.
function Kit.loop(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle, reverses: boolean)
	TweenService:Create(inst, TweenInfo.new(t, style, Enum.EasingDirection.InOut, -1, reverses), props):Play()
end

-- Fades every visible piece under `root` to nothing.
function Kit.fadeOut(root: Instance, t: number)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			local goal = {}
			if d.BackgroundTransparency < 1 then
				goal.BackgroundTransparency = 1
			end
			if d:IsA("ImageLabel") or d:IsA("ImageButton") then
				goal.ImageTransparency = 1
			elseif d:IsA("TextLabel") or d:IsA("TextButton") then
				goal.TextTransparency = 1
			elseif d:IsA("CanvasGroup") then
				goal.GroupTransparency = 1
			end
			if next(goal) then
				Kit.tween(d, t, goal)
			end
		elseif d:IsA("UIStroke") then
			Kit.tween(d, t, { Transparency = 1 })
		end
	end
end

return Kit
