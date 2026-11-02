-- Wygląd kajaka: czysta logika bez usług Robloxa (testy: logic/Cosmetics.spec). Dane są w content/CosmeticCatalog.
-- Serwer decyduje o odblokowaniu i założeniu, klient używa tych funkcji tylko do wyświetlania szafki (COSMETICS.md).
-- `data` to profil gracza z ProfileStore (Shared nie zna ProfileStore, dostaje zwykłą tabelę):
--   data.medals[riverId] = 1..3, data.cosmetics = { owned = { [id] = { via, at } }, unseen = { [id] = true }, equipped = { [slot] = id } }
-- (Dla TS: moduł z czystymi funkcjami nad stanem, jak reducer bez Reduxa.)

local Config = require(script.Parent.Config)
local CosmeticCatalog = require(script.Parent.content.CosmeticCatalog)

local Cosmetics = {}

-- Sloty obsługiwane w v1. Kask, kamizelka, wiosło i ślad dojdą później (COSMETICS.md, sekcja 2).
Cosmetics.SLOTS = { "kayak", "paint" }
-- Dzisiejsze kolory kajaków, wybierane z userId: to `paint_auto`, czyli wygląd sprzed szafki.
Cosmetics.AUTO_COLORS = {
	Color3.fromRGB(226, 84, 60),
	Color3.fromRGB(240, 170, 50),
	Color3.fromRGB(62, 150, 210),
	Color3.fromRGB(96, 190, 110),
	Color3.fromRGB(190, 90, 200),
	Color3.fromRGB(240, 110, 150),
}
Cosmetics.STARS_PER_RIVER = 3 -- złoto = 3 gwiazdki

-- id → pozycja i slot → domyślne id. Liczone raz przy wczytaniu modułu (dla TS: `new Map(catalog.map(...))`).
local byId: { [string]: any } = {}
local defaults: { [string]: string } = {}
for _, item in CosmeticCatalog do
	byId[item.id] = item
	if item.unlock.kind == "default" and defaults[item.slot] == nil then
		defaults[item.slot] = item.id
	end
end

function Cosmetics.item(id: any): any
	return if type(id) == "string" then byId[id] else nil
end

function Cosmetics.default(slot: string): string
	return defaults[slot]
end

-- Domyślne założenie: szablon `equipped` dla profilu (kopia, bo ProfileStore kopiuje szablon, a testy go zmieniają).
function Cosmetics.defaultEquipped(): { [string]: string }
	local equipped = {}
	for _, slot in Cosmetics.SLOTS do
		equipped[slot] = defaults[slot]
	end
	return equipped
end

-- Gwiazdki z medali: na każdej rzece z Config.RIVER_MEDALS najwyższy medal (brąz 1, srebro 2, złoto 3).
-- Śmieci w profilu (zły typ, stopień spoza 0..3, nieznana rzeka) nie dają gwiazdek.
function Cosmetics.stars(medals: any): number
	if type(medals) ~= "table" then
		return 0
	end
	local total = 0
	for riverId in Config.RIVER_MEDALS do
		local rank = medals[riverId]
		if type(rank) == "number" and rank == rank then
			total += math.clamp(math.floor(rank), 0, Cosmetics.STARS_PER_RIVER)
		end
	end
	return total
end

function Cosmetics.maxStars(): number
	local rivers = 0
	for _ in Config.RIVER_MEDALS do
		rivers += 1
	end
	return rivers * Cosmetics.STARS_PER_RIVER
end

-- Czy warunek pozycji jest spełniony. `robux` (i każdy nieznany rodzaj) nigdy: nadaje go tylko zakup na serwerze.
function Cosmetics.isUnlocked(item: any, data: any): boolean
	local unlock = item and item.unlock
	if unlock == nil then
		return false
	elseif unlock.kind == "default" then
		return true
	elseif unlock.kind == "stars" then
		return Cosmetics.stars(data and data.medals) >= unlock.min
	end
	return false
end

