-- Własny kajak: stan fizyki, sterowanie, cele Align, fazy wyścigu (ARCHITECTURE.md). Tylko ten moduł zapisuje do
-- Session, a kajaki z workspace.Kayaks śledzi przez ChildAdded/Removed (bez GetChildren co klatkę).
-- Kolejność w klatce (BindToRenderStep): ten moduł (fizyka) → CameraController (czyta wynik).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local KayakPhysics = require(Shared:WaitForChild("KayakPhysics"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local KayakPose = require(Client.logic.KayakPose)
local Session = require(Client.Session)
local KayakVisuals = require(script.Parent.KayakVisuals)
local PaddleInput = require(script.Parent.PaddleInput)

local KayakController = {}

local ownName = tostring(Players.LocalPlayer.UserId)
local paddleRemote: RemoteEvent = nil
local alignPosition: AlignPosition? = nil
local alignOrientation: AlignOrientation? = nil
local others: { Vector2 } = {} -- ta sama tablica co klatkę

local function addKayak(model: Instance)
	if model:IsA("Model") then
		table.insert(Session.kayaks, model)
		if model.Name == ownName then
			Session.ownModel = model
		end
	end
end

local function removeKayak(model: Instance)
	local index = table.find(Session.kayaks, model :: Model)
	if index then
		table.remove(Session.kayaks, index)
		if model == Session.ownModel then
			Session.ownModel, Session.ownHull = nil, nil
			alignPosition, alignOrientation = nil, nil
		end
		Session.emit("kayakRemoved", model)
	end
end

-- Kajak może jeszcze nie istnieć albo przyjść bez części: próbujemy co klatkę, aż wszystko będzie na miejscu.
local function resolveRig(): boolean
	if Session.ownHull then
		return true
	end
	local model = Session.ownModel
	local hull = model and model:FindFirstChild("Hull")
	if hull == nil then
		return false
	end
	local position = hull:FindFirstChildOfClass("AlignPosition")
	local orientation = hull:FindFirstChildOfClass("AlignOrientation")
	if position == nil or orientation == nil then
		return false
	end
	alignPosition, alignOrientation = position, orientation
	Session.ownHull = hull :: BasePart
	return true
end

local function send(kind: string, side: number)
	paddleRemote:FireServer(kind, side)
	Session.emit("paddle", Session.ownModel, kind, side)
end

local function updateBrace(state: any, wanted: number?)
	local current = state.brace
	if wanted ~= current then
		KayakPhysics.setBrace(state, wanted)
		if wanted then
			send("brace", wanted)
		else
			send("release", current)
		end
	end
end

local function collectOthers()
	local count = 0
	for _, model in Session.kayaks do
		local hull = model.PrimaryPart
		-- Kajak na mecie już nie płynie: nie może blokować mety kolejnym
		if model ~= Session.ownModel and hull and not model:GetAttribute("Finished") then
			count += 1
			local position = hull.Position
			others[count] = Vector2.new(position.X, position.Z)
		end
	end
	for i = #others, count + 1, -1 do
		others[i] = nil
	end
end

-- Po mecie i poza fazą racing fizyka nie działa (kontrakt), ale kajak nie staje jak wryty: wytraca prędkość.
local function glide(state: any, dt: number)
	state.strokeSide, state.queued = nil, nil
	if state.velocity.Magnitude > 0.05 then
		state.velocity *= math.exp(-Config.GLIDE_DRAG * dt)
		state.position += state.velocity * dt
	else
		state.velocity = Vector2.zero
	end
	state.spin *= math.exp(-Config.DRAG_ANGULAR * dt)
	state.heading = KayakPose.wrapAngle(state.heading + state.spin * dt)
end

-- Jezioro po starcie grupy: wiosła puszczone, kajak wytraca prędkość, ale brzeg i przeszkody dalej działają.
local function coast(state: any, dt: number)
	state.strokeSide, state.queued = nil, nil
	state.velocity *= math.exp(-Config.GLIDE_DRAG * dt)
	collectOthers()
	KayakPhysics.step(state, Session.river, others, dt)
end

-- W wiosce sterujemy zawsze, oprócz chwili między startem grupy a teleportem. Atrybut ustawia MatchService;
-- gdy teleport się nie uda, serwer go zdejmie i sterowanie wraca samo.
local function canSteer(finished: boolean): boolean
	if Session.phase == "free" then
		return Players.LocalPlayer:GetAttribute("QueueTraveling") ~= true
	end
	return Session.phase == "racing" and not finished
end

local function updateClock(state: any, finished: boolean)
	local now = workspace:GetServerTimeNow()
	local q = state.lastQuery
	-- Serwer włącza zegar na linii startu, więc na ekranie też (oficjalny wynik i tak liczy serwer)
	if Session.startedAt == nil and Session.active and q and q.s >= Config.START_LINE then
		Session.startedAt = now
	end
	if finished and Session.finishTime == nil and Session.startedAt then
		Session.finishTime = now - Session.startedAt
	end
end

local function frame(dt: number)
	local state = Session.state
	if state == nil or not resolveRig() then
		Session.active = false
		return
	end

	local model = Session.ownModel :: Model
	local finished = model:GetAttribute("Finished") == true
	Session.active = canSteer(finished)
	updateClock(state, finished)

	if Session.active then
		-- Ogłuszony nie wbija wiosła: bez tego animacja i rozbryzg szłyby mimo braku działania
		updateBrace(state, if os.clock() < state.stunUntil then nil else PaddleInput.currentBrace())
		PaddleInput.feedHeldStrokes(state)
		collectOthers()
		local started = KayakPhysics.step(state, Session.river, others, dt)
		if started then
			send("stroke", started)
		end
	else
		updateBrace(state, nil)
		if Session.phase == "free" then
			coast(state, dt)
		else
			glide(state, dt)
		end
	end

	-- lastHit czytamy tylko tutaj, a reszta dostaje zdarzenie (inaczej pierwszy czytający zabrałby je innym)
	if state.lastHit > 0 then
		Session.emit("hit", state.lastHit)
		state.lastHit = 0
	end

	-- Reszta akumulatora × prędkość: fizyka ma stały krok, a klatki nie, więc bez tego ruch lekko by szarpał
	local position = state.position + state.velocity * state.accumulator
	local pitch, roll, bob = KayakVisuals.ownPose(dt, state)
	;(alignPosition :: AlignPosition).Position = Vector3.new(position.X, state.height + Config.KAYAK_RIDE_Y + bob, position.Y)
	;(alignOrientation :: AlignOrientation).CFrame = KayakPose.cframe(0, 0, 0, state.heading, pitch - state.fallSpeed * Config.FALL_PITCH, roll)
end

local function onReset(x: number, z: number, heading: number)
	local state = KayakPhysics.new(Vector2.new(x, z), heading)
	local q = Session.river:query(state.position)
	state.hint, state.lastQuery = q.index, q -- kamera i efekty potrzebują rzeki jeszcze przed pierwszym krokiem
	Session.state = state
	Session.finishTime = nil
	if Session.phase == "racing" then
		-- Wejście w trakcie wyścigu: serwer liczy czas od własnego Reset
		local now = workspace:GetServerTimeNow()
		Session.startedAt, Session.raceBeganAt = now, now
	else
		Session.startedAt, Session.raceBeganAt = nil, nil
	end
	Session.emit("reset")
end

local function onRaceState(phase: string, endsAt: number)
	local changed = phase ~= Session.phase
	Session.phase, Session.phaseEndsAt = phase, endsAt
	if changed then
		if phase == "racing" then
			Session.raceBeganAt = workspace:GetServerTimeNow()
		end
		Session.emit("phase", phase, endsAt)
	end
end

-- Wodna bitwa: ArenaState zastępuje RaceState. Jedyny słuchacz tego zdarzenia: Roblox oddaje zdarzenia z kolejki tylko
-- pierwszemu połączeniu, więc ArenaController czyta stan z Session i zdarzenia "arenaState".
local function onArenaState(phase: any, endsAt: any, radius: any, alive: any)
	Session.arenaRadius, Session.arenaAlive = radius, alive
	if type(phase) == "string" and type(endsAt) == "number" then
		onRaceState(phase, endsAt)
	end
	Session.emit("arenaState")
end

function KayakController.start()
	paddleRemote = Remotes.get("Paddle")
	Remotes.get("Reset").OnClientEvent:Connect(onReset)
	if Session.arena then
		Remotes.get("ArenaState").OnClientEvent:Connect(onArenaState)
	else
		Remotes.get("RaceState").OnClientEvent:Connect(onRaceState)
	end

	RunService:BindToRenderStep("KayakPhysics", Enum.RenderPriority.Input.Value + 1, frame)

	-- Folder tworzy serwer; czekamy na końcu, bo to może trochę potrwać
	local folder = workspace:WaitForChild("Kayaks", math.huge)
	folder.ChildAdded:Connect(addKayak)
	folder.ChildRemoved:Connect(removeKayak)
	for _, model in folder:GetChildren() do
		addKayak(model)
	end
end

return KayakController
