-- Wodna bitwa po stronie klienta (ARCHITECTURE.md, sekcje „Strefy na jeziorze i Wodna bitwa” i „Walka w Wodnej bitwie 2.0”):
-- przycisk strumienia z paskiem zbiornika, pasek wytrzymałości, licznik żywych, strumienie wody, znacznik celu, pierścień
-- strefy i widok odpadnięcia. Zwycięzcę pokazuje tytuł panelu wyników w HudController.
-- Działa tylko, gdy workspace.RaceMode == "arena"; w innych trybach nie tworzy niczego i nie ma żadnych połączeń.
-- Klient tylko rysuje i otwiera lub zamyka strumień (ArenaFire(true/false)), jak mousedown i mouseup w TS. Zbiornik, cel,
-- obrażenia i odepchnięcie liczy serwer. Znacznik celu to lokalna podpowiedź, ostatnie słowo należy do serwera.
-- Fazę, promień strefy i liczbę żywych zapisuje do Session KayakController, a tu przychodzą zdarzeniami "phase" i "arenaState".
--
-- Telefon: strumienie to gotowa pula Beamów, a pierścień to stała lista paneli (dla TS: object pool, bez new w trakcie gry).
-- Pętla klatki istnieje tylko wtedy, gdy leci strumień, i sama się odpina (dla TS: requestAnimationFrame, który się nie
-- odnawia). Znacznik celu odświeża się 10 razy na sekundę, a strefa i ostrzeżenie 5 razy, tylko w trakcie walki.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArenaLayout = require(Shared:WaitForChild("content"):WaitForChild("ArenaLayout"))
local ArenaRules = require(Shared:WaitForChild("ArenaRules"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local Session = require(Client.Session)
local Texts = require(Client.ui.Texts).arena

local ArenaController = {}

local WATER_COLOR = Color3.fromRGB(70, 190, 225)
local RING_COLOR = Color3.fromRGB(60, 170, 255)
local WARN_COLOR = Color3.fromRGB(255, 170, 50) -- ostrzeżenie: bursztyn, tryb jest bez krwi i bez czerwieni
local ACCENT_COLOR = Color3.fromRGB(255, 196, 70)
local TEXT_COLOR = Color3.fromRGB(245, 248, 250)
local PANEL_COLOR = Color3.fromRGB(16, 34, 48)
local TRACK_COLOR = Color3.fromRGB(10, 22, 32)
local SPRAY_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- wbudowana w klienta, bez uploadu

-- Zasady są u serwera; ta liczba służy tylko do wyglądu paska.
local MAX_HEALTH = Config.ARENA_HEALTH or 100

-- Wygląd (tylko klient, bez wpływu na zasady).
local JET_POOL = 8 -- po jednym na gracza, bo jeden gracz ma najwyżej jeden strumień
local JET_HOLD = Config.ARENA_HIT_INTERVAL + 0.15 -- strumień gaśnie tyle s po ostatnim ArenaHit; musi być dłuższe niż odstęp między nimi
local JET_REACH = 40 -- pudło: strumień leci tyle przed dziób
local HIT_SPRAY = 12 -- rozbryzg przy każdym ArenaHit w cel
local PUSH_SPRAY = 10 -- rozbryzg przy odepchnięciu własnego kajaka
local HIT_FEEL_GAP = 0.4 -- strumień trafia wiele razy na sekundę, a błysk i drżenie nie mogą migać w tym tempie
local RING_SEGMENTS = 36
local RING_HEIGHT = 16
local RING_THICKNESS = 0.6
local RING_Y = 6 -- środek panelu nad lustrem wody
local RING_OVERLAP = 1.03 -- panele lekko na siebie zachodzą, bez szpar
local AIM_TICK = 0.1
local ZONE_TICK = 0.2
local ZONE_MIN_STEP = 0.05 -- mniejszej zmiany promienia nie warto rysować
local ZONE_MAX_RATE = 10 -- studs/s; zabezpieczenie przed dwoma stanami tuż po sobie
local ZONE_MIN_GAP = 0.2 -- krótszy odstęp między stanami nie mówi nic o tempie
local ZONE_PREDICT = 1.5 -- tyle s dalej zwężamy sami, gdy kolejny stan się spóźnia
local BUTTON_SIZE = 124
local BUTTON_X, BUTTON_Y = 0.78, 0.7 -- to samo miejsce co przycisk przedmiotu w Bitwie
local TANK_BAR_HEIGHT = 12
local TANK_BAR_GAP = 8 -- odstęp paska zbiornika od przycisku
local TANK_LOW = 0.25
local TANK_EMPTY = 0.02 -- od tego poziomu w dół przycisk pokazuje „PUSTO”
local TANK_READY = 0.1 -- „PUSTO” znika dopiero tutaj: inaczej przy trzymaniu napis i strumień migałyby co odczyt zbiornika
local AIM_HEIGHT = 5 -- znacznik celu nad kajakiem
local LOW_HEALTH = 0.3
local TOAST_TIME = 1.6
local OUT_TOAST_TIME = 3
local FLASH_TRANSPARENCY = 0.78
local BAR_TWEEN = TweenInfo.new(0.2)
local TANK_TWEEN = TweenInfo.new(Config.ARENA_TANK_INTERVAL, Enum.EasingStyle.Linear) -- między odczytami pasek płynie sam
local HOLD_RESEND = 0.5 -- przy trzymaniu tak często ponawiamy ArenaFire(true); limit serwera to 10 na sekundę
local PRESS_SCALE = 0.9 -- wciśnięty przycisk jest mniejszy przez cały czas trzymania
local PRESS_POP = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local KEYS = { [Enum.KeyCode.F] = true, [Enum.KeyCode.ButtonX] = true }

type Jet = { beam: Beam, start: Attachment, finish: Attachment, from: BasePart?, to: BasePart?, endsAt: number }

local player = Players.LocalPlayer
local ownId = player.UserId
local center: Vector2 = Session.river.center or Vector2.zero

local fireRemote: RemoteEvent = nil
local folder: Folder = nil
local gui: ScreenGui = nil
local scales: { UIScale } = {}

local jets: { Jet } = {}
local frameConnection: RBXScriptConnection? = nil
local spray: ParticleEmitter = nil
local sprayAttachment: Attachment = nil

local ringParts: { BasePart } = {}
local ringFrames: { CFrame } = {}
local ringAngles: { { cos: number, sin: number, turn: CFrame } } = {}
local ringColor = RING_COLOR
local shownRadius: number? = nil

local statusGroup: Frame = nil
local healthFill: Frame = nil
local healthLabel: TextLabel = nil
local aliveLabel: TextLabel = nil
local fireButton: TextButton = nil
local fireStroke: UIStroke = nil
local fireCaption: TextLabel = nil
local emptyCover: Frame = nil
local tankFill: Frame = nil
local pressScale: UIScale = nil
local aimMarker: BillboardGui = nil
local toastLabel: TextLabel = nil
local warningLabel: TextLabel = nil
local warningPulse: Tween = nil
local warningTint: Frame = nil
local watchLabel: TextLabel = nil
local flash: Frame = nil

local eliminated = false
local warned = false
local zoneTicking = false
local tankEmpty = false
local aimed: BasePart? = nil -- kadłub pod znacznikiem celu
local holdInput: InputObject? = nil -- palec lub klawisz trzymający strumień; nil = strumień zamknięty
local resendAt = 0 -- os.clock(), kiedy ponowić ArenaFire(true) przy trzymaniu
local feelAt = 0 -- os.clock(), od kiedy wolno znowu dać błysk i drżenie
local toastToken = 0

local zoneRadius: number? = nil -- ostatni promień od serwera
local zoneAt = 0 -- os.clock() tego stanu
local zoneRate = 0 -- studs/s, zmierzone z dwóch ostatnich stanów

local dropStuckHold: () -> () -- deklaracja wyprzedzająca (dla TS: hoisting), treść w sekcji interfejsu

-- Pomocnicze ----------------------------------------------------------------------------------------------------------------

local function newPart(size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = "ArenaFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Size = size
	return part
end

-- Wszystko oprócz przycisku strzału przepuszcza dotyk do wiosła.
local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local item: any = Instance.new(class)
	if item:IsA("GuiObject") then
		item.BorderSizePixel = 0
		item.Active = false
	end
	for key, value in props do
		item[key] = value
	end
	item.Parent = parent
	return item
end

local function label(props: { [string]: any }, parent: Instance): TextLabel
	local item: any = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = TEXT_COLOR,
		TextStrokeColor3 = PANEL_COLOR,
		TextStrokeTransparency = 0.25,
		Text = "",
	}, parent)
	for key, value in props do
		item[key] = value
	end
	return item
end

local function corner(parent: Instance, radius: UDim)
	make("UICorner", { CornerRadius = radius }, parent)
end

local function group(name: string, anchor: Vector2, position: UDim2, size: UDim2): Frame
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
	}, gui)
	table.insert(scales, make("UIScale", {}, frame))
	return frame
