# Party Dash v2 — what the owner has to do (things code cannot do)

## 1. Robux products (Creator Hub → your experience → Monetization)
Create these **Developer Products** with exactly these prices, then paste each id into `src/shared/Config.lua`
(`Config.PRODUCTS`). Until an id is filled in, the game shows the price and says "Coming soon!" (in Studio the
button grants the item for testing).

| Key in Config.PRODUCTS | Name to give it | Price (R$) |
|---|---|---|
| WheelSpin1 | 1 Spin | 9 |
| WheelSpin5 | 5 Spins | 39 |
| Revive | Revive | 19 |
| StarterPack | Starter Pack | 49 |
| GalaxyTrail19 | Galaxy Comet (Welcome Deal) | 19 |
| GalaxyTrail199 | Galaxy Comet | 199 |
| Coins500 | 500 Coins | 25 |
| Coins1500 | 1,500 Coins | 65 |
| Coins5000 | 5,000 Coins | 179 |
| UpgradeDashCooldown / UpgradeDashDistance / UpgradeBatPower / UpgradeJumpBoost | Upgrade +1 | 25 each |

**Game Passes** (paste ids into `Config.GAMEPASSES`): DoubleCoins "2X Coins" 149 R$, VIP 249 R$.

## 2. Group chest
Create a Roblox group for the game and put its id in `Config.GROUP_ID`. (Liking the game cannot be checked by any
Roblox API; the chest text asks for it, the group membership is what is verified.)

## 3. Season / limited trail
Set `Config.SEASON1_END` (unix time, e.g. launch + 30 days). Until then the Galaxy Comet trail really costs 199 R$
and every new player sees it for 19 R$ during their first 48 hours (honest "was 199" price).

## 4. Studio settings (Game Settings / Lighting; scripts cannot set these)
- Avatar: R15 (the slide tackle animation looks best on R15; R6 also works).
- Lighting.Technology = ShadowMap (crisp shadows).
- Before publishing: HttpService.HttpEnabled can be turned off again (it is only used by the Studio dev bridge).
- Publish the place so DataStores work (coins, levels, leaderboards are saved only in a published game).

## 5. Store page
`assets/art/` has the logo (`logo.png`), the loading art (`loading_bg.png`) and the store icon/thumbnail
(`store_icon.png`, `store_thumb.png` if present). Upload them on the experience's store page.

## 6. Please look at the 3D world with your screen unlocked
Overnight the Mac screen was locked, and Studio does not draw the 3D view while locked, so maps were checked with
geometry dumps and preview renders. Play one round of each game in Studio and tell me anything that looks off.
