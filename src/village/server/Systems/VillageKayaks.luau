-- Kajaki w wiosce: gracz od razu siedzi na jeziorze, bez chodzenia i bez wyścigu.
-- Ten sam KayakService co na spływie (Server.KayakService w village.project.json), tu tylko decyzja, gdzie go postawić.
-- Respawn załatwia pętla KayakService: nowa postać wraca do kajaka tam, gdzie akurat płynie, więc fizyka klienta nie
-- dostaje drugiego Reset. Wyjście z gry też: KayakService usuwa kajak w PlayerRemoving.
-- (Dla TS: cienki adapter nad wspólnym serwisem.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Lake = require(Shared:WaitForChild("Lake"))
local LakeLayout = require(Shared:WaitForChild("content"):WaitForChild("LakeLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local KayakService = require(script.Parent.Parent.KayakService)

local VillageKayaks = {}

local lake = Lake.new(LakeLayout)
local joined = 0 -- licznik wejść na serwer: numer miejsca w punkcie startu

local function launch(player: Player)
	if KayakService.get(player) then
		return
	end
	joined += 1
	local position = lake:spawnPoint(joined)
	KayakService.place(player, position, lake.heading)
	Remotes.get("Reset"):FireClient(player, position.X, position.Y, lake.heading)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		launch(player)
	end)
	if player.Character then
		launch(player)
	end
end

function VillageKayaks.init()
	KayakService.init()
end

function VillageKayaks.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	KayakService.start() -- pętla pilnująca, nigdy nie wraca
end

return VillageKayaks
