-- Per-key token buckets for remote rate limits. `rate` tokens refill per second up to `burst`; every accepted call
-- spends one. Pure (the clock can be passed in), so it is easy to test.
local Limiter = {}
Limiter.__index = Limiter

type Bucket = { tokens: number, at: number }

export type Limiter = typeof(setmetatable({} :: { rate: number, burst: number, buckets: { [any]: Bucket } }, Limiter))

function Limiter.new(rate: number, burst: number): Limiter
	return setmetatable({ rate = rate, burst = burst, buckets = {} }, Limiter)
end

-- True (and spends a token) when `key` may act now.
function Limiter.allow(self: Limiter, key: any, now: number?): boolean
	local t = now or os.clock()
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.burst, at = t }
		self.buckets[key] = bucket
	end
	bucket.tokens = math.min(self.burst, bucket.tokens + (t - bucket.at) * self.rate)
	bucket.at = t
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Limiter.forget(self: Limiter, key: any)
	self.buckets[key] = nil
end

return Limiter
