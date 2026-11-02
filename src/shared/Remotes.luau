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
	QueueState = "reliable", -- serwer → wszyscy (wioska): (river, liczba, koniec odliczania, gotowi)
	QueueAction = "reliable", -- klient → serwer (wioska): ("join", river) | ("leave") | ("ready")
	TravelNotice = "reliable", -- serwer → gracz: klucz tekstu o podróży
	RaceAction = "reliable", -- klient → serwer (spływ): "again" | "village"
	RaceVotes = "reliable", -- serwer → wszyscy (spływ): (płyną dalej, do wioski, niezdecydowani)
	MedalAwarded = "reliable", -- serwer → gracz: (riverId, stopień 1..3) po przyjęciu czasu
	GhostData = "reliable", -- serwer → gracz: (lista duchów) przed startem wyścigu
	SettingAction = "reliable", -- klient → serwer: (nazwa ustawienia, bool), PlayerSettings
	BattleUse = "reliable", -- klient → serwer: użycie przedmiotu
	BattleItem = "reliable", -- serwer → gracz: id przedmiotu lub nil
	BattleEffect = "reliable", -- serwer → gracz: (rodzaj, czas)
	BattleCrate = "reliable", -- serwer → wszyscy: (numer skrzynki, dostępna)
	BattleWorld = "reliable", -- serwer → wszyscy: ("net", x, z, id, aktywna)
	ArenaFire = "reliable", -- klient → serwer: (true | false) początek i koniec strumienia
	ArenaTank = "unreliable", -- serwer → gracz: (zbiornik 0..1)
	ArenaPush = "reliable", -- serwer → gracz: (dx, dz) odepchnięcie strumieniem
	ArenaState = "reliable", -- serwer → wszyscy: (faza, koniec fazy, promień strefy, żywi)
	ArenaHealth = "reliable", -- serwer → gracz: wytrzymałość
	ArenaHit = "reliable", -- serwer → wszyscy: (strzelający, cel lub nil)
	ArenaOut = "reliable", -- serwer → wszyscy: (userId, nazwa, miejsce)
	ArenaResults = "reliable", -- serwer → wszyscy: lista wyników
	PersonalBest = "reliable", -- serwer → gracz: (bestTime | nil, isNewRecord)
	CosmeticState = "reliable", -- serwer → gracz (wioska): { ready, failed, owned, equipped, unseen, stars, maxStars }
	CosmeticAction = "reliable", -- klient → serwer (wioska): ("sync") | ("equip", slot, itemId) | ("seen", slot); nigdy „odblokuj”
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