end

local function hullOf(userId: any): BasePart?
	local name = tostring(userId)
	for _, model in Session.kayaks do
		if model.Name == name then
			return model.PrimaryPart
		end
	end
	return nil
end

local function burst(position: Vector3, count: number)
	local camera = workspace.CurrentCamera
	if camera and (position - camera.CFrame.Position).Magnitude <= Config.FX_RADIUS then
		sprayAttachment.WorldPosition = position
		spray:Emit(count)
	end
end

-- Strumienie wody -----------------------------------------------------------------------------------------------------------

local function jetTarget(jet: Jet, from: BasePart): Vector3
	local to = jet.to
	if to and to.Parent then
		return to.Position
	end
	return from.Position + from.CFrame.LookVector * JET_REACH
end

local function stopJet(jet: Jet)
	jet.endsAt, jet.from, jet.to = 0, nil, nil
	jet.beam.Enabled = false
end

-- Oba kajaki płyną dalej, więc co klatkę pilnujemy końców strumienia, aż przestanie go podtrzymywać ArenaHit.
local function updateJet(jet: Jet, now: number)
	local from = jet.from
	if from == nil or from.Parent == nil or now >= jet.endsAt then
		stopJet(jet)
		return
	end
	jet.start.WorldPosition = from.Position + from.CFrame.LookVector * 3
	jet.finish.WorldPosition = jetTarget(jet, from)
