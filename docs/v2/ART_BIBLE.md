# Party Dash v2: ART BIBLE

Every builder gets this. All values are exact. A "tune" range appears only where a value has to be checked by eye in Studio, and the check is spelled out with it.
I studied ref1 to ref5, current-game-koth.jpg, every world builder, the UI kit, and the asset pipeline the lead has already started (`assets/raw/sheetA_menu.png`, `sheetB_currency.png`, `sheetC_items.png`, `assets/textures/*.png`, `src/shared/Assets.lua`).

---

## 0. The target look in one paragraph

The world is a blocky, sunny, high-contrast island world, like ref1, ref2 and ref4. Each walkable top is a **saturated, textured** surface. A **dark, textured cliff band** runs under its edge, and it sits in (or rises out of) a **saturated turquoise cartoon sea with white wave lines**, under a **clear blue sky**. There is no haze, no pastel and almost no Neon. **Only hazards glow or carry an outline.**
The UI uses chunky illustrated icon tiles with thick ink outlines and a 3D bottom lip. Panels have colored header bars on a neutral dark body, labels are in FredokaOne, and screens are full of live numbers, timers and prices.

---

## 1. Diagnosis: why the current game looks washed-out and blends together

Seen in `current-game-koth.jpg`: mint floor, white frosting, pale cyan sea, a white horizon and a milky sky. All the large areas sit at value 0.85-1.0 with low saturation, so the floor, the sea and the sky melt into one bright smear.

| # | Cause | Where |
|---|---|---|
| 1 | Three brightness boosts are stacked: `Brightness = math.max(3,3)` (1.5x the Roblox default of 2), `ExposureCompensation = 0.1`, and CC `Brightness = 0.03`. Light-colored top faces clip to near-white. | `src/server/Core/LightingSetup.lua:30, :37, :57` |
| 2 | The ambient light is far too high: `OutdoorAmbient (165,165,185)` and `Ambient (125,120,150)` (Roblox defaults are 128/70). Shadowed faces end up almost as bright as lit ones, so blocks lose their form shading and everything reads as flat. | `LightingSetup.lua:31-32` |
| 3 | `ColorShift_Top (255,245,225)` adds near-white sun tint to every upward face, so floors burn out. The LT builder already says so in a comment ("pale tiles burn out to white"). | `LightingSetup.lua:33`; `Minigames/LaserTracer/Arena.lua:28-30` |
| 4 | The Atmosphere puts a milky veil over everything: `Density 0.24, Haze 0.6, Glare 0.15, Color (205,232,255)`. Beyond about 100 studs everything turns white-blue, the horizon goes white, and the sea and sky get the same tint. | `LightingSetup.lua:44-52` |
| 5 | Bloom `Intensity 0.45, Size 26` runs on **42 `Enum.Material.Neon` usages** across `src/`. Neon smears into pink/cyan halos (P4 reported that the red laser looked pink-magenta). | `LightingSetup.lua:60`; grep `Enum.Material.Neon` |
| 6 | CC `Saturation +0.28` is applied to colors that are already pastel or clipped. It can't bring back hue that was lost; it only makes the Neon halos look garish. | `LightingSetup.lua:53-59` |
| 7 | There are **zero textures**. Every part is SmoothPlastic (`Core/Build.lua:10`, `Maps/Lobby.lua:46`, every Arena/Map `part()` helper), and `src/` contains no `Texture` or `Decal` instances. Without surface detail the eye has no scale or ground cue, so big areas read as flat blobs. The references are 100% textured (brick dirt, bevel/checker grass, wave water). | grep |
| 8 | The palette is pastel and then lightened further. `Theme.MapPalette` (Theme.lua:34-40) is all pastels, and the builders mix toward white on top of that: HitW `pastel()` lerps 30% to white (`HoleInTheWall/Arena.lua:41-43`), the lobby tiles lerp 22% (`Maps/Lobby.lua:138`), and the Spin bar shell lerps 50% with Glass at 0.65 (`Spin/Arena.lua:281`). KotH uses pastel tiers with white frosting. | |
| 9 | The water is terrain water with `WaterTransparency 0.25`, `WaterReflectance 0.6`. It mirrors the hazy white sky, so the result is pale cyan with no pattern. | `Core/World.lua:36-42` |
| 10 | The geometry language is wrong. Round discs, balls, lollipops, mushrooms and candy beads (`Build.disc/ball/ellipsoid`, `Lobby.lua:353-458`) give a Fall-Guys candy look, while the references are **blocky/voxel**. Floor edges are white frosting or a yellow Neon rim (`LaserTracer/Arena.lua:135-157`), so the walkable area has **no dark silhouette edge**. | |
| 11 | The arena floats 62 studs above the sea (`World.lua:14`) and has a cloud layer between them (`World.lua:212-217`). When the camera looks down, the background behind the floor is white clouds plus pale sea. | |
| 12 | The UI uses the classic AI-slop tells: purple-navy everywhere (`Theme.Colors.Panel (45,38,80)`, the purple pill gradient at `UI/Hud.lua:146`), emoji icons (`UI/Data.lua:26-47`, `Economy/Cosmetics.lua:83-85`), rainbow per-letter logo text (`UI/Lobby.lua:17`), a coin drawn from Frames (`UI/Kit.lua:140-194`), an empty "TOP 3" box, and a debug-looking "SHIFT [DASH] C SLIDE" strip. | |

---

## 2. LIGHTING preset "PD_Day" (crisp, saturated, readable)

### 2.1 Studio-side settings (once, saved in the place; game scripts cannot set these)
Run these with `execute_luau` in the Edit datamodel, then save the place:
- `game.Lighting.Technology = Enum.Technology.ShadowMap`: crisp sun shadows, cheap on phones, the classic simulator look.
- If the property exists: `game.Lighting.LightingStyle = Enum.LightingStyle.Realistic` (do NOT use Soft, which flattens shading).

### 2.2 `LightingSetup.apply()`: replace the body with these exact values
```lua
for _, child in Lighting:GetChildren() do
	if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
		child:Destroy()
	end
end
Lighting.ClockTime = 14            -- see sun check below
Lighting.GeographicLatitude = 25   -- see sun check below
Lighting.Brightness = 2.2
Lighting.ExposureCompensation = 0
Lighting.Ambient = Color3.fromRGB(64, 66, 84)
Lighting.OutdoorAmbient = Color3.fromRGB(118, 124, 148)   -- slightly cool shadows
Lighting.ColorShift_Top = Color3.fromRGB(255, 236, 205)   -- mild warm sun
Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
Lighting.EnvironmentDiffuseScale = 0.35
Lighting.EnvironmentSpecularScale = 0.15                  -- kills the grazing-angle white sheen on plastic
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.12
Lighting.FogStart = 0
Lighting.FogEnd = 100000
make("Sky", { Name = "Sky", SunAngularSize = 12, MoonAngularSize = 11, StarCount = 0, CelestialBodiesShown = true })
-- (no Skybox ids = Roblox classic blue sky with cartoon cumulus, which is what ref4 shows)
make("Atmosphere", { Name = "Atmosphere", Density = 0.12, Offset = 0.05,
	Color = Color3.fromRGB(170, 218, 255), Decay = Color3.fromRGB(110, 170, 235), Glare = 0, Haze = 0 })
make("BloomEffect", { Name = "Bloom", Intensity = 0.3, Size = 16, Threshold = 1.8 })
make("ColorCorrectionEffect", { Name = "Grade", Brightness = 0, Contrast = 0.08, Saturation = 0.12,
	TintColor = Color3.fromRGB(255, 255, 255) })
-- NO SunRaysEffect, NO DepthOfFieldEffect, NO Terrain.Clouds (cost on mobile, and they read as realistic, not cartoon)
```
`LightingData.lua` (legacy values) must no longer feed anything. Drop the `LightingData.Brightness` / `GeographicLatitude` reads at `LightingSetup.lua:29-30`.

### 2.3 Checks a builder or critic runs in Studio
1. **Sun direction.** Players spawn in the lobby looking +Z (`Lobby.lua:495`). The sun must sit **behind** that camera so the faces players see are lit and saturated, not backlit. Required: `Lighting:GetSunDirection()` has **Z < -0.2** and **0.6 <= Y <= 0.85**. If Z > 0, set `GeographicLatitude = -25`. If Y is too high or too low, move `ClockTime` within 13.0-15.5.
2. **Exposure** (screen_capture from the lobby spawn, sunlit grass top). The pixel must fall in **R 80-130, G 180-235, B 25-80**. If G > 235 or the color looks yellow-white, lower Brightness in 0.1 steps (floor 1.8). If G < 180, raise it (cap 2.6).
3. **Horizon.** The sky right at the horizon must stay blue (B - R >= 50), and the far edge of the sea plane must not show as a hard line. If it does, raise Atmosphere.Density in 0.03 steps (max 0.2). **Never** raise Haze.
4. **Neon budget.** Neon covers 5% of the frame or less during a round (see 3.5).

### 2.4 Optional per-map variant (client-only, nice-to-have)
Lighting changes made by a LocalScript stay local. A client module can tween these three properties over 1.5 s when the local player is InRound or Spectating on a given MinigameId, and tween back in the lobby. Skip this if time is short.

