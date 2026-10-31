-- Zasady Wodnej bitwy: czysta logika bez Instance, bez zegara i bez sieci (testy: logic/ArenaRules.spec, kontrakt: ARCHITECTURE.md).
-- Maszyna faz serwera, strumień (zbiornik, cel, osłony, obrażenia, odepchnięcie), zwężanie strefy, kolejność odpadania i wynik po czasie.
-- Czas `now` podaje wołający, a świat wchodzi jako migawka pozycji, którą Systems/ArenaService sam odczytał z Hull. Klient niczego tu nie dostarcza.
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
	place: number?, -- nil = wciąż na wodzie i w grze
	firing: boolean, -- czy strumień jest otwarty
	tank: number, -- zbiornik 0..1
	tankSent: number?, -- ostatnia wartość wysłana do gracza; nil = jeszcze nic
	tankSentAt: number,
	lastPosition: Vector2?, -- pozycja z poprzedniego obiegu, z niej liczymy prędkość
	hitShownAt: number, -- kiedy ten strzelec ostatnio pokazał trafienie innym
	push: Vector2, -- odepchnięcie zebrane, a jeszcze niewysłane
	pushSentAt: number,
}
export type Out = { userId: number, name: string, place: number }
export type Hit = { shooter: number, target: number }
export type Push = { id: number, push: Vector2 }
export type StreamResult = { hits: { Hit }, pushes: { Push }, outs: { Out } }
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
	streamedAt: number, -- ostatnie liczenie strumieni i zbiorników
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

-- Zbiornik ------------------------------------------------------------------------------------------------------------------

-- Opróżnianie przez `dt` sekund strumienia. Zwraca nowy stan i ile sekund strumienia naprawdę poszło:
-- końcówka zbiornika daje tylko tyle obrażeń, ile było w niej wody.
function ArenaRules.drain(tank: number, dt: number): (number, number)
	local available = tank * Config.ARENA_TANK_SECONDS
	if dt >= available then
		return 0, available
	end
	return tank - dt / Config.ARENA_TANK_SECONDS, dt
end

-- Ładowanie przez `dt` sekund: od wolnego w miejscu do pełnego od ARENA_TANK_FULL_SPEED.
-- Szybciej się nie da, więc podkręcony ruch kajaka daje najwyżej zwykłe pełne ładowanie. NaN liczymy jak postój.
function ArenaRules.refill(tank: number, speed: number, dt: number): number
	local share = if speed > 0 then math.min(speed / Config.ARENA_TANK_FULL_SPEED, 1) else 0
	local idleRate, fullRate = 1 / Config.ARENA_TANK_IDLE_TIME, 1 / Config.ARENA_TANK_FULL_TIME
	return math.min(tank + (idleRate + (fullRate - idleRate) * share) * dt, 1)
end

-- Wartość do wysłania albo nil: nowa, a od poprzedniej minęło ARENA_TANK_INTERVAL. (Dla TS: throttle, który zapamiętuje ostatni stan.)
function ArenaRules.tankToSend(contender: Contender, now: number): number?
	if contender.tank == contender.tankSent or now < contender.tankSentAt + Config.ARENA_TANK_INTERVAL then
		return nil
	end
	contender.tankSent, contender.tankSentAt = contender.tank, now
	return contender.tank
end

-- Strumień ------------------------------------------------------------------------------------------------------------------

-- Czy odcinek przecina koło? Szukamy punktu odcinka najbliższego środka koła: rzut na prostą przycięty do 0..1.
-- Brzeg koła też zasłania. Odcinek o zerowej długości to po prostu punkt `from`.
function ArenaRules.segmentHitsCircle(from: Vector2, to: Vector2, center: Vector2, radius: number): boolean
	local along = to - from
	local lengthSquared = along:Dot(along)
	local share = if lengthSquared > 0 then math.clamp((center - from):Dot(along) / lengthSquared, 0, 1) else 0
	return (from + along * share - center).Magnitude <= radius
end

local function shielded(from: Vector2, to: Vector2, obstacles: { any }): boolean
	for _, obstacle in obstacles do
		if ArenaRules.segmentHitsCircle(from, to, obstacle.position, obstacle.radius) then
			return true
		end
	end
	return false
end

-- Mnożnik z kursu celu: strzelec przed jego dziobem to 1, a bok i tył to ARENA_FLANK_MULTIPLIER.
-- Dwa kajaki w jednym punkcie: kierunek nieokreślony, liczymy jak z przodu.
function ArenaRules.flankMultiplier(shooter: Vector2, target: Fighter): number
	local offset = shooter - target.position
	if offset.Magnitude == 0 or offset.Unit:Dot(target.forward) >= Config.ARENA_FRONT_ARC_COS then
		return 1
	end
	return Config.ARENA_FLANK_MULTIPLIER
end

-- Odepchnięcie za `seconds` trafiania: wzdłuż strumienia, od strzelca. Kajaki w jednym punkcie: bez kierunku nie pchamy.
function ArenaRules.pushFor(shooter: Vector2, target: Vector2, seconds: number): Vector2
	local offset = target - shooter
	if offset.Magnitude == 0 then
		return Vector2.zero
	end
	return offset.Unit * (Config.ARENA_PUSH_PER_SECOND * seconds)
