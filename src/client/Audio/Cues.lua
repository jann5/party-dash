-- Reward cues: a coin chime when the Coins attribute goes up (at most one per 0.25 s, so a burst of payouts stays
-- pleasant) and a level-up jingle when Level goes up. The first value (profile load) is never celebrated.
local Players = game:GetService("Players")

local Cues = {}

local COIN_GAP = 0.25

-- Calls `play` whenever the numeric Player attribute `attr` increases (respecting `minGap` seconds between plays).
local function onIncrease(player: Player, attr: string, minGap: number, play: () -> ())
	local last = player:GetAttribute(attr)
	local lastPlayed = -math.huge
	player:GetAttributeChangedSignal(attr):Connect(function()
		local value = player:GetAttribute(attr)
		local previous = last
		last = value
		if typeof(value) ~= "number" or typeof(previous) ~= "number" or value <= previous then
			return
		end
		local now = os.clock()
		if now - lastPlayed < minGap then
			return
		end
		lastPlayed = now
		play()
	end)
end

function Cues.start(Audio)
	local player = Players.LocalPlayer
	onIncrease(player, "Coins", COIN_GAP, function()
		Audio.ui("CoinCollect", { pitch = 0.97 + math.random() * 0.08 })
	end)
	onIncrease(player, "Level", 0, function()
		Audio.play("LevelUp")
	end)
end

return Cues
