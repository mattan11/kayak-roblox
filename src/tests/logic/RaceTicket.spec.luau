-- Wpis wyścigu z MemoryStore: zły albo niepełny wpis nigdy nie może zepsuć startu serwera.

return function(t)
	local Config = require(t.shared.Config)
	local RaceTicket = require(t.server.RaceTicket)

	local function known(name: string): boolean
		return name == "Test"
	end

	t.describe("parse", function()
		t.it("poprawny wpis", function()
			local river, expected = RaceTicket.parse({ river = "Test", expected = 3 }, known)
			t.expect(river).toBe("Test")
			t.expect(expected).toBe(3)
		end)
		t.it("brak wpisu albo zły typ", function()
			for _, value in { "Test", 5, true } do
				local river, expected = RaceTicket.parse(value, known)
				t.expect(river).toBe(nil)
				t.expect(expected).toBe(nil)
			end
			t.expect((RaceTicket.parse(nil, known))).toBe(nil)
		end)
		t.it("nieznana rzeka nie psuje liczby graczy", function()
			local river, expected = RaceTicket.parse({ river = "Atlantis", expected = 2 }, known)
			t.expect(river).toBe(nil)
			t.expect(expected).toBe(2)
		end)
		t.it("tryb z wpisu, a stary lub zły wpis to wyścig", function()
			local function mode(value: any): any
				local _, _, result = RaceTicket.parse(value, known)
				return result
			end
			t.expect(mode({ river = "Test", expected = 2, mode = "battle" })).toBe("battle")
			t.expect(mode({ river = "Test", expected = 2 })).toBe("race")
			t.expect(mode({ river = "Test", expected = 2, mode = "royale" })).toBe("race")
			t.expect(mode(nil)).toBe(nil)
		end)
		t.it("brak wpisu: wyścig, a w Studio tryb z Config", function()
			t.expect(RaceTicket.resolveMode("battle", false)).toBe("battle")
			t.expect(RaceTicket.resolveMode("race", true)).toBe("race")
			t.expect(RaceTicket.resolveMode(nil, false)).toBe("race")
			t.expect(RaceTicket.resolveMode(nil, true)).toBe(Config.ACTIVE_MODE)
		end)
		t.it("tryb z wpisu, a stary lub zły wpis to wyścig", function()
			local function mode(value: any): any
				local _, _, result = RaceTicket.parse(value, known)
				return result
			end
			t.expect(mode({ river = "Test", expected = 2, mode = "battle" })).toBe("battle")
			t.expect(mode({ river = "Test", expected = 2 })).toBe("race")
			t.expect(mode({ river = "Test", expected = 2, mode = "royale" })).toBe("race")
			t.expect(mode(nil)).toBe(nil)
		end)
		t.it("brak wpisu: wyścig, a w Studio tryb z Config", function()
			t.expect(RaceTicket.resolveMode("battle", false)).toBe("battle")
			t.expect(RaceTicket.resolveMode("race", true)).toBe("race")
			t.expect(RaceTicket.resolveMode(nil, false)).toBe("race")
			t.expect(RaceTicket.resolveMode(nil, true)).toBe(Config.ACTIVE_MODE)
		end)
		t.it("Wodna bitwa: tryb z wpisu mimo braku pliku rzeki", function()
			local river, expected, mode = RaceTicket.parse({ river = "Arena", expected = 2, mode = "arena" }, known)
			t.expect(river).toBe(nil)
			t.expect(expected).toBe(2)
			t.expect(mode).toBe("arena")
			t.expect(RaceTicket.resolveMode(mode, false)).toBe("arena")
		end)
		t.it("liczba graczy poza zakresem jest ignorowana", function()
			for _, bad in { 0, -1, 1.5, Config.PIER_CAPACITY + 1, "3" } do
				local river, expected = RaceTicket.parse({ river = "Test", expected = bad }, known)
				t.expect(river).toBe("Test")
				t.expect(expected).toBe(nil)
			end
		end)
	end)
end
