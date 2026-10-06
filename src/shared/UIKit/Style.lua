-- UIKit design tokens (docs/v2/ART_BIBLE.md section 8). Sizes are DESIGN pixels at a 1080-tall screen; UIKit
-- screens apply a UIScale (clamp(viewportY / 1080, 0.55, 1.3)) so the same numbers work on phones and 1080p.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)

local Style = {}

local C = Theme.Colors

Style.Colors = C
Style.Font = Theme.FontFace -- FredokaOne: buttons, titles, numbers, prices
Style.FontHype = Theme.FontHype -- LuckiestGuy: countdowns, BOOM!, YOU WIN!
Style.FontBody = Theme.FontBody -- BuilderSans Bold: small text
Style.FontBodyHeavy = Theme.FontBodyHeavy

-- Type scale (design px)
Style.Text = {
	Hero = 120,
	Display = 72,
	H1 = 56,
	H2 = 40,
	Button = 30,
	Value = 34,
	Body = 22,
	Caption = 18,
}

-- Button / tile face colors: { face, dark lip }
Style.Variants = {
	Green = { C.Green, C.GreenDark },
	Blue = { C.Blue, C.BlueDark },
	Red = { C.Red, C.RedDark },
	Yellow = { C.Yellow, C.YellowDark },
	Gold = { C.Gold, C.YellowDark },
	Orange = { C.Orange, C.OrangeDark },
	Purple = { C.Purple, C.PurpleDark },
	Pink = { C.Pink, C.PinkDark },
	Cyan = { C.Cyan, C.CyanDark },
	Dark = { C.PanelLight, C.PanelDeep },
	White = { Color3.fromRGB(245, 245, 250), Color3.fromRGB(170, 172, 190) },
	Disabled = { Color3.fromRGB(150, 150, 165), Color3.fromRGB(110, 110, 125) },
}

-- ScreenGui DisplayOrder layers (higher = on top)
Style.Layers = {
	World = 1, -- BillboardGuis don't use this; reserved
	HUD = 10, -- timers, counters, docks
	Round = 20, -- round overlays (alive pill, bomb pill)
	Lanes = 30, -- toasts, feed, action lane
	Popup = 40, -- death panel, vote cards, results
	Panel = 50, -- modal panels (shop, wheel, settings)
	Overlay = 60, -- roulette / intro full-screen overlays
	Toast = 70, -- toasts above panels
	Loading = 100, -- loading screen
}

Style.Corner = {
	Tile = UDim.new(0.14, 0),
	Button = UDim.new(0.22, 0),
	Pill = UDim.new(0.5, 0),
	Panel = UDim.new(0, 18),
	Card = UDim.new(0, 12),
}

Style.Stroke = {
	Ink = C.Ink,
	Button = 3.5,
	Panel = 4,
	Card = 3,
}

-- Text stroke thickness from the text pixel height (ART_BIBLE 8.2).
function Style.textStroke(px: number): number
	if px >= 72 then
		return 6
	elseif px >= 48 then
		return 5
	elseif px >= 32 then
		return 4
	elseif px >= 24 then
		return 3
	elseif px >= 18 then
		return 2
	end
	return 1.5
end

function Style.lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), t)
end

function Style.darken(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- Robux glyph (private-use character in Roblox's fonts). Use Style.robux(19) -> "<glyph> 19".
Style.ROBUX = utf8.char(0xE002)
function Style.robux(n: number): string
	return Style.ROBUX .. " " .. tostring(n)
end

return Style
