-- Kolejka między serwerami: decyzje o starcie, wiele serwerów, lider i jego zmiana, walidacja danych z sieci, ponowienia.

return function(t)
	local Config = require(t.shared.Config)
	local MatchQueue = require(t.shared.MatchQueue)

	local CAPACITY = Config.PIER_CAPACITY
	local COUNTDOWN = Config.PIER_COUNTDOWN

	local function ticket(id: number, joinedAt: number, ready: boolean?, serverId: string?)
		local result = MatchQueue.ticket(id, serverId or "A", joinedAt)
		result.ready = ready == true
		return result
	end

	local function tickets(count: number, joinedAt: number)
		local list = {}
		for id = 1, count do
			table.insert(list, ticket(id, joinedAt))
		end
		return list
	end

	local function ids(list: { any }): string
		local result = {}
		for _, item in list do
			table.insert(result, item.userId)
		end
		return table.concat(result, ",")
	end

	-- Atrapa mapy MemoryStore: tylko to, czego używa MatchService, z wygasaniem po czasie. Spec przesuwa zegar sam.
	-- (Dla TS: `new FakeRedis()` w miejsce prawdziwego klienta.)
	local function fakeMap()
		local items: { [string]: { value: any, expires: number } } = {}
		local map = { now = 0 }
		function map.live(key: string): any
			local item = items[key]
			if item and item.expires > map.now then
				return item.value
			end
			items[key] = nil
			return nil
		end
		function map.set(key: string, value: any, ttl: number)
			items[key] = { value = value, expires = map.now + ttl }
		end
		function map.update(key: string, transform: (any) -> any, ttl: number): any
			local value = transform(map.live(key))
			if value ~= nil then
				map.set(key, value, ttl)
			end
			return value
		end
		function map.remove(key: string)
			items[key] = nil
		end
		function map.range(): { any }
			local list = {}
			for key in table.clone(items) do
				local value = map.live(key)
				if value then
					table.insert(list, value)
				end
			end
			return list
		end
		return map
	end

	t.describe("decyzja o starcie", function()
		t.it("pusta kolejka nie startuje i nie odlicza", function()
			local decision = MatchQueue.decide({}, 1000)
			t.expect(decision.group).toBe(nil)
			t.expect(decision.state.count).toBe(0)
			t.expect(decision.state.endsAt).toBe(nil)
		end)
		t.it("odliczanie liczy się od najstarszego biletu, kolejni go nie przedłużają", function()
			local decision = MatchQueue.decide({ ticket(2, 15), ticket(1, 10) }, 12)
			t.expect(decision.group).toBe(nil)
			t.expect(decision.state.endsAt).toBe(10 + COUNTDOWN)
			t.expect(ids(decision.rest)).toBe("1,2")
		end)
		t.it("koniec odliczania oddaje wszystkich, nawet solo", function()
			t.expect(MatchQueue.decide({ ticket(1, 0) }, COUNTDOWN - 0.1).group).toBe(nil)
			local group = MatchQueue.decide({ ticket(1, 0) }, COUNTDOWN).group
			t.expect(ids(group)).toBe("1")
		end)
		t.it("komplet startuje od razu", function()
			t.expect(MatchQueue.decide(tickets(CAPACITY - 1, 0), 1).group).toBe(nil)
			t.expect(#MatchQueue.decide(tickets(CAPACITY, 0), 1).group).toBe(CAPACITY)
		end)
		t.it("nadmiar czeka na następną grupę, a najstarsi płyną pierwsi", function()
			local list = tickets(CAPACITY - 1, 5)
			table.insert(list, ticket(100, 0))
			table.insert(list, ticket(101, 6))
			table.insert(list, ticket(102, 7))
			local decision = MatchQueue.decide(list, 7)
			t.expect(#decision.group).toBe(CAPACITY)
			t.expect(decision.group[1].userId).toBe(100)
			t.expect(ids(decision.rest)).toBe("101,102")
			t.expect(decision.state.count).toBe(2)
			t.expect(decision.state.endsAt).toBe(6 + COUNTDOWN)
		end)
		t.it("wszyscy gotowi startują od razu, solo też", function()
			t.expect(#MatchQueue.decide({ ticket(1, 0, true), ticket(2, 0, true) }, 1).group).toBe(2)
			t.expect(#MatchQueue.decide({ ticket(1, 0, true) }, 0).group).toBe(1)
		end)
		t.it("nowy gracz wstrzymuje start gotowych, ale nie kasuje ich głosów", function()
			local decision = MatchQueue.decide({ ticket(1, 0, true), ticket(2, 0, true), ticket(3, 1) }, 2)
			t.expect(decision.group).toBe(nil)
			t.expect(decision.state.ready).toBe(2)
		end)
		t.it("wyjście jedynego niezdecydowanego startuje resztę", function()
			t.expect(#MatchQueue.decide({ ticket(1, 0, true), ticket(2, 0, true) }, 2).group).toBe(2)
		end)
		t.it("ten sam wynik bez względu na kolejność wejścia i remisy czasu", function()
			local a = MatchQueue.decide({ ticket(3, 0), ticket(1, 0), ticket(2, 0) }, 1)
			local b = MatchQueue.decide({ ticket(2, 0), ticket(3, 0), ticket(1, 0) }, 1)
			t.expect(ids(a.rest)).toBe("1,2,3")
			t.expect(ids(b.rest)).toBe("1,2,3")
		end)
		t.it("nie zmienia listy wejściowej", function()
			local list = { ticket(2, 5), ticket(1, 0) }
			MatchQueue.decide(list, 0)
			t.expect(list[1].userId).toBe(2)
		end)
	end)

	t.describe("Wodna bitwa", function()
		local MIN = Config.ARENA_MIN_PLAYERS

		t.it("wymaga 2 graczy, a inne tryby nie", function()
			t.expect(MatchQueue.minPlayers("arena")).toBe(2)
			t.expect(MatchQueue.minPlayers("race")).toBe(1)
			t.expect(MatchQueue.minPlayers("battle")).toBe(1)
		end)
		t.it("solo czeka bez końca, nie odlicza i „gotowy” niczego nie zmienia", function()
			local decision = MatchQueue.decide({ ticket(1, 0, true) }, COUNTDOWN * 100, MIN)
			t.expect(decision.group).toBe(nil)
			t.expect(decision.state.count).toBe(1)
			t.expect(decision.state.endsAt).toBe(nil)
		end)
		t.it("odliczanie liczy się od drugiego biletu, więc długie czekanie pierwszego go nie skraca", function()
			local list = { ticket(1, 0), ticket(2, 500) }
			local decision = MatchQueue.decide(list, 501, MIN)
			t.expect(decision.group).toBe(nil)
			t.expect(decision.state.endsAt).toBe(500 + COUNTDOWN)
			t.expect(ids(MatchQueue.decide(list, 500 + COUNTDOWN, MIN).group)).toBe("1,2")
		end)
		t.it("dwóch gotowych startuje od razu, a komplet bez czekania", function()
			t.expect(#MatchQueue.decide({ ticket(1, 0, true), ticket(2, 0, true) }, 1, MIN).group).toBe(2)
			t.expect(#MatchQueue.decide(tickets(CAPACITY, 0), 1, MIN).group).toBe(CAPACITY)
		end)
		t.it("nadmiar: samotna reszta po grupie znowu czeka bez odliczania", function()
			local decision = MatchQueue.decide(tickets(CAPACITY + 1, 0), 1, MIN)
			t.expect(#decision.group).toBe(CAPACITY)
			t.expect(decision.state.count).toBe(1)
			t.expect(decision.state.endsAt).toBe(nil)
		end)
		t.it("klucz biletów, tryb i Match zgodne z kontraktem", function()
			t.expect(MatchQueue.queueKey(Config.ARENA_RIVER, "arena")).toBe("Arena_arena")
			t.expect(MatchQueue.parseMode("arena")).toBe("arena")
			t.expect(MatchQueue.parseMatch({ river = "Arena", mode = "arena", userIds = { 1, 2 }, at = 0 }).mode).toBe("arena")
		end)
		t.it("MODES to tylko tryby rzek: bez kolejki Test_arena", function()
			t.expect(table.find(MatchQueue.MODES, "arena")).toBe(nil)
		end)
	end)

	t.describe("jedna kolejka na gracza", function()
		t.it("zostaje nowszy bilet, niezależnie od rzeki", function()
			local result = MatchQueue.dedupe({
				Test = { ticket(1, 10), ticket(2, 3) },
				Mountain = { ticket(1, 20), ticket(3, 4) },
			})
			t.expect(ids(result.Test)).toBe("2")
			t.expect(ids(result.Mountain)).toBe("1,3")
		end)
		t.it("bilety bez konfliktu zostają", function()
			t.expect(ids(MatchQueue.dedupe({ Test = { ticket(1, 1), ticket(2, 2) } }).Test)).toBe("1,2")
		end)
	end)

	t.describe("dwa serwery", function()
		t.it("gracze z różnych serwerów trafiają do jednej grupy", function()
			local map = fakeMap()
			map.set("1", ticket(1, 0, false, "A"), Config.MATCH_TICKET_TTL)
			map.set("2", ticket(2, 1, false, "B"), Config.MATCH_TICKET_TTL)
			map.now = COUNTDOWN
			local decision = MatchQueue.decide(map.range(), COUNTDOWN)
			t.expect(ids(decision.group)).toBe("1,2")
			t.expect(decision.group[1].serverId).toBe("A")
			t.expect(decision.group[2].serverId).toBe("B")
		end)
		t.it("gotowość liczy się po wszystkich serwerach", function()
			local mixed = { ticket(1, 0, true, "A"), ticket(2, 0, false, "B") }
			t.expect(MatchQueue.decide(mixed, 1).group).toBe(nil)
			mixed[2].ready = true
			t.expect(#MatchQueue.decide(mixed, 1).group).toBe(2)
		end)
		t.it("bilet padniętego serwera wygasa, jeśli nikt go nie odnawia", function()
			local map = fakeMap()
			map.set("1", ticket(1, 0, false, "A"), Config.MATCH_TICKET_TTL)
			map.set("2", ticket(2, 0, false, "B"), Config.MATCH_TICKET_TTL)
			for time = Config.MATCH_TICKET_RENEW, Config.MATCH_TICKET_TTL + 1, Config.MATCH_TICKET_RENEW do
				map.now = time
				map.update("2", function(old)
					return old
				end, Config.MATCH_TICKET_TTL)
			end
			t.expect(ids(map.range())).toBe("2")
		end)
		t.it("odnowienie zabranego biletu go nie wskrzesza: tak serwer wie, że grupa ruszyła", function()
			local map = fakeMap()
			map.set("1", ticket(1, 0), Config.MATCH_TICKET_TTL)
			map.remove("1") -- lider zabrał bilet do grupy
			local renewed = map.update("1", function(old)
				return old
			end, Config.MATCH_TICKET_TTL)
			t.expect(renewed).toBe(nil)
			t.expect(#map.range()).toBe(0)
		end)
	end)

	t.describe("lider", function()
		local TTL = Config.MATCH_LEADER_TTL

		local function claim(map, serverId: string): boolean
			return map.update("Leader", function(current)
				return MatchQueue.claimLeader(current, serverId)
			end, TTL) ~= nil
		end

		t.it("jeden serwer dostaje blokadę, drugi nie", function()
			local map = fakeMap()
			t.expect(claim(map, "A")).toBe(true)
			t.expect(claim(map, "B")).toBe(false)
		end)
		t.it("lider odnawia blokadę i nikt mu jej nie zabiera", function()
			local map = fakeMap()
			claim(map, "A")
			for time = Config.MATCH_LEADER_RENEW, 60, Config.MATCH_LEADER_RENEW do
				map.now = time
				t.expect(claim(map, "B")).toBe(false)
				t.expect(claim(map, "A")).toBe(true)
			end
		end)
		t.it("padnięty lider oddaje blokadę po wygaśnięciu, a nowy lider widzi te same bilety", function()
			local leader, queue = fakeMap(), fakeMap()
			claim(leader, "A")
			queue.set("1", ticket(1, 0, false, "A"), Config.MATCH_TICKET_TTL)
			queue.set("2", ticket(2, 1, false, "B"), Config.MATCH_TICKET_TTL)

			leader.now = TTL - 0.1 -- A już się nie odzywa
			t.expect(claim(leader, "B")).toBe(false)
			leader.now = TTL
			queue.now = TTL
			t.expect(claim(leader, "B")).toBe(true)
			t.expect(claim(leader, "A")).toBe(false) -- A wstał: czeka, aż B odda blokadę

			local decision = MatchQueue.decide(queue.range(), COUNTDOWN)
			t.expect(ids(decision.group)).toBe("1,2")
		end)
		t.it("wyjście lidera (usunięcie klucza) przekazuje rolę od razu", function()
			local map = fakeMap()
			claim(map, "A")
			map.remove("Leader")
			t.expect(claim(map, "B")).toBe(true)
		end)
		t.it("odnowienie biletów co MATCH_TICKET_RENEW zmieści się w czasie życia z zapasem", function()
			t.expect(Config.MATCH_TICKET_TTL > Config.MATCH_TICKET_RENEW * 3).toBe(true)
			t.expect(Config.MATCH_LEADER_TTL > Config.MATCH_LEADER_RENEW * 2).toBe(true)
		end)
	end)

	t.describe("dane z sieci", function()
		t.it("zły bilet to nil, dobry zachowuje pola", function()
			for _, bad in { "x", 1, {}, { userId = 1 }, { userId = "1", serverId = "A", joinedAt = 0 } } do
				t.expect(MatchQueue.parseTicket(bad)).toBe(nil)
			end
			local parsed = MatchQueue.parseTicket({ userId = 1, serverId = "A", joinedAt = 2, ready = true })
			t.expect(parsed.ready).toBe(true)
			t.expect(MatchQueue.parseTicket({ userId = 1, serverId = "A", joinedAt = 2 }).ready).toBe(false)
		end)
		t.it("Match: odrzuca zły kształt i za dużą grupę", function()
			local tooMany = {}
			for id = 1, CAPACITY + 1 do
				table.insert(tooMany, id)
			end
			for _, bad in {
				"x",
				{ river = "Test", userIds = {}, at = 0 },
				{ river = "Test", userIds = tooMany, at = 0 },
				{ river = "Test", userIds = { "1" }, at = 0 },
				{ river = "Test", userIds = { 1 } },
				{ river = 1, userIds = { 1 }, at = 0 },
				{ river = "Test", userIds = { 1 }, at = 0, code = 5 },
			} do
				t.expect(MatchQueue.parseMatch(bad)).toBe(nil)
			end
		end)
		t.it("Match bez kodu oznacza nieudaną rezerwację", function()
			t.expect(MatchQueue.parseMatch({ river = "Test", userIds = { 1 }, at = 0 }).code).toBe(nil)
			t.expect(MatchQueue.parseMatch({ river = "Test", userIds = { 1 }, at = 0, code = "c" }).code).toBe("c")
		end)
		t.it("QueueState pomija puste rzeki i przechodzi przez parsowanie", function()
			local encoded = MatchQueue.encodeState({
				Test = { count = 2, endsAt = 30, ready = 1 },
				Mountain = { count = 0, endsAt = nil, ready = 0 },
			})
			t.expect(encoded.Mountain).toBe(nil)
			local parsed = MatchQueue.parseState(encoded)
			t.expect(parsed.Test.count).toBe(2)
			t.expect(parsed.Test.endsAt).toBe(30)
			t.expect(parsed.Test.ready).toBe(1)
			t.expect(MatchQueue.parseState("x")).toBe(nil)
		end)
		t.it("tryb: brak to wyścig, nieznany jest odrzucany", function()
			t.expect(MatchQueue.parseMode(nil)).toBe("race")
			t.expect(MatchQueue.parseMode("race")).toBe("race")
			t.expect(MatchQueue.parseMode("battle")).toBe("battle")
			for _, bad in { "royale", 1, true, {} } do
				t.expect(MatchQueue.parseMode(bad)).toBe(nil)
			end
		end)
		t.it("wyścig zachowuje stary klucz, a Bitwa ma osobną kolejkę", function()
			t.expect(MatchQueue.queueKey("Test", "race")).toBe("Test")
			t.expect(MatchQueue.queueKey("Test", "battle") ~= "Test").toBe(true)
		end)
		t.it("Match niesie tryb, stara wiadomość to wyścig, a zły tryb odpada", function()
			t.expect(MatchQueue.parseMatch({ river = "Test", userIds = { 1 }, at = 0 }).mode).toBe("race")
			t.expect(MatchQueue.parseMatch({ river = "Test", mode = "battle", userIds = { 1 }, at = 0 }).mode).toBe("battle")
			t.expect(MatchQueue.parseMatch({ river = "Test", mode = "x", userIds = { 1 }, at = 0 })).toBe(nil)
		end)
		t.it("gracz stoi w jednej kolejce także między trybami", function()
			local race, battle = MatchQueue.queueKey("Test", "race"), MatchQueue.queueKey("Test", "battle")
			local result = MatchQueue.dedupe({ [race] = { ticket(1, 1) }, [battle] = { ticket(1, 2) } })
			t.expect(#result[race]).toBe(0)
			t.expect(#result[battle]).toBe(1)
		end)
		t.it("tryb: brak to wyścig, nieznany jest odrzucany", function()
			t.expect(MatchQueue.parseMode(nil)).toBe("race")
			t.expect(MatchQueue.parseMode("race")).toBe("race")
			t.expect(MatchQueue.parseMode("battle")).toBe("battle")
			for _, bad in { "royale", 1, true, {} } do
				t.expect(MatchQueue.parseMode(bad)).toBe(nil)
			end
		end)
		t.it("wyścig zachowuje stary klucz, a Bitwa ma osobną kolejkę", function()
			t.expect(MatchQueue.queueKey("Test", "race")).toBe("Test")
			t.expect(MatchQueue.queueKey("Test", "battle") ~= "Test").toBe(true)
		end)
		t.it("Match niesie tryb, stara wiadomość to wyścig, a zły tryb odpada", function()
			t.expect(MatchQueue.parseMatch({ river = "Test", userIds = { 1 }, at = 0 }).mode).toBe("race")
			t.expect(MatchQueue.parseMatch({ river = "Test", mode = "battle", userIds = { 1 }, at = 0 }).mode).toBe("battle")
			t.expect(MatchQueue.parseMatch({ river = "Test", mode = "x", userIds = { 1 }, at = 0 })).toBe(nil)
		end)
		t.it("gracz stoi w jednej kolejce także między trybami", function()
			local race, battle = MatchQueue.queueKey("Test", "race"), MatchQueue.queueKey("Test", "battle")
			local result = MatchQueue.dedupe({ [race] = { ticket(1, 1) }, [battle] = { ticket(1, 2) } })
			t.expect(#result[race]).toBe(0)
			t.expect(#result[battle]).toBe(1)
		end)
		t.it("wiadomości mieszczą się w limicie 1 kB MessagingService", function()
			local userIds = {}
			for _ = 1, CAPACITY do
				table.insert(userIds, 99999999999)
			end
			local match = 200 + #table.concat(userIds, ",") + 300 -- pola + identyfikatory + zapas na długi kod dostępu
			t.expect(match).toBeLessThan(1000)
			local states = 7 * #'"Mountain":{"count":8,"endsAt":1798761600.123,"ready":8},'
			t.expect(states).toBeLessThan(1000)
		end)
	end)

	t.describe("ponowienia teleportu", function()
		t.it("każda próba ma przerwę, a po ostatniej koniec", function()
			t.expect(MatchQueue.retryDelay(1, "GameNotFound")).toBe(Config.TRAVEL_RETRY_WAIT)
			t.expect(MatchQueue.retryDelay(Config.TRAVEL_TRIES - 1, "Failure")).toBe(Config.TRAVEL_RETRY_WAIT)
			t.expect(MatchQueue.retryDelay(Config.TRAVEL_TRIES, "Failure")).toBe(nil)
		end)
		t.it("Flooded czeka dłużej, Unauthorized się nie ponawia", function()
			t.expect(MatchQueue.retryDelay(1, "Flooded")).toBe(Config.TRAVEL_FLOOD_WAIT)
			t.expect(MatchQueue.retryDelay(1, "Unauthorized")).toBe(nil)
		end)
		t.it("spóźnialski nie zatrzymuje spływu: ponowienia kończą się przed RACE_GATHER_TIME", function()
			local total = (Config.TRAVEL_TRIES - 1) * Config.TRAVEL_RETRY_WAIT
			t.expect(total).toBeLessThan(Config.RACE_GATHER_TIME)
		end)
	end)

	t.describe("awaria MemoryStore", function()
		t.it("startuje w trybie lokalnym, pierwszy sukces włącza kolejkę", function()
			local health = MatchQueue.newHealth()
			t.expect(health.down).toBe(true)
			t.expect(MatchQueue.report(health, false)).toBe(false)
			t.expect(MatchQueue.report(health, true)).toBe(true)
			t.expect(health.down).toBe(false)
		end)
		t.it("pojedyncze błędy nie przełączają, seria tak, i tylko raz", function()
			local health = MatchQueue.newHealth()
			MatchQueue.report(health, true)
			for _ = 1, Config.MATCH_FAIL_LIMIT - 1 do
				t.expect(MatchQueue.report(health, false)).toBe(false)
			end
			t.expect(MatchQueue.report(health, true)).toBe(false) -- sukces zeruje licznik
			for _ = 1, Config.MATCH_FAIL_LIMIT - 1 do
				MatchQueue.report(health, false)
			end
			t.expect(MatchQueue.report(health, false)).toBe(true)
			t.expect(health.down).toBe(true)
			t.expect(MatchQueue.report(health, false)).toBe(false)
		end)
	end)
end
