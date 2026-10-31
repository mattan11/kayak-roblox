-- Kolejka między serwerami: czysta logika bez Instance, bez zegara i bez sieci (testy: logic/MatchQueue.spec).
-- Wejście to bilety (ARCHITECTURE.md, „Kolejka między serwerami”), wyjście to decyzja. Czas `now` podaje wołający, a MemoryStore,
-- MessagingService i teleport obsługuje Systems/MatchService. Tutaj trafia też walidacja wszystkiego, co przychodzi z sieci.
-- (Dla TS: jak reducer plus zody do parsowania: dane wchodzą, decyzja wychodzi, efekty uboczne robi ktoś inny.)
--
-- Start rzeki: komplet biletów, albo najstarszy czeka PIER_COUNTDOWN, albo wszyscy `ready`.

local Config = require(script.Parent.Config)

local MatchQueue = {}

export type Ticket = { userId: number, serverId: string, joinedAt: number, ready: boolean }
export type State = { count: number, endsAt: number?, ready: number }
export type Decision = { group: { Ticket }?, rest: { Ticket }, state: State }
export type Match = { river: string, userIds: { number }, code: string?, at: number }
export type Health = { failures: number, down: boolean }

function MatchQueue.ticket(userId: number, serverId: string, now: number): Ticket
	return { userId = userId, serverId = serverId, joinedAt = now, ready = false }
end

-- Bilet z MemoryStore. Zły kształt = nil, jak `schema.safeParse`.
function MatchQueue.parseTicket(value: any): Ticket?
	if type(value) ~= "table" or type(value.userId) ~= "number" or type(value.joinedAt) ~= "number" then
		return nil
	end
	if type(value.serverId) ~= "string" then
		return nil
	end
	return { userId = value.userId, serverId = value.serverId, joinedAt = value.joinedAt, ready = value.ready == true }
end

-- Kolejność kolejki. Remis rozstrzyga userId, żeby każdy serwer wyliczył to samo.
local function older(a: Ticket, b: Ticket): boolean
	if a.joinedAt ~= b.joinedAt then
		return a.joinedAt < b.joinedAt
	end
	return a.userId < b.userId
end

