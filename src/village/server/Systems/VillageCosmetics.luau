-- Szafka po stronie serwera wioski: profil gracza (wspólny PlayerProfile), stan dla okna i zakładanie wyglądu.
-- Klient tylko prosi: ("sync"), ("equip", slot, itemId), ("seen", slot). Odblokowań nie da się poprosić: nadaje je wyłącznie
-- Cosmetics.evaluate z medali w profilu. Błędne prośby przepadają po cichu (oszust nie dostaje odpowiedzi).
-- Strefy szafki tu nie sprawdzamy celowo: gracz może założyć tylko to, co ma, więc nic by to nie chroniło (COSMETICS.md, sekcja 9).
-- Po założeniu kajak w wiosce od razu zmienia wygląd, a profil zapisze się sam (ProfileStore) i spływ przeczyta to po teleporcie.
-- (Dla TS: kontroler REST z walidacją wejścia i jednym źródłem prawdy w bazie.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerProfile = require(script.Parent.Parent.PlayerProfile)
local KayakService = require(script.Parent.Parent.KayakService)

local VillageCosmetics = {}

local failed: { [Player]: boolean } = {} -- profil się nie wczytał: szafka mówi o tym zamiast wiecznie „wczytywać”

-- Stan okna szafki. `owned` jako zbiór id (bez dat), bo klient potrzebuje tylko „mam / nie mam”.
local function sendState(player: Player)
	local profile = PlayerProfile.get(player)
	if profile == nil then
		Remotes.get("CosmeticState"):FireClient(player, { ready = false, failed = failed[player] == true })
		return
	end
	local data = profile.Data
	local owned = {}
	for id in data.cosmetics.owned do
		owned[id] = true
	end
	Remotes.get("CosmeticState"):FireClient(player, {
		ready = true,
		failed = false,
		owned = owned,
		equipped = data.cosmetics.equipped,
		unseen = data.cosmetics.unseen,
		stars = Cosmetics.stars(data.medals),
		maxStars = Cosmetics.maxStars(),
	})
end

local function applyLook(player: Player, data: any)
	KayakService.setLook(player, Cosmetics.look(data.cosmetics.equipped, player.UserId))
end

local function equip(player: Player, slot: any, itemId: any)
	local profile = PlayerProfile.get(player)
	if profile == nil then
		return
	end
	local cosmetics = profile.Data.cosmetics
	if not Cosmetics.canEquip(slot, itemId, cosmetics.owned) or cosmetics.equipped[slot] == itemId then
		return
	end
	cosmetics.equipped[slot] = itemId
	cosmetics.unseen[itemId] = nil
	applyLook(player, profile.Data)
	sendState(player)
end

-- Czyści znaczniki „Nowe” jednego slotu.
local function seen(player: Player, slot: any)
	local profile = PlayerProfile.get(player)
	if profile == nil or type(slot) ~= "string" then
		return
	end
	local unseen = profile.Data.cosmetics.unseen
	local changed = false
	for id in unseen do
		local item = Cosmetics.item(id)
		if item == nil or item.slot == slot then
			unseen[id] = nil -- nieznane id (usunięte z katalogu) też sprzątamy
			changed = true
		end
	end
	if changed then
		sendState(player)
	end
end

function VillageCosmetics.init()
	PlayerProfile.onLoaded(function(player: Player, profile: any)
		if profile == nil then
			failed[player] = true
		else
			applyLook(player, profile.Data)
		end
		sendState(player)
	end)

	Remotes.onServer("CosmeticAction", Config.COSMETIC_ACTION_RATE, Config.COSMETIC_ACTION_BURST, function(player: Player, action: any, slot: any, itemId: any)
		if action == "sync" then
			sendState(player)
		elseif action == "equip" then
			equip(player, slot, itemId)
		elseif action == "seen" then
			seen(player, slot)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		failed[player] = nil
	end)
end

function VillageCosmetics.start()
	PlayerProfile.start()
end

return VillageCosmetics
