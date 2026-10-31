-- Ustawienia gracza wspólne dla wioski i spływu: „realistyczne wiosłowanie”, „nauka zaliczona” i „ukryj duchy”.
-- Tylko serwer. Zapis w zwykłym DataStore, bo wioska nie używa ProfileStore, a ustawienie musi przejść na spływ.
-- Każde ustawienie ma własny klucz, więc zapis jednego nie nadpisze drugiego, a stare zapisy sterowania dalej działają.
-- Wartość trafia do atrybutu gracza, który czyta klient. Błąd zapisu lub odczytu to wartość domyślna, gra działa dalej.
-- (Dla TS: `localStorage`, tylko po stronie serwera i wspólny dla dwóch aplikacji.)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require(script.Parent.Remotes)

local PlayerSettings = {}

PlayerSettings.ATTRIBUTE = "RealisticPaddle"
PlayerSettings.TUTORIAL_ATTRIBUTE = "TutorialDone"
PlayerSettings.GHOSTS_ATTRIBUTE = "HideGhosts"
PlayerSettings.LOADED_ATTRIBUTE = "SettingsLoaded" -- odczyt się udał: brak TutorialDone naprawdę znaczy „nowy gracz”

local STORE = "PlayerSettings"

-- Nazwa z SettingAction → atrybut i przedrostek klucza. Sterowanie zostaje pod gołym userId, jak w istniejących zapisach.
local SETTINGS: { [string]: { attribute: string, prefix: string } } = {
	realistic = { attribute = PlayerSettings.ATTRIBUTE, prefix = "" },
	tutorialDone = { attribute = PlayerSettings.TUTORIAL_ATTRIBUTE, prefix = "tutorial_" },
	hideGhosts = { attribute = PlayerSettings.GHOSTS_ATTRIBUTE, prefix = "hideGhosts_" },
}

local function store(): DataStore?
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
	return if ok then result else nil
end

-- W Studio bez dostępu do API odczyt zawsze się nie uda, a nauka i tak ma się dać przetestować: stąd wyjątek na LOADED_ATTRIBUTE.
local function load(player: Player)
	local settings = store()
	local allRead = settings ~= nil
	if settings then
		for _, setting in SETTINGS do
			local ok, value = pcall(settings.GetAsync, settings, setting.prefix .. tostring(player.UserId))
			if ok and value == true and player.Parent == Players then
				player:SetAttribute(setting.attribute, true)
			elseif not ok then
				allRead = false
				if not RunService:IsStudio() then
					warn(`[Settings] odczyt: {value}`)
				end
			end
		end
	end
	if (allRead or RunService:IsStudio()) and player.Parent == Players then
		player:SetAttribute(PlayerSettings.LOADED_ATTRIBUTE, true)
	end
end

local function save(player: Player, setting: { attribute: string, prefix: string }, value: boolean)
	player:SetAttribute(setting.attribute, if value then true else nil)
	local settings = store()
	if settings then
		local ok, err = pcall(settings.SetAsync, settings, setting.prefix .. tostring(player.UserId), value)
		if not ok and not RunService:IsStudio() then
			warn(`[Settings] zapis: {err}`)
		end
	end
end

-- Woła jeden system w każdym miejscu.
function PlayerSettings.start()
	Remotes.onServer("SettingAction", 1, 2, function(player, name, value)
		local setting = if type(name) == "string" then SETTINGS[name] else nil
		if setting and type(value) == "boolean" then
			save(player, setting, value)
		end
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return PlayerSettings
