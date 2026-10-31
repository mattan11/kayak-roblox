-- Wyścig: łączy czystą logikę (RaceLogic) ze światem. Co RACE_SAMPLE_INTERVAL czyta pozycje Hull, liczy `s` przez
-- River:query, karmi nimi RaceLogic i wysyła zdarzenia. Sam niczego nie decyduje o fazach ani czasach.
-- (Dla TS: „kontroler” nad reducerem: pętla jak setInterval, efekty uboczne tutaj, logika w czystym module.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RaceLogic = require(script.Parent.Parent.RaceLogic)
local Analytics = require(script.Parent.Analytics)
local GhostService = require(script.Parent.GhostService)
local KayakService = require(script.Parent.KayakService)
local Leaderboard = require(script.Parent.Leaderboard)
local PlayerData = require(script.Parent.PlayerData)
local RiverBuilder = require(script.Parent.RiverBuilder)
local TravelService = require(script.Parent.TravelService)

local RaceService = {}

local river: any -- oba ustawiane w init(): rzeka powstaje dopiero w RiverBuilder.init()
local race: any
local hints: { [number]: number } = {} -- userId → ostatni odcinek rzeki (szybsze query, bez skoków między zakolami)

local raceState = Remotes.get("RaceState")
local raceResults = Remotes.get("RaceResults")
local resetEvent = Remotes.get("Reset")
local raceVotes = Remotes.get("RaceVotes")

-- Stawia gracza na kolejnym wolnym miejscu startowym i zapisuje go do wyścigu.
local function enroll(player: Player, now: number)
	local startWidth = river:query(river:pointAt(Config.START_DISTANCE)).halfWidth
	local s, lateral = RaceLogic.slot(race.nextSlot, startWidth)
	local center = river:pointAt(s)
	local q = river:query(center)
	local position = center + q.normal * lateral
	local heading = math.atan2(q.tangent.Y, q.tangent.X)

	race:enroll(player.UserId, player.Name, position, s, now)
	hints[player.UserId] = q.index
	KayakService.place(player, position, heading)
	resetEvent:FireClient(player, position.X, position.Y, heading)
	GhostService.prepare(player)
end

local function onFinished(player: Player, time: number)
	KayakService.setFinished(player)
	PlayerData.recordFinish(player, time)
	Analytics.raceFinished(player, time)
	GhostService.finish(player, time)
end

local function sampleRacers(now: number)
	for id, racer in race.racers do
		local player = Players:GetPlayerByUserId(id)
		local kayak = player and KayakService.get(player)
		if player and kayak and not racer.time and not racer.invalid then
			local hull = kayak.PrimaryPart :: BasePart
			local position = Vector2.new(hull.Position.X, hull.Position.Z)
			-- Po dużym skoku (lag) stara podpowiedź zgubiłaby kajak, więc wtedy szukamy w całej rzece.
			local jumped = (position - racer.lastPosition).Magnitude > Config.HINT_SEARCH_LIMIT
			local q = river:query(position, if jumped then nil else hints[id])
			hints[id] = q.index
			local outcome = race:sample(id, position, q.s, math.abs(q.lateral) - q.halfWidth, now)
			if racer.startedAt and outcome ~= "invalid" then
				GhostService.sample(id, now - racer.startedAt, hull, outcome == "finished")
			end
			if outcome == "finished" then
				onFinished(player, race.racers[id].time)
			elseif outcome == "invalid" then
				warn(`[Race] odrzucony wynik gracza {player.Name} (prędkość lub pozycja poza limitem)`)
			end
		end
	end
end

local function onPhase(phase: RaceLogic.Phase, now: number)
	if phase == "countdown" then
		hints = {}
		for _, player in Players:GetPlayers() do
			enroll(player, now)
		end
	elseif phase == "results" then
		local rows = race:results()
		raceResults:FireAllClients(rows)
		-- Wygrana liczy się tylko w wyścigu z kimś: solo każdy byłby pierwszy.
		if #rows >= 2 then
			local winner = Players:GetPlayerByUserId(rows[1].userId)
			if winner then
				PlayerData.addWin(winner)
			end
		end
		task.spawn(Leaderboard.refresh)
	end
end

local function onPlayerAdded(player: Player)
	raceState:FireClient(player, race.phase, race.phaseEndsAt)
	if race:canEnroll() and not race.racers[player.UserId] then
		enroll(player, workspace:GetServerTimeNow())
	end
end

-- Przyciski z ekranu wyników. Od klienta to tylko prośba: nieznana akcja przepada, a głos liczy się wg fazy (RaceLogic).
local function onRaceAction(player: Player, action: any)
	if action == "again" then
		race:voteAgain(player.UserId)
	elseif action == "village" then
		race:voteLeave(player.UserId)
		TravelService.toVillage(player)
	end
end

function RaceService.init()
	river = RiverBuilder.river
	race = RaceLogic.new(Config.START_LINE, river.length - Config.FINISH_MARGIN)
	if RiverBuilder.expected then
		race:expectPlayers(RiverBuilder.expected)
	end
	Remotes.onServer("RaceAction", 2, 4, onRaceAction)
	TravelService.onGiveUp = function(player)
		race:cancelLeave(player.UserId)
	end
end

function RaceService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Po teleporcie gracz bywa na serwerze, zanim skończy się budowa świata.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		race:remove(player.UserId)
		hints[player.UserId] = nil
	end)

	local sentPhase, sentEndsAt = race.phase, race.phaseEndsAt
	local sentVotes = ""
	while true do
		task.wait(Config.RACE_SAMPLE_INTERVAL)
		local now = workspace:GetServerTimeNow()
		if race.phase == "racing" then
			sampleRacers(now)
		end
		local changed = race:tick(now, #Players:GetPlayers())
		-- Najpierw RaceState, żeby klient znał fazę, zanim dostanie Reset albo wyniki.
		if race.phase ~= sentPhase or race.phaseEndsAt ~= sentEndsAt then
			sentPhase, sentEndsAt = race.phase, race.phaseEndsAt
			raceState:FireAllClients(sentPhase, sentEndsAt)
		end
		if changed then
			onPhase(changed, now)
		end
		-- Licznik decyzji tylko po zmianie, jak RaceState.
		if race.phase == "results" or race.phase == "countdown" then
			local again, leaving, undecided = race:tally(#Players:GetPlayers())
			local votes = `{again}/{leaving}/{undecided}`
			if votes ~= sentVotes then
				sentVotes = votes
				raceVotes:FireAllClients(again, leaving, undecided)
			end
		else
			sentVotes = ""
		end
	end
end

return RaceService
