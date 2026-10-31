-- Ślad ducha: próbkowanie, kompresja do liczb całkowitych, walidacja i interpolacja.

return function(t)
	local Config = require(t.shared.Config)
	local GhostTrack = require(t.shared.GhostTrack)

	-- Przejazd po prostej: 2 studs/s wzdłuż X, próbka co GHOST_SAMPLE_INTERVAL.
	local function straightRun(samples: number)
		local recorder = GhostTrack.newRecorder()
		for i = 0, samples - 1 do
			local time = i * Config.GHOST_SAMPLE_INTERVAL
			GhostTrack.record(recorder, time, time * 2, 0.3, -5, 0, false)
		end
		return recorder
	end

	t.describe("GhostTrack próbkowanie", function()
		t.it("z odczytów co 0,1 s zostaje próbka co GHOST_SAMPLE_INTERVAL", function()
			local recorder = GhostTrack.newRecorder()
			for i = 0, 100 do
				GhostTrack.record(recorder, i * 0.1, 0, 0, 0, 0, false)
			end
			t.expect(recorder.count).toBe(math.floor(10 / Config.GHOST_SAMPLE_INTERVAL + 0.5) + 1)
		end)
		t.it("force dokłada punkt na mecie, ale nie cofa czasu", function()
			local recorder = straightRun(2)
			local last = recorder.lastTime / Config.GHOST_TIME_SCALE
			t.expect(GhostTrack.record(recorder, last + 0.1, 1, 1, 1, 0, true)).toBe(true)
			t.expect(GhostTrack.record(recorder, last + 0.1, 1, 1, 1, 0, true)).toBe(false)
		end)
		t.it("nie przekracza limitu próbek", function()
			local recorder = GhostTrack.newRecorder()
			for i = 0, Config.GHOST_MAX_SAMPLES + 5 do
				GhostTrack.record(recorder, i, 0, 0, 0, 0, false)
			end
			t.expect(recorder.count).toBe(Config.GHOST_MAX_SAMPLES)
		end)
		t.it("limit próbek mieści najdłuższy wyścig z punktem na mecie", function()
			local longest = math.ceil(Config.RACE_TIME_LIMIT / Config.GHOST_SAMPLE_INTERVAL) + 2
			t.expect(Config.GHOST_MAX_SAMPLES >= longest).toBe(true)
		end)
	end)

	t.describe("GhostTrack zapis", function()
		t.it("trzyma tylko liczby całkowite i przechodzi walidację", function()
			local recorder = GhostTrack.newRecorder()
			GhostTrack.record(recorder, 0.123, 10.26, 0.31, -7.77, -2.5, false)
			GhostTrack.record(recorder, 0.8, 11.5, -12.04, -8, 3.1, false)
			local track = GhostTrack.finish(recorder, 800, 42)
			t.expect(track ~= nil).toBe(true)
			for _, value in (track :: any).data do
				t.expect(math.floor(value)).toBe(value)
			end
			t.expect(GhostTrack.validate(track)).toBe(true)
		end)
		t.it("odrzuca nagranie z jedną próbką", function()
			t.expect(GhostTrack.finish(straightRun(1), 100, 42)).toBe(nil)
		end)
		t.it("odrzuca nagranie z NaN", function()
			local recorder = straightRun(2)
			GhostTrack.record(recorder, 60, 0 / 0, 0, 0, 0, false)
			t.expect(GhostTrack.finish(recorder, 60000, 42)).toBe(nil)
		end)
		t.it("najgorszy przypadek mieści się w GHOST_MAX_BYTES, a limit jest daleko od 4 MB", function()
			local track = { v = 1, ms = 300000, userId = 42, data = {} }
			local coord = -Config.GHOST_MAX_COORD * Config.GHOST_POSITION_SCALE
			for i = 1, Config.GHOST_MAX_SAMPLES do
				for _, value in { Config.RACE_TIME_LIMIT * Config.GHOST_TIME_SCALE + i, coord, coord, coord, Config.GHOST_HEADING_STEPS - 1 } do
					table.insert(track.data, value)
				end
			end
			t.expect(GhostTrack.byteSize(track) <= Config.GHOST_MAX_BYTES).toBe(true)
			t.expect(Config.GHOST_MAX_BYTES).toBeLessThan(4 * 1024 * 1024)
		end)
		t.it("nadmiernie duży zapis nie przechodzi", function()
			local original = Config.GHOST_MAX_BYTES
			Config.GHOST_MAX_BYTES = 10
			local track = GhostTrack.finish(straightRun(3), 1000, 42)
			Config.GHOST_MAX_BYTES = original
			t.expect(track).toBe(nil)
		end)
	end)

	t.describe("GhostTrack walidacja", function()
		local function good()
			local recorder = straightRun(3)
			return { v = 1, ms = 1000, userId = 42, data = recorder.data }
		end
		t.it("przyjmuje poprawny ślad", function()
			t.expect(GhostTrack.validate(good())).toBe(true)
		end)
		t.it("odrzuca złe typy i wersję", function()
			t.expect(GhostTrack.validate(nil)).toBe(false)
			t.expect(GhostTrack.validate("ślad")).toBe(false)
			local track = good()
			track.v = 99
			t.expect(GhostTrack.validate(track)).toBe(false)
		end)
		t.it("odrzuca czas nierosnący", function()
			local track = good()
			track.data[6] = track.data[1]
			t.expect(GhostTrack.validate(track)).toBe(false)
		end)
		t.it("odrzuca niepełną próbkę, ułamek i pozycję poza światem", function()
			local cut = good()
			table.remove(cut.data)
			t.expect(GhostTrack.validate(cut)).toBe(false)
			local fraction = good()
			fraction.data[2] = 1.5
			t.expect(GhostTrack.validate(fraction)).toBe(false)
			local far = good()
			far.data[2] = (Config.GHOST_MAX_COORD + 1) * Config.GHOST_POSITION_SCALE
			t.expect(GhostTrack.validate(far)).toBe(false)
		end)
		t.it("odrzuca kurs poza zakresem i wartość nie-liczbę", function()
			local heading = good()
			heading.data[5] = Config.GHOST_HEADING_STEPS
			t.expect(GhostTrack.validate(heading)).toBe(false)
			local text = good() :: any
			text.data[3] = "1"
			t.expect(GhostTrack.validate(text)).toBe(false)
		end)
	end)

	t.describe("GhostTrack odtwarzanie", function()
		local function track()
			return GhostTrack.finish(straightRun(5), 2000, 42) :: any
		end
		t.it("interpoluje między próbkami", function()
			local x, y, z = GhostTrack.evaluate(track(), Config.GHOST_SAMPLE_INTERVAL * 1.5, 1)
			t.expect(x).toBeCloseTo(Config.GHOST_SAMPLE_INTERVAL * 3, 0.11)
			t.expect(y).toBeCloseTo(0.3, 0.06)
			t.expect(z).toBeCloseTo(-5, 0.06)
		end)
		t.it("przed startem i po końcu stoi na skrajnej próbce", function()
			local data = track()
			t.expect((GhostTrack.evaluate(data, -3, 1))).toBeCloseTo(0, 0.01)
			local last = 4 * Config.GHOST_SAMPLE_INTERVAL * 2
			t.expect((GhostTrack.evaluate(data, 999, 1))).toBeCloseTo(last, 0.11)
		end)
		t.it("cursor idzie do przodu i cofa się przy nowym przejeździe", function()
			local data = track()
			local _, _, _, _, cursor = GhostTrack.evaluate(data, 999, 1)
			t.expect(cursor).toBe(4)
			local x, _, _, _, rewound = GhostTrack.evaluate(data, 0, cursor)
			t.expect(rewound).toBe(1)
			t.expect(x).toBeCloseTo(0, 0.01)
		end)
		t.it("cursor spoza zakresu nie psuje odczytu", function()
			local _, _, _, _, cursor = GhostTrack.evaluate(track(), 0, 999)
			t.expect(cursor).toBe(1)
		end)
		t.it("kurs przechodzi przez 0 najkrótszą drogą", function()
			local recorder = GhostTrack.newRecorder()
			GhostTrack.record(recorder, 0, 0, 0, 0, -0.2, false)
			GhostTrack.record(recorder, 1, 0, 0, 0, 0.2, false)
			local _, _, _, heading = GhostTrack.evaluate(GhostTrack.finish(recorder, 1000, 42) :: any, 0.5, 1)
			-- Środek łuku −0,2..0,2 to 0 albo pełny obrót: bezpiecznie po sinusie.
			t.expect(math.abs(math.sin(heading))).toBeLessThan(0.05)
			t.expect(math.cos(heading)).toBeGreaterThan(0.99)
		end)
		t.it("kurs po zapisie zgadza się z oryginałem", function()
			local recorder = GhostTrack.newRecorder()
			GhostTrack.record(recorder, 0, 0, 0, 0, -2.5, false)
			GhostTrack.record(recorder, 1, 0, 0, 0, -2.5, false)
			local _, _, _, heading = GhostTrack.evaluate(GhostTrack.finish(recorder, 1000, 42) :: any, 0, 1)
			t.expect(math.cos(heading)).toBeCloseTo(math.cos(-2.5), 0.02)
			t.expect(math.sin(heading)).toBeCloseTo(math.sin(-2.5), 0.02)
		end)
	end)
end
