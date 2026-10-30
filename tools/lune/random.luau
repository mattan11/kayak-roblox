-- Zamiennik typu Random z Robloxa dla Lune (tam go nie ma). Generator Parka–Millera (LCG mod 2³¹−1):
-- prosty, deterministyczny dla danego ziarna, iloczyn mieści się dokładnie w double.
-- Kolejne liczby RÓŻNIĄ SIĘ od Robloxa (inny algorytm) — testy mogą polegać tylko na powtarzalności i zakresach.
-- (Dla TS: jak `seedrandom` zamiast Math.random — obiekt z własnym stanem.)

local MODULUS = 2147483647
local MULTIPLIER = 48271

local Random = {}
Random.__index = Random

function Random.new(seed: number?)
	-- Ziarno 0 zablokowałoby generator (0 · a = 0), więc przesuwamy je do 1..MODULUS−1.
	local start = math.floor(seed or os.clock() * 1e6) % (MODULUS - 1) + 1
	return setmetatable({ _state = start }, Random)
end

-- Liczba z [0, 1).
local function step(self): number
	self._state = (self._state * MULTIPLIER) % MODULUS
	return (self._state - 1) / (MODULUS - 1)
end

-- NextNumber() → [0, 1); NextNumber(min, max) → [min, max).
function Random:NextNumber(min: number?, max: number?): number
	local low, high = min or 0, max or 1
	return low + step(self) * (high - low)
end

-- Liczba całkowita z [min, max] (obie granice włącznie, jak w Robloxie).
function Random:NextInteger(min: number, max: number): number
	return min + math.floor(step(self) * (max - min + 1))
end

-- Tasowanie listy w miejscu (Fisher–Yates).
function Random:Shuffle(list: { any })
	for i = #list, 2, -1 do
		local j = self:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

function Random:Clone()
	return setmetatable({ _state = self._state }, Random)
end

return { new = Random.new }
