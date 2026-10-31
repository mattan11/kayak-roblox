-- Medale: czysta logika bez usług Robloxa (testy: logic/Medals.spec). Progi są w Config.RIVER_MEDALS.
-- Stopień to liczba: 0 brak, 1 brąz, 2 srebro, 3 złoto (dla TS: `enum Medal { None, Bronze, Silver, Gold }`).
-- Decyduje serwer, na czasie przyjętym przez RaceLogic. Klient używa tych funkcji tylko do wyświetlania.
-- Moduł jest w `shared`, bo progi pokazuje też wioska (RiverPicker).

local Config = require(script.Parent.Config)

local Medals = {}

-- Indeks = stopień. Nazwy to klucze wpisów w Config.RIVER_MEDALS.
Medals.RANKS = { "bronze", "silver", "gold" }
-- Kolory wspólne dla ekranu wyników i kafelków wioski.
Medals.COLORS = {
	Color3.fromRGB(214, 140, 76),
	Color3.fromRGB(205, 215, 225),
	Color3.fromRGB(255, 214, 64),
}
-- Atrybut gracza z najwyższym medalem na bieżącej rzece, ustawia go PlayerData (dla TS: stan tylko do odczytu u klienta).
Medals.ATTRIBUTE = "RiverMedal"

-- Najwyższy stopień za ten czas. Czas równy progowi daje medal. Rzeka bez wpisu i śmieciowy czas dają 0.
function Medals.medalFor(riverId: string, time: any): number
	local times = Config.RIVER_MEDALS[riverId]
	if times == nil or type(time) ~= "number" or time ~= time or time <= 0 then
		return 0
	end
	for rank = #Medals.RANKS, 1, -1 do
		if time <= times[Medals.RANKS[rank]] then
			return rank
		end
	end
	return 0
end

-- Zapadka: stopień w `medals` może tylko wzrosnąć. Zwraca (stopień po zmianie, czy wzrósł).
function Medals.award(medals: { [string]: number }, riverId: string, time: any): (number, boolean)
	local held = medals[riverId] or 0
	local rank = Medals.medalFor(riverId, time)
	if rank <= held then
		return held, false
	end
	medals[riverId] = rank
	return rank, true
end

-- Następny cel po stopniu `rank`: (stopień, ile sekund brakuje czasowi `time`) albo nil, gdy nie ma czego zdobywać.
-- Brak zaokrąglamy w górę do dziesiątych, bo tak HUD pokazuje czas: gracz nie zobaczy „brakuje 0.0 s”.
function Medals.nextGoal(riverId: string, rank: number, time: number): (number?, number?)
	local times = Config.RIVER_MEDALS[riverId]
	local nextRank = rank + 1
	local key = Medals.RANKS[nextRank]
	if times == nil or key == nil then
		return nil, nil
	end
	return nextRank, math.max(math.ceil((time - times[key]) * 10) / 10, 0.1)
end

-- Migracja starego profilu: medale z dotychczasowych rekordów, potem schema = 1. Działa na danych po Reconcile
-- i jest idempotentna (dla TS: krok migracji bazy z numerem wersji). COSMETICS.md, sekcja 4.
function Medals.migrate(data: any)
	if data.schema ~= 0 then
		return
	end
	for riverId, best in data.bestTimes do
		Medals.award(data.medals, riverId, best)
	end
	data.schema = 1
end

-- 118 → "1:58", do pokazania progu. Progi to pełne sekundy, więc bez dziesiątych.
function Medals.clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Medals
