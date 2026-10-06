# Audit: ui

**subsystem**: Client UI (HUD, roulette, intro, results, notify, tutorial, scoreboard) + Solo UI + Spectate + Movement HUD

**howItWorks**: BOOT: src/client/UI/init.client.lua waits for game.Loaded and Shared/{Config,GameState,Net,Theme}, then builds 3 ScreenGuis with screenGui(), destroying any old copy first. PartyHUD has DisplayOrder 5 and IgnoreGuiInset=false. PartyOverlay has DisplayOrder 10, IgnoreGuiInset=true and ScreenInsets=None. PartyNotify has DisplayOrder 20 and is safe-area aware. All three set ResetOnSpawn=false and ZIndexBehavior=Sibling. Kit.setViewport(overlay.AbsoluteSize) rescales every UIStroke made by Kit.stroke (the base thickness is defined for a 900px-tall screen, clamped 0.5-1.4). Each module starts inside pcall via run().

Kit.lua is a private builder kit: new/corner/stroke/gradient/aspect/sizeLimit/label/box/panel/coin/scaler/tween/popIn/popOut/punch/lighten/darken. It lives under the UI LocalScript, so no other system can require it. Each other system therefore carries its own copy: Solo/Ui.lua, Shop/Ui.lua and Minigames/KingOfTheHill/Ui.lua, plus inline builders in Movement/Hud.lua:43-79, Spectate/init.client.lua:50-119 and Dodgeball/Throw.lua.

Data.lua reads ReplicatedStorage.MinigameInfo.<Id>: DisplayName, Rules, Keys CSV and Kind. It also reads Icon/Color, but Core Registry.lua:85-93 never publishes those two. It reads ModifierInfo the same way. Icons are emoji tables: MINIGAME_ICONS (⚡🏐👑🚧🌀) and MODIFIER_ICONS. The color fallback is Theme.MinigameColors, then hashColor. Data also provides keyHint() (PC key vs touch button), playerName() with an async cache plus the NameResolved event, rankScores(), formatTime() and headshot() (rbxthumb).

Hud.lua builds two things.
- PartyHUD.MenuRail: a vertical Frame with UIListLayout at left-middle. Width is 0.11 of the screen height (SizeConstraint RelativeYY, clamped 60-112px). It gets a translucent Panel backing once a child docks, and slides off-screen during Roulette/ModifierRoulette.
- PartyHUD.TopBar: StatusPill (text from statusFor(phase)), TimerBadge (recomputed from PhaseEnd every Heartbeat, tick sfx at 5s or less in Round), AliveBadge ('%d / %d ALIVE', survival only, in Countdown/Round) and ModifierTag ('✨ NAME · 2x COINS'). TopBar hides in Lobby/Waiting and hides instantly in overlay phases.

Lobby.lua builds PartyHUD.LobbyLogo: 9 per-letter TextLabels, each with its own gradient, bobbing on RenderStepped, plus a NextGamePill showing 'NEXT GAME IN n' or 'WAITING FOR PLAYERS...'.

Scoreboard.lua builds PartyHUD.Top3 at the right (y 0.34). It shows only when Phase==Round and MinigameKind=='score'. Rows are reused and fed from GameState.ScoresJson. A 'YOU #n' row appears under the panel when you are outside the top 3.

Tutorial.lua builds PartyHUD.Tutorial, a speech bubble at bottom-center with its bottom at y 0.86. It runs 3 steps: Dash, Slide, Jump. A step completes on UIS keys, on the character attributes Dashing/Sliding, or on the Humanoid Jumping state. When done it fires remote UI_TutorialDone. src/server/UI/init.server.lua then sets Player.Seen_Tutorial (rate limit 2s), and Economy persists it (Sessions.lua:358-365). The tutorial starts after a blind task.delay(1.5).

Roulette.lua runs two View objects: PartyOverlay.Roulette and PartyOverlay.ModifierRoulette. Each View has a near-opaque navy gradient dim, 8 rotating rays and a title. The card reel comes from the RouletteReel/ModifierReel CSV, repeated to at least 12 cards. Each card is a Frame with an emoji bubble. Reel position = easeOutReel(u) between the client's first-sync time and (PhaseEnd - hold). On land it sets the Selected/SelectedId attributes, punches the title, pops the HOW TO PLAY info panel and fires confetti. Syncs are coalesced with task.defer.

Intro.lua builds PartyOverlay.Intro, a white card with: an accent header, an emoji bubble, the title, the rules, key chips (Data.keyHint), RoundTag, GoalTag and ModifierTag. It vanishes whenever Notify.bigShown fires.

Results.lua builds PartyOverlay.Results for Phase End: a ribbon with ResultText and a podium. Score rounds use a 2-1-3 podium from ScoresJson; survival rounds show up to 3 winners from WinnersCsv. It adds avatar headshots, a 👑 for #1, '😵 NO WINNERS THIS TIME!' when there are no winners, a footer and a 'LOBBY IN n' chip, plus confetti. It calls notify.setBigLane(true).

Notify.lua retries Net.event('Core_Announce') until the remote exists.
- big: text laid out at a fixed 100px and fitted with a UIScale, slam/tilt animation, shockwave ring for 3 characters or fewer.
- feed: top-right, at most 5 lines, 6s each.
- toast: bottom-center at y 0.97, at most 2, 3.2s each, fixed width 0.31 of the screen.

Confetti.lua runs a pool of 140 Frames on RenderStepped. Sfx.lua holds 5 rbxasset:// templates in SoundService.PartyUISfx, played with PlayLocalSound. There is no SoundGroup and no click sound.

Solo client (src/client/Solo) has its own ScreenGuis: SoloHud (DisplayOrder 12) and SoloOverlay (DisplayOrder 15).
- RailButton.mount polls every 0.5s for PartyHUD.MenuRail and docks the 'SOLO' button there (LayoutOrder 20). After 20s without a rail it uses a fallback dock.
- Picker: a modal with one card per SoloCapable minigame plus RANDOM. Each card shows your best (Player attribute SoloBest_<id>) and the world #1 (JSON attributes on ReplicatedStorage.SoloTop).
- Remotes: Solo_Start, Solo_Quit, Solo_State (intro/go/result/rejected).
- RunHud: timer from the server's startedAt, a progress bar toward your best, and a double-tap QUIT button at left-middle.
- Result: count-up, NEW RECORD rays and confetti, PLAY AGAIN/CLOSE, auto-close after 12s.
- While Player.InSolo is true, it sets PartyHUD and PartyOverlay Enabled=false.
- Solo keeps its own copies of Ui, Sfx (its 'click' is action_jump.mp3) and Confetti (a near-identical copy).

Spectate/init.client.lua builds SpectateGui (DisplayOrder 5) from raw Instance.new, with no kit and no sounds. Its bottom bar shows while Player.Spectating is true. It cycles through InRound players with < > buttons or Q/E, and STOP/WATCH toggles workspace.CurrentCamera.CameraSubject.

Movement/Hud.lua builds MovementHUD (DisplayOrder 3, IgnoreGuiInset=true).
- DashCooldownBar at bottom-center (offset 1,-92), always visible in every phase and on touch devices, with 'SHIFT' and 'C SLIDE' chips (the chips hide on touch-only devices).
- The ContextActionService mobile Dash/Slide buttons are re-skinned as flat colored circles with text and a shade-fill cooldown, and placed above the jump button.
- Speed lines.

Other systems dock buttons as follows. Shop/MenuButton.lua:100-145 watches PlayerGui.ChildAdded and PartyHUD.ChildAdded for MenuRail and builds ShopButton (LayoutOrder 10) with Shop/Ui.lua. Solo polls as described above. KotH Hud.lua:274-290 reads PartyHUD.Tutorial to lift its pill. Other ScreenGuis in the game: EconomyHUD (14, top-right in the topbar row), EconomyShop (12), KingOfTheHillHUD (4), DodgeballHUD (5).

