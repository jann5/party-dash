--!strict
--[[
Global TOP 10 board for Solo Record, mounted on every lobby's Part "LeaderboardAnchor".

The lobby Model is destroyed and rebuilt around every round, so the board watches workspace and re-mounts
itself whenever a Model with a "LeaderboardAnchor" Part appears. It cycles through the solo-capable
minigames every PAGE_SECONDS and re-renders as soon as a top list changes (Records.onTopChanged).

	Board.start(getIds: () -> { string }, getTop: (id) -> { TopEntry })
	Board.refresh()   -- re-render the current page now
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared.Theme)

local Board = {}

Board.GUI_NAME = "SoloTopBoard"
Board.PAGE_SECONDS = 8
Board.PIXELS_PER_STUD = 50

local C = Theme.Colors
local MEDALS = {
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(205, 215, 235),
	Color3.fromRGB(230, 145, 85),
}

type Row = { frame: Frame, rank: TextLabel, badge: Frame, name: TextLabel, time: TextLabel }
type View = {
	gui: SurfaceGui,
	header: Frame,
	headerGradient: UIGradient,
	gameName: TextLabel,
	rows: { Row },
	empty: TextLabel,
	dots: { Frame },
	dotRow: Frame,
}

type TopEntry = { userId: number, name: string, ms: number }

local views: { [BasePart]: View } = {}
local page = 1
local getIds: () -> { string } = function()
	return {}
end
local getTop: (string) -> { TopEntry } = function(_id)
	return {}
end
local getDisplayName: (string) -> string = function(id)
	return string.upper(id)
end

-- Builders --------------------------------------------------------------------------------------------

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = parent
	return inst
end

local function corner(parent: Instance, scale: number)
	new("UICorner", { CornerRadius = UDim.new(scale, 0), Parent = parent })
end

local function stroke(parent: Instance, thickness: number, color: Color3?)
	new("UIStroke", {
		Thickness = thickness,
		Color = color or C.Ink,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function label(parent: Instance, props: { [string]: any }, strokeSize: number): TextLabel
	local base = {
		BackgroundTransparency = 1,
		FontFace = Theme.FontFace,
		TextScaled = true,
		TextColor3 = C.White,
		Parent = parent,
	}
	for k, v in props do
		base[k] = v
	end
	local l = new("TextLabel", base)
	if strokeSize > 0 then
		stroke(l, strokeSize)
	end
	return l
end

local function formatTime(ms: number): string
	local s = ms / 1000
	if s >= 60 then
		return ("%d:%04.1f"):format(math.floor(s / 60), s % 60)
	end
	return ("%.1fs"):format(s)
end

local function buildView(anchor: BasePart): View
	local gui = new("SurfaceGui", {
		Name = Board.GUI_NAME,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = Board.PIXELS_PER_STUD,
		LightInfluence = 0,
		Brightness = 1.2,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = anchor,
	})

	local bg = new("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Parent = gui,
	})
	new("UIGradient", {
		Color = ColorSequence.new(C.Panel:Lerp(C.Purple, 0.35), C.Ink),
		Rotation = 90,
		Parent = bg,
	})

	-- Title ribbon.
	local title = new("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.7, 0.15),
		BackgroundColor3 = C.Yellow,
		BorderSizePixel = 0,
		Parent = bg,
	})
	corner(title, 0.45)
	stroke(title, 5)
	new("UIGradient", { Color = ColorSequence.new(C.Yellow, C.Orange), Rotation = 90, Parent = title })
	label(title, {
		Name = "Text",
		Text = "SOLO RECORDS",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.8),
	}, 4)

	-- Minigame header (accent colored per page).
	local header = new("Frame", {
		Name = "Game",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.21),
		Size = UDim2.fromScale(0.9, 0.11),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = bg,
	})
	corner(header, 0.5)
	stroke(header, 4)
	local headerGradient = new("UIGradient", { Rotation = 0, Parent = header })
	local gameName = label(header, {
		Name = "Text",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.78),
	}, 3)

	-- Two columns of five rows: 1-5 on the left, 6-10 on the right.
	local rows: { Row } = {}
	for i = 1, 10 do
		local col = if i <= 5 then 0 else 1
		local r = (i - 1) % 5
		local frame = new("Frame", {
			Name = "Row" .. i,
			Position = UDim2.fromScale(0.04 + col * 0.475, 0.355 + r * 0.115),
			Size = UDim2.fromScale(0.445, 0.1),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Parent = bg,
		})
		corner(frame, 0.35)
		local badge = new("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.015, 0.5),
			Size = UDim2.fromScale(0.15, 0.86),
			BackgroundColor3 = MEDALS[i] or C.Panel,
			BorderSizePixel = 0,
			Parent = frame,
		})
		corner(badge, 0.5)
		stroke(badge, 3)
		local rank = label(badge, {
			Name = "Rank",
			Text = tostring(i),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.8),
		}, 2.5)
		local name = label(frame, {
			Name = "Name",
			Text = "",
			Position = UDim2.fromScale(0.2, 0.12),
			Size = UDim2.fromScale(0.52, 0.76),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 2.5)
		local time = label(frame, {
			Name = "Time",
			Text = "",
			Position = UDim2.fromScale(0.73, 0.12),
			Size = UDim2.fromScale(0.25, 0.76),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.Yellow,
		}, 2.5)
		table.insert(rows, { frame = frame, rank = rank, badge = badge, name = name, time = time })
	end

	local empty = label(bg, {
		Name = "Empty",
		Text = "No records yet!\nPress SOLO and be the first!",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromScale(0.8, 0.28),
		TextColor3 = C.Cyan,
		Visible = false,
	}, 3)

	-- Page dots along the bottom edge.
	local dotRow = new("Frame", {
		Name = "Dots",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.985),
		Size = UDim2.fromScale(0.6, 0.04),
		BackgroundTransparency = 1,
		Parent = bg,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.015, 0),
		Parent = dotRow,
	})

	return {
		gui = gui,
		header = header,
		headerGradient = headerGradient,
		gameName = gameName,
		rows = rows,
		empty = empty,
		dots = {},
		dotRow = dotRow,
	}
