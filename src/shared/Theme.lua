-- Party Dash visual theme: bright cartoon (Stumble Guys / Fall Guys). FROZEN CONTRACT.
-- Every UI and every map should pull colors/fonts from here so the game looks like one product.
local Theme = {}

Theme.Font = Enum.Font.FredokaOne
Theme.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)

Theme.Colors = {
	Yellow = Color3.fromRGB(255, 205, 60),
	Orange = Color3.fromRGB(255, 150, 40),
	Pink = Color3.fromRGB(255, 95, 160),
	Red = Color3.fromRGB(255, 80, 80),
	Purple = Color3.fromRGB(150, 100, 255),
	Blue = Color3.fromRGB(70, 140, 255),
	Cyan = Color3.fromRGB(90, 210, 255),
	Green = Color3.fromRGB(90, 230, 120),
	White = Color3.fromRGB(255, 255, 255),
	Ink = Color3.fromRGB(30, 25, 50), -- outlines / text strokes / dark panels
	Panel = Color3.fromRGB(45, 38, 80),
	Laser = Color3.fromRGB(255, 40, 90), -- neon hazard color
	LaserAlt = Color3.fromRGB(60, 255, 230),
}

-- One accent per minigame (roulette cards, intro card, map trim).
Theme.MinigameColors = {
	LaserTracer = Color3.fromRGB(255, 70, 120),
	Dodgeball = Color3.fromRGB(255, 150, 40),
	KingOfTheHill = Color3.fromRGB(255, 205, 60),
	HoleInTheWall = Color3.fromRGB(70, 140, 255),
	Spin = Color3.fromRGB(150, 100, 255),
}

-- Cheerful map palette for floors/props (alternate tiles, rims, etc.).
Theme.MapPalette = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB(255, 215, 90),
	Color3.fromRGB(140, 235, 140),
	Color3.fromRGB(190, 150, 255),
}

Theme.CornerRadius = UDim.new(0, 14)
Theme.StrokeThickness = 3

return Theme
