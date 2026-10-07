--!nonstrict
-- Minigame / modifier card used by the vote cards and the roulette reel. Same anatomy as a UIKit button
-- (ART_BIBLE 8.3): ink-outlined gradient face in the card's accent colour, inner light rim, gloss, a darker 3D lip,
-- plus a stud texture, the big illustrated icon breaking out of the top edge and the name on a dark band.
--
--   local card = Cards.build(parent, Info.minigame("Spin"), Vector2.new(240, 170), { layoutOrder = 1 })
--   card.holder / card.body (punch this) / card.face / card.icon / card.name / card.stroke
--   card.setGrey(true)  -- disabled look (grey face, dimmed icon)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Assets)
local UIKit = require(ReplicatedStorage.Shared.UIKit)

local Style = UIKit.Style
local C = Style.Colors

local Cards = {}

local GREY = Color3.fromRGB(150, 150, 165)

local function faceColors(c: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Style.lighten(c, 0.18)),
		ColorSequenceKeypoint.new(0.55, c),
		ColorSequenceKeypoint.new(1, Style.darken(c, 0.16)),
	})
end

--[[
props: name, layoutOrder, position, anchor, className ("Frame" | "TextButton"), iconScale (default 0.56 of width),
	radius (px, default 18), nameSize (px)
]]
function Cards.build(parent: Instance?, info, size: Vector2, props: { [string]: any }?)
	local p = props or {}
	local lip = math.max(5, math.floor(size.Y * 0.045 + 0.5))
	local radius = UDim.new(0, p.radius or 18)
	local holder = UIKit.new(p.className or "Frame", {
		Name = p.name or ("Card_" .. info.id),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y + lip),
		Position = p.position or UDim2.new(),
		AnchorPoint = p.anchor or Vector2.new(),
		LayoutOrder = p.layoutOrder or 0,
		ZIndex = 2,
	})
	if holder:IsA("TextButton") then
		holder.Text = ""
		holder.AutoButtonColor = false
		holder:SetAttribute("PD_NoClick", true) -- plays its own click sound
	end
	holder:SetAttribute("MinigameId", info.id)

	-- body carries the pop/punch scale so a reel scale on the holder never fights it
	local body = UIKit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
	})
	local lipFrame = UIKit.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = Style.darken(info.color, 0.35),
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromOffset(0, lip),
		ZIndex = 2,
		Parent = body,
	})
	UIKit.corner(lipFrame, radius)
	UIKit.border(lipFrame, 4)

	local face = UIKit.new("Frame", {
		Name = "Face",
		BackgroundColor3 = C.White,
		Size = UDim2.fromOffset(size.X, size.Y),
		ZIndex = 3,
		Parent = body,
	})
	UIKit.corner(face, radius)
	local stroke = UIKit.border(face, 4)
	local grad = UIKit.gradient(face, { C.White, C.White }, 90)
	grad.Color = faceColors(info.color)

	local studs = Assets.Textures.studs
	if studs and studs ~= "" then
		local pattern = UIKit.new("ImageLabel", {
			Name = "Pattern",
			BackgroundTransparency = 1,
			Image = studs,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(36, 36),
			ImageTransparency = 0.86,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = face,
		})
		UIKit.corner(pattern, radius)
	end
	local rim = UIKit.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		ZIndex = 4,
		Parent = face,
	})
	UIKit.corner(rim, radius)
	local rimStroke = UIKit.border(rim, 2, Style.lighten(info.color, 0.45), 0.25)
	local gloss = UIKit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -10, 0.42, 0),
		Position = UDim2.fromOffset(5, 4),
		ZIndex = 4,
		Parent = face,
	})
	UIKit.corner(gloss, radius)
	UIKit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Parent = gloss,
	})

	-- name band
	local bandH = math.min(64, math.floor(size.Y * 0.26))
	local band = UIKit.new("Frame", {
		Name = "Band",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
		Size = UDim2.new(1, -14, 0, bandH),
		Position = UDim2.new(0.5, 0, 1, -7),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 5,
		Parent = face,
	})
	UIKit.corner(band, UDim.new(0, math.max(8, (p.radius or 18) - 6)))
	local nameLabel = UIKit.text(band, {
		name = "Title",
		text = info.name,
		size = p.nameSize or math.min(30, math.floor(bandH * 0.62)),
		frameSize = UDim2.new(1, -10, 1, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		zindex = 6,
	})
	-- long names shrink instead of spilling out of the band
	nameLabel.TextScaled = true
	UIKit.new("UITextSizeConstraint", { MaxTextSize = nameLabel.TextSize, MinTextSize = 12, Parent = nameLabel })

	-- big icon, overflowing the top edge (ref1 tiles); a child of the face so it sinks with it on press
	local iconSize = math.floor(size.X * (p.iconScale or 0.56))
	local icon = UIKit.icon(face, info.icon, {
		size = UDim2.fromOffset(iconSize, iconSize),
		position = UDim2.new(0.5, 0, 0, math.floor((size.Y - bandH) * 0.46)),
		zindex = 8,
	})

	local api = {
		holder = holder,
		body = body,
		face = face,
		icon = icon,
		name = nameLabel,
		band = band,
		stroke = stroke,
		lip = lip,
		info = info,
	}
	function api.setGrey(on: boolean)
		local c = on and GREY or info.color
		grad.Color = faceColors(c)
		lipFrame.BackgroundColor3 = Style.darken(c, 0.35)
		rimStroke.Color = Style.lighten(c, 0.45)
		icon.ImageColor3 = on and Color3.fromRGB(170, 170, 180) or C.White
		icon.ImageTransparency = on and 0.25 or 0
	end
	holder.Parent = parent
	return api
end

-- Press feedback for a card holder that is a TextButton: the face sinks onto its lip, hover grows it a bit
-- (the hover scale lives on the holder, punches use the body).
function Cards.pressable(card)
	local holder = card.holder
	local face = card.face
	local lip = card.lip
	local scale = UIKit.new("UIScale", { Name = "HoverScale", Parent = holder })
	local function press(on: boolean)
		UIKit.tween(face, on and 0.06 or 0.14, {
			Position = UDim2.fromOffset(0, on and lip or 0),
		}, on and Enum.EasingStyle.Quad or Enum.EasingStyle.Back)
	end
	holder.MouseEnter:Connect(function()
		if not UIKit.isTouch() then
			UIKit.tween(scale, 0.1, { Scale = 1.04 })
		end
	end)
	holder.MouseLeave:Connect(function()
		press(false)
		UIKit.tween(scale, 0.1, { Scale = 1 })
	end)
	holder.MouseButton1Down:Connect(function()
		press(true)
	end)
	holder.MouseButton1Up:Connect(function()
		press(false)
	end)
end

return Cards
