-- Wpis wyścigu z MemoryStore: co wioska zamówiła dla tego serwera zarezerwowanego (ARCHITECTURE.md, „Przejście wioska → spływ”).
-- Rzeki nie bierzemy z danych teleportu, bo przechodzą przez klienta. Wpis pisze serwer wioski, więc oszust go nie podmieni.
-- Każda porażka kończy się tak samo: nil, a RiverBuilder bierze Config.ACTIVE_RIVER. Tak samo działa Play w Studio.
-- Tryb czytamy z tego samego wpisu, a jego brak znaczy zwykły wyścig (w Studio: Config.ACTIVE_MODE).
-- Tryb "arena" nie ma pliku w content/rivers, więc nazwa rzeki wychodzi tu jako nil: RiverBuilder patrzy wtedy tylko na tryb.
-- (Dla TS: `const ticket = await redis.get(serverId).catch(() => null)` plus walidacja kształtu danych.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MatchQueue = require(Shared:WaitForChild("MatchQueue"))

local RaceTicket = {}

-- Sprawdza wpis (czysta funkcja, testy: logic/RaceTicket.spec). Zwraca (nazwa rzeki lub nil, liczba graczy lub nil, tryb lub nil).
-- Stary wpis bez trybu i wpis ze złym trybem to "race". Nil oznacza brak wpisu.
function RaceTicket.parse(value: any, isKnownRiver: (string) -> boolean): (string?, number?, MatchQueue.Mode?)
	if type(value) ~= "table" then
		return nil, nil, nil
	end
	local river = if type(value.river) == "string" and isKnownRiver(value.river) then value.river else nil
	local expected = value.expected
	local validExpected = type(expected) == "number"
		and expected % 1 == 0
		and expected >= 1
		and expected <= Config.PIER_CAPACITY
	return river, if validExpected then expected else nil, MatchQueue.parseMode(value.mode) or "race"
end

-- Ostateczny tryb serwera. Brak wpisu poza Studio to "race", a w Studio decyduje Config.
function RaceTicket.resolveMode(mode: MatchQueue.Mode?, isStudio: boolean): MatchQueue.Mode
	if mode then
		return mode
	end
	return if isStudio then MatchQueue.parseMode(Config.ACTIVE_MODE) or "race" else "race"
end

-- Czyta wpis tego serwera. Serwer publiczny, prywatny VIP i Studio nie mają wpisu, więc od razu zwracają nil.
-- Serwer zarezerwowany rozpoznajemy po PrivateServerOwnerId == 0. (Yielduje: najwyżej kilka sekund przy awarii.)
function RaceTicket.read(): any
	local serverId = game.PrivateServerId
	if serverId == "" or game.PrivateServerOwnerId ~= 0 then
		return nil
	end
	for attempt = 1, Config.RACE_TICKET_TRIES do
		local ok, value = pcall(function()
			return game:GetService("MemoryStoreService"):GetSortedMap(Config.RACE_TICKET_MAP):GetAsync(serverId)
		end)
		if ok and value ~= nil then
			return value
		end
		warn(`[RaceTicket] próba {attempt}: {if ok then "brak wpisu" else value}`)
		if attempt < Config.RACE_TICKET_TRIES then
			task.wait(Config.RACE_TICKET_WAIT)
		end
	end
	return nil
end

return RaceTicket
