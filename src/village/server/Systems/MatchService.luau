-- Kolejka między serwerami i wyjazd na spływ (ARCHITECTURE.md, „Kolejka między serwerami”). Zasady startu: shared/MatchQueue.
-- Gracz klika „join”, serwer pisze bilet do MemoryStore i odnawia go. Lider (jeden serwer z blokadą) czyta bilety wszystkich rzek,
-- rezerwuje serwer i ogłasza grupę. Każdy serwer teleportuje SWOICH graczy, każdego osobno.
-- (Dla TS: bilety to kolejka w Redisie, lider to worker z lockiem, MessagingService to pub/sub.)
--
-- Budżet MemoryStore: limit gry to 1000 + 120 × gracze jednostek na minutę. Na serwer idzie ok. 40 na blokadę, lider dokłada
-- 30 na rzekę plus 30 na bilet, a każdy bilet 12 na odnawianie. Limit odczytu GetRangeAsync to 200 pozycji, czyli z zapasem.
--
-- Pewne rzeczy są tu celowe:
--  - MessagingService jest „best effort”, więc Match wysyłamy dwa razy (powtórkę odsiewa pole `at`), a gdy obie wiadomości
--    zginą, serwer gracza widzi zabrany bilet i po MATCH_TAKEN_TIMEOUT mówi „travel.failed”. Gracz nie utknie.
--  - Bilety pisze jedna pętla (syncLoop), kolejno. Inaczej „usuń” mogłoby wyprzedzić „utwórz” i zostawić bilet-ducha.
--  - Teleport to zawsze jeden gracz na wywołanie: gracze i tak bywają na różnych serwerach, a błąd jednego (np. GameNotFound
--    na telefonie) nie może zabrać reszcie ponowień. Kod dostępu kieruje wszystkich na ten sam serwer.
--  - Serwer spływu nie czeka na spóźnialskich dłużej niż RACE_GATHER_TIME: wpis `expected` to tylko podpowiedź.
--
-- Klient widzi swój stan przez atrybuty gracza (replikują się same): QueueRiver, QueueReady, QueueTraveling.

local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MatchQueue = require(Shared:WaitForChild("MatchQueue"))
local Places = require(Shared:WaitForChild("Places"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MatchService = {}

type Entry = {
	ticket: MatchQueue.Ticket,
	river: string,
	written: boolean, -- bilet jest (albo właśnie trafia) w MemoryStore
	dirty: boolean, -- zmiana czeka na zapis
	renewAt: number,
	takenAt: number?, -- od kiedy wiemy, że lider zabrał bilet, a Match jeszcze nie doszedł
}
type Trip = { attempts: number, deadline: number, options: TeleportOptions, retrying: boolean }
type Removal = { river: string, userId: number }

local STUDIO = RunService:IsStudio()
local LEADER_KEY = "Leader"
local EMPTY: MatchQueue.State = { count = 0, endsAt = nil, ready = 0 }

local rivers: { string } = {} -- dostępne rzeki, z RiverCatalog
local entries: { [number]: Entry } = {} -- bilety graczy z tego serwera; to one decydują, kogo teleportujemy
local trips: { [number]: Trip } = {} -- userId → podróż w toku
local removals: { Removal } = {} -- bilety do usunięcia z MemoryStore
local joinedAt: { [number]: number } = {} -- ostatnie „join”, limit przełączania rzek
local sent: { [string]: MatchQueue.State } = {} -- ostatni wysłany QueueState
local ticketMaps: { [string]: MemoryStoreSortedMap } = {}
local warnedAt: { [string]: number } = {}

local health = MatchQueue.newHealth()
local subscribed = false
local leaderSince: number? = nil -- os.clock() ostatniego udanego odnowienia blokady

local queueState: RemoteEvent
local travelNotice: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Awaria usług potrafi dawać błąd w każdym obiegu, więc ten sam temat ostrzega raz na MATCH_WARN_INTERVAL.
-- Błędy teleportu i rezerwacji idą zwykłym warn: każdy się liczy.
local function quietWarn(topic: string, message: any)
	local clock = os.clock()
	if clock - (warnedAt[topic] or -math.huge) >= Config.MATCH_WARN_INTERVAL then
		warnedAt[topic] = clock
		warn(`[Match] {topic}: {message}`)
	end
end

local function ticketMap(river: string): MemoryStoreSortedMap
	local map = ticketMaps[river]
	if map == nil then
		map = MemoryStoreService:GetSortedMap(Config.MATCH_TICKET_PREFIX .. river)
		ticketMaps[river] = map
	end
	return map
end

-- Atrybuty dla klienta: jedyna droga, którą dowie się, czy serwer przyjął jego „join”.
local function mark(id: number)
	local player = Players:GetPlayerByUserId(id)
	if player then
		local entry = entries[id]
		player:SetAttribute("QueueRiver", if entry then entry.river else nil)
		player:SetAttribute("QueueReady", if entry and entry.ticket.ready then true else nil)
		player:SetAttribute("QueueTraveling", if trips[id] then true else nil)
	end
end

-- Gracz przestaje stać w kolejce. `alreadyGone` = bilet zabrał lider albo nigdy nie dotarł, nie ma czego usuwać.
local function forget(id: number, alreadyGone: boolean?)
	local entry = entries[id]
	if entry == nil then
		return
	end
	entries[id] = nil
	if entry.written and not alreadyGone and not health.down then
		table.insert(removals, { river = entry.river, userId = id })
	end
	mark(id)
end

local function notice(id: number, textKey: string)
	local player = Players:GetPlayerByUserId(id)
	if player then
		travelNotice:FireClient(player, textKey)
	end
end

local function sendState(river: string, state: MatchQueue.State)
	local last = sent[river]
	if last.count ~= state.count or last.endsAt ~= state.endsAt or last.ready ~= state.ready then
		sent[river] = state
		queueState:FireAllClients(river, state.count, state.endsAt, state.ready)
	end
end

-- Teleport -----------------------------------------------------------------------------------------------------------

local onFailed: (Player, string) -> ()

local function send(player: Player, trip: Trip)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Places.placeId("race"), { player }, trip.options)
	end)
	if not ok then
		warn(`[Match] {player.Name}: teleport, próba {trip.attempts}: {err}`)
		onFailed(player, "Failure")
	end