end

-- Rendering -------------------------------------------------------------------------------------------

local function renderDots(view: View, count: number, current: number)
	while #view.dots < count do
		local dot = new("Frame", {
			Name = "Dot",
			Size = UDim2.fromScale(0.05, 1),
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			Parent = view.dotRow,
		})
		new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = dot })
		corner(dot, 0.5)
		table.insert(view.dots, dot)
	end
	for i, dot in view.dots do
		dot.Visible = i <= count
		dot.BackgroundColor3 = if i == current then C.Yellow else C.White
		dot.BackgroundTransparency = if i == current then 0 else 0.55
	end
end

local function render(view: View)
	local ids = getIds()
	if #ids == 0 then
		view.gameName.Text = "COMING SOON"
		view.headerGradient.Color = ColorSequence.new(C.Purple, C.Pink)
		for _, row in view.rows do
			row.frame.Visible = false
		end
		view.empty.Visible = true
		renderDots(view, 0, 0)
		return
	end
	local index = (page - 1) % #ids + 1
	local id = ids[index]
	local accent = Theme.MinigameColors[id] or C.Purple
	view.gameName.Text = getDisplayName(id)
	view.headerGradient.Color = ColorSequence.new(accent:Lerp(C.White, 0.15), accent:Lerp(C.Ink, 0.25))

	local top = getTop(id)
	for i, row in view.rows do
		local entry = top[i]
		row.frame.Visible = entry ~= nil
		if entry then
			row.name.Text = entry.name
			row.time.Text = formatTime(entry.ms)
			row.frame.BackgroundTransparency = if i <= 3 then 0.78 else 0.88
		end
	end
	view.empty.Visible = #top == 0
	renderDots(view, #ids, index)
end

local function mount(anchor: BasePart)
	if views[anchor] and views[anchor].gui.Parent == anchor then
		return
	end
	local existing = anchor:FindFirstChild(Board.GUI_NAME)
	if existing then
		existing:Destroy()
	end
	local view = buildView(anchor)
	views[anchor] = view
	render(view)
	anchor.Destroying:Connect(function()
		views[anchor] = nil
	end)
end

-- Finds every lobby-like Model in workspace with a LeaderboardAnchor Part and mounts a board on it.
local function scan()
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") then
			local anchor = child:FindFirstChild("LeaderboardAnchor")
			if anchor and anchor:IsA("BasePart") then
				mount(anchor)
			end
		end
	end
	for anchor in views do
		if not anchor.Parent or not anchor:IsDescendantOf(workspace) then
			views[anchor] = nil
		end
	end
end

function Board.refresh()
	for _, view in views do
		render(view)
	end
end

function Board.start(idsFn: () -> { string }, topFn: (string) -> { TopEntry }, nameFn: (string) -> string)
	getIds = idsFn
	getTop = topFn
	getDisplayName = nameFn
	workspace.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			-- The lobby is fully built before it is parented, but wait a frame for safety.
			task.defer(scan)
		end
	end)
	scan()
	-- Page cycling plus a slow rescan (covers anchors added after their Model was parented).
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(1)
			elapsed += 1
			scan()
			if elapsed >= Board.PAGE_SECONDS then
				elapsed = 0
				page += 1
				Board.refresh()
			end
		end
	end)
end

return Board