There is no background music, no SoundGroups, no settings and no loading screen anywhere in the repo. No ImageLabel uses an uploaded image: every icon is either an emoji or drawn from Frames. Generated PNG icons already exist locally (assets/icons/*.png from assets/raw/sheetA_menu.png via tools/slice_sheet.py) but are not uploaded yet.


## bugs


---

**title**: TOP 3 scoreboard is an empty dark box for most of a score round

**severity**: major

**file**: src/client/UI/Scoreboard.lua

**line**: 161

**rootCause**: render() only paints the entries present in GameState.ScoresJson, and paintRow (lines 133-138) hides a row when it has no entry. Core writes ScoresJson='{}' at round start (src/server/Core/RoundLoop.lua:314). Context:_pushScores only publishes when _scoresDirty is set (Context.lua:369-379), and that only happens after the first ctx.addScore or at stop() (Context.lua:530). Until somebody scores, the panel shows only the 'TOP 3' header.

**fix**: Fix both sides. (1) Core: right after Context.new in RoundLoop.playRound, call writeScores(table.clone(ctx._scores)) so every participant appears with 0 points. (2) Scoreboard.render: when ranked has fewer than 3 entries, fill the rows from Players whose InRound==true with score 0, or show a 'No points yet!' placeholder row. Never show an empty panel.

**evidence**: docs/reference/current-game-koth.jpg shows the empty 'TOP 3' panel on the right with 51 seconds left.


---

**title**: Click sounds are missing or inconsistent, and no SFX/music can be muted (no SoundGroups)

**severity**: major

**file**: src/client/UI/Sfx.lua

**line**: 15

**rootCause**: There are three separate Sfx modules (UI/Sfx.lua, Solo/Sfx.lua, Shop/Sfx.lua). Each puts its Sound templates in its own SoundService folder (PartyUISfx/SoloSfx/EconomySfx) with no SoundGroup and plays them via PlayLocalSound. The 'click' differs per module: Solo/Sfx.lua:8 uses rbxasset://sounds/action_jump.mp3 pitched 1.7, which sounds like a jump, and Shop/Sfx.lua:11 uses volume_slider.ogg. UI/Sfx.lua has no click at all. These buttons play no sound: Spectate Prev/Next/Stop (Spectate/init.client.lua:259-273), the SOLO rail button (Solo/RailButton.lua:142), Shop tab buttons (Shop/Window.lua:283-286) and the KotH input button (KingOfTheHill/Input.lua:211). Fourteen files create Sound instances, server-side ones included (Economy/Visuals.lua, KingOfTheHill/BatTool.lua), and none is grouped.

**fix**: Create UIKit/Audio.lua (see contractChanges). It owns the SoundGroups SoundService.PD_Music and PD_Sfx, keeps one sound catalog, and provides Audio.play(name). Audio.autoGroup() hooks SoundService.DescendantAdded and workspace.DescendantAdded: any Sound that has no SoundGroup and no 'PD_Music' attribute gets SoundGroup=PD_Sfx, set client-locally. Audio.autoClick(playerGui) connects a click to every GuiButton that is not under TouchGui/ContextActionGui and not marked NoClick or PD_Kit. Then delete UI/Sfx, Solo/Sfx and Shop/Sfx, or turn them into thin wrappers around Audio.


---

**title**: Bottom-center HUD elements overlap (Tutorial vs dash bar on phones, toasts vs dash bar and spectate bar)

**severity**: major

**file**: src/client/UI/Tutorial.lua

**line**: 68

**rootCause**: Several ScreenGuis place things at bottom-center in different coordinate spaces, and none of them reserves space. PartyHUD (IgnoreGuiInset=false): Tutorial bubble with bottom at y 0.86, height 0.2. MovementHUD (IgnoreGuiInset=true): DashCooldownBar at UDim2.new(0.5,0,1,-92), 26px tall (Movement/Hud.lua:91-93). PartyNotify: toasts with bottom at 0.97, up to 2 stacked, 26-54px each (Notify.lua:361-403). SpectateGui: bar at (0.5,0,1,-16), min 320x50, max 640x100 (Spectate/init.client.lua:23-48). DodgeballHUD at 1,-132. KotH pill at BASE_LIFT. Only KotH avoids anything, and only the Tutorial. At 800x360 with a ~36px inset, the Tutorial spans y≈250-315 and the dash bar 242-268. At 1080p, two stacked toasts span ≈941-1049 against the dash bar at 962-988 and the spectate bar at 964-1064.

**fix**: Add UIKit/Lanes.lua with fixed reserved bands in one coordinate space: every HUD ScreenGui uses IgnoreGuiInset=true and ScreenInsets=DeviceSafeInsets. Bands: ActionLane = bottom 1,-(jumpRowHeight+16) for minigame hints and the Tutorial; StatusLane = top-center under the topbar; ToastLane = top-center under the StatusLane (move toasts up, AutomaticSize X). The dash indicator becomes a corner icon rather than a centered bar. The spectate/death bar owns the bottom band only while it is visible, and the ActionLane shifts up while it does.


---

**title**: Onboarding hints flash for returning players on a slow DataStore

**severity**: minor

**file**: src/client/UI/Tutorial.lua

**line**: 340

**rootCause**: begin() runs after a blind task.delay(1.5) and checks Seen_Tutorial at that moment. Economy only mirrors Seen_Tutorial after the profile loads (src/server/Economy/Sessions.lua:134-136, signalled by the Player attribute EconomyLoaded = Rules.Attr.Loaded). When the load takes longer than 1.5s, a returning player sees the DASH bubble pop up and then abort() hides it.

**fix**: Wait for Players.LocalPlayer:GetAttribute('EconomyLoaded')==true, with a 12s timeout, and for LoadingDone from the new loading screen before calling begin(). Keep the Seen_Tutorial attribute listener.


---

**title**: Every single-player round ends on a sad 'NO WINNERS THIS TIME!' 😵 card

**severity**: minor

**file**: src/client/UI/Results.lua

**line**: 267

**rootCause**: Results.fill() shows the nobody state when WinnersCsv is empty. Core's Results.apply refuses winners when fewer than 2 players took part (src/server/Core/Results.lua:35, 58). The owner tests alone, so every round they played ended on this card with no personal stats.

**fix**: Add a personal row that always shows: placement, survived time, +coins, +XP. Data comes from the new Player attributes LastPlacement, LastSurvived, LastRoundCoins and LastRoundXP (see contractChanges). Replace the 😵 with a neutral 'ROUND OVER' illustration. In a 1-participant round, show 'You lasted 41.2s! Best: 55.0s'.


---

**title**: Text is unreadable on phones (roulette rules, Solo picker captions, long toasts)

**severity**: minor

**file**: src/client/UI/Roulette.lua

**line**: 328

**rootCause**: Roulette Info has Size (0.9,0.15) with UIAspectRatioConstraint 5.2 and DominantAxis Height, which gives about 281x54px at 800x360. The Body label is 0.46 of that height with 2 lines, so the text renders at about 10-11px. Solo/Picker.lua:236-239 captions are 0.055-0.06 of a ~140px card, about 8px. Notify toast width is fixed at 0.62 of a 0.5-wide box with max 460px (Notify.lua:395-403), so long server toasts such as "Couldn't load your save. Progress won't be kept!" shrink to the 8px MinTextSize.

**fix**: The UIKit text helper enforces MinTextSize 12 on phone. The roulette info panel uses AspectRatio about 3 and is at least 0.2 of the screen height, or is dropped, since Intro already shows the rules. Picker cards drop the 'YOUR BEST'/'WORLD #1' caption lines in favor of a trophy or stopwatch icon next to the value. Toasts use AutomaticSize X, capped at 0.8 of the screen width, and wrap to 2 lines.


---

**title**: Kill feed overlaps the TOP 3 panel and the EconomyHUD delta/level-up labels

**severity**: minor

**file**: src/client/UI/Notify.lua

**line**: 267

**rootCause**: Feed is anchored top-right at (1,-10,0,8) with size 0.25x0.3 of the safe area. Its lower lines (y up to about 0.4) cover Top3 (Scoreboard.lua:39, y from 0.34). Its first line sits right under the EconomyHUD cluster, whose Delta and LevelUp labels drop below it (Shop/Hud.lua:138-151, DESIGN_H+2..+12).

**fix**: Move the feed to a right-side lane below the currency cluster (y 0.14-0.30) with at most 3 lines, and move Top3 to y 0.32 or lower, or merge the feed into Top3's area during score rounds. Lanes.lua owns these Y bands.


---

**title**: Equal DisplayOrders give an undefined draw order between ScreenGuis

**severity**: minor

**file**: src/client/Spectate/init.client.lua

**line**: 20

**rootCause**: PartyHUD=5 (UI/init.client.lua:52), SpectateGui=5 and DodgeballHUD=5 (Dodgeball/Throw.lua:73) are equal. SoloHud=12 (Solo/init.client.lua:59) and EconomyShop=12 (Shop/Window.lua:51) are equal. Overlapping widgets from these GUIs may draw in either order.

**fix**: Add a single UIKit.Style.Layers table: World 1, Hud 5, MinigameHud 6, Spectate 7, Overlay 10, Death 11, Modal 12, Currency 14, Solo 15, Notify 20, Loading 100. Every ScreenGui must use it.


---

**title**: Dash cooldown bar is always on screen, including the lobby and touch devices

**severity**: minor

**file**: src/client/Movement/Hud.lua

**line**: 88

**rootCause**: buildBar() parents DashCooldownBar to MovementHUD and nothing ever hides it. updateHints only hides the SHIFT and 'C SLIDE' chips on touch-only devices. On mobile the skinned Dash button already shows its own cooldown shade (lines 378-389), so the bar is duplicate clutter. It also sits in the Results/Intro phases and the lobby.

**fix**: Hide the bar on touch-only devices. Show it only while the local player is InRound or InSolo and the phase is Countdown or Round. Per brief #11, the slide gets no fill or bar at all: on the mobile Slide button, replace the shade fill (lines 390-396) with a plain dim/desaturate during cooldown.


---

**title**: No UI entries for the Bomb Tag that replaces King of the Hill

**severity**: minor

**file**: src/client/UI/Data.lua

**line**: 25

**rootCause**: MINIGAME_ICONS, Theme.MinigameColors (frozen Theme.lua:25-31) and Solo/Emblems.lua DRAW have no BombTag key. A new id falls back to '🎲', hashColor() and an initial-letter emblem. KingOfTheHill-specific coupling also remains: KingOfTheHill/Hud.lua:274-290 reads PartyHUD.Tutorial by name.

**fix**: Add Registry publishing of Color and Icon from optional definition fields (see contractChanges), and make Data.minigame return an image asset via UIKit.Icons. Add the BombTag color to Theme as a lead contract edit, and delete the KingOfTheHill entries together with the KotH client.


---

**title**: The Registry never publishes the Icon/Color attributes that Data reads

**severity**: minor

**file**: src/server/Core/Registry.lua

**line**: 85

**rootCause**: publish(minigameInfo, id, {...}) writes DisplayName, Rules, Keys, Kind, SoloCapable, Duration and Hidden. Data.minigame (Data.lua:105-111) reads attr('Color') and attr('Icon'), which are therefore always nil. Even if Icon were set, it is put into a TextLabel's Text, so an rbxassetid image would show as text.

**fix**: Add optional icon:string and color:Color3 to the Minigame contract and publish them. In Roulette, Intro and Results, render the icon through UIKit.Icons.image(nameOrId) as an ImageLabel, keeping emoji only as a last fallback.


---

**title**: Solo button is lost for good if PartyHUD is ever rebuilt

**severity**: minor

**file**: src/client/Solo/RailButton.lua

**line**: 205

**rootCause**: The attach loop exits after the first successful attach. UI/init.client.lua:32-35 destroys an existing PartyHUD before recreating it, which destroys the SOLO button parented to the old MenuRail. Shop/MenuButton.lua handles this case by watching ChildAdded; Solo does not.

**fix**: Replace both docking hacks with UIKit.Dock.add('Left', def). The Dock owns the button definitions and re-creates them whenever the dock frame is rebuilt.


---

**title**: Spectate and Movement strokes do not scale with screen size

**severity**: minor

**file**: src/client/Spectate/init.client.lua

**line**: 38

**rootCause**: UIStroke Thickness is a fixed Theme.StrokeThickness=3, or 2 for text (Spectate lines 38-41, 59-62, 85-93; Movement/Hud.lua:50-57, 72-76). These strokes are never registered with Kit.setViewport, so the outlines look heavy on a 360px phone and hairline on 1440p, unlike the rest of the HUD.

**fix**: Build these widgets with UIKit, which registers every stroke for rescaling.


---

**title**: Roulette spin timing is based on the client's first-sync time, not the phase start

**severity**: minor

**file**: src/client/UI/Roulette.lua

**line**: 678

**rootCause**: view:spin(items, now, endT) uses the local time when the client first saw the phase. The header comment says 'the reel position is a pure function of server time'. A client that syncs late, for example after a hitch, plays a compressed spin with fast ticks. A PhaseEnd extension of more than 0.75s restarts the reel from the start (line 676).

**fix**: Core writes a PhaseStart attribute (server time) in setPhase, and Roulette uses it as startT. Keep the retime path.


---

**title**: Spectate controls are confusing and give no way out

**severity**: minor

**file**: src/client/Spectate/init.client.lua

**line**: 265

**rootCause**: STOP/WATCH only toggles the CameraSubject back to your own character, which is standing on the spectator platform. The < > buttons hide when there is 1 or fewer candidates. The Q/E hint is decided once at build time from KeyboardEnabled. There is no headshot, alive count, LOBBY or REVIVE button. Spectate activates automatically on elimination (lines 286-288) with no choice offered (brief #17/#28).

**fix**: Rewrite as part of the DeathScreen and spectate bar (see the briefPlans entry for #17/#28).


## briefPlans


---

**briefItem**: #20 + #7 + #9 All UI 10x better, modern, not AI slop, like the references

**currentState**: Widget inventory, rated 1-10 against ref1-5:
- PartyHUD.MenuRail (left-middle, Shop + Solo, translucent grey backing, icons drawn from Frames): 3.
- PartyHUD.TopBar (StatusPill / TimerBadge / AliveBadge / ModifierTag, pastel purple pill, '✨' emoji): 4.
- PartyHUD.LobbyLogo ('PARTY DASH' with a different gradient per letter, ~36% of the screen height on phones, plus a 'NEXT GAME IN' pill): 4.
- PartyHUD.Top3 (dark translucent box, often empty): 3.
- PartyHUD.Tutorial (white bubble with keycap): 5.
- PartyOverlay.Roulette and ModifierRoulette (dark navy dim, cards with emoji bubbles): 5.
- PartyOverlay.Intro (white card, emoji, rules repeated a second time): 4.
- PartyOverlay.Results (dark purple card, 😵/👑/🎉 emoji, no rewards shown): 4.
- PartyNotify Big (slam text): 6. Feed: 4. Toasts (clip): 4.
- SpectateGui bar (raw Instances, '<' '>' text glyphs, no sounds): 2.
- MovementHUD DashCooldownBar plus mobile Dash/Slide skins (flat circles with text, no icons): 4.
- SoloHud.SoloRunHud: 5. SoloOverlay.SoloPicker (tiny text on phone, Frame-drawn emblems): 5. SoloOverlay.SoloResult: 6. Solo RailButton: 4.
- EconomyHUD / EconomyShop: separate kit (Shop/Ui.lua). Its fixed 1000x600 design size scaled by UIScale is the best pattern in the repo.
Common problems:
- The pastel palette and purple-ink (30,25,50) outlines read washed out next to the refs, which use pure black outlines, saturated primaries and Title Case labels on icon tiles.
- Every icon is an emoji or a Frame drawing.
- No uploaded images, no textures in panels.
- Four duplicated kits.

**plan**: 1) Build ReplicatedStorage.Shared.UIKit (new src/shared/UIKit/) and make it the only builder kit.
- Style.lua:
  - Colors: Red (235,50,50), Orange (255,145,20), Yellow (255,210,30), Green (70,215,60), Cyan (30,205,255), Blue (35,120,255), Purple (145,70,240), Pink (255,75,175), Gold (255,190,30), PanelDark (36,38,48), PanelDark2 (24,25,32), Outline = Color3.new(0,0,0), White.
  - Fonts: Label = FredokaOne; Heavy = Font.fromEnum(Enum.Font.GothamBlack) for prices, numbers and panel titles.
  - Stroke: text 0.09 x text pixel height (min 1.5); border 3px at 720p, rescaled.
  - Corners: tile UDim.new(0.2,0); pill UDim.new(0.3,0); panel UDim.new(0,18).
  - Layers: the DisplayOrder table.
- Text.lua: outlined white label with a black UIStroke and an optional drop-shadow clone offset +6% of its height. TextScaled with UITextSizeConstraint MinTextSize 12.
- Button.lua (see #25).
- Panel.lua: modal window authored at a fixed design size (e.g. 900x560), fitted by UIScale = min(sw*0.92/W, sh*0.88/H), using the refit pattern from Shop/Window.lua.
  - Header bar 90px with a per-panel gradient (rainbow for Shop, green for Featured, blue for Settings). Title left-aligned in Heavy 56px, 4px black stroke plus shadow.
  - Red square X: Button style 'close', 70px, CornerRadius 0.15, overlapping the top-right corner.
  - Body PanelDark plus a tiled studs texture (assets/textures/studs.png uploaded; ImageLabel ScaleType=Tile, TileSize 64, ImageTransparency 0.88). This gives the ref3/ref5 brick look.
  - Pop-in: Back 0.3s from 0.6. Only one panel is open at a time (Panel.current).
- Icons.lua, Dock.lua, Lanes.lua, Audio.lua.
- Confetti.lua: move UI/Confetti.lua here and delete Solo/Confetti.lua.
- Format.lua: m:ss, 1.2K abbreviations, robux glyph utf8.char(0xE002), verified in Studio; fall back to an uploaded robux icon.
2) HUD redesign:
- MenuRail becomes LeftDock: no backing, UIGridLayout with 2 columns, CellSize = clamp(0.15*H, 58, 100) px, CellPadding 8px, Position (0,12,0.52,0). A countdown pill (ref1 '00:46') sits above it, as wide as 2 tiles. Tiles: Shop (shop.png, Red), Daily (chest_daily.png, Purple), Wheel (wheel.png, Blue), Solo (stopwatch.png, Green).
- RightDock (vertical, right-middle): Group Chest, Limited Trail and Starter Pack offers, each with a timer or price under it, as in ref1.
- TopOffers: 2-3 product pills top-center, lobby only.
- Round TopBar: accent-colored banner with the minigame icon image and name in Heavy. The timer becomes big outlined digits with no box. Alive shows a person icon plus '7/12'.
- LobbyLogo removed (the world sign carries the brand). LobbyStatus pill takes its place (join-zone states, see #26).
- Top3 becomes a slim leaderboard of headshot circles that always lists the participants.
- Feed and toasts move into lanes.
- All lobby docks tween off-screen during Intro/Countdown/Round. Settings and coins stay.
3) Overlays:
- Roulette: generated card art per minigame (512x640 PNG on its accent color) instead of emoji bubbles. Background in a bright accent gradient (e.g. MinigameColor lightened to darkened) plus a sunburst ImageLabel rotating at 14 deg/s, instead of the near-black (40,30,95)->(15,12,35). Drop the Info panel: Intro owns the rules.
- Intro: a 3s 'HOW TO PLAY' card with 2-3 pictogram chips (icon + key or touch glyph). Remove the def.rules sub-line from the GO! big text in RoundLoop.lua:335.
- Results: gold and pink gradient podium; reward row with coin count-up, XP bar fill and streak flame.
4) Port Solo Picker/RunHud/Result and the Spectate bar to UIKit.
5) Labels on icon tiles are Title Case ('Shop', 'Daily'). ALL CAPS only for banners and announcements.

**risks**: Theme.lua is frozen, so the new palette must live in UIKit.Style; otherwise the lead must edit Theme. Shop, Solo, Movement, Spectate and the minigame HUDs all need migrating, so parallel builders must agree on the UIKit API first (wave-1 piece). GothamBlack rendering and the 0xE002 robux glyph must be checked in Studio. Uploaded images need moderation and an asset id before the UI can show them, so keep drawn fallbacks so nothing renders blank.


---

**briefItem**: #24 Fake loading screen 'Loading assets...' with progress bar + SKIP

**currentState**: None. The Roblox default loading screen is followed directly by the HUD popping in. No ReplicatedFirst mapping exists in default.project.json.

**plan**: File: src/first/Loading.client.lua, mapped to ReplicatedFirst.PartyDashFirst (needs a default.project.json and studio_pull.luau change). Fallback if the lead rejects that: src/client/Loading/init.client.lua, which shows only after Roblox's own screen.
1. Call ReplicatedFirst:RemoveDefaultLoadingScreen() first.
2. Build ScreenGui 'PD_Loading': DisplayOrder 100, IgnoreGuiInset=true, ScreenInsets=None, ResetOnSpawn=false, parented to PlayerGui.
3. Root is a CanvasGroup (for one-shot fading).
- Background: generated key-art ImageLabel (loading_bg, ScaleType Crop) with a slow zoom: UIScale 1.0 to 1.06 over 8s, Sine. Before the image loads, use a bright cyan-to-blue gradient plus the tiled studs texture.
- Logo ImageLabel ('PARTY DASH' generated logo) at top-center, 0.32 of the screen height, with a bob of sin(t*2)*0.015.
- Progress bar at (0.5, 0.78), Size (0.6, 0.055): PanelDark2 track, 3px black stroke, CornerRadius 0.5. Fill uses a Green->Yellow gradient plus a diagonal-stripe ImageLabel scrolling TileSize offset at 40px/s.
- Percent label 'Loading assets... 37%' above it in Heavy. Messages cycle every 1.1s: 'Loading assets...', 'Building arenas...', 'Charging lasers...', 'Pumping dodgeballs...', 'Almost there...'.
- Tip line at the bottom, picked at random from 6 tips (e.g. 'Slide under the HIGH laser!').
4. Fake progress over a 6.5s target: 0 to 40% in 1.2s (Quad out), hold at 62% for 0.8s, then up to 100% by 6.5s. Meanwhile ContentProvider:PreloadAsync(UIKit.Icons.list()) runs in a task, and progress cannot reach 100% before preload finishes (6s cap).
5. SKIP button: UIKit pill, Green, 'SKIP ▶', bottom-right (1,-24, 1,-24), height 0.09*H. It fades in after 1.0s. Clicking it plays the click sound and calls finish().
6. finish(): tween fill to 100% in 0.25s, show 'Ready!', fade GroupTransparency 0 to 1 over 0.35s, then Destroy. Set Players.LocalPlayer:SetAttribute('LoadingDone', true) client-locally. Audio starts music on it, Tutorial waits for it, and the HUD runs its dock pop-in on it.
7. Runs once per session (ReplicatedFirst scripts run once).

**risks**: ReplicatedFirst runs before ReplicatedStorage.Shared is guaranteed to exist, so use WaitForChild for UIKit or make the loader self-contained with inline helpers. Requires the frozen default.project.json and tools/studio_pull.luau to be edited by the lead.


---

**briefItem**: #23 Calm background music, mutable in Settings (Settings panel with Music/SFX toggles)

**currentState**: No music, no SoundGroup and no settings UI. SFX are spread over 14 files plus server-created sounds.

**plan**: UIKit/Audio.lua (client-only API, required from client code):
- Creates SoundService.PD_Music (SoundGroup, Volume 0.45) and PD_Sfx (Volume 1).
- Music: a playlist of 3 calm, Roblox-owned or licensed tracks (the builder picks them with the Studio MCP search_asset, Audio, keywords 'calm'/'chill'/'happy lobby', creator Roblox, and verifies Sound.IsLoaded and TimeLength > 60 in Play). Looped=false. 2s crossfade to the next track on Ended. Volume x1.0 in Lobby/Waiting and x0.6 in Round (tween 1s on Phase change). Starts on LoadingDone.
- Audio.autoGroup(): every Sound under workspace or SoundService with no SoundGroup and no 'PD_Music' attribute gets SoundGroup = PD_Sfx, so server and minigame sounds respect the toggle without editing those pieces.
- Audio.play(name, pitchMul?) wraps PlayLocalSound and returns early when SFX is off.
Settings panel (UIKit.Panel 'Settings', 640x420 design):
- Opened from a small round gear button (settings.png) placed top-left next to the Roblox buttons. Position X from GuiService.TopbarInset.Min.X + 8 (or 'Settings' in the LeftDock on phones if TopbarInset is too narrow).
- Rows: icon + label + toggle. Music (music note) ON/OFF. Sound Effects (speaker) ON/OFF. 'Replay Tutorial' button: sets a local flag and calls Tutorial.restart().
- Toggle: 120x56 pill. ON = Green with the knob on the right; OFF = grey (120,120,130) with the knob on the left. Knob tween 0.15s Back. A click sound plays when the toggle turns on.
Persistence:
- New remote UI_Settings (client to server, payload {music: boolean, sfx: boolean}), handled in src/server/UI/init.server.lua. Validate typeof==boolean, rate-limit 0.5s, set the Player attributes Set_Music and Set_Sfx.
- Economy adds profile.settings = {music=true, sfx=true}. It mirrors them on load (next to Sessions.lua:134) and saves them when the attributes change (same pattern as Seen_Tutorial, Sessions.lua:358-365).
- The client applies changes immediately (optimistic); Audio listens to Set_Music/Set_Sfx.

**risks**: Free, public music is limited to Roblox-owned and licensed tracks. User-uploaded audio over 6s is private, so IDs must be verified in a Play session. PlayLocalSound honoring SoundGroup volume must be verified; Audio.play's own guard covers it either way.


---

**briefItem**: #25 Click sound on every button + hit sound

**currentState**: Click sounds exist only in some Shop and Solo buttons, using different sounds. Spectate, the Solo rail button, Shop tabs and KotH have none. Core client hits (Core/init.client.lua:116-128) show a POW word, sparkles and camera shake, but no sound.

**plan**: UIKit/Button.lua: Button.new(opts) returns {instance, setEnabled, setBadge, setTimer, setText, setPrice, destroy}.
opts:
- style: 'tile' | 'pill' | 'round' | 'close' | 'toggle'
- color, icon (Icons key or rbxassetid), text, badge ('!' or a number), price ({robux=19, old=199} or {coins=500})
- size, position, anchor, parent, layoutOrder
- sound: default 'click'; also 'buy', 'back' or false
- cooldown: default 0.25s debounce
- onClick
Built as a TextButton with Text='' and AutoButtonColor=false.
- Tile: vertical gradient (lighten 0.15 to darken 0.2), 3px black Border stroke, inner rim Frame with a 2px stroke in lighten(color, 0.45) at transparency 0.25, and a gloss Frame on the top 30% at 0.8 transparency. Icon ImageLabel at 88% centered at y 0.42, overflowing the top by 6%. Label anchored (0.5,0.5) at y 0.86, size (1.1,0.34), Title Case, Label font, white with black stroke.
- Pill: CornerRadius 0.3, a darker 12% bottom strip for depth, and an optional price row under it with a coin or robux glyph.
- Badge: red circle with '!' at (0.92,0.08), pulsing 1 to 1.15 (Sine 0.55s, repeat, reverse).
Interaction:
- Hover (MouseEnter): UIScale to 1.06, Back 0.12s.
- Press (InputBegan MouseButton1 or Touch): 0.92 in 0.06s.
- Release: Back 0.2s to 1 or 1.06.
- Activated: debounce, then Audio.play(sound), then onClick.
- Disabled: grey gradient, a +/-6 degree wiggle and Audio.play('deny').
- Sets attribute PD_Kit=true.
Button.attach(existingGuiButton, opts) retrofits the bounce and sound onto buttons built elsewhere.
Audio.autoClick(PlayerGui) is the safety net. It hooks PlayerGui.DescendantAdded: for any GuiButton that is not a descendant of TouchGui/ContextActionGui and has neither PD_Kit nor NoClick, it connects Activated to Audio.play('click'). This guarantees brief #25 even in pieces that were not migrated.
Sound catalog:
- click: rbxassetid://15675059323 (Roblox_UI_Bright_Click, already used in Movement/Assets.lua:24), volume 0.5.
- whoosh (open/close): rbxassetid://15675024286.
- Keep tick/pop/land/boom (the rbxasset sounds in UI/Sfx.lua).
- purchase (ka-ching layered, from Shop/Sfx.purchase), deny, reward.
- hit: a Roblox-owned punch/impact found via search_asset. Fallback: rbxasset://sounds/action_jump_land.mp3 at speed 1.5.
Hit sound: in Core/init.client.lua watchCharacter, when Stunned becomes true, create a 3D Sound in PD_Sfx on HumanoidRootPart (RollOffMaxDistance 80, PlaybackSpeed random 0.9-1.1) and play it. Use a louder 2D Audio.play('hit') when the hit player is the local player.

**risks**: Auto-hooking may double-click buttons that already play their own sound until those pieces are migrated. Mark them with PD_Kit or NoClick during migration.


---

**briefItem**: #17 + #28 After dying: SPECTATE / back to LOBBY / REVIVE for Robux

**currentState**: On elimination Core sets Spectating=true, teleports the player to the spectator stands (RoundLoop.lua:270-273) and sends Announce.big 'YOU'RE OUT!'. The SpectateGui bar auto-opens. There is no choice, no lobby (the lobby map is destroyed for the whole round: Places.destroyLobby at RoundLoop.lua:296, LOBBY_CENTER == ARENA_CENTER in Config) and no revive product.

**plan**: Core/Economy prerequisites (contract):
- Persistent lobby at its own position. Do not destroy it per round.
- Remote Core_DeathChoice (client to server: 'lobby' | 'spectate').
- Product Config.PRODUCTS.Revive.
- Player attributes CanRevive (bool) and ReviveUntil (server time), set when a survival-round player is eliminated in Round with at least 2 alive and no revive used this round. Window: 8s.
- Core API to revive into the live ctx: alive again, InRound=true, Spectating=false, teleport to a random map Spawns part, 2s spawn shield, Announce.feed '<name> is BACK!'.
New client module src/client/UI/Death.lua, a ScreenGui layer 'Death' (DisplayOrder 11):
- Trigger: InRound goes true to false while Phase==Round and Spectating==true.
- After 0.6s (letting the existing big 'YOU'RE OUT!' play), slide up from the bottom: a red banner 'YOU'RE OUT!' with the sub-line '#4 of 8 · 23.4s · +7 coins' (from LastPlacement/LastSurvived/LastRoundCoins).
- Row of 3 Button pills, each 0.28 of the screen wide (max 300px) and 0.13*H tall:
  - REVIVE: Green, heart icon plus '⟨robux⟩ 25', with a circular countdown ring drawn from ReviveUntil. Shown only while CanRevive is true. Calls MarketplaceService:PromptProductPurchase(Config.PRODUCTS.Revive). Hidden when the product id is 0 unless workspace Debug_FreeRevive is set, which fires Core_DeathChoice('revive') for critics.
  - SPECTATE: Blue, eye icon.
  - LOBBY: Orange, house icon. Fires Core_DeathChoice('lobby'); the server teleports the player to the lobby, and they can then use the Wheel, Shop and Solo.
- After 10s with no choice, default to SPECTATE.
- The Spectate bar is rewritten with UIKit: target headshot (rbxthumb) plus name plus 'Alive 3/8'. Big arrow buttons (image) left and right of the name. Touch swipe left/right on the empty screen also cycles. A LOBBY pill and, while the window is open, a REVIVE pill. Remove the STOP/WATCH toggle.
- Spectating from the lobby only needs the camera to follow the target; no stands are required.
- On revive success: hide Death and the Spectate bar, Announce.big 'REVIVED!', Audio.play('reward').

**risks**: Depends on the Core rework (persistent lobby, revive API) and on Economy receipt handling. Revive must be validated server-side (round still running, player eliminated this round, once per round) to avoid paying for a dead round. With StreamingEnabled, the arena might not stream to a player in a far-away lobby, so check workspace.StreamingEnabled (default off here).


---

**briefItem**: #14 20 seconds in the lobby after a round, then the roulette

**currentState**: Config.LOBBY_TIME = 15. Lobby.lua shows 'NEXT GAME IN n' inside the logo pill.

**plan**: The lead changes Config.LOBBY_TIME to 20. The UI shows the countdown in the new LobbyStatus pill: top-center under the topbar, Heavy digits, urgent red with tick sounds at 5s or less (the existing logic at Lobby.lua:144-149). At 3, 2, 1, Notify.big shows the digits ('GET READY'). The end-of-round Results card shows 'LOBBY IN n' (Results.lua:122) as before.

**risks**: Pacing: lobby 20 + roulette 5 + modifier 4 + intro 4 + countdown 3 is about 36s between rounds. The roulette info panel and the GO! rule line should go so the pre-round flow stays punchy.


---

**briefItem**: #26 Step into the square in the lobby to join the round

**currentState**: No join zone. Every eligible player is picked (RoundLoop.pickParticipants).

**plan**: Contract: the server (Core) sets the Player attribute Joined (bool) and the GameState attribute JoinedCount (number), and the Lobby map adds a JoinPad part.
UI LobbyStatus pill states:
- (a) Not joined: yellow pill 'STEP ON THE PAD TO PLAY!' with a pulsing arrow icon. A client-side Beam from the HumanoidRootPart to the JoinPad (Attachment on each, Beam texture arrow, TextureSpeed 1.5, Width 1.2, color Yellow) shows while the player is not joined and Phase==Lobby.
- (b) Joined: green pill 'YOU'RE IN! 3 ready · 0:14'. Plays 'reward' and a punch scale when Joined becomes true.
- (c) JoinedCount==0 near the end: 'Nobody joined, waiting...'.
Optionally a row of up to 8 headshots of the joined players under the pill.

**risks**: Core must define what happens when nobody joins (restart the lobby timer) and whether AFK players are excluded.


---

**briefItem**: #27 Daily chest + extra chest for joining the group and liking the game

**currentState**: The daily reward is granted silently: Sessions.checkDaily sends a toast 'DAILY REWARD! +50 coins' (Sessions.lua:331-350). There is no chest, button or panel.

**plan**: UI side; Economy owns the server remotes Economy_ClaimDaily and Economy_ClaimGroupChest, plus the attributes DailyReadyAt, DailyStreak and GroupChestReadyAt.
- LeftDock tile 'Daily' (chest_daily.png). The badge '!' shows when workspace:GetServerTimeNow() >= DailyReadyAt; otherwise a timer pill 'hh:mm:ss' sits under the tile.
- Panel 'Daily Chest': a 7-day track of 7 small tiles (Day 1 50 coins up to Day 7 a big chest), the current day highlighted gold with a check mark on past days, and a big CLAIM pill.
- Claim animation: the chest image shakes (rotation +/-8 degrees, 0.5s), scales up 1.3, burst rays and confetti, then reward icons fly to the coin counter (Shop/Hud already animates flying coins).
- RightDock tile 'Group Chest' (chest_group.png), panel with 2 steps:
  - [JOIN GROUP]: GroupService:PromptJoinAsync(groupId) on the client; the server verifies with Player:IsInGroup.
  - [LIKE THE GAME]: honor step; no API can verify likes.
  - Then OPEN CHEST.

**risks**: Likes cannot be verified, and rewarding likes or favorites may conflict with Roblox's engagement-incentive rules. The lead should decide whether to gate only on group membership. The group id must go into Config.


---

**briefItem**: #29 Wheel of fortune in the lobby UI, 9 Robux per spin

**currentState**: None. Config.PRODUCTS has no spin product.

**plan**: LeftDock tile 'Wheel' (wheel.png), with a badge when a free spin is available.
Panel 'Lucky Wheel' (800x600 design):
- Wheel ImageLabel: generated 8-segment wheel, 420px, centered left. Gold pointer image at the top. Light bulbs around the rim blink on a 0.2s alternating tween.
- Segments: 50, 100, 250, 500 and 1000 coins, a trail, 2x coins for 15 min, and 'Spin again'.
- Right column: 'SPIN' Button pill Green with a robux glyph and '9' (product WheelSpin). 'FREE SPIN' shows when available, with its timer. Prize odds list (ref5 style percentages).
Flow:
- RemoteFunction Economy_SpinWheel(useFree) returns {index, reward} or an error. The server rolls the RNG and grants the prize.
- For Robux spins, the receipt adds Player attribute WheelSpins += 1 and the client then calls the spin.
- Animation: target rotation = 360*6 + (360 - index*45 + 22.5 + random(-15,15)), Quint Out over 4.5s. Tick sound each time floor(rotation/45) changes. On stop: punch, confetti, reward popup card.

**risks**: Paid random rewards need prize odds shown to players (Roblox policy for paid random items), so show the odds list.


---

**briefItem**: #30 + #31 Starter packs (500 coins) and a limited trail at 19 Robux shown as from 199

**currentState**: The Shop has a Robux tab (RobuxTab.lua) with coin packs. There are no lobby offers, no strikethrough prices and no limited timer.

**plan**: TopOffers row, top-center, lobby only. Pill buttons 0.18 of the screen wide x 0.09*H tall, ref1 style, with the price line under them:
- 'STARTER PACK' (Yellow, gift icon): ⟨robux⟩ price for 500 coins plus a trail. One-time; hidden once the Owned attribute is set.
- 'LIMITED TRAIL' (Purple): '19' with the old price '199' shown with a red strikethrough. The strikethrough is a Frame Size (1.15,0.14) rotated -10 degrees, Red with a black 1.5px stroke, over the old-price label (ref5 style). A countdown 'Ends in 2d 13h 05m' comes from Config.LIMITED_TRAIL_END_UTC.
- '2X COINS' (Green): game pass.
Clicking a pill opens a Featured panel modeled on ref5:
- Green header 'Shop', '-- FEATURED --' title, red 'New!' tag, 'Limited Time!', the live countdown.
- A big preview of the trail (a ViewportFrame with a dummy running and the trail attached, or the generated art).
- Green Robux price buttons with the strikethrough old price above them.
All prompts use MarketplaceService:PromptProductPurchase or PromptGamePassPurchase, and the server grants the items.

**risks**: A fake 'from 199' anchor price can be seen as a deceptive-pricing pattern. The lead may want to back it with a real discount event. Product ids are 0 until created in Creator Hub, so hide the buttons or use the Debug path in Studio.


---

**briefItem**: #5 Generated graphics (ChatGPT) that are very good and match

**currentState**: Every in-UI icon is an emoji (Data.lua:25-47, Results 👑😵🎉, Hud ✨) or drawn from Frames (Kit.coin, Solo/Emblems.lua, RailButton stopwatch). Local PNGs already exist in assets/icons (shop, chest_daily, chest_group, wheel, gift, settings, trophy, stopwatch, crown), sliced from assets/raw/sheetA_menu.png by tools/slice_sheet.py, but none is uploaded.

**plan**: UIKit/Icons.lua maps names to 'rbxassetid://<id>'. Icons.image(parent, name, props) returns an ImageLabel (ScaleType Fit, transparent background). When the id is missing it falls back to the drawn version (Kit.coin, Emblems) or the emoji. Icons.list() feeds the loading-screen preload.
Still to generate, in the same style (glossy, black outline, transparent background):
- Utility icons: coin, robux (only if glyph U+E002 fails), music note, speaker, eye (spectate), house (lobby), heart+ (revive), play, skip, lock, check, star, flame (streak), person (alive), skull/out, timer clock, arrow left/right, X close.
- Minigame icons: BombTag bomb, LaserTracer lasers, Dodgeball ball, HoleInTheWall wall, Spin pillar/bat.
- Offer art: trail, starter pack box, VIP crown, 2x badge.
- Large art: roulette card art per minigame (512x640), 'PARTY DASH' logo (transparent 1024x400), loading background key art (1920x1080), wheel (8 segments), sunburst rays, diagonal-stripe tile.
Pipeline: slice with tools/slice_sheet.py, upload with the Studio MCP upload_image/store_image (lead), then paste the ids into Icons.lua.

**risks**: Moderation delay on uploaded images. Keep fallbacks so the UI never shows blank squares. Icon resolution: upload at 256 and 512 for large art.


---

**briefItem**: #6 + #12 + #19 Addictive, come back, spend Robux (UI hooks)

**currentState**: Results show only the winners. Coins and XP arrive as separate toasts that are easy to miss (MAX_TOASTS=2 drops older ones, Notify.lua:390-392). No streak visuals, no 'next unlock', no notification badges except the Shop '!'.

**plan**: - Results card gets a reward row: coin icon with a count-up from 0 to LastRoundCoins (0.8s with ticks), an XP bar fill tweening from the old XP to the new XP with a 'LEVEL UP!' burst, and a streak flame 'x3' when Streak >= 2 (leaderstats.Streak exists). The footer becomes a teaser: 'Level 5 unlocks Rainbow Trail' (from Economy cosmetics rules), or 'Daily chest ready!' when claimable.
- Badges: Daily '!', Wheel '!' when a free spin is available, Shop '!' when an upgrade is affordable (already exists), Group Chest timer.
- Lobby: joined-players avatar row, a 'WIN STREAK x3' chip under the LobbyStatus pill.
- Win: full-screen confetti plus a 'VICTORY!' big text with a gold gradient; the existing win effect cosmetic.
- Death screen with REVIVE.
All of these read Player attributes, so the UI stays read-only.

**risks**: Needs the Economy and Core attributes listed in contractChanges.


---

**briefItem**: #10 Bomb Tag replaces King of the Hill (UI hooks only)

**currentState**: Data.MINIGAME_ICONS, Theme.MinigameColors and Solo/Emblems have KingOfTheHill and no BombTag. KingOfTheHill/Hud.lua is coupled to PartyHUD.Tutorial.

**plan**: - Delete the KotH client UI and its entries.
- Add a BombTag icon (bomb.png), a color (Red/Orange accent such as (255,90,40)) through the Registry Color attribute or a Theme edit, and roulette card art.
- The Bomb Tag HUD (owned by the BombTag piece) uses UIKit and the ActionLane:
  - While holding the bomb: big pulsing fuse timer under the TopBar ('YOU HAVE THE BOMB! 7.3', Red, punch every second, tick pitch rising), a red screen-edge vignette (ImageLabel radial at 0.6 to 0.2 transparency pulse) and an arrow toward the nearest player.
  - While not holding it: a holder chip 'BOMB: <name>' with a headshot.
- Alive counter and Results work unchanged (survival kind). soloCapable=false, so the Solo picker skips it.

**risks**: The fuse timer must be driven by server time (an attribute on the map or the player) so all clients agree.


---

**briefItem**: #11 Slide: cooldown but no bar (HUD part)

**currentState**: PC: no slide bar, but a 'C SLIDE' chip hangs off the dash bar (Movement/Hud.lua:173-183). Mobile: the Slide button shows a shade fill during cooldown (Movement/Hud.lua:390-396). Config.SLIDE_COOLDOWN=0.4.

**plan**: - Remove the slide shade fill. During cooldown set the Slide button's ImageTransparency or icon to a 0.45 dim and its UIScale to 0.94, then pop back to 1.0 with Back 0.15s when it is ready again. No progress visual.
- Replace the 'C SLIDE' text chip with a keycap icon only in the Intro card.
- Hide DashCooldownBar on touch-only devices and outside InRound/InSolo play.
- Skin the mobile buttons with images (dash and slide icons) instead of text.

**risks**: Coordinate with the Movement owner, who is reworking the slide animation and cooldown.


---

**briefItem**: #32 The lobby must look 10x better (HUD part)

**currentState**: Lobby HUD = the bouncing 9-color 'PARTY DASH' logo, 'NEXT GAME IN' pill and a vertical rail with 2 buttons on a grey backing.

**plan**: Lobby HUD composition, matching ref1/ref2:
- Top-left: Settings gear.
- Top-center: TopOffers row, then the LobbyStatus pill under it.
- Top-right: currency/level (EconomyHUD, restyled with Heavy digits and coin.png).
- Left: timer pill plus the 2x2 tile grid.
- Right: Group Chest, Limited and Starter offers with timers and prices.
- Bottom-center: kept empty (ActionLane), so the beautiful map is visible.
All docks pop in staggered (Back 0.4s, 0.05s apart) after LoadingDone, and slide off when Phase leaves Lobby/Waiting/End.

**risks**: Phone real estate. Test at 800x360 and 667x375 (iPhone SE landscape) so the docks never cover the thumbstick zone (bottom-left 40%) or the jump/action buttons.


---

**briefItem**: #3 Controls (HUD presentation part)

**currentState**: Mobile Dash/Slide are re-skinned CAS buttons with text labels. Key hints: Intro chips and Tutorial bubble. The PC dash bar sits at bottom-center.

**plan**: - Mobile action buttons use image icons (dash, slide and the minigame action: throw/bat/bomb pass). Size stays proportional to the jump button (Movement/Hud.lua:358-376 logic). Ready state shows a subtle glow ring.
- PC: a small ability cluster at bottom-right: Dash icon with a radial cooldown made from a UIGradient Transparency sweep on a ring image, plus a keycap 'SHIFT'. The slide shows only a keycap 'C', with no cooldown visual.
- The Tutorial uses the same icons, so players learn one visual language.

**risks**: The Movement owner owns the input code; the UI only provides the skin.


---

**briefItem**: #1 + #18 Fix all bugs (UI subsystem)

**currentState**: See the bugs list: empty TOP3, overlap lanes, tutorial flash, sad solo results, tiny phone text, feed overlap, DisplayOrder collisions, dash bar clutter, missing Icon/Color publishing, Solo re-dock, unscaled strokes, roulette timing, spectate UX.

**plan**: Fix each bug as specified in the bugs list. Most are resolved structurally by the UIKit migration (Layers, Lanes, Dock, Text MinTextSize 12, stroke registry). Keep the existing inspection attributes critics rely on: Roulette Spinning/CenterId/SelectedId, Notify LastBig/LastFeed/LastToast, Tutorial Step, Scoreboard row UserId/Score. Add new ones: Death 'Shown', LobbyStatus 'State', Settings 'Music'/'Sfx', Loading 'Done'.

**risks**: Regression risk across Shop and Solo during migration. Migrate one system per piece, with critic screenshots at 800x360 and 1920x1080.

**contractChanges**: 1. NEW shared module tree src/shared/UIKit/ (ReplicatedStorage.Shared.UIKit), owned by the UI piece and built in wave 1 so other pieces can build on it. API freezes once it lands. Modules:
- Style: palette, fonts, stroke and corner tokens, Layers.
- Text, Button, Panel, Icons.
- Dock: Dock.add(dockName, def) returns a Button. Docks: 'Left', 'Right', 'TopOffers', 'TopLeft'. It waits for PartyHUD and re-creates buttons if the dock is rebuilt.
- Lanes: reserved Y bands Status, Toast, Feed, Action, BottomBar.
- Audio: SoundGroups PD_Music/PD_Sfx, play(), autoGroup(), autoClick(), music playlist, settings binding.
- Confetti, Format.
This replaces the four private kits: UI/Kit.lua, Solo/Ui.lua, Shop/Ui.lua and KingOfTheHill/Ui.lua.

2. ARCHITECTURE.md 'UI conventions':
- Replace the MenuRail contract (Shop LayoutOrder 10, Solo 20) with the Dock API. Left grid order: Shop 10, Solo 20, Daily 30, Wheel 40. Right: GroupChest 10, Limited 20, Starter 30. TopLeft: Settings.
- Keep a Frame named PartyHUD.MenuRail as an alias of the Left dock during migration. A UIGridLayout overrides child Size, so the current Shop and Solo buttons still fit.
- Every ScreenGui takes its DisplayOrder from UIKit.Style.Layers. All HUD ScreenGuis use IgnoreGuiInset=true with ScreenInsets=DeviceSafeInsets, and position top items with GuiService.TopbarInset.
- Bottom-center placement only through UIKit.Lanes.
- Every button goes through UIKit.Button, or carries NoClick for gameplay buttons.

3. Theme.lua (frozen, lead edit): add MinigameColors.BombTag and remove KingOfTheHill. Optionally move the saturated palette into Theme; otherwise it lives in UIKit.Style.

4. Minigame contract (Contracts/Minigame.lua): optional definition fields icon (Icons key or rbxassetid) and color (Color3). Core Registry.lua:85-93 publishes them as MinigameInfo attributes Icon and Color, which Data.minigame already reads.

5. Config.lua:
- LOBBY_TIME = 20.
- PRODUCTS gains Revive, WheelSpin, StarterPack and LimitedTrail.
- New keys: GROUP_ID, LIMITED_TRAIL_END_UTC, REVIVE_WINDOW = 8, REVIVE_PER_ROUND = 1.
- LOBBY_CENTER moves away from ARENA_CENTER (e.g. Vector3.new(0,50,-700)) so the lobby persists during rounds. Core stops calling Places.destroyLobby every round. This is needed for the LOBBY button (#17).

6. GameState (frozen doc, lead edit) new attributes:
- PhaseStart (server time when the phase began, for roulette sync).
- JoinedCount (join zone, #26).
Core must also write initial zero scores for all participants at round start (fixes the empty TOP 3).

7. New Player attributes:
- Joined (bool): Core, join pad.
- Set_Music, Set_Sfx (bool): server UI script, persisted by Economy in profile.settings.
- CanRevive (bool) and ReviveUntil (server time): Core.
- LastPlacement and LastSurvived (Core at elimination or round end); LastRoundCoins and LastRoundXP (Economy at round end). Used by the Death and Results screens.
- DailyReadyAt, DailyStreak, GroupChestReadyAt, WheelSpins, FreeSpinAt: Economy.
- LoadingDone: client-local, set by the loading screen.

8. New remotes:
- UI_Settings (client to server, {music: boolean, sfx: boolean}): server UI script, validated and rate-limited to 0.5s.
- Core_DeathChoice (client to server, 'lobby' | 'spectate', plus 'revive' only when workspace Debug_FreeRevive is set). Server validates that the player was eliminated this round and the round is running.
- Economy_ClaimDaily, Economy_ClaimGroupChest (RemoteEvents).
- Economy_SpinWheel (RemoteFunction returning {index, reward}; server RNG).

9. default.project.json gains "ReplicatedFirst": { "PartyDashFirst": { "$path": "src/first" } } for the loading screen, and tools/studio_pull.luau must also rebuild ReplicatedFirst.PartyDashFirst.

10. New debug hook: workspace attribute Debug_FreeRevive (bool), so critics can test revive without Robux.

**qualityNotes**: Duplication:
- Four UI kits (UI/Kit.lua, Solo/Ui.lua, Shop/Ui.lua, KingOfTheHill/Ui.lua) plus inline builders in Movement/Hud.lua, Spectate/init.client.lua and Dodgeball/Throw.lua.
- Two near-identical Confetti modules (UI/Confetti.lua vs Solo/Confetti.lua).
- Three Sfx modules reusing the same five rbxasset sounds with different 'click' meanings.
- Three different docking strategies: Shop watches ChildAdded, Solo polls every 0.5s with a 20s fallback, KotH looks up PartyHUD.Tutorial by name.

Per-frame work:
- Lobby.lua: RenderStepped moves 9 letters plus the logo every frame for the whole lobby.
- Hud.lua: Heartbeat reads 2 GameState attributes every frame even with the timer hidden. It returns early only when the TopBar is hidden, which is fine, but Lobby could also run at about 30 Hz.
- Spectate: polls every 0.3s; validate() calls candidates() twice, through refreshLabels.
- Tutorial: bobConn RenderStepped for the whole tutorial.
None of this is severe, but prefer a single UIKit Animator (one RenderStepped iterating registered callbacks) for idle bobs.

Layout:
- PartyHUD has IgnoreGuiInset=false while MovementHUD, Spectate, KotH and Dodgeball use true. Bottom offsets therefore live in different coordinate spaces, which is the root of the overlap bugs.
- Mixed sizing approaches (Scale+Aspect+SizeLimit vs fixed design pixels+UIScale). The Shop's fixed design size plus fit UIScale (Shop/Window.lua refit) gives the most consistent results; use it for every Panel.

Look:
- Emoji icons (⚡🏐👑🚧🌀✨😵🎉) render differently per platform and read as placeholder art; replace them with uploaded images.
- Ink (30,25,50) outlines and the pastel palette are the main reasons the UI looks washed out against the references, which use pure black outlines and saturated fills.

Security and robustness:
- UI_TutorialDone is safe (no payload, 2s rate limit, PlayerRemoving cleanup).
- New remotes must validate types and state server-side. Wheel RNG and revive eligibility stay on the server.
- Purchase buttons must handle Config.PRODUCTS id 0 (hide them, or use the Debug path) so PromptProductPurchase never errors in Studio.

Testability:
- Keep the attribute inspection hooks that critics rely on: Roulette Spinning/CenterId/SelectedId/Selected, Notify LastBig/LastFeed/LastToast, Tutorial Step, Scoreboard row UserId/Score, FeedLine/Toast Text.
- Add equivalent ones on the new screens: PD_Loading Done, Death Shown/Choice, Settings Music/Sfx, LobbyStatus State, Wheel LastIndex.

Relevant paths:
- /Users/jannawrot/Desktop/roblox-julek-temp/src/client/UI/
- /Users/jannawrot/Desktop/roblox-julek-temp/src/client/Solo/
- /Users/jannawrot/Desktop/roblox-julek-temp/src/client/Spectate/init.client.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/src/client/Movement/Hud.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/src/server/UI/init.server.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/src/client/Shop/MenuButton.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/src/server/Core/RoundLoop.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/src/server/Core/Places.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/src/server/Core/Registry.lua
- /Users/jannawrot/Desktop/roblox-julek-temp/assets/icons/ (9 sliced PNGs, not uploaded)
- /Users/jannawrot/Desktop/roblox-julek-temp/tools/slice_sheet.py
