-- Katalog rzek wioski: 7 pozycji na planszy, w kolejności wyświetlania. Czyste dane, jak rivers/*.luau.
-- Tablica: `for _, entry in RiverCatalog do`. (Dla TS: `export const riverCatalog: RiverEntry[] = [...]`.)
--   id         stały identyfikator, nazwa pliku z content/rivers i rankingu `Times_<id>`
--   river      nazwa pliku z content/rivers
--   label      nazwa dla gracza
--   difficulty "Łatwa" | "Średnia" | "Trudna"
--   available  czy można na niej płynąć

local function open(id: string, label: string, difficulty: string)
	return { id = id, river = id, label = label, difficulty = difficulty, available = true }
end

return {
	open("Test", "Leśna Struga", "Łatwa"),
	open("Easy2", "Słoneczna Dolina", "Łatwa"),
	open("Easy3", "Piaskowa Łacha", "Łatwa"),
	open("Medium1", "Sosnowy Bór", "Średnia"),
	open("Medium2", "Czerwony Kanion", "Średnia"),
	open("Mountain", "Górski Potok", "Trudna"),
	open("Hard2", "Lodowy Żleb", "Trudna"),
}
