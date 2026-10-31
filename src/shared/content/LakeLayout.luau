-- Układ jeziora w wiosce: dane, które czytają serwer (punkt startu), klient (Lake.new w Session), świat (VillageWorld stawia
-- bryły) i nauka (LakeTutorial).
-- Współrzędne jak wszędzie: Vector2(x, z). Kurs w radianach: przód = (cos, sin), więc -π/2 to płynięcie w stronę -Z.
-- Bryły powstają z tych samych liczb co `obstacles`, więc to, co widać, i to, od czego kajak się odbija, nie może się rozjechać.
-- Trzy strefy leżą po północnej stronie, a tablica każdej stoi na plaży dokładnie za ringiem, patrząc od środka jeziora.
-- (Dla TS: plik JSON ze stałymi, a na dole jedna wyliczona tablica.)

local Config = require(script.Parent.Parent.Config)

export type Circle = { position: Vector2, radius: number }
-- `mode` to tryb kolejki (MatchService, atrybut Mode na QueueZone), `sign` to środek tablicy z napisem `label`.
export type Zone = { id: string, mode: string, label: string, color: Color3, position: Vector2, radius: number, sign: Vector2 }

local SIGN_DISTANCE = 178 -- tablice stref od środka jeziora: na plaży, zaraz za linią wody
local SIGN_WIDTH = 24
local SIGN_HEIGHT = 10

local center = Vector2.new(0, Config.VILLAGE_LAKE_Z)
local spawn = center + Vector2.new(0, 75) -- południowa część jeziora: miejsce na naukę, daleko od stref i boi

local function zone(id: string, label: string, color: Color3, offset: Vector2): Zone
	local position = center + offset
	return {
		id = id,
		mode = id,
		label = label,
		color = color,
		position = position,
		radius = Config.VILLAGE_ZONE_RADIUS,
		sign = center + offset.Unit * SIGN_DISTANCE,
	}
end

local zones: { Zone } = {
	zone("race", "Wyścig", Color3.fromRGB(255, 214, 40), Vector2.new(0, -130)),
	zone("battle", "Bitwa", Color3.fromRGB(224, 60, 52), Vector2.new(-68, -112)),
	zone("arena", "Wodna bitwa", Color3.fromRGB(56, 140, 245), Vector2.new(68, -112)),
}

-- Boje do omijania, rozrzucone po jeziorze.
local buoys: { Circle } = {
	{ position = center + Vector2.new(-70, -60), radius = 3 },
	{ position = center + Vector2.new(-115, -10), radius = 3 },
	{ position = center + Vector2.new(-90, 60), radius = 3 },
	{ position = center + Vector2.new(125, -70), radius = 3 },
	{ position = center + Vector2.new(40, -70), radius = 3 },
}

-- Slalom treningowy po wschodniej stronie: boje na zmianę, z południa na północ.
local slalom: { Circle } = {
	{ position = center + Vector2.new(70, 60), radius = 1.5 },
	{ position = center + Vector2.new(100, 40), radius = 1.5 },
	{ position = center + Vector2.new(70, 20), radius = 1.5 },
	{ position = center + Vector2.new(100, 0), radius = 1.5 },
	{ position = center + Vector2.new(70, -20), radius = 1.5 },
	{ position = center + Vector2.new(100, -40), radius = 1.5 },
}

local obstacles: { Circle } = table.clone(buoys)
table.move(slalom, 1, #slalom, #obstacles + 1, obstacles)

local raceZone = zones[1] -- `zone` poniżej to jej alias: nauka prowadzi do strefy wyścigu
local toZone = raceZone.position - spawn

return {
	center = center,
	radius = Config.VILLAGE_LAKE_RADIUS,
	spawn = spawn,
	heading = math.atan2(toZone.Y, toZone.X), -- dziób na strefę wyścigu
	obstacles = obstacles, -- wszystko, co odbija kajak; ringi stref nie, bo przez nie się wpływa
	zones = zones,
	zone = raceZone,
	signWidth = SIGN_WIDTH,
	signHeight = SIGN_HEIGHT,
	buoys = buoys,
	slalom = slalom,
}
