-- Liczby i teksty HUD-a bez Instance (testy: logic/RaceFormat.spec).

local RaceFormat = {}

local TOP_LIMIT = 10

-- 83.45 → "1:23.4". Bez czasu (np. gracz nie dopłynął) → "–:––".
function RaceFormat.time(seconds: number?): string
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then
		return "–:––"
	end
	local tenths = math.floor(seconds * 10)
	return string.format("%d:%02d.%d", tenths // 600, (tenths // 10) % 60, tenths % 10)
end

-- Ułamek trasy 0..1.
function RaceFormat.progress(s: number, startS: number, finishS: number): number
	return math.clamp((s - startS) / (finishS - startS), 0, 1)
end

-- Miejsce: 1 + ilu jest dalej na trasie. others = lista s pozostałych, `count` = ile pierwszych pozycji jest aktualnych
-- (HUD używa tej samej tablicy przy każdym odświeżeniu).
function RaceFormat.place(mine: number, others: { number }, count: number): number
	local place = 1
	for i = 1, count do
		if others[i] > mine then
			place += 1
		end
	end
	return place
end

-- Ranking z JSON-a serwera (TopTimes): lista { userId, name, time }. Odrzuca śmieci, nigdy nie rzuca błędu.
function RaceFormat.parseTop(decoded: any): { { userId: number?, name: string, time: number } }
	local entries = {}
	if type(decoded) ~= "table" then
		return entries
	end
	for _, row in decoded do
		if type(row) == "table" and type(row.name) == "string" and type(row.time) == "number" then
			table.insert(entries, { userId = row.userId, name = row.name, time = row.time })
			if #entries == TOP_LIMIT then
				break
			end
		end
	end
	return entries
end

return RaceFormat
