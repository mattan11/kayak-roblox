-- Wygląd kajaka na spływie: po wczytaniu profilu zakłada to, co gracz wybrał w szafce w wiosce (COSMETICS.md, sekcja 6).
-- Spływ tylko czyta `equipped`, niczego nie zmienia. Kajak stoi od razu z wyglądem domyślnym (`enroll` nie czeka na profil),
-- a skórka dochodzi po wczytaniu, zwykle w czasie zbierania grupy. Spóźniony profil zmienia tylko wygląd, nigdy czas.
-- Brak profilu = wygląd domyślny. Brak szablonu skórki = klasyk (KayakBody).
-- (Dla TS: subskrybent zdarzenia `profileLoaded`, który woła jeden setter.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Cosmetics"))

local PlayerProfile = require(script.Parent.Parent.PlayerProfile)
local KayakService = require(script.Parent.KayakService)

local LookService = {}

function LookService.init()
	PlayerProfile.onLoaded(function(player: Player, profile: any)
		if profile then
			KayakService.setLook(player, Cosmetics.look(profile.Data.cosmetics.equipped, player.UserId))
		end
	end)
end

return LookService
