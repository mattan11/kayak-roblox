-- Wodna bitwa na serwerze (ARCHITECTURE.md, „Strefy na jeziorze i Wodna bitwa”). Zasady są w shared/ArenaRules, tutaj tylko świat
-- i sieć: co ARENA_TICK zbieramy migawkę kajaków, karmimy nią ArenaRules i rozsyłamy skutki. Trafienia i strefę rozstrzyga serwer
-- z pozycji Hull, a od klienta bierzemy tylko „chcę strzelić”, bez żadnych argumentów.
-- W trybach race i battle start() wychodzi od razu: żadnej pętli, żadnych handlerów. W arena z kolei RaceService milczy, więc
-- RaceState nie idzie: fazy niesie ArenaState. Rekordy, medale, duchy i rankingi nie mają stąd żadnego wejścia.
-- (Dla TS: kontroler nad reducerem, jak RaceService nad RaceLogic.)
--
-- Spóźnialski (doszedł po starcie walki) dostaje kajak z flagą Finished: patrzy i wchodzi do następnej rundy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared:WaitForChild("content"):WaitForChild("ArenaLayout"))
local ArenaRules = require(Shared:WaitForChild("ArenaRules"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local KayakService = require(script.Parent.KayakService)
local RiverBuilder = require(script.Parent.RiverBuilder)
local TravelService = require(script.Parent.TravelService)

local ArenaService = {}

local match: ArenaRules.Match
local nextSlot = 1 -- kolejne miejsce startowe w tej rundzie
local sentHealth: { [number]: number } = {} -- userId → ostatnia wysłana wytrzymałość
local sentPhase, sentEndsAt, sentAlive, sentRadiusAt = "", 0, -1, 0
local sentVotes = ""

local raceVotes: RemoteEvent
local arenaState: RemoteEvent
local arenaHealth: RemoteEvent
local arenaHit: RemoteEvent
local arenaOut: RemoteEvent
local arenaResults: RemoteEvent
local resetEvent: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function roster(): { ArenaRules.Entrant }
	local list: { ArenaRules.Entrant } = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, { id = player.UserId, name = player.Name })
	end
	return list
end

-- Migawka z Hull: tylko gracze, którzy mają kajak. Kto wyszedł z serwera, nie ma kajaka, więc nie jest ani celem, ani strzelcem.
local function snapshot(): { [number]: ArenaRules.Fighter }
	local fighters: { [number]: ArenaRules.Fighter } = {}
	for _, player in Players:GetPlayers() do
		local kayak = KayakService.get(player)
		local hull = kayak and kayak.PrimaryPart
		if hull then
			local look = hull.CFrame.LookVector
			local flat = Vector2.new(look.X, look.Z)
			fighters[player.UserId] = {
				position = Vector2.new(hull.Position.X, hull.Position.Z),
				-- Kajak jest zawsze prawie poziomo, ale zerowy wektor dałby NaN w Unit.
				forward = if flat.Magnitude > 0 then flat.Unit else Vector2.xAxis,
			}
		end
	end
	return fighters
end

-- Liczba do wysłania: ile osób liczy się teraz na ekranie. Poza walką to po prostu gracze na serwerze.
local function aliveCount(): number
	return if match.phase == "racing" or match.phase == "results" then match.alive else #Players:GetPlayers()
end

local function radiusNow(): number
	return ArenaRules.currentRadius(match, ArenaLayout.radius, now())
end

-- Stan idzie po każdej zmianie, a sam promień co ARENA_STATE_INTERVAL: klient między odczytami dorysowuje go sam.
local function sendState()
	local time = now()
	local alive = aliveCount()
	local changed = match.phase ~= sentPhase or match.phaseEndsAt ~= sentEndsAt or alive ~= sentAlive
	local radiusDue = match.phase == "racing" and time >= sentRadiusAt + Config.ARENA_STATE_INTERVAL
	if changed or radiusDue then
		sentPhase, sentEndsAt, sentAlive, sentRadiusAt = match.phase, match.phaseEndsAt, alive, time
		arenaState:FireAllClients(match.phase, match.phaseEndsAt, radiusNow(), alive)
	end
end

-- Wytrzymałość tylko po zmianie widocznej liczby: strefa pali po ułamku w każdym obiegu.
local function sendHealth()
	for id, contender in match.contenders do
		local shown = math.ceil(contender.health)
		if sentHealth[id] ~= shown then
			local player = Players:GetPlayerByUserId(id)
			if player then
				sentHealth[id] = shown
				arenaHealth:FireClient(player, shown)
			end
		end
	end
end

-- Odpadnięty zostaje na wodzie: Finished zabiera mu stery, a kamera i świat działają dalej.
local function sendOut(out: ArenaRules.Out)
	arenaOut:FireAllClients(out.userId, out.name, out.place)
	local player = Players:GetPlayerByUserId(out.userId)
	if player then
		KayakService.setFinished(player)
	end
end

-- Stawia kajak na kolejnym miejscu startowym i każe klientowi wyzerować fizykę.
local function seat(player: Player)
	local position, heading = ArenaRules.spawnPoint(ArenaLayout, nextSlot)
	nextSlot += 1
	KayakService.place(player, position, heading)
	resetEvent:FireClient(player, position.X, position.Y, heading)
end

local function onPhase(phase: ArenaRules.Phase)
	if phase == "countdown" then
		nextSlot = 1
		sentHealth = {}
		for _, player in Players:GetPlayers() do
			seat(player)
			arenaHealth:FireClient(player, Config.ARENA_HEALTH) -- pasek pełny już w odliczaniu
		end
	elseif phase == "results" then
		arenaResults:FireAllClients(match.rows)
	end
end

-- Licznik decyzji tylko po zmianie, jak w RaceService.
local function sendVotes()
	if match.phase == "results" or match.phase == "countdown" then
		local again, leaving, undecided = ArenaRules.tally(match, #Players:GetPlayers())
		local votes = `{again}/{leaving}/{undecided}`
		if votes ~= sentVotes then
			sentVotes = votes
			raceVotes:FireAllClients(again, leaving, undecided)
		end
	else
		sentVotes = ""
	end
end

local function tick(time: number)
	if match.phase == "racing" then
		for _, out in ArenaRules.burn(match, ArenaLayout, snapshot(), time) do
			sendOut(out)
		end
	end
	local changed = ArenaRules.tick(match, time, roster())
	-- Najpierw ArenaState, żeby klient znał fazę, zanim dostanie Reset albo wyniki.
	sendState()
	if changed then
		onPhase(changed)
	end
	sendHealth()
	sendVotes()
	ArenaBuilder.setZone(radiusNow())
	-- Serwer zarezerwowany nikogo już nie przyjmie: samotny gracz wraca do wioski, zamiast czekać bez końca.
	if ArenaRules.stranded(match, time) then
		for _, player in Players:GetPlayers() do
			TravelService.toVillage(player)
		end
	end
end

-- Od klienta to tylko prośba bez argumentów: kogo trafia i czy może strzelić, rozstrzyga ArenaRules z pozycji Hull.
-- Limit z Remotes tnie zalew zapytań, a odnowienie w ArenaRules pilnuje tempa strzałów. Odmowa jest cicha.
local function onFire(player: Player)
	local id = player.UserId
	local shot = ArenaRules.fire(match, id, snapshot(), now())
	if shot == nil then
		return
	end
	arenaHit:FireAllClients(id, shot.target)
	if shot.out then
		sendOut(shot.out)
	end
	sendHealth()
	sendState()
end

-- Przyciski z ekranu wyników i „Wyjdź”. RaceService tu nie działa, więc obsługujemy je sami, tak samo jak w wyścigu.
-- Od klienta to tylko prośba: nieznana akcja przepada, a głos liczy się wg fazy (ArenaRules).
local function onRaceAction(player: Player, action: any)
	if action == "again" then
		ArenaRules.voteAgain(match, player.UserId)
	elseif action == "village" then
		ArenaRules.voteLeave(match, player.UserId)
		TravelService.toVillage(player)
	end
end

local function onPlayerAdded(player: Player)
	arenaState:FireClient(player, match.phase, match.phaseEndsAt, radiusNow(), aliveCount())
	seat(player)
	if match.phase == "racing" then
		KayakService.setFinished(player)
	end
end

local function onPlayerRemoving(player: Player)
	local id = player.UserId
	sentHealth[id] = nil
	local out = ArenaRules.leave(match, id)
	if out then
		arenaOut:FireAllClients(out.userId, out.name, out.place)
	end
end

function ArenaService.start()
	if RiverBuilder.mode ~= "arena" then
		return
	end
	arenaState = Remotes.get("ArenaState")
	arenaHealth = Remotes.get("ArenaHealth")
	arenaHit = Remotes.get("ArenaHit")
	arenaOut = Remotes.get("ArenaOut")
	arenaResults = Remotes.get("ArenaResults")
	resetEvent = Remotes.get("Reset")
	raceVotes = Remotes.get("RaceVotes")
	TravelService.onGiveUp = function(player)
		ArenaRules.cancelLeave(match, player.UserId)
	end
	-- W Studio wystarczy jeden gracz, żeby sprawdzić Play bez dwóch klientów. Poza Studio solo nie gra: patrz ArenaRules.stranded.
	match = ArenaRules.newMatch(RiverBuilder.expected, if RunService:IsStudio() then 1 else Config.ARENA_MIN_PLAYERS)

	Remotes.onServer("ArenaFire", Config.ARENA_FIRE_RATE, Config.ARENA_FIRE_BURST, onFire)
	Remotes.onServer("RaceAction", 2, 4, onRaceAction)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Po teleporcie gracz bywa na serwerze, zanim skończy się budowa świata.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	while true do
		task.wait(Config.ARENA_TICK)
		tick(now())
	end
end

return ArenaService