end

local function onFrame()
	local now = os.clock()
	local flying = false
	for _, jet in jets do
		if jet.endsAt > 0 then
			updateJet(jet, now)
			flying = flying or jet.endsAt > 0
		end
	end
	if not flying and frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

-- Każdy ArenaHit przedłuża strumień tego strzelca (dla TS: debounce, który gasi efekt, gdy zdarzenia przestają przychodzić).
-- Klucz to kadłub strzelca, więc jeden gracz nigdy nie zajmuje dwóch Beamów, a zmiana celu tylko przestawia koniec.
local function showJet(from: BasePart, to: BasePart?)
	local free: Jet? = nil
	for _, jet in jets do
		if jet.from == from then
			jet.to = to
			jet.endsAt = os.clock() + JET_HOLD
			return
		end
		if free == nil and jet.endsAt == 0 then
			free = jet
		end
	end
	if free then
		free.from, free.to = from, to
		free.endsAt = os.clock() + JET_HOLD
		free.start.WorldPosition = from.Position + from.CFrame.LookVector * 3
		free.finish.WorldPosition = jetTarget(free, from)
		free.beam.Enabled = true
		if frameConnection == nil then
			frameConnection = RunService.Heartbeat:Connect(onFrame)
		end
	end
end

local function stopAllJets()
	for _, jet in jets do
		stopJet(jet)
	end
end

-- Pierścień strefy ----------------------------------------------------------------------------------------------------------
-- Części są wysokie i świecące: z niskiej kamery na telefonie płaski okrąg na wodzie byłby kreską. Promień zmienia się tylko
-- przez stany z serwera, więc gdy strefa stoi, nie liczymy niczego (wczesny return w setRing).

local function setRingColor(color: Color3)
	if color ~= ringColor then
		ringColor = color
		for _, part in ringParts do
			part.Color = color
		end
	end
end