-- Czy gracz ma tę pozycję: domyślną ma każdy, resztę musi mieć w `owned`.
function Cosmetics.owns(item: any, owned: any): boolean
	if item == nil then
		return false
	end
	return item.unlock.kind == "default" or (type(owned) == "table" and owned[item.id] ~= nil)
end

-- Nadaje należne pozycje (za gwiazdki) i oznacza je jako nowe. Idempotentne: druga runda nic nie zmienia, a raz nadane
-- zostaje na zawsze, także po podniesieniu progu (zapadka). Zwraca listę nowych id.
function Cosmetics.evaluate(data: any, now: number?): { string }
	local cosmetics = data.cosmetics
	local added = {}
	for _, item in CosmeticCatalog do
		if item.unlock.kind ~= "default" and cosmetics.owned[item.id] == nil and Cosmetics.isUnlocked(item, data) then
			cosmetics.owned[item.id] = { via = "play", at = now or os.time() }
			cosmetics.unseen[item.id] = true
			table.insert(added, item.id)
		end
	end
	return added
end

-- Tylko Studio (Config.COSMETICS_STUDIO_ALL): wszystko, poza ukrytymi, bez znaczników „Nowe”.
function Cosmetics.grantAll(data: any, now: number?)
	for _, item in CosmeticCatalog do
		if item.unlock.kind ~= "default" and not item.hidden and data.cosmetics.owned[item.id] == nil then
			data.cosmetics.owned[item.id] = { via = "grant", at = now or os.time() }
		end
	end
end

-- Czy można założyć `itemId` w `slot`. Argumenty przychodzą od klienta, więc najpierw typy.
function Cosmetics.canEquip(slot: any, itemId: any, owned: any): boolean
	if type(slot) ~= "string" or type(itemId) ~= "string" then
		return false
	end
	local item = byId[itemId]
	return item ~= nil and item.slot == slot and not item.hidden and defaults[slot] ~= nil and Cosmetics.owns(item, owned)
end

-- Naprawia założenie: slot z nieznanym, nieposiadanym, ukrytym albo źle przypisanym przedmiotem wraca do domyślnego.
-- Nieznane sloty zostają (mógł je zapisać nowszy serwer). Zwraca true, gdy coś zmieniło.
function Cosmetics.sanitize(equipped: { [string]: any }, owned: any): boolean
	local changed = false
	for _, slot in Cosmetics.SLOTS do
		if not Cosmetics.canEquip(slot, equipped[slot], owned) then
			equipped[slot] = defaults[slot]
			changed = true
		end
	end
	return changed
end

-- Kolor z pozycji koloru: `auto` z userId (jak przed szafką), reszta z katalogu.
local function paintColor(paintId: any, userId: number): Color3
	local item = byId[paintId]
	if item and item.slot == "paint" and item.render.kind == "color" then
		return item.render.color
	end
	return Cosmetics.AUTO_COLORS[userId % #Cosmetics.AUTO_COLORS + 1]
end

export type Look = {
	template: string, -- szablon w ReplicatedStorage.LookAssets
	color: Color3?, -- kolor części Paint; nil = skórka ma stały wygląd
	classicColor: Color3, -- kolor na wypadek powrotu do klasyka (brak szablonu skórki)
}

-- Wygląd do zbudowania z założenia. Śmieci w `equipped` dają klasyka (sanitize i tak to naprawia na serwerze).
function Cosmetics.look(equipped: any, userId: number): Look
	equipped = if type(equipped) == "table" then equipped else {}
	local kayakItem = byId[equipped.kayak]
	if kayakItem == nil or kayakItem.slot ~= "kayak" then
		kayakItem = byId[defaults.kayak]
	end
	local color = paintColor(equipped.paint, userId)
	return {
		template = kayakItem.render.template,
		color = if kayakItem.render.paintable then color else nil,
		classicColor = color,
	}
end

-- Pozycje slotu widoczne w szafce, w kolejności katalogu.
function Cosmetics.list(slot: string): { any }
	local items = {}
	for _, item in CosmeticCatalog do
		if item.slot == slot and not item.hidden then
			table.insert(items, item)
		end
	end
	return items
end

return Cosmetics
