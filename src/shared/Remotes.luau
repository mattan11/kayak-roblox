-- Jedna lista zdarzeń sieciowych (ARCHITECTURE.md). Tworzy je serwer, klient czeka, aż się pojawią.
-- Literówka w nazwie = błąd od razu. (Dla TS: jak lista typów wiadomości w socket.io.)
--
-- Zasada: wszystko OD klienta to prośba, nie fakt. Na serwerze rejestrujemy handler przez Remotes.onServer:
-- najpierw limit zapytań (RateLimit), potem handler, który sam sprawdza typy i zakresy argumentów.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimit = require(script.Parent.RateLimit)

type Kind = "reliable" | "unreliable"

-- Nazwa → rodzaj kanału. Dopisywać tu każde nowe zdarzenie (z komentarzem: kto → kto i co niesie).
local DEFINITIONS: { [string]: Kind } = {
	Paddle = "unreliable", -- klient → serwer: ruch wiosła ("stroke" | "brace" | "release", side) — tylko do animacji u innych
	PaddleEcho = "unreliable", -- serwer → wszyscy: (userId, kind, side) — animacja wiosła cudzego kajaka
	Reset = "reliable", -- serwer → gracz: ustaw kajak (x, z, heading) i wyzeruj fizykę
	RaceState = "reliable", -- serwer → wszyscy: (phase, phaseEndsAt) — czas z workspace:GetServerTimeNow()
	RaceResults = "reliable", -- serwer → wszyscy: lista { userId, name, time }, kolejność = miejsce
	Feedback = "reliable", -- klient → serwer: ocena wyścigu (stars 1..5) — Analytics
	PierState = "reliable", -- serwer → wszyscy (wioska): (pierId, liczba graczy, koniec odliczania)
	PierAction = "reliable", -- klient → serwer (wioska): ("leave" | "go", pierId)
	TravelNotice = "reliable", -- serwer → gracz: klucz tekstu o podróży
	RaceAction = "reliable", -- klient → serwer (spływ): "again" | "village"
	PersonalBest = "reliable", -- serwer → gracz: (bestTime | nil, isNewRecord)
}

local FOLDER_NAME = "Remotes"

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, kind in DEFINITIONS do
		local remote = Instance.new(if kind == "unreliable" then "UnreliableRemoteEvent" else "RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	if DEFINITIONS[name] == nil then
		error(`[Remotes] nieznane zdarzenie '{name}' — dopisz je do DEFINITIONS`, 2)
	end
	return folder:WaitForChild(name) :: any
end

-- Wspólny limiter dla wszystkich handlerów serwera.
local limiter = RateLimit.new()
if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		limiter:forget(player)
	end)
end

-- Rejestracja handlera na serwerze z limitem: `rate` zapytań/s, chwilowo do `burst`.
-- Zapytania ponad limit są po cichu odrzucane (oszust nie dostaje informacji zwrotnej).
function Remotes.onServer(name: string, rate: number, burst: number, handler: (Player, ...any) -> ())
	assert(RunService:IsServer(), "Remotes.onServer tylko na serwerze")
	Remotes.get(name).OnServerEvent:Connect(function(player, ...)
		if limiter:allow(player, name, rate, burst, os.clock()) then
			handler(player, ...)
		end
	end)
end

return Remotes
