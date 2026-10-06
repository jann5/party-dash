-- Builds the loading screen (ART_BIBLE 8.8): full-screen key art over a sky gradient, a darkened bottom, the logo
-- top-center (~46% wide), and a design-pixel canvas holding the tip pill, the status line and the progress pill
-- (dark track, yellow -> orange fill with scrolling diagonal stripes, a bomb riding the leading edge).
local Kit = require(script.Parent.Kit)

local View = {}

local LOGO_ASPECT = 1024 / 541 -- logo.png
local LOGO_TOP = 0.045 -- logo top edge, fraction of the screen height
local STRIPE_TILE = 44

View.LOGO_TOP = LOGO_TOP
View.STRIPE_TILE = STRIPE_TILE

export type View = {
	gui: ScreenGui,
	ui: Frame,
	background: ImageLabel,
	backgroundZoom: UIScale,
	logo: ImageLabel,
	logoScale: UIScale,
	groove: ImageLabel,
	fill: CanvasGroup,
	stripes: ImageLabel,
	runner: ImageLabel,
	status: TextLabel,
	tip: TextLabel,
	tipStroke: UIStroke,
}

function View.build(ids: { [string]: string }, playerGui: Instance): View
	local new = Kit.new

	local gui = new("ScreenGui", {
		Name = "PD_Loading",
		DisplayOrder = 100,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	-- sky gradient first, so the screen already looks finished before the key art streams in
	local backdrop = new("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Kit.WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	Kit.gradient(backdrop, ColorSequence.new(Kit.CYAN, Kit.BLUE), 90)
	local background = new("ImageLabel", {
		Name = "Background",
		BackgroundTransparency = 1,
		Image = ids.bg,
		ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = 1, -- revealed once streamed
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = backdrop,
	})
	local backgroundZoom = new("UIScale", { Parent = background })

	-- darkens the bottom so the bar and the tips read over the bright sea
	local bottomShade = new("Frame", {
		Name = "BottomShade",
		BackgroundColor3 = Kit.INK,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.42),
		ZIndex = 2,
		Parent = backdrop,
	})
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 0.62),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
		Parent = bottomShade,
	})

	local logo = new("ImageLabel", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Image = ids.logo,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, LOGO_TOP),
		Size = UDim2.fromScale(0.46, 0.43),
		Rotation = -1.5,
		ZIndex = 5,
		Parent = gui,
	})
	local logoScale = new("UIScale", { Scale = 0.6, Parent = logo })

	-- design canvas: children use 1080p pixels, a UIScale maps them to the real screen (same rule as UIKit)
	local ui = new("Frame", {
		Name = "UI",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = gui,
	})
	local fitScale = new("UIScale", { Parent = ui })

	-- progress pill
	local bar = new("Frame", {
		Name = "Bar",
		BackgroundColor3 = Kit.PANEL_DEEP,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -54),
		Size = UDim2.new(0.6, 0, 0, 54),
		ZIndex = 10,
		Parent = ui,
	})
	Kit.corner(bar, Kit.PILL)
	Kit.border(bar, 4)
	local groove = new("ImageLabel", {
		Name = "Groove",
		BackgroundTransparency = 1,
		Image = ids.stripes,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(STRIPE_TILE, STRIPE_TILE),
		ImageTransparency = 0.94,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = bar,
	})
	Kit.corner(groove, Kit.PILL)
	local inner = new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, -12),
		ZIndex = 11,
		Parent = bar,
	})
	-- a CanvasGroup, so its rounded corners also clip the moving stripes
	local fill = new("CanvasGroup", {
		Name = "Fill",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 11,
		Parent = inner,
	})
	Kit.corner(fill, Kit.PILL)
	local fillColor = new("Frame", {
		Name = "Color",
		BackgroundColor3 = Kit.WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
		Parent = fill,
	})
	Kit.gradient(fillColor, ColorSequence.new(Kit.YELLOW, Kit.ORANGE), 0)
	local stripes = new("ImageLabel", {
		Name = "Stripes",
		BackgroundTransparency = 1,
		Image = ids.stripes,
		ImageTransparency = 0.7,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(STRIPE_TILE, STRIPE_TILE),
		Position = UDim2.fromOffset(-STRIPE_TILE, 0), -- scrolls to 0 and repeats (one tile = seamless)
		Size = UDim2.new(1, STRIPE_TILE, 1, 0),
		ZIndex = 12,
		Parent = fill,
	})
	Kit.gloss(fill, 13, 0.5)
	local runner = new("ImageLabel", {
		Name = "Runner",
		BackgroundTransparency = 1,
		Image = ids.bomb,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0.58),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(84, 84),
		ZIndex = 15,
		Parent = inner,
	})

	local status = new("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		FontFace = Kit.FONT_BODY,
		TextSize = 26,
		TextColor3 = Kit.WHITE,
		Text = "Loading assets... 0%",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.new(0.6, 0, 0, 32),
		ZIndex = 10,
		Parent = ui,
	})
	Kit.outline(status, 2.5)

	local tipPill = new("Frame", {
		Name = "TipPill",
		BackgroundColor3 = Kit.PANEL_DEEP,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -164),
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 10,
		Parent = ui,
	})
	Kit.corner(tipPill, Kit.PILL)
	Kit.border(tipPill, 3)
	new("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 26), Parent = tipPill })
	local tip = new("TextLabel", {
		Name = "Tip",
		BackgroundTransparency = 1,
		FontFace = Kit.FONT_BODY,
		TextSize = 26,
		TextColor3 = Kit.WHITE,
		RichText = true,
		Text = "",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 11,
		Parent = tipPill,
	})
	local tipStroke = Kit.outline(tip, 2)

	-- design scale + logo size (~46% of the width, capped by height so phones keep room for the bar)
	local function layout()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local s = math.clamp(size.Y / 1080, 0.55, 1.3)
		fitScale.Scale = s
		ui.Size = UDim2.fromScale(1 / s, 1 / s)
		local w = math.min(0.46, 0.42 * size.Y * LOGO_ASPECT / size.X)
		logo.Size = UDim2.fromScale(w, w * size.X / (size.Y * LOGO_ASPECT))
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	gui.Parent = playerGui
	layout()

	return {
		gui = gui,
		ui = ui,
		background = background,
		backgroundZoom = backgroundZoom,
		logo = logo,
		logoScale = logoScale,
		groove = groove,
		fill = fill,
		stripes = stripes,
		runner = runner,
		status = status,
		tip = tip,
		tipStroke = tipStroke,
	}
end

return View