end

-- Nieudana próba (błąd pcall, TeleportInitFailed albo brak wieści): ponowienie tego gracza na ten sam serwer albo koniec.
-- `retrying` chroni przed podwójnym liczeniem, gdy jeden teleport zgłosi błąd oboma drogami.
function onFailed(player: Player, reason: string)
	local id = player.UserId
	local trip = trips[id]
	if trip == nil or trip.retrying or player.Parent ~= Players then
		return
	end
	local delay = MatchQueue.retryDelay(trip.attempts, reason)
	if delay == nil then
		warn(`[Match] {player.Name}: teleport poddany po {trip.attempts} próbach ({reason})`)
		trips[id] = nil
		mark(id)
		travelNotice:FireClient(player, "travel.failed")
		return
	end
	trip.retrying = true
	task.delay(delay, function()
		if trips[id] == trip and player.Parent == Players then
			trip.retrying = false
			trip.attempts += 1
			trip.deadline = now() + Config.TRAVEL_TIMEOUT
			send(player, trip)
		end
	end)
end

local function beginTrip(player: Player, code: string)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	local trip = { attempts = 1, deadline = now() + Config.TRAVEL_TIMEOUT, options = options, retrying = false }
	trips[player.UserId] = trip
	mark(player.UserId)
	task.spawn(send, player, trip)
end

-- Wiadomość Match: decyzja lidera. Sięga tylko po własnych graczy, którzy wciąż stoją w tej kolejce. Działa też dla powtórki.
local function onMatch(data: any)
	local match = MatchQueue.parseMatch(data)
	if match == nil then
		return
	end
	for _, id in match.userIds do
		local entry = entries[id]
		if entry and entry.river == match.river and entry.ticket.joinedAt <= match.at then
			forget(id, true)
			local player = Players:GetPlayerByUserId(id)
			if player and match.code then
				beginTrip(player, match.code)
			else
				notice(id, "travel.failed")
			end
		end
	end
end

-- Lider -----------------------------------------------------------------------------------------------------------------

-- Serwer zarezerwowany + wpis w MemoryStore. Wpis musi powstać PRZED teleportem, bo spływ czyta go zaraz po starcie.
-- ReserveServerAsync i ReservedServerAccessCode dokumentacja oznacza jako przestarzałe, ale tylko ta para ma potwierdzony
-- związek z game.PrivateServerId, na którym opiera się odczyt wpisu. Migracja na ReservedServerId dotyczy tylko tej funkcji.
local function reserve(river: string, expected: number): string?
	for attempt = 1, Config.TRAVEL_TRIES do
		local ok, result = pcall(function()
			local code, privateServerId = TeleportService:ReserveServerAsync(Places.placeId("race"))
			local map = MemoryStoreService:GetSortedMap(Config.RACE_TICKET_MAP)
			map:SetAsync(privateServerId, { river = river, expected = expected }, Config.RACE_TICKET_TTL)
			return code
		end)
		if ok then
			return result
		end
		warn(`[Match] rezerwacja {river}, próba {attempt}: {result}`)
		if attempt < Config.TRAVEL_TRIES then
			task.wait(Config.TRAVEL_RETRY_WAIT)
		end
	end
	return nil
