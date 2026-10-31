-- Wodna bitwa po stronie klienta (ARCHITECTURE.md, sekcja „Strefy na jeziorze i Wodna bitwa”): przycisk strzału, pasek
-- wytrzymałości, licznik żywych, strumienie wody, pierścień strefy, widok odpadnięcia i komunikat o zwycięzcy.
-- Działa tylko, gdy workspace.RaceMode == "arena"; w innych trybach nie tworzy niczego i nie ma żadnych połączeń.
-- Klient tylko rysuje i prosi o strzał (ArenaFire). Cel, trafienie i obrażenia liczy serwer.
-- Fazę, promień strefy i liczbę żywych zapisuje do Session KayakController, a tu przychodzą zdarzeniami "phase" i "arenaState".
--
-- Telefon: strumienie to gotowa pula Beamów, a pierścień to stała lista paneli (dla TS: object pool, bez new w trakcie gry).
-- Pętla klatki istnieje tylko wtedy, gdy leci strumień, i sama się odpina (dla TS: requestAnimationFrame, który się nie
-- odnawia). Strefa i ostrzeżenie odświeżają się 5 razy na sekundę, tylko w trakcie walki. Pasek i odnowienie animuje Tween.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

-- Zasady są u serwera; te dwie liczby służą tylko do wyglądu i rytmu przycisku. Do czasu wpisania ich do Config działają wartości z kontraktu.
local MAX_HEALTH = Config.ARENA_HEALTH or 100
local FIRE_COOLDOWN = (Config.ARENA_COOLDOWN or 1) + 0.05 -- zapas na opóźnienia sieci: serwer nie odrzuci strzału przy trzymaniu

-- Wygląd (tylko klient, bez wpływu na zasady).
local JET_POOL = 4 -- 8 graczy × 1 strzał/s × JET_TIME to średnio 2 strumienie naraz
local JET_TIME = 0.28
local JET_REACH = 40 -- pudło: strumień leci tyle przed dziób
local RING_SEGMENTS = 36
local RING_HEIGHT = 16
local RING_THICKNESS = 0.6
local RING_Y = 6 -- środek panelu nad lustrem wody
local RING_OVERLAP = 1.03 -- panele lekko na siebie zachodzą, bez szpar
local ZONE_TICK = 0.2
local ZONE_MIN_STEP = 0.05 -- mniejszej zmiany promienia nie warto rysować
local ZONE_MAX_RATE = 10 -- studs/s; zabezpieczenie przed dwoma stanami tuż po sobie
local ZONE_MIN_GAP = 0.2 -- krótszy odstęp między stanami nie mówi nic o tempie
local ZONE_PREDICT = 1.5 -- tyle s dalej zwężamy sami, gdy kolejny stan się spóźnia
local BUTTON_SIZE = 124
local BUTTON_X, BUTTON_Y = 0.78, 0.7 -- to samo miejsce co przycisk przedmiotu w Bitwie
local LOW_HEALTH = 0.3
local TOAST_TIME = 1.6
local OUT_TOAST_TIME = 3
local FLASH_TRANSPARENCY = 0.78
local BAR_TWEEN = TweenInfo.new(0.2)
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
local cooldownCover: Frame = nil
local pressScale: UIScale = nil
local toastLabel: TextLabel = nil
local warningLabel: TextLabel = nil
local warningPulse: Tween = nil
local warningTint: Frame = nil
local watchLabel: TextLabel = nil
local winnerLabel: TextLabel = nil
local flash: Frame = nil

local eliminated = false
local warned = false
local zoneTicking = false
local readyAt = 0 -- os.clock(), od kiedy wolno strzelić
local holdInput: InputObject? = nil -- palec lub klawisz trzymający ogień
local holdToken = 0 -- zmiana unieważnia pętlę ognia (dla TS: jak AbortController)
local toastToken = 0

local zoneRadius: number? = nil -- ostatni promień od serwera
local zoneAt = 0 -- os.clock() tego stanu
local zoneRate = 0 -- studs/s, zmierzone z dwóch ostatnich stanów

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

-- Oba kajaki płyną dalej, więc przez ułamek sekundy pilnujemy końców strumienia. Pod koniec rozbryzg na trafionym.
local function updateJet(jet: Jet, now: number)
	local from = jet.from
	if from == nil or from.Parent == nil then
		stopJet(jet)
		return
	end
	local target = jetTarget(jet, from)
	if now >= jet.endsAt then
		if jet.to then
			burst(target, 24)
		end
		stopJet(jet)
		return
	end
	jet.start.WorldPosition = from.Position + from.CFrame.LookVector * 3
	jet.finish.WorldPosition = target
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

local function playJet(from: BasePart, to: BasePart?)
	for _, jet in jets do
		if jet.endsAt == 0 then
			jet.from, jet.to = from, to
			jet.endsAt = os.clock() + JET_TIME
			jet.start.WorldPosition = from.Position + from.CFrame.LookVector * 3
			jet.finish.WorldPosition = jetTarget(jet, from)
			jet.beam.Enabled = true
			if frameConnection == nil then
				frameConnection = RunService.Heartbeat:Connect(onFrame)
			end
			return
		end
	end
	-- Pełna pula: bez strumienia, ale gracz ma widzieć trafienie
	if to then
		burst(to.Position, 24)
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