local function setRing(radius: number)
	if shownRadius and math.abs(radius - shownRadius) < ZONE_MIN_STEP then
		return
	end
	if shownRadius == nil then
		for _, part in ringParts do
			part.Parent = folder
		end
	end
	shownRadius = radius
	local chord = 2 * radius * math.sin(math.pi / RING_SEGMENTS) * RING_OVERLAP
	local size = Vector3.new(RING_THICKNESS, RING_HEIGHT, chord)
	for i, part in ringParts do
		local angle = ringAngles[i]
		part.Size = size
		ringFrames[i] = CFrame.new(center.X + angle.cos * radius, RING_Y, center.Y + angle.sin * radius) * angle.turn
	end
	workspace:BulkMoveTo(ringParts, ringFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Serwer przysyła stany rzadziej niż klatki, więc promień przewidujemy z tempa z dwóch ostatnich stanów.
-- Przewidywanie ma limit: gdy strefa dojdzie do końca, następny stan ustawi tempo z powrotem na 0.
local function predictedRadius(now: number): number?
	local radius = zoneRadius
	if radius == nil then
		return nil
	end
	return math.max(radius - zoneRate * math.min(now - zoneAt, ZONE_PREDICT), 0)
end

local function setWarning(shown: boolean)
	if shown == warned then
		return
	end
	warned = shown
	warningLabel.Visible = shown
	warningTint.Visible = shown
	setRingColor(if shown then WARN_COLOR else RING_COLOR)
	if shown then
		warningPulse:Play()
	else
		warningPulse:Cancel()
		warningLabel.TextTransparency = 0
	end
end

local function zoneTick()
	local radius = predictedRadius(os.clock())
	if radius == nil then
		return
	end
	setRing(radius)
	local hull = Session.ownHull
	local outside = false
	if hull and not eliminated then
		local position = hull.Position
		outside = (Vector2.new(position.X, position.Z) - center).Magnitude > radius
	end
	setWarning(outside)
end

-- Znacznik celu ------------------------------------------------------------------------------------------------------------
-- Tylko dla czytelności: pokazuje, kogo strumień prawdopodobnie trafi. Serwer liczy cel sam, z pozycji Hull.

local function canFire(): boolean
	return Session.phase == "racing" and not eliminated and Session.state ~= nil
end

local function setAim(target: BasePart?)
	if target ~= aimed then
		aimed = target
		aimMarker.Adornee = target
		aimMarker.Enabled = target ~= nil
	end
end

-- Czy strumień do tego punktu przejdzie? Przeszkody i test odcinka z kołem te same, co na serwerze.
local function shielded(from: Vector2, to: Vector2): boolean
	for _, obstacle in ArenaLayout.obstacles do
		if ArenaRules.segmentHitsCircle(from, to, obstacle.position, obstacle.radius) then
			return true
		end
	end
	return false
end

-- Najbliższy żywy gracz w stożku przed dziobem, nieosłonięty. Te same progi co ArenaRules.pickTarget, ale bez jego `match`
-- (dla TS: selektor na danych z ekranu, bo stan rundy zna tylko serwer); odpadnięci mają atrybut Finished.
local function findTarget(): BasePart?
	local own = Session.ownHull
	if own == nil then
		return nil
	end
	local look = own.CFrame.LookVector
	local forward = Vector2.new(look.X, look.Z)
	if forward.Magnitude == 0 then
		return nil
	end
	forward = forward.Unit
	local origin = Vector2.new(own.Position.X, own.Position.Z)
	local best: BasePart? = nil
	local bestDistance = Config.ARENA_CANNON_RANGE
	for _, model in Session.kayaks do
		local hull = model.PrimaryPart
		if hull and hull ~= own and not model:GetAttribute("Finished") then
			local position = Vector2.new(hull.Position.X, hull.Position.Z)
			local offset = position - origin
			local distance = offset.Magnitude
			if distance <= bestDistance and distance > 0 and offset.Unit:Dot(forward) >= Config.ARENA_CANNON_ARC_COS and not shielded(origin, position) then
				best, bestDistance = hull, distance
			end
		end
	end
	return best
end

-- Wspólna pętla rundy: znacznik co AIM_TICK, strefa co ZONE_TICK. Żyje tylko w fazie racing.
local function startRoundTicks()
	if zoneTicking then
		return
	end
	zoneTicking = true
	task.spawn(function()
		local zoneDue = 0
		while Session.phase == "racing" do
			dropStuckHold()
			setAim(if canFire() then findTarget() else nil)
			-- ArenaHit idzie tylko przy trafieniu, a gracz ma widzieć wodę także wtedy, gdy strzela w pustkę.
			local own = Session.ownHull
			if holdInput and own and not tankEmpty then
				showJet(own, aimed)
			end
			local now = os.clock()
			-- Serwer gasi strumień przy pustym zbiorniku i sam go nie otwiera, a ArenaTank jest kanałem zawodnym, więc jeden
			-- komunikat „woda wróciła” mógłby przepaść. Dlatego trzymany przycisk prosi cyklicznie (dla TS: retry zamiast jednego
			-- fetch). Przy „PUSTO” milczymy, żeby nie robić krótkich zrywów strumienia z resztek wody.
			if holdInput and not tankEmpty and now >= resendAt then
				resendAt = now + HOLD_RESEND
				fireRemote:FireServer(true)
			end
			if now >= zoneDue then
				zoneDue = now + ZONE_TICK
				zoneTick()
			end
			task.wait(AIM_TICK)
		end
		zoneTicking = false
		setWarning(false)
		setAim(nil)
	end)
end

-- Odpowiednik reduktora dla jednego stanu z serwera: pamiętamy promień i liczymy tempo zwężania.
local function onZone(radius: any)
	if type(radius) ~= "number" then
		return
	end
	local now = os.clock()
	local last = zoneRadius
	local gap = now - zoneAt
	if last and radius == last and gap < ZONE_MIN_GAP then
		return -- drugi stan tuż po pierwszym (np. zmiana fazy): nic nowego
	end
	if last and Session.phase == "racing" and radius < last then
		zoneRate = math.min((last - radius) / math.max(gap, ZONE_MIN_GAP), ZONE_MAX_RATE)
	else
		zoneRate = 0
	end
	zoneRadius, zoneAt = radius, now
	setRing(radius)
end

-- Interfejs -----------------------------------------------------------------------------------------------------------------

local function hideToast()
	toastToken += 1
	toastLabel.Visible = false
end

local function showToast(text: string, duration: number)
	if Session.phase == "results" then
		return -- panel wyników już mówi, kto na którym miejscu; napis nie może na niego nachodzić
	end
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(duration, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local function flashScreen()
	flash.BackgroundTransparency = FLASH_TRANSPARENCY
	flash.Visible = true
	local tween = TweenService:Create(flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			flash.Visible = false
		end
	end)
	tween:Play()
end

local function setHealth(health: number)
	local share = math.clamp(health / MAX_HEALTH, 0, 1)
	healthLabel.Text = string.format(Texts.health, math.max(math.ceil(health), 0))
	healthFill.BackgroundColor3 = if share <= LOW_HEALTH then WARN_COLOR else WATER_COLOR
	TweenService:Create(healthFill, BAR_TWEEN, { Size = UDim2.fromScale(share, 1) }):Play()
end

local function setTank(value: number)
	local share = math.clamp(value, 0, 1)
	TweenService:Create(tankFill, TANK_TWEEN, { Size = UDim2.fromScale(share, 1) }):Play()
	tankFill.BackgroundColor3 = if share <= TANK_LOW then WARN_COLOR else WATER_COLOR
	local empty = if tankEmpty then share < TANK_READY else share <= TANK_EMPTY
	if empty ~= tankEmpty then
		tankEmpty = empty
		emptyCover.Visible = empty
		fireCaption.Text = if empty then Texts.empty else Texts.fire
		fireCaption.TextColor3 = if empty then WARN_COLOR else WATER_COLOR
		fireStroke.Color = if empty then WARN_COLOR else WATER_COLOR
		if not empty then
			resendAt = 0 -- woda wróciła: trzymany przycisk poprosi o strumień w najbliższym obiegu pętli rundy
		end
	end
end

-- Wciśnięcie otwiera strumień, puszczenie zamyka. Zbiornika tu nie sprawdzamy: decyduje serwer.
local function beginHold(input: InputObject)
	if holdInput ~= nil or not canFire() then
		return
	end
	holdInput = input
	resendAt = os.clock() + HOLD_RESEND
	fireRemote:FireServer(true)
	pressScale.Scale = PRESS_SCALE
end

local function stopHold()
	if holdInput == nil then
		return
	end
	holdInput = nil
	fireRemote:FireServer(false)
	TweenService:Create(pressScale, PRESS_POP, { Scale = 1 }):Play()
end

-- Bezpiecznik: systemowy gest przerywa dotyk i InputEnded może nie przyjść. Bez tego strumień lałby się do końca zbiornika,
-- a kolejne wciśnięcia nic by nie dawały, bo holdInput jest zajęty. Klawisz po puszczeniu może mieć inny InputObject,
-- a jego koniec trzymania wykrywa endsHold.
dropStuckHold = function()
	local held = holdInput
	if held and (held.UserInputState == Enum.UserInputState.End or held.UserInputState == Enum.UserInputState.Cancel) then
		stopHold()
	end
end

-- Dotyk rozpoznajemy po obiekcie (dla TS: pointerId), a mysz i klawisz po rodzaju, bo ich InputObject może być inny.
local function endsHold(input: InputObject): boolean
	local held = holdInput
	if held == nil then
		return false
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		return input == held
	end
	return input.UserInputType == held.UserInputType and input.KeyCode == held.KeyCode
end

-- Ukryty przycisk nie przechwytuje dotyku, więc pole pod nim jest zwykłym polem wiosła.
local function updateView()
	local shown = canFire()
	fireButton.Visible = shown
	fireButton.Active = shown
	if not shown then
		stopHold()
		setAim(nil)
	end
	statusGroup.Visible = Session.phase ~= "results"
	watchLabel.Visible = eliminated and Session.phase == "racing"
end

local function resetRound()
	eliminated = false
	setTank(1)
	setHealth(MAX_HEALTH)
	stopAllJets()
	updateView()
end

local function onHealth(health: any)
	if type(health) == "number" then
		setHealth(health)
	end
end

-- Wspólne dla trafienia i odepchnięcia: ta sama droga co uderzenie w skałę, KayakController odda to rozbryzgowi, dźwiękowi
-- i drżeniu kamery. Throttle jak w TS: najwyżej raz na HIT_FEEL_GAP, bo strumień trafia wiele razy na sekundę.
local function feelHit()
	local now = os.clock()
	if now < feelAt then
		return
	end
	feelAt = now + HIT_FEEL_GAP
	local state = Session.state
	if state then
		state.lastHit = math.max(state.lastHit, Config.HIT_FULL_STRENGTH * 0.35)
	end
	flashScreen()
end

local function onHit(shooterId: any, targetId: any)
	local from = hullOf(shooterId)
	local to = if targetId ~= nil then hullOf(targetId) else nil
	if from then
		showJet(from, to)
	end
	if to then
		burst(to.Position, HIT_SPRAY)
	end
	if targetId == ownId then
		feelHit()
	end
end

local function onTank(value: any)
	if type(value) == "number" then
		setTank(value)
	end
end

-- Odepchnięcie ofiary: serwer podaje zmianę prędkości, a fizykę własnego kajaka liczy to urządzenie.
-- Po odpadnięciu i poza walką (Session.active = false) nie ma czego pchać.
local function onPush(dx: any, dz: any)
	local state = Session.state
	if type(dx) ~= "number" or type(dz) ~= "number" or state == nil or not Session.active then
		return
	end
	state.velocity += Vector2.new(dx, dz)
	feelHit()
	local hull = Session.ownHull
	if hull then
		burst(hull.Position, PUSH_SPRAY)
	end
end

local function onOut(userId: any, name: any, place: any)
	if place == 1 then
		return -- zwycięzca nie odpada; jeśli serwer wyśle go tą drogą, ogłosi go i tak ArenaResults
	end
	if userId == ownId then
		eliminated = true
		setWarning(false)
		flashScreen()
		showToast(string.format(Texts.outSelf, tonumber(place) or 0), OUT_TOAST_TIME)
		updateView()
	else
		showToast(string.format(Texts.outOther, tostring(name)), TOAST_TIME)
	end
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local scale = math.min(camera.ViewportSize.Y / Config.HUD_DESIGN_HEIGHT, Config.HUD_SCALE_MAX)
		for _, item in scales do
			item.Scale = scale
		end
	end
end

local function buildStatus()
	statusGroup = group("Status", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 8), UDim2.fromOffset(300, 46))
	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = TRACK_COLOR,
		BackgroundTransparency = 0.25,
	}, statusGroup)
	corner(track, UDim.new(0, 8))
	healthFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WATER_COLOR }, track)
	corner(healthFill, UDim.new(0, 8))
	healthLabel = label({ Size = UDim2.fromScale(1, 1), TextSize = 14 }, track)
	aliveLabel = label({ Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 22), TextSize = 18, TextColor3 = ACCENT_COLOR }, statusGroup)