end

local function publishMatch(data: any)
	for attempt = 1, Config.MATCH_PUBLISH_TIMES do
		local ok, err = pcall(function()
			MessagingService:PublishAsync(Config.MATCH_TOPIC, data)
		end)
		if not ok then
			warn(`[Match] publikacja grupy, próba {attempt}: {err}`)
		end
		if attempt < Config.MATCH_PUBLISH_TIMES then
			task.wait(Config.MATCH_PUBLISH_GAP)
		end
	end
end

-- Bilety usuwamy od razu, w pętli lidera (następny obieg ich już nie zobaczy), a rezerwacja idzie obok, żeby nie wstrzymywać reszty rzek.
local function startGroup(river: string, group: { MatchQueue.Ticket })
	local map = ticketMap(river)
	local userIds: { number } = {}
	for _, ticket in group do
		table.insert(userIds, ticket.userId)
		local ok, err = pcall(function()
			map:RemoveAsync(tostring(ticket.userId))
		end)
		if not ok then
			quietWarn("usuwanie biletu", err)
		end
	end
	task.spawn(function()
		local code = reserve(river, #userIds)
		local data = { river = river, userIds = userIds, code = code, at = now() }
		onMatch(data) -- swoich graczy obsługujemy od razu, reszta dowie się z wiadomości
		publishMatch(data)
	end)
end

local function isLeader(): boolean
	-- Zapas względem wygaśnięcia blokady: zawieszony lider przestaje rozdzielać, zanim następca zacznie.
	return leaderSince ~= nil and os.clock() - leaderSince < Config.MATCH_LEADER_TTL - Config.MATCH_LEADER_RENEW
end

local function leaderTick()
	local byRiver: { [string]: { MatchQueue.Ticket } } = {}
	for _, river in rivers do
		local ok, items = pcall(function()
			return ticketMap(river):GetRangeAsync(Enum.SortDirection.Ascending, Config.MATCH_RANGE)
		end)
		if MatchQueue.report(health, ok) then
			MatchService._modeChanged()
		end
		if not ok then
			quietWarn("odczyt biletów", items)
			return
		end
		local tickets: { MatchQueue.Ticket } = {}
		for _, item in items do
			local ticket = MatchQueue.parseTicket(item.value)
			if ticket then
				table.insert(tickets, ticket)
			end
		end
		byRiver[river] = tickets
	end

	local time = now()
	local states: { [string]: MatchQueue.State } = {}
	for river, tickets in MatchQueue.dedupe(byRiver) do
		local decision = MatchQueue.decide(tickets, time)
		states[river] = decision.state
		if decision.group then
			startGroup(river, decision.group)
		end
		sendState(river, decision.state)
	end

	local ok, err = pcall(function()
		MessagingService:PublishAsync(Config.QUEUE_STATE_TOPIC, MatchQueue.encodeState(states))
	end)
	if not ok then
		quietWarn("publikacja stanu", err)
	end
end

-- Tryb lokalny: ten serwer jest liderem w pamięci, bez teleportu.
local function localTick()
	local byRiver: { [string]: { MatchQueue.Ticket } } = {}
	for _, river in rivers do
		byRiver[river] = {}
	end
	for _, entry in entries do
		table.insert(byRiver[entry.river], entry.ticket)
	end
	local time = now()
	for river, tickets in byRiver do
		local decision = MatchQueue.decide(tickets, time)
		for _, ticket in decision.group or {} do
			forget(ticket.userId, true)
			notice(ticket.userId, if RunService:IsStudio() then "travel.studio" else "travel.unavailable")
		end
		sendState(river, decision.state)
	end
end

local function onState(data: any)
	local states = MatchQueue.parseState(data)
	if states == nil or health.down then
		return
	end
	for _, river in rivers do
		sendState(river, states[river] or EMPTY)
	end
end

-- Bilety ------------------------------------------------------------------------------------------------------------------

-- `written` ustawiamy przed wywołaniem, które yielduje: wyjście gracza w trakcie zapisu ma dodać usunięcie, a pętla zrobi je później.
local function writeEntry(id: number, entry: Entry)
	local map = ticketMap(entry.river)
	local key = tostring(id)
	entry.dirty = false
	local ok: boolean, result: any
	if entry.written then
		-- Transformacja zwraca nil przy braku biletu, więc odnowienie go nie wskrzesi: brak = lider zabrał bilet do grupy.
		ok, result = pcall(function()
			return map:UpdateAsync(key, function(old: any, sortKey: any)
				if old == nil then
					return nil
				end
				return entry.ticket, sortKey
			end, Config.MATCH_TICKET_TTL)
		end)
		if ok and result == nil then
			entry.takenAt = entry.takenAt or now()
		end
	else
		entry.written = true
		ok, result = pcall(function()
			return map:SetAsync(key, entry.ticket, Config.MATCH_TICKET_TTL, entry.ticket.joinedAt)
		end)
		if not ok then
			entry.written = false
		end
	end
	if ok then
		entry.renewAt = now() + Config.MATCH_TICKET_RENEW
	else
		entry.dirty = true
		quietWarn("zapis biletu", result)
	end
	if MatchQueue.report(health, ok) then
		MatchService._modeChanged()
	end
end

local function syncTickets()
	local batch = removals
	removals = {}
	for _, removal in batch do
		local ok, err = pcall(function()
			ticketMap(removal.river):RemoveAsync(tostring(removal.userId))
		end)
		if not ok then
			quietWarn("usuwanie biletu", err) -- zostanie najwyżej na MATCH_TICKET_TTL
		end
	end

	local due: { number } = {}
	local time = now()
	for id, entry in entries do
		if entry.takenAt == nil and (not entry.written or entry.dirty or time >= entry.renewAt) then
			table.insert(due, id)
		end
	end
	for _, id in due do
		local entry = entries[id]
		if entry and not health.down then
			writeEntry(id, entry)
		end
	end
end

-- Zmiana trybu. Powrót do MemoryStore zapisuje bilety od nowa, bo przez awarię mogły wygasnąć.
function MatchService._modeChanged()
	if health.down then
		warn("[Match] MemoryStore niedostępny: tryb lokalny, bez teleportu")
		leaderSince = nil
		removals = {}
	else
		print("[Match] kolejka między serwerami włączona")
		for _, entry in entries do
			entry.written, entry.takenAt = false, nil
		end
	end
end

local function subscribe(): boolean
	if subscribed then
		return true
	end
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Config.MATCH_TOPIC, function(message)
			onMatch(message.Data)
		end)
		MessagingService:SubscribeAsync(Config.QUEUE_STATE_TOPIC, function(message)
			onState(message.Data)
		end)
	end)
	if not ok then
		quietWarn("subskrypcja", err)
	end
	subscribed = ok
	return ok
