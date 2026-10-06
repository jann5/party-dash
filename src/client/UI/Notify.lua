-- Party Dash announcements: renders remote "Core_Announce" (see src/server/Announce.lua).
--   big   -> huge bouncy centered text (+ optional sub line), e.g. countdown "3", "YOU'RE OUT!"
--   feed  -> kill-feed line top-right, fades out
--   toast -> small pill at the bottom ("+25 coins")
-- The root Frame keeps LastBig / LastFeed / LastToast attributes for easy inspection.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Data = require(script.Parent.Data)
local Kit = require(script.Parent.Kit)
local Sfx = require(script.Parent.Sfx)

local C = Theme.Colors

local Notify = {}

export type Api = {
	setBigLane: (boolean) -> (), -- true while the results card owns the middle of the screen
	bigShown: RBXScriptSignal, -- fires (text) whenever a big announcement appears
}

local MAX_TEXT = 120
local MAX_FEED = 5
local MAX_TOASTS = 2

-- Big text lanes (screen-height fractions). Normal: centered a bit above the middle, clear of the
-- HUD top bar and the onboarding bubble. High: above the results card.
local LANE_Y = 0.44
local HIGH_LANE_Y = 0.13
-- TextSize and TextScaled both stop at 100px, which is far too small for a countdown digit, so big text
-- is laid out at this fixed size and blown up with a UIScale fitted to the screen.
local BASE_SIZE = 100

local function clean(value: any, limit: number): string?
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	if utf8.len(value) == nil then
		return nil -- invalid UTF-8
	end
	if #value > limit then
		-- cut on a character boundary
		local cut = utf8.offset(value, limit + 1)
		value = string.sub(value, 1, (cut or (limit + 1)) - 1)
	end
	return value
end

local function charCount(text: string): number
	return utf8.len(text) or #text
end

