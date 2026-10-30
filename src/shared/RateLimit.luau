-- Limit zapytań „wiadro żetonów” (token bucket) — czysta logika, bez Robloxa (testy: logic/RateLimit.spec).
-- Każdy klucz (np. gracz + nazwa remotu) ma wiadro z `burst` żetonami, które dolewa się w tempie `rate` na sekundę.
-- Zapytanie zabiera 1 żeton; brak żetonu = odrzucone. Chroni serwer przed zasypywaniem zdarzeniami przez oszustów.
-- (Dla TS: jak rate-limiter w Express, np. express-rate-limit, tylko w pamięci jednego serwera.)

local RateLimit = {}
RateLimit.__index = RateLimit

export type Bucket = { tokens: number, last: number }

function RateLimit.new()
	return setmetatable({ buckets = {} :: { [any]: { [string]: Bucket } } }, RateLimit)
end

-- Czy pozwolić na zapytanie `key` właściciela `owner` w chwili `now` (sekundy, np. os.clock()).
function RateLimit:allow(owner: any, key: string, rate: number, burst: number, now: number): boolean
	local perOwner = self.buckets[owner]
	if not perOwner then
		perOwner = {}
		self.buckets[owner] = perOwner
	end
	local bucket = perOwner[key]
	if not bucket then
		bucket = { tokens = burst, last = now }
		perOwner[key] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Sprzątanie po wyjściu gracza (inaczej tabela trzymałaby obiekt Player na zawsze — wyciek pamięci).
function RateLimit:forget(owner: any)
	self.buckets[owner] = nil
end

return RateLimit
