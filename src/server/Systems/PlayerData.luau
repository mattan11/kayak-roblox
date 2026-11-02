-- Dane gracza na spływie: rekord, ranking, licznik przejazdów i wygranych, medale. Wczytanie, szablon i zwolnienie sesji
-- są we wspólnym Server.PlayerProfile (ten sam profil czyta wioska); tutaj tylko to, co zmienia wyścig.
-- Profil: bestTimes[riverId] = czas w sekundach, races = ukończone przejazdy, wins = wygrane z innymi,
-- medals[riverId] = najwyższy medal (1..3, tylko rośnie), schema = wersja danych (migracja w Medals.migrate).
-- Gdy profil się nie wczyta, gracz po prostu gra bez zapisu: nie ma wtedy czym nadpisać prawdziwych danych.
-- W trybie Bitwa profil wczytujemy zwyczajnie, ale nic się nie zmienia: bez rekordu, medalu, rankingu i liczników.
-- (Dla TS: repozytorium z cache w pamięci — gra zmienia dane, a biblioteka sama je zapisuje.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Medals = require(Shared:WaitForChild("Medals"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerProfile = require(script.Parent.Parent.PlayerProfile)
local RaceLogic = require(script.Parent.Parent.RaceLogic)
local Leaderboard = require(script.Parent.Leaderboard)
local RiverBuilder = require(script.Parent.RiverBuilder)

local PlayerData = {}

local riverId: string -- ustawiane w init(), bo rzeka powstaje dopiero w RiverBuilder.init()
local personalBest = Remotes.get("PersonalBest")
local medalAwarded = Remotes.get("MedalAwarded")

-- Po wczytaniu profilu (PlayerProfile.onLoaded). nil = nie udało się: gracz gra bez zapisu.
local function onLoaded(player: Player, profile: any)
	if profile == nil or player.Parent ~= Players then
		return
	end
	-- Brak atrybutu chowa medal na ekranie wyników, tak samo jak przy niewczytanym profilu.
	if RiverBuilder.mode ~= "battle" then
		personalBest:FireClient(player, profile.Data.bestTimes[riverId], false)
		player:SetAttribute(Medals.ATTRIBUTE, profile.Data.medals[riverId] or 0)
	end
end

-- Ukończony, zaakceptowany przejazd: licznik, rekord osobisty, a przy rekordzie wpis do globalnego rankingu.
-- `time` pochodzi z RaceLogic, więc medal też: klient nie ma tu nic do powiedzenia.
-- MedalAwarded idzie tylko wtedy, gdy stopień wzrósł, a atrybut niesie stan dla ekranu wyników.
function PlayerData.recordFinish(player: Player, time: number)
	local profile = PlayerProfile.get(player)
	if not profile or RiverBuilder.mode == "battle" then
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
	local profile = PlayerProfile.get(player)
	if profile and RiverBuilder.mode ~= "battle" then
		profile.Data.wins += 1
	end
end

function PlayerData.init()
	riverId = RiverBuilder.river.id
	PlayerProfile.onLoaded(onLoaded)
end

function PlayerData.start()
	PlayerProfile.start()
end

return PlayerData
