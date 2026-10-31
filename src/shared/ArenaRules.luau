-- Zasady Wodnej bitwy: czysta logika bez Instance, bez zegara i bez sieci (testy: logic/ArenaRules.spec, kontrakt: ARCHITECTURE.md).
-- Maszyna faz serwera, obrażenia, stożek celu, zwężanie strefy, kolejność odpadania i wynik po czasie. Czas `now` podaje wołający,
-- a świat wchodzi jako migawka pozycji, którą Systems/ArenaService sam odczytał z Hull. Klient niczego tu nie dostarcza.
-- (Dla TS: reducer: `(state, action) => effects`, jak BattleRules i RaceLogic. Zegar wstrzyknięty jak w testach z fake timers.)
--
-- Fazy mają te same nazwy co RaceLogic, a „racing” to tutaj walka: klient liczy fizykę w tej samej fazie co w wyścigu.

local Config = require(script.Parent.Config)

local ArenaRules = {}

export type Phase = "waiting" | "countdown" | "racing" | "results"
export type Entrant = { id: number, name: string }
export type Fighter = { position: Vector2, forward: Vector2 } -- forward: kierunek dziobu, wektor jednostkowy
export type Contender = {
	id: number,
	name: string,
	health: number, -- ułamkowa: strefa pali po trochu w każdym obiegu
	readyAt: number, -- od kiedy wolno strzelić
	place: number?, -- nil = wciąż na wodzie i w grze
}
export type Out = { userId: number, name: string, place: number }
export type Shot = { target: number?, out: Out? }
export type Row = { userId: number, name: string, place: number, health: number }
export type Match = {
	phase: Phase,
	phaseEndsAt: number,
	minPlayers: number, -- poniżej tej liczby runda nie rusza (1 tylko w Studio, do testów solo)
	expected: number?, -- ilu graczy wysłała wioska; nil = na nikogo nie czekamy
	gatherEndsAt: number?, -- do kiedy czekamy na resztę grupy (liczone od pierwszego gracza)
	aloneUntil: number?, -- gracz został sam: po tym czasie odsyłamy go do wioski, serwer zarezerwowany nikogo już nie przyjmie
	contenders: { [number]: Contender },
	entrants: number, -- ilu zaczęło rundę
	alive: number,
	startedAt: number?, -- start walki; z niego liczymy strefę
	endedAt: number?, -- koniec walki: strefa zatrzymuje się na ekranie wyników
	burnedAt: number, -- ostatnie liczenie obrażeń strefy
	rows: { Row }, -- wyniki ostatniej rundy, od pierwszego miejsca
	againVotes: { [number]: boolean }, -- kto kliknął „Jeszcze raz”
	leaving: { [number]: boolean }, -- kto kliknął „Do wioski” i jeszcze jest na serwerze
	leftCount: number, -- ilu odeszło z serwera od końca walki
}

-- Kolejne miejsca na okręgu, w ósemkach koła: dwa kajaki stają naprzeciw siebie, a każdy następny w największej luce.
-- Nie zależy to od liczby graczy, więc spóźnialski w odliczaniu po prostu bierze kolejne wolne miejsce.
local SPAWN_ORDER = { 0, 4, 2, 6, 1, 5, 3, 7 }

ArenaRules.SPAWN_SLOTS = #SPAWN_ORDER

-- Świat ----------------------------------------------------------------------------------------------------------------------

