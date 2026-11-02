-- Logika wyglądu: gwiazdki z medali, odblokowania (zapadka, idempotentność), zakładanie, naprawa profilu, wygląd kajaka
-- oraz wspólny szablon profilu z migracją starych danych (PlayerProfile.TEMPLATE + prepare).

return function(t)
	local Config = require(t.shared.Config)
	local Cosmetics = require(t.shared.Cosmetics)
	local PlayerProfile = require(t.server.PlayerProfile)

	-- Głęboka kopia i scalenie z szablonem jak ProfileStore:Reconcile (brakujące klucze tekstowe, także w zagnieżdżonych tabelach).
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local result = {}
		for key, item in value do
			result[key] = copy(item)
		end
		return result
	end
	local function reconcile(target: any, template: any)
		for key, value in template do
			if type(key) == "string" then
				if target[key] == nil then
					target[key] = copy(value)
				elseif type(target[key]) == "table" and type(value) == "table" then
					reconcile(target[key], value)
				end
			end
		end
	end
	local function newProfile(data: any): any
		local profile = data or {}
		reconcile(profile, PlayerProfile.TEMPLATE)
		return profile
	end
	-- Medale tak, żeby dały `stars` gwiazdek (złoto po kolei na rzekach, reszta na ostatniej).
	local function medalsFor(stars: number): { [string]: number }
		local medals = {}
		for riverId in Config.RIVER_MEDALS do
			if stars <= 0 then
				break
			end
			local rank = math.min(stars, 3)
			medals[riverId] = rank
			stars -= rank
		end
		return medals
	end

	t.describe("stars", function()
		t.it("brąz 1, srebro 2, złoto 3, suma po rzekach", function()
			t.expect(Cosmetics.stars({})).toBe(0)
			t.expect(Cosmetics.stars({ Test = 1 })).toBe(1)
			t.expect(Cosmetics.stars({ Test = 2, Mountain = 3 })).toBe(5)
			t.expect(Cosmetics.stars(medalsFor(21))).toBe(21)
		end)

		t.it("śmieci, nieznane rzeki i stopnie spoza zakresu nie dają więcej", function()
			t.expect(Cosmetics.stars(nil)).toBe(0)
			t.expect(Cosmetics.stars("x")).toBe(0)
			t.expect(Cosmetics.stars({ Nieznana = 3 })).toBe(0)
			t.expect(Cosmetics.stars({ Test = 99 })).toBe(3)
			t.expect(Cosmetics.stars({ Test = -2 })).toBe(0)
			t.expect(Cosmetics.stars({ Test = "3" })).toBe(0)
			t.expect(Cosmetics.stars({ Test = 0 / 0 })).toBe(0)
		end)

		t.it("maxStars = 3 × liczba rzek z medalami", function()
			t.expect(Cosmetics.maxStars()).toBe(21)
		end)
	end)

	t.describe("isUnlocked i evaluate", function()
		t.it("próg gwiazdek: równy wystarcza, o jedną mniej nie", function()
			local duck = Cosmetics.item("kayak_duck")
			t.expect(Cosmetics.isUnlocked(duck, { medals = medalsFor(3) })).toBe(true)
			t.expect(Cosmetics.isUnlocked(duck, { medals = medalsFor(2) })).toBe(false)
			t.expect(Cosmetics.isUnlocked(Cosmetics.item("kayak_classic"), { medals = {} })).toBe(true)
			t.expect(Cosmetics.isUnlocked(nil, { medals = {} })).toBe(false)
		end)

		t.it("robux i nieznany rodzaj nigdy nie są nadawane za grę", function()
			local paid = { id = "x", slot = "kayak", unlock = { kind = "robux", productId = 1 } }
			t.expect(Cosmetics.isUnlocked(paid, { medals = medalsFor(21) })).toBe(false)
			t.expect(Cosmetics.isUnlocked({ unlock = { kind = "shop", price = 1 } }, { medals = medalsFor(21) })).toBe(false)
		end)

		t.it("nadaje należne, oznacza jako nowe i jest idempotentne", function()
			local data = newProfile({ medals = medalsFor(6) })
			local added = Cosmetics.evaluate(data, 100)
			local owned = data.cosmetics.owned
			t.expect(owned.kayak_duck ~= nil).toBe(true)
			t.expect(owned.kayak_shark ~= nil).toBe(true)
			t.expect(owned.kayak_rocket).toBe(nil)
			t.expect(owned.kayak_shark.via).toBe("play")
			t.expect(owned.kayak_shark.at).toBe(100)
			t.expect(data.cosmetics.unseen.kayak_duck).toBe(true)
			t.expect(owned.kayak_classic).toBe(nil) -- domyślne nie trafiają do profilu
			t.expect(#added > 0).toBe(true)
			t.expect(#Cosmetics.evaluate(data, 200)).toBe(0)
			t.expect(owned.kayak_shark.at).toBe(100)
		end)

		t.it("zapadka: spadek gwiazdek (np. zmiana progów) nie zabiera przedmiotów", function()
			local data = newProfile({ medals = medalsFor(21) })
			Cosmetics.evaluate(data)
			data.medals = {}
			Cosmetics.evaluate(data)
			t.expect(data.cosmetics.owned.kayak_dragon ~= nil).toBe(true)
			t.expect(Cosmetics.sanitize({ kayak = "kayak_dragon", paint = "paint_night" }, data.cosmetics.owned)).toBe(false)
		end)

		t.it("grantAll (Studio) daje wszystko bez znaczników Nowe", function()
			local data = newProfile()
			Cosmetics.grantAll(data)
			for _, slot in Cosmetics.SLOTS do
				for _, item in Cosmetics.list(slot) do
					t.expect(Cosmetics.owns(item, data.cosmetics.owned)).toBe(true)
				end
			end
			t.expect(next(data.cosmetics.unseen)).toBe(nil)
			t.expect(data.cosmetics.owned.kayak_dragon.via).toBe("grant")
		end)
	end)

	t.describe("canEquip i sanitize", function()
		local owned = { kayak_duck = { via = "play", at = 1 }, paint_lagoon = { via = "play", at = 1 } }

		t.it("pozwala na posiadane i domyślne we właściwym slocie", function()
			t.expect(Cosmetics.canEquip("kayak", "kayak_duck", owned)).toBe(true)
			t.expect(Cosmetics.canEquip("kayak", "kayak_classic", owned)).toBe(true)
			t.expect(Cosmetics.canEquip("paint", "paint_lagoon", owned)).toBe(true)
			t.expect(Cosmetics.canEquip("paint", "paint_auto", {})).toBe(true)
		end)

		t.it("odrzuca nieposiadane, obcy slot, nieznane id i śmieciowe typy", function()
			t.expect(Cosmetics.canEquip("kayak", "kayak_dragon", owned)).toBe(false)
			t.expect(Cosmetics.canEquip("paint", "kayak_duck", owned)).toBe(false)
			t.expect(Cosmetics.canEquip("kayak", "paint_lagoon", owned)).toBe(false)
			t.expect(Cosmetics.canEquip("kayak", "nie_ma", owned)).toBe(false)
			t.expect(Cosmetics.canEquip("helmet", "kayak_duck", owned)).toBe(false)
			t.expect(Cosmetics.canEquip(1, "kayak_duck", owned)).toBe(false)
			t.expect(Cosmetics.canEquip("kayak", { "kayak_duck" }, owned)).toBe(false)
			t.expect(Cosmetics.canEquip("kayak", nil, owned)).toBe(false)
			t.expect(Cosmetics.canEquip("kayak", "kayak_duck", nil)).toBe(false)
		end)

		t.it("naprawia złe sloty, zostawia dobre i nieznane sloty", function()
			local equipped: any = { kayak = "kayak_dragon", paint = "paint_lagoon", helmet = "helmet_red" }
			t.expect(Cosmetics.sanitize(equipped, owned)).toBe(true)
			t.expect(equipped.kayak).toBe("kayak_classic")
			t.expect(equipped.paint).toBe("paint_lagoon")
			t.expect(equipped.helmet).toBe("helmet_red")
			t.expect(Cosmetics.sanitize(equipped, owned)).toBe(false)

			local broken: any = { kayak = 5, paint = "kayak_duck" }
			Cosmetics.sanitize(broken, owned)
			t.expect(broken.kayak).toBe("kayak_classic")
			t.expect(broken.paint).toBe("paint_auto")
		end)
	end)

	t.describe("look", function()
		t.it("klasyk z kolorem auto z userId, jak przed szafką", function()
			local look = Cosmetics.look({ kayak = "kayak_classic", paint = "paint_auto" }, 7)
			t.expect(look.template).toBe("KayakClassic")
			t.expect(look.color).toBe(Cosmetics.AUTO_COLORS[7 % #Cosmetics.AUTO_COLORS + 1])
			t.expect(look.classicColor).toBe(look.color)
		end)

		t.it("klasyk z kolorem z katalogu", function()
			local look = Cosmetics.look({ kayak = "kayak_classic", paint = "paint_night" }, 7)
			t.expect(look.color).toBe(Cosmetics.item("paint_night").render.color)
		end)

		t.it("skórka z teksturą ma stały wygląd, ale niesie kolor na powrót do klasyka", function()
			local look = Cosmetics.look({ kayak = "kayak_dragon", paint = "paint_lagoon" }, 7)
			t.expect(look.template).toBe("KayakDragon")
			t.expect(look.color).toBe(nil)
			t.expect(look.classicColor).toBe(Cosmetics.item("paint_lagoon").render.color)
		end)

		t.it("śmieci w założeniu dają klasyka", function()
			t.expect(Cosmetics.look(nil, 1).template).toBe("KayakClassic")
			t.expect(Cosmetics.look({ kayak = "paint_night" }, 1).template).toBe("KayakClassic")
			t.expect(Cosmetics.look({ kayak = "nie_ma", paint = 3 }, 1).color).toBe(Cosmetics.AUTO_COLORS[2])
		end)
	end)

	t.describe("profil (PlayerProfile)", function()
		t.it("szablon: schema 0, puste medale, domyślne założenie dla każdego slotu", function()
			local template = PlayerProfile.TEMPLATE
			t.expect(template.schema).toBe(0)
			t.expect(next(template.medals)).toBe(nil)
			t.expect(next(template.cosmetics.owned)).toBe(nil)
			for _, slot in Cosmetics.SLOTS do
				t.expect(template.cosmetics.equipped[slot]).toBe(Cosmetics.default(slot))
			end
		end)

		t.it("stary profil (tylko bestTimes, races, wins): medale z rekordów, nagrody, rekordy nietknięte", function()
			local data = newProfile({ bestTimes = { Test = 120, Mountain = 190 }, races = 12, wins = 2 })
			PlayerProfile.prepare(data)
			t.expect(data.schema).toBe(1)
			t.expect(data.medals.Test).toBe(3)
			t.expect(data.medals.Mountain).toBe(1)
			t.expect(data.bestTimes.Test).toBe(120)
			t.expect(data.races).toBe(12)
			t.expect(data.wins).toBe(2)
			t.expect(data.cosmetics.owned.kayak_duck ~= nil).toBe(true) -- 4 gwiazdki
			t.expect(data.cosmetics.owned.kayak_shark).toBe(nil)
			t.expect(data.cosmetics.equipped.kayak).toBe("kayak_classic")
		end)

		t.it("drugie przygotowanie niczego nie zmienia, a zepsute założenie wraca do domyślnego", function()
			local data = newProfile({ bestTimes = { Test = 120 } })
			PlayerProfile.prepare(data)
			local medals = data.medals.Test
			data.cosmetics.equipped.kayak = "kayak_dragon" -- jak po ręcznej edycji albo błędzie
			PlayerProfile.prepare(data)
			t.expect(data.medals.Test).toBe(medals)
			t.expect(data.cosmetics.equipped.kayak).toBe("kayak_classic")
		end)

		t.it("prepare z grantAll (Studio) pozwala założyć smoka", function()
			local data = newProfile()
			PlayerProfile.prepare(data, true)
			data.cosmetics.equipped.kayak = "kayak_dragon"
			PlayerProfile.prepare(data, true)
			t.expect(data.cosmetics.equipped.kayak).toBe("kayak_dragon")
		end)
	end)
end
