-- Party Dash visual theme v2: bright, blocky, saturated (docs/v2/ART_BIBLE.md section 4). FROZEN CONTRACT.
-- Every UI and every map pulls colors/fonts from here so the game looks like one product.
-- Rules (ART_BIBLE 4.3): floors S >= 0.45 and 0.45 <= V <= 0.90, no pastels, never Lerp a world color toward white;
-- blue/cyan belongs to the sea and sky (no walkable floor uses it); hazards S >= 0.8, V >= 0.9.
local Theme = {}

Theme.Font = Enum.Font.FredokaOne -- display: buttons, titles, numbers, prices
Theme.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
Theme.FontHype = Font.new("rbxasset://fonts/families/LuckiestGuy.json", Enum.FontWeight.Regular) -- countdowns, BOOM!, YOU WIN!
Theme.FontBody = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold) -- small text
Theme.FontBodyHeavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)

Theme.Colors = {
	Yellow = Color3.fromRGB(255, 211, 38),
	YellowDark = Color3.fromRGB(214, 140, 0),
	Orange = Color3.fromRGB(255, 138, 28),
	OrangeDark = Color3.fromRGB(198, 82, 8),
	Pink = Color3.fromRGB(255, 78, 166),
	PinkDark = Color3.fromRGB(186, 28, 108),
	Red = Color3.fromRGB(235, 48, 58),
	RedDark = Color3.fromRGB(160, 22, 36),
	Purple = Color3.fromRGB(138, 72, 240),
	PurpleDark = Color3.fromRGB(86, 34, 170),
	Blue = Color3.fromRGB(36, 122, 246),
	BlueDark = Color3.fromRGB(18, 72, 182),
	Cyan = Color3.fromRGB(28, 196, 245),
	CyanDark = Color3.fromRGB(0, 128, 196),
	Green = Color3.fromRGB(62, 208, 72),
	GreenDark = Color3.fromRGB(24, 138, 44),
	Lime = Color3.fromRGB(150, 226, 40),
	Gold = Color3.fromRGB(255, 196, 30),
	Silver = Color3.fromRGB(200, 206, 222),
	Bronze = Color3.fromRGB(214, 128, 56),
	White = Color3.fromRGB(255, 255, 255),
	Ink = Color3.fromRGB(22, 18, 36), -- outlines, text strokes
	InkSoft = Color3.fromRGB(52, 46, 76),
	Panel = Color3.fromRGB(38, 34, 56), -- neutral dark charcoal-violet panel body
	PanelDeep = Color3.fromRGB(26, 23, 40),
	PanelLight = Color3.fromRGB(56, 50, 82), -- cards on a panel
	Muted = Color3.fromRGB(186, 180, 212), -- secondary text on dark
	Disabled = Color3.fromRGB(140, 140, 156),
	Laser = Color3.fromRGB(255, 28, 36),
	LaserAlt = Color3.fromRGB(255, 28, 36), -- brief #13: BOTH laser heights are red; height is shown by SHAPE
	Danger = Color3.fromRGB(255, 40, 40),
}

-- One accent per minigame (roulette/vote cards, intro card). Five distinct hues.
Theme.MinigameColors = {
	LaserTracer = Color3.fromRGB(235, 48, 58), -- red
	Dodgeball = Color3.fromRGB(36, 122, 246), -- blue
	HoleInTheWall = Color3.fromRGB(62, 208, 72), -- green
	Spin = Color3.fromRGB(138, 72, 240), -- purple
	BombTag = Color3.fromRGB(255, 211, 38), -- yellow
	KingOfTheHill = Color3.fromRGB(255, 211, 38), -- legacy (removed in v2), kept so old code never nil-indexes
}

-- Generic decoration colors only, NEVER floors.
Theme.MapPalette = {
	Color3.fromRGB(235, 48, 58),
	Color3.fromRGB(255, 138, 28),
	Color3.fromRGB(255, 211, 38),
	Color3.fromRGB(62, 208, 72),
	Color3.fromRGB(36, 122, 246),
	Color3.fromRGB(138, 72, 240),
}

Theme.Rarity = {
	Common = Color3.fromRGB(170, 178, 196),
	Rare = Color3.fromRGB(36, 122, 246),
	Epic = Color3.fromRGB(138, 72, 240),
	Legendary = Color3.fromRGB(255, 170, 20),
	Limited = Color3.fromRGB(255, 60, 140),
}