function Notify.start(gui: ScreenGui): Api
	local root = Kit.box({ Name = "Notify", ZIndex = 30, Parent = gui })

	-- BIG ---------------------------------------------------------------------------------------
	local bigShownEvent = Instance.new("BindableEvent")

	-- shockwave ring behind countdown digits
	local ring = Kit.new("Frame", {
		Name = "BigRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, LANE_Y),
		Size = UDim2.fromScale(0.2, 0.2),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = C.White,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 31,
		Parent = root,
	})
	Kit.corner(UDim.new(0.5, 0)).Parent = ring
	local ringStroke = Kit.new("UIStroke", { Color = C.Yellow, Thickness = 8, Parent = ring })

	-- Big (sized to the text at BASE_SIZE) -> UIScale fit to screen -> Pop (UIScale for the bounce)
	local big = Kit.box({
		Name = "Big",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, LANE_Y),
		Size = UDim2.fromOffset(100, 100),
		Visible = false,
		ZIndex = 32,
		Parent = root,
	})
	local fitScale = Kit.new("UIScale", { Name = "Fit", Parent = big })
	local pop = Kit.box({
		Name = "Pop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 32,
		Parent = big,
	})
	local popScale = Kit.scaler(pop)

	local function bigLabel(name: string, color: Color3, z: number): (TextLabel, UIStroke)
		local label = Kit.new("TextLabel", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = Theme.FontFace,
			Text = "",
			TextColor3 = color,
			TextSize = BASE_SIZE,
			TextScaled = false,
			TextWrapped = false,
			ZIndex = z,
			Parent = pop,
		})
		local stroke = Kit.new("UIStroke", {
			Color = C.Ink,
			LineJoinMode = Enum.LineJoinMode.Round,
			Thickness = 6,
			Parent = label,
		})
		return label, stroke
	end
	-- chunky drop shadow under the main text for depth
	local bigShadow, shadowStroke = bigLabel("Shadow", C.Ink, 32)
	local bigText, bigStroke = bigLabel("Text", C.White, 33)
	local bigGradient = Kit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(C.White, C.Yellow),
		Parent = bigText,
	})

	local bigSub = Kit.label("", {
		Name = "BigSub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, LANE_Y + 0.1),
		Size = UDim2.fromScale(0.6, 0.065),
		Visible = false,
		ZIndex = 33,
		Parent = root,
	}, { maxText = 56, stroke = 4 })
	local subStroke = bigSub:FindFirstChildOfClass("UIStroke")
	local subScale = Kit.scaler(bigSub)

	local bigToken = 0
	local highLane = false -- set while the results card owns the middle of the screen
	local currentShort = false

	-- Fit the big text to the current lane / screen. Returns nothing; safe to call any time.
	local function layoutBig()
		local text = bigText.Text
		local screen = root.AbsoluteSize
		if text == "" or screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local bounds = TextService:GetTextSize(text, BASE_SIZE, Enum.Font.FredokaOne, Vector2.new(10000, 10000))
		local w, h = bounds.X + 30, bounds.Y + 16
		big.Size = UDim2.fromOffset(w, h)
		-- short = countdown digits / "GO!": dominate the screen; long lines stay narrow enough to clear
		-- the TOP 3 panel on the right
		local maxW, maxH
		if highLane then
			maxW, maxH = 0.8, currentShort and 0.2 or 0.12
		else
			maxW, maxH = currentShort and 0.8 or 0.54, currentShort and 0.42 or 0.17
		end
		local s = math.min(screen.X * maxW / w, screen.Y * maxH / h)
		fitScale.Scale = s
		local strokePx = screen.Y * (currentShort and 0.011 or 0.006)
		bigStroke.Thickness = math.max(1, strokePx / s)
		shadowStroke.Thickness = bigStroke.Thickness
		bigShadow.Position = UDim2.new(0.5, 0, 0.5, strokePx * 1.1 / s)

		local centerY = highLane and HIGH_LANE_Y or LANE_Y
		big.Position = UDim2.fromScale(0.5, centerY)
		ring.Position = big.Position
		-- the sub line sits just under the glyphs (the box carries some empty line height)
		local halfH = (h * s * 0.5) / screen.Y
		bigSub.Position = UDim2.fromScale(0.5, centerY + halfH * 0.8 + 0.012)
		bigSub.Size = UDim2.fromScale(0.6, highLane and 0.05 or 0.065)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutBig)

	local function setBigAlpha(alpha: number)
		bigText.TextTransparency = alpha
		bigStroke.Transparency = alpha
		bigShadow.TextTransparency = alpha
		shadowStroke.Transparency = alpha
	end

	local function showBig(text: string, sub: string?, color: Color3?)
		bigToken += 1
		local token = bigToken
		currentShort = charCount(text) <= 3
		local short = currentShort
		bigText.Text = text
		bigShadow.Text = text
		layoutBig()
		big.Visible = true
		setBigAlpha(0)
		local tint = color or C.Yellow
		bigGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Kit.lighten(tint, 0.75)),
			ColorSequenceKeypoint.new(0.55, Kit.lighten(tint, 0.15)),
			ColorSequenceKeypoint.new(1, tint),
		})
		bigSub.Text = sub or ""
		bigSub.Visible = sub ~= nil
		bigSub.TextTransparency = 0
		if subStroke then
			subStroke.Transparency = 0
		end
		bigShownEvent:Fire(text)

		-- countdown numbers get a rising pitch
		local number = tonumber(text)
		if number then
			Sfx.play("pop", 0.9 + math.clamp(4 - number, 0, 4) * 0.12)
		else
			Sfx.play(short and "boom" or "pop", short and 1 or 0.9)
		end

		-- slam in: oversized + tilted -> settle with a bounce
		pop.Rotation = math.random(-12, 12)
		popScale.Scale = short and 2.3 or 1.7
		Kit.tween(popScale, 0.42, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		Kit.tween(pop, 0.6, { Rotation = 0 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		if sub then
			Kit.popIn(subScale, 0.4, 0.12)
		end
		if short and not highLane then
			ring.Visible = true
			ring.Size = UDim2.fromScale(0.16, 0.16)
			ringStroke.Color = tint
			ringStroke.Thickness = math.max(2, root.AbsoluteSize.Y * 0.014)
			ringStroke.Transparency = 0
			Kit.tween(ring, 0.55, { Size = UDim2.fromScale(0.8, 0.8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			Kit.tween(ringStroke, 0.55, { Transparency = 1, Thickness = 1 })
		else
			ring.Visible = false
		end

		-- the next countdown digit simply replaces this one (token check), so a lone digit can linger
		local hold = short and 1.5 or 2.6
		task.delay(hold, function()
			if bigToken ~= token then
				return
			end
			local out = 0.24
			Kit.tween(popScale, out, { Scale = 1.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			for _, inst in { bigText, bigShadow, bigSub } do
				Kit.tween(inst, out, { TextTransparency = 1 })
			end
			for _, s in { bigStroke, shadowStroke, subStroke } do
				if s then
					Kit.tween(s, out, { Transparency = 1 })
				end
			end
			task.delay(out + 0.02, function()
				if bigToken == token then
					big.Visible = false
					bigSub.Visible = false
					ring.Visible = false
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

	return {
		-- lets the results card push big text up so they never overlap
		setBigLane = function(high: boolean)
			if highLane == high then
				return
			end
			highLane = high
			if big.Visible then
				layoutBig()
			end
		end,
		bigShown = bigShownEvent.Event,
	}
end

return Notify
