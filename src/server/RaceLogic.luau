-- Logika wyścigu — czysta, bez Instance i bez zegara (testy: logic/RaceLogic.spec). Czas `now` podaje wołający.
-- Maszyna stanów faz + tabela zawodników: linia startu, meta, wyniki, wykrywanie oszustw.
-- Systems/RaceService tylko karmi ją pozycjami i wysyła zdarzenia.
-- (Dla TS: jak reducer — dane wchodzą, stan się zmienia, efekty uboczne robi ktoś inny.)

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local RaceLogic = {}
RaceLogic.__index = RaceLogic

export type Phase = "waiting" | "countdown" | "racing" | "results"

export type Racer = {
	id: number,
	name: string,
	late: boolean, -- wszedł w trakcie wyścigu: płynie sam dla siebie, nie ma go w RaceResults
	startedAt: number?, -- kiedy ruszył zegar
	time: number?, -- czas przejazdu (po mecie)
	invalid: boolean, -- wynik odrzucony (oszustwo)
	lastS: number,
	lastPosition: Vector2,
	lastAt: number,
	allowance: number, -- ile studs wolno się jeszcze przesunąć (wiadro jak w RateLimit)
}

export type Result = { userId: number, name: string, time: number }

function RaceLogic.new(startLine: number, finishLine: number)
	return setmetatable({
		phase = "waiting" :: Phase,
		phaseEndsAt = 0,
		startLine = startLine,
		finishLine = finishLine,
		racers = {} :: { [number]: Racer },
		nextSlot = 0,
		expected = nil :: number?, -- ilu graczy wysłała wioska; nil = na nikogo nie czekamy
		gatherEndsAt = nil :: number?, -- do kiedy czekamy na resztę grupy (liczone od pierwszego gracza)
		againVotes = {} :: { [number]: boolean }, -- kto kliknął „Jeszcze raz”
	}, RaceLogic)
end

-- Wioska wysłała `count` graczy: przed pierwszym odliczaniem czekamy na nich najwyżej RACE_GATHER_TIME.
function RaceLogic:expectPlayers(count: number)
	self.expected = count
end

-- Zmiana fazy. Wejście w countdown czyści listę: to nowy wyścig.
function RaceLogic:_enter(phase: Phase, endsAt: number)
	self.phase = phase
	self.phaseEndsAt = endsAt
	if phase == "countdown" or phase == "waiting" then
		self.racers = {}
		self.nextSlot = 0
	end
	-- Głosy przeżywają przejście results → countdown: część osób klika dopiero w odliczaniu.
	if phase == "racing" or phase == "waiting" then
		self.againVotes = {}
	end
end

-- Czy dalej czekamy na resztę grupy? phaseEndsAt w waiting = koniec czekania.
function RaceLogic:_gathering(now: number, playerCount: number): boolean
	local expected = self.expected
	if expected == nil then
		return false
	end
	if self.gatherEndsAt == nil then
		self.gatherEndsAt = now + Config.RACE_GATHER_TIME
		self.phaseEndsAt = self.gatherEndsAt
	end
	if playerCount < expected and now < self.gatherEndsAt then
		return true
	end
	self.expected = nil
	return false
end

-- „Jeszcze raz”. Głos liczy się tylko po wyścigu (results i odliczanie), reszta jest ignorowana.
function RaceLogic:voteAgain(id: number): boolean
	if self.phase ~= "results" and self.phase ~= "countdown" then
		return false
	end
	self.againVotes[id] = true
	return true
end

-- Czy wszyscy na serwerze kliknęli? Liczy tick, więc wyjście ostatniego niezdecydowanego też domyka głosowanie.
function RaceLogic:_everyoneAgain(playerCount: number): boolean
	local votes = 0
	for _ in self.againVotes do
		votes += 1
	end
	return votes >= playerCount
end

function RaceLogic:_allDone(): boolean
	for _, racer in self.racers do
		if not racer.late and not racer.time and not racer.invalid then
			return false
		end
	end
	return true
end

-- Upływ czasu. Zwraca nową fazę, gdy się zmieniła, inaczej nil. Solo też działa: wystarczy jeden gracz.
function RaceLogic:tick(now: number, playerCount: number): Phase?
	local phase = self.phase
	if playerCount == 0 then
		if phase == "waiting" then
			return nil
		end
		self:_enter("waiting", 0)
	elseif phase == "waiting" then
		if self:_gathering(now, playerCount) then
			return nil
		end
		self:_enter("countdown", now + Config.COUNTDOWN_TIME)
	elseif phase == "countdown" then
		if self:_everyoneAgain(playerCount) then
			self.phaseEndsAt = math.min(self.phaseEndsAt, now + Config.AGAIN_COUNTDOWN)
		end
		if now < self.phaseEndsAt then
			return nil
		end
		self:_enter("racing", now + Config.RACE_TIME_LIMIT)
	elseif phase == "racing" then
		if now < self.phaseEndsAt and not self:_allDone() then
			return nil
		end
		self:_enter("results", now + (if playerCount == 1 then Config.SOLO_RESULTS_TIME else Config.RESULTS_TIME))
	else -- results
		local everyone = self:_everyoneAgain(playerCount)
		if now < self.phaseEndsAt and not everyone then
			return nil
		end
		local time = if playerCount == 1 then Config.SOLO_COUNTDOWN_TIME else Config.COUNTDOWN_TIME
		self:_enter("countdown", now + (if everyone then Config.AGAIN_COUNTDOWN else time))
	end
	return self.phase
