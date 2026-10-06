-- Party Dash announcements: renders remote "Core_Announce" (see src/server/Announce.lua).
--   big   -> huge bouncy centered text (+ optional sub line), e.g. countdown "3", "YOU'RE OUT!"
--   feed  -> kill-feed line top-right, fades out
--   toast -> small pill at the bottom ("+25 coins")
-- The root Frame keeps LastBig / LastFeed / LastToast attributes for easy inspection.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors

local Notify = {}

local MAX_TEXT = 120
local MAX_FEED = 5
local MAX_TOASTS = 3

local function clean(value: any, limit: number): string?
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	return string.sub(value, 1, limit)
end

function Notify.start(gui: ScreenGui)
	local root = Kit.box({ Name = "Notify", ZIndex = 30, Parent = gui })

	-- BIG ---------------------------------------------------------------------------------------
	local big = Kit.box({
		Name = "Big",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.9, 0.16),
		Visible = false,
		ZIndex = 31,
		Parent = root,
	})
	local bigScale = Kit.scaler(big)
	local bigText = Kit.label("", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromScale(1, 0.7),
		Position = UDim2.fromScale(0.5, 0),
		ZIndex = 32,
		Parent = big,
	}, { maxText = 150, stroke = 8 })
	local bigGradient = Kit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(C.White, C.Yellow),
		Parent = bigText,
	})
	local bigSub = Kit.label("", {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.8, 0.24),
		ZIndex = 32,
		Parent = big,
	}, { maxText = 48, stroke = 4 })

	local bigToken = 0
	local highLane = false -- set while the results card owns the middle of the screen
	local function showBig(text: string, sub: string?, color: Color3?)
		bigToken += 1
		local token = bigToken
		big.Visible = true
		bigText.Text = text
		bigSub.Text = sub or ""
		bigSub.Visible = sub ~= nil
		bigText.TextTransparency = 0
		bigSub.TextTransparency = 0
		local tint = color or C.Yellow
		bigGradient.Color = ColorSequence.new(Kit.lighten(tint, 0.7), tint)

		-- countdown numbers get a rising pitch and a snappier hold
		local short = #text <= 3
		local number = tonumber(text)
		if number then
			Sfx.play("pop", 0.9 + math.clamp(4 - number, 0, 4) * 0.12)
		else
			Sfx.play(short and "boom" or "pop", short and 1 or 0.9)
		end

		big.Rotation = math.random(-10, 10)
		-- TextScaled caps at 100px, so short texts (countdown digits) get extra size from the UIScale
		local rest = short and ((highLane or sub) and 1.2 or 1.6) or 1
		bigScale.Scale = rest * 2.2
		Kit.tween(bigScale, 0.45, { Scale = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		Kit.tween(big, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

		local hold = short and 1.6 or 2.6
		task.delay(hold, function()
			if bigToken ~= token then
				return
			end
			Kit.tween(bigScale, 0.3, { Scale = rest * 1.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Kit.tween(bigText, 0.3, { TextTransparency = 1 })
			Kit.tween(bigSub, 0.3, { TextTransparency = 1 })
			task.delay(0.32, function()
				if bigToken == token then
					big.Visible = false
				end
			end)
		end)
	end

	-- FEED --------------------------------------------------------------------------------------
	local feed = Kit.box({
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromScale(0.25, 0.3),
		ZIndex = 31,
		Parent = root,
	})
	Kit.sizeLimit(420, 300).Parent = feed
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.02, 0),
		Parent = feed,
	})
	local feedOrder = 0

	local function addFeed(text: string)
		feedOrder -= 1 -- newest on top
		local entries = {}
		for _, child in feed:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(entries, child)
			end
		end
		-- newest first; drop the oldest so at most MAX_FEED lines remain with the new one
		table.sort(entries, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = MAX_FEED, #entries do
			entries[i]:Destroy()
		end

		local row = Kit.box({
			Name = "FeedLine",
			Size = UDim2.fromScale(1, 0.18),
			LayoutOrder = feedOrder,
			ZIndex = 31,
			Parent = feed,
		})
		row:SetAttribute("Text", text)
		Kit.sizeLimit(10000, 44, 0, 22).Parent = row
		local pillFrame = Kit.panel(C.Panel, {
			Name = "Pill",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1.3, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 0.1,
			ZIndex = 31,
			Parent = row,
		}, UDim.new(0.5, 0), 2.5)
		local accent = Kit.new("Frame", {
			Name = "Accent",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.03, 0.5),
			Size = UDim2.fromScale(0.5, 0.5),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundColor3 = C.Red,
			BorderSizePixel = 0,
			ZIndex = 32,
			Parent = pillFrame,
		})
		Kit.corner(UDim.new(0.5, 0)).Parent = accent
		local label = Kit.label(text, {
			Name = "Text",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.96, 0.5),
			Size = UDim2.fromScale(0.86, 0.66),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 32,
			Parent = pillFrame,
		}, { maxText = 26, stroke = 2 })
		Kit.tween(pillFrame, 0.35, { Position = UDim2.fromScale(1, 0.5) }, Enum.EasingStyle.Back)
		task.delay(6, function()
			if not row.Parent then
				return
			end
			Kit.tween(pillFrame, 0.4, { BackgroundTransparency = 1, Position = UDim2.fromScale(1.15, 0.5) })
			Kit.tween(label, 0.4, { TextTransparency = 1 })
			Kit.tween(accent, 0.4, { BackgroundTransparency = 1 })
			for _, s in pillFrame:GetDescendants() do
				if s:IsA("UIStroke") then
					Kit.tween(s, 0.4, { Transparency = 1 })
				end
			end
			task.delay(0.45, function()
				row:Destroy()
			end)
		end)
	end

	-- TOAST -------------------------------------------------------------------------------------
	local toasts = Kit.box({
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.5, 0.24),
		ZIndex = 33,
		Parent = root,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.04, 0),
		Parent = toasts,
	})
	local toastOrder = 0

	local function addToast(text: string, color: Color3?)
		toastOrder += 1
		local list = {}
		for _, child in toasts:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(list, child)
			end
		end
		table.sort(list, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #list - MAX_TOASTS + 1 do
			list[i]:Destroy()
		end

		local tint = color or C.Yellow
		local toast = Kit.panel(tint, {
			Name = "Toast",
			Size = UDim2.fromScale(0.62, 0.3),
			LayoutOrder = toastOrder,
			ZIndex = 33,
			Parent = toasts,
		}, UDim.new(0.5, 0), 3)
		toast:SetAttribute("Text", text)
		Kit.sizeLimit(460, 54, 0, 26).Parent = toast
		Kit.gradient(Kit.lighten(tint, 0.3), tint).Parent = toast
		Kit.label(text, {
			Name = "Text",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.7),
			ZIndex = 34,
			Parent = toast,
		}, { maxText = 30, stroke = 2.5 })
		local scale = Kit.scaler(toast)
		Kit.popIn(scale, 0.4)
		Sfx.play("pop", 1.5)
		task.delay(3.2, function()
			if toast.Parent then
				Kit.popOut(scale, 0.25).Completed:Connect(function()
					toast:Destroy()
				end)
			end
		end)
	end

	-- Wire the remote (client-side validation: never trust the shape of incoming data) --------
	local function onAnnounce(kind: any, text: any, sub: any, colorHex: any)
		local msg = clean(text, MAX_TEXT)
		if not msg then
			return
		end
		local color = Data.parseHex(colorHex)
		if kind == "big" then
			root:SetAttribute("LastBig", msg)
			showBig(msg, clean(sub, MAX_TEXT), color)
		elseif kind == "feed" then
			root:SetAttribute("LastFeed", msg)
			addFeed(msg)
		elseif kind == "toast" then
			root:SetAttribute("LastToast", msg)
			addToast(msg, color)
		end
	end

	-- Net.event errors on the client after 30s if the remote never appears, so retry quietly.
	task.spawn(function()
		local remote: RemoteEvent? = nil
		while not remote do
			local ok, result = pcall(Net.event, "Core_Announce")
			if ok then
				remote = result
			else
				task.wait(2)
			end
		end
		remote.OnClientEvent:Connect(onAnnounce)
	end)

	-- lets the results card push big text up so they never overlap
	return {
		setBigLane = function(high: boolean)
			big.Position = UDim2.fromScale(0.5, high and 0.1 or 0.4)
			big.Size = high and UDim2.fromScale(0.8, 0.14) or UDim2.fromScale(0.9, 0.16)
			highLane = high
		end,
	}
end

return Notify
