--!strict
-- Per-player, per-remote token buckets: a burst of `burst` requests, refilling `rate` per second.
-- Each remote has its own bucket, so spamming the wheel never starves shop feedback.
local Players = game:GetService("Players")

local Limiter = {}

type Bucket = { tokens: number, at: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

function Limiter.allow(player: Player, key: string, burst: number, rate: number): boolean
	local now = os.clock()
	local mine = buckets[player]
	if not mine then
		if player.Parent ~= Players then
			return false
		end
		mine = {}
		buckets[player] = mine
	end
	local b = mine[key]
	if not b then
		b = { tokens = burst, at = now }
		mine[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.at) * rate)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Limiter.start()
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Limiter