end

-- Czy gracz może teraz dostać kajak? W waiting zaraz ruszy countdown, a w results czeka na następny wyścig.
function RaceLogic:canEnroll(): boolean
	return self.phase == "countdown" or self.phase == "racing"
end

-- Zapis na wyścig (zajmuje miejsce startowe nextSlot). W fazie racing to spóźnialski: zegar rusza od razu.
function RaceLogic:enroll(id: number, name: string, position: Vector2, s: number, now: number)
	local late = self.phase == "racing"
	self.racers[id] = {
		id = id,
		name = name,
		late = late,
		startedAt = if late then now else nil,
		time = nil,
		invalid = false,
		lastS = s,
		lastPosition = position,
		lastAt = now,
		allowance = Config.JUMP_ALLOWANCE,
	}
	self.nextSlot += 1
end

-- Gracz wyszedł. Kto już dopłynął, zostaje w wynikach.
function RaceLogic:remove(id: number)
	self.againVotes[id] = nil
	local racer = self.racers[id]
	if racer and not racer.time then
		self.racers[id] = nil
	end
end

-- Moment przecięcia linii między dwoma odczytami (interpolacja: odczyty są co 0,1 s, a czas chcemy dokładniej).
local function crossingTime(fromS: number, toS: number, line: number, fromT: number, toT: number): number
	return fromT + (toT - fromT) * math.clamp((line - fromS) / (toS - fromS), 0, 1)
end

-- Kolejny odczyt pozycji Hull: `s` z River:query, `outside` = o ile dalej od środka niż halfWidth (<=0 w korycie).
-- Zwraca "finished", gdy ten odczyt zakończył przejazd, "invalid", gdy właśnie odrzuciliśmy wynik, inaczej nil.
function RaceLogic:sample(id: number, position: Vector2, s: number, outside: number, now: number): ("finished" | "invalid")?
	local racer = self.racers[id]
	if not racer or racer.time or racer.invalid then
		return nil
	end

	-- Wiadro żetonów na dystans: lag zbiera zapas, więc szarpnięcie po przycięciu sieci nie jest oszustwem,
	-- a średnia prędkość i tak nie przekroczy limitu.
	local dt = now - racer.lastAt
	local moved = (position - racer.lastPosition).Magnitude
	racer.allowance = math.min(Config.JUMP_ALLOWANCE, racer.allowance + Config.MAX_KAYAK_SPEED * dt) - moved
	if racer.allowance < 0 or outside > Config.OFF_RIVER_TOLERANCE then
		racer.invalid = true
		return "invalid"
	end

	local fromS, fromT = racer.lastS, racer.lastAt
	racer.lastS, racer.lastPosition, racer.lastAt = s, position, now

	if not racer.startedAt and fromS < self.startLine and s >= self.startLine then
		racer.startedAt = crossingTime(fromS, s, self.startLine, fromT, now)
	end
	if racer.startedAt and s >= self.finishLine then
		local finishedAt = crossingTime(fromS, s, self.finishLine, fromT, now)
		racer.time = math.round(math.max(finishedAt - racer.startedAt, 0) * 1000) / 1000
		-- Pierwszy na mecie skraca wyścig reszcie; spóźnialski płynie sam i niczego nie skraca.
		if not racer.late then
			self.phaseEndsAt = math.min(self.phaseEndsAt, now + Config.FINISH_GRACE)
		end
		return "finished"
	end
	return nil
end

-- Wyniki od najszybszego. Bez spóźnialskich, odrzuconych i tych, którzy nie dopłynęli.
function RaceLogic:results(): { Result }
	local rows: { Result } = {}
	for _, racer in self.racers do
		if racer.time and not racer.late then
			table.insert(rows, { userId = racer.id, name = racer.name, time = racer.time })
		end
	end
	table.sort(rows, function(a, b)
		return a.time < b.time
	end)
	return rows
end

-- Miejsce startowe: środek, potem na zmianę prawo/lewo co SLOT_SPACING; gdy brak szerokości, kolejny rząd wyżej.
-- Zwraca (s, lateral).
function RaceLogic.slot(index: number, halfWidth: number): (number, number)
	local reach = math.floor((halfWidth - Config.KAYAK_RADIUS) / Config.SLOT_SPACING) -- ile miejsc na stronę
	local perRow = reach * 2 + 1
	local row = index // perRow
	local column = index % perRow
	local side = if column % 2 == 1 then 1 else -1
	return math.max(Config.START_DISTANCE - row * Config.SLOT_ROW_SPACING, Config.KAYAK_RADIUS),
		side * ((column + 1) // 2) * Config.SLOT_SPACING
end

-- Wynik w OrderedDataStore: tylko liczby całkowite, więc milisekundy.
function RaceLogic.timeToScore(time: number): number
	return math.round(time * 1000)
end

function RaceLogic.scoreToTime(score: number): number
	return score / 1000
end

-- Czy nowy czas jest rekordem wobec dotychczasowego (nil = pierwszy przejazd)?
function RaceLogic.isRecord(best: number?, time: number): boolean
	return best == nil or time < best
end

return RaceLogic
