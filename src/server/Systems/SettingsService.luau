-- Ustawienia gracza: logika w Shared.PlayerSettings, wspólna z wioską.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))

local SettingsService = {}

function SettingsService.start()
	PlayerSettings.start()
end

return SettingsService