local function startZoneTicks()
	if zoneTicking then
		return
	end
	zoneTicking = true
	task.spawn(function()
		while Session.phase == "racing" do
			zoneTick()
			task.wait(ZONE_TICK)
		end
		zoneTicking = false
		setWarning(false)
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

local function showToast(text: string, duration: number)
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

local function canFire(): boolean
	return Session.phase == "racing" and not eliminated and Session.state ~= nil
end

local function stopHold()
	holdToken += 1
	holdInput = nil
end

local function tryFire()
	local now = os.clock()
	if not canFire() or now < readyAt then
		return
	end
	readyAt = now + FIRE_COOLDOWN
	fireRemote:FireServer()

	pressScale.Scale = 0.88
	TweenService:Create(pressScale, PRESS_POP, { Scale = 1 }):Play()
	-- Odnowienie widać jako ciemną nakładkę, która znika. Animuje silnik, bez pracy w klatce.
	cooldownCover.BackgroundTransparency = 0.35
	TweenService:Create(cooldownCover, TweenInfo.new(FIRE_COOLDOWN, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play()
end

-- Trzymanie = ciągły ogień: pętla żyje tylko od wciśnięcia do puszczenia.
local function beginHold(input: InputObject)
	if holdInput ~= nil then
		return
	end
	holdInput = input
	holdToken += 1
	local token = holdToken
	task.spawn(function()
		while token == holdToken do
			tryFire()
			task.wait(math.max(readyAt - os.clock(), 0.05))
		end
	end)
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
	end
	statusGroup.Visible = Session.phase ~= "results"
	watchLabel.Visible = eliminated and Session.phase == "racing"
end

local function resetRound()
	eliminated = false
	readyAt = 0
	cooldownCover.BackgroundTransparency = 1
	winnerLabel.Visible = false
	setHealth(MAX_HEALTH)
	stopAllJets()
	updateView()
end

local function onHealth(health: any)
	if type(health) == "number" then
		setHealth(health)
	end
end

local function onHit(shooterId: any, targetId: any)
	local from = hullOf(shooterId)
	local to = if targetId ~= nil then hullOf(targetId) else nil
	if from then
		playJet(from, to)
	end
	if targetId == nil and shooterId == ownId then
		showToast(Texts.noTarget, TOAST_TIME)
	elseif targetId == ownId then
		local state = Session.state
		if state then
			-- Ta sama droga co uderzenie w skałę: KayakController odda to rozbryzgowi, dźwiękowi i drżeniu kamery.
			state.lastHit = math.max(state.lastHit, Config.HIT_FULL_STRENGTH * 0.35)
		end
		flashScreen()
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

-- Zwycięzca to pierwszy wiersz wyników. Napis ponad panelem wyników z HudController.
local function onResults(rows: any)
	if type(rows) ~= "table" then
		return
	end
	for index, row in rows do
		if type(row) == "table" and (row.place or index) == 1 then
			winnerLabel.Text = if row.userId == ownId then Texts.winnerSelf else string.format(Texts.winner, tostring(row.name))
			winnerLabel.Visible = true
			return
		end
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

	local winnerBox = group("Winner", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 2), UDim2.fromOffset(560, 28))
	winnerLabel = label({ Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = ACCENT_COLOR, Visible = false }, winnerBox)
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
	make("UIStroke", { Color = WATER_COLOR, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, fireButton)

	local inner = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, fireButton)
	pressScale = make("UIScale", {}, inner)
	label({ Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 58), TextSize = 50, TextStrokeTransparency = 1, Text = Texts.fireIcon }, inner)
	label({ Position = UDim2.fromOffset(8, 78), Size = UDim2.new(1, -16, 0, 24), TextScaled = true, TextColor3 = WATER_COLOR, TextStrokeTransparency = 1, Text = Texts.fire }, inner)
	cooldownCover = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1 }, inner)
	corner(cooldownCover, UDim.new(0.5, 0))

	-- Nie Activated: ono przychodzi dopiero po puszczeniu, a tu liczy się moment wciśnięcia i trzymanie.
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
		DisplayOrder = 6, -- nad HUD-em: napis o zwycięzcy stoi nad panelem wyników, a reszta jest wtedy ukryta
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
end

local function onArenaState()
	onZone(Session.arenaRadius)
	local alive = Session.arenaAlive
	aliveLabel.Text = if type(alive) == "number" then string.format(Texts.alive, alive) else ""
end

local function onPhase(phase: string)
	if phase == "countdown" then
		resetRound()
	end
	updateView()
	if phase == "racing" then
		startZoneTicks()
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
	Remotes.get("ArenaResults").OnClientEvent:Connect(onResults)

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
