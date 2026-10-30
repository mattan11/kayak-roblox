-- Własne zdarzenia do Creator Dashboard (PUBLISHING.md). Działają tylko z serwera i tylko w opublikowanej grze,
-- więc wołania są w pcall: w Studio nic się nie dzieje. (Dla TS: cienka nakładka na klienta analityki.)

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Analytics = {}

local function log(player: Player, name: string, value: number)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value)
	end)
end

function Analytics.raceFinished(player: Player, time: number)
	log(player, "RaceFinished", time)
end

function Analytics.init()
	Remotes.onServer("Feedback", 1, 2, function(player, stars)
		if typeof(stars) == "number" and stars % 1 == 0 and stars >= 1 and stars <= 5 then
			log(player, "RaceRating", stars)
		end
	end)
end

return Analytics
