-- Dane gracza na koncie przez ProfileStore (blokada sesji, autozapis, zwolnienie przy wyjściu).
-- Profil: bestTimes[riverId] = czas w sekundach, races = ukończone przejazdy, wins = wygrane z innymi.
-- W Studio bez dostępu do API ProfileStore sam działa na danych tymczasowych, więc nic tu tego nie obsługuje.
-- Gdy profil się nie wczyta, gracz po prostu gra bez zapisu: nie ma wtedy czym nadpisać prawdziwych danych.
-- (Dla TS: repozytorium z cache w pamięci — gra zmienia dane, a biblioteka sama je zapisuje.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

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
}

local riverId: string -- ustawiane w init(), bo rzeka powstaje dopiero w RiverBuilder.init()
local personalBest = Remotes.get("PersonalBest")
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
end

-- Ukończony, zaakceptowany przejazd: licznik, rekord osobisty, a przy rekordzie wpis do globalnego rankingu.
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