end

local function buildMessages()
	local toastBox = group("Toast", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.2), UDim2.fromOffset(460, 44))
	toastLabel = label({ Size = UDim2.fromScale(1, 1), TextSize = 28, Visible = false }, toastBox)

	local warningBox = group("ZoneWarning", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.32), UDim2.fromOffset(460, 50))
	warningLabel = label({ Size = UDim2.fromScale(1, 1), TextSize = 36, TextColor3 = WARN_COLOR, Text = Texts.zoneWarning, Visible = false }, warningBox)
	warningPulse = TweenService:Create(
		warningLabel,
		TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextTransparency = 0.45 }
	)

	local watchBox = group("Watching", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -14), UDim2.fromOffset(460, 28))
	watchLabel = label({ Size = UDim2.fromScale(1, 1), TextSize = 19, Text = Texts.watching, Visible = false }, watchBox)
end

local function buildButton()
	-- Scale tej grupy dopasowuje przycisk do ekranu, a pressScale w środku daje „pop”: jedna skala nie nadpisuje drugiej.
	fireButton = make("TextButton", {
		Name = "Fire",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(BUTTON_X, BUTTON_Y),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, gui)
	table.insert(scales, make("UIScale", {}, fireButton))
	corner(fireButton, UDim.new(0.5, 0))
	fireStroke = make("UIStroke", { Color = WATER_COLOR, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, fireButton)

	local inner = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, fireButton)
	pressScale = make("UIScale", {}, inner)
	label({ Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 58), TextSize = 50, TextStrokeTransparency = 1, Text = Texts.fireIcon }, inner)
	-- Kolejność rysowania (dla TS: z-index po kolejności w DOM): ikona, przyciemnienie, podpis, żeby „PUSTO” zostało jasne.
	emptyCover = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Visible = false }, inner)
	corner(emptyCover, UDim.new(0.5, 0))
	fireCaption = label({ Position = UDim2.fromOffset(8, 78), Size = UDim2.new(1, -16, 0, 24), TextScaled = true, TextColor3 = WATER_COLOR, TextStrokeTransparency = 1, Text = Texts.fire }, inner)

	-- Zbiornik pod przyciskiem: nie jest Active, więc dotyk w pasek idzie do wiosła jak w resztę HUD-u.
	local tankTrack = make("Frame", {
		Name = "Tank",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, TANK_BAR_GAP),
		Size = UDim2.new(1, 0, 0, TANK_BAR_HEIGHT),
		BackgroundColor3 = TRACK_COLOR,
		BackgroundTransparency = 0.25,
	}, fireButton)
	corner(tankTrack, UDim.new(0, TANK_BAR_HEIGHT // 2))
	tankFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WATER_COLOR }, tankTrack)
	corner(tankFill, UDim.new(0, TANK_BAR_HEIGHT // 2))

	-- Nie Activated: ono przychodzi dopiero po puszczeniu, a tu liczy się moment wciśnięcia i trzymanie.
	-- Przycisk jest Active, więc PaddleInput dostaje ten dotyk jako processed i pomija go, a drugi palec na wodzie to osobny
	-- InputObject (dla TS: inny pointerId) i wiosłuje normalnie.
	fireButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			beginHold(input)
		end
	end)
end

local function buildInterface()
	gui = make("ScreenGui", {
		Name = "Arena",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 6, -- nad HUD-em; przy wynikach status, przycisk i komunikaty są ukryte, więc nic nie nachodzi na panel
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WATER_COLOR, BackgroundTransparency = 1, Visible = false }, gui)
	warningTint = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WARN_COLOR, BackgroundTransparency = 0.86, Visible = false }, gui)
	buildStatus()
	buildMessages()
	buildButton()
	updateScale()
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

