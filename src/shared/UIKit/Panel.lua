--!nonstrict
-- UIKit modal panel (ART_BIBLE 8.4): dimmed background, dark body with a subtle stud pattern, colored header bar
-- with a big title + an icon overlapping its left edge, and a big red X overlapping the top-right corner.
-- Only one panel is open at a time (opening one closes the other). Escape / X / tapping the dim closes it.
--
--   local panel = UIKit.panel({ name = "Shop", title = "Shop", icon = "shop", color = "Green",
--                               size = Vector2.new(1100, 680), onClose = function() end })
--   -- fill panel.body (a Frame, design px) with your content
--   panel.open() / panel.close() / panel.toggle() / panel.isOpen()
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Core = require(script.Parent.Core)
local Style = require(script.Parent.Style)

local C = Style.Colors

local Panel = {}

local current = nil -- the open panel api
local opened = Instance.new("BindableEvent") -- fires (name, isOpen)
Panel.Changed = opened.Event

function Panel.current()
	return current
end

function Panel.closeAll()
	if current then
		current.close()
	end
end

function Panel.new(props: { [string]: any })
	local size: Vector2 = props.size or Vector2.new(1000, 640)
	local variant = Style.Variants[props.color or "Green"] or Style.Variants.Green
	local headerH = props.headerHeight or 96
	local gui, root = Core.screen("PD_Panel_" .. (props.name or "Panel"), props.layer or "Panel")
	gui.Enabled = false

	local dim = Core.new("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = root,
	})
	dim:SetAttribute("PD_NoClick", true)

	local frame = Core.new("Frame", {
		Name = "Window",
		BackgroundColor3 = C.White,
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		ZIndex = 10,
		Parent = root,
	})
	Core.corner(frame, Style.Corner.Panel)
	Core.border(frame, Style.Stroke.Panel)
	Core.gradient(frame, { C.Panel, C.PanelDeep }, 90)
	local fit = Core.new("UIScale", { Name = "Fit", Parent = frame })
	local pop = Core.new("UIScale", { Name = "PopScale", Parent = frame })
	pop.Scale = 1
	-- keep the window inside the screen on small phones
	local function refit()
		local rs = root.AbsoluteSize
		local s = 1
		if rs.X > 0 and rs.Y > 0 then
			-- root is in design px already (UIScale applied above it): compare in design px
			local designW = rs.X / math.max(0.01, Core.scale())
			local designH = rs.Y / math.max(0.01, Core.scale())
			s = math.min(1, (designW - 40) / size.X, (designH - 40) / (size.Y + 40))
		end
		fit.Scale = math.max(0.5, s)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	task.defer(refit)

	-- subtle studs pattern
	local pattern = Core.new("ImageLabel", {
		Name = "Pattern",
		BackgroundTransparency = 1,
		Image = Assets.Textures.studs or "",
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(40, 40),
		ImageTransparency = 0.93,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = frame,
	})
	Core.corner(pattern, Style.Corner.Panel)

	local header = Core.new("Frame", {
		Name = "Header",
		BackgroundColor3 = C.White,
		Size = UDim2.new(1, 0, 0, headerH),
		ZIndex = 11,
		Parent = frame,
	})
	Core.corner(header, Style.Corner.Panel)
	Core.border(header, Style.Stroke.Panel)
	if props.rainbow then
		Core.gradient(header, { C.Red, C.Orange, C.Yellow, C.Green, C.Cyan, C.Blue, C.Purple }, 0)
	else
		Core.gradient(header, { Style.lighten(variant[1], 0.12), variant[1], Style.darken(variant[1], 0.1) }, 90)
	end
	-- square off the header's bottom corners
	local squarer = Core.new("Frame", {
		Name = "Squarer",
		BackgroundColor3 = Style.darken(variant[1], 0.1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -20),
		ZIndex = 11,
		Parent = header,
	})
	if props.rainbow then
		Core.gradient(squarer, { C.Red, C.Orange, C.Yellow, C.Green, C.Cyan, C.Blue, C.Purple }, 0)
		squarer.BackgroundColor3 = C.White
	end
	local stripes = Assets.Textures.stripes_diag
	if stripes and stripes ~= "" then
		Core.new("ImageLabel", {
			Name = "Stripes",
			BackgroundTransparency = 1,
			Image = stripes,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(96, 96),
			ImageTransparency = 0.85,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 12,
			Parent = header,
		})
	end
	local hgloss = Core.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -10, 0.4, 0),
		Position = UDim2.fromOffset(5, 4),
		ZIndex = 12,
		Parent = header,
	})
	Core.corner(hgloss, Style.Corner.Panel)
	Core.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Parent = hgloss,
	})
	local iconW = 0
	if props.icon then
		iconW = 120
		Core.icon(header, props.icon, {
			size = UDim2.fromOffset(118, 118),
			position = UDim2.new(0, 46, 0.42, 0),
			rotation = -6,
			zindex = 16,
		})
	end
	local title = Core.text(header, {
		text = props.title or "",
		size = 56,
		drop = true,
		xalign = "left",
		frameSize = UDim2.new(1, -(iconW + 140), 1, 0),
		position = UDim2.fromOffset(iconW + 24, 0),
		zindex = 15,
	})

	-- big red X
	local close = Core.button(frame, {
		name = "Close",
		size = Vector2.new(72, 72),
		color = "Red",
		corner = UDim.new(0, 12),
		position = UDim2.new(1, 18, 0, -18),
		anchor = Vector2.new(1, 0),
		zindex = 30,
		text = "X",
		font = "hype",
		textSize = 50,
	})

	local body = Core.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -36, 1, -(headerH + 28)),
		Position = UDim2.fromOffset(18, headerH + 12),
		ZIndex = 12,
		Parent = frame,
	})

	local api =
		{ gui = gui, root = root, frame = frame, body = body, header = header, title = title, name = props.name }
	local isOpen = false
	local actionName = "PD_ClosePanel_" .. (props.name or "Panel")

	function api.isOpen()
		return isOpen
	end
	function api.setTitle(t: string)
		title.Text = t
	end
	function api.close()
		if not isOpen then
			return
		end
		isOpen = false
		if current == api then
			current = nil
		end
		ContextActionService:UnbindAction(actionName)
		Core.tween(dim, 0.15, { BackgroundTransparency = 1 })
		Core.tween(pop, 0.15, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.15, function()
			if not isOpen then
				gui.Enabled = false
			end
		end)
		opened:Fire(props.name, false)
		if props.onClose then
			task.spawn(props.onClose)
		end
	end
	function api.open()
		if isOpen then
			return
		end
		if current and current ~= api then
			current.close()
		end
		current = api
		isOpen = true
		gui.Enabled = true
		refit()
		dim.BackgroundTransparency = 1
		Core.tween(dim, 0.15, { BackgroundTransparency = 0.45 })
		pop.Scale = 0.85
		frame.Position = UDim2.new(0.5, 0, 0.52, 20)
		Core.tween(pop, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		Core.tween(frame, 0.25, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
		Core.sound("UiOpen")
		ContextActionService:BindAction(actionName, function(_, state)
			if state == Enum.UserInputState.Begin then
				api.close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
		opened:Fire(props.name, true)
		if props.onOpen then
			task.spawn(props.onOpen)
		end
	end
	function api.toggle()
		if isOpen then
			api.close()
		else
			api.open()
		end
	end
	close.button.Activated:Connect(api.close)
	dim.Activated:Connect(api.close)
	return api
end

--[[
Tabs on the left side of a panel body (ref5): icon + label, the selected one scales up with a glow.
tabs = { { id = "Featured", icon = "sale_tag", label = "Featured" }, ... }
Returns { frame, content (Frame to the right), select(id), onSelect: Signal(id) }
]]
function Panel.sideTabs(body: Frame, tabs: { { [string]: any } }, width: number?)
	local w = width or 140
	local side = Core.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, w, 1, 0),
		ZIndex = 13,
		Parent = body,
	})
	Core.list(side, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local content = Core.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(w + 14), 1, 0),
		Position = UDim2.fromOffset(w + 14, 0),
		ZIndex = 13,
		ClipsDescendants = true,
		Parent = body,
	})
	local selectedEvent = Instance.new("BindableEvent")
	local entries = {}
	local api = { frame = side, content = content, onSelect = selectedEvent.Event }
	function api.select(id: string)
		for tid, e in entries do
			local on = tid == id
			e.glow.Visible = on
			Core.tween(e.scale, 0.15, { Scale = on and 1.12 or 1 }, Enum.EasingStyle.Back)
			e.label.TextColor3 = on and C.Yellow or C.White
		end
		selectedEvent:Fire(id)
	end
	for i, t in tabs do
		local b = Core.new("TextButton", {
			Name = t.id,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(w, w * 0.95),
			LayoutOrder = i,
			ZIndex = 14,
			Parent = side,
		})
		b:SetAttribute("PD_NoClick", true)
		local sc = Core.new("UIScale", { Parent = b })
		local glow = Core.new("ImageLabel", {
			Name = "Glow",
			BackgroundTransparency = 1,
			Image = Assets.Textures.glow_soft or "",
			ImageColor3 = C.Yellow,
			ImageTransparency = 0.3,
			Size = UDim2.fromScale(1.1, 1.1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Visible = false,
			ZIndex = 14,
			Parent = b,
		})
		Core.icon(
			b,
			t.icon or "gift",
			{ size = UDim2.fromOffset(w * 0.68, w * 0.68), position = UDim2.fromScale(0.5, 0.4), zindex = 15 }
		)
		local label = Core.text(b, {
			text = t.label or t.id,
			size = 24,
			frameSize = UDim2.new(1.2, 0, 0, 28),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
			zindex = 16,
		})
		if t.badge then
			Core.badge(b, t.badge, 26)
		end
		entries[t.id] = { scale = sc, glow = glow, label = label }
		b.Activated:Connect(function()
			Core.sound("UiClick")
			api.select(t.id)
		end)
	end
	return api
end

-- Scrolling content area inside a panel body. Returns the ScrollingFrame (AutomaticCanvasSize Y).
function Panel.scroll(parent: Instance, props: { [string]: any }?)
	local p = props or {}
	local sf = Core.new("ScrollingFrame", {
		Name = p.name or "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = p.size or UDim2.fromScale(1, 1),
		Position = p.position or UDim2.new(),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Muted,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = p.zindex or 13,
		Parent = parent,
	})
	Core.new("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 16),
		Parent = sf,
	})
	return sf
end

-- Card on a panel (PanelLight, ink stroke, top highlight). Returns the Frame.
function Panel.card(parent: Instance, props: { [string]: any }?)
	local p = props or {}
	local f = Core.new("Frame", {
		Name = p.name or "Card",
		BackgroundColor3 = p.color or C.PanelLight,
		Size = p.size or UDim2.fromOffset(260, 320),
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.new(),
		LayoutOrder = p.layoutOrder or 0,
		ZIndex = p.zindex or 14,
		Parent = parent,
	})
	Core.corner(f, Style.Corner.Card)
	Core.border(f, Style.Stroke.Card)
	local hl = Core.new("Frame", {
		Name = "TopLight",
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -16, 0, 2),
		Position = UDim2.fromOffset(8, 3),
		ZIndex = f.ZIndex + 1,
		Parent = f,
	})
	hl.Name = "TopLight"
	return f
end

return Panel