| Map | ClockTime | Brightness | ColorShift_Top | Atmosphere.Color / Decay |
|---|---|---|---|---|
| Lobby, Dodgeball, HoleInTheWall, BombTag | 14 | 2.2 | (255,236,205) | (170,218,255) / (110,170,235) |
| LaserTracer ("golden hour laser show") | 17.4 | 1.9 | (255,190,140) | (255,196,170) / (140,110,200) |
| Spin | 15.5 | 2.1 | (255,220,180) | (190,220,255) / (110,170,235) |

---

## 3. WORLD MATERIALS: the blocky brick/stud/checker look

### 3.1 Geometry rules
- **Everything structural is axis-aligned blocks on a 2-stud grid.** Islands, cliffs, terraces, trees, fences and signs all follow it. Use cylinders and balls only for small props: wheel hub, balloons, bomb, laser nodes.
- Round arenas (LT, Dodgeball) are built as a **voxel disc**: horizontal strips 4 studs deep (one Part per strip, X extent snapped to multiples of 4), so the rim is stair-stepped like ref1. This takes about 21 parts for r=42, not 300 tiles.
- **Never put a Texture on a Cylinder or Ball part**; the mapping stretches. If a part must stay round, give it a flat color plus a darker rim ring.
- Every walkable top has a **cliff band** under its edge. It is at least 2 studs tall, textured, and darker or contrasting (rules in 4.4), and it continues down to the sea (section 5).
- Floor parts start on multiples of their StudsPerTile (positions and sizes multiples of 8 for 8-stud tiles). Textures then line up across neighbouring parts without any OffsetStuds math.

### 3.2 Texture tiles
These already exist in `Assets.Textures`, made by `tools/gen_textures.py`. They are 256 px, grayscale, and tinted by `Texture.Color3`, which multiplies:
`tile_bevel` (1 beveled block), `tile_bevel_2x2`, `studs` (2x2 LEGO studs), `checker`, `checker_soft`, `bricks` (4 rows x 2), `planks` (4 vertical planks), `waves` (white Voronoi lines on alpha), `hazard` (diagonal stripes), `speckle`.

**Add these to `gen_textures.py`** (lead or tools owner), then upload them and add them to the manifest:
| New tile | Content | Used for |
|---|---|---|
| `grass_top.png` | `tile_bevel_2x2` where the two diagonal cells are 8% darker (a beveled checker; it reproduces ref2 and ref4 in one opaque layer) | grass floors |
| `stone_blocks.png` | irregular large blocks: 3 rows, random widths of 60-140 px, 6 px mortar at gray 150, blocks 205-235, same bevel style as `bricks` | stone pillars/cliffs |
| `awning.png` | vertical stripes, 2 white plus 2 gray-90 (tint red gives red/white) | shop awning, umbrellas, candy bars |
| `laser_dash.png` | 64x16: white rect over x 0-26, the rest transparent | high-laser candy dashes (Beam texture) |
| `stripes_diag.png` | white 45° bands, 24 px wide, 24 px gap, on alpha | UI header gloss stripes (ref5) |
| `glow_soft.png` | 256 px radial white to transparent (alpha 1 to 0, smoothstep) | UI tab glow, icon backlights |

### 3.3 Surface recipes
For every recipe: `Part.Material = SmoothPlastic` and `Part.Color = tint`, so distant LOD looks the same. One `Texture` goes on each listed face with `Texture.Color3 = tint`. Remember that the PNG's gray multiplies the tint, so the rendered average comes out at about 0.9x the tint.

