-- Wspólne stałe i matematyka kręcącego się kija (serwer + klient).
local Shared = {}

Shared.PILLAR_COUNT = 8
Shared.PILLAR_RADIUS = 32
Shared.PILLAR_TOP = 25
Shared.BAR_Y = 26.5
Shared.BAR_THICK = 1.4
Shared.BAR_HALF_LEN = 37
Shared.HIDDEN_Y = -60

Shared.EVENTS = {
	{ id = "Fog", name = "MGŁA", desc = "Prawie nic nie widać!" },
	{ id = "TwoBars", name = "DWA KIJE", desc = "Drugi kij kręci się w drugą stronę!" },
	{ id = "LowGravity", name = "NISKA GRAWITACJA", desc = "Skaczesz jak na Księżycu!" },
	{ id = "Crazy", name = "SZALONY KIJ", desc = "Kij losowo zmienia kierunek!" },
	{ id = "Turbo", name = "TURBO", desc = "Kij od początku pędzi!" },
}

function Shared.getEvent(id)
	for _, e in Shared.EVENTS do
		if e.id == id then
			return e
		end
	end
	return nil
end

function Shared.pillarCFrame(i)
	local th = (i - 1) * (2 * math.pi / Shared.PILLAR_COUNT)
	local pos = Vector3.new(math.cos(th) * Shared.PILLAR_RADIUS, Shared.PILLAR_TOP, -math.sin(th) * Shared.PILLAR_RADIUS)
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

-- Stan kija trzymamy w jednym atrybucie, żeby zmiany docierały do klientów naraz.
function Shared.encode(s)
	return string.format("%.6f,%.4f,%.5f,%.5f,%.5f,%d,%d", s.a0, s.t0, s.w, s.acc, s.maxW, s.dir, s.active and 1 or 0)
end

function Shared.decode(str)
	if typeof(str) ~= "string" then
		return nil
	end
	local a0, t0, w, acc, maxW, dir, active = string.match(str, "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
	if not a0 then
		return nil
	end
	return {
		a0 = tonumber(a0), t0 = tonumber(t0), w = tonumber(w), acc = tonumber(acc),
		maxW = tonumber(maxW), dir = tonumber(dir), active = active == "1",
	}
end

local function travelAndSpeed(s, t)
	local dt = math.max(0, t - s.t0)
	if s.acc > 0 and s.w < s.maxW then
		local tCap = (s.maxW - s.w) / s.acc
		if dt < tCap then
			return s.w * dt + 0.5 * s.acc * dt * dt, s.w + s.acc * dt
		end
		return s.w * tCap + 0.5 * s.acc * tCap * tCap + s.maxW * (dt - tCap), s.maxW
	end
	return s.w * dt, s.w
end

-- Kąt zależy tylko od czasu serwera, więc każdy klient liczy go sam i kij kręci się płynnie.
function Shared.angle(s, t)
	local travel = travelAndSpeed(s, t)
	return s.a0 + s.dir * travel
end

function Shared.speed(s, t)
	local _, w = travelAndSpeed(s, t)
	return w
end

function Shared.barCFrame(angle)
	return CFrame.new(0, Shared.BAR_Y, 0) * CFrame.Angles(0, angle, 0)
end

-- Kąt pozycji w tym samym układzie co kij (oś X kija obrócona o angle wokół Y).
function Shared.positionAngle(pos)
	return math.atan2(-pos.Z, pos.X)
end

-- Kij ma dwa ramiona, więc odległość liczymy modulo pi, w zakresie (-pi/2, pi/2].
function Shared.armDistance(barAngle, posAngle)
	local d = (barAngle - posAngle) % math.pi
	if d > math.pi / 2 then
		d -= math.pi
	end
	return d
end

return Shared
