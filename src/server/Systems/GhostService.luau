-- Duchy: nagrywa przejazd z pozycji Hull, które czyta RaceService, zapisuje rekordy i wysyła graczom gotowe ślady.
-- DataStore `Ghosts_<rzeka>`: klucz `u<userId>` to własny duch, `top` to rekord świata. Duch to dodatek: każde zapytanie
-- jest w pcall i biegnie w osobnym wątku, a bez danych (Studio bez API, awaria) wyścig idzie dalej bez zmian.
-- Klient niczego tu nie przysyła, więc nie ma jak podmienić śladu.
-- (Dla TS: serwis z cache w Mapie, zapis to `void save()` poza główną pętlą, błędy kończą się w catch.)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GhostTrack = require(Shared:WaitForChild("GhostTrack"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RaceLogic = require(script.Parent.Parent.RaceLogic)
local RiverBuilder = require(script.Parent.RiverBuilder)

local GhostService = {}

local TOP_KEY = "top"

local ghostData = Remotes.get("GhostData")
local store: DataStore? = nil

local recorders: { [number]: GhostTrack.Recorder } = {} -- userId → nagranie bieżącego przejazdu
local own: { [number]: any } = {} -- userId → Track; false = sprawdzone, nie ma; nil = jeszcze nie wiemy
local sent: { [number]: { own: any, world: any } } = {} -- co gracz już ma: ślad to do 20 KB, nie wysyłamy go co rundę
local top: any = nil -- rekord świata (Track)
local topCheckedAt = -math.huge
local topBusy = false
local pendingSaves = 0

local function report(action: string, message: any)
	if not RunService:IsStudio() then
		warn(`[Ghost] {action}: {message}`)
	end
end

local function ownKey(userId: number): string
	return `u{userId}`
end

-- Szybszy z dwóch śladów; każdy może być nil albo false.
local function faster(a: any, b: any): any
	if not a then
		return b
	elseif not b then
		return a
	end
	return if b.ms < a.ms then b else a
end

-- (czy odczyt się udał, poprawny ślad albo nil). Wadliwy wpis traktujemy jak brak wpisu.
local function read(key: string): (boolean, any)
	local dataStore = store
	if not dataStore then
		return false, nil
	end
	local ok, value = pcall(function()
		return dataStore:GetAsync(key)
	end)
	if not ok then
		report("odczyt", value)
		return false, nil
	end
	return true, if GhostTrack.validate(value) then value else nil
end

-- UpdateAsync, nie SetAsync: na innym serwerze mógł właśnie wpaść lepszy czas. Zwraca lepszy wpis, jeśli taki już był.
local function save(key: string, track: any): any
	local dataStore = store :: DataStore
	local better = nil
	for attempt = 1, Config.GHOST_SAVE_TRIES do
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(old: any)
				if GhostTrack.validate(old) and old.ms <= track.ms then
					better = old
					return nil -- nil = bez zmian
				end
				better = nil
				return track, { track.userId } -- lista userId: powiązanie danych z kontem (RODO), jak AddUserId w profilu
			end)
		end)
		if ok then
			return better
		end
		report("zapis", err)
		if attempt < Config.GHOST_SAVE_TRIES then
			task.wait(Config.GHOST_SAVE_WAIT)
		end
	end
	return nil
end

local function persist(userId: number, track: any, saveOwn: boolean, saveTop: boolean)
	pendingSaves += 1
	if saveOwn then
		local better = save(ownKey(userId), track)
		if better and own[userId] == track then
			own[userId] = better
		end
	end
	if saveTop then
		local better = save(TOP_KEY, track)
		if better and top == track then
			top = better
		end
	end
	pendingSaves -= 1
end

-- Rekord świata czytamy rzadko. Gdy kilku graczy pyta naraz, reszta czeka na ten sam odczyt.
local function refreshTop()
	while topBusy do
		task.wait()
	end
	if os.clock() - topCheckedAt < Config.GHOST_TOP_REFRESH then
		return
	end
	topBusy, topCheckedAt = true, os.clock()
	local ok, value = read(TOP_KEY)
	if ok then
		top = faster(top, value)
	end
	topBusy = false
end

-- Najwyżej dwa duchy, także w grupie: własny i rekord świata. Własny rekord świata to ten sam przejazd, więc jeden kajak.
local function deliver(player: Player)
	local id = player.UserId
	refreshTop()
	if own[id] == nil then
		local ok, value = read(ownKey(id))
		if ok and player.Parent == Players then
			own[id] = faster(own[id], value) or false
		end
	end
	if player.Parent ~= Players then
		return
	end

	local mine, world = own[id] or nil, top
	if world and world.userId == id then
		mine, world = faster(mine, world), nil
	end
	local last = sent[id]
	if last and last.own == mine and last.world == world then
		return
	end
	sent[id] = { own = mine, world = world }

	local list = {}
	if mine then
		table.insert(list, { kind = "own", track = mine })
	end
	if world then
		table.insert(list, { kind = "world", track = world })
	end
	ghostData:FireClient(player, list)
end

-- Gracz zapisany na wyścig: nowe nagranie i ślady na ten wyścig. Nie blokuje wołającego.
function GhostService.prepare(player: Player)
	recorders[player.UserId] = GhostTrack.newRecorder()
	task.spawn(deliver, player)
end

-- Odczyt z RaceService. `t` liczymy od racer.startedAt, czyli od tej samej chwili co oficjalny czas wyścigu.
function GhostService.sample(userId: number, t: number, hull: BasePart, last: boolean)
	local recorder = recorders[userId]
	if recorder then
		local position, look = hull.Position, hull.CFrame.LookVector
		GhostTrack.record(recorder, t, position.X, position.Y, position.Z, math.atan2(look.Z, look.X), last)
	end
end

-- Przejazd przyjęty przez RaceLogic. Zapis idzie w tle, a pamięć serwera zmienia się od razu: następna runda dostanie
-- nowego ducha także wtedy, gdy DataStore nie działa.
function GhostService.finish(player: Player, time: number)
	local id = player.UserId
	local recorder = recorders[id]
	recorders[id] = nil
	if not recorder then
		return
	end
	local ms = RaceLogic.timeToScore(time)
	local mine = own[id]
	local beatsOwn = RaceLogic.isRecord(if mine then mine.ms else nil, ms)
	local beatsTop = RaceLogic.isRecord(if top then top.ms else nil, ms)
	if not beatsOwn and not beatsTop then
		return
	end
	local track = GhostTrack.finish(recorder, ms, id)
	if track == nil then
		warn(`[Ghost] ślad gracza {player.Name} nie przeszedł walidacji albo limitu rozmiaru`)
		return
	end
	if beatsOwn then
		own[id] = track
	end
	if beatsTop then
		top = track
	end
	if store then
		task.spawn(persist, id, track, beatsOwn, beatsTop)
	end
end

function GhostService.init()
	-- Sam store też w pcall: w Studio bez API potrafi rzucić już tutaj.
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "Ghosts_" .. RiverBuilder.river.id)
	if ok then
		store = result
	else
		report("store", result)
	end
end

function GhostService.start()
	Players.PlayerRemoving:Connect(function(player)
		local id = player.UserId
		recorders[id], own[id], sent[id] = nil, nil, nil
	end)
	-- Serwer zarezerwowany gaśnie zaraz po odejściu graczy, a ostatni rekord może być jeszcze w zapisie.
	game:BindToClose(function()
		local deadline = os.clock() + Config.GHOST_CLOSE_WAIT
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait()
		end
	end)
end

return GhostService
