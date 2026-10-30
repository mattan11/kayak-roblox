-- Teksty i liczby HUD-a.

return function(t)
	local RaceFormat = require(t.client.logic.RaceFormat)

	t.describe("time", function()
		t.it("formatuje minuty, sekundy, dziesiąte", function()
			t.expect(RaceFormat.time(83.45)).toBe("1:23.4")
			t.expect(RaceFormat.time(5)).toBe("0:05.0")
			t.expect(RaceFormat.time(600)).toBe("10:00.0")
		end)
		t.it("brak czasu", function()
			t.expect(RaceFormat.time(nil)).toBe("–:––")
			t.expect(RaceFormat.time(-1)).toBe("–:––")
		end)
	end)

	t.describe("progress i place", function()
		t.it("postęp obcięty do 0..1", function()
			t.expect(RaceFormat.progress(5, 10, 110)).toBe(0)
			t.expect(RaceFormat.progress(60, 10, 110)).toBe(0.5)
			t.expect(RaceFormat.progress(500, 10, 110)).toBe(1)
		end)
		t.it("miejsce liczy tylko aktualne pozycje tablicy", function()
			local others = { 100, 300, 999 }
			t.expect(RaceFormat.place(200, others, 2)).toBe(2)
			t.expect(RaceFormat.place(200, others, 3)).toBe(3)
			t.expect(RaceFormat.place(200, others, 0)).toBe(1)
		end)
	end)

	t.describe("parseTop", function()
		t.it("znosi brak i śmieci", function()
			t.expect(#RaceFormat.parseTop(nil)).toBe(0)
			t.expect(#RaceFormat.parseTop("x")).toBe(0)
			t.expect(#RaceFormat.parseTop({ { name = "a" }, 5 })).toBe(0)
		end)
		t.it("czyta listę i ucina do 10", function()
			local rows = {}
			for i = 1, 15 do
				rows[i] = { userId = i, name = "g" .. i, time = 100 + i }
			end
			local top = RaceFormat.parseTop(rows)
			t.expect(#top).toBe(10)
			t.expect(top[1].name).toBe("g1")
			t.expect(top[1].userId).toBe(1)
		end)
	end)
end
