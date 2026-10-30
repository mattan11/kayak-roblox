-- Powrót ze spływu do wioski (ARCHITECTURE.md, „Przejście spływ → wioska”). Do TRAVEL_TRIES prób, potem gracz zostaje tutaj.
-- Dane gracza są bezpieczne: ProfileStore zwalnia sesję przy wyjściu z serwera, więc nic nie zapisujemy ręcznie.
-- TravelNotice wysyłamy tylko wtedy, gdy podróż się NIE odbyła: HUD odblokowuje wtedy przyciski.
-- W Studio teleport nie działa, więc gracz dostaje komunikat i zostaje. (Dla TS: `fetch` z retry i powiadomieniem o porażce.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Places = require(Shared:WaitForChild("Places"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TravelService = {}

type Trip = { attempts: number, deadline: number }

-- Gracze w drodze. Po deadline wolno kliknąć znowu: Roblox czasem nie zgłasza ani sukcesu, ani błędu.
local trips: { [Player]: Trip } = {}

local onFailed: (Player) -> ()

local function attempt(player: Player)
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, Places.placeId("village"), { player })
	if not ok then
		warn(`[Travel] {player.Name}: {err}`)
		onFailed(player)
	end
end

-- Nieudana próba (błąd pcall albo TeleportInitFailed): ponowienie albo komunikat.
function onFailed(player: Player)
	local trip = trips[player]
	if trip == nil or player.Parent ~= Players then
		return
	end
	if trip.attempts >= Config.TRAVEL_TRIES then
		trips[player] = nil
		Remotes.get("TravelNotice"):FireClient(player, "travel.failed")
		return
	end
	trip.attempts += 1
	task.delay(Config.TRAVEL_RETRY_WAIT, function()
		if trips[player] == trip and player.Parent == Players then
			attempt(player)
		end
	end)
end

function TravelService.toVillage(player: Player)
	local trip = trips[player]
	if trip and os.clock() < trip.deadline then
		return
	end
	if RunService:IsStudio() then
		Remotes.get("TravelNotice"):FireClient(player, "travel.studio")
		return
	end
	trips[player] = { attempts = 1, deadline = os.clock() + Config.TRAVEL_TIMEOUT }
	attempt(player)
end

function TravelService.init()
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Travel] {player.Name}: teleport nie wystartował ({result}: {message})`)
		onFailed(player :: Player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		trips[player] = nil
	end)
end

return TravelService
