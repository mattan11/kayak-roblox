-- Dane gracza na koncie przez ProfileStore (blokada sesji, autozapis, zwolnienie przy wyjściu).
-- Profil: bestTimes[riverId] = czas w sekundach, races = ukończone przejazdy, wins = wygrane z innymi,
-- medals[riverId] = najwyższy medal (1..3, tylko rośnie), schema = wersja danych (migracja w Medals.migrate).
-- W Studio bez dostępu do API ProfileStore sam działa na danych tymczasowych, więc nic tu tego nie obsługuje.
-- Gdy profil się nie wczyta, gracz po prostu gra bez zapisu: nie ma wtedy czym nadpisać prawdziwych danych.
-- (Dla TS: repozytorium z cache w pamięci — gra zmienia dane, a biblioteka sama je zapisuje.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Medals = require(Shared:WaitForChild("Medals"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local RaceLogic = require(script.Parent.Parent.RaceLogic)
local Leaderboard = require(script.Parent.Leaderboard)
local RiverBuilder = require(script.Parent.RiverBuilder)

local PlayerData = {}

local STORE_NAME = "Profiles"
-- Szablon: nowe pola dopisujemy tutaj, profile:Reconcile uzupełni je u starych graczy.
local TEMPLATE = {
	bestTimes = {} :: { [string]: number },
	races = 0,
	wins = 0,
	-- 0 celowo: Reconcile dopisałby wyższy numer staremu profilowi i migracja by się nie wykonała.
	schema = 0,
	medals = {} :: { [string]: number },
}

local riverId: string -- ustawiane w init(), bo rzeka powstaje dopiero w RiverBuilder.init()
local personalBest = Remotes.get("PersonalBest")
local medalAwarded = Remotes.get("MedalAwarded")
local store
local profiles: { [Player]: any } = {}

local function load(player: Player)
	local profile = store:StartSessionAsync("u_" .. player.UserId, {
		-- przestań próbować, gdy gracz wyszedł w trakcie wczytywania
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		return
	end
	profile:AddUserId(player.UserId) -- RODO/GDPR: powiązanie profilu z kontem
	profile:Reconcile()
	Medals.migrate(profile.Data)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	-- Profil przejęty przez inny serwer: stąd już go nie ruszamy.
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
	end)
	profiles[player] = profile
	personalBest:FireClient(player, profile.Data.bestTimes[riverId], false)
	player:SetAttribute(Medals.ATTRIBUTE, profile.Data.medals[riverId] or 0)
end

-- Ukończony, zaakceptowany przejazd: licznik, rekord osobisty, a przy rekordzie wpis do globalnego rankingu.
-- `time` pochodzi z RaceLogic, więc medal też: klient nie ma tu nic do powiedzenia.
-- MedalAwarded idzie tylko wtedy, gdy stopień wzrósł, a atrybut niesie stan dla ekranu wyników.
function PlayerData.recordFinish(player: Player, time: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	local data = profile.Data
	data.races += 1
	local isNew = RaceLogic.isRecord(data.bestTimes[riverId], time)
	if isNew then
		data.bestTimes[riverId] = time
		task.spawn(Leaderboard.submit, player.UserId, time)
	end
	personalBest:FireClient(player, data.bestTimes[riverId], isNew)
	local rank, raised = Medals.award(data.medals, riverId, time)
	if raised then
		player:SetAttribute(Medals.ATTRIBUTE, rank)
		medalAwarded:FireClient(player, riverId, rank)
	end
end

function PlayerData.addWin(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Data.wins += 1
	end
end

function PlayerData.init()
	riverId = RiverBuilder.river.id
	store = ProfileStore.New(STORE_NAME, TEMPLATE)
end

function PlayerData.start()
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

return PlayerData