-- Punkt startu numer `slot` (od 1) i kurs z dziobem na środek jeziora.
function ArenaRules.spawnPoint(layout: any, slot: number): (Vector2, number)
	local step = SPAWN_ORDER[(slot - 1) % #SPAWN_ORDER + 1]
	local angle = math.pi / 2 + step * math.pi / 4
	local outward = Vector2.new(math.cos(angle), math.sin(angle))
	return layout.center + outward * layout.spawnRing, math.atan2(-outward.Y, -outward.X)
end

-- Promień strefy `elapsed` sekund po starcie walki: liniowo, a po ARENA_ZONE_TIME już stały.
function ArenaRules.zoneRadius(fullRadius: number, elapsed: number): number
	local progress = math.clamp(elapsed / Config.ARENA_ZONE_TIME, 0, 1)
	return fullRadius + (Config.ARENA_ZONE_END_RADIUS - fullRadius) * progress
end

-- NaN z zepsutej pozycji ma się liczyć jako „poza strefą”, a nie jako ochrona, stąd `not (<=)` zamiast `>`.
function ArenaRules.isOutside(position: Vector2, center: Vector2, radius: number): boolean
	return not ((position - center).Magnitude <= radius)
end

-- Obrażenia --------------------------------------------------------------------------------------------------------------------

function ArenaRules.damage(health: number, amount: number): number
	return math.max(health - amount, 0)
end

-- Id rosnąco: `pairs` nie ma stałej kolejności, a dwa odczyty tych samych danych mają dać ten sam wynik.
local function sortedIds(list: { [number]: any }): { number }
	local ids: { number } = {}
	for id in list do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Czy gracz jest w grze? Odpadnięty, widz i gracz spoza rundy nie strzelają i nie są celem.
local function livingOf(match: Match, id: number): Contender?
	local contender = match.contenders[id]
	if contender and contender.place == nil then
		return contender
	end
	return nil
end

-- Najbliższy żywy cel w stożku przed dziobem albo nil. Remis odległości rozstrzyga niższe id.
function ArenaRules.pickTarget(match: Match, shooterId: number, fighters: { [number]: Fighter }): number?
	local shooter = fighters[shooterId]
	if shooter == nil then
		return nil
	end
	local bestId: number? = nil
	local bestDistance = math.huge
	for _, id in sortedIds(fighters) do
		if id ~= shooterId and livingOf(match, id) then
			local offset = fighters[id].position - shooter.position
			local distance = offset.Magnitude
			-- Dwa kajaki w jednym punkcie: kierunek nieokreślony (Unit dałby NaN), więc cel uznajemy za trafiony.
			local facing = if distance > 0 then offset.Unit:Dot(shooter.forward) else 1
			if distance <= Config.ARENA_CANNON_RANGE and distance < bestDistance and facing >= Config.ARENA_CANNON_ARC_COS then
				bestId, bestDistance = id, distance
			end
		end
	end
	return bestId
end

-- Gracz odpada. Miejsce = ilu było żywych przed nim, więc kto odpadł wcześniej, ma gorsze miejsce.
local function eliminate(match: Match, contender: Contender): Out
	contender.health = 0
	contender.place = match.alive
	match.alive -= 1
	return { userId = contender.id, name = contender.name, place = contender.place :: number }
end

-- Strzał. Nil = odmowa: nie ta faza, gracz poza grą, brak kajaka albo trwa odnowienie.
-- Strzał bez celu też zużywa odnowienie: inaczej klient mógłby sprawdzać zasięg za darmo, 4 razy na sekundę.
function ArenaRules.fire(match: Match, id: number, fighters: { [number]: Fighter }, now: number): Shot?
	local contender = livingOf(match, id)
	if match.phase ~= "racing" or contender == nil or fighters[id] == nil or now < contender.readyAt then
		return nil
	end
	contender.readyAt = now + Config.ARENA_COOLDOWN
	local target = ArenaRules.pickTarget(match, id, fighters)
	if target == nil then
		return { target = nil, out = nil }
	end
	local victim = match.contenders[target]
	victim.health = ArenaRules.damage(victim.health, Config.ARENA_CANNON_DAMAGE)
	return { target = target, out = if victim.health <= 0 then eliminate(match, victim) else nil }
end

-- Strefa: obrażenia za czas od poprzedniego liczenia, tylko dla żywych z kajakiem. Przycięcie serwera nie zabija jednym obiegiem.
-- Odpadają najpierw ci z najgłębszym „minusem”, czyli kto miał mniej wytrzymałości, ten zajmuje gorsze miejsce.
function ArenaRules.burn(match: Match, layout: any, fighters: { [number]: Fighter }, now: number): { Out }
	local outs: { Out } = {}
	local startedAt = match.startedAt
	if match.phase ~= "racing" or startedAt == nil then
		return outs
	end
	local step = math.clamp(now - match.burnedAt, 0, Config.ARENA_BURN_MAX_STEP)
	match.burnedAt = now
	local radius = ArenaRules.zoneRadius(layout.radius, now - startedAt)
	local burned: { { contender: Contender, left: number } } = {}
	for _, id in sortedIds(fighters) do
		local contender = livingOf(match, id)
		if contender and ArenaRules.isOutside(fighters[id].position, layout.center, radius) then
			local left = contender.health - Config.ARENA_ZONE_DPS * step
			contender.health = math.max(left, 0)
			if left <= 0 then
				table.insert(burned, { contender = contender, left = left })
			end
		end
	end
	table.sort(burned, function(a, b)
		if a.left ~= b.left then
			return a.left < b.left
		end
		return a.contender.id < b.contender.id
	end)
	for _, entry in burned do
		table.insert(outs, eliminate(match, entry.contender))
	end
	return outs
end

-- Gracz wyszedł z serwera. W trakcie walki odpada od razu i zostaje w wynikach, a po walce liczy się tylko do głosów.
function ArenaRules.leave(match: Match, id: number): Out?
	match.againVotes[id] = nil
	match.leaving[id] = nil
	if match.phase == "results" or match.phase == "countdown" then
		match.leftCount += 1
	end
	local contender = livingOf(match, id)
	if match.phase ~= "racing" or contender == nil then
		return nil
	end
	return eliminate(match, contender)
end

-- Runda ------------------------------------------------------------------------------------------------------------------------

-- Czy walka się skończyła? Solo (tylko Studio) nie kończy się od razu: gra do czasu albo do spalenia w strefie.
function ArenaRules.isOver(match: Match, now: number): boolean
	local enough = if match.entrants <= 1 then 0 else 1
	return match.alive <= enough or now >= match.phaseEndsAt
end

local function startRound(match: Match, roster: { Entrant }, now: number)
	match.contenders = {}
	for _, entrant in roster do
		match.contenders[entrant.id] =
			{ id = entrant.id, name = entrant.name, health = Config.ARENA_HEALTH, readyAt = 0, place = nil }
	end
	match.entrants = #roster
	match.alive = #roster
	match.startedAt = now
	match.endedAt = nil
	match.burnedAt = now
	match.rows = {}
end

-- Koniec walki: żywi dostają najlepsze miejsca wg wytrzymałości, remis rozstrzyga niższe id. Wynik: wszyscy, od pierwszego miejsca.
local function finishRound(match: Match, now: number)
	match.endedAt = now
	local living: { Contender } = {}
	for _, id in sortedIds(match.contenders) do
		local contender = match.contenders[id]
		if contender.place == nil then
			table.insert(living, contender)
		end
	end
	table.sort(living, function(a, b)
		if a.health ~= b.health then
			return a.health > b.health
		end
		return a.id < b.id
	end)
	for place, contender in living do
		contender.place = place
	end

	local rows: { Row } = {}
	for _, contender in match.contenders do
		table.insert(rows, {
			userId = contender.id,
			name = contender.name,
			place = contender.place :: number,
			health = math.ceil(contender.health),
		})
	end
	table.sort(rows, function(a, b)
		return a.place < b.place
	end)
	match.rows = rows
end

function ArenaRules.newMatch(expected: number?, minPlayers: number): Match
	return {
		phase = "waiting",
		phaseEndsAt = 0,
		minPlayers = minPlayers,
		expected = expected,
		gatherEndsAt = nil,
		aloneUntil = nil,
		contenders = {},
		entrants = 0,
		alive = 0,
		startedAt = nil,
		endedAt = nil,
		burnedAt = 0,
		rows = {},
		againVotes = {},
		leaving = {},
		leftCount = 0,
	}
end

-- Zmiana fazy. Countdown i waiting czyszczą stan: to już nowa runda, a wyniki poprzedniej poszły do klientów.
-- Głosy przeżywają przejście results → countdown: część osób klika dopiero w odliczaniu (jak w RaceLogic).
local function enter(match: Match, phase: Phase, endsAt: number)
	match.phase = phase
	match.phaseEndsAt = endsAt
	if phase == "countdown" or phase == "waiting" then
		match.contenders, match.rows = {}, {}
		match.entrants, match.alive = 0, 0
		match.startedAt, match.endedAt = nil, nil
	end
	if phase == "racing" or phase == "waiting" then
		match.againVotes, match.leaving = {}, {}
		match.leftCount = 0
	end
end

-- Głosy z ekranu wyników: te same zasady co w RaceLogic, więc klient obsługuje oba tryby jednym kodem ------------------------------

local function countKeys(set: { [number]: boolean }): number
	local count = 0
	for _ in set do
		count += 1
	end
	return count
end

-- „Jeszcze raz”. Liczy się tylko po walce (results i odliczanie), reszta jest ignorowana.
function ArenaRules.voteAgain(match: Match, id: number)
	if match.phase == "results" or match.phase == "countdown" then
		match.againVotes[id] = true
		match.leaving[id] = nil
	end
end

-- „Do wioski”: każdy decyduje za siebie, głos tylko pokazuje innym, ile osób odpływa.
function ArenaRules.voteLeave(match: Match, id: number)
	if match.phase == "results" or match.phase == "countdown" then
		match.againVotes[id] = nil
		match.leaving[id] = true
	end
end

-- Teleport się nie udał: gracz zostaje i znów jest niezdecydowany.
function ArenaRules.cancelLeave(match: Match, id: number)
	match.leaving[id] = nil
end

-- Stan decyzji do RaceVotes: (płyną dalej, do wioski, niezdecydowani).
function ArenaRules.tally(match: Match, playerCount: number): (number, number, number)
	local again, leaving = countKeys(match.againVotes), countKeys(match.leaving)
	return again, leaving + match.leftCount, math.max(playerCount - again - leaving, 0)
end

local function everyoneAgain(match: Match, playerCount: number): boolean
	local votes = countKeys(match.againVotes)
	return votes > 0 and votes + countKeys(match.leaving) >= playerCount
end

-- Czy dalej czekamy na resztę grupy? Jak w RaceLogic: najwyżej RACE_GATHER_TIME od pierwszego gracza.
local function gathering(match: Match, now: number, count: number): boolean
	local expected = match.expected
	if expected == nil then
		return false
	end
	if match.gatherEndsAt == nil then
		match.gatherEndsAt = now + Config.RACE_GATHER_TIME
		match.phaseEndsAt = match.gatherEndsAt :: number
	end
	if count < expected and now < (match.gatherEndsAt :: number) then
		return true
	end
	match.expected = nil
	return false
end

-- Upływ czasu. Zwraca nową fazę, gdy się zmieniła, inaczej nil. `roster` to gracze obecni teraz na serwerze.
function ArenaRules.tick(match: Match, now: number, roster: { Entrant }): Phase?
	local phase = match.phase
	local count = #roster
	if count == 0 then
		match.aloneUntil = nil
		if phase == "waiting" then
			return nil
		end
		enter(match, "waiting", 0)
	elseif phase == "waiting" then
		if gathering(match, now, count) then
			return nil
		end
		if count < match.minPlayers then
			if match.aloneUntil == nil then
				match.aloneUntil = now + Config.ARENA_ALONE_TIME
				match.phaseEndsAt = match.aloneUntil :: number
			end
			return nil
		end
		match.aloneUntil = nil
		enter(match, "countdown", now + Config.COUNTDOWN_TIME)
	elseif phase == "countdown" then
		if count < match.minPlayers then
			enter(match, "waiting", 0)
		else
			if everyoneAgain(match, count) then
				match.phaseEndsAt = math.min(match.phaseEndsAt, now + Config.AGAIN_COUNTDOWN)
			end
			if now < match.phaseEndsAt then
				return nil
			end
			startRound(match, roster, now)
			enter(match, "racing", now + Config.ARENA_ROUND_TIME)
		end
	elseif phase == "racing" then
		if not ArenaRules.isOver(match, now) then
			return nil
		end
		finishRound(match, now)
		enter(match, "results", now + Config.RESULTS_TIME)
	else -- results
		local everyone = everyoneAgain(match, count)
		if now < match.phaseEndsAt and not everyone then
			return nil
		end
		if count >= match.minPlayers then
			enter(match, "countdown", now + (if everyone then Config.AGAIN_COUNTDOWN else Config.COUNTDOWN_TIME))
		else
			enter(match, "waiting", 0)
		end
	end
	return match.phase
end

-- Czy pora odesłać samotnego gracza do wioski? Prawda raz na ARENA_ALONE_TIME: gdy teleport się nie uda, spróbujemy znowu.
function ArenaRules.stranded(match: Match, now: number): boolean
	local aloneUntil = match.aloneUntil
	if aloneUntil == nil or now < aloneUntil then
		return false
	end
	match.aloneUntil = now + Config.ARENA_ALONE_TIME
	match.phaseEndsAt = match.aloneUntil :: number
	return true
end

-- Promień strefy do wysłania i narysowania. Przed walką pełne jezioro, a na ekranie wyników strefa stoi.
function ArenaRules.currentRadius(match: Match, fullRadius: number, now: number): number
	local startedAt = match.startedAt
	if startedAt == nil then
		return fullRadius
	end
	return ArenaRules.zoneRadius(fullRadius, (match.endedAt or now) - startedAt)
end

return ArenaRules
