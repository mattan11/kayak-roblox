-- Katalog rzek wioski: 7 pozycji na planszy, w kolejności wyświetlania. Czyste dane, jak rivers/*.luau.
-- Tablica: `for _, entry in RiverCatalog do`. (Dla TS: `export const riverCatalog: RiverEntry[] = [...]`.)
--   id         stały identyfikator; przy dostępnej rzece to nazwa pliku z content/rivers
--   river      nazwa pliku z content/rivers; nil = rzeki jeszcze nie ma (`available = false`)
--   label      nazwa dla gracza
--   difficulty "Łatwa" | "Średnia" | "Trudna"
--   available  czy można na niej płynąć

local function open(id: string, label: string, difficulty: string)
	return { id = id, river = id, label = label, difficulty = difficulty, available = true }
end

local function soon(id: string, difficulty: string)
	return { id = id, river = nil, label = "Wkrótce", difficulty = difficulty, available = false }
end

return {
	open("Test", "Leśna Struga", "Łatwa"), -- nazwa robocza, rzeka `Test` czeka na nazwę (VISION.md)
	soon("Easy2", "Łatwa"),
	soon("Easy3", "Łatwa"),
	soon("Medium1", "Średnia"),
	soon("Medium2", "Średnia"),
	open("Mountain", "Górski Potok", "Trudna"),
	soon("Hard2", "Trudna"),
}
