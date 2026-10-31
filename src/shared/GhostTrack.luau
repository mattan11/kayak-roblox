-- Ślad ducha: czysta logika, bez Instance i bez zegara (testy: logic/GhostTrack.spec).
-- Serwer nagrywa próbki (record), składa z nich zapis (finish), a klient odtwarza go z interpolacją (evaluate).
-- Dane to płaska tablica liczb całkowitych: t, x, y, z, kurs, t, x, y, z, kurs... Płaska, bo JSON jest wtedy krótki,
-- a odczyt co klatkę nie dotyka małych tabel. (Dla TS: jak Int32Array z krokiem 5 zamiast tablicy obiektów.)
-- y też jest w śladzie, bo na wodospadzie kajak spada.

local Config = require(script.Parent.Config)

local GhostTrack = {}

local VERSION = 1 -- format danych; po jego zmianie stare wpisy nie przejdą validate i zostaną nadpisane
local STRIDE = 5 -- ile liczb ma jedna próbka
local TWO_PI = 2 * math.pi
local BASE_OVERHEAD = 64 -- nazwy pól i nawiasy JSON-a

local TIME_SCALE = Config.GHOST_TIME_SCALE
local POSITION_SCALE = Config.GHOST_POSITION_SCALE
local HEADING_STEPS = Config.GHOST_HEADING_STEPS

export type Recorder = { data: { number }, count: number, lastTime: number }

-- Ślad po JSON-ie. Tabela jest tylko do odczytu: serwer trzyma ją w pamięci i może przypisać do dwóch miejsc naraz.
export type Track = { v: number, ms: number, userId: number, data: { number } }

local function isInteger(value: any): boolean
	return type(value) == "number" and math.floor(value) == value
end

function GhostTrack.newRecorder(): Recorder
	return { data = {}, count = 0, lastTime = -math.huge }
end

-- Kolejny odczyt pozycji. Serwer woła to częściej, niż trzeba, a tutaj zostaje próbka co GHOST_SAMPLE_INTERVAL.
-- `force` zapisuje ostatni punkt przejazdu poza kolejnością. Zwraca, czy próbka weszła.
function GhostTrack.record(recorder: Recorder, t: number, x: number, y: number, z: number, heading: number, force: boolean?): boolean
	local time = math.round(t * TIME_SCALE)
	local dueAt = recorder.lastTime + Config.GHOST_SAMPLE_INTERVAL * TIME_SCALE
	if time <= recorder.lastTime or (time < dueAt and not force) or recorder.count >= Config.GHOST_MAX_SAMPLES then
		return false
	end
	local data = recorder.data
	local offset = recorder.count * STRIDE
	data[offset + 1] = time
	data[offset + 2] = math.round(x * POSITION_SCALE)
	data[offset + 3] = math.round(y * POSITION_SCALE)
	data[offset + 4] = math.round(z * POSITION_SCALE)
	data[offset + 5] = math.round(heading / TWO_PI * HEADING_STEPS) % HEADING_STEPS
	recorder.count += 1
	recorder.lastTime = time
	return true
end

-- Czy dane nadają się do użycia? Sprawdzamy wszystko, bo wpis z DataStore mógł powstać w starej wersji gry.
function GhostTrack.validate(track: any): boolean
	if type(track) ~= "table" or track.v ~= VERSION or not isInteger(track.ms) or track.ms <= 0 then
		return false
	end
	if not isInteger(track.userId) or type(track.data) ~= "table" then
		return false
	end
	local data = track.data
	local length = #data
	local count = length // STRIDE
	if length % STRIDE ~= 0 or count < 2 or count > Config.GHOST_MAX_SAMPLES then
		return false
	end
	local maxTime = Config.RACE_TIME_LIMIT * 2 * TIME_SCALE
	local maxCoord = Config.GHOST_MAX_COORD * POSITION_SCALE
	local lastTime = -1
	for offset = 0, length - STRIDE, STRIDE do
		local time, x, y, z, heading = data[offset + 1], data[offset + 2], data[offset + 3], data[offset + 4], data[offset + 5]
		if not (isInteger(time) and isInteger(x) and isInteger(y) and isInteger(z) and isInteger(heading)) then
			return false
		end
		if time <= lastTime or time > maxTime then
			return false
		end
		if math.abs(x) > maxCoord or math.abs(y) > maxCoord or math.abs(z) > maxCoord then
			return false
		end
		if heading < 0 or heading >= HEADING_STEPS then
			return false
		end
		lastTime = time
	end
	return true
end

-- Rozmiar po JSON-ie, policzony bez HttpService, żeby dało się go testować poza silnikiem.
function GhostTrack.byteSize(track: Track): number
	local size = BASE_OVERHEAD
	for _, value in track.data do
		size += #tostring(value) + 1
	end
	return size
end

-- Składa zapis z nagrania. `ms` to czas przyjęty przez RaceLogic. nil = dane nie przeszły walidacji albo limitu rozmiaru.
function GhostTrack.finish(recorder: Recorder, ms: number, userId: number): Track?
	local track = { v = VERSION, ms = ms, userId = userId, data = recorder.data }
	if GhostTrack.validate(track) and GhostTrack.byteSize(track) <= Config.GHOST_MAX_BYTES then
		return track
	end
	return nil
end

-- Pozycja ducha w chwili `t` (sekundy od linii startu). Przed pierwszą próbką i po ostatniej stoi na jej miejscu.
-- `cursor` to numer odcinka z poprzedniej klatki: dzięki niemu nie szukamy od początku. Wołający trzyma go u siebie
-- (zaczyna od 1). Pięć liczb zamiast tabeli, bo to wołane co klatkę: (x, y, z, kurs, cursor).
function GhostTrack.evaluate(track: Track, t: number, cursor: number): (number, number, number, number, number)
	local data = track.data
	local count = #data // STRIDE
	local time = t * TIME_SCALE
	if cursor < 1 or cursor >= count or data[(cursor - 1) * STRIDE + 1] > time then
		cursor = 1
	end
	while cursor < count - 1 and data[cursor * STRIDE + 1] <= time do
		cursor += 1
	end

	local a = (cursor - 1) * STRIDE
	local b = a + STRIDE
	local alpha = math.clamp((time - data[a + 1]) / (data[b + 1] - data[a + 1]), 0, 1)
	-- Kurs najkrótszą drogą, żeby przejście przez 0 nie kręciło kajakiem dookoła.
	local turn = (data[b + 5] - data[a + 5] + HEADING_STEPS / 2) % HEADING_STEPS - HEADING_STEPS / 2
	return (data[a + 2] + (data[b + 2] - data[a + 2]) * alpha) / POSITION_SCALE,
		(data[a + 3] + (data[b + 3] - data[a + 3]) * alpha) / POSITION_SCALE,
		(data[a + 4] + (data[b + 4] - data[a + 4]) * alpha) / POSITION_SCALE,
		(data[a + 5] + turn * alpha) / HEADING_STEPS * TWO_PI,
		cursor
end

return GhostTrack
