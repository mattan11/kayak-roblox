-- Wpis wyścigu z MemoryStore: co wioska zamówiła dla tego serwera zarezerwowanego (ARCHITECTURE.md, „Przejście wioska → spływ”).
-- Rzeki nie bierzemy z danych teleportu, bo przechodzą przez klienta. Wpis pisze serwer wioski, więc oszust go nie podmieni.
-- Każda porażka kończy się tak samo: nil, a RiverBuilder bierze Config.ACTIVE_RIVER. Tak samo działa Play w Studio.
-- (Dla TS: `const ticket = await redis.get(serverId).catch(() => null)` plus walidacja kształtu danych.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local RaceTicket = {}

-- Sprawdza wpis (czysta funkcja, testy: logic/RaceTicket.spec). Zwraca (nazwa rzeki lub nil, liczba graczy lub nil).
function RaceTicket.parse(value: any, isKnownRiver: (string) -> boolean): (string?, number?)
	if type(value) ~= "table" then
		return nil, nil
	end
	local river = if type(value.river) == "string" and isKnownRiver(value.river) then value.river else nil
	local expected = value.expected
	local validExpected = type(expected) == "number"
		and expected % 1 == 0
		and expected >= 1
		and expected <= Config.PIER_CAPACITY
	return river, if validExpected then expected else nil
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
