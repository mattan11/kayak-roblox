-- Zasady trybu Bitwa: czysta logika bez Instance, bez zegara i bez sieci (testy: logic/BattleRules.spec, kontrakt: ARCHITECTURE.md).
-- Rozmieszczenie skrzynek liczy też klient, reszta to stan rundy, który zmienia Systems/BattleService. Czas `now` i generator
-- losowy podaje wołający, a wynik każdej funkcji to opis skutków do wysłania, nie samo wysłanie.
-- (Dla TS: reducer: `(state, action) => effects`. Generator wstrzykujemy jak `() => number` zamiast Math.random, żeby test był powtarzalny.)
--
-- Gracze wchodzą jako `fighters`: migawka tego, co serwer sam odczytał z Hull i RaceLogic. Klient niczego tu nie dostarcza.

local Config = require(script.Parent.Config)

local BattleRules = {}

export type Item = "boost" | "shield" | "net" | "cannon"
export type CrateKind = Item | "mystery" -- "mystery" = skrzynka „?”, przedmiot losowany przy zebraniu
export type Crate = { index: number, position: Vector2, s: number, kind: CrateKind }
export type Net = { id: number, ownerId: number, position: Vector2, expiresAt: number }
export type Fighter = {
	position: Vector2,
	forward: Vector2, -- kierunek dziobu, wektor jednostkowy
	s: number, -- postęp wzdłuż rzeki
	finished: boolean, -- na mecie: nie atakuje, nie zbiera i nie jest celem, ale liczy się do miejsc
}
export type Holder = { item: Item?, shield: boolean, protectedUntil: number, readyAt: number }
export type Effect = { id: number, kind: "stun" | "slow" | "boost" | "shieldHit", time: number }
export type Outcome = { item: Item, effects: { Effect }, net: Net? }
export type Pickup = { id: number, index: number, item: Item }
export type Sweep = { removed: { Net }, effects: { Effect } }
export type State = {
	crates: { Crate },
	respawnAt: { [number]: number }, -- numer zabranej skrzynki → kiedy wraca
	holders: { [number]: Holder }, -- userId → stan gracza; zgłoszenie po wyjściu po prostu nikogo tu nie znajdzie
	nets: { Net },
	nextNetId: number,
}

-- Kolejność ma znaczenie: to na tej liście opiera się losowanie, a tabela w Luau nie ma gwarantowanej kolejności kluczy.
BattleRules.ITEMS = { "boost", "shield", "net", "cannon" } :: { Item }

-- Skrzynki ---------------------------------------------------------------------------------------------------------------

local function nearFall(river: any, s: number): boolean
	for _, fall in river.falls do
		if math.abs(fall.s - s) < Config.BATTLE_CRATE_FALL_CLEAR then
			return true
		end
	end
	return false
end

local function nearRock(river: any, position: Vector2): boolean
	for _, rock in river.rocks do
		if (rock.position - position).Magnitude < rock.radius + Config.BATTLE_CRATE_ROCK_CLEAR then
			return true
		end
	end
	return false
end

