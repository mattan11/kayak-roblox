-- Zasady Wodnej bitwy: strefa, stożek celu, strumień (zbiornik, osłony, obrażenia, odepchnięcie), kolejność odpadania, koniec rundy i serwer zarezerwowany z 2 graczami.

return function(t)
	local ArenaLayout = require(t.shared.content.ArenaLayout)
	local ArenaRules = require(t.shared.ArenaRules)
	local Config = require(t.shared.Config)

	local FULL = ArenaLayout.radius

	local function roster(...: number): { any }
		local list = {}
		for _, id in { ... } do
			table.insert(list, { id = id, name = "P" .. id })
		end
		return list
	end

	-- Kajak w środku świata płynący w +X, jeśli nie podano inaczej.
	local function fighter(x: number, z: number?, forward: Vector2?)
		return { position = Vector2.new(x, z or 0), forward = forward or Vector2.xAxis }
	end

	-- Mecz ustawiony od razu na walkę, zaczętą w czasie 0.
	local function fighting(...: number)
		local players = roster(...)
		local match = ArenaRules.newMatch(nil, 2)
		ArenaRules.tick(match, 0, players) -- countdown
		ArenaRules.tick(match, Config.COUNTDOWN_TIME, players) -- walka
		t.expect(match.phase).toBe("racing")
		match.startedAt, match.burnedAt, match.phaseEndsAt = 0, 0, Config.ARENA_ROUND_TIME
		return match, players
	end

	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) < 1e-6
	end

	-- Jezioro bez przeszkód: strumień sprawdzamy osobno od osłon.
	local OPEN = { obstacles = {} }

	-- Otwiera strumień gracza 1 i liczy jeden obieg o długości `dt`.
	local function burst(match: any, fighters: any, dt: number)
		ArenaRules.setFiring(match, 1, true)
		return ArenaRules.stream(match, OPEN, fighters, match.streamedAt + dt)
	end

	t.describe("układ jeziora", function()
		t.it("przeszkody leżą w jeziorze i nie nachodzą na siebie", function()
			for index, obstacle in ArenaLayout.obstacles do
				t.expect((obstacle.position - ArenaLayout.center).Magnitude + obstacle.radius < FULL).toBe(true)
				for other = index + 1, #ArenaLayout.obstacles do
					local second = ArenaLayout.obstacles[other]
					t.expect((obstacle.position - second.position).Magnitude > obstacle.radius + second.radius + 8).toBe(true)
				end
			end
		end)
		t.it("miejsc startowych starczy na komplet, są na wodzie, z dala od przeszkód i od siebie", function()
			t.expect(ArenaRules.SPAWN_SLOTS).toBe(Config.PIER_CAPACITY)
			for slot = 1, ArenaRules.SPAWN_SLOTS do
				local point = ArenaRules.spawnPoint(ArenaLayout, slot)
				t.expect((point - ArenaLayout.center).Magnitude < FULL - Config.HULL_REACH - Config.KAYAK_RADIUS).toBe(true)
				for _, obstacle in ArenaLayout.obstacles do
					t.expect((point - obstacle.position).Magnitude > obstacle.radius + 10).toBe(true)
				end
				for other = slot + 1, ArenaRules.SPAWN_SLOTS do
					t.expect((point - ArenaRules.spawnPoint(ArenaLayout, other)).Magnitude > Config.KAYAK_CONTACT * 3).toBe(true)
				end
			end
		end)
		t.it("dwa kajaki stoją naprzeciw siebie, a dziób patrzy na środek", function()
			local first, heading = ArenaRules.spawnPoint(ArenaLayout, 1)
			local second = ArenaRules.spawnPoint(ArenaLayout, 2)
			t.expect(near((first + second - ArenaLayout.center * 2).Magnitude, 0)).toBe(true)
			local forward = Vector2.new(math.cos(heading), math.sin(heading))
			t.expect(forward:Dot((ArenaLayout.center - first).Unit) > 0.999).toBe(true)
		end)
		t.it("numeracja zaczyna się od nowa po komplecie", function()
			local a = ArenaRules.spawnPoint(ArenaLayout, 1)
			local b = ArenaRules.spawnPoint(ArenaLayout, ArenaRules.SPAWN_SLOTS + 1)
			t.expect(a == b).toBe(true)
		end)
		t.it("układ działa jako Lake", function()
			local lake = require(t.shared.Lake).new(ArenaLayout)
			t.expect(#lake.rocks).toBe(#ArenaLayout.obstacles)
			t.expect(lake.still).toBe(true)
		end)
	end)

	t.describe("strefa", function()
		t.it("zwęża się liniowo do końcowego promienia i dalej stoi", function()
			t.expect(ArenaRules.zoneRadius(FULL, 0)).toBe(FULL)
			t.expect(near(ArenaRules.zoneRadius(FULL, Config.ARENA_ZONE_TIME / 2), (FULL + Config.ARENA_ZONE_END_RADIUS) / 2)).toBe(true)
			t.expect(ArenaRules.zoneRadius(FULL, Config.ARENA_ZONE_TIME)).toBe(Config.ARENA_ZONE_END_RADIUS)
			t.expect(ArenaRules.zoneRadius(FULL, Config.ARENA_ROUND_TIME)).toBe(Config.ARENA_ZONE_END_RADIUS)
			t.expect(ArenaRules.zoneRadius(FULL, -5)).toBe(FULL)
		end)
		t.it("granica należy do strefy, a zepsuta pozycja nie chroni", function()
			t.expect(ArenaRules.isOutside(Vector2.new(40, 0), Vector2.zero, 40)).toBe(false)
			t.expect(ArenaRules.isOutside(Vector2.new(40.1, 0), Vector2.zero, 40)).toBe(true)
			t.expect(ArenaRules.isOutside(Vector2.new(0 / 0, 0), Vector2.zero, 40)).toBe(true)
		end)
		t.it("pali tylko poza strefą, tyle na sekundę", function()
			local match = fighting(1, 2)
			match.startedAt = -Config.ARENA_ZONE_TIME
			local fighters = { [1] = fighter(0), [2] = fighter(100) }
			ArenaRules.burn(match, ArenaLayout, fighters, 1)
			t.expect(match.contenders[1].health).toBe(Config.ARENA_HEALTH)
			t.expect(match.contenders[2].health).toBe(Config.ARENA_HEALTH - Config.ARENA_ZONE_DPS)
		end)
		t.it("przycięcie serwera nie zabija jednym obiegiem", function()
			local match = fighting(1, 2)
			match.startedAt = -Config.ARENA_ZONE_TIME
			ArenaRules.burn(match, ArenaLayout, { [1] = fighter(100) }, 1000)
			t.expect(match.contenders[1].health).toBe(Config.ARENA_HEALTH - Config.ARENA_ZONE_DPS * Config.ARENA_BURN_MAX_STEP)
		end)
		t.it("odpadnięty i gracz bez kajaka nie są palone", function()
			local match = fighting(1, 2, 3)
			match.startedAt = -Config.ARENA_ZONE_TIME
			match.contenders[3].health = 1
			ArenaRules.burn(match, ArenaLayout, { [1] = fighter(100), [3] = fighter(100) }, 1)
			t.expect(match.contenders[2].health).toBe(Config.ARENA_HEALTH) -- bez kajaka w migawce
			t.expect(match.contenders[3].place).toBe(3)
			local before = match.alive
			ArenaRules.burn(match, ArenaLayout, { [3] = fighter(100) }, 2)
			t.expect(match.alive).toBe(before)
		end)
		t.it("dwóch spalonych naraz: gorsze miejsce ma ten, kto miał mniej", function()
			local match = fighting(1, 2)
			match.startedAt = -Config.ARENA_ZONE_TIME
			match.contenders[1].health = 3
			match.contenders[2].health = 1
			local outs = ArenaRules.burn(match, ArenaLayout, { [1] = fighter(100), [2] = fighter(100) }, 1)
			t.expect(outs[1].userId).toBe(2)
			t.expect(outs[1].place).toBe(2)
			t.expect(outs[2].place).toBe(1)
			t.expect(match.alive).toBe(0)
			t.expect(ArenaRules.isOver(match, 1)).toBe(true)
		end)
	end)

	t.describe("cel", function()
		t.it("wybiera najbliższego w stożku", function()
			local match = fighting(1, 2, 3)
			local fighters = { [1] = fighter(0), [2] = fighter(50), [3] = fighter(30) }
			t.expect(ArenaRules.pickTarget(match, 1, fighters)).toBe(3)
		end)
		t.it("pomija siebie, cel poza zasięgiem i poza stożkiem", function()
			local match = fighting(1, 2, 3, 4)
			local fighters = {
				[1] = fighter(0),
				[2] = fighter(Config.ARENA_CANNON_RANGE + 1),
				[3] = fighter(-10), -- za rufą
				[4] = fighter(0, 20), -- prostopadle do dziobu
			}
			t.expect(ArenaRules.pickTarget(match, 1, fighters)).toBe(nil)
		end)
		t.it("zasięg i brzeg stożka są włącznie", function()
			local match = fighting(1, 2)
			t.expect(ArenaRules.pickTarget(match, 1, { [1] = fighter(0), [2] = fighter(Config.ARENA_CANNON_RANGE) })).toBe(2)
			local cos = Config.ARENA_CANNON_ARC_COS
			local side = Vector2.new(cos, math.sqrt(1 - cos * cos)) * 30
			local fighters = { [1] = fighter(0), [2] = fighter(side.X * 1.0001, side.Y) }
			t.expect(ArenaRules.pickTarget(match, 1, fighters)).toBe(2)
		end)
		t.it("kierunek liczy się z dziobu, nie z pozycji", function()
			local match = fighting(1, 2)
			local fighters = { [1] = fighter(0, 0, Vector2.new(0, 1)), [2] = fighter(0, 40) }
			t.expect(ArenaRules.pickTarget(match, 1, fighters)).toBe(2)
			fighters[1] = fighter(0, 0, Vector2.new(0, -1))
			t.expect(ArenaRules.pickTarget(match, 1, fighters)).toBe(nil)
		end)
		t.it("dwa kajaki w jednym punkcie: bez NaN, trafienie", function()
			local match = fighting(1, 2)
			t.expect(ArenaRules.pickTarget(match, 1, { [1] = fighter(5), [2] = fighter(5) })).toBe(2)
		end)
		t.it("stożek ma około 120°: 55° od dziobu trafia, 65° już nie", function()
			local match = fighting(1, 2)
			local function at(degrees: number)
				local angle = math.rad(degrees)
				return { [1] = fighter(0), [2] = fighter(40 * math.cos(angle), 40 * math.sin(angle)) }
			end
			t.expect(ArenaRules.pickTarget(match, 1, at(55))).toBe(2)
			t.expect(ArenaRules.pickTarget(match, 1, at(-55))).toBe(2)
			t.expect(ArenaRules.pickTarget(match, 1, at(65))).toBe(nil)
		end)
		t.it("spóźnialski i odpadnięty nie są celem", function()
			local match = fighting(1, 2)
			ArenaRules.leave(match, 2)
			t.expect(ArenaRules.pickTarget(match, 1, { [1] = fighter(0), [2] = fighter(30), [9] = fighter(20) })).toBe(nil)
		end)
	end)

	t.describe("zbiornik", function()
		t.it("pełny starcza dokładnie na ARENA_TANK_SECONDS strumienia", function()
			local left, spent = ArenaRules.drain(1, Config.ARENA_TANK_SECONDS / 2)
			t.expect(near(left, 0.5)).toBe(true)
			t.expect(spent).toBe(Config.ARENA_TANK_SECONDS / 2)
			left, spent = ArenaRules.drain(1, Config.ARENA_TANK_SECONDS)
			t.expect(left).toBe(0)
			t.expect(spent).toBe(Config.ARENA_TANK_SECONDS)
		end)
		t.it("końcówka daje tylko tyle sekund, ile zostało wody", function()
			local left, spent = ArenaRules.drain(0.01, 1)
			t.expect(left).toBe(0)
			t.expect(near(spent, 0.01 * Config.ARENA_TANK_SECONDS)).toBe(true)
		end)
		t.it("w ruchu ładuje się w 8 do 10 s, a powolny ruch jest pomiędzy", function()
			t.expect(Config.ARENA_TANK_FULL_TIME >= 8 and Config.ARENA_TANK_FULL_TIME <= 10).toBe(true)
			t.expect(near(ArenaRules.refill(0, Config.ARENA_TANK_FULL_SPEED, Config.ARENA_TANK_FULL_TIME), 1)).toBe(true)
			local slow = ArenaRules.refill(0, Config.ARENA_TANK_FULL_SPEED / 2, 1)
			t.expect(slow > ArenaRules.refill(0, 0, 1)).toBe(true)
			t.expect(slow < ArenaRules.refill(0, Config.ARENA_TANK_FULL_SPEED, 1)).toBe(true)
		end)
		t.it("w miejscu prawie nie ładuje", function()
			t.expect(Config.ARENA_TANK_IDLE_TIME >= Config.ARENA_TANK_FULL_TIME * 5).toBe(true)
			t.expect(near(ArenaRules.refill(0, 0, Config.ARENA_TANK_IDLE_TIME), 1)).toBe(true)
		end)
		t.it("szybciej niż pełna prędkość nie ładuje, nie przelewa się, a NaN to postój", function()
			t.expect(ArenaRules.refill(0, 1000, 1)).toBe(ArenaRules.refill(0, Config.ARENA_TANK_FULL_SPEED, 1))
			t.expect(ArenaRules.refill(0.99, 1000, 100)).toBe(1)
			t.expect(ArenaRules.refill(0, 0 / 0, 1)).toBe(ArenaRules.refill(0, 0, 1))
		end)
		t.it("do gracza najwyżej co ARENA_TANK_INTERVAL, także przy ładowaniu, a bez zmiany wcale", function()
			local match = fighting(1, 2)
			local contender = match.contenders[1]
			t.expect(ArenaRules.tankToSend(contender, 10)).toBe(1)
			contender.tank = 0.9
			t.expect(ArenaRules.tankToSend(contender, 10 + Config.ARENA_TANK_INTERVAL / 2)).toBe(nil)
			t.expect(ArenaRules.tankToSend(contender, 10 + Config.ARENA_TANK_INTERVAL)).toBe(0.9)
			t.expect(ArenaRules.tankToSend(contender, 20)).toBe(nil)
		end)
	end)

	t.describe("osłony", function()
		local A, B, C = Vector2.zero, Vector2.new(40, 0), Vector2.new(20, 0)
		t.it("koło na odcinku zasłania, obok już nie", function()
			t.expect(ArenaRules.segmentHitsCircle(A, B, C, 5)).toBe(true)
			t.expect(ArenaRules.segmentHitsCircle(A, B, Vector2.new(20, 6), 5)).toBe(false)
		end)
		t.it("brzeg koła zasłania", function()
			t.expect(ArenaRules.segmentHitsCircle(A, B, Vector2.new(20, 5), 5)).toBe(true)
		end)
		t.it("koło na prostej, ale za końcem odcinka, nie zasłania", function()
			t.expect(ArenaRules.segmentHitsCircle(A, B, Vector2.new(50, 0), 5)).toBe(false)
			t.expect(ArenaRules.segmentHitsCircle(A, B, Vector2.new(-10, 0), 5)).toBe(false)
		end)
		t.it("odcinek zerowej długości to punkt, bez NaN", function()
			t.expect(ArenaRules.segmentHitsCircle(A, A, Vector2.new(3, 0), 5)).toBe(true)
			t.expect(ArenaRules.segmentHitsCircle(A, A, Vector2.new(9, 0), 5)).toBe(false)
		end)
		t.it("cel za skałą odpada, a wygrywa dalszy i odsłonięty", function()
			local match = fighting(1, 2, 3)
			local rock = { { position = Vector2.new(15, 0), radius = 4 } }
			local fighters = { [1] = fighter(0), [2] = fighter(30), [3] = fighter(50, 25) }
			t.expect(ArenaRules.pickTarget(match, 1, fighters, rock)).toBe(3)
			fighters[3] = nil
			t.expect(ArenaRules.pickTarget(match, 1, fighters, rock)).toBe(nil)
		end)
		t.it("strumień przez skałę nie zadaje obrażeń, ale zużywa wodę", function()
			local match = fighting(1, 2)
			local layout = { obstacles = { { position = Vector2.new(15, 0), radius = 4 } } }
			ArenaRules.setFiring(match, 1, true)
			local result = ArenaRules.stream(match, layout, { [1] = fighter(0), [2] = fighter(30) }, match.streamedAt + 1)
			t.expect(#result.hits).toBe(0)
			t.expect(match.contenders[2].health).toBe(Config.ARENA_HEALTH)
			t.expect(match.contenders[1].tank < 1).toBe(true)
		end)
	end)

	t.describe("strumień", function()
		-- Cel [2] 30 studs przed dziobem strzelca, ze swoim dziobem w stronę `forward`.
		local function aimed(forward: Vector2)
			return { [1] = fighter(0), [2] = fighter(30, 0, forward) }
		end
		local HEAD_ON, BROADSIDE, STERN = Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(1, 0)

		t.it("z przodu zwykłe obrażenia, z boku i z tyłu z mnożnikiem", function()
			local shooter = Vector2.zero
			t.expect(ArenaRules.flankMultiplier(shooter, aimed(HEAD_ON)[2])).toBe(1)
			t.expect(ArenaRules.flankMultiplier(shooter, aimed(BROADSIDE)[2])).toBe(Config.ARENA_FLANK_MULTIPLIER)
			t.expect(ArenaRules.flankMultiplier(shooter, aimed(STERN)[2])).toBe(Config.ARENA_FLANK_MULTIPLIER)
			t.expect(ArenaRules.flankMultiplier(Vector2.new(30, 0), aimed(STERN)[2])).toBe(1) -- jeden punkt: bez NaN
		end)
		t.it("obrażenia na sekundę zależą od strony trafienia", function()
			for _, case in { { HEAD_ON, 1 }, { STERN, Config.ARENA_FLANK_MULTIPLIER } } do
				local match = fighting(1, 2)
				burst(match, aimed(case[1]), 1)
				local lost = Config.ARENA_HEALTH - match.contenders[2].health
				t.expect(near(lost, Config.ARENA_STREAM_DPS * case[2])).toBe(true)
			end
		end)
		t.it("zamknięty strumień nic nie robi, a pudło też zużywa wodę", function()
			local match = fighting(1, 2)
			ArenaRules.stream(match, OPEN, aimed(HEAD_ON), match.streamedAt + 1)
			t.expect(match.contenders[2].health).toBe(Config.ARENA_HEALTH)
			local result = burst(match, { [1] = fighter(0), [2] = fighter(-40) }, 1)
			t.expect(#result.hits).toBe(0)
			t.expect(near(match.contenders[1].tank, 1 - 1 / Config.ARENA_TANK_SECONDS)).toBe(true)
		end)
		t.it("gaśnie przy pustym zbiorniku i dopiero po doładowaniu da się go otworzyć", function()
			local match = fighting(1, 2)
			local contender = match.contenders[1]
			contender.tank = 0.01
			burst(match, aimed(HEAD_ON), 1)
			t.expect(contender.tank).toBe(0)
			t.expect(contender.firing).toBe(false)
			ArenaRules.setFiring(match, 1, true)
			t.expect(contender.firing).toBe(false)
			ArenaRules.stream(match, OPEN, aimed(HEAD_ON), match.streamedAt + 1)
			t.expect(contender.tank > 0).toBe(true)
			ArenaRules.setFiring(match, 1, true)
			t.expect(contender.firing).toBe(true)
		end)
		t.it("końcówka zbiornika daje obrażenia tylko za resztkę wody", function()
			local match = fighting(1, 2)
			match.contenders[1].tank = 1 / (10 * Config.ARENA_TANK_SECONDS) -- 0,1 s strumienia
			burst(match, aimed(HEAD_ON), 1)
			t.expect(near(Config.ARENA_HEALTH - match.contenders[2].health, Config.ARENA_STREAM_DPS * 0.1)).toBe(true)
		end)
		t.it("zbiornik ładuje się z ruchu w migawce, a w trakcie strumienia nie", function()
			local match = fighting(1, 2)
			local contender = match.contenders[1]
			contender.tank = 0.5
			local start = match.streamedAt
			ArenaRules.stream(match, OPEN, { [1] = fighter(0) }, start + 1) -- pierwszy odczyt: bez prędkości
			local still = contender.tank
			ArenaRules.stream(match, OPEN, { [1] = fighter(Config.ARENA_TANK_FULL_SPEED) }, start + 2)
			t.expect(near(contender.tank - still, 1 / Config.ARENA_TANK_FULL_TIME)).toBe(true)
			local before = contender.tank
			burst(match, { [1] = fighter(100) }, 1)
			t.expect(contender.tank < before).toBe(true)
		end)
		t.it("odpadnięcie gasi strumień, a odpadnięty nie ładuje się dalej", function()
			local match = fighting(1, 2, 3)
			local victim = match.contenders[1]
			victim.health = 1
			victim.tank = 0.5
			ArenaRules.setFiring(match, 1, true)
			ArenaRules.setFiring(match, 2, true)
			local fighters = { [1] = fighter(0), [2] = fighter(-30) } -- 2 płynie za 1 i celuje mu w rufę
			ArenaRules.stream(match, OPEN, fighters, match.streamedAt + 1)
			t.expect(victim.place).toBe(3)
			t.expect(victim.firing).toBe(false)
			local tank = victim.tank
			ArenaRules.stream(match, OPEN, fighters, match.streamedAt + 1)
			t.expect(victim.tank).toBe(tank)
		end)
		t.it("wyjście z serwera gasi strumień", function()
			local match = fighting(1, 2)
			ArenaRules.setFiring(match, 1, true)
			ArenaRules.leave(match, 1)
			t.expect(match.contenders[1].firing).toBe(false)
		end)
		t.it("zniknięcie kajaka gasi strumień", function()
			local match = fighting(1, 2)
			burst(match, { [2] = fighter(30) }, 0.1)
			t.expect(match.contenders[1].firing).toBe(false)
		end)
		t.it("poza walką, widz i odpadnięty nie otwierają strumienia", function()
			local waiting = ArenaRules.newMatch(nil, 2)
			ArenaRules.setFiring(waiting, 1, true) -- bez błędu, po prostu nic
			local match = fighting(1, 2)
			ArenaRules.setFiring(match, 9, true)
			t.expect(match.contenders[9]).toBe(nil)
			ArenaRules.leave(match, 2)
			ArenaRules.setFiring(match, 2, true)
			t.expect(match.contenders[2].firing).toBe(false)
		end)
		t.it("przycięcie serwera nie opróżnia zbiornika jednym obiegiem", function()
			local match = fighting(1, 2)
			burst(match, aimed(HEAD_ON), 1000)
			t.expect(near(match.contenders[1].tank, 1 - Config.ARENA_BURN_MAX_STEP / Config.ARENA_TANK_SECONDS)).toBe(true)
		end)
		t.it("ArenaHit najwyżej co ARENA_HIT_INTERVAL", function()
			local match = fighting(1, 2)
			local fighters = aimed(HEAD_ON)
			local shown = 0
			for _ = 1, 10 do -- 1 s po 0,1 s
				shown += #burst(match, fighters, 0.1).hits
			end
			t.expect(shown >= 3 and shown <= 4).toBe(true)
		end)
		t.it("odepchnięcie od strzelca, zbiorcze, nie częściej niż ArenaHit, i nic się nie gubi", function()
			local match = fighting(1, 2)
			local fighters = aimed(HEAD_ON)
			local total, events = Vector2.zero, 0
			for _ = 1, 10 do
				for _, entry in burst(match, fighters, 0.1).pushes do
					t.expect(entry.id).toBe(2)
					total += entry.push
					events += 1
				end
			end
			ArenaRules.setFiring(match, 1, false)
			for _, entry in ArenaRules.stream(match, OPEN, fighters, match.streamedAt + 1).pushes do
				total += entry.push
				events += 1
			end
			t.expect(events <= 5).toBe(true)
			t.expect(near(total.Y, 0)).toBe(true)
			t.expect(math.abs(total.X - Config.ARENA_PUSH_PER_SECOND) < 1e-3).toBe(true)
		end)
		t.it("dwa kajaki w jednym punkcie: odepchnięcie bez NaN", function()
			t.expect(ArenaRules.pushFor(Vector2.one, Vector2.one, 1) == Vector2.zero).toBe(true)
		end)
		t.it("wyczerpana wytrzymałość to odpadnięcie, z miejscem", function()
			local match = fighting(1, 2, 3)
			match.contenders[2].health = 1
			local result = burst(match, aimed(HEAD_ON), 1)
			t.expect(result.outs[1].userId).toBe(2)
			t.expect(result.outs[1].place).toBe(3)
			t.expect(match.contenders[2].health).toBe(0)
			t.expect(match.alive).toBe(2)
		end)
		t.it("dwóch dobija się w tym samym obiegu: zostaje zwycięzca", function()
			local match, players = fighting(1, 2)
			match.contenders[1].health, match.contenders[2].health = 0.1, 0.1
			ArenaRules.setFiring(match, 2, true)
			burst(match, { [1] = fighter(0), [2] = fighter(30, 0, HEAD_ON) }, 1)
			t.expect(match.alive).toBe(1)
			t.expect(ArenaRules.tick(match, 1, players)).toBe("results")
			t.expect(match.rows[1].userId).toBe(1)
		end)
		t.it("poza walką stream nic nie liczy", function()
			local waiting = ArenaRules.newMatch(nil, 2)
			t.expect(#ArenaRules.stream(waiting, OPEN, {}, 1).hits).toBe(0)
		end)
	end)

	t.describe("koniec rundy", function()
		t.it("zostaje jeden: koniec, miejsca wg kolejności odpadania", function()
			local match, players = fighting(1, 2, 3)
			match.contenders[3].health = 1
			match.contenders[2].health = 1
			local fighters = { [1] = fighter(0), [2] = fighter(50), [3] = fighter(30) }
			t.expect(burst(match, fighters, 1).outs[1].place).toBe(3)
			t.expect(ArenaRules.tick(match, 1, players)).toBe(nil)
			t.expect(burst(match, fighters, 1).outs[1].place).toBe(2)
			t.expect(ArenaRules.tick(match, 2, players)).toBe("results")
			t.expect(match.rows[1].userId).toBe(1)
			t.expect(match.rows[2].userId).toBe(2)
			t.expect(match.rows[3].userId).toBe(3)
			t.expect(match.rows[1].place).toBe(1)
		end)
		t.it("po czasie wygrywa największa wytrzymałość, a remis rozstrzyga id", function()
			local match, players = fighting(1, 2, 3)
			match.contenders[1].health = 30
			match.contenders[2].health = 70.5
			match.contenders[3].health = 30
			t.expect(ArenaRules.tick(match, Config.ARENA_ROUND_TIME - 1, players)).toBe(nil)
			t.expect(ArenaRules.tick(match, Config.ARENA_ROUND_TIME, players)).toBe("results")
			t.expect(match.rows[1].userId).toBe(2)
			t.expect(match.rows[1].health).toBe(71)
			t.expect(match.rows[2].userId).toBe(1)
			t.expect(match.rows[3].userId).toBe(3)
		end)
		t.it("po czasie odpadli stoją za wszystkimi żywymi", function()
			local match, players = fighting(1, 2, 3)
			ArenaRules.leave(match, 1)
			t.expect(ArenaRules.tick(match, Config.ARENA_ROUND_TIME, players)).toBe("results")
			t.expect(match.rows[3].userId).toBe(1)
			t.expect(match.rows[3].place).toBe(3)
		end)
		t.it("po wynikach rusza kolejna runda z pełną wytrzymałością", function()
			local match, players = fighting(1, 2)
			match.contenders[1].health = 10
			ArenaRules.tick(match, Config.ARENA_ROUND_TIME, players)
			local after = match.phaseEndsAt
			t.expect(ArenaRules.tick(match, after - 1, players)).toBe(nil)
			t.expect(ArenaRules.tick(match, after, players)).toBe("countdown")
			t.expect(#match.rows).toBe(0)
			t.expect(next(match.contenders)).toBe(nil)
			ArenaRules.tick(match, after + Config.COUNTDOWN_TIME, players)
			t.expect(match.phase).toBe("racing")
			t.expect(match.contenders[1].health).toBe(Config.ARENA_HEALTH)
			t.expect(match.phaseEndsAt).toBe(after + Config.COUNTDOWN_TIME + Config.ARENA_ROUND_TIME)
		end)
		t.it("strefa startuje od nowa, a na ekranie wyników stoi", function()
			local match, players = fighting(1, 2)
			t.expect(ArenaRules.currentRadius(match, FULL, 0)).toBe(FULL)
			ArenaRules.leave(match, 2)
			ArenaRules.tick(match, 60, roster(1))
			local frozen = ArenaRules.currentRadius(match, FULL, 60)
			t.expect(ArenaRules.currentRadius(match, FULL, 65)).toBe(frozen)
			ArenaRules.tick(match, 60 + Config.RESULTS_TIME, players)
			t.expect(ArenaRules.currentRadius(match, FULL, 80)).toBe(FULL)
		end)
	end)

	t.describe("głosy po walce", function()
		-- Mecz na ekranie wyników: walka skończona przez limit czasu.
		local function atResults(...: number)
			local match, players = fighting(...)
			ArenaRules.tick(match, Config.ARENA_ROUND_TIME, players)
			t.expect(match.phase).toBe("results")
			return match, players
		end

		t.it("wszyscy „Jeszcze raz” skraca wyniki do krótkiego odliczania", function()
			local match, players = atResults(1, 2)
			local time = Config.ARENA_ROUND_TIME + 1
			ArenaRules.voteAgain(match, 1)
			t.expect(ArenaRules.tick(match, time, players)).toBe(nil)
			ArenaRules.voteAgain(match, 2)
			t.expect(ArenaRules.tick(match, time, players)).toBe("countdown")
			t.expect(match.phaseEndsAt).toBe(time + Config.AGAIN_COUNTDOWN)
		end)
		t.it("głos w odliczaniu też skraca czas, a walka czyści głosy", function()
			local match, players = atResults(1, 2)
			local time = match.phaseEndsAt
			ArenaRules.tick(match, time, players)
			ArenaRules.voteAgain(match, 1)
			ArenaRules.voteAgain(match, 2)
			ArenaRules.tick(match, time + 1, players)
			t.expect(match.phaseEndsAt).toBe(time + 1 + Config.AGAIN_COUNTDOWN)
			ArenaRules.tick(match, match.phaseEndsAt, players)
			t.expect(match.phase).toBe("racing")
			t.expect(next(match.againVotes)).toBe(nil)
		end)
		t.it("licznik jak w wyścigu, a nieudany teleport cofa głos", function()
			local match = atResults(1, 2, 3)
			ArenaRules.voteAgain(match, 1)
			ArenaRules.voteLeave(match, 2)
			local again, leaving, undecided = ArenaRules.tally(match, 3)
			t.expect(`{again}/{leaving}/{undecided}`).toBe("1/1/1")
			ArenaRules.cancelLeave(match, 2)
			again, leaving, undecided = ArenaRules.tally(match, 3)
			t.expect(`{again}/{leaving}/{undecided}`).toBe("1/0/2")
			ArenaRules.leave(match, 3)
			again, leaving, undecided = ArenaRules.tally(match, 2)
			t.expect(`{again}/{leaving}/{undecided}`).toBe("1/1/1")
		end)
		t.it("w walce głosy nie działają", function()
			local match = fighting(1, 2)
			ArenaRules.voteAgain(match, 1)
			ArenaRules.voteLeave(match, 2)
			t.expect(next(match.againVotes)).toBe(nil)
			t.expect(next(match.leaving)).toBe(nil)
		end)
		t.it("samotny „Jeszcze raz” nie rusza rundy poniżej minimum", function()
			local match = atResults(1, 2)
			ArenaRules.voteAgain(match, 1)
			t.expect(ArenaRules.tick(match, Config.ARENA_ROUND_TIME + 1, roster(1))).toBe("waiting")
		end)
	end)

	t.describe("gracze na serwerze zarezerwowanym", function()
		t.it("czeka na `expected` z wpisu, po czym rusza odliczanie", function()
			local match = ArenaRules.newMatch(3, 2)
			t.expect(ArenaRules.tick(match, 0, roster(1, 2))).toBe(nil)
			t.expect(match.phase).toBe("waiting")
			t.expect(match.phaseEndsAt).toBe(Config.RACE_GATHER_TIME)
			t.expect(ArenaRules.tick(match, 5, roster(1, 2, 3))).toBe("countdown")
		end)
		t.it("nie czeka na spóźnialskiego dłużej niż RACE_GATHER_TIME", function()
			local match = ArenaRules.newMatch(3, 2)
			ArenaRules.tick(match, 0, roster(1, 2))
			t.expect(ArenaRules.tick(match, Config.RACE_GATHER_TIME - 1, roster(1, 2))).toBe(nil)
			t.expect(ArenaRules.tick(match, Config.RACE_GATHER_TIME, roster(1, 2))).toBe("countdown")
		end)
		t.it("dotarł jeden z dwóch: nie gra sam, a po czasie wraca do wioski", function()
			local match = ArenaRules.newMatch(2, 2)
			local solo = roster(1)
			ArenaRules.tick(match, 0, solo)
			local gathered = Config.RACE_GATHER_TIME
			t.expect(ArenaRules.tick(match, gathered, solo)).toBe(nil)
			t.expect(match.phase).toBe("waiting")
			t.expect(ArenaRules.stranded(match, gathered + Config.ARENA_ALONE_TIME - 1)).toBe(false)
			t.expect(ArenaRules.stranded(match, gathered + Config.ARENA_ALONE_TIME)).toBe(true)
			t.expect(ArenaRules.stranded(match, gathered + Config.ARENA_ALONE_TIME + 1)).toBe(false) -- nie ponawia co obieg
			t.expect(ArenaRules.stranded(match, gathered + 2 * Config.ARENA_ALONE_TIME)).toBe(true)
		end)
		t.it("drugi dopływa, zanim pierwszy zostanie odesłany: gramy", function()
			local match = ArenaRules.newMatch(2, 2)
			ArenaRules.tick(match, 0, roster(1))
			ArenaRules.tick(match, Config.RACE_GATHER_TIME, roster(1))
			t.expect(ArenaRules.tick(match, Config.RACE_GATHER_TIME + 1, roster(1, 2))).toBe("countdown")
			t.expect(ArenaRules.stranded(match, 1e6)).toBe(false)
		end)
		t.it("wyjście w odliczaniu cofa do czekania", function()
			local match = ArenaRules.newMatch(nil, 2)
			ArenaRules.tick(match, 0, roster(1, 2))
			t.expect(ArenaRules.tick(match, 1, roster(1))).toBe("waiting")
			t.expect(ArenaRules.tick(match, 2, roster(1))).toBe(nil)
			t.expect(match.aloneUntil).toBe(2 + Config.ARENA_ALONE_TIME)
		end)
		t.it("drugi z dwóch wychodzi w walce: wygrywa ten, kto został, i zostaje w wynikach sam z wychodzącym", function()
			local match = fighting(1, 2)
			local out = ArenaRules.leave(match, 2)
			t.expect(out.place).toBe(2)
			t.expect(ArenaRules.tick(match, 5, roster(1))).toBe("results")
			t.expect(match.rows[1].userId).toBe(1)
			t.expect(match.rows[2].userId).toBe(2)
		end)
		t.it("po wynikach samotny gracz czeka, a potem wraca do wioski", function()
			local match = fighting(1, 2)
			ArenaRules.leave(match, 2)
			ArenaRules.tick(match, 5, roster(1))
			t.expect(ArenaRules.tick(match, match.phaseEndsAt, roster(1))).toBe("waiting")
			t.expect(ArenaRules.tick(match, 100, roster(1))).toBe(nil)
			t.expect(ArenaRules.stranded(match, 100 + Config.ARENA_ALONE_TIME)).toBe(true)
		end)
		t.it("wyjście poza walką i powtórne wyjście niczego nie liczą", function()
			local match = fighting(1, 2, 3)
			t.expect(ArenaRules.leave(match, 3).place).toBe(3)
			t.expect(ArenaRules.leave(match, 3)).toBe(nil)
			t.expect(ArenaRules.leave(match, 99)).toBe(nil)
			t.expect(ArenaRules.leave(ArenaRules.newMatch(nil, 2), 1)).toBe(nil)
			t.expect(match.alive).toBe(2)
		end)
		t.it("wszyscy wyszli: mecz wraca do czekania bez wyników", function()
			local match = fighting(1, 2)
			t.expect(ArenaRules.tick(match, 5, {})).toBe("waiting")
			t.expect(#match.rows).toBe(0)
			t.expect(match.aloneUntil).toBe(nil)
		end)
		t.it("w Studio jeden gracz gra do czasu albo do spalenia", function()
			local match = ArenaRules.newMatch(nil, 1)
			local solo = roster(1)
			t.expect(ArenaRules.tick(match, 0, solo)).toBe("countdown")
			t.expect(ArenaRules.tick(match, Config.COUNTDOWN_TIME, solo)).toBe("racing")
			t.expect(ArenaRules.tick(match, Config.COUNTDOWN_TIME + 1, solo)).toBe(nil)
			t.expect(ArenaRules.isOver(match, Config.COUNTDOWN_TIME + 1)).toBe(false)
		end)
	end)
end
