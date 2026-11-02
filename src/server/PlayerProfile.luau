-- Profil gracza w ProfileStore, wspólny dla wioski i spływu (COSMETICS.md, sekcje 4–5). Tylko wczytanie, migracja, nagrody
-- i zwolnienie sesji; rzeczy spływowe (rekord, ranking, medale za przejazd) są w PlayerData, szafka w VillageCosmetics.
-- Leży poza Systems, bo oba miejsca montują go pod Server (village.project.json), obok Packages: ścieżka jest ta sama.
-- Nie jest systemem: start() wołają systemy, które go używają (drugie wołanie nic nie robi).
--
-- Blokada sesji: sesję zwalnia EndSession w PlayerRemoving, także przy teleporcie. Serwer docelowy czeka, aż stara sesja się
-- zapisze i zwolni (zwykle kilka sekund), więc zawsze dostaje świeże dane, np. właśnie założoną skórkę. Sesji NIE kończymy
-- przed teleportem: nieudany teleport zostawiłby gracza bez profilu.
-- Studio: z Config.COSMETICS_STUDIO_ALL profil jest tymczasowy (store.Mock) i ma wszystko; bez flagi ProfileStore sam działa na
-- danych tymczasowych, gdy Studio nie ma dostępu do API, a z dostępem pisze do prawdziwych profili.
-- (Dla TS: repozytorium z cache w pamięci i zdarzeniem `onLoaded`, jak EventEmitter.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Medals = require(Shared:WaitForChild("Medals"))

local PlayerProfile = {}

local STORE_NAME = "Profiles"
-- Szablon: nowe pola dopisujemy tutaj, profile:Reconcile uzupełni je u starych graczy (także w zagnieżdżonych tabelach).
PlayerProfile.TEMPLATE = {
	bestTimes = {} :: { [string]: number }, -- [riverId] = czas w sekundach
	races = 0, -- ukończone przejazdy
	wins = 0, -- wygrane z innymi
	-- 0 celowo: Reconcile dopisałby wyższy numer staremu profilowi i migracja by się nie wykonała.
	schema = 0,
	medals = {} :: { [string]: number }, -- [riverId] = 1 brąz | 2 srebro | 3 złoto, tylko rośnie
	cosmetics = {
		owned = {} :: { [string]: any }, -- [itemId] = { via = "play" | "grant", at = os.time() }
		unseen = {} :: { [string]: boolean }, -- [itemId] = true: znacznik „Nowe” w szafce
		equipped = Cosmetics.defaultEquipped(), -- [slot] = itemId, nigdy pusty slot
	},
}

local store
local profiles: { [Player]: any } = {}
local listeners: { (Player, any) -> () } = {}
local started = false

local function studioAll(): boolean
	return Config.COSMETICS_STUDIO_ALL == true and RunService:IsStudio()
end

-- Po Reconcile: migracja medali (raz), nagrody za gwiazdki (zawsze, idempotentnie) i naprawa założenia (zawsze).
-- Dzięki temu dopisanie przedmiotu do katalogu działa wstecz bez migracji, a uszkodzony profil daje najwyżej wygląd domyślny.
function PlayerProfile.prepare(data: any, grantAll: boolean?)
	Medals.migrate(data)
	Cosmetics.evaluate(data)
	if grantAll then
		Cosmetics.grantAll(data)
	end
	Cosmetics.sanitize(data.cosmetics.equipped, data.cosmetics.owned)
end

local function notify(player: Player, profile: any)
	for _, listener in listeners do
		task.spawn(listener, player, profile)
	end
end

local function load(player: Player)
	local source = if studioAll() then store.Mock else store
	local profile = source:StartSessionAsync("u_" .. player.UserId, {
		-- przestań próbować, gdy gracz wyszedł w trakcie wczytywania
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		if player.Parent == Players then
			notify(player, nil) -- gra działa dalej bez zapisu
		end
		return
	end
	profile:AddUserId(player.UserId) -- RODO/GDPR: powiązanie profilu z kontem
	profile:Reconcile()
	PlayerProfile.prepare(profile.Data, studioAll() or Config.COSMETICS_ALL_USERS[player.UserId] == true)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	-- Profil przejęty przez inny serwer: stąd już go nie ruszamy.
	profile.OnSessionEnd:Connect(function()
		if profiles[player] == profile then
			profiles[player] = nil
		end
	end)
	profiles[player] = profile
	notify(player, profile)
end

-- Wczytany profil albo nil (jeszcze się wczytuje, nie udało się, albo przejął go inny serwer).
function PlayerProfile.get(player: Player): any
	return profiles[player]
end

-- `listener(player, profile)` po każdym wczytaniu; profile = nil, gdy się nie udało. Rejestrować w init(), przed start().
function PlayerProfile.onLoaded(listener: (Player, any) -> ())
	table.insert(listeners, listener)
end

function PlayerProfile.start()
	if started then
		return
	end
	started = true
	-- require dopiero tutaj: sam moduł (szablon, prepare) da się wtedy sprawdzić w Lune, bez usług DataStore.
	local ProfileStore = require(script.Parent.Packages.ProfileStore) :: any
	store = ProfileStore.New(STORE_NAME, PlayerProfile.TEMPLATE)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			profile:EndSession()
		end
	end)
end

return PlayerProfile