-- Stan do pokazania graczom. Kolejka ponad komplet też się liczy: nadmiarowi wypłyną następną grupą.
function MatchQueue.state(tickets: { Ticket }): State
	local oldest: number? = nil
	local ready = 0
	for _, ticket in tickets do
		oldest = if oldest == nil then ticket.joinedAt else math.min(oldest, ticket.joinedAt)
		if ticket.ready then
			ready += 1
		end
	end
	return { count = #tickets, endsAt = if oldest then oldest + Config.PIER_COUNTDOWN else nil, ready = ready }
end

-- Które bilety startują. Grupa to najstarsze bilety, najwyżej komplet; reszta czeka i dostaje swój stan.
function MatchQueue.decide(tickets: { Ticket }, now: number): Decision
	local sorted = table.clone(tickets)
	table.sort(sorted, older)
	local state = MatchQueue.state(sorted)
	local count = #sorted
	local capacity = Config.PIER_CAPACITY
	local go = count >= capacity
		or (count > 0 and (now >= (state.endsAt :: number) or state.ready == count))
	if not go then
		return { group = nil, rest = sorted, state = state }
	end
	local group = table.move(sorted, 1, math.min(count, capacity), 1, {})
	local rest = table.move(sorted, #group + 1, count, 1, {})
	return { group = group, rest = rest, state = MatchQueue.state(rest) }
end

-- Gracz może stać w jednej kolejce. Gdy zmienił rzekę, a usunięcie starego biletu nie doszło do skutku, liczy się nowszy bilet.
function MatchQueue.dedupe(byRiver: { [string]: { Ticket } }): { [string]: { Ticket } }
	local newest: { [number]: Ticket } = {}
	for _, tickets in byRiver do
		for _, ticket in tickets do
			local seen = newest[ticket.userId]
			if seen == nil or ticket.joinedAt > seen.joinedAt then
				newest[ticket.userId] = ticket
			end
		end
	end
	local result: { [string]: { Ticket } } = {}
	for river, tickets in byRiver do
		local kept: { Ticket } = {}
		for _, ticket in tickets do
			if newest[ticket.userId] == ticket then
				table.insert(kept, ticket)
			end
		end
		result[river] = kept
	end
	return result
end

-- Funkcja dla UpdateAsync na kluczu Leader. Nil anuluje zapis (dokumentacja MemoryStoreSortedMap), czyli blokadę ma ktoś inny.
-- Blokada kończy się sama przez wygaśnięcie klucza: nie porównujemy zegarów różnych serwerów. (Dla TS: `SET key me NX PX` w Redisie.)
function MatchQueue.claimLeader(current: any, serverId: string): { serverId: string }?
	if type(current) == "table" and current.serverId ~= serverId then
		return nil
	end
	return { serverId = serverId }
end

-- Wiadomość tematu Match. Brak `code` = rezerwacja się nie udała. `at` pozwala odrzucić powtórkę dla gracza, który stanął
-- w kolejce po tej decyzji (MessagingService może dostarczyć wiadomość dwa razy, bo publikujemy ją z zapasem).
function MatchQueue.parseMatch(data: any): Match?
	if type(data) ~= "table" or type(data.river) ~= "string" or type(data.userIds) ~= "table" then
		return nil
	end
	if type(data.at) ~= "number" or (data.code ~= nil and type(data.code) ~= "string") then
		return nil
	end
	if #data.userIds == 0 or #data.userIds > Config.PIER_CAPACITY then
		return nil
	end
	for _, id in data.userIds do
		if type(id) ~= "number" then
			return nil
		end
	end
	return { river = data.river, userIds = data.userIds, code = data.code, at = data.at }
end

-- Stan z tematu QueueState: wysyłamy tylko niepuste rzeki, bo limit wiadomości to 1 kB. Brak rzeki = pusta kolejka.
function MatchQueue.encodeState(states: { [string]: State }): { [string]: State }
	local result: { [string]: State } = {}
	for river, state in states do
		if state.count > 0 then
			result[river] = state
		end
	end
	return result
end

function MatchQueue.parseState(data: any): { [string]: State }?
	if type(data) ~= "table" then
		return nil
	end
	local result: { [string]: State } = {}
	for river, state in data do
		if type(river) == "string" and type(state) == "table" and type(state.count) == "number" then
			local ends = if type(state.endsAt) == "number" then state.endsAt else nil
			local ready = if type(state.ready) == "number" then state.ready else 0
			result[river] = { count = state.count, endsAt = ends, ready = ready }
		end
	end
	return result
end

-- Po ilu sekundach ponowić teleport jednego gracza. Nil = koniec prób. `reason` to nazwa z Enum.TeleportResult.
-- Unauthorized się nie naprawi, Flooded potrzebuje dłuższej przerwy (wzór SafeTeleport z dokumentacji Roblox).
function MatchQueue.retryDelay(attempts: number, reason: string): number?
	if attempts >= Config.TRAVEL_TRIES or reason == "Unauthorized" then
		return nil
	end
	return if reason == "Flooded" then Config.TRAVEL_FLOOD_WAIT else Config.TRAVEL_RETRY_WAIT
end

-- Stan łącza z MemoryStore. Startujemy jako `down`: dopiero pierwsze udane wywołanie włącza kolejkę między serwerami.
-- (Dla TS: bezpiecznik, circuit breaker: po serii błędów przestajemy pytać i próbujemy tylko od czasu do czasu.)
function MatchQueue.newHealth(): Health
	return { failures = 0, down = true }
end

-- Wynik jednego wywołania. Zwraca true, gdy zmienił się tryb.
function MatchQueue.report(health: Health, ok: boolean): boolean
	if ok then
		local changed = health.down
		health.failures, health.down = 0, false
		return changed
	end
	health.failures += 1
	if not health.down and health.failures >= Config.MATCH_FAIL_LIMIT then
		health.down = true
		return true
	end
	return false
end

return MatchQueue