local function buildJet(anchor: BasePart): Jet
	local start, finish = Instance.new("Attachment"), Instance.new("Attachment")
	start.Parent, finish.Parent = anchor, anchor
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = start, finish
	beam.Texture = SPRAY_TEXTURE
	beam.TextureSpeed = 3
	beam.TextureLength = 6
	beam.Width0, beam.Width1 = 0.9, 2.2
	beam.FaceCamera = true
	beam.LightEmission = 0.4
	beam.Color = ColorSequence.new(WATER_COLOR, TEXT_COLOR)
	beam.Transparency = NumberSequence.new(0.1, 0.35)
	beam.Enabled = false
	beam.Parent = anchor
	return { beam = beam, start = start, finish = finish, from = nil, to = nil, endsAt = 0 }
end

-- Mały romb nad celem, widoczny przez wszystko, jak znacznik w LakeTutorial. Adornee przestawia się na kadłub celu.
local function buildAimMarker()
	aimMarker = make("BillboardGui", {
		Name = "ArenaAim",
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(22, 22),
		StudsOffsetWorldSpace = Vector3.new(0, AIM_HEIGHT, 0),
		Enabled = false,
	}, nil)
	local shape = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		Rotation = 45,
		BackgroundColor3 = ACCENT_COLOR,
	}, aimMarker)
	make("UIStroke", { Color = PANEL_COLOR, Thickness = 2 }, shape)
	aimMarker.Parent = player:WaitForChild("PlayerGui")
