-- Zasady Bitwy: skrzynki na prawdziwych rzekach, losowanie wg miejsca, wybór celu i kolejność obrony.

return function(t)
	local BattleRules = require(t.shared.BattleRules)
	local Config = require(t.shared.Config)
	local River = require(t.shared.River)

	local rivers = {
		River.new(require(t.shared.content.rivers.Test)),
		River.new(require(t.shared.content.rivers.Mountain)),
	}

	-- Generator o stałej wartości: test wskazuje palcem miejsce w przedziale [0, 1).
	local function fixed(value: number): () -> number
		return function()
			return value
		end
	end

	-- Kajak płynący w +X, jeśli nie podano inaczej. `s` domyślnie zgadza się z pozycją, czyli rzeka prosta.
	local function fighter(x: number, z: number?, forward: Vector2?)
		return { position = Vector2.new(x, z or 0), forward = forward or Vector2.xAxis, s = x, finished = false }
	end

	local function emptyState()
		return BattleRules.newState({})
	end

	local function crate(kind: string?)
		return { index = 1, position = Vector2.new(100, 0), s = 100, kind = kind or "mystery" }
	end

	local function give(state: any, id: number, item: string)
		state.holders[id] = { item = item, shield = false, protectedUntil = 0, readyAt = 0 }
	end

	t.describe("skrzynki", function()
		t.it("każda rzeka ma skrzynki z kolejnymi numerami, na wodzie i w tej samej kolejności", function()
			for _, river in rivers do
				local crates = BattleRules.crates(river)
				t.expect(#crates > 30).toBe(true)
				for index, entry in crates do
					t.expect(entry.index).toBe(index)
					local q = river:query(entry.position)
					t.expect(math.abs(q.lateral) < q.halfWidth).toBe(true)
				end
				local again = BattleRules.crates(river)
				t.expect(#again).toBe(#crates)
				t.expect(again[#again].position).toBe(crates[#crates].position)
				t.expect(again[#again].kind).toBe(crates[#crates].kind)
			end
		end)
		t.it("trzymają się z dala od skał, wodospadów, startu i mety", function()
			for _, river in rivers do
				for _, entry in BattleRules.crates(river) do
					for _, rock in river.rocks do
						local gap = (rock.position - entry.position).Magnitude - rock.radius
						t.expect(gap >= Config.BATTLE_CRATE_ROCK_CLEAR).toBe(true)
					end
					for _, fall in river.falls do
						t.expect(math.abs(fall.s - entry.s) >= Config.BATTLE_CRATE_FALL_CLEAR).toBe(true)
					end
					t.expect(entry.s > Config.START_LINE).toBe(true)
					t.expect(entry.s < river.length - Config.FINISH_MARGIN).toBe(true)
				end
			end
		end)
		t.it("zebranie daje przedmiot, a skrzynka wraca po czasie", function()
			local state = BattleRules.newState({ crate() })
			local fighters = { [1] = fighter(100) }
			local pickups = BattleRules.collect(state, fighters, 10, fixed(0))
			t.expect(#pickups).toBe(1)
			t.expect(pickups[1].item).toBe("boost") -- solo
			t.expect(state.holders[1].item).toBe("boost")
			-- Druga osoba nie zbierze zabranej skrzynki.
			t.expect(#BattleRules.collect(state, { [1] = fighter(100), [2] = fighter(100) }, 11, fixed(0))).toBe(0)
			t.expect(#BattleRules.respawn(state, 10 + Config.BATTLE_CRATE_RESPAWN - 0.1)).toBe(0)
			t.expect(BattleRules.respawn(state, 10 + Config.BATTLE_CRATE_RESPAWN)[1]).toBe(1)
			t.expect(state.respawnAt[1]).toBe(nil)
		end)
		t.it("każdy rząd ma skrzynkę „?” i wszystkie przedmioty są do wybrania", function()
			for _, river in rivers do
				local rows: { [number]: number } = {}
				local seen: { [string]: boolean } = {}
				for _, entry in BattleRules.crates(river) do
					seen[entry.kind] = true
					if entry.kind == "mystery" then
						rows[entry.s] = (rows[entry.s] or 0) + 1
					end
				end
				t.expect(seen.mystery).toBe(true)
				for _, item in BattleRules.ITEMS do
					t.expect(seen[item]).toBe(true)
				end
				for _, count in rows do
					t.expect(count).toBe(1)
				end
			end
		end)
		t.it("skrzynka z ikoną daje dokładnie to, co pokazuje, bez losowania", function()
			local state = BattleRules.newState({ crate("cannon") })
			local pickups = BattleRules.collect(state, { [1] = fighter(100), [2] = fighter(0) }, 0, function(): number
				error("losowanie niepotrzebne")
			end)
			t.expect(pickups[1].item).toBe("cannon")
		end)
		t.it("wpłynięcie w skrzynkę wymienia niechciany przedmiot", function()
			local state = BattleRules.newState({ crate("boost") })
			give(state, 1, "net")
			t.expect(BattleRules.collect(state, { [1] = fighter(100) }, 0, fixed(0))[1].item).toBe("boost")
			t.expect(state.holders[1].item).toBe("boost")
		end)
		t.it("skrzynka z tym samym przedmiotem zostaje dla innych", function()
			local state = BattleRules.newState({ crate("net") })
			give(state, 1, "net")
			t.expect(#BattleRules.collect(state, { [1] = fighter(100) }, 0, fixed(0))).toBe(0)
			t.expect(state.respawnAt[1]).toBe(nil)
		end)
		t.it("poza zasięgiem i po mecie nic się nie dzieje", function()
			local state = BattleRules.newState({ crate() })
			local done = fighter(100)
			done.finished = true
			t.expect(#BattleRules.collect(state, { [1] = fighter(100, Config.BATTLE_CRATE_RADIUS + 1), [2] = done }, 0, fixed(0))).toBe(0)
		end)
	end)

	t.describe("losowanie", function()
		t.it("miejsca liczą się od najdalszego, a remis rozstrzyga id", function()
			local ranks = BattleRules.ranks({ [7] = fighter(50), [3] = fighter(90), [9] = fighter(50) })
			t.expect(ranks[3]).toBe(1)
			t.expect(ranks[7]).toBe(2)
			t.expect(ranks[9]).toBe(3)
		end)
		t.it("solo zawsze boost", function()
			for _, roll in { 0, 0.5, 0.999 } do
				t.expect(BattleRules.rollItem(1, 1, fixed(roll))).toBe("boost")
			end
		end)
		t.it("prowadzący nigdy nie dostaje armatki, a ostatni dostaje ją najczęściej", function()
			local function share(rank: number, item: string): number
				local hits = 0
				for step = 0, 999 do
					if BattleRules.rollItem(rank, 8, fixed(step / 1000)) == item then
						hits += 1
					end
				end
				return hits
			end
			t.expect(share(1, "cannon")).toBe(0)
			t.expect(share(8, "cannon") > share(4, "cannon")).toBe(true)
			t.expect(share(4, "cannon") > 0).toBe(true)
			t.expect(share(1, "net") > share(8, "net")).toBe(true)
		end)
		t.it("cały zakres generatora daje znany przedmiot", function()
			for _, roll in { 0, 0.25, 0.5, 0.75, 0.9999999 } do
				for rank = 1, 8 do
					t.expect(table.find(BattleRules.ITEMS, BattleRules.rollItem(rank, 8, fixed(roll))) ~= nil).toBe(true)
				end
			end
		end)
		t.it("każdy przedmiot ma wagi w Config", function()
			for _, item in BattleRules.ITEMS do
				t.expect(type(Config.BATTLE_ITEM_WEIGHTS[item])).toBe("table")
			end
		end)
	end)

	t.describe("wybór celu", function()
		t.it("najbliższy w zasięgu, nigdy on sam", function()
			local state = emptyState()
			local fighters = { [1] = fighter(0), [2] = fighter(10), [3] = fighter(6) }
			t.expect(BattleRules.pickTarget(state, 1, fighters, 0)).toBe(3)
			t.expect(BattleRules.pickTarget(state, 1, { [1] = fighter(0) }, 0)).toBe(nil)
		end)
		t.it("armatka tylko w stożku przed dziobem i do swojego zasięgu", function()
			local state = emptyState()
			local range = Config.BATTLE_CANNON_RANGE
			t.expect(BattleRules.pickTarget(state, 1, { [1] = fighter(0), [2] = fighter(range) }, 0)).toBe(2)
			t.expect(BattleRules.pickTarget(state, 1, { [1] = fighter(0), [2] = fighter(range + 1) }, 0)).toBe(nil)
			t.expect(BattleRules.pickTarget(state, 1, { [1] = fighter(0), [2] = fighter(0, 20) }, 0)).toBe(nil)
		end)
		t.it("kieruje się dziobem kajaka, nie osią świata", function()
			local state = emptyState()
			local fighters = { [1] = fighter(0, 0, Vector2.new(0, 1)), [2] = fighter(0, 30), [3] = fighter(30) }
			t.expect(BattleRules.pickTarget(state, 1, fighters, 0)).toBe(2)
		end)
		t.it("nie strzela przez brzeg do sąsiedniego zakola", function()
			local bend = fighter(30)
			bend.s = 30 + Config.BATTLE_CANNON_RANGE * Config.BATTLE_BEND_SLACK + 1
			t.expect(BattleRules.pickTarget(emptyState(), 1, { [1] = fighter(0), [2] = bend }, 0)).toBe(nil)
		end)
		t.it("pomija chronionych i tych na mecie", function()
			local state = emptyState()
			state.holders[2] = { shield = false, protectedUntil = 5, readyAt = 0 }
			local done = fighter(5)
			done.finished = true
			local fighters = { [1] = fighter(0), [2] = fighter(3), [3] = done, [4] = fighter(10) }
			t.expect(BattleRules.pickTarget(state, 1, fighters, 1)).toBe(4)
		end)
		t.it("kajak w tym samym punkcie nie psuje rachunku", function()
			t.expect(BattleRules.pickTarget(emptyState(), 1, { [1] = fighter(0), [2] = fighter(0) }, 0)).toBe(2)
		end)
	end)

	t.describe("trafienia", function()
		t.it("ogłuszenie, a potem ochrona na czas ogłuszenia i BATTLE_PROTECT_TIME", function()
			local state = emptyState()
			local effect = BattleRules.hit(state, 2, 10)
			t.expect(effect.kind).toBe("stun")
			t.expect(effect.time).toBe(Config.BATTLE_STUN_TIME)
			local until_ = 10 + Config.BATTLE_STUN_TIME + Config.BATTLE_PROTECT_TIME
			t.expect(BattleRules.hit(state, 2, until_ - 0.1)).toBe(nil)
			t.expect(BattleRules.hit(state, 2, until_).kind).toBe("stun")
		end)
		t.it("tarcza blokuje dokładnie jeden atak i nie daje ochrony", function()
			local state = emptyState()
			give(state, 2, "shield")
			local fighters = { [2] = fighter(0) }
			t.expect(BattleRules.use(state, 2, fighters, 0).item).toBe("shield")
			t.expect(state.holders[2].item).toBe(nil)
			t.expect(BattleRules.hit(state, 2, 1).kind).toBe("shieldHit")
			t.expect(BattleRules.isProtected(state, 2, 1)).toBe(false)
			t.expect(BattleRules.hit(state, 2, 2).kind).toBe("stun")
		end)
		t.it("chroniony gracz zachowuje tarczę", function()
			local state = emptyState()
			state.holders[2] = { shield = true, protectedUntil = 10, readyAt = 0 }
			t.expect(BattleRules.hit(state, 2, 1)).toBe(nil)
			t.expect(state.holders[2].shield).toBe(true)
		end)
	end)

	t.describe("użycie przedmiotu", function()
		t.it("bez przedmiotu albo bez gracza nic się nie dzieje", function()
			local state = emptyState()
			t.expect(BattleRules.use(state, 1, { [1] = fighter(0) }, 0)).toBe(nil)
			give(state, 1, "boost")
			t.expect(BattleRules.use(state, 1, {}, 0)).toBe(nil)
			t.expect(state.holders[1].item).toBe("boost")
		end)
		t.it("boost działa na użytkownika, a przedmiot znika", function()
			local state = emptyState()
			give(state, 1, "boost")
			local outcome = BattleRules.use(state, 1, { [1] = fighter(0) }, 0)
			t.expect(outcome.effects[1].id).toBe(1)
			t.expect(outcome.effects[1].kind).toBe("boost")
			t.expect(outcome.effects[1].time).toBe(Config.BATTLE_BOOST_TIME)
			t.expect(BattleRules.use(state, 1, { [1] = fighter(0) }, 5)).toBe(nil)
		end)
		t.it("czas odnowienia dotyczy też następnego przedmiotu", function()
			local state = emptyState()
			local fighters = { [1] = fighter(0) }
			give(state, 1, "boost")
			BattleRules.use(state, 1, fighters, 10)
			state.holders[1].item = "boost"
			t.expect(BattleRules.use(state, 1, fighters, 10 + Config.BATTLE_USE_COOLDOWN - 0.1)).toBe(nil)
			t.expect(BattleRules.use(state, 1, fighters, 10 + Config.BATTLE_USE_COOLDOWN) ~= nil).toBe(true)
		end)
		t.it("atak bez celu nie zabiera przedmiotu ani nie rusza czasu odnowienia", function()
			local state = emptyState()
			give(state, 1, "cannon")
			t.expect(BattleRules.use(state, 1, { [1] = fighter(0) }, 0)).toBe(nil)
			t.expect(state.holders[1].item).toBe("cannon")
			t.expect(state.holders[1].readyAt).toBe(0)
		end)
		t.it("atak ogłusza cel", function()
			local state = emptyState()
			give(state, 1, "cannon")
			local outcome = BattleRules.use(state, 1, { [1] = fighter(0), [2] = fighter(5) }, 0)
			t.expect(outcome.effects[1].id).toBe(2)
			t.expect(outcome.effects[1].kind).toBe("stun")
		end)
		t.it("gracz na mecie nie używa przedmiotów", function()
			local state = emptyState()
			give(state, 1, "boost")
			local done = fighter(0)
			done.finished = true
			t.expect(BattleRules.use(state, 1, { [1] = done }, 0)).toBe(nil)
		end)
	end)

	t.describe("siatka", function()
		local function layNet(state: any, x: number, now: number): any
			give(state, 1, "net")
			return BattleRules.use(state, 1, { [1] = fighter(x) }, now).net
		end

		t.it("powstaje za kajakiem", function()
			local net = layNet(emptyState(), 100, 0)
			t.expect(net.position).toBe(Vector2.new(100 - Config.BATTLE_NET_BEHIND, 0))
		end)
		t.it("właściciel jej nie uruchamia", function()
			local state = emptyState()
			local net = layNet(state, 100, 0)
			local sweep = BattleRules.sweepNets(state, { [1] = fighter(net.position.X) }, 1)
			t.expect(#sweep.removed).toBe(0)
			t.expect(#state.nets).toBe(1)
		end)
		t.it("ogłusza i spowalnia pierwszego, a potem znika", function()
			local state = emptyState()
			local net = layNet(state, 100, 0)
			local x = net.position.X
			local sweep = BattleRules.sweepNets(state, { [2] = fighter(x), [3] = fighter(x) }, 1)
			t.expect(#sweep.removed).toBe(1)
			t.expect(#sweep.effects).toBe(2)
			t.expect(sweep.effects[1].id).toBe(2)
			t.expect(sweep.effects[1].kind).toBe("stun")
			t.expect(sweep.effects[2].id).toBe(2)
			t.expect(sweep.effects[2].kind).toBe("slow")
			t.expect(sweep.effects[2].time).toBe(Config.BATTLE_NET_SLOW_TIME)
			t.expect(#state.nets).toBe(0)
		end)
		t.it("znika po czasie bez trafienia", function()
			local state = emptyState()
			layNet(state, 100, 0)
			t.expect(#BattleRules.sweepNets(state, {}, Config.BATTLE_NET_LIFETIME - 0.1).removed).toBe(0)
			local sweep = BattleRules.sweepNets(state, {}, Config.BATTLE_NET_LIFETIME)
			t.expect(#sweep.removed).toBe(1)
			t.expect(#sweep.effects).toBe(0)
		end)
		t.it("chroniony przepływa, a siatka czeka na następnego", function()
			local state = emptyState()
			local net = layNet(state, 100, 0)
			state.holders[2] = { shield = false, protectedUntil = 5, readyAt = 0 }
			local sweep = BattleRules.sweepNets(state, { [2] = fighter(net.position.X) }, 1)
			t.expect(#sweep.removed).toBe(0)
			t.expect(#state.nets).toBe(1)
		end)
		t.it("tarcza zatrzymuje siatkę kosztem tarczy", function()
			local state = emptyState()
			local net = layNet(state, 100, 0)
			state.holders[2] = { shield = true, protectedUntil = 0, readyAt = 0 }
			local sweep = BattleRules.sweepNets(state, { [2] = fighter(net.position.X) }, 1)
			t.expect(sweep.effects[1].kind).toBe("shieldHit")
			t.expect(#sweep.effects).toBe(1)
			t.expect(#state.nets).toBe(0)
		end)
	end)

	t.describe("gracz, który wyszedł", function()
		t.it("znika ze stanu, a jego prośby i cudze ataki nie psują rundy", function()
			local state = emptyState()
			give(state, 1, "net")
			local net = BattleRules.use(state, 1, { [1] = fighter(100) }, 0).net
			give(state, 1, "boost")
			BattleRules.remove(state, 1)
			t.expect(state.holders[1]).toBe(nil)
			t.expect(BattleRules.use(state, 1, {}, 5)).toBe(nil)
			t.expect(BattleRules.pickTarget(state, 1, {}, 5)).toBe(nil)
			-- Siatka zostaje i dalej działa, także na tego, kto wszedł później.
			local sweep = BattleRules.sweepNets(state, { [2] = fighter(net.position.X) }, 6)
			t.expect(#sweep.removed).toBe(1)
		end)
	end)
end
