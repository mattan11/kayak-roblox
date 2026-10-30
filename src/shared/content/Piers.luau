-- Pomosty wioski: po jednym na rzekę, ułożone łukiem na południowym brzegu jeziora. Czyste dane, jak rivers/*.luau.
-- Tablica w kolejności stanowisk: `for _, pier in Piers do`. (Dla TS: `export const piers: Pier[] = [...]`.)
--   id         stały identyfikator stanowiska, to samo co atrybut `PierId` na strefie kolejki
--   river      nazwa pliku z content/rivers; nil = zaślepka („Wkrótce”), bez strefy kolejki
--   label      napis na tablicy
--   difficulty "Łatwa" | "Średnia" | "Trudna"
--   color      kolor tablicy i kajaka-ozdoby
--   position   Vector2(x, z): początek pomostu na plaży
--   direction  Vector2 długości 1: kierunek w stronę wody

local Config = require(script.Parent.Parent.Config)

local EASY = Color3.fromRGB(62, 156, 92)
local MEDIUM = Color3.fromRGB(216, 150, 48)
local HARD = Color3.fromRGB(196, 66, 56)

-- Stanowisko leży na okręgu wokół środka jeziora; kąt 0° = południe (+Z), ujemny = zachód (−X).
local function station(id: string, angle: number, river: string?, label: string, difficulty: string, color: Color3)
	local radians = math.rad(angle)
	local outward = Vector2.new(math.sin(radians), math.cos(radians))
	local reach = Config.VILLAGE_LAKE_RADIUS + Config.PIER_START_ON_BEACH
	return {
		id = id,
		river = river,
		label = label,
		difficulty = difficulty,
		color = color,
		position = Vector2.new(0, Config.VILLAGE_LAKE_Z) + outward * reach,
		direction = -outward,
	}
end

return {
	station("easy1", -22, "Test", "Leśna Struga", "Łatwa", EASY), -- nazwa robocza, rzeka `Test` czeka na nazwę (VISION.md)
	station("easy2", -44, nil, "Wkrótce", "Łatwa", EASY),
	station("easy3", -66, nil, "Wkrótce", "Łatwa", EASY),
	station("medium1", 0, nil, "Wkrótce", "Średnia", MEDIUM),
	station("medium2", 22, nil, "Wkrótce", "Średnia", MEDIUM),
	station("hard1", 44, "Mountain", "Górski Potok", "Trudna", HARD),
	station("hard2", 66, nil, "Wkrótce", "Trudna", HARD),
}
