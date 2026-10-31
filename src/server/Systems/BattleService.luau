-- Tryb Bitwa na serwerze (ARCHITECTURE.md, „Tryb Bitwa”). Zasady są w shared/BattleRules, tutaj tylko świat i sieć: co BATTLE_TICK
-- zbieramy migawkę kajaków, karmimy nią BattleRules i rozsyłamy skutki. Fizykę skutku liczy urządzenie ofiary.
-- W trybach race i arena start() wychodzi od razu: żadnej pętli, żadnych handlerów, żadnych zdarzeń.
-- (Dla TS: kontroler nad reducerem, jak RaceService nad RaceLogic.)
--
-- Stan rundy żyje tylko w fazie racing i przepada przy wejściu w nią oraz przy wyjściu. Wszystko idzie przez userId, a migawka
-- bierze tylko graczy obecnych na serwerze, więc gracz, który wyszedł, nie jest ani celem, ani atakującym.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleRules = require(Shared:WaitForChild("BattleRules"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local KayakService = require(script.Parent.KayakService)
local RaceService = require(script.Parent.RaceService)
local RiverBuilder = require(script.Parent.RiverBuilder)

local BattleService = {}

local SHIELD_ATTRIBUTE = "BattleShield" -- atrybut kajaka: aktywna tarcza, widoczna dla wszystkich klientów

local random = Random.new()
local crates: { BattleRules.Crate } = {}
local state: BattleRules.State

local battleItem: RemoteEvent
local battleEffect: RemoteEvent
local battleCrate: RemoteEvent
local battleWorld: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function nextNumber(): number
	return random:NextNumber()
end

-- Migawka z Hull i RaceLogic: tylko zawodnicy z kajakiem, bez wyników odrzuconych jako oszustwo. Pozycję `s` liczy RaceService.
local function snapshot(): { [number]: BattleRules.Fighter }
	local fighters: { [number]: BattleRules.Fighter } = {}
	local _, racers = RaceService.snapshot()
	for id, racer in racers do
		local player = Players:GetPlayerByUserId(id)
		local kayak = player and KayakService.get(player)
		local hull = kayak and kayak.PrimaryPart
		if hull and not racer.invalid then
			local look = hull.CFrame.LookVector
			local flat = Vector2.new(look.X, look.Z)
			fighters[id] = {
				position = Vector2.new(hull.Position.X, hull.Position.Z),
				-- Kajak jest zawsze prawie poziomo, ale zerowy wektor dałby NaN w Unit.
				forward = if flat.Magnitude > 0 then flat.Unit else Vector2.xAxis,
				s = racer.lastS,
				finished = racer.time ~= nil,
			}
		end
	end
	return fighters
end

local function setShield(id: number, active: boolean)
	local player = Players:GetPlayerByUserId(id)
	local kayak = player and KayakService.get(player)
	if kayak then
		kayak:SetAttribute(SHIELD_ATTRIBUTE, if active then true else nil)
	end
end

local function sendEffects(effects: { BattleRules.Effect })
	for _, effect in effects do
		local player = Players:GetPlayerByUserId(effect.id)
		if player then
			battleEffect:FireClient(player, effect.kind, effect.time)
			if effect.kind == "stun" or effect.kind == "boost" then
				battleEffect:FireAllClients("seen", effect.kind, effect.id, effect.time) -- klient pomija własne
			end
			if effect.kind == "shieldHit" then
				setShield(effect.id, false)
			end
		end
	end
end

local function sendNet(net: BattleRules.Net, active: boolean)
	battleWorld:FireAllClients("net", net.position.X, net.position.Y, net.id, active)
end

-- Nowy stan rundy. Klient dostaje tylko to, co faktycznie się zmieniło.
local function resetRound()
	for index in state.respawnAt do
		battleCrate:FireAllClients(index, true)
	end
	for _, net in state.nets do
		sendNet(net, false)
	end
	for id, holder in state.holders do
		local player = Players:GetPlayerByUserId(id)
		if player and holder.item then
			battleItem:FireClient(player, nil)
		end
		if holder.shield then
			setShield(id, false)
		end
	end
	state = BattleRules.newState(crates)
end

local function tick(time: number)
	local fighters = snapshot()
	for _, index in BattleRules.respawn(state, time) do
		battleCrate:FireAllClients(index, true)
	end
	for _, pickup in BattleRules.collect(state, fighters, time, nextNumber) do
		battleCrate:FireAllClients(pickup.index, false)
		local player = Players:GetPlayerByUserId(pickup.id)
		if player then
			battleItem:FireClient(player, pickup.item)
		end
	end
	local sweep = BattleRules.sweepNets(state, fighters, time)
	for _, net in sweep.removed do
		sendNet(net, false)
	end
	sendEffects(sweep.effects)
end

-- Od klienta to tylko prośba bez argumentów: co ma, kogo trafia i czy może, rozstrzyga BattleRules z pozycji Hull.
-- Odmowa jest cicha i przedmiot zostaje, więc przycisk wciśnięty bez celu niczego nie zabiera.
local function onUse(player: Player)
	local phase = RaceService.snapshot()
	if phase ~= "racing" then
		return
	end
	local id = player.UserId
	local outcome = BattleRules.use(state, id, snapshot(), now())
	if outcome == nil then
		return
	end
	battleItem:FireClient(player, nil)
	if outcome.item == "shield" then
		setShield(id, true)
	end
	if outcome.net then
		sendNet(outcome.net, true)
	end
	-- Atak widzą wszyscy: strumień lub rozbryzg między strzelającym a celem.
	if outcome.item == "cannon" or outcome.item == "splash" then
		local victim = outcome.effects[1]
		battleEffect:FireAllClients("seen", outcome.item, id, victim and victim.id)
	end
	sendEffects(outcome.effects)
end

-- Gracz wszedł w trakcie: dostaje to, co odbiega od stanu początkowego.
local function sendWorldTo(player: Player)
	for index in state.respawnAt do
		battleCrate:FireClient(player, index, false)
	end
	for _, net in state.nets do
		battleWorld:FireClient(player, "net", net.position.X, net.position.Y, net.id, true)
	end
end

function BattleService.start()
	if RiverBuilder.mode ~= "battle" then
		return
	end
	battleItem = Remotes.get("BattleItem")
	battleEffect = Remotes.get("BattleEffect")
	battleCrate = Remotes.get("BattleCrate")
	battleWorld = Remotes.get("BattleWorld")
	crates = BattleRules.crates(RiverBuilder.river)
	state = BattleRules.newState(crates)
	print(`[Battle] {#crates} skrzynek na rzece {RiverBuilder.river.id}`)

	Remotes.onServer("BattleUse", 4, 6, onUse)
	Players.PlayerAdded:Connect(sendWorldTo)
	for _, player in Players:GetPlayers() do
		sendWorldTo(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		BattleRules.remove(state, player.UserId)
	end)

	local lastPhase = RaceService.snapshot()
	while true do
		task.wait(Config.BATTLE_TICK)
		local phase = RaceService.snapshot()
		if phase ~= lastPhase then
			if phase == "racing" or lastPhase == "racing" then
				resetRound()
			end
			lastPhase = phase
		end
		if phase == "racing" then
			tick(now())
		end
	end
end

return BattleService