| Recipe | Tint RGB | Texture | Faces | StudsPerTileU x V | Texture.Transparency |
|---|---|---|---|---|---|
| `grass_top` | (100,210,45) | grass_top (fallback tile_bevel_2x2) | Top | 8 x 8 | 0 |
| `grass_lip` (1.5-stud green band along a cliff's top edge, overhang 0.3) | (74,168,36) | tile_bevel | Front/Back/Left/Right | 2 x 2 | 0 |
| `dirt_cliff` | (140,84,46) | bricks | Front/Back/Left/Right | 8 x 8 | 0 |
| `dirt_cliff_low` (lower terrace) | (110,64,34) | bricks | sides | 8 x 8 | 0 |
| `stone` | (148,150,164) | stone_blocks (fallback bricks) | sides | 10 x 10 | 0 |
| `stone_top` | (160,162,176) | tile_bevel_2x2 | Top | 8 x 8 | 0 |
| `wood` (fences, stalls, docks) | (176,112,60) | planks | all 6 | 8 x 16 (fence rails 4 x 4) | 0 |
| `sand` | (240,214,150) | speckle | Top + sides | 12 x 12 | 0 |
| `paver` (paths, plaza, spawn) | (226,200,150) | tile_bevel | Top | 4 x 4 | 0 |
| `hazard_trim` | (255,211,38) | hazard | Top + outer side | 6 x 6 | 0 |
| `toy_block` (Bomb Tag obstacles) | block color | studs on Top; tile_bevel on sides with StudsPerTile = that face's size (one bevel frame per face) | Top + sides | top 4 x 4 | 0 |
| `lt_tile` (Laser Tracer floor) | (48,54,120), alt strips (58,66,146) | tile_bevel | Top | 6 x 6 | 0 |
| `steel` (LT cliff) | (52,54,78) | tile_bevel_2x2 | sides | 6 x 6 | 0 |
| `maple` (Dodgeball court) | (230,168,98) | planks | Top | 6 x 24 | 0 |
| `turf_check` (HitW floor) | (124,222,44) | checker_soft | Top | 8 x 8 (4-stud squares) | 0 |
| `brick_wall_<color>` (HitW walls) | wall color | bricks | Front/Back | 8 x 8 | 0 |
| `foam_mat` (Bomb Tag floor) | (128,88,214) | tile_bevel_2x2 | Top | 8 x 8 | 0 |
| `leaf` (blocky canopy) | (70,190,60), dark (46,150,46) | tile_bevel_2x2 | all 6 | 6 x 6 | 0 |
| `trunk` | (130,84,46) | planks | sides | 2 x 6 | 0 |
| `water` | Part (24,168,236) | layer A: waves, Color3 (175,235,255), U/V 28, Transparency 0.15. Layer B: waves, Color3 (110,210,250), U/V 43, OffsetStudsU 14, OffsetStudsV 9, Transparency 0.55 | Top | see left | see left |
| `cloud` | (255,255,255), underside boxes (226,236,250) | none | n/a | n/a | n/a |

Do not use legacy `SurfaceType.Studs`: it gives 1-stud studs, which are far too busy at a distance and can't be controlled. Do not use the built-in Grass, Slate, Rock, CrackedLava or DiamondPlate materials: they are realistic PBR and fight the cartoon tiles.

### 3.4 Shared helper (suggested `src/shared/WorldKit.lua`, owned by Core)
```lua
WorldKit.RECIPES                                   -- the table above, keyed by recipe name
WorldKit.skin(part: BasePart, recipe: string, faces: {Enum.NormalId}?)  -- sets Material/Color + creates Textures
WorldKit.block(parent, name, size: Vector3, cf: CFrame, recipe: string, collide: boolean?): Part
WorldKit.voxelDisc(parent, center: CFrame, radius: number, cell: number, topRecipe: string, height: number): {Part}
WorldKit.cliff(parent, center: CFrame, footprint: {Part} | Vector2, topY: number, seaY: number, upper: string, lower: string)
      -- grass/trim lip (1.5) + upper band to topY-6 + lower band to seaY-2 + foam ring at seaY
WorldKit.foam(parent, rectOrRadius, seaY)          -- 2-stud wide frame, Color (235,250,255), Transparency 0.25, 0.2 thick, at seaY+0.05
WorldKit.blockTree(parent, groundPos, scale) / WorldKit.palm(parent, groundPos, scale) / WorldKit.cloud(parent, pos, scale, rng)
```
Every map builder (Lobby, LT, Dodgeball, HitW, Spin, BombTag, Stands, Solo Backdrop) uses this module, so the whole game shares one material language.

### 3.5 Neon and hazard-readability budget
- Neon is allowed **only** on: lasers (LT), the bomb spark/fuse, pickups (golden ball), the lobby join-zone border, jump pads, telegraph flashes, Spin bar tips and the wheel bulbs. That's it.
- Remove Neon from: the LT rim `Glow` (`LaserTracer/Arena.lua:148-155`, replace with `hazard_trim`); the Spin pillar `Band`/`Glow` (`Spin/Arena.lua:115-131`, use SmoothPlastic at the pillar color); the Spin `HubRim`/`HubBand` (`:144-156`); the HitW pylon `Ring` (`HoleInTheWall/Arena.lua:145-147`); the Spin bar `Core` (`Spin/Arena.lua:274`, use SmoothPlastic with the awning candy texture); the Spin `Shell` Glass (`:281`, delete it, because the visual bar must equal the hit bar).
- Moving hazards get a **Highlight** so they read against any background: `FillTransparency 1, OutlineColor (22,18,36), OutlineTransparency 0, DepthMode Occluded`. Use it on dodgeballs, Spin bars, HitW walls and the bomb. Roblox renders at most 31 Highlights; reserve them in this order: bomb holder > Spin bars > walls > balls.

---

## 4. PALETTE

### 4.1 Theme v2 (lead edits `src/shared/Theme.lua`; existing keys are kept, values change, new keys are added)
```lua
Theme.Font = Enum.Font.FredokaOne
Theme.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
Theme.FontHype = Font.new("rbxasset://fonts/families/LuckiestGuy.json", Enum.FontWeight.Regular)   -- NEW
Theme.FontBody = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)      -- NEW
Theme.FontBodyHeavy = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold) -- NEW

Theme.Colors = {
	Yellow = Color3.fromRGB(255, 211, 38),  YellowDark = Color3.fromRGB(214, 140, 0),
	Orange = Color3.fromRGB(255, 138, 28),  OrangeDark = Color3.fromRGB(198, 82, 8),
	Pink   = Color3.fromRGB(255, 78, 166),  PinkDark   = Color3.fromRGB(186, 28, 108),
	Red    = Color3.fromRGB(235, 48, 58),   RedDark    = Color3.fromRGB(160, 22, 36),
	Purple = Color3.fromRGB(138, 72, 240),  PurpleDark = Color3.fromRGB(86, 34, 170),
	Blue   = Color3.fromRGB(36, 122, 246),  BlueDark   = Color3.fromRGB(18, 72, 182),
	Cyan   = Color3.fromRGB(28, 196, 245),  CyanDark   = Color3.fromRGB(0, 128, 196),
	Green  = Color3.fromRGB(62, 208, 72),   GreenDark  = Color3.fromRGB(24, 138, 44),
	Lime   = Color3.fromRGB(150, 226, 40),
	Gold   = Color3.fromRGB(255, 196, 30),
	Silver = Color3.fromRGB(200, 206, 222), Bronze = Color3.fromRGB(214, 128, 56),
	White  = Color3.fromRGB(255, 255, 255),
	Ink       = Color3.fromRGB(22, 18, 36),   -- outlines, text strokes
	InkSoft   = Color3.fromRGB(52, 46, 76),
	Panel     = Color3.fromRGB(38, 34, 56),   -- neutral dark charcoal-violet (was a purple (45,38,80))
	PanelDeep = Color3.fromRGB(26, 23, 40),
	PanelLight= Color3.fromRGB(56, 50, 82),   -- cards on a panel
	Muted     = Color3.fromRGB(186, 180, 212),-- secondary text on dark
	Disabled  = Color3.fromRGB(140, 140, 156),
	Laser     = Color3.fromRGB(255, 28, 36),
	LaserAlt  = Color3.fromRGB(255, 28, 36),  -- brief #13: BOTH laser heights are red; height is shown by shape
	Danger    = Color3.fromRGB(255, 40, 40),
}
Theme.MinigameColors = {           -- roulette card / intro accent; five distinct hues
	LaserTracer = Color3.fromRGB(235, 48, 58),   -- red
	Dodgeball = Color3.fromRGB(36, 122, 246),    -- blue
	HoleInTheWall = Color3.fromRGB(62, 208, 72), -- green
	Spin = Color3.fromRGB(138, 72, 240),         -- purple
	BombTag = Color3.fromRGB(255, 211, 38),      -- yellow (NEW)
	KingOfTheHill = Color3.fromRGB(255, 211, 38),-- kept only so old code doesn't nil-index
}
Theme.MapPalette = { -- generic deco only, NEVER floors
	Color3.fromRGB(235, 48, 58), Color3.fromRGB(255, 138, 28), Color3.fromRGB(255, 211, 38),
	Color3.fromRGB(62, 208, 72), Color3.fromRGB(36, 122, 246), Color3.fromRGB(138, 72, 240),
}
Theme.Rarity = { Common = Color3.fromRGB(170,178,196), Rare = Color3.fromRGB(36,122,246),
	Epic = Color3.fromRGB(138,72,240), Legendary = Color3.fromRGB(255,170,20), Limited = Color3.fromRGB(255,60,140) }
Theme.World = {
	GrassTop = Color3.fromRGB(100,210,45), GrassAlt = Color3.fromRGB(88,194,38), GrassLip = Color3.fromRGB(74,168,36),
	Dirt = Color3.fromRGB(140,84,46), DirtDark = Color3.fromRGB(110,64,34),
	Sand = Color3.fromRGB(240,214,150), SandWet = Color3.fromRGB(214,184,120),
	Stone = Color3.fromRGB(148,150,164), StoneDark = Color3.fromRGB(108,110,126),
	Wood = Color3.fromRGB(176,112,60), WoodDark = Color3.fromRGB(128,78,40),
	Paver = Color3.fromRGB(226,200,150), PaverAlt = Color3.fromRGB(208,180,128),
	Water = Color3.fromRGB(24,168,236), WaterLine = Color3.fromRGB(175,235,255), WaterLine2 = Color3.fromRGB(110,210,250),
	Foam = Color3.fromRGB(235,250,255),
	Leaf = Color3.fromRGB(70,190,60), LeafDark = Color3.fromRGB(46,150,46), Trunk = Color3.fromRGB(130,84,46),
	Cloud = Color3.fromRGB(255,255,255), CloudShade = Color3.fromRGB(226,236,250),
}
Theme.CornerRadius = UDim.new(0, 12)
Theme.StrokeThickness = 3
```
Follow-ups: `client/Minigames/LaserTracer/Motion.lua:35-38` must use `high = Theme.Colors.LaserAlt` (it is cyan today). `client/Solo/Emblems.lua:40-43` uses LaserAlt and must be checked. Cosmetic swatches in `Economy/Cosmetics.lua` change shade automatically.

### 4.2 Per-minigame palettes (every map must look different)
| Map (theme) | Floor / alt | Edge band (cliff) | Trim | Hazard (reserved hue) | Props | Card accent |
|---|---|---|---|---|---|---|
| **Lobby** "Sunny Isle" | grass (100,210,45)/(88,194,38) | dirt bricks (140,84,46), lip (74,168,36), lower (110,64,34) | wood (176,112,60), pavers (226,200,150) | none (no hazards in the lobby) | palms, block trees, fences, stalls | n/a |
| **Laser Tracer** "Laser Lab" | indigo tiles (48,54,120)/(58,66,146) | steel (40,42,62), texture tint (52,54,78) | 1.2-stud yellow/ink `hazard_trim` rim flush at floor top | **red lasers (255,28,36)** | white towers (235,238,245), dark caps (40,42,62) | Red |
| **Dodgeball** "Sports Day" | maple planks (230,168,98) | blue stadium band (28,86,190) with a 0.6 white stripe, then stone cliff | white court lines (255,255,255), 3-stud blue out-band (36,122,246) inside the rim, blue center circle with white ring | **red balls (235,48,58) + white seam + Highlight**; golden ball (255,196,30) Neon | navy cannons (30,40,80) + white bands + red muzzle ring | Blue |
| **Hole in the Wall** "Brick Run" (ref4) | turf checker (124,222,44)/(108,202,34), 4-stud squares | dirt bricks | 1-stud wood plank border | **walls rotate** Red (235,48,58) / Blue (36,122,246) / Purple (138,72,240) / Orange (255,138,28) with bricks; hole inner faces = wall color darkened 0.4 | none on the floor | Green |
| **Spin** "Pillar Lagoon" | pillar tops: `Color3.fromHSV((i-1)/12, 0.72, 0.95)` with a 0.6-stud rim at the same hue, V 0.45 | stone_blocks columns into the water | yellow hub cap (255,211,38) | **red/white candy bars** (awning texture tinted (235,48,58)) + yellow Neon tips + Highlight | bat (176,112,60) with red grip (235,48,58) | Purple |
| **Bomb Tag** "Toy Box" | purple foam mat (128,88,214)/(114,76,196) | dark purple band (64,40,110), then stone cliff | red/white curb blocks | **bomb (30,30,38) + orange spark (255,140,20); holder Highlight red (255,40,40)** | toy blocks Red/Yellow/Blue/Green with studs; jump pads Lime Neon ring | Yellow |

### 4.3 Contrast rules (numeric; use `Color3:ToHSV()`)
1. **Floors:** S >= 0.45 and 0.45 <= V <= 0.90. No pastels. `:Lerp(White, x)` is banned on any world color.
2. **Edge band vs floor:** ΔV >= 0.25, **or** hue difference >= 90° with ΔV >= 0.12. (Lobby 0.82 vs 0.55 passes. LT 0.47 vs 0.24 passes. Dodgeball orange vs blue passes on hue. Bomb Tag 0.84 vs 0.43 passes.)
3. **Blue/cyan (hue 180-225°) belongs to the water and sky.** No walkable floor uses it. (LT indigo is hue 235° at V 0.47, which is allowed.)
4. **White belongs to clouds, text and small trims**, at most 10% of the frame. No white floors, no white frosting bands.
5. **Hazards:** S >= 0.8, V >= 0.9 (the bomb is the only dark exception: it reads through its spark plus Highlight). The hazard hue sits at least 40° from the floor hue, and no decoration on that map uses the hazard hue.
6. **Players:** the floor V stays within 0.45-0.90 so any avatar (dark or light) separates from it. Nameplates use ink-stroked text (see 8).
7. **Decoration never sits inside the gameplay silhouette.** Nothing taller than 1 stud on a playable floor unless it is an obstacle. Decoration outside the rim stays below floor level or more than 12 studs away.

---

## 5. BACKDROP and world layout (sea, sky, islands, clouds, kill planes)

### 5.1 The world is islands IN the sea (not floating 62 studs up)
This is ref1: a dark brick cliff band separates the bright top from bright water, and that is the single biggest readability fix. Falling becomes **a splash into the water = out**, which matches the owner's mental model (brief #16).

The values below change keys the lead owns. Changing values is allowed; new keys are additions.
| Key | Old | New |
|---|---|---|
| `Config.LOBBY_CENTER` | (0,50,0) | **(0,50,0)** (grass top at Y 50) |
| `Config.ARENA_CENTER` | (0,50,0) | **(0,50,340)**: the arena island sits north of the lobby, visible from the join zone. The lobby must persist during rounds for #14, #17 and #26, so `Places.destroyLobby()` at `Core/RoundLoop.lua:296` must stop destroying it. |
| `Config.SEA_DROP` (NEW) | n/a | **14**: water surface = center.Y - 14 (Y 36) |
| `Config.KILL_DEPTH` | 30 | **17**: killY = water - 3, so the elimination fires just after the splash |
| `Config.SPECTATOR_OFFSET` | (0,45,-110) | **(-84,4,0)**: stands on their own islet west of the arena, out of the lobby's line of sight |
| `World.SEA_LEVEL` (`World.lua:14`) | ARENA_CENTER.Y - 62 | `Config.ARENA_CENTER.Y - Config.SEA_DROP` |
| `Spin/Arena.lua:32 KILL_DEPTH` | 24 | delete the override (use Config), or 17 |
| `Places.RESCUE_Y` (`Places.lua:16`) | min(...) - 30 | `Config.LOBBY_CENTER.Y - Config.SEA_DROP - 3` |
| `Solo/Backdrop.lua:20 SEA_DROP` | 62 | `Config.SEA_DROP` |

### 5.2 Sea = Parts, not terrain water
- `World.init` first calls `workspace.Terrain:Clear()`, which removes the terrain water and any terrain left in the place.
- Sea: a **3x3 grid of Parts**, each `Size (2048, 1, 2048)`, top face at SEA_Y, the grid centered at (0, SEA_Y - 0.5, 170) (midway between the lobby and the arena), so it covers X ±3072 and Z -2902..3242. Each part has the `water` recipe (two waves Textures), `CanCollide = false`, `CanQuery = false`, `CanTouch = false`, `CastShadow = false`, `Reflectance 0`.
  - Because the water is not collidable, **nobody can swim**, and the swimming-bug class of #16 is gone. Players sink through the water and die at killY.
- **Wave animation** (client, one loop for all sea parts): `OffsetStudsU += 1.1*dt`, `OffsetStudsV += 0.45*dt` on layer A; `OffsetStudsU -= 0.6*dt`, `OffsetStudsV += 0.8*dt` on layer B. Write every 1/30 s, wrapping modulo the tile size.
- **Splash** (client; triggers when any character's HRP crosses SEA_Y going down): a ring Cylinder 0.2 high, Color (235,250,255), grows from 2 to 10 studs in diameter while Transparency goes 0.2 to 1 over 0.5 s. Plus a ParticleEmitter `:Emit(40)` with Color (255,255,255) to (150,225,255), Size 0.6 to 0, Speed 18-28, SpreadAngle 25, Acceleration (0,-90,0), Lifetime 0.6-0.9. Plus the splash sound.
- **Shore foam** around every island: `WorldKit.foam`, Color (235,250,255), Transparency 0.25.
- **Lobby wading shelf**: a collidable `sand` slab whose top sits at SEA_Y - 1.6, extending 14 studs out from the beach terrace. Kids can wade like the player in ref1. Past the shelf is deep water: they fall, get rescued and splash back on the beach.

### 5.3 Islands, rocks, clouds, sky
- **Arena island**: each minigame builds its own floor at center.Y. `WorldKit.cliff` continues every edge down to SEA_Y - 2: a lip or trim band, an upper band of 6 studs, then a lower band to the water, then foam.
- **Distant voxel islands**: 10 of them, decorative (no collide, query or touch), at **260-700 studs** from (0, SEA_Y, 170). No island sits within 120 studs of the lobby or arena edges, and a **60°-wide corridor centered on +Z from the lobby stays clear**, so the arena is always visible from the join zone.
  - 3 large: footprint 80-130 studs, 2-3 stepped terraces, top 18-30 above water, 3-5 block trees, 2 palms.
  - 4 medium: 40-70 studs, 1-2 terraces, top 8-16 above water.
  - 3 sand islets: 20-36 studs, 2-3 above water, 1-2 palms, a beach umbrella.
  - Plus 6 sea rocks (`stone`, 6-12 stud blocks, 2-6 above water).
- **Blocky trees**: trunk 2x8x2 (`trunk`); canopy 10x6x10 plus 7x4x7 offset (+1.5, +4, -1) (`leaf`, top block uses LeafDark).
- **Palms**: 5 trunk cubes of 1.6 stud, each stepping +0.5 X / +2 Y; 6 leaf slabs 1.4 x 0.4 x 7 radiating, drooping 20°, Leaf/LeafDark alternating; 2 coconuts (balls (110,70,40) d 1.2).
- **Clouds**: 14 blocky clouds. Each is 3-6 white boxes (12-40 x 6-12 x 10-24), and the bottom box uses CloudShade. Place them at Y = SEA_Y + 110..190, horizontal distance 350-900, `CastShadow = false`. On the client they drift +X at 2 studs/s and wrap at ±1000.
- **Delete** the floating islands (`World.lua:177-193`), the low cloud layer (`World.lua:212-217`) and the round `Build.cloud`. Keep the **2 hot-air balloons** at SEA_Y + 70..110, each with a `wood` basket.
- **Sky**: the default Sky instance from 2.2; no custom skybox.
- **Solo copies** (`Solo/Backdrop.lua`): the same recipe around each solo center: 3x3 sea tiles, 4 islands (1 large, 2 medium, 1 islet), 6 clouds.

---

## 6. LOBBY LAYOUT (#26 join square, #27 chests, #29 wheel, shop, leaderboards, spawn)

### 6.1 Island shape (coordinates relative to LOBBY_CENTER `o`; +Z is north, toward the arena; grass top = o.Y)
- **Plateau**: X -64..64, Z -56..56 (128 x 112), with 8x8 notches cut at the 4 corners. Top: `grass_top`. Edge: 1.5-stud `grass_lip`, then `dirt_cliff` down to o.Y - 6.
- **Terrace ring**: 10 studs wide at o.Y - 6. Sand on the S and E, grass on the N and W. Its edge is `dirt_cliff_low` down to SEA_Y (o.Y - 14).
- **Stairs**: block steps 8 wide, 2 studs per step, at S (0,-56), W (-64,0) and E (64,0), plateau to terrace. Two more from terrace to shelf.
- **Wading shelf** (5.2) and invisible boundary walls at the shelf's outer edge, 30 tall.
- **Paths** (`paver`, 8 wide, 0.1 above grass): spawn (0,-31) to plaza (0,-14); plaza (0,18) to join pad (0,24); plaza to shop (-36,4); plaza to wheel (36,4).

### 6.2 Top-down sketch (not to scale; exact numbers in 6.3)
```
                       N (+Z)   ~~~ arena island on the horizon, 340 studs ~~~
   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ sea / wading shelf ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   ~~  terrace (grass)  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 z+56 +-fence------------------[====== PLAY ARCH ======]------------------fence-+
      |  [TOP WINS]           |                       |           [TOP SOLO]   |
 z+36 |   board (-48,34) \    |   JOIN ZONE  24 x 24  |    / board (48,34)     |
      |                       |   yellow/white checker|                        |
 z+24 |   block tree          +-----------------------+         block tree     |
      |                                 ||                                     |
 z+4  | [SHOP STALL]  ====paver====( PLAZA r14 )====paver====  [LUCKY WHEEL]   |
      |  (-46,4) faces +X          ( winners podium )          (46,4) faces -X |
      |                                 ||                                     |
 z-18 |          [DAILY CHEST]          ||          [GROUP CHEST]              |
      |            (-20,-18)            ||            (20,-18)                 |
 z-38 |  palm                 [  SPAWN PAD 24 x 14  ]                   palm   |
      |                          (0,-38), faces +Z                             |
 z-56 +-----stairs----------------------stairs---------------------stairs------+
   ~~ sand terrace: palms x8, umbrellas x3, dock 8x30 at (0,-86) ~~~~~~~~~~~~~~~~
                    S (-Z)        x = -64 ........... 0 ........... +64
```
The flow: you spawn facing north. Two chests are the first thing you see (daily hook). Shop and wheel flank the plaza (impulse buys). The join zone is ahead, with the leaderboards angled at it (competition while you wait), and the live arena island sits behind the PLAY arch.

### 6.3 Stations (center x,z; footprint; facing)
| Station | Center | Build spec |
|---|---|---|
| **Spawn pad** | (0,-38), 24x14 | `paver` slab 0.2 high. Top: a Decal of `logo` (9.1), 16x10, Transparency 0. The 12 spawn points move here; players face +Z. |
| **Daily chest** (#27) | (-20,-18) | Pedestal 9x1x9 `stone_top`. Chest 7x5x5: `wood` body, gold bands (255,196,30) 0.6 thick, gold lock, hinged lid (opens 70° over 0.4 s on claim). When READY, a Neon ring (255,211,38) pulses on the pedestal (Transparency 0.2 to 0.6, 1 Hz); on cooldown it is dim (0.85). Yaw: front faces the spawn. |
| **Group chest** (#27) | (20,-18) | Same chest, gold body (255,196,30) with a blue band (36,122,246) and a white star emblem (matches `chest_group` icon). |
| **Plaza + winners podium** | (0,4), circle r 14 | Plaza in `paver`. Podium faces -Z (toward the spawn): 1st block 8x5x6 Gold, 2nd 8x3.5x6 Silver at x -8, 3rd 8x2.5x6 Bronze at x +8. Avatars of last round's top 3 via `Players:CreateHumanoidModelFromUserId`, anchored and posed. This is competition (#8). |
| **Shop stall** | (-46,4), 18x12, faces +X | 4 `wood` posts 1.2x9x1.2; counter 14x3.5x3 `wood`; sloped awning (15°) of 2-stud stripes alternating Red/White (`awning` texture); top board 14x4 showing `shop` icon plus "Shop" in FredokaOne. Props: coin-block pile, a bat on the counter. ProximityPrompt opens the Shop UI. |
| **Lucky wheel** (#29) | (46,4), faces -X | Wheel = Cylinder 1.5 thick, 18 diameter, its face showing `wheel_face.png` (procedural, 8.6) via SurfaceGui. Gold rim (255,196,30), 16 Neon bulbs d 0.8 alternating Yellow/White in a chase (0.12 s step). Red pointer wedge at the top. Stand: two `wood` A-frame legs plus a red base 10x2x6. The client spins it when anyone spins (sync to the server result). Prompt opens the Wheel UI (9 Robux per spin). |
| **Join zone** (#26) | (0,36), pad 24x24, 0.4 high | Yellow (255,211,38) / White (255,250,230) checker in 4-stud squares (`checker` tinted). Border: 1-stud Neon frame, White idle, Green (60,255,90) pulsing while counting, Yellow flashing in the last 5 s. **PLAY arch** on the north edge at z 48: pillars 3x16x3 at x ±13 in alternating Red/White 2-stud blocks; beam 30x3x3; board 22x6 reading "PLAY" (FredokaOne, white, Green gradient, Ink stroke 6), facing -Z. A BillboardGui above the pad shows "3/12 READY" and "0:12" in LuckiestGuy. While active, sparkles rise from the pad edges (Green). |
| **TOP WINS board** | (-48,34), yaw to (0,30) | 2 `wood` posts plus a 20x14 board, header 20x3 Gold, body Panel (38,34,56), 10 rows (medal icon, avatar thumbnail circle, name, wins), with a 3D gold crown on top. |
| **TOP SOLO board** | (48,34), yaw to (0,30) | Same frame with an Orange header. This is the existing `LeaderboardAnchor` (Solo mounts on it); keep that part name and keep it a direct child. |
| **Decor** | edges only | 8 palms on the terraces; 6 block trees at the plateau corners; `wood` post-and-rail fence (posts 1x3x1 every 6 studs, rails 0.4x0.5) along the plateau edge with gaps at stairs and the arch; flower clusters (5-9 cubes of 1x1x1 in Red/Yellow/Pink/White); 6 grey rocks; 3 beach umbrellas (pole plus 8x0.6x8 red/white top); dock 8x30 `wood` at (0,-86) on posts into the water. |

**Floating station labels** (ref1 style): a BillboardGui per station, Size 12x3 studs, StudsOffset +Y above the prop, LightInfluence 0, MaxDistance 160, AlwaysOnTop false. Text is FredokaOne with Ink stroke 3 plus a drop label (see 8.3). Colors: "Shop" Green, "Lucky Wheel" rainbow UIGradient, "Daily Chest" Yellow, "Group Chest" Cyan with a subtitle "Like + Join = FREE chest!" in White BuilderSans ExtraBold, "Top Wins" Gold, "Top Solo" Orange.

**Remove** from `Maps/Lobby.lua`: pastel tiles (124-149), candy beads (163-168), rainbow (261-295), candy-cane posts and Glass balloons (183-257), lollipops, mushrooms, gifts and puff trees (353-458), and the HOW TO PLAY board (331-349). Controls hints move to the UI.

---

## 7. MAP ART per minigame (palettes in 4.2)

### 7.1 Laser Tracer: "Laser Lab"
- **Floor**: voxel disc r 42, `lt_tile` (alternate strips use the alt tint), cliff `steel` down to the water, rim = 1.2-stud `hazard_trim` flush at the floor top. **No central hub** (brief #15): delete `buildHub` (`Arena.lua:171-209`); the center tile carries a 6x6 decal of the `game_laser_tracer` emblem.
- **Emitters**: white towers 3x10x3 (235,238,245) with a dark cap (40,42,62) and a red Neon lens (255,28,36), standing on an outer **rail ring** of steel blocks at r 48. They visually slide along the rail so lasers can come from anywhere (random movement, #15).
- **Lasers: both RED (255,28,36), with height readable at a glance (#13):**
  | | LOW (jump over) = "hurdle" | HIGH (slide under) = "limbo bar" |
  |---|---|---|
  | Beam | `Beam` instance, Color red, Width 0.75, LightEmission 0.6, LightInfluence 0, Brightness 2, FaceCamera true, no texture (solid) | the same red Beam at Width 0.55, **plus** an overlay Beam with `laser_dash` texture, Color White, Width 0.42, TextureMode Wrap, TextureLength 2.5, TextureSpeed 3: a red/white candy-cane bar |
  | End posts | short white posts 1.2x1.6x1.2 with a red Neon cap: the beam sits ON them | tall white poles 0.5x6.5x0.5 from the floor up past the beam, with a red Neon ring at beam height: a limbo frame you go under |
  | Curtain | Part (length x 1.6 x 0.05), Transparency 1, from the floor up to the beam. SurfaceGui on Front and Back, SizingMode FixedSize (256x64), LightInfluence 0, Brightness 1.5. Child Frame red with `UIGradient Rotation 90`, Transparency NumberSequence {(0,0.35),(1,0.85)} (solid at the beam, fading to the floor): **a red fence** | Part (length x 4 x 0.05) from the beam UP. Gradient Rotation 90, {(0,1),(1,0.4)} (fading upward): **a red curtain hanging above the bar** |
  | Floor line | one solid red line 0.6 wide, Transparency 0.35 | two thin rails 0.2 wide, 0.9 apart, Transparency 0.35 |
  | Telegraph tag | `arrow_jump` icon (green up-chevron) BillboardGui, replacing the "JUMP!" text | `arrow_slide` icon (orange down-chevron), replacing "SLIDE!" (`Lasers.lua:32`) |
  | Sound | hum, lower pitch (0.9) | hum, higher pitch (1.15) |
- Keep a faint Neon glow cylinder only if Bloom allows it: Transparency 0.8, 1.6x the beam width.

### 7.2 Dodgeball: "Sports Day"
- Voxel disc r 38 in `maple`. White lines 0.8 wide, 0.05 above the floor: center line, center circle r 7.4 in Blue with a white ring, 16 throw dashes at r 28.5. A 3-stud Blue out-band just inside the rim. The cliff band is a 3-stud blue stadium wall (28,86,190) with a 0.6 white stripe, then `stone` to the water.
- Remove the candy beads (`Map.lua:138-148`), the candy underside (`:151-155`), the floating big balls and the clouds (`:158-186`).
- Balls: red rubber (235,48,58) SmoothPlastic with a white seam and a Highlight (3.5). Golden ball: Gold Neon (keep the pad and sparkles). Cannons: navy (30,40,80) with white bands and a red muzzle ring; keep the googly eyes (they are charming and on-style).

### 7.3 Hole in the Wall: "Brick Run" (ref4)
- Floor 64x64 `turf_check`, a 1-stud `wood` border, `dirt_cliff` to the water. Delete the pastel stripes (`Arena.lua:59-65`) and the candy tiers (`:102-110`).
- Walls: 66x14x2 in `brick_wall_<color>`, rotating Red, Blue, Purple, Orange per spawn. The hole's inner faces get the wall color darkened by 0.4, which gives the hole a crisp outline. **No text at all**: remove `WallView.lua:24-26` labels and the `label()` calls at `:193-196` (brief #21).
- **Hole shapes = pixel-art bitmaps on a 1-stud grid** (blocky, on-style, never the same twice in a row). Rule: the bitmap must contain the clearance rectangle of its kind (`Patterns.HOLES`: NORMAL 7w x 8h from the floor; HIGH 7w x 6h starting 4.5 up; LOW 8w x 3h from the floor), and **the server hit test uses the same bitmap** (a union of row rects), never a looser bounding box. Examples (top row first, `#` = hole):
```
NORMAL "star-man" 11x10   LOW "mouse hole" 10x4   HIGH "porthole" 9x8 (bottom row at y=4.5)
....###....               ..######..              ...###...
....###....               .########.              .#######.
###########               ##########              .#######.
.#########.               ##########              #########
..#######..                                       #########
..#######..                                       .#######.
..#######..                                       .#######.
..#######..                                       ...###...
..#######..
..#######..
```
  More shapes to author under the same rule: heart, star, plus, keyhole, house, arch, T, zig-zag stairs, and "jumping-man" (arms up, sitting high) as the HIGH variant. That makes about 12 bitmaps, picked at random with no immediate repeats.
- Telegraph: a floor strip in the wall's color, Neon, Transparency 0.5, flashing 2 Hz for `Patterns.TELEGRAPH` seconds.

### 7.4 Spin: "Pillar Lagoon"
- Pillars rise straight out of the water: `stone` columns, square 9x9 tops preferred (if they stay round, use flat colors only; no textures on cylinders). Tops use the HSV ring colors with a 0.6 rim.
- **Delete `Foot`** (`Spin/Arena.lua:111-113`). It is the small ledge you can stand on (brief #22). Also make sure the column body radius or size is never wider than the top.
- Delete the lava basin, lava glow, rock island and candy rim (`buildLava`, `:158-238`). The pillars stand in the shared sea and get foam rings.
- Hub: `stone` tower with a Yellow cap. Bars: SmoothPlastic with the `awning` texture tinted red, giving red/white candy stripes along the bar (StudsPerTileU 4), yellow Neon tips, and a Highlight. **Visual thickness = hit thickness** (delete `Shell`, `:281`).
- Bat (brief #22): wood (176,112,60) with red grip tape (235,48,58), matching the `bat` icon.

### 7.5 Bomb Tag: "Toy Box" (new)
- Island 96x96 with 8x8 corner notches. Floor `foam_mat`; edge = a 2-stud band in dark purple (64,40,110), then `stone` to the water; red/white curb blocks 1 stud high on the rim.
- Obstacles: all `toy_block` in Red, Yellow, Blue and Green. Local positions, floor top at y=0:
  - Center stage 20x20x4 at (0,0) with 8-wide ramps on N and S, and an E-W tunnel through it 6w x 3.5h.
  - 4 corner towers 10x10x8 at (±32,±32), each a 2-block stack with a 5x5x4 step block.
  - A 4-wide bridge at height 8 between the NW and NE towers.
  - 4 juke walls 12x2.5x2 at (±20,0) and (0,±20).
  - 8 columns 3x6x3 at (±12,±30) and (±30,±12).
  - 4 jump pads 4x4 at (±22,±22) with a Lime Neon ring and an up-chevron decal, launching onto the towers.
  - One dynamic element (the Bomb Tag builder's choice): sliding tunnel doors or pop-up floor blocks.
- Bomb: Ball d 2.4 (30,30,38) SmoothPlastic, Reflectance 0.08; fuse cylinder 0.25x0.8 (200,170,120). Spark: ParticleEmitter Color (255,220,90) to (255,90,20), Rate 40 rising to 120 as the fuse runs out; PointLight orange Range 10.
- Holder: Highlight FillColor (255,40,40), FillTransparency pulsing 0.75 to 0.45 (1 Hz, 4 Hz in the last 3 s), OutlineColor (255,240,240). Countdown BillboardGui above the head: LuckiestGuy, White to Yellow at 5 or less to Red at 3 or less, Ink stroke 4, scale punch every second.
- Explosion: Neon sphere White to Orange, 0 to 14 studs in 0.25 s, then fade. 6 dark smoke cubes (60,60,70) tween up and fade. `boom_burst` icon billboard pops for 0.4 s. Camera shake within 30 studs.

---

## 8. UI STYLE GUIDE

### 8.1 Fonts (max 2 per screen)
| Role | Font | Use |
|---|---|---|
| Display / buttons / titles / numbers | **FredokaOne** (`Theme.FontFace`) | button labels in **Title Case** ("Shop", "Daily", "Spin"), panel titles, prices, currency |
| Hype words and countdowns | **LuckiestGuy** (`Theme.FontHype`) | "3-2-1", "BOOM!", "YOU WIN!", "ELIMINATED", the bomb timer, "-90%" stickers |
| Small text | **BuilderSans Bold / ExtraBold** (`Theme.FontBody`/`FontBodyHeavy`) | descriptions, odds %, settings rows, tips, timers under 20 px |
| Banned | Bangers, Arcade, SciFi, Cartoon, GothamBlack, emoji | n/a |

**Type scale** (design px at 1080 tall): Hero 120 (LuckiestGuy) · Display 72 · H1 56 · H2 40 · Button 30 · HUD value 34 · Body 22 · Caption 18. **Device minimum 12 px.**
Scaling: `UIScale = clamp(viewportY/1080, 0.55, 1.3)`, then min'd so the panel fits within the screen minus 2x margin. A linear 0.36 on phones makes body text unreadable, hence the 0.55 floor.

### 8.2 Text stroke (UIStroke Contextual, Color Ink (22,18,36), LineJoinMode Round)
Thickness = clamp(textPixelHeight × 0.085, 1.5, 6). Steps: ≥72 px gives 6, 48-71 gives 5, 32-47 gives 4, 24-31 gives 3, 18-23 gives 2, under 18 gives 1.5.
For TextScaled labels, compute it from `TextBounds.Y` on `AbsoluteSize` change (new `Kit.autoStroke(label)`). The viewport-based `Kit.setViewport` scaling is not enough.
**Headline drop**: a duplicate label behind, TextColor Ink, offset +0.06 × height in Y, same stroke. This is the chunky extruded look of ref5's "FEATURED".
Gold title gradient (titles only): UIGradient (255,240,120) to (255,170,20), Rotation 90.

### 8.3 Button anatomy (new `Kit.button(opts)`; every button uses it)
```
Btn (ImageButton, BackgroundTransparency 1, AutoButtonColor false)
 ├─ Lip     Frame  same size, Position +lip (lip = 0.08 x height), color = <Color>Dark, UICorner r, UIStroke Ink 3.5 Border
 ├─ Face    Frame  BackgroundColor White + UIGradient {0: lighten(c,0.15), 0.5: c, 1: darken(c,0.12)} Rot 90, UICorner r, UIStroke Ink 3.5 Border
 │   ├─ Rim    Frame inset 3 px, transparent, UIStroke lighten(c,0.45) 2 px, Transparency 0.2   (inner light border, ref4)
 │   ├─ Gloss  Frame top 45%, White, UIGradient Transparency {(0,0.55),(1,1)} Rot 90, UICorner r-2
 │   ├─ Icon   ImageLabel (Assets.icon(name)), ScaleType Fit, may overflow the face by 10-15% (ref1)
 │   └─ Label  FredokaOne White, auto stroke, Title Case
 └─ Badge   optional red circle 0.32 x size, top-right, Rotation -8°, "!" LuckiestGuy, pulse 1.0 to 1.12 sine 0.6 s
```
- Corner radius: square tiles `UDim.new(0.14,0)`; wide buttons `UDim.new(0.22,0)`; pills `UDim.new(0.5,0)`.
- **Hover** (mouse only): UIScale 1.04 over 0.10 s Quad Out; Gloss transparency 0.55 to 0.40.
- **Press**: Face moves down by `lip` and UIScale goes to 0.96 over 0.06 s Quad Out; the "click" sound plays on every button (#25), pitch 1 ± 0.05.
- **Release**: back over 0.14 s, Back Out.
- **Disabled**: gradient (150,150,165) to (110,110,125), icon ImageColor3 (170,170,180), label TextTransparency 0.35; plays the "deny" sound and shakes 3 × 4 px over 0.18 s.
- **Offer shine**: a white band (UIGradient Transparency, 15% opaque at 0.6) sweeps Offset X -1 to 1 over 0.6 s every 3.5 s, Rotation 20.
- Semantic face colors: **Green** buy/claim/confirm · **Red** close/danger · **Yellow/Gold** reward/daily · **Blue** secondary/info · **Purple to Pink** premium/limited.

### 8.4 Panel anatomy (ref3 / ref5)
- **Dim**: Ink at BackgroundTransparency 0.45, fading in over 0.15 s. Open: UIScale 0.85 to 1 (Back Out, 0.25 s) plus Y +20 px to 0.
- **Body**: UIGradient Panel (38,34,56) to PanelDeep (26,23,40), corner 18, UIStroke Ink 4. **Pattern overlay**: ImageLabel `studs` texture, ScaleType Tile, TileSize 40x40, ImageTransparency 0.93, clipped. This gives the subtle stud texture of ref5.
- **Header bar**: 96 design-px tall, full width, colored by panel: Shop Green, Wheel Purple, Daily Yellow to Orange, Settings Blue, Offers Pink. It carries the `stripes_diag` overlay at ImageTransparency 0.85, a top-40% gloss, a FredokaOne 56 title (left-aligned, white, stroke 5 plus drop), and a 110 px icon overlapping the left edge, rotated -6°.
- **Close**: 72x72 square, Red to RedDark, corner 12, stroke Ink 4, inner light rim, "X" in LuckiestGuy 52 white with stroke 3. It sits at the header's right and overlaps the panel's top-right border by 50% (ref3/ref5).
- **Section title**: "-- FEATURED --" style, FredokaOne 40 Yellow, stroke 4 plus drop.
- **Card**: PanelLight (56,50,82), corner 12, stroke Ink 3, a 2 px top highlight (White at 0.85).
- **Robux price button**: Green face, text `utf8.char(0xE002) .. " 19"` in FredokaOne 34. The Robux glyph U+E002 must be verified in Studio; the fallback is the built-in `rbxasset://textures/ui/common/robux.png`. **Never generate a Robux logo.**
- **Strikethrough old price** (#31: 199 to 19): above the button, Red (255,80,80), FredokaOne at 70% size, with a 3 px red Frame line at Rotation -10° across it. Add a "-90%" sticker (Red, Rotation -12°, LuckiestGuy) and a "LIMITED" ribbon (UIGradient Purple to Pink) with a live countdown "23h 14m 09s" in BuilderSans ExtraBold.
- **Side tabs** (ref5): icon 96 px plus a FredokaOne 24 label under it, no background. The selected tab gets icon scale 1.12 and `glow_soft` behind it (ImageColor3 = header color, 0.3).
- **Timer pill** (ref1 "00:46"): PanelDeep at 0.15 transparency, corner 0.5, stroke Ink 3, a `gift` icon at each end, time in FredokaOne white stroke 3.
- **Never show an empty container.** Use placeholder rows ("—") or hide it (the KotH TOP 3 box is the current example).

### 8.5 HUD zones (follow ref1; sizes use SizeConstraint RelativeYY, H = screen height)
| Zone | Content | Size |
|---|---|---|
| Top-left 0.22W x 0.12H | **reserved for Roblox core buttons**; nothing here | n/a |
| Left-middle | timer pill (free gift), then a 2-column grid of square tiles: Shop, Wheel, Daily, Settings (+ Solo) | tile 0.115H (min 56, max 104 px), gap 0.012H |
| Bottom-left | currency stack: coin icon plus amount, level badge plus XP bar, trophy plus wins | row 0.065H, icons 0.075H overflowing |
| Top-center | lobby: "Next round 0:14" pill plus a hint "Step on the PLAY pad!"; round: game name pill, timer, alive count | pill 0.07H |
| Top-right | offers column: Starter Pack, Limited Trail (-90%), VIP; each with a timer | 0.09H |
| Right-middle | playtime rewards and streak | 0.09H |
| Bottom-right | mobile actions around the jump button: Dash 0.15H, Slide 0.12H, Swing 0.12H; dark circles (Ink at 0.35) with a white icon and Ink stroke 3, like ref1's jump button | n/a |
| Center 50% x 50% | **nothing persistent during rounds**, only transient callouts | n/a |
- Cooldowns: Dash shows a bottom-up fill (Ink at 0.45) inside its button. **Slide shows no bar** (#11): its icon just drops to 50% transparency while it cools down. Delete the bottom "SHIFT / DASH / C SLIDE" strip (`client/Movement/Hud.lua` DashCooldownBar plus key chips).
- Numbers: separators ("12,450"), abbreviate at 100K or more ("125K", "1.2M"), count up over 0.6 s Quad Out when they change, with a +amount fly-in.

### 8.6 Motion tokens
tap 0.06/0.14 · popIn 0.25 Back Out · panel 0.25 · toast 0.35 · count-up 0.6 · shine every 3.5 s · idle icon bob ±2 px sine 1.6 s · badge pulse 0.6 s · reward confetti on every claim.

### 8.7 DO / DON'T (how it stops looking like AI slop)
**DO**
1. Put a real illustrated icon (9.x) on every tile, card and offer. Keep labels short and in Title Case.
2. Build buttons as chunky square tiles with a 3D lip, gloss and a thick ink outline, and let the icon overflow the tile.
3. Use neutral dark panels with **colored header bars**. Color lives in headers, buttons and icons.
4. Show live numbers everywhere: timers, prices, struck-through old prices, odds %, x2 multipliers, "+25".
5. Add juice: press squash, Back-easing pop-ins, shine sweeps, count-ups, pulsing "!" badges, confetti on rewards.
6. Give every screen one hero element and a clear size hierarchy from the type scale.
7. Keep one light direction (top-left) across icons, gloss and bevels.
8. Use color semantically (8.3).

**DON'T** (all of these are in the current build)
1. Emoji as icons (`UI/Data.lua:26-47`, `Economy/Cosmetics.lua:83-85`).
2. Rainbow per-letter text (`UI/Lobby.lua:17` LETTER_COLORS); use the logo image instead.
3. Purple-on-purple everything (`Theme.Colors.Panel` (45,38,80), purple pill gradient `UI/Hud.lua:146`).
4. Icons drawn from Frames (`Kit.coin`, `UI/Kit.lua:140-194`; the coin glyph on `Shop/MenuButton.lua:39-53`).
5. Long ALL-CAPS instruction sentences during play ("CLIMB TO THE GOLDEN ZONE!"); use 1-3 words plus an icon.
6. Empty boxes; debug-looking key strips.
7. The same 14 px radius and the same 3 px stroke on everything, with everything center-aligned.
8. Pastels, Glass, translucent "glass" panels, thin strokes (< 2 px), gradient text on body copy, sparkle confetti with no reason behind it.
9. Text on gameplay objects (wall labels, "JUMP!/SLIDE!" tags); use shapes and icons.

### 8.8 Loading screen (#24)
- Full-screen ImageLabel `loading_bg` (ScaleType Crop). `logo` sits top-center at 46% width with an idle bob.
- Bottom 12%: a progress pill 60% wide, PanelDeep with Ink stroke 4. Fill is a Yellow to Orange gradient with a moving `stripes_diag` overlay. The status line above it reads "Loading assets... 63%" in BuilderSans ExtraBold 22, then "Loading maps...", "Loading sounds...". A rotating tip appears above that ("Tip: Slide under the striped laser!").
- A "Skip" button (secondary Blue, small) bottom-right, appearing after 1.5 s. The fake duration is 4-6 s.
- It must run from **ReplicatedFirst** (`ReplicatedFirst:RemoveDefaultLoadingScreen()`). That needs a `ReplicatedFirst` mapping in `default.project.json` (lead/tools).

### 8.9 Wheel of fortune UI
- Do not ask ChatGPT for the wheel face; segment counts and angles must be exact. Instead, `tools/gen_wheel.py` (PIL) draws `wheel_face.png` at 1024 px: 8 wedges in Red, Yellow, Blue, Green, Purple, Orange, Cyan, Pink (Theme), white 6 px separators and an Ink 10 px outer outline.
- Prize icons are separate ImageLabels at 0.62 radius, rotated per segment. The rim and bulbs are Frames.
- A red pointer sits at the top. The "Spin" button is Green and reads glyph plus "9"; under it, "Free spin in 23:10:04" in BuilderSans.
- The same PNG goes on the 3D lobby wheel.

---

## 9. ICONS and ART: ChatGPT image generation

### 9.1 Already made (`assets/raw`, sliced to `assets/icons/*.png`)
- **Sheet A, menu (uploaded, in `Assets.Icons`):** shop, chest_daily, chest_group, wheel, gift, settings, trophy, stopwatch, crown.
- **Sheet B, currency (sliced, not uploaded yet; add to `manifest.json`):** coin, coin_stack, coin_sack, coin_chest, xp_star, lightning, revive_heart, spectate_eye, home.
- **Sheet C, items (sliced, not uploaded yet):** bomb, bat, trail_rainbow, speed_shoe, spring, hourglass, party_popper, music, speaker.
These three sheets define the house style: glossy 3D cartoon, thick dark navy outline, top-left light, saturated colors. Every new sheet must match them.

### 9.2 STYLE LOCK (paste verbatim at the start of every sheet prompt)
> Create a 1024x1024 sprite sheet: nine separate game UI icons arranged in a 3x3 grid, for a bright modern Roblox party game. All nine share one identical art style: glossy 3D cartoon render like premium mobile-game icons, chunky rounded toy-like proportions, bold saturated colors (vivid red #EB303A, sunny yellow #FFD326, lime green #3ED048, royal blue #247AF6, purple #8A48F0, gold #FFC41E), smooth glossy plastic/candy material with a bright specular highlight on the upper-left and soft darker shading on the lower-right (light from the top-left), and a thick, clean, dark navy outline (#16122A, about 3% of the icon width) around each icon's outer silhouette. Camera: slight three-quarter view from above, same angle and same scale for every icon. Each icon sits centered in its own cell of an invisible 3x3 grid, fills about 70% of the cell, with clear empty space around it; icons never touch each other or the cell edges. Fully transparent background (real alpha channel), no background shapes or cards, no ground shadows, no text, no letters, no numbers, no watermark, no grid lines.

Then append "Row 1 (left to right): ... Row 2: ... Row 3: ..." with the item lines below.
Slice with: `python3 tools/slice_sheet.py <sheet.png> 3 3 <names> 256`. Use size 512 for Sheet E and Sheet H, because they appear large on cards.

### 9.3 Sheet D: social, streak and status
Names: `fire_streak,calendar_star,thumbs_up,group_friends,lock,check_badge,sale_tag,alarm_clock,spin_ticket`
> Row 1: (1) a big cartoon flame with an orange-yellow core and red outer tongues; (2) a red-and-white tear-off desk calendar with two metal rings on top and a big gold star on the page instead of a date; (3) a cartoon thumbs-up hand in sunny yellow with a small blue cuff. Row 2: (4) three blocky cube-headed cartoon toy heads side by side with simple happy faces and red, blue and green collars, the middle one slightly in front (generic toy figures, no logos); (5) a chunky golden padlock with a dark keyhole, closed; (6) a round lime-green badge with a bold white check mark and a lighter rim. Row 3: (7) a red price tag with a round hole and a string, with a white percent symbol on it (the percent symbol is allowed on this icon only); (8) a red twin-bell alarm clock with a white face, gold bells and small shake lines; (9) a golden ticket with notched edges and a purple star in the center.

Used for: streak bar, daily calendar, like-the-game prompt, join-group prompt, locked items, claimed state, Featured/Sale tab (ref5), limited timers, wheel tickets.

### 9.4 Sheet E: minigame emblems (roulette cards, intro cards, Solo picker, game-mode badges)
Names: `game_laser_tracer,game_dodgeball,game_hole_in_wall,game_spin,game_bomb_tag,game_random,skull_out,podium,medal_gold`
> Row 1: (1) two glowing red laser beams crossing in an X over a small square dark-indigo tiled platform, one beam low near the floor and one higher with white candy stripes, short white posts at the beam ends; (2) a shiny red rubber dodgeball with a white stripe flying to the right with white motion lines, a small navy-blue cartoon cannon behind it; (3) a thick red brick wall chunk standing on a small green grass block, with a simple person-shaped hole cut through it (standing figure with arms out) and light shining through. Row 2: (4) a round grey stone pillar top seen at an angle with a red-and-white candy-striped bar sweeping over it and curved white motion arcs; (5) a round glossy black cartoon bomb with angry eyebrows and eyes, a short rope fuse with a bright yellow-orange spark and little flying sparks; (6) a glossy purple mystery cube with gold edges and a big white question mark on its front (the question mark symbol is allowed on this icon only). Row 3: (7) a cute round white cartoon skull, friendly not scary, with dark eye holes, slightly tilted; (8) a three-step winners podium, gold center block tallest with a star, silver left, bronze right; (9) a gold medal with a star in the middle hanging from a red-and-blue ribbon.

They replace `UI/Data.lua` MINIGAME_ICONS. A card = accent gradient (4.1) + the map's floor texture as a tiled ImageLabel (0.85 transparency) + the emblem at 70% width + the name in FredokaOne.

### 9.5 Sheet F: modifiers and boosts
Names: `mod_low_gravity,mod_turbo,mod_fog,mod_giant,mod_tiny,mod_slippery,boost_2x_coins,vip_badge,boost_xp`
> Row 1: (1) a yellow crescent moon with a small floating white feather and two tiny stars; (2) a red cartoon rocket with a round white window flying up-right with an orange-yellow flame; (3) a chunky blue-grey cartoon cloud with a darker swirl and a few small mist puffs. Row 2: (4) a round green potion bottle with a cork, bubbles and a big white upward arrow on its label; (5) a small pink potion bottle with a cork, bubbles and a white downward arrow on its label; (6) a light-blue glossy ice cube with frost on its corners and a tiny shine sparkle. Row 3: (7) two overlapping shiny gold coins with a bright sparkle burst behind them; (8) a purple shield badge with a gold rim, a small gem in its center and a gold crown on top; (9) a glossy blue five-point star with a green upward arrow behind it.

They replace `UI/Data.lua` MODIFIER_ICONS (LowGravity, Turbo, Fog, Giant, Tiny, Slippery). The other three cover the 2x Coins pass, the VIP pass and XP boosts.

### 9.6 Sheet G: trails and win effects (cosmetics shop previews, Limited trail #31)
Names: `trail_fire,trail_ice,trail_hearts,trail_lightning,trail_galaxy,trail_bubbles,win_fireworks,win_crown_rain,win_star_sparkles`
> Row 1: (1) a curved swoosh trail made of orange and red cartoon flames streaming left to right with a glowing tip; (2) a curved swoosh trail made of light-blue ice crystals and small snowflakes; (3) a curved swoosh trail of glossy pink and red hearts getting smaller toward the end. Row 2: (4) a bright yellow zig-zag lightning trail with small electric sparks; (5) a premium curved swoosh trail of deep purple and magenta cosmic space full of tiny white stars, with a pink glow and a gold sparkle at its tip; (6) a curved trail of glossy cyan soap bubbles of different sizes. Row 3: (7) a burst of red, yellow and blue cartoon fireworks exploding out of a small striped rocket tube; (8) a gold crown with small gold coins and stars falling around it; (9) a big yellow four-point sparkle star surrounded by smaller sparkles.

These replace the WinEffect emojis in `Economy/Cosmetics.lua:83-85`. `trail_galaxy` is the **LIMITED** trail at 19 Robux, shown as down from 199.

### 9.7 Sheet H: rewards, offers and feedback
Names: `starter_pack,coin_mountain,mega_chest,boom_burst,hit_star,splash,arrow_jump,arrow_slide,target_lock`
> Row 1: (1) an open red gift box overflowing with gold coins, a blue star and a small gold crown peeking out; (2) a huge mountain of shiny gold coins with a few coins tumbling down its sides; (3) a large purple-and-gold legendary treasure chest, lid slightly open, bright magenta glow and sparkles spilling out. Row 2: (4) a jagged comic explosion burst, yellow center, orange then red outer spikes, with small grey smoke puffs; (5) a white-and-yellow cartoon impact star burst with short speed lines, like a bonk hit effect; (6) a cartoon water splash in turquoise and white with flying droplets. Row 3: (7) a thick lime-green upward chevron arrow with a white highlight; (8) a thick orange downward chevron arrow with a white highlight; (9) a red-and-white bullseye target with a small dart in its center.

Used for: Starter Pack (#30), the biggest coin pack, the wheel jackpot and premium chest, the Bomb Tag explosion, hit feedback (#25), elimination splash, laser telegraphs (7.1), Dodgeball lock-on.

### 9.8 LOGO (1536x1024, transparent)
> Create a 1536x1024 game logo with a fully transparent background for a Roblox party game called PARTY DASH. Two lines: the word PARTY on top and the word DASH below it, about 30% larger, both slanted forward about 8 degrees as if running fast. Chunky, rounded, bubbly 3D cartoon letters. PARTY is a glossy sunny-yellow to orange vertical gradient (#FFD326 to #FF8A1C); DASH is a glossy sky-blue to royal-blue vertical gradient (#1CC4F5 to #247AF6). Every letter has a thick dark navy outline (#16122A), a darker 3D extruded side going down-right, and a bright white gloss highlight on its upper-left. Three short white speed lines trail behind the left side of DASH, a few small confetti pieces and one tiny gold sparkle star around the words. The letters are spelled exactly P-A-R-T-Y and D-A-S-H, perfectly legible, centered, filling about 80% of the width. No other text, no watermark.

Used for: loading screen, lobby spawn decal, Results header, the PLAY arch board (alternative). Regenerate until the spelling is perfect.

### 9.9 LOADING SCREEN BACKGROUND (1536x1024, opaque)
> Create a 1536x1024 bright, saturated key-art background for a Roblox party game loading screen, in a blocky voxel cartoon style. A sunny tropical sea of vivid turquoise water (#18A8EC) covered with a light cartoon wave-cell line pattern; a few blocky islands with lime-green grass tops (#64D22D) and brown brick-textured dirt cliffs; blocky palm trees; puffy white clouds in a clear blue sky. In the middle distance, a round game arena island where two glowing red lasers sweep across a dark indigo tile floor, a black cartoon bomb with a lit fuse bounces, and a red-and-white striped bar spins over stone pillars. Three small blocky toy-like cartoon characters (generic, no logos, not real game avatars) run and jump in the right foreground. Keep the upper-center calm with mostly empty sky so a logo can sit there, and keep the bottom 20% simple (water) for a progress bar. Crisp, clean, high contrast, no haze, no text, no letters, no UI, no watermark.

### 9.10 Optional (store page; strongly affects click-through for kids)
- **Game icon (1024x1024, opaque)**: "same style as the loading art: a black cartoon bomb with a lit fuse in the foreground, a blocky toy character dashing past with speed lines, a red laser behind, bright blue sky, bold and readable at 50 px, no text."
- **Thumbnail (1536x1024)**: the loading-art prompt, plus "close-up action moment, the bomb exploding into a yellow-orange comic burst while two characters dive away."

### 9.11 Generation QA (reject and regenerate, max 3 tries, then use ChatGPT "edit" on the single bad cell)
Reject the result if any of these hold:
- any text or letters appear (except the logo and the allowed symbols);
- the outline is missing, thin or a different color;
- one icon is flat or 2D while the others are 3D;
- icons touch each other or cross a cell;
- the perspective differs between icons;
- colors are muddy or off-palette;
- the background is not truly transparent (a fake checkerboard).
Pipeline: browser capture over black and over white, then `tools/matte.py`, then `slice_sheet.py`, then the Studio MCP `upload_image` via `devserver /asset/...`, then `assets/manifest.json`, then `tools/gen_assets_lua.py`. Art (logo, loading_bg, game cards) goes under the `art` key, so it lands in `Assets.Art`.

---

## 10. Acceptance checklist (critics, via screen_capture)
1. Lobby spawn view: grass top pixel within R 80-130, G 180-235, B 25-80; water shows white wave lines; the horizon is blue; the arena island is visible behind the PLAY arch.
2. Every map: the floor edge reads as a dark or contrasting band down to the water (rule 4.3.2); no white or pastel floor; Neon at 5% of the frame or less.
3. Falling off any arena: a visible splash, then elimination. Nobody swims and nobody ends up standing on a ledge (the Spin `Foot` is gone).
4. Laser Tracer: a still frame with one low and one high laser lets you name which is which without text (fence vs limbo poles, solid vs candy stripes). Both are red.
5. HitW: no letters on walls; at least 5 different hole shapes in 60 s; the hole outline is visible.
6. UI: no emoji anywhere; every menu tile has an `Assets.Icons` image; buttons have a lip and press animation and play a click sound; panels have a colored header and a red X; there is no empty box; the slide has no cooldown bar.
7. Every map is distinct: from a single screenshot a reviewer can tell Lobby / LT / DB / HitW / Spin / BombTag apart by floor color alone.