end

local function buildRing()
	for i = 1, RING_SEGMENTS do
		local angle = (i - 1) / RING_SEGMENTS * 2 * math.pi
		-- Obrót o -angle kładzie lokalną oś Z wzdłuż stycznej do okręgu (-sin, cos); po niej biegnie długość panelu.
		ringAngles[i] = { cos = math.cos(angle), sin = math.sin(angle), turn = CFrame.Angles(0, -angle, 0) }
		local part = newPart(Vector3.new(RING_THICKNESS, RING_HEIGHT, 1), RING_COLOR)
		part.Material = Enum.Material.Neon
		part.Transparency = 0.35
		ringParts[i] = part
		ringFrames[i] = CFrame.identity
	end
end

local function buildWorld()
	folder = Instance.new("Folder")
	folder.Name = "ArenaFx"
	folder.Parent = workspace

	-- Jedna niewidzialna kotwica na wszystkie efekty (dla TS: wspólny canvas zamiast elementu na każdy efekt).
	local anchor = newPart(Vector3.one, TEXT_COLOR)
	anchor.Transparency = 1
	anchor.Parent = folder

	sprayAttachment = Instance.new("Attachment")
	sprayAttachment.Parent = anchor
	spray = Instance.new("ParticleEmitter")
	spray.Texture = SPRAY_TEXTURE
	spray.Rate = 0
	spray.Lifetime = NumberRange.new(0.4, 0.8)
	spray.Speed = NumberRange.new(10, 22)
	spray.SpreadAngle = Vector2.new(60, 60)
	spray.Acceleration = Vector3.new(0, -50, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Size = NumberSequence.new(0.8, 1.8)
	spray.Transparency = NumberSequence.new(0.15, 1)
	spray.Color = ColorSequence.new(TEXT_COLOR)
	spray.Parent = sprayAttachment

	for i = 1, JET_POOL do
		jets[i] = buildJet(anchor)
	end
	buildRing()
	buildAimMarker()
end

local function onArenaState()
	onZone(Session.arenaRadius)
	local alive = Session.arenaAlive
	aliveLabel.Text = if type(alive) == "number" then string.format(Texts.alive, alive) else ""
end

local function onPhase(phase: string)
	if phase == "countdown" then
		resetRound()
	elseif phase == "results" then
		hideToast()
	end
	updateView()
	if phase == "racing" then
		startRoundTicks()
	end
end

local function connectInput()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and KEYS[input.KeyCode] and fireButton.Visible then
			beginHold(input)
		end
	end)
	-- Globalnie, nie na przycisku: palec zsunięty z przycisku też kończy ogień przy puszczeniu.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if endsHold(input) then
			stopHold()
		end
	end)
	UserInputService.WindowFocusReleased:Connect(stopHold)