end

-- Blokada lidera: każdy serwer próbuje, udaje się temu, kto ją już ma, albo komukolwiek, gdy klucz wygasł.
local function claimLeader()
	local serverId = game.JobId
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap(Config.MATCH_LEADER_MAP):UpdateAsync(LEADER_KEY, function(current: any)
			return MatchQueue.claimLeader(current, serverId)
		end, Config.MATCH_LEADER_TTL)
	end)
	if ok then
		leaderSince = if result ~= nil then os.clock() else nil
	else
		quietWarn("blokada lidera", result)
	end
	if MatchQueue.report(health, ok) then
		MatchService._modeChanged()
	end
end

-- Zamknięcie serwera: oddajemy rolę od razu, a bilety sprzątamy, zanim PlayerRemoving przepadnie razem z pętlą zapisu.
local function onClose()
	if health.down then
		return
	end
	syncTickets()
	if isLeader() then
		pcall(function()
			MemoryStoreService:GetSortedMap(Config.MATCH_LEADER_MAP):RemoveAsync(LEADER_KEY)
		end)
	end
end

-- Gracz i strefa -----------------------------------------------------------------------------------------------------------

-- Czy gracz stoi w strefie kolejki? Świat może jeszcze nie istnieć, dlatego FindFirstChild w każdym obiegu.
local function inZone(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local folder = workspace:FindFirstChild("Piers")
	if root == nil or not root:IsA("BasePart") or folder == nil then
		return false
	end
	for _, zone in folder:GetChildren() do
		if zone:IsA("BasePart") and zone.Name == "QueueZone" then
			local point = zone.CFrame:PointToObjectSpace(root.Position)
			local half = zone.Size / 2
			if math.abs(point.X) <= half.X and math.abs(point.Y) <= half.Y and math.abs(point.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- Pozycja jest pewniejsza niż Touched (ten sam obieg co dawniej w PierService). Sprzątamy tu też zawieszone podróże i bilety.
local function scan(time: number)
	for _, player in Players:GetPlayers() do
		local id = player.UserId
		local trip = trips[id]
		if trip and not trip.retrying and time >= trip.deadline then
			warn(`[Match] {player.Name}: brak wieści o teleporcie po {Config.TRAVEL_TIMEOUT} s, próba {trip.attempts}`)
			onFailed(player, "Timeout")
		end
		local entry = entries[id]
		if entry then
			if entry.takenAt and time >= entry.takenAt + Config.MATCH_TAKEN_TIMEOUT then
				warn(`[Match] {player.Name}: bilet zabrany, ale Match nie doszedł`)
				forget(id, true)
				notice(id, "travel.failed")
			elseif not inZone(player) then
				forget(id)
			end
		end
	end
end

local function isRiver(river: any): boolean
	return type(river) == "string" and table.find(rivers, river) ~= nil
end

local function join(player: Player, river: any)
	local id = player.UserId
	local time = now()
	if not isRiver(river) or trips[id] or not inZone(player) then
		return
	end
	if time - (joinedAt[id] or -math.huge) < Config.MATCH_JOIN_COOLDOWN then
		return -- każde wejście to zapis w MemoryStore, a limit jest wspólny dla całej gry
	end
	local current = entries[id]
	if current then
		if current.river == river then
			return
		end
		forget(id) -- zmiana rzeki: nigdy dwie kolejki naraz
	end
	joinedAt[id] = time
	entries[id] = {
		ticket = MatchQueue.ticket(id, game.JobId, time),
		river = river,
		written = false,
		dirty = true,
		renewAt = 0,
		takenAt = nil,
	}
	mark(id)
end

local function onAction(player: Player, action: any, river: any)
	local id = player.UserId
	if action == "join" then
		join(player, river)
	elseif action == "leave" then
		forget(id)
	elseif action == "ready" then
		local entry = entries[id]
		if entry and not entry.ticket.ready then
			entry.ticket.ready = true
			entry.dirty = true
			mark(id)
		end
	else
		return
	end
	if health.down then
		localTick() -- bez sieci nie ma na co czekać: „Płyń teraz” solo rusza od razu
	end
end

local function sendAllTo(player: Player)
	for river, state in sent do
		queueState:FireClient(player, river, state.count, state.endsAt, state.ready)
	end
end

-- Dostępne rzeki. RiverCatalog czytamy tutaj, a nie na górze pliku: gdyby go zabrakło, reszta wioski ma działać.
local function loadRivers()
	local Content = Shared:WaitForChild("content")
	local module = Content:FindFirstChild("RiverCatalog")
	local ok, catalog = pcall(require, module)
	if not ok then
		warn(`[Match] brak katalogu rzek: {catalog}`)
		return
	end
	local files = Content:WaitForChild("rivers")
	for _, entry in catalog do
		if entry.available and entry.river and files:FindFirstChild(entry.river) then
			table.insert(rivers, entry.river)
			sent[entry.river] = EMPTY
		end
	end
end

function MatchService.init()
	queueState = Remotes.get("QueueState")
	travelNotice = Remotes.get("TravelNotice")
	loadRivers()

	Remotes.onServer("QueueAction", 2, 4, onAction)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Match] {player.Name}: teleport nie wystartował ({result.Name} = {result.Value}: {message})`)
		-- IsTeleporting: poprzednia próba wciąż leci. Rozstrzygnie ją koniec czasu albo wyjście gracza z serwera.
		if result ~= Enum.TeleportResult.IsTeleporting then
			onFailed(player :: Player, result.Name)
		end
	end)
end

function MatchService.start()
	Players.PlayerAdded:Connect(sendAllTo)
	for _, player in Players:GetPlayers() do
		sendAllTo(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local id = player.UserId
		forget(id)
		trips[id], joinedAt[id] = nil, nil
	end)

	if not STUDIO then
		game:BindToClose(onClose)
		task.spawn(function() -- blokada i powrót po awarii
			while true do
				if subscribe() then
					claimLeader()
				end
				task.wait(if health.down then Config.MATCH_PROBE_INTERVAL else Config.MATCH_LEADER_RENEW)
			end
		end)
		task.spawn(function() -- zapis biletów
			while true do
				task.wait(1)
				if not health.down then
					syncTickets()
				end
			end
		end)
	end

	task.spawn(function() -- decyzje
		while true do
			task.wait(Config.MATCH_TICK)
			if health.down then
				localTick()
			elseif isLeader() then
				leaderTick()
			end
		end
	end)

	while true do
		task.wait(Config.PIER_SCAN_INTERVAL)
		scan(now())
	end
end

return MatchService
