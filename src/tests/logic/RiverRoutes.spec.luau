-- Wszystkie rzeki z katalogu: koryta się nie stykają, nurt mieści się w limicie, a bot przepływa całą trasę.

return function(t)
	local Config = require(t.shared.Config)
	local KayakPhysics = require(t.shared.KayakPhysics)
	local River = require(t.shared.River)
	local RiverCatalog = require(t.shared.content.RiverCatalog)

	local rivers = t.shared.content.rivers

	local function load(entry: any)
		return River.new(require(rivers:FindFirstChild(entry.river)))
	end

	-- Bot celuje w punkt przed sobą, jak w specu górskiej rzeki. Wynik: czas przejazdu, najwyższa prędkość i uderzenia.
	local function race(river: any): (number, number, number)
		local start = river:query(river:pointAt(Config.START_DISTANCE))
		local state = KayakPhysics.new(river:pointAt(Config.START_DISTANCE), math.atan2(start.tangent.Y, start.tangent.X))
		local elapsed, peak, hits = 0, 0, 0
		while elapsed < Config.RACE_TIME_LIMIT do
			local q = river:query(state.position, state.hint)
			if q.s >= river.length - Config.FINISH_MARGIN then
				break
			end
			local target = river:pointAt(math.min(q.s + 25, river.length)) - state.position
			local err = (math.atan2(target.Y, target.X) - state.heading + math.pi) % (2 * math.pi) - math.pi
			KayakPhysics.setBrace(state, if math.abs(err) > 0.7 then (if err > 0 then 1 else -1) else nil)
			if state.queued == nil and state.brace == nil then
				if math.abs(err) > 0.15 then
					KayakPhysics.requestStroke(state, if err > 0 then -1 else 1)
				else
					KayakPhysics.requestStroke(state, if state.strokes % 2 == 0 then 1 else -1)
				end
			end
			KayakPhysics.step(state, river, nil, 1 / 30)
			elapsed += 1 / 30
			peak = math.max(peak, state.velocity.Magnitude)
			if state.lastHit > 0 then
				hits += 1
				state.lastHit = 0
			end
		end
		return elapsed, peak, hits
	end

	t.describe("trasy z katalogu", function()
		t.it("koryto nie styka się samo ze sobą", function()
			for _, entry in RiverCatalog do
				local river = load(entry)
				local gap = 2 * (Config.BANK_MARGIN + Config.BEACH_WIDTH)
				for i = 1, river.vertices, 4 do
					for j = i + 60, river.vertices, 4 do
						local reach = river.halfWidths[i] + river.halfWidths[j] + gap
						t.expect((river.positions[i] - river.positions[j]).Magnitude > reach).toBe(true)
					end
				end
			end
		end)
		t.it("nurt nie przekracza 30 studs/s, żeby limit anty-oszustwo miał zapas", function()
			for _, entry in RiverCatalog do
				for _, speed in load(entry).speeds do
					t.expect(speed <= 30).toBe(true)
				end
			end
		end)
		t.it("wodospady dzieli co najmniej 300 studs, a skały nie zamykają koryta", function()
			for _, entry in RiverCatalog do
				local river = load(entry)
				for index = 2, #river.falls do
					t.expect(river.falls[index].s - river.falls[index - 1].s >= 300).toBe(true)
				end
				for _, rock in river.rocks do
					local q = river:query(rock.position)
					t.expect(math.abs(rock.lateral) + rock.radius < q.halfWidth).toBe(true)
				end
			end
		end)
		t.it("bot kończy każdą rzekę w limicie, bez przekroczenia prędkości", function()
			for _, entry in RiverCatalog do
				local river = load(entry)
				local time, peak, hits = race(river)
				print(`[bot] {entry.id}: długość {math.floor(river.length)}, czas {math.floor(time)} s, prędkość {math.floor(peak)}, uderzenia {hits}`)
				t.expect(time).toBeLessThan(Config.RACE_TIME_LIMIT - 40)
				t.expect(peak).toBeLessThan(Config.MAX_KAYAK_SPEED)
			end
		end)
	end)
end
