-- Katalog wyglądu: skórki kajaków (slot `kayak`) i kolory klasyka (slot `paint`). Czyste dane, jak RiverCatalog.
-- Tablica w kolejności wyświetlania w szafce: `for _, item in CosmeticCatalog do`. Logika jest w Shared.Cosmetics.
-- (Dla TS: `export const cosmetics: CosmeticItem[] = [...]`, a `unlock` to unia z polem `kind`.)
--
-- Pola (spec odrzuca każde inne): id, slot, label, render, unlock, hidden, order.
--   id      stały identyfikator, trafia do profilu, więc NIGDY się nie zmienia
--   slot    "kayak" | "paint"
--   label   nazwa dla gracza
--   render  kajak: { kind = "model", template = nazwa w ReplicatedStorage.LookAssets, paintable = kolor działa?, swatch = kolor kafelka }
--           kolor: { kind = "color", color = Color3 } albo { kind = "auto" } (kolor z userId, jak przed szafką)
--   unlock  { kind = "default" }            ma każdy, nie trafia do profilu
--           { kind = "stars", min = N }     gwiazdki z medali (brąz 1, srebro 2, złoto 3 na każdej rzece), na zawsze
--           { kind = "robux", productId }   później; dziś nieobsługiwane, nadaje tylko serwerowy zakup
--   hidden  true = nie ma go w szafce (np. przyszłe pozycje)
--
-- Gwiazdek się nie wydaje: próg tylko odblokowuje. 7 rzek × 3 = 21 gwiazdek najwyżej.

local function kayak(id: string, label: string, template: string, swatch: Color3, minStars: number?)
	return {
		id = id,
		slot = "kayak",
		label = label,
		render = { kind = "model", template = template, paintable = minStars == nil, swatch = swatch },
		unlock = if minStars then { kind = "stars", min = minStars } else { kind = "default" },
	}
end

local function paint(id: string, label: string, color: Color3, minStars: number)
	return { id = id, slot = "paint", label = label, render = { kind = "color", color = color }, unlock = { kind = "stars", min = minStars } }
end

return {
	-- Kajaki. Skórki z teksturą mają stały wygląd: kolor ich nie zmienia (paintable = false).
	kayak("kayak_classic", "Klasyk", "KayakClassic", Color3.fromRGB(226, 84, 60)),
	kayak("kayak_round", "Pękaty", "KayakRound", Color3.fromRGB(255, 110, 20), 1),
	kayak("kayak_duck", "Kaczka", "KayakDuck", Color3.fromRGB(255, 214, 64), 3), -- docelowo za Robux (MONETIZATION.md), w v1 za gwiazdki
	kayak("kayak_racer", "Strzała", "KayakRacer", Color3.fromRGB(0, 110, 255), 4),
	kayak("kayak_shark", "Rekin", "KayakShark", Color3.fromRGB(110, 140, 165), 6),
	kayak("kayak_icebreaker", "Lodołamacz", "KayakIcebreaker", Color3.fromRGB(240, 244, 248), 8),
	kayak("kayak_rocket", "Rakieta", "KayakRocket", Color3.fromRGB(235, 235, 240), 10),
	kayak("kayak_neon", "Neon", "KayakNeon", Color3.fromRGB(70, 220, 230), 12), -- docelowo Premium za Robux, w v1 za gwiazdki
	kayak("kayak_phoenix", "Feniks", "KayakPhoenix", Color3.fromRGB(245, 120, 40), 14),
	kayak("kayak_gold", "Złoty Flisak", "KayakGold", Color3.fromRGB(255, 190, 30), 16),
	kayak("kayak_kraken", "Kraken", "KayakKraken", Color3.fromRGB(140, 70, 170), 18),
	kayak("kayak_ice_dragon", "Lodowy Smok", "KayakIceDragon", Color3.fromRGB(170, 220, 245), 20), -- docelowo Premium za Robux
	kayak("kayak_dragon", "Smok", "KayakDragon", Color3.fromRGB(60, 160, 90), 21),

	-- Kolory klasyka: tanie progi, pierwszy kolor od razu, kolejne po pierwszych medalach.
	{ id = "paint_auto", slot = "paint", label = "Barwa załogi", render = { kind = "auto" }, unlock = { kind = "default" } },
	paint("paint_sunset", "Zachód słońca", Color3.fromRGB(244, 128, 44), 0),
	paint("paint_lagoon", "Laguna", Color3.fromRGB(40, 190, 190), 1),
	paint("paint_forest", "Las", Color3.fromRGB(60, 140, 70), 1),
	paint("paint_lemon", "Cytryna", Color3.fromRGB(245, 220, 60), 2),
	paint("paint_berry", "Jagoda", Color3.fromRGB(120, 70, 190), 3),
	paint("paint_snow", "Śnieg", Color3.fromRGB(240, 244, 248), 4),
	paint("paint_night", "Noc", Color3.fromRGB(40, 48, 70), 5),
}
