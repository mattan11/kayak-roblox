-- Kolejki pomostów i wyjazd grupy na spływ (ARCHITECTURE.md, „Przejście wioska → spływ”). Zasady kolejki: shared/PierQueue.
-- Co PIER_SCAN_INTERVAL porównujemy pozycje graczy ze strefami i doprowadzamy kolejki do zgodności. Pozycja jest pewniejsza
-- niż Touched, a odczyt workspace.Piers w każdym obiegu sam obsługuje strefy dodane później albo brak świata.
-- (Dla TS: reconcile loop, jak w Kubernetesie: stan pożądany → poprawki, zamiast handlera na każde zdarzenie.)
--
-- Gracz w drodze ma wpis w `trips` i pętla go pomija. Gdy podróż się nie uda, wpis znika, a gracz stojący w strefie sam wraca
-- do kolejki w następnym obiegu. Jedna ścieżka załatwia porażkę teleportu, wyczerpane próby i Studio.
-- Rezerwacja: patrz reserve() (jedyne miejsce z ReserveServerAsync).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PierQueue = require(Shared:WaitForChild("PierQueue"))
local Places = require(Shared:WaitForChild("Places"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Content = Shared:WaitForChild("content")
local Piers = require(Content:WaitForChild("Piers"))

local PierService = {}

type Trip = { attempts: number, deadline: number, options: TeleportOptions? }

local queues: { [string]: any } = {} -- pierId → PierQueue; tylko pomosty z rzeką, nie zaślepki
local riverOf: { [string]: string } = {} -- pierId → nazwa rzeki
local sent: { [string]: { count: number, endsAt: number? } } = {} -- ostatni wysłany PierState
local inQueue: { [number]: string } = {} -- userId → pierId
local refused: { [number]: string } = {} -- kliknął „Zejdź”: wraca do kolejki dopiero po zejściu ze strefy
local trips: { [number]: Trip } = {} -- userId → podróż w toku

local pierState: RemoteEvent
local travelNotice: RemoteEvent

-- Pomost pod graczem albo nil. Świat może jeszcze nie istnieć, dlatego FindFirstChild w każdym obiegu.
local function pierAt(position: Vector3): string?
	local folder = workspace:FindFirstChild("Piers")
	if folder == nil then
		return nil
	end
	for _, zone in folder:GetChildren() do
		if zone:IsA("BasePart") and zone.Name == "QueueZone" then
			local localPosition = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y and math.abs(localPosition.Z) <= half.Z then
				local pierId = zone:GetAttribute("PierId")
				return if type(pierId) == "string" and queues[pierId] then pierId else nil
			end
		end
	end
	return nil
end

-- Podróż się nie odbyła. Komunikat, a pętla sama przywróci gracza do kolejki.
local function release(player: Player, textKey: string)
	trips[player.UserId] = nil
	travelNotice:FireClient(player, textKey)
end

local onFailed: (Player) -> ()

local function send(group: { Player }, options: TeleportOptions)
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, Places.placeId("race"), group, options)
	if not ok then
		warn(`[Pier] teleport: {err}`)
		for _, player in group do
			onFailed(player)
		end
	end
end

-- Nieudana próba (błąd pcall albo TeleportInitFailed): ponowienie tego gracza na ten sam serwer albo koniec.
function onFailed(player: Player)
	local trip = trips[player.UserId]
	if trip == nil or player.Parent ~= Players then
		return
	end
	if trip.attempts >= Config.TRAVEL_TRIES or trip.options == nil then
		release(player, "travel.failed")
		return
	end
	trip.attempts += 1
	trip.deadline = workspace:GetServerTimeNow() + Config.TRAVEL_TIMEOUT
	task.delay(Config.TRAVEL_RETRY_WAIT, function()
		if trips[player.UserId] == trip and player.Parent == Players then
			send({ player }, trip.options :: TeleportOptions)
		end
	end)
end

-- Serwer zarezerwowany + wpis w MemoryStore. Wpis musi powstać PRZED teleportem, bo spływ czyta go zaraz po starcie.
-- ReserveServerAsync i ReservedServerAccessCode dokumentacja oznacza już jako przestarzałe, ale tylko ta para ma potwierdzony
-- związek z game.PrivateServerId, na którym opiera się odczyt wpisu. Migracja na ReservedServerId dotyczy tylko tej funkcji.
local function reserve(river: string, expected: number): TeleportOptions?
	for attempt = 1, Config.TRAVEL_TRIES do
		local ok, result = pcall(function()
			local code, privateServerId = TeleportService:ReserveServerAsync(Places.placeId("race"))
			local map = game:GetService("MemoryStoreService"):GetSortedMap(Config.RACE_TICKET_MAP)
			map:SetAsync(privateServerId, { river = river, expected = expected }, Config.RACE_TICKET_TTL)
			return code
		end)
		if ok then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = result
			return options
		end
		warn(`[Pier] rezerwacja, próba {attempt}: {result}`)
		if attempt < Config.TRAVEL_TRIES then
			task.wait(Config.TRAVEL_RETRY_WAIT)
		end
	end
	return nil
end

-- Start grupy z pomostu (koniec odliczania albo „Płyń teraz”).
local function startGroup(pierId: string, members: { number })
	local group: { Player } = {}
	local deadline = workspace:GetServerTimeNow() + Config.TRAVEL_TIMEOUT
	for _, id in members do
		inQueue[id] = nil
		local player = Players:GetPlayerByUserId(id)
		if player then
			trips[id] = { attempts = 1, deadline = deadline }
			table.insert(group, player)
		end
	end
	if #group == 0 then
		return
	end

	if RunService:IsStudio() then
		for _, player in group do
			release(player, "travel.studio")
		end
		return
	end

	task.spawn(function()
		local options = reserve(riverOf[pierId], #group)
		if options == nil then
			for _, player in group do
				if player.Parent == Players then
					release(player, "travel.failed")
				end
			end
			return
		end
		local present: { Player } = {}
		for _, player in group do
			local trip = trips[player.UserId]
			if trip and player.Parent == Players then
				trip.options = options
				table.insert(present, player)
			end
		end
		if #present > 0 then
			send(present, options)
		end
	end)
end

-- Jeden obieg: kto gdzie stoi → kolejki.
local function scan(now: number)
	for _, player in Players:GetPlayers() do
		local id = player.UserId
		local trip = trips[id]
		if trip and now >= trip.deadline then
			trips[id], trip = nil, nil
		end
		if trip == nil then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local pierId = if root and root:IsA("BasePart") then pierAt(root.Position) else nil

			if refused[id] ~= pierId then
				refused[id] = nil
			end
			local current = inQueue[id]
			if current and current ~= pierId then
				queues[current]:leave(id)
				inQueue[id], current = nil, nil
			end
			if pierId and current == nil and refused[id] == nil and queues[pierId]:join(id, now) then
				inQueue[id] = pierId
			end
		end
	end
end

-- PierState tylko po zmianie, jak RaceState w RaceService.
local function broadcast()
	for pierId, queue in queues do
		local last = sent[pierId]
		if last.count ~= queue:count() or last.endsAt ~= queue.endsAt then
			last.count, last.endsAt = queue:count(), queue.endsAt
			pierState:FireAllClients(pierId, last.count, last.endsAt)
		end
	end
end

local function onAction(player: Player, action: any, pierId: any)
	local queue = if type(pierId) == "string" then queues[pierId] else nil
	local id = player.UserId
	if queue == nil or not queue:has(id) then
		return
	end
	if action == "leave" then
		queue:leave(id)
		inQueue[id] = nil
		refused[id] = pierId
	elseif action == "go" then
		startGroup(pierId, queue:go(id))
	end
end

local function sendAllTo(player: Player)
	for pierId, last in sent do
		pierState:FireClient(player, pierId, last.count, last.endsAt)
	end
end

function PierService.init()
	pierState = Remotes.get("PierState")
	travelNotice = Remotes.get("TravelNotice")

	local rivers = Content:WaitForChild("rivers")
	for _, pier in Piers do
		if pier.river then
			queues[pier.id] = PierQueue.new()
			sent[pier.id] = { count = 0, endsAt = nil }
			riverOf[pier.id] = if rivers:FindFirstChild(pier.river) then pier.river else Config.ACTIVE_RIVER
		end
	end

	Remotes.onServer("PierAction", 2, 4, onAction)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Pier] {player.Name}: teleport nie wystartował ({result}: {message})`)
		onFailed(player :: Player)
	end)
end

function PierService.start()
	Players.PlayerAdded:Connect(sendAllTo)
	for _, player in Players:GetPlayers() do
		sendAllTo(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local id = player.UserId
		local pierId = inQueue[id]
		if pierId then
			queues[pierId]:leave(id)
		end
		inQueue[id], refused[id], trips[id] = nil, nil, nil
	end)

	while true do
		task.wait(Config.PIER_SCAN_INTERVAL)
		local now = workspace:GetServerTimeNow()
		scan(now)
		for pierId, queue in queues do
			local group = queue:tick(now)
			if group then
				startGroup(pierId, group)
			end
		end
		broadcast()
	end
end

return PierService
