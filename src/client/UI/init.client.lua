--!nonstrict
-- Party Dash HUD v2 (piece V5). Every round-related screen, built with Shared.UIKit (ART_BIBLE section 8):
--   Status    top lane: NEXT GAME timer + join hints / YOU'RE IN, then the round's game, alive count, sudden death
--   Vote      three vote cards in the Action lane (queued players, Lobby)
--   Roulette  full-screen reel that lands on the chosen game / modifier
--   Intro     how-to-play card (round members, Intro)
--   Hype      huge transient words: Core_Announce "big" and the 3-2-1-GO countdown
--   Announce  routes Core_Announce: big -> Hype, feed -> kill feed lane, toast -> UIKit.toast
--   Death     OUT! panel with Spectate / Lobby / Revive (Core_Death)
--   Results   podium, MVP and the coin breakdown (End)
--   Tutorial  DASH / SLIDE / JUMP hint chips for new players
-- Spectating itself lives in src/client/Spectate. Modules only read replicated state and connect to remotes
-- lazily, so the HUD boots and works before Core, Economy or any minigame exist.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

if not game:IsLoaded() then
	game.Loaded:Wait()
end
ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIKit")

-- The custom HUD replaces the default player list (it covered the currency and the feed). Chat stays.
task.spawn(function()
	for _ = 1, 60 do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
		if not StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) then
			return
		end
		task.wait(0.5)
	end
end)

-- Each module starts in its own thread: one failing module can never take the rest of the HUD down.
for _, name in { "Status", "Vote", "Roulette", "Intro", "Hype", "Announce", "Death", "Results", "Tutorial" } do
	task.spawn(function()
		require(script:WaitForChild(name)).start()
	end)
end
