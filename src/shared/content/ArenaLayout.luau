-- Układ jeziora Wodnej bitwy: dane, które czytają serwer (Lake, ArenaBuilder, ArenaRules) i klient (Lake.new w Session).
-- Pola jak w LakeLayout, ale bez `spawn` i `heading`: `Lake.new(ArenaLayout)` ich nie potrzebuje, dopóki nikt nie woła Lake:spawnPoint.
-- Współrzędne: Vector2(x, z).
-- Bryły powstają z tych samych liczb co `obstacles`, więc to, co widać, i to, od czego kajak się odbija, nie może się rozjechać.
-- (Dla TS: plik JSON ze stałymi, a na dole jedna wyliczona tablica.)

local Config = require(script.Parent.Parent.Config)

export type Circle = { position: Vector2, radius: number }

local center = Vector2.zero

-- Wyspy to osłona w drodze do środka, poza osiami startu, żeby żaden kajak nie zaczynał z dziobem w brzegu.
local islands: { Circle } = {
	{ position = center + Vector2.new(68, 68), radius = 22 },
	{ position = center + Vector2.new(-72, 62), radius = 18 },
	{ position = center + Vector2.new(-62, -72), radius = 24 },
	{ position = center + Vector2.new(74, -64), radius = 19 },
}

-- Skały na końcową fazę: strefa kończy na 40 studs, więc środek zostaje prawie otwarty.
local rocks: { Circle } = {
	{ position = center, radius = 6 },
	{ position = center + Vector2.new(0, 62), radius = 5 },
	{ position = center + Vector2.new(0, -62), radius = 5 },
	{ position = center + Vector2.new(62, 0), radius = 5 },
	{ position = center + Vector2.new(-62, 0), radius = 5 },
	{ position = center + Vector2.new(0, 118), radius = 4 },
	{ position = center + Vector2.new(118, 0), radius = 4 },
	{ position = center + Vector2.new(-118, 0), radius = 4 },
	{ position = center + Vector2.new(0, -118), radius = 4 },
}

local obstacles: { Circle } = table.clone(islands)
table.move(rocks, 1, #rocks, #obstacles + 1, obstacles)

return {
	center = center,
	radius = Config.ARENA_RADIUS,
	spawnRing = Config.ARENA_SPAWN_RING, -- okrąg miejsc startowych; miejsca liczy ArenaRules.spawnPoint, serwer sam stawia kajaki
	obstacles = obstacles, -- wszystko, co odbija kajak
	islands = islands,
	rocks = rocks,
}
