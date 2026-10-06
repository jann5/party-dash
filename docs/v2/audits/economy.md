# Audit: economy

**subsystem**: Economy, persistence, shop, Robux (src/server/Economy/*, src/shared/Economy/*, src/client/Shop/*, Config.PRODUCTS/GAMEPASSES)

**howItWorks**: BOOT: src/server/Economy/init.lua is a ModuleScript. Its child Script Boot.server.lua calls Economy.start() (init.lua:207), which does the following: task.spawn(Store.init), Remotes.start(), Market.start(), Visuals.start(), sets MarketplaceService.ProcessReceipt = Economy.processReceipt (init.lua:218), connects Signals.RoundFinished/SoloFinished -> Rewards.*, runs Sessions.load and Market.refreshPasses on PlayerAdded, Sessions.unload on PlayerRemoving, saveAll(true) in BindToClose (25s deadline), and an autosave loop every Sessions.AUTOSAVE=60s that also calls checkDaily (init.lua:239-250). It also creates a BindableFunction "EconomyApi" so another VM (the command bar) can forward calls.
STORE (Store.lua): DataStore "PartyDash_Profiles_v1", key "u_<userId>". Store.init probes GetAsync("__probe"). In Studio, if that fails, it falls back to an in-memory JSON table. Store.update(key, transform) wraps UpdateAsync: 4 attempts, 1/2/4s backoff, waits up to 10s for UpdateAsync budget. Returning nil from the transform cancels the write.
PROFILE (Profile.lua, VERSION=1): fields coins, wins, xp, level, upgrades{name->0..5}, ownedCosmetics (stored as an array, held as a set), equipped{slot->id}, lastDaily (UTC day), seenTutorial, receipts (last Rules.MAX_RECEIPTS=50 PurchaseIds), stats{rounds, coinsEarned}. reconcile() builds a fresh default and copies only known fields and catalog-known cosmetic ids. serialize() writes only known fields.
SESSIONS (Sessions.lua): one Session per Player instance: {data, loaded, persistent, lost, saving, closing, pendingReceipts, passes}. tryAcquire (145-171) puts lock={jobId,time} inside the record and refuses if another job's lock is younger than LOCK_STALE=300s. load() retries with 2/4/8/15s delays: "locked" shows a toast and keeps retrying; after 3 "error" attempts it uses a temporary non-persistent profile. write() (174-205) refuses if the lock belongs to another job (sets s.lost), refreshes or releases the lock, and on success clears ALL pendingReceipts. save() serializes per session through s.saving. saveSoon() debounces by 6s.
Mutators (all mirror to Player attributes and leaderstats right away): addCoins, addXP (level-up toast; XP needed = 50+25n), setUpgrade, grantCosmetic, equip, setPass, checkDaily (auto-grants Config.DAILY_REWARD=50 once per UTC day, toast only, no UI). Attributes: Coins, Level, XP, XPNext, Upg_*, Cos_*, Owned_Cosmetics (CSV), Pass_DoubleCoins/Pass_VIP, EconomyLoaded, Seen_Tutorial. leaderstats.Coins is added; saved Wins are merged into Core's leaderstats.Wins.
REWARDS (Rewards.lua): on RoundFinished every participant gets Rules.roundCoins(survived, winner, modifierRound, DoubleCoins) = 5 + 1 per 10s survived (+25 for a win), x2 on a modifier round, x2 with the pass. The same number is added as XP, plus a toast. Winners also get their equipped WinEffect (Visuals.winEffect). On SoloFinished: Rules.soloCoins = 2 per 10s, uncapped.
REMOTES (Remotes.lua, names in Rules.Remote): Economy_BuyUpgrade(name), Economy_BuyCosmetic(id), Economy_Equip(id | slot,id). A shared token bucket allows 10 burst at 4/s. Every request is answered on Economy_Result(ok, action, id, message). There are no yields between check and mutation, so these are atomic.
MARKET (Market.lua): processReceipt(receipt, keyHint) checks the player is online, loaded, persistent and not lost, otherwise returns NotProcessedYet. If receipts already holds the PurchaseId, it re-saves when that receipt is still pending, else returns PurchaseGranted. Otherwise it resolves the key with Rules.productKey (a linear scan of Config.PRODUCTS; id 0 never matches), runs grant(player,key) (coin packs from Rules.COIN_PACKS; Upgrade<Name> buys +1 level, or refunds the top price in coins if already maxed), then addReceipt, pendingReceipts, toast, and a synchronous Sessions.save. It returns PurchaseGranted only if that save succeeded. Gamepasses: UserOwnsGamePassAsync once per join, plus PromptGamePassPurchaseFinished. VIP auto-equips TrailVIP.
VISUALS (Visuals.lua): server-built BillboardGui "PlayerTag" (name, Lv pill, VIP pill), Trail "CosmeticTrail" on the HRP driven by Cos_Trail, win effects in workspace.EconomyFx.
SHARED: Rules.lua holds remote/attribute names, UPGRADE_INFO (emoji icons), COIN_PACKS, PASS_INFO, pricing math and productKey. Cosmetics.lua holds the catalog: 8 trails including the VIP one, 7 dash colors, 7 bat colors, 3 win effects, with coin prices. Slots: Trail, DashColor, BatColor, WinEffect.
CLIENT (src/client/Shop): init.client.lua builds Window "EconomyShop" (DisplayOrder 12, authored at 1000x600 and fitted with a UIScale) with three tabs, each built inside a pcall: UpgradesTab (4 cards), CosmeticsTab (slot list plus grids), RobuxTab (coin packs, instant upgrades, passes; id 0 shows "COMING SOON" with an error sound and a shake; prices are fetched lazily via GetProductInfo). Hud.lua: "EconomyHUD" (DisplayOrder 14) top-right coin pill (coins fly in, "+" opens Robux) and level bar. MenuButton.lua docks the SHOP button into PartyHUD.MenuRail at LayoutOrder 10. State.lua reads the mirrored attributes and pairs requests with Economy_Result through an action:id key and a 4s timeout. Sfx.lua uses rbxasset sounds. Ui.lua is the economy's own UI kit (a third kit next to UI/Kit.lua and Solo/Ui.lua).
Outside consumers: Movement reads Upg_DashCooldown/DashDistance/JumpBoost and Cos_DashColor. KotH reads Upg_BatPower (KingOfTheHill/init.lua:80) and Cos_BatColor (BatTool.parseColor, BatTool.lua:48).


## bugs


---

**title**: Profile drops unknown cosmetic ids and unknown fields: Robux-bought items are wiped during rolling updates or catalog edits

**severity**: major

**file**: src/server/Economy/Profile.lua

**line**: 89

**rootCause**: reconcile() keeps an owned id only if Cosmetics.get(id) knows it (lines 89-97), and builds the result from Profile.default(), copying only the known keys (70-125). serialize() (128-148) writes only those keys, and write() saves the snapshot as the whole record. If a newer server grants 'TrailLimitedX' (#31), 'TrailStarter' (#30), or new v2 fields (spins, reviveTokens, daily streak), an older server still running during a Roblox rolling update loads the profile without them and saves it back, permanently deleting paid items and counters. The same happens if a catalog id is ever renamed or removed.

**fix**: Keep unknown data. In reconcile, put every string id (#id<=40) that the catalog does not know into data.ownedUnknown (an array). In serialize, write the union of owned and ownedUnknown. Carry unknown top-level keys: data._extra = {k=v for raw keys not in the schema}, merged back in serialize. Bump Profile.VERSION to 2 and never let an older VERSION lower a newer record's version (write max(raw.version, VERSION)). Do this BEFORE shipping any Robux-only cosmetic.

**evidence**: Profile.lua:92-95 `local item = Cosmetics.get(id) if item and not item.vip then data.ownedCosmetics[item.id] = true end`; Sessions.lua:179-190 writes `table.clone(snapshot)` as the full record.


---

**title**: pendingReceipts is cleared by an unrelated save, so a later retry acknowledges a purchase that never reached disk

**severity**: major

**file**: src/server/Economy/Sessions.lua

**line**: 201

**rootCause**: write() takes its snapshot before UpdateAsync yields, then on success runs table.clear(s.pendingReceipts) for every receipt, including receipts granted while that save was in flight and therefore missing from its snapshot. Sequence: an autosave starts (snapshot without receipt R). processReceipt(R) grants, sets pendingReceipts[R], and waits on s.saving. The autosave succeeds and clears R. The receipt's own save then fails (outage) and returns NotProcessedYet. Roblox retries in the same server: Market.lua:66-72 sees hasReceipt(R) with pendingReceipts[R] nil and returns PurchaseGranted, although R was never persisted. A crash or shutdown with saves still failing loses a paid purchase.

**fix**: In write(), copy the pending set before the update (`local confirming = table.clone(s.pendingReceipts)`, inside the snapshot step) and on success remove only those keys. Optionally have processReceipt verify persistence with a per-receipt saved flag instead of an in-memory set.

**evidence**: Sessions.lua:179 `local snapshot = Profile.serialize(s.data)` ... 201-203 `if ok then table.clear(s.pendingReceipts) end`; Market.lua:66-72.


---

**title**: Phone layout: the whole shop scales to ~0.47, giving 19-31px touch targets and ~8px text

**severity**: major

**file**: src/client/Shop/Window.lua

**line**: 296

**rootCause**: refit() uses min(size.X*0.95/(W+50), size.Y*0.9/(H+90), 1.25) with W,H=1000,600. On an 800x360 landscape phone (IgnoreGuiInset) that is min(0.72, 0.47) = 0.47, so the Close button (66px design) becomes 31px, tabs (62px) 29px, cosmetic Action buttons (40px) 19px, and labels with max 17-18 (blurbs, 'Next', counts) render at ~8px. That fails 'iPad kid' readability and Roblox's 44px touch guideline.

**fix**: Below 500px of screen height, use a compact layout: drop the +90/+50 overhang allowance (move the toast inside the window), fill 98% of the height (scale ~0.59), hide the balance and level chips (the HUD already shows them), and raise every MaxTextSize below 22 to at least 22 design px. Better, author the shop at about 860x430 design px with side tabs as in ref5, so phones get scale >= 0.8. Add a UISizeConstraint so buttons never go below 44px absolute.

**evidence**: Window.lua:19 `local W, H = 1000, 600`; :296 `fit.Scale = math.min(size.X * 0.95 / (W + 50), size.Y * 0.9 / (H + 90), 1.25)`.


---

**title**: BEST VALUE ribbon clipped at the scroll edge and under the scrollbar

**severity**: minor

**file**: src/client/Shop/RobuxTab.lua

**line**: 195

**rootCause**: The ribbon is anchored (1,0.5) at x = PACK_W + 6, so it sticks 6px past the card's right edge, plus ~1px from the 6-degree rotation and 2.5px of Border stroke. Coins5000 is the last card in a ROW_W=940 row placed at x=4 (UIPadding left 4) inside a 952px-wide ScrollingFrame, which clips at 952. The 8px vertical scrollbar (ScrollBarThickness 8, default VerticalScrollBarInset None) is always visible because the content is ~676px against a 404px viewport, and it draws over x 944-952. The ribbon's right ~8-10px therefore sit under the scrollbar and the clip edge.

**fix**: Keep the ribbon inside the card: AnchorPoint (1,0), Position UDim2.fromOffset(PACK_W - 10, -12), Rotation 4. Set scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always, ROW_W = Window.CONTENT.X - 24 (=928), UIPadding PaddingTop 16 so ribbons poking above a card are not clipped at the top of the scroll.

**evidence**: RobuxTab.lua:19 ROW_W=940; :136 ScrollBarThickness=8; :144-149 PaddingLeft 4; :195-202 `AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(PACK_W + 6, 6), Size = UDim2.fromOffset(118, 28), Rotation = 6`; Window.lua:22 CONTENT 952x404.


---

**title**: Muddy brown coin-pack icon tiles

**severity**: minor

**file**: src/client/Shop/RobuxTab.lua

**line**: 178

**rootCause**: The 'Pile' tile is a Ui.TILE panel with Ui.gradient(glow, Color3.fromRGB(90,75,40), Ui.TILE): an olive-brown to dark-purple gradient behind gold coins. That is low contrast and reads as mud.

**fix**: Replace it with a bright backdrop: gradient from Ui.lighten(C.Yellow,0.55) to C.Orange, or light sky to cyan, plus a white sunburst ImageLabel behind. Better still, a generated coin-pile image per pack size (small, medium, big) from the new Assets registry on a light radial tile, as in ref3/ref5.

**evidence**: RobuxTab.lua:172-178 `local glow = Ui.panel(card, Ui.TILE, {...}) Ui.gradient(glow, Color3.fromRGB(90, 75, 40), Ui.TILE)`.


---

**title**: Products are untestable and the whole ROBUX tab is dead while ids are 0 (no Studio path)

**severity**: minor

**file**: src/client/Shop/RobuxTab.lua

**line**: 84

**rootCause**: Every Config.PRODUCTS/GAMEPASSES id is 0 (Config.lua:58-71). robuxButton mode 'soon' only plays an error sound and shakes, and Rules.productKey refuses id 0. There is no way to exercise grant code, receipts or new features (#27-#31) in Studio, and the tab shows 10 'COMING SOON' buttons.

**fix**: Add the Studio-only DevShop path described in briefPlans: a remote that exists only under RunService:IsStudio(), funneled through the same processReceipt code using a synthetic PurchaseId, plus a client Purchase.product(key) helper that shows the display price with a TEST tag.

**evidence**: RobuxTab.lua:84-90, 216-222; Rules.lua:122-132 (`productId == 0 -> nil`); Market.lua:75 keyHint is limited to coin packs and upgrades.


---

**title**: Autosave loop iterates the live sessions table while yielding; inserts are undefined and the loop has no pcall

**severity**: minor

**file**: src/server/Economy/init.lua

**line**: 242

**rootCause**: `for player in Sessions.all()` iterates the live `sessions` table (Sessions.all returns the table itself, Sessions.lua:60-62) and calls task.wait(0.2) per player. Meanwhile Sessions.load inserts new keys (Sessions.lua:445). Inserting during next() traversal is undefined in Luau: entries can be skipped, or traversal can error. Nothing is wrapped in pcall, so one error kills autosave and lock refresh for the rest of the server's life, and a crash then loses everything since each player joined.

**fix**: Snapshot the keys first (`local list = {} for p in Sessions.all() do table.insert(list, p) end`), iterate the list, and wrap each player's body in pcall/task.spawn.

**evidence**: init.lua:239-250.


---

**title**: Same-server rejoin can load a stale profile, and the old session's release then removes the live lock

**severity**: minor

**file**: src/server/Economy/Sessions.lua

**line**: 152

**rootCause**: Sessions are keyed by Player instance, and tryAcquire treats a lock with the same JOB_ID as its own. If a player rejoins the SAME server (private server or Rejoin) while the old session's release save is still in flight (throttling or retries can stretch that to several seconds), the new session acquires immediately and reads data from before the final save. The old write() then commits its snapshot WITHOUT a lock (release=true) while the new session is live. The new session's next save overwrites the old session's last delta (round coins, saveSoon purchases).

**fix**: Keep `unloading[userId] = true` for the whole of unload(), and in load() wait (`while unloading[player.UserId] do task.wait(0.1) end`) before calling tryAcquire.

**evidence**: Sessions.lua:150-160 (only `lock.jobId ~= JOB_ID` is refused); :428-445 (new session per Player); :488-512 (unload).


---

**title**: Product grant mutates data before the receipt is recorded and is not protected; a throwing handler causes a double grant on retry

**severity**: minor

**file**: src/server/Economy/Market.lua

**line**: 83

**rootCause**: grant(player,key) mutates s.data (for example addCoins), and only afterwards does processReceipt call addReceipt. If a handler errors halfway (likely once more complex handlers arrive: starter pack with several items, revive calling Core), the ProcessReceipt callback errors, Roblox retries, and the partial grant is applied again.

**fix**: Run each handler in pcall on a deep copy (or snapshot coins, spins and owned items and restore on error). Record the receipt in the same synchronous block. Handlers must not yield: anything that yields, such as a Core revive, is deferred with task.defer after the receipt is saved.

**evidence**: Market.lua:83-88.


---

**title**: Latent: any Robux-only cosmetic added to the catalog can be bought for coins (price 0)

**severity**: minor

**file**: src/server/Economy/Remotes.lua

**line**: 88

**rootCause**: buyCosmetic blocks only item.vip and otherwise checks coins >= item.price. The VIP pattern uses price 0. A builder adding 'TrailStarter' or a limited trail with price 0 and a new flag (robuxOnly/product) gets it bought for free through Economy_BuyCosmetic. Profile.reconcile (line 93) and grantCosmetic (Sessions.lua:296) also special-case only vip.

**fix**: Add an Item field `source: "coins"|"vip"|"robux"|"reward"`. buyCosmetic rejects anything that is not 'coins' with 'Get it in the FEATURED tab!'. grantCosmetic accepts robux and reward items. ownedCsv and the UI show non-coin items as locked with their source.

**evidence**: Remotes.lua:88-98; Cosmetics.lua:16-26 (no source field).


---

**title**: Removing King of the Hill breaks the COSMETICS tab and strands BatPower/BatColor purchases

**severity**: minor

**file**: src/client/Shop/CosmeticsTab.lua

**line**: 108

**rootCause**: The default bat preview colour is Theme.MinigameColors.KingOfTheHill. If Theme drops that key for Bomb Tag (#10), Ui.panel gets a nil colour, BackgroundColor3=nil throws, and init.client.lua:46-48 catches the error, leaving an empty Cosmetics tab. In addition, Upg_BatPower is read only by KingOfTheHill/init.lua:80 and Cos_BatColor only by KingOfTheHill/BatTool.lua:48/124, so after the swap the upgrades and bat skins players paid for do nothing.

**fix**: Use a literal colour (e.g. C.Orange) in CosmeticsTab:108. Move BatTool.parseColor into a shared module (src/shared/Economy/BatColor.lua) so the new Spin bat (#22) reads Cos_BatColor and Upg_BatPower. Rename the upgrade's display to 'BONK POWER' and have Bomb Tag's tag-shove knockback scale with it too. Keep the attribute and key name BatPower for data compatibility.

**evidence**: CosmeticsTab.lua:108 `local color = if item then item.color else Theme.MinigameColors.KingOfTheHill`; Cosmetics.lua:7,89.


---

**title**: Coin farming: Solo coins uncapped, AFK players auto-join every round

**severity**: minor

**file**: src/shared/Economy/Rules.lua

**line**: 113

**rootCause**: soloCoins = floor(seconds/10)*2 with no cap, and Solo ignores Context's safety fuse (P10 note 5). Any safe-spot exploit (the Spin wall ledge from #22) farms coins without limit. In the main loop, RoundLoop.eligible/pickParticipants (RoundLoop.lua:69-98) puts every idle player into every round, and Rewards pays COINS_PARTICIPATE plus survival coins to AFK players.

**fix**: Cap Solo at min(seconds,180) and pay nothing under 10s. Pay main-round rewards only to players who entered the join zone (#26), which Core already handles once participants come from the zone. Optionally add a daily soft cap on solo coins.

**evidence**: Rules.lua:113-119; Rewards.lua:100-106; RoundLoop.lua:69-98.


---

**title**: Studio with API access writes test data into the production profile store

**severity**: minor

**file**: src/server/Economy/Store.lua

**line**: 11

**rootCause**: Store.NAME is 'PartyDash_Profiles_v1' everywhere. With Studio API access enabled, the probe succeeds and mode becomes 'datastore', so every Studio session, including the planned dev purchase grants, writes to the live players' store under the tester's userId.

**fix**: `Store.NAME = if RunService:IsStudio() then "PartyDash_Profiles_Studio_v1" else "PartyDash_Profiles_v1"`, and refuse DevShop grants unless the Studio store is used.

**evidence**: Store.lua:11, 47-73.


---

**title**: Temporary (non-persistent) profile is invisible to the client: Robux purchases silently do nothing

**severity**: minor

**file**: src/server/Economy/Market.lua

**line**: 62

**rootCause**: After 3 store errors, Sessions.load sets persistent=false (Sessions.lua:464-475). processReceipt then returns NotProcessedYet (correct, nothing is lost), but the client still shows active buy buttons. The player pays, sees no coins, and gets them only in a later session. No attribute exposes the state.

**fix**: Mirror an EconomyPersistent attribute (bool). RobuxTab and Featured disable buy buttons with 'Save offline - try again soon' while it is false.

**evidence**: Market.lua:62-64; Sessions.lua:464-475.


---

**title**: Emoji glyphs used as icons (rendered by the system emoji font)

**severity**: minor

**file**: src/shared/Economy/Rules.lua

**line**: 30

**rootCause**: The upgrade icons (⚡💨🚀💥), slot icons (🌈💨🏏🎉 at CosmeticsTab.lua:21-22), win FX icons (Cosmetics.lua:99-101) and the VIP crown (RobuxTab.lua:320) are emoji in Fredoka TextLabels. They render in platform-dependent styles or as tofu (console), don't match the cartoon outline style, and add to the 'AI slop' look the owner complained about (#5, #7).

**fix**: Replace with ImageLabels from a new src/shared/Assets.lua registry (generated icons, see briefPlans #5/#20). Keep the drawn-shape fallback while an asset id is "".

**evidence**: Rules.lua:30-33; CosmeticsTab.lua:21-22; RobuxTab.lua:318-326.


## briefPlans


---

**briefItem**: #27 DAILY CHEST with streak (claim every day)

**currentState**: Sessions.checkDaily (Sessions.lua:334-352) auto-grants Config.DAILY_REWARD=50 on join through Sessions.Loaded (init.lua:220-222) and the autosave loop. Feedback is a toast only. There is no chest, no claim button, no streak and no countdown, so it gives no reason to come back.

**plan**: DATA (Profile v2): daily = { day: number (UTC day of the last claim), streak: number }. Migration in reconcile: if raw.daily is missing, set day = raw.lastDaily, streak = (raw.lastDaily>0) and 1 or 0. Keep lastDaily serialized for old servers.
SHARED src/shared/Economy/Daily.lua: STREAK = 7-day calendar { {coins=50}, {coins=75}, {coins=100,spins=1}, {coins=150}, {coins=200,revives=1}, {coins=300}, {coins=500,spins=2,item='TrailStreak' (first time only, otherwise +500 coins)} }. dayIndex(streak) = ((streak-1)%7)+1. nextClaimAt(day) = (day+1)*86400.
SERVER src/server/Economy/Daily.lua: claimDaily(player). Requires a loaded session. today = Rules.utcDay(). If d.day == today, return {ok=false, reason='claimed', nextAt}. Otherwise streak = (d.day == today-1) and d.streak+1 or 1, apply the bundle via Rewards.applyBundle(player, Daily.STREAK[idx], 'daily'), set d.day = today and d.streak = streak, mirror, then saveSoon. Everything runs synchronously, with no yield between the check and the mutation, so spam cannot double-claim. Delete the auto-grant: Sessions.checkDaily, the Loaded hook in init.lua:220-222 and the checkDaily call in the autosave loop.
REMOTE: Net.func('Economy_Claim') (kind:'daily'|'group'|'playtime'|'vip', arg:any) -> {ok, reason?, message, reward={coins,spins,revives,boostSeconds,items}, streak?, nextAt?}. Shares Remotes.allow; per-player busy flag.
ATTRIBUTES: DailyDay, DailyStreak (the client derives ready from Rules.utcDay(workspace:GetServerTimeNow()) ~= DailyDay).
CLIENT src/client/Rewards/DailyChest.lua: a 'DAILY' square icon button in MenuRail (LayoutOrder 30) with a red '!' badge when ready and an 'hh:mm:ss' countdown when not. Popup: a 7-day calendar row of chest tiles (claimed ticks, today glowing, day 7 big golden chest), a CLAIM button, then a chest-open animation (shake, lid pop, burst, items fly to the HUD). Auto-open once per session when ready, after the loading screen (wait for LocalPlayer attribute ClientReady, set by #24). Hold Hud coin fly-in until the chest reveal (see Wheel: State.holdCoinFx).

**risks**: UTC rollover is ~1-2am for Polish players, which is fine. The client must use workspace:GetServerTimeNow(), not os.time(), for countdowns. Streak resets after one missed day; a 'streak saver' product could come later.


---

**briefItem**: #27 GROUP CHEST (join group + like the game -> extra chest)

**currentState**: Nothing exists. There is no Config.GROUP_ID and no group or like logic anywhere (grep for IsInGroup returns nothing).

**plan**: CONFIG: add Config.GROUP_ID = 0 (the owner fills it in). DATA: groupDay: number (UTC day of the last group chest claim): an extra daily chest for group members, matching the Polish 'codziennie... dodatkowa skrzynke'. SHARED Daily.GROUP = {coins=100, spins=1}.
SERVER Daily.claimGroup(player): if Config.GROUP_ID == 0, return {ok=false, reason='disabled'}. If groupDay == today, return 'claimed'+nextAt. Membership is checked FRESH with pcall(GroupService.GetGroupsAsync, GroupService, player.UserId), looking for the id (Player:IsInGroup is cached server-side and misses joins made mid-session); on error fall back to player:IsInGroup(Config.GROUP_ID). This yields, so re-check groupDay ~= today after the yield before mutating. If not a member, return {ok=false, reason='notMember'}. Otherwise applyBundle, set groupDay, saveSoon.
LIKE: cannot be verified (no API). The UI only asks: 'Join the group & like the game!'. The reward is gated on group membership alone.
CLIENT: a world prop in the lobby, a golden chest with BillboardGui 'GROUP CHEST / Join the group & like the game!' like ref1/ref3. The Lobby map owner adds a 'GroupChestAnchor' part to Lobby.build; Economy client watches workspace.Lobby and adds a ProximityPrompt (the lobby is rebuilt every round: Places.buildLobby/destroyLobby). Add a matching icon in the right RewardRail. When the claim returns notMember, show a panel with 'JOIN GROUP' that calls pcall(GroupService.PromptJoinAsync, GroupService, Config.GROUP_ID) if that API is available, otherwise text instructions, plus 'I joined! Claim' to retry. Studio: workspace attribute Debug_FakeGroupMember=true bypasses the check under RunService:IsStudio() only.

**risks**: Roblox policy disallows incentivizing likes/favorites; keep the reward tied to group membership and phrase the like as a request ('and leave a like!'). GetGroupsAsync is a web call: rate-limit it to one per 10s per player.


---

**briefItem**: #28 REVIVE for Robux (respawn back into the round)

**currentState**: There is no revive. Context:_eliminate (Context.lua:314-336) is final: _alive=nil, a placement is assigned and onEliminated runs. RoundLoop's onEliminated (RoundLoop.lua:258-280) sets InRound=false and Spectating=true and sends the player to the stands. No Core API can put a player back.

**plan**: CORE HOOK (Core builder, contract change): Context:_revive(p): boolean. It returns false unless self._running and not self._stopped and not self._over and self._participant[p] and not self._alive[p] and p.Parent==Players and self._kind=='survival'. Otherwise: self._alive[p]=true, self._alivePlayers+=1, self._placements[p]=nil, self._survived[p]=nil, self._shieldUntil[p]=os.clock()+2.5 (_eliminate ignores any reason except 'left' during the shield, and a fall during the shield respawns instead), self:_respawnNow(p) (CharacterAdded already places a dead character via _onCharacter), pcall the optional session:onRevive(p) (a new optional method in Contracts/Minigame.lua, so Bomb Tag, Dodgeball and others can reset per-player state), then fire params.onRevived(p). RoundLoop passes onRevived: InRound=true, Spectating=false, GameState.write('Alive', ctx:_aliveCount()), Announce.feed(audience, '<name> is BACK!'), plus a ForceField-like sparkle for 2.5s. New module src/server/Core/Revive.lua: Revive.status(player) -> 'ok'|'noRound'|'over'|'notParticipant'|'alive'|'solo'|'score' and Revive.revive(player) -> boolean, both operating on State.ctx.
DATA: reviveTokens: number (purchases, wheel, daily, playtime and starter all add tokens). PRODUCT key Config.PRODUCTS.Revive (suggest R$ 19-25).
SERVER src/server/Economy/Revive.lua: on Signals.PlayerEliminated (fires with info.minigameId; it is a main-round signal), if Revive.status(p)=='ok', ctx:_aliveCount()>=2 (otherwise the round ends anyway: lastStanding, Context.lua:357) and usedThisRound[p] < 1, store offers[p]={round=GameState RoundNumber, until=os.clock()+25} and FireClient Economy_ReviveOffer(expiresAtServerTime = GetServerTimeNow()+8, tokens). Remote Economy_UseRevive (RemoteEvent, no args): validate the offer is live and the same round, tokens>0 and status ok, then synchronously reviveTokens-=1, then call Revive.revive(p). If it returns false, refund the token. Increment usedThisRound and reply on Economy_Result('revive'). Products registry handler 'Revive': reviveTokens+=1 (pure counter, idempotent via receipts), then after the receipt save task.defer(autoUse, player): if an offer is live, consume and revive; otherwise toast 'Revive saved for next time!'. Clear offers on Signals.RoundFinished.
CLIENT src/client/Shop/RevivePopup.lua (own ScreenGui 'EconomyRevive', DisplayOrder 11, above PartyOverlay 10 and below the shop at 12): appears with the server offer as a center-bottom card above the spectate bar: heart/angel icon, 'REVIVE!' and a ring countdown of 8s (ring, not a bar). The button reads 'USE REVIVE (x2)' when ReviveTokens>0, otherwise the Robux price through Purchase.product('Revive'). It hides when the Spectating attribute goes false, on timeout, or when the Phase becomes End. It must coexist with #17's SPECTATE / LOBBY buttons (UI subsystem); agree on positions: the revive card at y=0.62, the out-panel buttons at the bottom.

**risks**: Pay-to-win perception: limit to 1 per round per player. With 2 players the round ends instantly on elimination, so revive is only offered in rounds that started with 3 or more. Receipt latency of 1-5s is handled by the 25s server grace and token fallback. #17 'back to lobby during a round' conflicts with the lobby being destroyed during rounds (LOBBY_CENTER == ARENA_CENTER, RoundLoop.lua:296), which is Core's issue.


---

**briefItem**: #29 WHEEL OF FORTUNE (9 Robux per spin, free daily spin)

**currentState**: Nothing exists.

**plan**: SHARED src/shared/Economy/Wheel.lua: SEGMENTS (8, drawn clockwise from the top, each {id,label,color,weight,reward}): Coins50 w28 {coins=50}; Coins100 w22 {coins=100}; Boost w14 {boostSeconds=900, label='2X 15m'}; Coins250 w13 {coins=250}; Spin w9 {spins=1}; Revive w9 {revives=1}; Coins750 w4 {coins=750}; Mythic w1 {item='TrailFortune', dupCoins=1500}. odds(i)=weight/sum, shown in the UI ('Chances' button like ref3).
DATA: spins: number (tokens), freeSpinDay: number. PRODUCTS: WheelSpin1 (R$ 9) -> spins+=1; WheelSpin10 (R$ 79, 'x10 +2 BONUS') -> spins+=12.
SERVER src/server/Economy/Wheel.lua: Net.func('Economy_Spin')() -> {ok, reason?, index, segmentId, reward, spinsLeft, usedFree}. Validation: loaded session, Remotes.allow bucket, spinning[player] lock (released after 4.5s, the animation length). Spend the free spin first (freeSpinDay ~= today, then set it to today), otherwise spins>0 then spins-=1, otherwise return reason='noSpins'. Roll with a module-level Random.new(), weighted. Apply the reward immediately through Rewards.applyBundle (so leaving mid-animation loses nothing; duplicate mythic -> dupCoins). Mirror Spins and FreeSpinDay, saveSoon. All before returning, with no yields.
POLICY: on join, pcall(PolicyService.GetPolicyInfoForPlayerAsync) and mirror PaidRandomRestricted = info.ArePaidRandomItemsRestricted. The UI hides the Robux spin buttons for those players (free spins stay). Always show odds before purchase (Roblox paid-random-item rule).
CLIENT src/client/Wheel/: a 'SPIN' icon button in MenuRail (LayoutOrder 40) with a '!' when the free spin is ready. Modal 'EconomyWheel' (DisplayOrder 13): the wheel is a generated wheel ImageLabel, or 8 wedge Frames with rotated labels, plus a pointer and a stand. Buttons: 'FREE SPIN!' / 'SPIN (x3)' / 'R$ 9' / 'x10 R$ 79'. Animation: target = current + 360*6 + (360 - (index-0.5)*45) + jitter in ±17 degrees, tweened 4.2s Quint Out. A RenderStepped tick sound plays whenever floor(rot/45) changes, pitch rising, then a prize popup with burst. Auto-spin when the Spins attribute increases after a WheelSpin purchase. Coin reveal sync: add State.holdCoinFx(seconds) in Shop/State.lua, and have Hud.onCoins queue the diff until the hold ends, so the HUD doesn't spoil the result. Optional lobby world wheel (Lobby owner adds 'WheelAnchor'; a ProximityPrompt opens the UI).

**risks**: Expected value is ~100 coins plus extras per R$ 9; tune it against coin-pack prices. Two spin sources: free daily, plus playtime and daily rewards that can grant spins.


---

**briefItem**: #30 STARTER PACK (e.g. 500 coins + items, one-time)

**currentState**: Only plain coin packs exist (Rules.COIN_PACKS); there are no bundles and no one-time flags.

**plan**: SHARED src/shared/Economy/Offers.lua: STARTER = {key='StarterPack', coins=500, items={'TrailStarter'}, spins=3, revives=1, displayPrice=49, wasPrice=199}. Cosmetics adds TrailStarter with source='robux' (see the latent free-buy bug).
DATA: starterPack: boolean, firstJoin: number (os.time() set once when the profile is created; useful for offers and analytics).
SERVER: Products handler 'StarterPack': if data.starterPack is already true, grant 500 coins only (never lose a purchase; Roblox products are re-buyable); otherwise grant the coins, item (and equip it), spins and revives via applyBundle, set starterPack=true and mirror StarterOwned.
CLIENT: a FEATURED tab (first tab, left) with a big Starter card: 'STARTER PACK - ONE TIME ONLY!', item tiles (coin pile 500, trail preview, 3 spins, 1 revive), price button 'R$ 49' with a struck-through 'R$ 199' (a red line Frame over the text) and a 'BEST DEAL' ribbon kept inside the card bounds. A right-rail offer icon is shown until bought, and the shop auto-opens Featured once on the first or second session after the daily popup.

**risks**: Be truthful about the 'was' price: show it as the sum of the parts' value (500 coins ≈ R$ 25, plus spins 27, revive 19, trail ...) rather than an invented number.


---

**briefItem**: #31 LIMITED TRAIL for 19 Robux shown discounted from 199 with a countdown

**currentState**: Nothing exists. Every trail is coin-bought or VIP. Profile.reconcile would drop unknown limited ids on older servers (see bugs).

**plan**: SHARED Offers.LIMITED = { key='LimitedTrail', rotation={'TrailLava','TrailGalaxy','TrailCandy','TrailElectric'}, period=7*86400, epoch=<a Monday 00:00 UTC unix>, price=19, wasPrice=199 }. Offers.currentLimited(now) -> (itemId, endsAt) where k = floor((now-epoch)/period), item = rotation[k % #rotation + 1], endsAt = epoch + (k+1)*period. The countdown is REAL: the item genuinely leaves and the next trail rotates in. Cosmetics gets the 4 trails with source='robux' and limited=true (rainbow and sparkle visuals in Visuals.applyTrail).
PRODUCT: a single Config.PRODUCTS.LimitedTrail. Handler: id = currentLimited(os.time()). If it is already owned and now - startOf(current) < 900, try the previous rotation item (receipt processed just after the rollover). If everything is owned, grant 1000 coins. Otherwise grant, equip, mirror and toast 'LIMITED trail unlocked!'.
CLIENT: the FEATURED tab's top card has a 'New!' / 'LIMITED' tag, the trail name, an animated trail preview, a live countdown '3d 18h 31m 17s' from endsAt using workspace:GetServerTimeNow(), a big green 'R$ 19' and a red struck-through 'R$ 199' like ref5. It shows 'OWNED' after purchase. The Cosmetics tab shows limited trails with a 'LIMITED' lock that opens Featured. A right-rail offer icon carries a mini timer.

**risks**: A fake 'was 199' aimed at kids is a policy and ethics risk. Show wasPrice only if the item will be sold at 199 later (for example in a future 'Vault' rotation); otherwise label it '-90% LAUNCH DEAL'. The lead decides.


---

**briefItem**: #19 / #12 / #8 retention and spending (playtime gifts, boosts, VIP, level rewards, featured shop, choices)

**currentState**: Retention hooks: an auto daily of 50 coins and a level-up toast with no reward. Spending: 3 coin packs, 4 upgrade products, 2 passes (all id 0). Nothing has a timer, a streak or choices.

**plan**: 1) PLAYTIME GIFTS (refs: gift icons with 07:30 / FREE). DATA playtime={day,seconds,claimed={idx...}}. The server accrues seconds from the session clock: on load set accrueAt=os.clock(); on each claim, autosave or unload, do seconds += os.clock()-accrueAt and reset accrueAt; reset when the day changes. Tiers in Daily.PLAYTIME: 3m 30c, 6m 1 spin, 10m 60c, 15m 2X 10min, 20m 100c, 30m 1 revive, 45m 200c, 60m 2 spins. Economy_Claim('playtime', idx) validates idx (integer 1..#tiers, not yet claimed, accrued >= tier.sec). Mirror PlaytimeSec + PlaytimeAt (server time of the mirror) + PlaytimeClaimed (CSV) so the client can count down locally. CLIENT: a right-side RewardRail (new PartyHUD.RewardRail, contract) showing the next 2 gifts with timers and a bouncing 'CLAIM!' when ready.
2) 2X COINS BOOST: DATA boostUntil (unix). Product Boost2x (R$ 29, 30 min, stacks in time), plus wheel and playtime rewards. Change Rules.roundCoins(survived, winner, modifierRound, multiplier) where multiplier = (DoubleCoins and 2 or 1) * (boostActive and 2 or 1). Mirror BoostUntil; the HUD shows a '2X 14:59' pill under the coin counter.
3) VIP buff: +1 'VIP chest' per day (Economy_Claim('vip'), {coins=150}) and +25% coins; update PASS_INFO.blurb.
4) LEVEL REWARDS in Sessions.addXP: each level-up gives 20*level coins, and every 5th level +1 spin, via applyBundle (make XP its own currency: XP = coins earned before multipliers, not after).
5) FEATURED tab first in the shop with side tabs plus icons (Featured / Coins / Upgrades / Cosmetics / Passes) like ref5.
6) Optional choice product (#8): PickMinigame (R$ 25), where the buyer chooses the next minigame. It needs a Core hook RoundLoop.requestNext(minigameId, player) honored by pickMinigame (RoundLoop.lua:102), plus a feed line '<name> picked LASER TRACER!'.
7) Optional daily quests (3 per day, fed by Signals.RoundFinished/PlayerEliminated: 'Win 1 round', 'Play 5 rounds', 'Survive 60s') with coin and spin rewards.

**risks**: Keep economy numbers in Config/Daily/Wheel tables so the lead can tune. Don't overload the HUD on phones: at most 2 right-rail icons visible at a time.


---

**briefItem**: Dev-mode (Studio) purchase path for products/passes with id 0 (enables testing #27-#31, required by #18/#33)

**currentState**: id 0 shows 'COMING SOON' (RobuxTab.lua:84-90). Rules.productKey ignores 0. Market.processReceipt's keyHint (Market.lua:75) accepts only coin packs and upgrades. There is no way to test grants in Studio.

**plan**: SERVER src/server/Economy/DevShop.lua: `if not RunService:IsStudio() then return { start = function() end } end`. Only in Studio, create Net.event('Economy_DevBuy') with handler (player, kind:'product'|'pass', key:string): validate with type checks and that key is in Config.PRODUCTS / Config.GAMEPASSES, rate-limit. For products, call Market.processReceipt({PlayerId=player.UserId, ProductId=0, PurchaseId='studio-'..HttpService:GenerateGUID(false), CurrencySpent=0}, key) and generalize the keyHint check to `Products.has(keyHint)`. The SAME code path as live runs, including receipt recording and save. For passes, call Sessions.setPass(player,key,true) plus Market.onPassGranted. Refuse unless Store.NAME is the Studio store (see bug). The live server never creates the remote, so there is no exploit surface.
SHARED Rules.PRODUCT_INFO[key] = {displayPrice=number, title, ...} for every product (Coins500 25, Coins1500 65, Coins5000 199, Upgrade* 49, StarterPack 49, LimitedTrail 19, WheelSpin1 9, WheelSpin10 79, Revive 19, Boost2x 29) and Rules.PASS_INFO[...].displayPrice (DoubleCoins 149, VIP 199).
CLIENT src/client/Shop/Purchase.lua (the only place that prompts): Purchase.product(key) and Purchase.pass(key). If id ~= 0, call MarketplaceService:PromptProductPurchase/PromptGamePassPurchase (pcall); Studio then shows Roblox's own test-purchase dialog, which is safe. If id == 0 and RunService:IsStudio(), fire Economy_DevBuy after a small in-game confirm sheet 'TEST PURCHASE (Studio)'. Otherwise toast 'Coming soon!'. Purchase.priceText(key) returns the fetched real price, or displayPrice with a 'TEST' tag in Studio. Every buy button (RobuxTab, Featured, Wheel, Revive) uses it.
Also: workspace attributes Debug_FakeGroupMember (group chest) and Debug_EconomyDay (offset added to Rules.utcDay in Studio, to test streaks and rollover), both honored only under IsStudio.

**risks**: Team Test servers are hosted by Roblox, where IsStudio may be false, so the dev path is guaranteed only in Play / Start Server. Document this for critics.


---

**briefItem**: #20 / #7 / #9 / #5 Shop and economy UI 10x better, graphics generated with ChatGPT

**currentState**: A dark purple panel (C.Panel / Ui.CARD (62,54,108) / Ui.TILE (36,31,64)), a yellow 'SHOP' banner, 3 top tabs, emoji icons, a muddy coin tile, a clipped ribbon, an unreadable phone scale, and 'COMING SOON' everywhere. It uses its own Ui kit (src/client/Shop/Ui.lua), a third kit beside UI/Kit.lua and Solo/Ui.lua.

**plan**: Restyle to ref3/ref5: a bright header bar (green with diagonal gloss stripes, or rainbow), a big square red X (ref), a white-outlined title 'SHOP' left-aligned in the header, a lighter inner panel (e.g. #2B2F4A with a subtle checker ImageLabel tile, or a light cream panel), vertical side tabs with generated icons on the right (Featured % tag, Coins pile, Upgrades lightning, Cosmetics trail, Passes crown). Cards get colourful gradient frames per rarity. Green Robux buttons use the Robux glyph utf8.char(0xE002) followed by the price, with a struck-through old price in red where relevant. Fix the ribbon clipping and phone scale (bugs). Every button plays the shared click sound (#25).
ASSETS registry src/shared/Assets.lua (new contract): { Icons = { Coin='rbxassetid://...', CoinPileS/M/L, Chest, ChestGold (group), ChestEpic (day 7), Gift (playtime), Wheel, WheelPointer, Revive, Boost2x, VIPCrown, StarterBox, Upg_DashCooldown, Upg_DashDistance, Upg_JumpBoost, Upg_BatPower, Slot_Trail/Dash/Bat/WinFx, Tab_Featured/Coins/Upgrades/Cosmetics/Passes, Menu_Shop/Daily/Spin/Solo }, Backgrounds = { SunburstWhite, CheckerTile } }, with '' meaning draw the current shape fallback. Generation brief for ChatGPT: 'glossy 3D cartoon game icon, thick dark outline, bright saturated colors, transparent background, Roblox simulator style, 512x512', one consistent palette (Theme.Colors). Upload as Decals and paste the ids.
HUD (Shop/Hud.lua): coin pill as in the refs (bottom-left money stack in ref1, or keep top-right), plus a boost timer pill. MenuButton: a square icon tile with an outlined label under it (ref 'Shop' tile) instead of a round coin button; the UI subsystem should turn MenuRail into a 2-column UIGridLayout (Shop 10, Solo 20, Daily 30, Spin 40).

**risks**: Image ids require the owner's upload (moderation delay), so code must render well with fallbacks. Coordinate the colour language with the UI subsystem so the three kits converge into one shared client kit.


---

**briefItem**: #10 Bomb Tag replaces King of the Hill: economy coupling

**currentState**: Upg_BatPower is used only by KingOfTheHill/init.lua:80. Cos_BatColor is used only by KingOfTheHill/BatTool.lua (parseColor :48). CosmeticsTab.lua:108 depends on Theme.MinigameColors.KingOfTheHill.

**plan**: Move parseColor into src/shared/Economy/BatColor.lua (pure function, same accepted formats) and use it from the new Spin bat (#22). Keep the upgrade key and attribute 'BatPower' but rename its display to 'BONK POWER' ('Push others further'), applied to Spin bat knockback and to Bomb Tag's pass-shove. Fix CosmeticsTab.lua:108 to a literal colour. Optional new cosmetic slot 'BombSkin' (Cos_BombSkin) for Bomb Tag: Cosmetics.SLOTS append, SLOT_INFO {title='BOMB', attr='Cos_BombSkin', defaultName='Classic Bomb'}, 5 coin skins plus a rainbow; the Bomb Tag server reads the holder's Cos_BombSkin to colour the bomb model. Rewards need no change: Bomb Tag is survival kind, so placements, survived and winners already flow through Signals.RoundFinished.

**risks**: If BatPower has no consumer for a while, players who bought levels feel scammed. Ship the Spin bat in the same wave.


---

**briefItem**: #26 / #14 join zone and 20s lobby: economy interplay

**currentState**: Every idle player is a participant (RoundLoop.lua:69-98) and gets paid (AFK farming). The shop auto-closes only on Intro/Countdown (Window.lua:402-406).

**plan**: Core (another subsystem) picks participants from the join square, which removes AFK rewards with no Economy change because Rewards pays result.participants only. Economy: close the shop, wheel and daily modals when the Phase becomes Roulette and the player is standing in the zone, so a modal never hides the roulette. Show a 'Step on the square to play!' hint in empty states. Config.LOBBY_TIME = 20 (lead).

**risks**: none for Economy


---

**briefItem**: #25 / #23 click sound on every button, settings mute

**currentState**: Shop/Sfx.lua 'click' = volume_slider.ogg @1.3, Solo/Sfx.lua 'click' = action_jump.mp3 @1.7, UI/Sfx.lua has no click: three inconsistent sound sets, all played with PlayLocalSound with no SoundGroup.

**plan**: Use one client sound module, or let the UI subsystem own a global DescendantAdded hook on PlayerGui that plays the shared click on every GuiButton.Activated unless the attribute NoClickSound=true. The Shop then removes its own Sfx.play('click') calls (MenuButton.lua:77, RobuxTab.lua:85, Hud.lua:78/133, CosmeticsTab) to avoid double clicks. Parent all economy sound templates under SoundService.SFX (a SoundGroup) so the settings toggle (#23) can mute SFX and Music separately.

**risks**: Double sounds if both the hook and the local calls stay.


---

**briefItem**: #18 fix all bugs: economy persistence hardening

**currentState**: See bugs: unknown-field loss, pendingReceipts race, same-server rejoin race, autosave iteration, non-atomic grants, Studio writes to the prod store, invisible temporary profile.

**plan**: Apply the bug fixes in this order: Profile v2 with passthrough, write() confirming only its own receipts, the unloading[userId] gate in load, the autosave snapshot plus pcall, the Products registry with pcall and rollback, Store.NAME split for Studio, the EconomyPersistent attribute. Add Profile v2 fields in ONE place (Profile.default/reconcile/serialize): daily{day,streak}, groupDay, vipDay, spins, freeSpinDay, reviveTokens, starterPack, boostUntil, firstJoin, playtime{day,seconds,claimed}, stats.robuxSpent (+= receiptInfo.CurrencySpent). Raise Rules.MAX_RECEIPTS to 100 (cheap spins mean many receipts). Remove the redundant saveSoon after receipt saves (DataStore allows about one write per key every 6s; extra writes get throttled and queued).

**risks**: Profile.reconcile must clamp every new counter (int(value,0,cap)) because the stored record is untrusted.

**contractChanges**: 1) src/shared/Config.lua (frozen, lead): ADD keys only.
- Config.GROUP_ID = 0
- Config.PRODUCTS += StarterPack, LimitedTrail, WheelSpin1, WheelSpin10, Revive, Boost2x (all 0), plus optionally PickMinigame
- Config.LOBBY_TIME = 20
Keep DAILY_REWARD (now unused, or the day-1 amount).

2) Product registry rule (add to ARCHITECTURE.md): ONLY Economy assigns MarketplaceService.ProcessReceipt (init.lua:218). Every developer product is registered in src/server/Economy/Products.lua as `Products.register(key, { grant = function(player, session, receipt): (boolean, string?) end, oneTime = bool? })`.
- Handlers mutate session.data synchronously and must not yield.
- Anything that yields (a Core revive) runs via task.defer after the receipt save.
- Market.grant (Market.lua:22-46) and the keyHint whitelist (Market.lua:75) are replaced by Products.has/apply.
- Every prompt on the client goes through src/client/Shop/Purchase.lua (Studio dev path when the id is 0).

3) Reward primitive: Rewards.applyBundle(player, bundle, reason) -> appliedBundle, where bundle = { coins?, xp?, spins?, revives?, boostSeconds?, items?: {cosmeticId} }. Duplicate items convert to coins (Cosmetics item.dupCoins, or price, or 500). It mirrors attributes and returns what was granted, for the client reveal. All new reward sources call it: daily, group, VIP, playtime, wheel, starter, limited, level-ups.

4) Profile v2 schema (Profile.lua, VERSION 2), with unknown-key passthrough (_extra) and unknown-cosmetic passthrough (ownedUnknown). New fields:
- daily = { day, streak }, groupDay, vipDay
- spins, freeSpinDay, reviveTokens
- starterPack (bool), boostUntil, firstJoin
- playtime = { day, seconds, claimed = {int} }
- stats.robuxSpent
Migration: lastDaily maps to daily.day.

5) Cosmetics.Item gains `source: "coins"|"vip"|"robux"|"reward"`, `limited: boolean?` and `dupCoins: number?`. New ids: TrailStarter, TrailFortune, TrailStreak, TrailLava, TrailGalaxy, TrailCandy, TrailElectric. Optional slot BombSkin (attr Cos_BombSkin) for Bomb Tag.

6) New remotes (Net), owner Economy:
- Economy_Claim: RemoteFunction (kind:"daily"|"group"|"vip"|"playtime", arg) -> result table
- Economy_Spin: RemoteFunction () -> {ok, index, segmentId, reward, spinsLeft, usedFree}
- Economy_UseRevive: RemoteEvent; the reply comes on Economy_Result with action "revive"
- Economy_ReviveOffer: RemoteEvent, server to client (expiresAt, tokens) or ("cancel")
- Economy_DevBuy: RemoteEvent, created only when RunService:IsStudio()

7) New Player attributes (Economy; add to the ARCHITECTURE.md table and Rules.Attr):
- Spins, FreeSpinDay, ReviveTokens
- DailyDay, DailyStreak, GroupDay, VipDay
- PlaytimeSec, PlaytimeAt, PlaytimeClaimed
- StarterOwned, BoostUntil, FirstJoin
- PaidRandomRestricted, EconomyPersistent
Client countdowns must use workspace:GetServerTimeNow(), and Rules.utcDay(t) takes that value.

8) CORE hook for Revive (Core builder):
- Context:_revive(p): boolean, plus `_shieldUntil` (non-"left" eliminations are ignored during a 2.5s shield)
- params.onRevived(p) in Context.new; RoundLoop sets InRound=true and Spectating=false, writes GameState Alive and sends a feed line
- New module src/server/Core/Revive.lua: Revive.status(player): string, Revive.revive(player): boolean, operating on State.ctx
- Contracts/Minigame.lua: optional `session:onRevive(player)`
- Optional Signals.PlayerRevived(player, { minigameId })
Economy listens to Signals.PlayerEliminated to make offers. That signal already exists, but it fires only for the main round, which is correct.

9) UI subsystem rails:
- PartyHUD.MenuRail becomes a 2-column grid of square icon tiles with labels (ref3). LayoutOrders: Shop 10, Solo 20, Daily 30, Spin 40.
- New PartyHUD.RewardRail (right-middle, vertical) for timed gifts and offers (playtime gift, group chest, starter, limited). Economy docks its items there as MenuButton does today (rebuild on PartyHUD recreate).
- A client-local attribute LocalPlayer.ClientReady=true, set by the loading screen (#24), so popups (daily chest) wait for it.
- Revive card at y≈0.62, above #17's SPECTATE/LOBBY buttons.

10) New shared art registry src/shared/Assets.lua (icon and background image ids, "" means fallback). All UI pieces read it.

11) Lobby map (shared Maps/Lobby.lua owner) adds anchor parts GroupChestAnchor and WheelAnchor (optional world props). Economy attaches ProximityPrompts by watching workspace.Lobby, because the lobby is rebuilt every round (Places.buildLobby/destroyLobby).

12) Bomb Tag / Spin:
- Move KingOfTheHill/BatTool.parseColor to src/shared/Economy/BatColor.lua.
- The Spin bat and the Bomb Tag shove read Upg_BatPower and Cos_BatColor.
- Theme.MinigameColors.KingOfTheHill must not be removed until CosmeticsTab.lua:108 stops referencing it (or add a BombTag key and keep the old one).

13) Store.NAME becomes "PartyDash_Profiles_Studio_v1" under RunService:IsStudio() (Economy-internal, but critics should know Studio data is separate).

**qualityNotes**: - XP equals the coins granted after multipliers (Rewards.lua:42-43), so the DoubleCoins pass and modifier rounds also double XP. Compute XP from the base reward before multipliers.
- DataStore per-key write throttle (about one write per 6s): processReceipt already saves synchronously. The saveSoon calls after purchases and claims add queued writes, and a kid buying several 9 R$ spins quickly will see 6s+ receipt latency. Batch with one saveSoon and skip it when a receipt save just happened.
- Consider swapping the homemade session lock for ProfileStore (loleris), which handles locking, MessagingService lock-steal requests and receipt handling. If the homemade lock stays, apply the three persistence fixes above.
- Rules.productKey scans linearly on every receipt; build a reverse map once, rebuilt only when debug code remaps ids.
- Ui.punch and Ui.tween create a new Tween on every hover, press and coin landing. That is acceptable, but Hud.flyCoins builds up to 12 coins of 5 instances each per gain. Pool them if the wheel, chests and playtime gifts start firing it frequently.
- Shop/Ui.lua, UI/Kit.lua and Solo/Ui.lua are three separate UI kits with different stroke and gradient conventions, which explains why the screens don't look like one product. Merge them into one shared client kit during the UI overhaul.
- Use the Robux glyph utf8.char(0xE002) instead of the text "R$".
- Robux upgrade products ("Instantly to Lv N") sell direct power. Keep that for upgrades, but weight new monetization toward cosmetics, spins, revive and boosts (kid-friendly, less pay-to-win).
- Paid random items (wheel spins): show odds before purchase and respect PolicyService ArePaidRandomItemsRestricted.
- Rewarding likes is against Roblox policy: gate the chest on group membership only.
- Keep the "was 199" price truthful.
- Every new claim and spin handler must finish its check and mutation without yielding. Any yielding web call (GetGroupsAsync, PolicyService) runs before the check, and state is re-checked after it.
- Remotes.allow uses one shared bucket (10 burst at 4/s) across all economy remotes. Wheel and claim spam can starve equip and buy feedback; give each remote its own bucket, or a cost of 1 for UI actions and 2 for claims.
- Visuals.lua builds the PlayerTag BillboardGui server-side with MaxDistance 110. With the new bright maps, check contrast and make the VIP gold name readable (add a stroke).