-- Skrzynki na trasie: rzędy po 3 w poprzek. Zależy tylko od rzeki i Config, więc serwer i klient mają te same numery i te same ikony.
-- Skała wycina pojedynczą skrzynkę, a wodospad cały rząd. W każdym rzędzie jedna skrzynka to „?”, na kolejnym torze niż w poprzednim
-- rzędzie, a dwie pokazują przedmioty z ITEMS po kolei: gracz wybiera sterowaniem, co bierze.
function BattleRules.crates(river: any): { Crate }
	local list: { Crate } = {}
	local last = river.length - Config.FINISH_MARGIN - Config.BATTLE_CRATE_FINISH_CLEAR
	local s = Config.START_LINE + Config.BATTLE_CRATE_START
	local row = 0
	local shown = 0 -- ile przedmiotów rozdano na ikony
	while s <= last do
		if not nearFall(river, s) then
			local center = river:pointAt(s)
			local q = river:query(center)
			local mysteryLane = row % 3 - 1
			row += 1
			for lane = -1, 1 do
				local kind: CrateKind = "mystery"
				if lane ~= mysteryLane then
					kind = BattleRules.ITEMS[shown % #BattleRules.ITEMS + 1]
					shown += 1
				end
				local position = center + q.normal * (lane * Config.BATTLE_CRATE_LANE * q.halfWidth)
				if not nearRock(river, position) then
					table.insert(list, { index = #list + 1, position = position, s = s, kind = kind })
				end
			end
		end
		s += Config.BATTLE_CRATE_SPACING
	end
	return list
end

function BattleRules.newState(crates: { Crate }): State
	return { crates = crates, respawnAt = {}, holders = {}, nets = {}, nextNetId = 1 }
end

-- Stan gracza tworzony przy pierwszej potrzebie: spóźnialski dołącza bez osobnego kroku.
local function holderOf(state: State, id: number): Holder
	local holder = state.holders[id]
	if holder == nil then
		holder = { item = nil, shield = false, protectedUntil = 0, readyAt = 0 }
		state.holders[id] = holder
	end
	return holder
end

-- Gracz wyszedł z serwera. Jego siatki zostają na wodzie: to zwykłe przeszkody, które znikną same.
function BattleRules.remove(state: State, id: number)
	state.holders[id] = nil
end

-- Czy ktoś ma właśnie ochronę? Chroniony nie jest celem, a siatka go przepuszcza i czeka na następnego.
function BattleRules.isProtected(state: State, id: number, now: number): boolean
	local holder = state.holders[id]
	return holder ~= nil and now < holder.protectedUntil
end

-- Przedmioty --------------------------------------------------------------------------------------------------------------

-- Id graczy rosnąco: `pairs` nie ma stałej kolejności, a dwa odczyty tych samych danych mają dać ten sam wynik.
local function sortedIds(fighters: { [number]: Fighter }): { number }
	local ids: { number } = {}
	for id in fighters do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Miejsca: 1 = najdalej wzdłuż rzeki. Remis rozstrzyga userId.
function BattleRules.ranks(fighters: { [number]: Fighter }): { [number]: number }
	local ids = sortedIds(fighters)
	table.sort(ids, function(a, b)
		local sa, sb = fighters[a].s, fighters[b].s
		if sa ~= sb then
			return sa > sb
		end
		return a < b
	end)
	local ranks: { [number]: number } = {}
	for rank, id in ids do
		ranks[id] = rank
	end
	return ranks
end

-- Losowanie wg miejsca. `random` zwraca liczbę z [0, 1), jak Math.random w JS. Solo dostaje boost: reszta nie miałaby celu.
function BattleRules.rollItem(rank: number, count: number, random: () -> number): Item
	if count <= 1 then
		return "boost"
	end
	local behind = math.clamp((rank - 1) / (count - 1), 0, 1) -- 0 = prowadzący, 1 = ostatni
	local weights: { number } = {}
	local total = 0
	for index, item in BattleRules.ITEMS do
		local entry = Config.BATTLE_ITEM_WEIGHTS[item]
		weights[index] = entry.front + (entry.back - entry.front) * behind
		total += weights[index]
	end
	local roll = random() * total
	for index, item in BattleRules.ITEMS do
		roll -= weights[index]
		if roll < 0 then
			return item
		end
	end
	return BattleRules.ITEMS[#BattleRules.ITEMS] -- błąd zaokrąglenia przy samej górze zakresu
end

-- Kto przepływa teraz przez skrzynkę. Zebranie zastępuje trzymany przedmiot, więc niechciany wymienia się na inny albo dowolną „?”.
-- Skrzynka z tym, co gracz już ma, zostaje dla innych. Wynik: lista do wysłania jako BattleItem i BattleCrate.
function BattleRules.collect(state: State, fighters: { [number]: Fighter }, now: number, random: () -> number): { Pickup }
	local pickups: { Pickup } = {}
	local ranks = BattleRules.ranks(fighters)
	local count = #sortedIds(fighters)
	for _, id in sortedIds(fighters) do
		local fighter = fighters[id]
		local holder = holderOf(state, id)
		if not fighter.finished then
			for _, crate in state.crates do
				-- Najpierw tanie porównanie wzdłuż rzeki: 8 graczy × ok. 90 skrzynek × 10 razy na sekundę.
				if
					math.abs(crate.s - fighter.s) <= Config.BATTLE_CRATE_RADIUS * 2
					and state.respawnAt[crate.index] == nil
					and crate.kind ~= holder.item
					and (crate.position - fighter.position).Magnitude <= Config.BATTLE_CRATE_RADIUS
				then
					local item: Item = if crate.kind == "mystery" then BattleRules.rollItem(ranks[id], count, random) else crate.kind
					holder.item = item
					state.respawnAt[crate.index] = now + Config.BATTLE_CRATE_RESPAWN
					table.insert(pickups, { id = id, index = crate.index, item = item })
					break
				end
			end
		end
	end
	return pickups
end

-- Skrzynki, którym minął czas odnowienia. Wynik: ich numery.
function BattleRules.respawn(state: State, now: number): { number }
	local back: { number } = {}
	for index, at in state.respawnAt do
		if now >= at then
			table.insert(back, index)
		end
	end
	for _, index in back do
		state.respawnAt[index] = nil
	end
	table.sort(back)
	return back
end

-- Ataki ---------------------------------------------------------------------------------------------------------------------

-- Najbliższy cel armatki albo nil. Pomija siebie, graczy na mecie i chronionych (atak przeszedłby na marne), a tarcza nie chroni
-- przed wyborem: zdejmuje ją dopiero trafienie. Warunek `s` odrzuca kajak z sąsiedniego zakola: blisko w linii prostej, ale za brzegiem.
function BattleRules.pickTarget(state: State, attackerId: number, fighters: { [number]: Fighter }, now: number): number?
	local attacker = fighters[attackerId]
	if attacker == nil then
		return nil
	end
	local range, arc = Config.BATTLE_CANNON_RANGE, Config.BATTLE_CANNON_ARC_COS
	local bestId: number? = nil
	local bestDistance = math.huge
	for _, id in sortedIds(fighters) do
		local fighter = fighters[id]
		if id ~= attackerId and not fighter.finished and not BattleRules.isProtected(state, id, now) then
			local offset = fighter.position - attacker.position
			local distance = offset.Magnitude
			-- Dwa kajaki w jednym punkcie: kierunek nieokreślony (Unit dałby NaN), więc cel uznajemy za trafiony.
			local facing = if distance > 0 then offset.Unit:Dot(attacker.forward) else 1
			local alongRiver = math.abs(fighter.s - attacker.s)
			if distance <= range and distance < bestDistance and facing >= arc and alongRiver <= range * Config.BATTLE_BEND_SLACK then
				bestId, bestDistance = id, distance
			end
		end
	end
	return bestId
end

-- Trafienie gracza: najpierw ochrona, potem tarcza, na końcu ogłuszenie. Nil = atak nic nie dał.
-- Ochrona liczy się od końca ogłuszenia, więc zawsze wypada po nim (dla TS: `until = now + stun + protect`).
function BattleRules.hit(state: State, id: number, now: number): Effect?
	if BattleRules.isProtected(state, id, now) then
		return nil
	end
	local holder = holderOf(state, id)
	if holder.shield then
		holder.shield = false
		return { id = id, kind = "shieldHit", time = 0 }
	end
	holder.protectedUntil = now + Config.BATTLE_STUN_TIME + Config.BATTLE_PROTECT_TIME
	return { id = id, kind = "stun", time = Config.BATTLE_STUN_TIME }
end

-- Prośba o użycie przedmiotu. Nil = odmowa i przedmiot zostaje: brak przedmiotu, gracza, zbyt szybko, gracz na mecie albo brak celu.
function BattleRules.use(state: State, id: number, fighters: { [number]: Fighter }, now: number): Outcome?
	local holder = state.holders[id]
	local fighter = fighters[id]
	if holder == nil or fighter == nil or fighter.finished or now < holder.readyAt then
		return nil
	end
	local item = holder.item
	if item == nil then
		return nil
	end

	local outcome: Outcome = { item = item, effects = {}, net = nil }
	if item == "boost" then
		table.insert(outcome.effects, { id = id, kind = "boost", time = Config.BATTLE_BOOST_TIME })
	elseif item == "shield" then
		holder.shield = true
	elseif item == "net" then
		local net: Net = {
			id = state.nextNetId,
			ownerId = id,
			position = fighter.position - fighter.forward * Config.BATTLE_NET_BEHIND,
			expiresAt = now + Config.BATTLE_NET_LIFETIME,
		}
		state.nextNetId += 1
		table.insert(state.nets, net)
		outcome.net = net
	else
		local target = BattleRules.pickTarget(state, id, fighters, now)
		if target == nil then
			return nil
		end
		local effect = BattleRules.hit(state, target, now)
		if effect then
			table.insert(outcome.effects, effect)
		end
	end
	holder.item = nil
	holder.readyAt = now + Config.BATTLE_USE_COOLDOWN
	return outcome
end

-- Obieg siatek: każda znika po czasie albo po pierwszym trafieniu. Właściciel, gracz na mecie i chroniony przepływają bez skutku.
-- Ogłuszenie z siatki niesie też spowolnienie; tarcza zatrzymuje oba.
function BattleRules.sweepNets(state: State, fighters: { [number]: Fighter }, now: number): Sweep
	local sweep: Sweep = { removed = {}, effects = {} }
	local ids = sortedIds(fighters)
	local kept: { Net } = {}
	for _, net in state.nets do
		local gone = now >= net.expiresAt
		if not gone then
			for _, id in ids do
				local fighter = fighters[id]
				local caught = id ~= net.ownerId
					and not fighter.finished
					and not BattleRules.isProtected(state, id, now)
					and (fighter.position - net.position).Magnitude <= Config.BATTLE_NET_RADIUS
				if caught then
					local effect = BattleRules.hit(state, id, now)
					if effect then
						table.insert(sweep.effects, effect)
						if effect.kind == "stun" then
							table.insert(sweep.effects, { id = id, kind = "slow", time = Config.BATTLE_NET_SLOW_TIME })
						end
					end
					gone = true
					break
				end
			end
		end
		table.insert(if gone then sweep.removed else kept, net)
	end
	state.nets = kept
	return sweep
end

return BattleRules
