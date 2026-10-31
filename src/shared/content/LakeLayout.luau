-- Układ jeziora w wiosce: dane, które czytają serwer (punkt startu), klient (Lake.new w Session), świat (VillageWorld stawia
-- bryły) i nauka (LakeTutorial).
-- Współrzędne jak wszędzie: Vector2(x, z). Kurs w radianach: przód = (cos, sin), więc -π/2 to płynięcie w stronę -Z.
-- Bryły powstają z tych samych liczb co `obstacles`, więc to, co widać, i to, od czego kajak się odbija, nie może się rozjechać.
-- (Dla TS: plik JSON ze stałymi, a na dole jedna wyliczona tablica.)

local Config = require(script.Parent.Parent.Config)

export type Circle = { position: Vector2, radius: number }

local center = Vector2.new(0, Config.VILLAGE_LAKE_Z)
local spawn = center + Vector2.new(0, 75) -- południowa część jeziora: miejsce na naukę, daleko od strefy i boi
local zone: Circle = { position = center + Vector2.new(0, -130), radius = Config.VILLAGE_ZONE_RADIUS }

-- Boje do omijania, rozrzucone po jeziorze.
local buoys: { Circle } = {
	{ position = center + Vector2.new(-70, -60), radius = 3 },
	{ position = center + Vector2.new(-115, -10), radius = 3 },
	{ position = center + Vector2.new(-90, 60), radius = 3 },
	{ position = center + Vector2.new(125, -70), radius = 3 },
	{ position = center + Vector2.new(70, -100), radius = 3 },
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

local toZone = zone.position - spawn

return {
	center = center,
	radius = Config.VILLAGE_LAKE_RADIUS,
	spawn = spawn,
	heading = math.atan2(toZone.Y, toZone.X), -- dziób na strefę startu
	obstacles = obstacles, -- wszystko, co odbija kajak; ring strefy nie, bo przez niego się wpływa
	zone = zone,
	buoys = buoys,
	slalom = slalom,
}