end

-- Najbliższy żywy cel w stożku przed dziobem albo nil. Remis odległości rozstrzyga niższe id.
-- Cel za przeszkodą nie istnieje dla strumienia, więc wygrywa dalszy, ale odsłonięty.
function ArenaRules.pickTarget(match: Match, shooterId: number, fighters: { [number]: Fighter }, obstacles: { any }?): number?
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
			if
				distance <= Config.ARENA_CANNON_RANGE
				and distance < bestDistance
				and facing >= Config.ARENA_CANNON_ARC_COS
				and not shielded(shooter.position, fighters[id].position, obstacles or {})
			then
				bestId, bestDistance = id, distance
			end
		end
	end
	return bestId
end

-- Gracz odpada. Miejsce = ilu było żywych przed nim, więc kto odpadł wcześniej, ma gorsze miejsce. Jego strumień gaśnie.
local function eliminate(match: Match, contender: Contender): Out
	contender.health = 0
	contender.firing = false
	contender.place = match.alive
	match.alive -= 1
	return { userId = contender.id, name = contender.name, place = contender.place :: number }
end

-- Prośba klienta o otwarcie lub zamknięcie strumienia. Odmowa jest cicha: walka trwa tylko w „racing”, a pusty zbiornik nie otwiera.
function ArenaRules.setFiring(match: Match, id: number, open: boolean)
	local contender = livingOf(match, id)
	if match.phase ~= "racing" or contender == nil or (open and contender.tank <= 0) then
		return
	end
	contender.firing = open
end

-- Jeden gracz w obiegu: zbiornik, a przy otwartym strumieniu także trafienie. Ofiara zbiera odepchnięcie, wysyłane potem razem.
local function streamOne(match: Match, contender: Contender, layout: any, fighters: { [number]: Fighter }, dt: number, now: number, result: StreamResult)
	local fighter = fighters[contender.id]
	if fighter == nil then
		contender.firing, contender.lastPosition = false, nil -- bez kajaka nie ma strumienia ani pomiaru prędkości
		return
	end
	local last = contender.lastPosition
	local speed = if last and dt > 0 then (fighter.position - last).Magnitude / dt else 0
	contender.lastPosition = fighter.position
	if not contender.firing then
		contender.tank = ArenaRules.refill(contender.tank, speed, dt)
		return
	end

	local left, seconds = ArenaRules.drain(contender.tank, dt)
	contender.tank = left
	contender.firing = left > 0
	local targetId = ArenaRules.pickTarget(match, contender.id, fighters, layout.obstacles)
	if targetId == nil or seconds <= 0 then
		return
	end
	local victim, target = match.contenders[targetId], fighters[targetId]
	local amount = Config.ARENA_STREAM_DPS * seconds * ArenaRules.flankMultiplier(fighter.position, target)
	victim.health = ArenaRules.damage(victim.health, amount)
	victim.push += ArenaRules.pushFor(fighter.position, target.position, seconds)
	if now >= contender.hitShownAt + Config.ARENA_HIT_INTERVAL then
		contender.hitShownAt = now
		table.insert(result.hits, { shooter = contender.id, target = targetId })
	end
	if victim.health <= 0 then
		table.insert(result.outs, eliminate(match, victim))
	end
end

-- Jeden obieg walki. Id rosnąco, więc wynik jest powtarzalny: gdy dwóch dobija się nawzajem w tym samym obiegu, żyje niższe id,
-- a runda nie kończy się bez zwycięzcy. Czas tnie ten sam limit co strefę: przycięcie serwera nie opróżnia zbiornika jednym obiegiem.
function ArenaRules.stream(match: Match, layout: any, fighters: { [number]: Fighter }, now: number): StreamResult
	local result: StreamResult = { hits = {}, pushes = {}, outs = {} }
	if match.phase ~= "racing" then
		return result
	end
	local dt = math.clamp(now - match.streamedAt, 0, Config.ARENA_BURN_MAX_STEP)
	match.streamedAt = now
	local ids = sortedIds(match.contenders)
	for _, id in ids do
		local contender = livingOf(match, id)
		if contender then
			streamOne(match, contender, layout, fighters, dt, now, result)
		end
	end
	-- Odepchnięcie zbiorcze: kilku strzelców i kilka obiegów to jedno zdarzenie do ofiary.
	for _, id in ids do
		local contender = livingOf(match, id)
		if contender and contender.push ~= Vector2.zero and now >= contender.pushSentAt + Config.ARENA_HIT_INTERVAL then
			table.insert(result.pushes, { id = id, push = contender.push })
			contender.push, contender.pushSentAt = Vector2.zero, now
		end
	end
	return result
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
		match.contenders[entrant.id] = {
			id = entrant.id,
			name = entrant.name,
			health = Config.ARENA_HEALTH,
			place = nil,
			firing = false,
			tank = 1,
			tankSent = nil,
			tankSentAt = -math.huge,
			lastPosition = nil,
			hitShownAt = -math.huge,
			push = Vector2.zero,
			pushSentAt = -math.huge,
		}
	end
	match.entrants = #roster
	match.alive = #roster
	match.startedAt = now
	match.endedAt = nil
	match.burnedAt = now
	match.streamedAt = now
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
		streamedAt = 0,
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
