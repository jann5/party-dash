-- UIKit number / time formatting.
local Format = {}

-- 12450 -> "12,450"
function Format.number(n: number): string
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (neg and "-" or "") .. out
end

-- 125000 -> "125K", 1234567 -> "1.2M", below 100K -> Format.number
function Format.short(n: number): string
	local a = math.abs(n)
	if a >= 1e9 then
		return (("%.1fB"):format(n / 1e9):gsub("%.0B", "B"))
	elseif a >= 1e6 then
		return (("%.1fM"):format(n / 1e6):gsub("%.0M", "M"))
	elseif a >= 1e5 then
		return ("%dK"):format(math.floor(n / 1e3))
	end
	return Format.number(n)
end

-- seconds -> "0:14" / "12:05" / "1:02:03"
function Format.clock(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s)
	end
	return ("%d:%02d"):format(m, s)
end

-- seconds -> "1d 23h 12m 09s" / "23h 14m 09s" / "14m 09s" / "9s"
function Format.long(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if d > 0 then
		return ("%dd %02dh %02dm %02ds"):format(d, h, m, s)
	elseif h > 0 then
		return ("%dh %02dm %02ds"):format(h, m, s)
	elseif m > 0 then
		return ("%dm %02ds"):format(m, s)
	end
	return ("%ds"):format(s)
end

-- 0.125 -> "12.5%"
function Format.percent(p: number): string
	local v = p * 100
	if math.abs(v - math.floor(v + 0.5)) < 0.05 then
		return ("%d%%"):format(math.floor(v + 0.5))
	end
	return ("%.1f%%"):format(v)
end

return Format