-- Shared world colors (Lobby, backdrop, generic props). Used by Shared.Art recipes.
Theme.World = {
	GrassTop = Color3.fromRGB(100, 210, 45),
	GrassAlt = Color3.fromRGB(88, 194, 38),
	GrassLip = Color3.fromRGB(74, 168, 36),
	Dirt = Color3.fromRGB(140, 84, 46),
	DirtDark = Color3.fromRGB(110, 64, 34),
	Sand = Color3.fromRGB(240, 214, 150),
	SandWet = Color3.fromRGB(214, 184, 120),
	Stone = Color3.fromRGB(148, 150, 164),
	StoneDark = Color3.fromRGB(108, 110, 126),
	Wood = Color3.fromRGB(176, 112, 60),
	WoodDark = Color3.fromRGB(128, 78, 40),
	Paver = Color3.fromRGB(226, 200, 150),
	PaverAlt = Color3.fromRGB(208, 180, 128),
	Water = Color3.fromRGB(24, 168, 236),
	WaterLine = Color3.fromRGB(175, 235, 255),
	WaterLine2 = Color3.fromRGB(110, 210, 250),
	Foam = Color3.fromRGB(235, 250, 255),
	Leaf = Color3.fromRGB(70, 190, 60),
	LeafDark = Color3.fromRGB(46, 150, 46),
	Trunk = Color3.fromRGB(130, 84, 46),
	Cloud = Color3.fromRGB(255, 255, 255),
	CloudShade = Color3.fromRGB(226, 236, 250),
}

-- Per-map palettes (ART_BIBLE 4.2): every map must look different from a single screenshot.
Theme.Maps = {
	LaserTracer = { -- "Laser Lab"
		floor = Color3.fromRGB(48, 54, 120),
		floorAlt = Color3.fromRGB(58, 66, 146),
		edge = Color3.fromRGB(40, 42, 62),
		edgeTint = Color3.fromRGB(52, 54, 78),
		trim = Color3.fromRGB(255, 211, 38),
		hazard = Color3.fromRGB(255, 28, 36),
		prop = Color3.fromRGB(235, 238, 245),
		propDark = Color3.fromRGB(40, 42, 62),
	},
	Dodgeball = { -- "Sports Day"
		floor = Color3.fromRGB(230, 168, 98),
		edge = Color3.fromRGB(28, 86, 190),
		line = Color3.fromRGB(255, 255, 255),
		band = Color3.fromRGB(36, 122, 246),
		hazard = Color3.fromRGB(235, 48, 58),
		gold = Color3.fromRGB(255, 196, 30),
		prop = Color3.fromRGB(30, 40, 80),
	},
	HoleInTheWall = { -- "Brick Run"
		floor = Color3.fromRGB(124, 222, 44),
		floorAlt = Color3.fromRGB(108, 202, 34),
		edge = Color3.fromRGB(140, 84, 46),
		trim = Color3.fromRGB(176, 112, 60),
		walls = {
			Color3.fromRGB(235, 48, 58),
			Color3.fromRGB(36, 122, 246),
			Color3.fromRGB(138, 72, 240),
			Color3.fromRGB(255, 138, 28),
		},
	},
	Spin = { -- "Pillar Lagoon": pillar tops use Color3.fromHSV((i-1)/12, 0.72, 0.95)
		pillar = Color3.fromRGB(148, 150, 164),
		hub = Color3.fromRGB(255, 211, 38),
		hazard = Color3.fromRGB(235, 48, 58),
		bat = Color3.fromRGB(176, 112, 60),
		batGrip = Color3.fromRGB(235, 48, 58),
	},
	BombTag = { -- "Toy Box"
		floor = Color3.fromRGB(128, 88, 214),
		floorAlt = Color3.fromRGB(114, 76, 196),
		edge = Color3.fromRGB(64, 40, 110),
		curbA = Color3.fromRGB(235, 48, 58),
		curbB = Color3.fromRGB(255, 255, 255),
		blocks = {
			Color3.fromRGB(235, 48, 58),
			Color3.fromRGB(255, 211, 38),
			Color3.fromRGB(36, 122, 246),
			Color3.fromRGB(62, 208, 72),
		},
		bomb = Color3.fromRGB(30, 30, 38),
		spark = Color3.fromRGB(255, 140, 20),
		holder = Color3.fromRGB(255, 40, 40),
		pad = Color3.fromRGB(150, 226, 40),
	},
}

Theme.CornerRadius = UDim.new(0, 12)
Theme.StrokeThickness = 3

return Theme
