-- Zasady Wodnej bitwy: strefa, stożek celu, limit strzałów, kolejność odpadania, koniec rundy i serwer zarezerwowany z 2 graczami.

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

	t.describe("strzał", function()
		t.it("trafia najbliższego w stożku, za 15", function()
			local match = fighting(1, 2, 3)
			local fighters = { [1] = fighter(0), [2] = fighter(50), [3] = fighter(30) }
			local shot = ArenaRules.fire(match, 1, fighters, 1)
			t.expect(shot.target).toBe(3)
			t.expect(match.contenders[3].health).toBe(Config.ARENA_HEALTH - Config.ARENA_CANNON_DAMAGE)
			t.expect(match.contenders[2].health).toBe(Config.ARENA_HEALTH)
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
		t.it("odnowienie: zalew strzałów daje jeden, a pudło też je zużywa", function()
			local match = fighting(1, 2)
			local away = { [1] = fighter(0), [2] = fighter(-40) }
			local shot = ArenaRules.fire(match, 1, away, 1)
			t.expect(shot.target).toBe(nil)
			local aimed = { [1] = fighter(0), [2] = fighter(40) }
			for _ = 1, 20 do
				t.expect(ArenaRules.fire(match, 1, aimed, 1 + Config.ARENA_COOLDOWN / 2)).toBe(nil)
			end
			t.expect(match.contenders[2].health).toBe(Config.ARENA_HEALTH)
			t.expect(ArenaRules.fire(match, 1, aimed, 1 + Config.ARENA_COOLDOWN).target).toBe(2)
		end)
		t.it("poza walką, bez kajaka i spoza rundy strzał jest odrzucany", function()
			local fighters = { [1] = fighter(0), [2] = fighter(40), [9] = fighter(10) }
			local waiting = ArenaRules.newMatch(nil, 2)
			t.expect(ArenaRules.fire(waiting, 1, fighters, 1)).toBe(nil)
			local match = fighting(1, 2)
			t.expect(ArenaRules.fire(match, 9, fighters, 1)).toBe(nil) -- spóźnialski
			t.expect(ArenaRules.fire(match, 1, { [2] = fighter(40) }, 1)).toBe(nil)
		end)
		t.it("trafienia zabierają wytrzymałość do zera, potem gracz odpada", function()
			local match = fighting(1, 2, 3)
			local fighters = { [1] = fighter(0), [2] = fighter(40) }
			local hits = math.ceil(Config.ARENA_HEALTH / Config.ARENA_CANNON_DAMAGE)
			local out = nil
			for shot = 1, hits do
				local result = ArenaRules.fire(match, 1, fighters, shot * Config.ARENA_COOLDOWN)
				t.expect(out).toBe(nil)
				out = result.out
			end
			t.expect(out.userId).toBe(2)
			t.expect(out.name).toBe("P2")
			t.expect(out.place).toBe(3)
			t.expect(match.contenders[2].health).toBe(0)
			t.expect(match.alive).toBe(2)
		end)
		t.it("odpadnięty nie strzela i nie jest celem", function()
			local match = fighting(1, 2, 3)
			match.contenders[2].health = 1
			local fighters = { [1] = fighter(0), [2] = fighter(40), [3] = fighter(60) }
			t.expect(ArenaRules.fire(match, 1, fighters, 1).out.userId).toBe(2)
			t.expect(ArenaRules.fire(match, 2, fighters, 5)).toBe(nil)
			t.expect(ArenaRules.fire(match, 1, fighters, 5).target).toBe(3)
		end)
	end)

	t.describe("koniec rundy", function()
		t.it("zostaje jeden: koniec, miejsca wg kolejności odpadania", function()
			local match, players = fighting(1, 2, 3)
			match.contenders[3].health = 1
			match.contenders[2].health = 1
			local fighters = { [1] = fighter(0), [2] = fighter(50), [3] = fighter(30) }
			t.expect(ArenaRules.fire(match, 1, fighters, 1).out.place).toBe(3)
			t.expect(ArenaRules.tick(match, 1, players)).toBe(nil)
			t.expect(ArenaRules.fire(match, 1, fighters, 2).out.place).toBe(2)
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
