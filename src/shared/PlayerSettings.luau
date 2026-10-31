-- Ustawienia gracza wspólne dla wioski i spływu: na razie tylko „realistyczne wiosłowanie”.
-- Tylko serwer. Zapis w zwykłym DataStore, bo wioska nie używa ProfileStore, a ustawienie musi przejść na spływ.
-- Wartość trafia do atrybutu gracza, który czyta klient. Błąd zapisu lub odczytu to domyślne sterowanie, gra działa dalej.
-- (Dla TS: `localStorage`, tylko po stronie serwera i wspólny dla dwóch aplikacji.)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Remotes)

local PlayerSettings = {}

PlayerSettings.ATTRIBUTE = "RealisticPaddle"

local STORE = "PlayerSettings"

local function store(): DataStore?
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
	return if ok then result else nil
end

local function load(player: Player)
	local settings = store()
	if settings == nil then
		return
	end
	local ok, value = pcall(settings.GetAsync, settings, tostring(player.UserId))
	if ok and value == true and player.Parent == Players then
		player:SetAttribute(PlayerSettings.ATTRIBUTE, true)
	elseif not ok and not RunService:IsStudio() then
		warn(`[Settings] odczyt: {value}`)
	end
end

local function save(player: Player, realistic: boolean)
	player:SetAttribute(PlayerSettings.ATTRIBUTE, if realistic then true else nil)
	local settings = store()
	if settings then
		local ok, err = pcall(settings.SetAsync, settings, tostring(player.UserId), realistic)
		if not ok and not RunService:IsStudio() then
			warn(`[Settings] zapis: {err}`)
		end
	end
end

-- Woła jeden system w każdym miejscu.
function PlayerSettings.start()
	Remotes.onServer("SettingAction", 1, 2, function(player, name, value)
		if name == "realistic" and type(value) == "boolean" then
			save(player, value)
		end
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return PlayerSettings
