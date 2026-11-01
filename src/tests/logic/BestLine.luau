-- Narzędzie, nie test: szuka najszybszej linii każdej rzeki tą samą fizyką co gra, z rytmem wiosła jak u człowieka.
-- Uruchomienie: lune.exe run tools/lune/run_tests.luau BestLine (kilka minut, dlatego nie ma końcówki .spec).
-- Pilot ma kilka pokręteł: jak daleko patrzy, jak mocno ścina zakręty, kiedy koryguje kurs i kiedy hamuje. Przeszukujemy je
-- po jednym, dwa przebiegi (dla TS: coordinate descent). Wynik to dobry czas osiągalny, nie matematyczne optimum,
-- a progi medali wyliczamy z niego tą samą proporcją na każdej rzece. Klawisze: patrz medalsFor.

return function(t)
	local Config = require(t.shared.Config)
	local KayakPhysics = require(t.shared.KayakPhysics)
	local River = require(t.shared.River)
	local RiverCatalog = require(t.shared.content.RiverCatalog)

	local STEP = 1 / 30
	local OPTIONS = {
		look = { 15, 20, 25, 30, 40, 55, 70 }, -- ile studs przed kajakiem leży punkt celowania
		inner = { 0, 0.15, 0.3, 0.45, 0.6 }, -- ułamek szerokości, o który ścinamy wnętrze zakrętu
		deadband = { 0.1, 0.2, 0.3, 0.45, 0.6 }, -- błąd kursu (rad), od którego machnięcie koryguje kurs
		brace = { 0.8, 1.1, 1.5, 3.2 }, -- błąd kursu (rad), od którego hamujemy wbiciem
		clear = { 2, 4, 6 }, -- zapas przy omijaniu skał
	}
	local KEYS = { "look", "inner", "deadband", "brace", "clear" }

	-- Punkt docelowy na lini zakrętu; skała przed kajakiem przesuwa cel na stronę, po której jest więcej wody.
	local function aimPoint(river: any, s: number, setting: any): Vector2
		local at = math.min(s + setting.look, river.length)
		local center = river:pointAt(at)
		local q = river:query(center)
		local lateral = -math.sign(q.curvature) * math.min(math.abs(q.curvature) * 40, 1) * setting.inner * q.halfWidth
		for _, rock in river.rocks do
			if rock.s > s and rock.s < at + 12 then
				local room = rock.radius + Config.KAYAK_RADIUS + setting.clear
				if math.abs(lateral - rock.lateral) < room then
					local side = if rock.lateral > 0 then -1 else 1
					lateral = rock.lateral + side * room
				end
			end
		end
		return center + q.normal * math.clamp(lateral, -q.halfWidth * 0.8, q.halfWidth * 0.8)
	end

	local function race(river: any, setting: any, limit: number): number
		local start = river:query(river:pointAt(Config.START_DISTANCE))
		local state = KayakPhysics.new(river:pointAt(Config.START_DISTANCE), math.atan2(start.tangent.Y, start.tangent.X))
		state.height = start.level
		local elapsed = 0
		while elapsed < limit do
			local q = river:query(state.position, state.hint)
			if q.s >= river.length - Config.FINISH_MARGIN then
				return elapsed
			end
			local target = aimPoint(river, q.s, setting) - state.position
			local err = (math.atan2(target.Y, target.X) - state.heading + math.pi) % (2 * math.pi) - math.pi
			KayakPhysics.setBrace(state, if math.abs(err) > setting.brace then (if err > 0 then 1 else -1) else nil)
			if state.queued == nil and state.brace == nil then
				if math.abs(err) > setting.deadband then
					KayakPhysics.requestStroke(state, if err > 0 then -1 else 1)
				else
					KayakPhysics.requestStroke(state, if state.strokes % 2 == 0 then 1 else -1)
				end
			end
			KayakPhysics.step(state, river, nil, STEP)
			elapsed += STEP
		end
		return math.huge
	end

	local function search(river: any): (number, any)
		local best = { look = 55, inner = 0.3, deadband = 0.3, brace = 1.1, clear = 2 }
		local bestTime = race(river, best, Config.RACE_TIME_LIMIT)
		local improved, passes = true, 0
		while improved and passes < 2 do
			improved, passes = false, passes + 1
			for _, key in KEYS do
				for _, value in OPTIONS[key] do
					if value ~= best[key] then
						local trial = table.clone(best)
						trial[key] = value
						local time = race(river, trial, bestTime)
						if time < bestTime then
							best, bestTime, improved = trial, time, true
						end
					end
				end
			end
			task.wait() -- Lune nie blokuje wyjścia wypisywaniem
		end
		return bestTime, best
	end

	for _, entry in RiverCatalog do
		local river = River.new(require(t.shared.content.rivers:FindFirstChild(entry.river)))
		local time, setting = search(river)
		local medals = Config.RIVER_MEDALS[entry.river]
		print(
			string.format(
				"[linia] %s: %.1f s, złoto obecne %d (%.2f×), look=%d inner=%.2f deadband=%.2f brace=%.1f clear=%d",
				entry.id,
				time,
				medals.gold,
				medals.gold / time,
				setting.look,
				setting.inner,
				setting.deadband,
				setting.brace,
				setting.clear
			)
		)
	end
end
