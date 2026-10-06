# v1 QA playtest


## observations


---

**area**: Spin / map exploit (brief #22)

**issue**: The ledge at the bottom of each pillar is a standable exploit. The 'Foot' disc is CanCollide=true, 1 stud wider than the pillar body, and its top (y=26) is exactly the map KillY (26). A player standing on it has root Y=29, which is above KillY, so they are never eliminated, and the bar never reaches them because height=-24 is below Hit.LOW_LIMIT (-5.5).

**severity**: critical

**evidence**: Spin Round, Debug_NoEliminate=false. Server teleport to Pillar01.Foot edge (40.3, 29.05, 0). I sampled every 0.5 s for 7 s: InRound=true, Spectating=false, root pos stayed 40.3-40.5, 29.0, 0, state=Running, FloorMaterial=Slate. Code: src/server/Minigames/Spin/Arena.lua:111 disc(model, center, "Foot", top - (0, PILLAR_HEIGHT-2, 0), 3, BODY_RADIUS + 1, ...); Arena.lua:32 KILL_DEPTH = 24 -> map attr KillY=26; lava parts (Lava/LavaGlow, y=24.4-25) are CanCollide=false. Fix: remove Foot or make it CanCollide=false, set KillY above any collidable geometry under the tops (e.g. center.Y-8), or add a lava touch-kill.


---

**area**: Spin / Laser Tracer hit detection (brief #22, 'jump but still hit')

**issue**: The server tests hits against the replicated character position, which arrives about 0.2 s after the client's own. Lag compensation only subtracts half the ping (about 0 in Studio), so a jump that clears the bar on the player's screen is still counted as a hit. Laser Tracer has the same problem for low lasers (jump check on server root Y) and for high lasers (server-side 'Sliding' attribute with a 0.15 s grace).

**severity**: critical

**evidence**: Spin Round with Space held 10 s (auto-jump), logged on server Heartbeat and client in parallel. 8 hits in 14 s. Three examples:
- Hit at server t=1.24: server height trace [0.20 x10, -0.02, 0.41], client feet at the same hit [1.71 ... 7.21, 8.11].
- Hit at server t=5.74: server [0.20 x11, 0.12], client [-0.03 ... 6.11, 7.22].
- Hit at server t=4.39: server shows a descending jump (6.73 -> 0.03) while the client is already in the next jump (-0.01 -> 6.85).
Code: src/server/Minigames/Spin/init.lua:243 lag = clamp(ping*0.5, 0, MAX_LAG=0.2); Spin/Hit.lua CLEAR_HEIGHT=1.4; LaserTracer/init.lua:60-63 lagOf = ping*0.5+0.03; LaserTracer/init.lua:118 SLIDE_GRACE=0.15. Fix: rewind by ping + ~0.25 s of interpolation buffer, or have the client report jump/slide timestamps (validated, rate-limited) and treat the player as airborne/sliding for that window.


---

**area**: Water / fall bug (brief #16)

**issue**: In King of the Hill (score kind), a fall never kills. The player freezes in mid-air about 25 studs under the map for 2 s with the toast 'Oops! Back in 2...', then gets teleported back to a spawn. This is exactly what the owner describes. In the survival modes, elimination is an instant teleport to the spectator stands with no fall, splash or death moment. The sea (y=-12) is 32 studs below KillY (20), so a player never visibly lands in the water before vanishing.

**severity**: critical

**evidence**: KotH, NoEliminate=false, teleport to (83, 53, 0): t=0.4 y=49 Freefall, t=0.8-2.5 pos (83, 24, 0) Anchored=true, t=2.9 pos (-11, 54, 38) Running, InRound stayed true. Knockback.apply(p, dir, 200, 0.6) gave the same result, and the screenshot shows the toast 'Oops! Back in 2...' at the bottom, overlapping the DASH row. Code: src/server/Core/Context.lua:295-306 (_onFall score branch: Teleport.setAnchored(p, true), Announce.toast, task.delay(2, _respawnNow)). Survival path: RoundLoop.lua:258-279 onEliminated -> Places.sendToStands(p) immediately. World.SEA_LEVEL = ARENA_CENTER.Y - 62 (src/server/Core/World.lua:14), Config.KILL_DEPTH = 30.


---

**area**: Slide animation and cooldown (brief #11)

**issue**: The slide is a head-first belly flop, not a feet-first football slide tackle. The whole body is pitched forward 78 degrees and the Cartoony_Fall animation plays on top of the walk/run tracks. The slide cooldown is only 0.4 s, so slides chain almost back to back. A slide pressed while airborne or stunned is silently ignored, with no feedback.

**severity**: major

**evidence**: Client sampler during a slide: LowerTorso.Root C0 pitch reached -69, then -75, then -78 deg; HipHeight 2.00 -> 0.95; playing tracks 742640026 (walk), 742638842 (run), 742637151 (Cartoony_Fall); horizontal speed 36 -> 20 over about 0.65 s. Code: src/client/Movement/Pose.lua:24 SLIDE_PITCH = -math.rad(78) ('head first'); src/shared/Movement/Assets.lua:19 Assets.SlidePose = 742637151 ('superman dive'); src/shared/Config.lua:37-38 SLIDE_DURATION 0.75, SLIDE_COOLDOWN 0.4. C and LeftControl both trigger the slide when grounded (Controller.lua:476-477). Ctrl presses during PlatformStanding were dropped.


---

**area**: Laser Tracer (briefs #13, #15)

**issue**: There is still a central pillar ('Hub' model), and the lasers are red (low) and cyan (high) instead of all red. Lasers do not move randomly: they are sweeps rotating around the hub plus straight slides, with a periodic 'REVERSE!'. One laser touch is a knockout: knockback 95-110 studs/s throws you off the 42-stud-radius disc. A solo player standing still lasted 4.9 s and 6.4 s.

**severity**: major

**evidence**: Live map: Hub.Column 13 x 6.6 at (0, 56.5, 0), Dome at y=63.5, Beacon (Neon) at y=67.6, LowRing red at y=51.6, HighRing cyan at y=54.6. Lasers (client): low BeamCore color (1, 0.22, 0.22) at y=51.6; high BeamCore (0.12, 0.86, 1) at y=54.6. Code: src/client/Minigames/LaserTracer/Motion.lua:35-38 COLORS; src/server/Minigames/LaserTracer/Arena.lua:171 buildHub; Director.lua:193/211 patterns 'sweep'/'slide', Director.lua:321 announce 'REVERSE!'; LaserTracer/init.lua:39 KNOCK_POWER=95. Results showed 'kaczucha_70 lasted 4.9s' and 'lasted 6.4s'.


---

**area**: Hole in the Wall (brief #21)

**issue**: The wall panels carry big text labels 'RUN!', 'JUMP!' and 'SLIDE!'. There are only three rectangular hole types, so walls feel samey.

**severity**: major

**evidence**: Live client: Workspace.HoleInTheWallVisuals.Wall2.Panel.SurfaceGui.TextLabel text 'JUMP!' (x4) and 'RUN!' (x2). Code: src/client/Minigames/HoleInTheWall/WallView.lua:24-26 labels; src/server/Minigames/HoleInTheWall/Patterns.lua HOLES = NORMAL (w7, 0-8), HIGH (w7, 4.5-10.5), LOW (w8, 0-3) only.


---

**area**: Spawn kill and harsh knockbacks

**issue**: After a respawn, the player is often hit within about 1 s. Dodgeball balls hit at 135-196 studs/s, and two hits stack. Every survival mode is decided by one touch, and a solo player loses in about 5 s doing nothing, with no counterplay window or invulnerability.

**severity**: major

**evidence**: Laser Tracer (NoEliminate=true): respawn at t=3.80, hit (PlatformStanding, hspd 110.8) at t=4.80, more hits at 6.33, 7.33, 9.65, 10.85, 11.87. Dodgeball: hspd 163.7 then 196.5 within 0.4 s (stacked). Spin: respawned and hit on the first frame after landing (server log: heights -27 -> 0.20 -> HIT). Code: Dodgeball/Tuning.lua:91 power = 135*(1+0.1*(i-1)); Spin/init.lua:49 HIT_POWER=140; HoleInTheWall/Patterns.lua:62 power 170-240. No spawn-protection attribute exists anywhere in src/server.


---

**area**: After-death flow (brief #17)

**issue**: No 'back to lobby' option. The spectate bar only shows SPECTATING / target name / STOP (or WATCH). With a single player every round ends with 'NOBODY SURVIVED!'. For KotH the result text is 'KACZUCHA_70 SCORED 0!'. Winners require 2 or more participants, so a solo player can never win a round.

**severity**: major

**evidence**: src/client/Spectate/init.client.lua:189-201 (texts 'SPECTATING', 'PAUSED', 'Nobody left...', button 'STOP'/'WATCH'). Observed End phase: GameState.ResultText 'KACZUCHA_70 SCORED 0!', WinnersCsv ''. src/server/Core/Results.lua:87-95.


---

**area**: Results screen UI

**issue**: The headline 'NOBODY SURVIVED!' is shown twice, once as the server's big announcement and once as the results card ribbon. The '+5 coins' toast covers the SPECTATING bar and its STOP button, and the 'Q / E' hint is tiny and grey.

**severity**: major

**evidence**: Capture during End: big red 'NOBODY SURVIVED!' at y≈190 plus a pink ribbon 'NOBODY SURVIVED!' at y≈360, 'kaczucha_70 lasted 4.9s', and an orange '+5 coins' pill over 'SPECTATING' / 'STOP'. Code: src/server/Core/Results.lua:111 Announce.big(audience, text, ...); src/client/UI/Results.lua:235 renders the same ResultText.


---

**area**: Default Roblox leaderboard overlap

**issue**: The CoreGui PlayerList (People / Streak / Wins / Coins) is enabled. It sits right under the custom Level/XP/Coins HUD, and the kill feed is drawn on top of it. Both are unreadable and look unpolished.

**severity**: major

**evidence**: Several captures show 'kaczucha_70 got knocked out! #1' over the 'People Streak Wins Coins' header at top right. Client: StarterGui:GetCoreGuiEnabled(PlayerList) = true.


---

**area**: Mid-round banners

**issue**: Event banners appear in huge letters in the middle of the screen during play, covering the area where the player is looking: 'REVERSE!' (LT) and 'GIANT BALLS!' with a subtitle (Dodgeball modifier).

**severity**: minor

**evidence**: Captures LT_controls_hud ('REVERSE!' roughly 760x150 px in the screen centre) and DB_after ('GIANT BALLS!' plus 'They plow through everyone in their way!' across the centre).


---

**area**: Shop window behaviour

**issue**: The shop can be opened during an active round and covers about 75% of the screen while you are playing. It also stays open over the Roulette. It only auto-closes at the countdown.

**severity**: major

**evidence**: Opened the shop during a KotH Round (timer pill and 'TOP 3' visible behind the window). Earlier the shop stayed open over 'PICKING A GAME...' and closed when the countdown '1' appeared.


---

**area**: Robux monetization (briefs #19, #28-31)

**issue**: Every Robux item shows 'COMING SOON' and no Robux price appears anywhere. These are all coin packs (500 / 1,500 / 5,000), instant upgrades, and the 2X COINS and VIP passes. There is no starter pack, limited trail with a fake old price, wheel spin, revive, daily or group chest, or countdown offer. The coin-pack tiles have a muddy brown backdrop, the 'BEST VALUE' ribbon is clipped at the right edge, and the 'Instant upgrades' row is cut off by the scroll frame.

**severity**: major

**evidence**: Captures SHOP_robux2 and SHOP_robux3. src/shared/Config.lua:58-70: PRODUCTS and GAMEPASSES ids are all 0.


---

**area**: Shop and picker art (brief #5, 'AI slop')

**issue**: Icons are mismatched emoji and flat vectors. Upgrades use ⚡, 💨, 🚀 and 💥. Cosmetic categories use 🌈, a bat emoji and 🎉, and VIP is a small crown emoji on yellow. The KotH 'BAT' is just the text BAT in an orange circle. The Solo picker's Hole in the Wall icon reads as an 'info i'. Upgrades are dry '+3% / -6%' stat bumps.

**severity**: major

**evidence**: Captures SHOP_2 (upgrades), SHOP_cos (cosmetics: 'TRAILS 0 / 8 OWNED' pink text on a pink tile has low contrast), SHOP_robux3, SHOP_1 (Solo picker) and KOTH_round.


---

**area**: Solo picker UI

**issue**: All five cards repeat 'YOUR BEST -- / WORLD #1 Be the first!'. The PLAY buttons hang half outside the card frames. There is a large empty band between the cards and the footer line. The panel has a lot of dead purple space.

**severity**: minor

**evidence**: Capture SHOP_1 (opened via the SOLO rail button): cards DODGEBALL / HOLE IN THE WALL / LASER TRACER / SPIN / RANDOM.


---

**area**: Lobby HUD and retention (briefs #8, #12, #19, #26-27, #32)

**issue**: The lobby screen is empty apart from the 'PARTY DASH' letters, a 'NEXT GAME IN 12' pill and two rail buttons (SHOP, SOLO). There is no daily reward or streak, wheel, group/like chest, quests, offers with timers, settings, music toggle or join zone. There is no background music (no looped non-character Sound exists), no loading screen, and no settings panel. src/shared/Audio.lua exists untracked but nothing requires it.

**severity**: major

**evidence**: Capture LOBBY_hud. Client scan: 116 Sounds, only 4 looped, all default character sounds. grep shows no Audio.setMusic callers. RoundLoop.pickParticipants drafts every non-solo player, with no join zone. Config.LOBBY_TIME = 15 (brief wants 20 s).


---

**area**: Map and lobby visuals (briefs #2, #4, #7)

**issue**: Every map uses smooth, untextured pastel geometry with no material or pattern. The lobby is a 128x128 floating platform 62 studs above the sea, the opposite of the reference's ground-level grass and dirt islands on bright water. Laser Tracer's floor is 162 rainbow wedge tiles in about 10 alternating colours. Lighting is tuned toward white glare, which matches the owner's washed-out KotH screenshot.

**severity**: major

**evidence**: Lobby: 502 parts, 495 SmoothPlastic + 6 Glass + 1 Foil, 26 distinct BrickColors (Persimmon 33, Pink 31, Pastel violet 28, Mint 20, ...), Institutional white 108. KotH: 274 SmoothPlastic + 37 Neon, Institutional white 113 of 311. Dodgeball: 336 SmoothPlastic + 20 Neon. Lighting (src/server/Core/LightingSetup.lua): Brightness 3, ExposureCompensation 0.1, OutdoorAmbient (165, 165, 185), Atmosphere Density 0.24 / Haze 0.6 / Color (205, 232, 255), Bloom 0.45, ColorCorrection Saturation 0.28. The 3D view could not be captured (see visualNotes), so this point rests on geometry dumps plus docs/reference/current-game-koth.jpg.


---

**area**: KotH HUD

**issue**: The 'TOP 3' panel is a large empty dark box on the right while nobody has scored. The timer format switches from '1:25' to '57'. The bottom chip 'CLIMB TO THE GOLDEN ZONE!' with a 'BAT' text icon stacks on top of the dash row.

**severity**: minor

**evidence**: Captures KOTH_round and KOTH_fall (the mode is being replaced by Bomb Tag, but the same HUD kit will be reused).


---

**area**: Movement HUD

**issue**: The 'SHIFT | DASH bar | C SLIDE' row is small (chip text about 12 px at 1730 px width) and sits at the bottom centre where toasts also appear. Survival modes show only 'HOLE IN THE WALL / 1 / 1 ALIVE', with no timer and no personal score or goal to chase. The 'Press SHIFT to DASH 1/3' tutorial bubble covers the bottom centre during countdown and GO.

**severity**: minor

**evidence**: Captures HW_round, LT_intro, LT_round1, KOTH_fall (toast overlapping the DASH row).


---

**area**: Client leaks

**issue**: Client containers from earlier minigames stay in the workspace during later rounds.

**severity**: minor

**evidence**: During Laser Tracer the client workspace still contained HoleInTheWallFx and PD_DodgeballClient (185 descendants per P5 notes).


---

**area**: Dash

**issue**: The dash itself works: a horizontal speed spike to 99.8 studs/s for about 0.25 s, a root pitch of -29 deg, then a 2.5 s cooldown bar. Dash presses during stun are dropped silently, with no 'not ready' feedback.

**severity**: minor

**evidence**: LT sampler: t=0.93 hspd 99.8, then 86.1 (Dashing=true), 48.4, 20.0 by t=1.25. Config.DASH_COOLDOWN 2.5, DASH_DISTANCE 18, DASH_DURATION 0.22.

**visualNotes**: I could not see the 3D world in this session. Every screen_capture showed only the GUI over a black 3D view, in Play (Client) and in Edit with camera_position/look_at. A ViewportFrame clone of the map also came out empty. macOS reports the frontmost process as 'loginwindow', so the Mac screen is locked and Studio stops drawing 3D; a mac screencapture of the window also failed ('could not create image from rect'). Map visuals are judged from geometry, colour and material dumps plus docs/reference/current-game-koth.jpg. The lead should get someone to re-shoot the maps with the screen unlocked.

Per screen (GUI only):
- LOBBY: the 'PARTY DASH' title in multicolour letters, the 'NEXT GAME IN 12' pill, a rail on the left with only SHOP and SOLO, the Level/XP and Coins pills at top right. The default Roblox PlayerList sits right under those pills. The rest of the screen is empty, with nothing to do or claim and no offers or timers, far from the busy reference HUDs (ref1/ref2). The lobby world is a floating 128x128 SmoothPlastic platform 62 studs above the sea, with 26 colours and 108 white parts. It has a 'HOW TO PLAY' board and a solo leaderboard board.
- ROULETTE 'PICKING A GAME...': the best screen. Tilted coloured cards over a dark sunburst. Its icons are emoji-style (crown, cyclone, barrier, lightning) that clash with the rest. The dash HUD shows faintly through the dim.
- INTRO card (LASER TRACER): pink header with a lightning-emoji circle, a rules line, SPACE/C/SHIFT key chips, and an orange 'LAST ONE STANDING WINS' pill. Readable, but generic.
- COUNTDOWN: a huge gradient '3' / '1' plus 'GET READY!' and '1 / 1 ALIVE'. The tutorial bubble 'Press SHIFT to DASH 1/3' covers the bottom centre.
- ROUND HUD (all modes): a navy mode-name pill plus a green 'X / Y ALIVE' pill. There is no timer or score in survival modes. Big centre banners ('REVERSE!', 'GIANT BALLS!') cover the play area mid-round. The bottom 'SHIFT | DASH | C SLIDE' row is tiny.
- KotH HUD: a timer pill; a 'TOP 3' empty black box on the right; 'BAT' text in an orange circle with 'CLIMB TO THE GOLDEN ZONE!'; the 'Oops! Back in 2...' toast collides with the dash row. The owner's screenshot shows the 3D look: white-washed glare on the right half, pastel pink and mint, lollipops, pale islands, all blending.
- RESULTS (End): 'NOBODY SURVIVED!' twice (a red headline and a pink ribbon), a dizzy-face emoji, 'NO WINNERS THIS TIME!', 'GOOD GAME, EVERYONE!', a 'LOBBY IN 1' button, and a '+5 coins' toast covering the SPECTATING / STOP bar.
- SHOP: an orange 'SHOP' header, coin and LEVEL pills, and three tabs (Upgrades / Cosmetics / Robux). Upgrades are four cards with emoji icons and dull '+0% -> -6%' stats. Cosmetics: trail previews as gradient sticks with a ghost face; low-contrast '0 / 8 OWNED'; the second row is cut off. Robux: every item 'COMING SOON', muddy brown coin tiles, the 'BEST VALUE' ribbon clipped, a VIP card made of a crown emoji on yellow. Overall it is a dark navy/purple panel style, not the bright chunky rainbow-header shop of ref3/ref5.
- SOLO PICKER: a purple panel with five cards (Dodgeball, Hole in the Wall with an 'info i' icon, Laser Tracer, Spin, Random). Each card repeats '-- / Be the first!', the PLAY buttons hang off the cards, and there is a big empty band at the bottom.
- SPECTATE bar: 'SPECTATING / Nobody left... / STOP' at the bottom centre. There is no 'Back to lobby' button.
- Maps from the data: Laser Tracer is a disc of 162 SmoothPlastic wedge tiles in about 10 alternating hues, plus a central hub pillar and dome. Dodgeball has 356 parts in 18 BrickColors, 'Institutional white' 98 and 'Black metallic' 60. Hole in the Wall is a 64x64 platform with pastel walls carrying text labels. Spin has slate pillars with neon bands, a non-collidable CrackedLava disc at y≈25, and a black DiamondPlate hub. KotH has 311 parts, 113 of them white, plus pastels. Nothing uses textured materials (Brick, Grass, Ground, Sand) or checker patterns like ref1, ref2 and ref4.


## consoleErrors

- No game-script errors or warnings from Party Dash code in about 25 minutes of play (about 15 rounds across all 5 minigames, KotH twice).
- Info at boot: [Economy] DataStores unavailable (You must publish this place to the web to access DataStore.). Using in-memory profiles.
- Info at boot: [Solo] This place is not published: Solo records are kept in memory for this server only.
- Info: [Core] registry: 6 minigame(s) [Dodgeball, HoleInTheWall, KingOfTheHill, LaserTracer, Spin, _Sandbox], 6 modifier(s) [Fog, Giant, LowGravity, Slippery, Tiny, Turbo]
- Only other entries came from my own test commands: reading Lighting.Technology is not allowed, and 'VirtualInput::SendMousePosition hits CoreGUI' from the test mouse driver.
**waterBugRepro**: Setup: sync OK (147 scripts), Debug_FastIntermission=true, Debug_NoEliminate=false, Debug_ForceModifier="". Sea = terrain Water at y=-12 (World.SEA_LEVEL = ARENA_CENTER.Y-62). A raycast under every 'outside' point hit Terrain Water @ y=-12.
(a) Teleport about 40 studs off the edge at y=53 (Server: HumanoidRootPart.CFrame):
- LaserTracer at (82, 53, 0): the round was in Intro, so I stayed frozen there (Anchored) until Round. Then y=49 at +0.4 s, and at +0.5 s InRound=false, Spectating=true, teleported to the stands (-12, 101, -124). Phase End, then Lobby.
- Dodgeball at (78, 53, 0): y=49 at 0.4 s; at 0.8 s InRound=false, Spectating=true, teleported to the stands (-1, 101, -123).
- HoleInTheWall at (72, 53, 0): identical, eliminated at 0.8 s, stands (-1, 98, -111).
- Spin at (81, 53, 0): eliminated at 0.8 s (KillY 26), stands (17, 99, -117).
- KingOfTheHill at (83, 53, 0): NOT eliminated. At 0.8 s the root was Anchored at (83, 24, 0) in Freefall, hanging in mid-air 36 studs above the water for about 2.1 s with the toast 'Oops! Back in 2...'. At 2.9 s I was teleported back to a spawn (-11, 54, 38), and InRound stayed true for the rest of the round.
(b) Knockback.apply(player, outwardDir, 200, 0.6):
- LT, Dodgeball, HITW and Spin: PlatformStanding flight about 200 studs outward, crossing KillY at about 1.0-1.3 s. Then InRound=false, Spectating=true, instant teleport to the stands, and the round ended (End, then Lobby about 2 s later).
- KotH: flew to (-52, 50, 190), fell, froze, toast 'Oops! Back in 2...', and was teleported back to a spawn.
Conclusion: the owner's 'fell in the water and got teleported back instead of dying' reproduces 100% in King of the Hill. Cause: the score-kind respawn in src/server/Core/Context.lua:295-306 (_onFall: setAnchored true, toast, task.delay(2, _respawnNow)).
In the survival modes the player never reaches the water: KillY (center-30 = 20, Spin 26) is 32+ studs above the sea. Elimination is an instant teleport to the spectator stands (RoundLoop.lua:272 Places.sendToStands) with no splash, ragdoll or death beat, which also reads as 'teleported back'.
Related: Places.rescueLoop (Places.lua:90-111) silently teleports anyone below RESCUE_Y=20 outside a running round (Intro, End, Lobby) back to the stands or lobby.
Related exploit: on Spin a player standing on the pillar 'Foot' ledge (root y=29 > KillY 26) is never eliminated.
Studio was left in Edit mode with workspace.Debug_ForceMinigame="".