end

local function activate()
	fireRemote = Remotes.get("ArenaFire")
	buildWorld()
	buildInterface()
	connectInput()
	setHealth(MAX_HEALTH)

	Remotes.get("ArenaHealth").OnClientEvent:Connect(onHealth)
	Remotes.get("ArenaHit").OnClientEvent:Connect(onHit)
	Remotes.get("ArenaOut").OnClientEvent:Connect(onOut)
	Remotes.get("ArenaTank").OnClientEvent:Connect(onTank)
	Remotes.get("ArenaPush").OnClientEvent:Connect(onPush)

	Session.on("arenaState", onArenaState)
	Session.on("phase", onPhase)
	Session.on("reset", resetRound)

	-- KayakController mógł dostać pierwszy stan, zanim tu dotarliśmy.
	onArenaState()
	onPhase(Session.phase)
end

function ArenaController.start()
	-- Atrybut ustawia serwer spływu. Może przyjść po starcie klienta, ale tryb nie zmienia się w trakcie gry.
	if workspace:GetAttribute("RaceMode") == "arena" then
		activate()
		return
	end
	local connection: RBXScriptConnection
	connection = workspace:GetAttributeChangedSignal("RaceMode"):Connect(function()
		if workspace:GetAttribute("RaceMode") == "arena" then
			connection:Disconnect()
			activate()
		end
	end)
end

return ArenaController
