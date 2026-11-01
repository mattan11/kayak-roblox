-- Medale: progi, granice czasów, zapadka, następny cel i migracja profilu.

return function(t)
	local Config = require(t.shared.Config)
	local Medals = require(t.shared.Medals)
	local RiverCatalog = require(t.shared.content.RiverCatalog)

	t.describe("Config.RIVER_MEDALS", function()
		t.it("każda dostępna rzeka ma czasy, a złoto < srebro < brąz", function()
			for _, entry in RiverCatalog do
				if entry.available then
					local times = Config.RIVER_MEDALS[entry.river]
					t.expect(times ~= nil).toBe(true)
					t.expect(times.gold).toBeLessThan(times.silver)
					t.expect(times.silver).toBeLessThan(times.bronze)
				end
			end
		end)
	end)

	t.describe("medalFor", function()
		t.it("czas równy progowi daje medal, o włos wolniejszy już nie", function()
			t.expect(Medals.medalFor("Test", 123)).toBe(3)
			t.expect(Medals.medalFor("Test", 123.01)).toBe(2)
			t.expect(Medals.medalFor("Test", 135)).toBe(2)
			t.expect(Medals.medalFor("Test", 135.01)).toBe(1)
			t.expect(Medals.medalFor("Test", 156)).toBe(1)
			t.expect(Medals.medalFor("Test", 156.01)).toBe(0)
		end)

		t.it("każda rzeka ma własne progi", function()
			t.expect(Medals.medalFor("Mountain", 152)).toBe(3)
			t.expect(Medals.medalFor("Mountain", 168)).toBe(2)
			t.expect(Medals.medalFor("Mountain", 197)).toBe(1)
			t.expect(Medals.medalFor("Mountain", 198)).toBe(0)
		end)

		t.it("rzeka bez wpisu i śmieciowe czasy nie dają medalu", function()
			t.expect(Medals.medalFor("Nieznana", 1)).toBe(0)
			t.expect(Medals.medalFor("Test", nil)).toBe(0)
			t.expect(Medals.medalFor("Test", "100")).toBe(0)
			t.expect(Medals.medalFor("Test", 0 / 0)).toBe(0)
			t.expect(Medals.medalFor("Test", 0)).toBe(0)
			t.expect(Medals.medalFor("Test", -5)).toBe(0)
		end)
	end)

	t.describe("award (zapadka)", function()
		t.it("nadaje pierwszy medal i podnosi stopień", function()
			local medals = {}
			local rank, isNew = Medals.award(medals, "Test", 150)
			t.expect(rank).toBe(1)
			t.expect(isNew).toBe(true)
			rank, isNew = Medals.award(medals, "Test", 110)
			t.expect(rank).toBe(3)
			t.expect(isNew).toBe(true)
			t.expect(medals.Test).toBe(3)
		end)

		t.it("gorszy i taki sam przejazd niczego nie zmieniają", function()
			local medals = { Test = 2 }
			local rank, isNew = Medals.award(medals, "Test", 150)
			t.expect(rank).toBe(2)
			t.expect(isNew).toBe(false)
			rank, isNew = Medals.award(medals, "Test", 130)
			t.expect(rank).toBe(2)
			t.expect(isNew).toBe(false)
			t.expect(medals.Test).toBe(2)
		end)

		t.it("przejazd bez medalu nie tworzy wpisu", function()
			local medals = {}
			local rank, isNew = Medals.award(medals, "Test", 200)
			t.expect(rank).toBe(0)
			t.expect(isNew).toBe(false)
			t.expect(medals.Test).toBe(nil)
		end)

		t.it("medal zostaje po zaostrzeniu progu", function()
			local medals = { Test = 3 } -- zdobyty przy dawnych, luźniejszych progach
			Medals.award(medals, "Test", 200)
			t.expect(medals.Test).toBe(3)
		end)
	end)

	t.describe("nextGoal", function()
		t.it("bez medalu celem jest brąz", function()
			local rank, missing = Medals.nextGoal("Test", 0, 170)
			t.expect(rank).toBe(1)
			t.expect(missing).toBeCloseTo(14)
		end)

		t.it("brak zaokrąglany w górę do dziesiątych", function()
			local rank, missing = Medals.nextGoal("Test", 2, 123.04)
			t.expect(rank).toBe(3)
			t.expect(missing).toBeCloseTo(0.1)
			_, missing = Medals.nextGoal("Test", 1, 137.21)
			t.expect(missing).toBeCloseTo(2.3)
		end)

		t.it("po złocie i na rzece bez wpisu nie ma celu", function()
			t.expect(Medals.nextGoal("Test", 3, 100)).toBe(nil)
			t.expect(Medals.nextGoal("Nieznana", 0, 100)).toBe(nil)
		end)
	end)

	t.describe("migrate", function()
		-- Stary profil po Reconcile: nowe pola mają wartości z szablonu.
		local function oldProfile(bestTimes: { [string]: any })
			return { bestTimes = bestTimes, races = 7, wins = 2, schema = 0, medals = {} }
		end

		t.it("liczy medale z rekordów i ustawia schema = 1", function()
			local data = oldProfile({ Test = 113, Mountain = 190, Stara = 50 })
			Medals.migrate(data)
			t.expect(data.schema).toBe(1)
			t.expect(data.medals.Test).toBe(3)
			t.expect(data.medals.Mountain).toBe(1)
			t.expect(data.medals.Stara).toBe(nil)
		end)

		t.it("nie rusza rekordów ani liczników", function()
			local data = oldProfile({ Test = 113 })
			Medals.migrate(data)
			t.expect(data.bestTimes.Test).toBe(113)
			t.expect(data.races).toBe(7)
			t.expect(data.wins).toBe(2)
		end)

		t.it("dwukrotna migracja daje ten sam wynik", function()
			local data = oldProfile({ Test = 113 })
			Medals.migrate(data)
			data.bestTimes.Test = 150 -- gdyby liczyła się drugi raz, to i tak nie może obniżyć
			data.medals.Mountain = 2 -- medal zdobyty po migracji
			Medals.migrate(data)
			t.expect(data.medals.Test).toBe(3)
			t.expect(data.medals.Mountain).toBe(2)
			t.expect(data.schema).toBe(1)
		end)

		t.it("nowy gracz bez rekordów przechodzi bez medali", function()
			local data = oldProfile({})
			Medals.migrate(data)
			t.expect(data.schema).toBe(1)
			t.expect(next(data.medals)).toBe(nil)
		end)

		t.it("profil już zmigrowany zostaje bez zmian", function()
			local data = { bestTimes = { Test = 113 }, schema = 1, medals = {} }
			Medals.migrate(data)
			t.expect(data.medals.Test).toBe(nil) -- profil po migracji: medale zmienia tylko award
		end)
	end)

	t.describe("clock", function()
		t.it("zapisuje próg jako m:ss", function()
			t.expect(Medals.clock(118)).toBe("1:58")
			t.expect(Medals.clock(145)).toBe("2:25")
			t.expect(Medals.clock(180)).toBe("3:00")
		end)
	end)
end
