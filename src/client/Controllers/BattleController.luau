-- Tryb Bitwa po stronie klienta (ARCHITECTURE.md, sekcja „Tryb Bitwa”): skrzynki, siatki, przycisk przedmiotu i widać skutki.
-- Działa tylko, gdy workspace.RaceMode == "battle"; w zwykłym wyścigu nie tworzy niczego i nie ma żadnych połączeń.
-- Klient tylko rysuje i prosi o użycie przedmiotu (BattleUse). Decyzje podejmuje serwer, a tu zapisujemy jedynie
-- state.stunUntil, state.boostUntil i state.slowUntil, gdy przyjdzie BattleEffect.
--
-- Telefon: wszystko to gotowe pule (dla TS: object pool jak w WaterEffects). Najwięcej 15 części naraz: 6 skrzynek,
-- 3 siatki, 3 tarcze, 2 kotwice kilwatera i 1 kotwica efektów. Nieużywana część nie ma rodzica, więc nic nie kosztuje.
-- Pętla klatki jest podpięta tylko wtedy, gdy widać skrzynkę albo leci strumień (dla TS: requestAnimationFrame, który
-- sam się nie odnawia, gdy nie ma co rysować). Resztę animuje silnik: Tween, Trail, Beam, spoiny do kadłuba.
-- Wybór widocznych skrzynek odświeża się 4 razy na sekundę, nie co klatkę.

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
local Texts = require(Client.ui.Texts)

local BattleController = {}

local WATER_COLOR = Color3.fromRGB(70, 190, 225) -- sygnał ogłuszenia i tarczy: woda, bez czerwieni
local CRATE_COLOR = Color3.fromRGB(255, 196, 70)
local ITEM_CRATE_COLOR = Color3.fromRGB(245, 248, 250) -- skrzynka z ikoną: inna niż żółta „?”
local NET_COLOR = Color3.fromRGB(255, 140, 50)
local TEXT_COLOR = Color3.fromRGB(245, 248, 250)
local PANEL_COLOR = Color3.fromRGB(16, 34, 48)
local SPRAY_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- wbudowana w klienta, bez uploadu
local ITEM_POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Pule i wygląd (tylko klient, bez wpływu na zasady). Do przeniesienia do Config, gdy trzeba będzie je stroić.
local CRATE_POOL = 6 -- dwa najbliższe rzędy po 3
local NET_POOL = 3
local SHIELD_POOL = 3
local TRAIL_POOL = 2
local STAR_POOL = 3
local CRATE_SIZE = 3.5
local CRATE_FLOAT = 1.2 -- środek skrzynki nad lustrem wody
local CRATE_BOB = 0.25
local CRATE_SPIN = 1.4 -- rad/s
local CRATE_VIEW_AHEAD = 220 -- skrzynki przed graczem (wzdłuż rzeki); BATTLE_CRATE_SPACING = 120
local CRATE_VIEW_BEHIND = 20
local CRATE_REFRESH = 0.25
local NET_LINES = 5
local SHIELD_SIZE = 11
local TRAIL_LIFETIME = 1.8
local STAR_HEIGHT = 6.5 -- nad kadłubem, czyli nad głową postaci
local STAR_DISTANCE = 140
local JET_TIME = 0.45
local JET_REACH = 40 -- pudło: strumień leci tyle przed dziób
local ITEM_BUTTON_SIZE = 96
local ITEM_BUTTON_X, ITEM_BUTTON_Y = 0.78, 0.7 -- środek prawego dolnego pola: kciuk leży przy krawędzi, tu trzeba sięgnąć celowo
local USE_ANSWER_TIME = 1 -- po tylu s bez odpowiedzi uznajemy, że serwer odmówił (brak celu)
local TOAST_TIME = 1.6
local FLASH_TRANSPARENCY = 0.72
local SHIELD_ATTRIBUTE = "BattleShield" -- atrybut kajaka, ustawia BattleService
local KEYS = { [Enum.KeyCode.F] = true, [Enum.KeyCode.ButtonX] = true }

type Crate = { index: number, x: number, y: number, z: number, s: number, kind: string, taken: boolean, slot: CrateSlot? }
type CrateSlot = { part: BasePart, mark: TextLabel, crate: Crate? }
type NetSlot = { part: BasePart, id: number? }
type Aura = { attach: (BasePart) -> (), detach: () -> (), model: Model?, token: number }

local player = Players.LocalPlayer
local ownId = player.UserId
local river = Session.river

local folder: Folder = nil
local gui: ScreenGui = nil
local useRemote: RemoteEvent = nil

local crates: { Crate } = {}
local cratesByIndex: { [number]: Crate } = {}
local crateSlots: { CrateSlot } = {}
local netSlots: { NetSlot } = {}
local shields: { Aura } = {}
local trails: { Aura } = {}
local stars: { Aura } = {}
local auraPools = { shields, trails, stars }

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local frameConnection: RBXScriptConnection? = nil

local spray: ParticleEmitter = nil
local sprayAttachment: Attachment = nil
local jetBeam: Beam = nil
local jetStart: Attachment = nil
local jetEnd: Attachment = nil
local jetFrom: BasePart? = nil
local jetTo: BasePart? = nil
local jetUntil = 0 -- 0 = strumień nie leci

local itemButton: TextButton = nil
local itemIcon: TextLabel = nil
local itemName: TextLabel = nil
local itemScale: UIScale = nil
local buttonScale: UIScale = nil
local toastScale: UIScale = nil
local toastLabel: TextLabel = nil
local flash: Frame = nil

local item: string? = nil -- przedmiot gracza wg ostatniego BattleItem
local pendingItem: string? = nil -- przedmiot wysłany do użycia, czekamy na odpowiedź
local pendingAt = 0
local toastToken = 0

-- Pomocnicze ----------------------------------------------------------------------------------------------------------------

local function newPart(size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = "BattleFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
	part.Size = size
	return part
end

local function modelOf(userId: number): Model?
	local name = tostring(userId)
	for _, model in Session.kayaks do
		if model.Name == name then
			return model
		end
	end
	return nil
end

-- Efekty przy kajakach ------------------------------------------------------------------------------------------------------
-- Aura = coś przypiętego do kajaka na czas skutku: gwiazdki, tarcza albo kilwater. Trzy pule, jeden sposób obsługi.

local function hideSlot(aura: Aura)
	aura.token += 1 -- unieważnia zaplanowane zgaszenie (dla TS: jak clearTimeout)
	aura.model = nil
	aura.detach()
end

-- duration == nil: aura trwa do hideAura. Pełna pula = bez efektu, bo to tylko wygląd.
local function showAura(pool: { Aura }, model: Model?, duration: number?)
	local hull = model and model.PrimaryPart
	if model == nil or hull == nil then
		return
	end
	local aura: Aura? = nil
	for _, slot in pool do
		if slot.model == model then
			aura = slot
			break
		end
	end
	if aura == nil then
		for _, slot in pool do
			if slot.model == nil then
				aura = slot
				slot.model = model
				slot.attach(hull)
				break
			end
		end
	end
	if aura == nil then
		return
	end
	local slot = aura
	slot.token += 1
	if duration then
		local token = slot.token
		task.delay(duration, function()
			if slot.token == token then
				hideSlot(slot)
			end
		end)
	end
end

local function hideAura(pool: { Aura }, model: Model?)
	for _, slot in pool do
		if slot.model ~= nil and slot.model == model then
			hideSlot(slot)
		end
	end
end

-- Tarczę ogłasza serwer atrybutem kajaka, więc widać ją u wszystkich. Sprawdzane 4 razy na sekundę, bo kajaków jest najwyżej 8.
local function syncShields()
	for _, model in Session.kayaks do
		if model:GetAttribute(SHIELD_ATTRIBUTE) == true then
			showAura(shields, model)
		else
			hideAura(shields, model)
		end
	end
end

local function hideAllAuras()
	for _, pool in auraPools do
		for _, slot in pool do
			if slot.model then
				hideSlot(slot)
			end
		end
	end
end

-- Część spawana do kadłuba: rusza się z kajakiem bez ani jednej linijki w pętli klatki. Massless, więc nie zmienia fizyki,
-- a spoina istnieje tylko u tego gracza. Kolejność: najpierw ustawiamy CFrame, potem spoina, bo inaczej poruszylibyśmy kajak.
local function newWelded(part: Part): ((BasePart) -> (), () -> ())
	part.Anchored = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Parent = part
	return function(hull: BasePart)
		part.CFrame = hull.CFrame
		weld.Part1 = hull
		part.Parent = folder
	end, function()
		part.Parent = nil
		weld.Part1 = nil
	end
end

local function buildShield(): Aura
	local part = newPart(Vector3.one * SHIELD_SIZE, WATER_COLOR)
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.ForceField -- wbudowany materiał: sama poświata, bez tekstury
	local attach, detach = newWelded(part)
	return { attach = attach, detach = detach, model = nil, token = 0 }
end

-- Trail rysuje silnik, a dwa zaczepy przy rufie dają płaską wstęgę na wodzie. Przód kajaka to LookVector (-Z), więc rufa to +Z.
local function buildTrail(): Aura
	local part = newPart(Vector3.one * 0.2, TEXT_COLOR)
	part.Transparency = 1
	local left, right = Instance.new("Attachment"), Instance.new("Attachment")
	left.Position, right.Position = Vector3.new(-1.1, -0.2, 3), Vector3.new(1.1, -0.2, 3)
	left.Parent, right.Parent = part, part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = left, right
	trail.Lifetime = TRAIL_LIFETIME
	trail.Color = ColorSequence.new(TEXT_COLOR, WATER_COLOR)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Enabled = false
	trail.Parent = part
	local attachPart, detachPart = newWelded(part)
	return {
		attach = function(hull: BasePart)
			attachPart(hull)
			trail.Enabled = true
		end,
		detach = function()
			trail.Enabled = false
			detachPart()
		end,
		model = nil,
		token = 0,
	}
end

local function buildStars(): Aura
	local board = Instance.new("BillboardGui")
	board.Name = "BattleStars"
	board.Size = UDim2.fromOffset(110, 40)
	board.StudsOffset = Vector3.new(0, STAR_HEIGHT, 0)
	board.MaxDistance = STAR_DISTANCE
	board.AlwaysOnTop = true
	board.Enabled = false
	board.Parent = folder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = Texts.battle.stars
	label.TextColor3 = CRATE_COLOR
	label.TextStrokeTransparency = 0.3
	label.TextSize = 30
	label.Rotation = -12
	label.Parent = board
	local wobble = TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 12 })
	return {
		attach = function(hull: BasePart)
			board.Adornee = hull
			board.Enabled = true
			wobble:Play()
		end,
		detach = function()
			wobble:Cancel()
			board.Enabled = false
			board.Adornee = nil
		end,
		model = nil,
		token = 0,
	}
end

-- Rozbryzgi i strumień ------------------------------------------------------------------------------------------------------

local function burst(position: Vector3, count: number)
	local camera = workspace.CurrentCamera
	if camera and (position - camera.CFrame.Position).Magnitude <= Config.FX_RADIUS then
		sprayAttachment.WorldPosition = position
		spray:Emit(count)
	end
end

local function stopJet()
	jetUntil, jetFrom, jetTo = 0, nil, nil
	jetBeam.Enabled = false
end

local function jetTarget(from: BasePart): Vector3
	local to = jetTo
	if to and to.Parent then
		return to.Position
	end
	return from.Position + from.CFrame.LookVector * JET_REACH
end

-- Beam niesie animację tekstury sam, a my tylko pilnujemy końców, bo oba kajaki płyną dalej.
local function updateJet(now: number)
	local from = jetFrom
	if from == nil or from.Parent == nil then
		stopJet()
		return
	end
	local target = jetTarget(from)
	if now >= jetUntil then
		burst(target, 24)
		stopJet()
		return
	end
	jetStart.WorldPosition = from.Position + from.CFrame.LookVector * 3
	jetEnd.WorldPosition = target
end

-- Najbliższy kajak przed dziobem: tylko do wyglądu u strzelającego, ofiarę i tak wybrał serwer.
local function nearestAhead(hull: BasePart, range: number, arcCos: number): BasePart?
	local position = hull.Position
	local forward = hull.CFrame.LookVector
	local best: BasePart? = nil
	local bestDistance = range
	for _, model in Session.kayaks do
		local other = model.PrimaryPart
		if other and other ~= hull then
			local offset = other.Position - position
			local distance = offset.Magnitude
			if distance > 0 and distance < bestDistance and offset.Unit:Dot(forward) >= arcCos then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function ensureFrame()
	if frameConnection == nil then
		-- Pętla jest niżej: Luau widzi lokalne dopiero po deklaracji, więc podpinamy przez BattleController.frame
		frameConnection = RunService.Heartbeat:Connect(BattleController.frame)
	end
end

local function playCannon(from: BasePart, to: BasePart?)
	jetFrom, jetTo = from, to
	jetUntil = os.clock() + JET_TIME
	jetStart.WorldPosition = from.Position + from.CFrame.LookVector * 3
	jetEnd.WorldPosition = jetTarget(from)
	jetBeam.Enabled = true
	ensureFrame()
end

-- Skrzynki i siatki ---------------------------------------------------------------------------------------------------------

local function releaseCrate(crate: Crate)
	local slot = crate.slot
	if slot then
		crate.slot = nil
		slot.crate = nil
		slot.part.Parent = nil
	end
end

local function assignCrate(crate: Crate)
	for _, slot in crateSlots do
		if slot.crate == nil then
			slot.crate = crate
			crate.slot = slot
			local shown = Texts.battle.items[crate.kind]
			slot.mark.Text = if shown then shown.icon else Texts.battle.crateMark
			slot.part.Color = if shown then ITEM_CRATE_COLOR else CRATE_COLOR
			slot.part.CFrame = CFrame.new(crate.x, crate.y, crate.z)
			slot.part.Parent = folder
			ensureFrame()
			return
		end
	end
end

-- Dwa przejścia: najpierw zwalniamy sloty, żeby skrzynka wchodząca w zasięg miała gdzie trafić. Lista jest posortowana po s.
local function refreshCrates()
	local state = Session.state
	local q = state and state.lastQuery
	local s = if q then q.s else -math.huge
	local shown = 0
	for _, crate in crates do
		local wanted = not crate.taken and crate.s >= s - CRATE_VIEW_BEHIND and crate.s <= s + CRATE_VIEW_AHEAD and shown < CRATE_POOL
		if wanted then
			shown += 1
		else
			releaseCrate(crate)
		end
	end
	shown = 0
	for _, crate in crates do
		if not crate.taken and crate.s >= s - CRATE_VIEW_BEHIND and crate.s <= s + CRATE_VIEW_AHEAD and shown < CRATE_POOL then
			shown += 1
			if crate.slot == nil then
				assignCrate(crate)
			end
		end
	end
end

local function onCrate(index: any, available: any)
	local crate = cratesByIndex[index]
	if crate == nil then
		return
	end
	crate.taken = available ~= true
	if crate.taken then
		if crate.slot then
			burst(Vector3.new(crate.x, crate.y, crate.z), 14)
		end
		releaseCrate(crate)
	end
end

local function hideNet(slot: NetSlot)
	slot.id = nil
	slot.part.Parent = nil
end

local function hideNets()
	for _, slot in netSlots do
		hideNet(slot)
	end
end

local function onWorld(kind: any, x: any, z: any, id: any, active: any)
	if kind ~= "net" or type(x) ~= "number" or type(z) ~= "number" then
		return
	end
	for _, slot in netSlots do
		if slot.id == id then
			if active ~= true then
				hideNet(slot)
			end
			return
		end
	end
	if active ~= true then
		return
	end
	for _, slot in netSlots do
		if slot.id == nil then
			slot.id = id
			local level = river:query(Vector2.new(x, z)).level
			slot.part.CFrame = CFrame.new(x, level + Config.FX_WATER_Y, z)
			slot.part.Parent = folder
			burst(slot.part.Position, 8)
			return
		end
	end
end

-- Część z płaskim oczkiem: linie to Frame'y na SurfaceGui, więc sieć kosztuje jedną część.
local function buildNet(): NetSlot
	local width = Config.BATTLE_NET_RADIUS * 2
	local part = newPart(Vector3.new(width, 0.1, width), NET_COLOR)
	part.Transparency = 1
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Parent = part
	for line = 0, NET_LINES - 1 do
		local at = line / (NET_LINES - 1)
		for vertical = 0, 1 do
			local frame = Instance.new("Frame")
			frame.BorderSizePixel = 0
			frame.BackgroundColor3 = NET_COLOR
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = if vertical == 1 then UDim2.fromScale(at, 0.5) else UDim2.fromScale(0.5, at)
			frame.Size = if vertical == 1 then UDim2.new(0, 8, 1, 0) else UDim2.new(1, 0, 0, 8)
			frame.Parent = surface
		end
	end
	return { part = part, id = nil }
end

local function buildCrateSlot(): CrateSlot
	local part = newPart(Vector3.one * CRATE_SIZE, CRATE_COLOR)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(54, 54)
	board.StudsOffset = Vector3.new(0, CRATE_SIZE, 0)
	board.MaxDistance = CRATE_VIEW_AHEAD
	board.Parent = part
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Font = Enum.Font.GothamBold
	mark.Text = Texts.battle.crateMark
	mark.TextColor3 = TEXT_COLOR
	mark.TextStrokeTransparency = 0.2
	mark.TextSize = 42
	mark.Parent = board
	return { part = part, mark = mark, crate = nil }
end

-- Dane z BattleRules, te same numery co na serwerze. Moduł wczytujemy tutaj: w zwykłym wyścigu nie liczymy skrzynek wcale.
local function loadCrates()
	local module = Shared:FindFirstChild("BattleRules")
	local ok, list = pcall(function()
		return (require(module :: ModuleScript) :: any).crates(river)
	end)
	if not ok then
		warn(`[BattleController] skrzynki: {list}`)
		return
	end
	local hint = nil
	for _, entry in list do
		local q = river:query(entry.position, hint)
		hint = q.index
		local crate: Crate = {
			index = entry.index,
			x = entry.position.X,
			y = q.level + CRATE_FLOAT,
			z = entry.position.Y,
			s = entry.s,
			kind = entry.kind,
			taken = false,
			slot = nil,
		}
		table.insert(crates, crate)
		cratesByIndex[entry.index] = crate
	end
end

-- Pętla klatki istnieje tylko wtedy, gdy ma co animować, i sama się odpina.
function BattleController.frame()
	local now = os.clock()
	local moved = 0
	local angle = now * CRATE_SPIN
	local bob = math.sin(now * 2) * CRATE_BOB
	for _, slot in crateSlots do
		local crate = slot.crate
		if crate then
			moved += 1
			moveParts[moved] = slot.part
			moveFrames[moved] = CFrame.new(crate.x, crate.y + bob, crate.z) * CFrame.Angles(0, angle, 0)
		end
	end
	for i = #moveParts, moved + 1, -1 do
		moveParts[i], moveFrames[i] = nil, nil
	end
	if moved > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if jetUntil > 0 then
		updateJet(now)
	end
	if moved == 0 and jetUntil == 0 and frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

-- Interfejs -----------------------------------------------------------------------------------------------------------------

local function showToast(text: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(TOAST_TIME, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

local function flashScreen(duration: number)
	flash.BackgroundTransparency = FLASH_TRANSPARENCY
	flash.Visible = true
	local tween = TweenService:Create(flash, TweenInfo.new(duration), { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		flash.Visible = false
	end)
	tween:Play()
end

-- Przycisk tylko w trakcie wyścigu: ukryty nie przechwytuje dotyku, więc pole pod nim jest zwykłym polem wiosła.
local function updateButton()
	local shown = item ~= nil and Session.phase == "racing"
	itemButton.Visible = shown
	itemButton.Active = shown
end

local function useItem()
	if item == nil or pendingItem ~= nil or Session.phase ~= "racing" then
		return
	end
	pendingItem, pendingAt = item, os.clock()
	useRemote:FireServer()
end

-- Serwer zabrał przedmiot, czyli użycie się udało. BattleItem nie mówi, kogo trafiono, więc atak rysujemy z tego, co gracz trzymał.
local function onConsumed(used: string)
	local hull = Session.ownHull
	if hull and used == "cannon" then
		playCannon(hull, nearestAhead(hull, Config.BATTLE_CANNON_RANGE, Config.BATTLE_CANNON_ARC_COS))
	end
end

local function onItem(id: any)
	local texts = if type(id) == "string" then Texts.battle.items[id] else nil
	local used = pendingItem
	pendingItem = nil
	item = if texts then id else nil
	if texts then
		itemIcon.Text = texts.icon
		itemName.Text = texts.name
		itemScale.Scale = 1.3
		TweenService:Create(itemScale, ITEM_POP, { Scale = 1 }):Play()
	elseif used then
		onConsumed(used)
	end
	updateButton()
end

-- Bez odpowiedzi w czasie = serwer odmówił. Przedmiot zostaje, a gracz ma wiedzieć dlaczego nic się nie stało.
local function checkPending()
	local used = pendingItem
	if used and os.clock() - pendingAt >= USE_ANSWER_TIME then
		pendingItem = nil
		if used == "cannon" then
			showToast(Texts.battle.noTarget)
		end
	end
end

local function onStun(duration: number)
	local state = Session.state
	if state then
		state.stunUntil = math.max(state.stunUntil, os.clock() + duration)
		-- Ta sama droga co uderzenie w skałę: KayakController odda to rozbryzgowi, dźwiękowi i drżeniu kamery.
		state.lastHit = math.max(state.lastHit, Config.HIT_FULL_STRENGTH * 0.6)
	end
	showAura(stars, Session.ownModel, duration)
	showToast(Texts.battle.stunned)
	flashScreen(duration)
end

-- Przychodzi zaraz po ogłuszeniu z siatki, więc napis zastępuje „Ogłuszony!”.
local function onSlow(duration: number)
	local state = Session.state
	if state then
		state.slowUntil = math.max(state.slowUntil, os.clock() + duration)
	end
	showToast(Texts.battle.netted)
end

local function onBoost(duration: number)
	local state = Session.state
	if state then
		state.boostUntil = math.max(state.boostUntil, os.clock() + duration)
	end
	showAura(trails, Session.ownModel, duration)
	showToast(Texts.battle.boost)
end

local function onShieldHit()
	hideAura(shields, Session.ownModel)
	local hull = Session.ownHull
	if hull then
		burst(hull.Position, 24)
	end
	showToast(Texts.battle.shieldHit)
end

-- Cudze skutki, czyli BattleEffect("seen", what, userId, extra) do wszystkich. Własne przychodzą zwykłą drogą, więc tu je pomijamy.
-- Atak: what = "cannon", extra = userId celu lub nil. Stany: what = "stun" | "boost", extra = czas.
-- Bez tego wydarzenia gra działa, tylko gracz nie widzi skutków na cudzych kajakach.
local function onForeign(what: any, userId: any, extra: any)
	if userId == ownId then
		return
	end
	local model = if type(userId) == "number" then modelOf(userId) else nil
	if model == nil then
		return
	end
	if what == "cannon" then
		local hull = model.PrimaryPart
		local target = if type(extra) == "number" then modelOf(extra) else nil
		if hull then
			playCannon(hull, target and target.PrimaryPart)
		end
	else
		local pool = if what == "stun" then stars elseif what == "boost" then trails else nil
		if pool and type(extra) == "number" then
			showAura(pool, model, extra)
		end
	end
end

local function onEffect(kind: any, a: any, b: any, c: any)
	if kind == "seen" then
		onForeign(a, b, c)
		return
	end
	if kind == "stun" and type(a) == "number" then
		onStun(a)
	elseif kind == "slow" and type(a) == "number" then
		onSlow(a)
	elseif kind == "boost" and type(a) == "number" then
		onBoost(a)
	elseif kind == "shieldHit" then
		onShieldHit()
	end
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local scale = math.min(camera.ViewportSize.Y / Config.HUD_DESIGN_HEIGHT, Config.HUD_SCALE_MAX)
		buttonScale.Scale, toastScale.Scale = scale, scale
	end
end

local function buildInterface()
	gui = Instance.new("ScreenGui")
	gui.Name = "Battle"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4 -- pod HUD-em: wyniki przykrywają wszystko
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Tylko przycisk jest Active. Błysk i napisy przepuszczają dotyk do wiosła.
	flash = Instance.new("Frame")
	flash.Active = false
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WATER_COLOR
	flash.BackgroundTransparency = 1
	flash.Visible = false
	flash.Parent = gui

	local toastBox = Instance.new("Frame")
	toastBox.Active = false
	toastBox.AnchorPoint = Vector2.new(0.5, 0.5)
	toastBox.Position = UDim2.fromScale(0.5, 0.2)
	toastBox.Size = UDim2.fromOffset(400, 50)
	toastBox.BackgroundTransparency = 1
	toastBox.Parent = gui
	toastScale = Instance.new("UIScale")
	toastScale.Parent = toastBox

	toastLabel = Instance.new("TextLabel")
	toastLabel.Active = false
	toastLabel.BackgroundTransparency = 1
	toastLabel.Size = UDim2.fromScale(1, 1)
	toastLabel.Font = Enum.Font.GothamBold
	toastLabel.TextColor3 = TEXT_COLOR
	toastLabel.TextStrokeColor3 = PANEL_COLOR
	toastLabel.TextStrokeTransparency = 0.2
	toastLabel.TextSize = 32
	toastLabel.Visible = false
	toastLabel.Parent = toastBox

	itemButton = Instance.new("TextButton")
	itemButton.Name = "UseItem"
	itemButton.AnchorPoint = Vector2.new(0.5, 0.5)
	itemButton.Position = UDim2.fromScale(ITEM_BUTTON_X, ITEM_BUTTON_Y)
	itemButton.Size = UDim2.fromOffset(ITEM_BUTTON_SIZE, ITEM_BUTTON_SIZE)
	itemButton.BackgroundColor3 = PANEL_COLOR
	itemButton.BackgroundTransparency = 0.15
	itemButton.BorderSizePixel = 0
	itemButton.Text = ""
	itemButton.Visible = false
	itemButton.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = itemButton
	local stroke = Instance.new("UIStroke")
	stroke.Color = CRATE_COLOR
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = itemButton

	buttonScale = Instance.new("UIScale")
	buttonScale.Parent = itemButton

	-- Skala ekranu jest na przycisku, a „pop” po zdobyciu przedmiotu na ramce w środku: jedna nie nadpisuje drugiej.
	local inner = Instance.new("Frame")
	inner.Active = false
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.fromScale(1, 1)
	inner.Parent = itemButton
	itemScale = Instance.new("UIScale")
	itemScale.Parent = inner

	itemIcon = Instance.new("TextLabel")
	itemIcon.Active = false
	itemIcon.BackgroundTransparency = 1
	itemIcon.Position = UDim2.fromOffset(0, 6)
	itemIcon.Size = UDim2.new(1, 0, 0, 56)
	itemIcon.Font = Enum.Font.GothamBold
	itemIcon.TextColor3 = TEXT_COLOR
	itemIcon.TextSize = 46
	itemIcon.Text = ""
	itemIcon.Parent = inner

	itemName = Instance.new("TextLabel")
	itemName.Active = false
	itemName.BackgroundTransparency = 1
	itemName.Position = UDim2.fromOffset(4, 64)
	itemName.Size = UDim2.new(1, -8, 0, 24)
	itemName.Font = Enum.Font.GothamBold
	itemName.TextColor3 = CRATE_COLOR
	itemName.TextScaled = true
	itemName.Text = ""
	itemName.Parent = inner

	updateScale()
	gui.Parent = player:WaitForChild("PlayerGui")

	itemButton.Activated:Connect(useItem)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

local function buildWorld()
	folder = Instance.new("Folder")
	folder.Name = "BattleFx"
	folder.Parent = workspace

	for _ = 1, CRATE_POOL do
		table.insert(crateSlots, buildCrateSlot())
	end
	for _ = 1, NET_POOL do
		table.insert(netSlots, buildNet())
	end
	for _ = 1, SHIELD_POOL do
		table.insert(shields, buildShield())
	end
	for _ = 1, TRAIL_POOL do
		table.insert(trails, buildTrail())
	end
	for _ = 1, STAR_POOL do
		table.insert(stars, buildStars())
	end

	-- Jedna niewidzialna kotwica na wszystkie jednorazowe efekty (dla TS: wspólny canvas zamiast elementu na każdy efekt).
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

	jetStart, jetEnd = Instance.new("Attachment"), Instance.new("Attachment")
	jetStart.Parent, jetEnd.Parent = anchor, anchor
	jetBeam = Instance.new("Beam")
	jetBeam.Attachment0, jetBeam.Attachment1 = jetStart, jetEnd
	jetBeam.Texture = SPRAY_TEXTURE
	jetBeam.TextureSpeed = 3
	jetBeam.TextureLength = 6
	jetBeam.Width0, jetBeam.Width1 = 0.9, 2.2
	jetBeam.FaceCamera = true
	jetBeam.LightEmission = 0.4
	jetBeam.Color = ColorSequence.new(WATER_COLOR, TEXT_COLOR)
	jetBeam.Transparency = NumberSequence.new(0.1, 0.35)
	jetBeam.Enabled = false
	jetBeam.Parent = anchor
end

local function onPhase(phase: string)
	if phase == "countdown" then
		hideAllAuras()
		hideNets()
		stopJet()
	end
	updateButton()
end

local function activate()
	useRemote = Remotes.get("BattleUse")
	loadCrates()
	buildWorld()
	buildInterface()

	Remotes.get("BattleItem").OnClientEvent:Connect(onItem)
	Remotes.get("BattleEffect").OnClientEvent:Connect(onEffect)
	Remotes.get("BattleCrate").OnClientEvent:Connect(onCrate)
	Remotes.get("BattleWorld").OnClientEvent:Connect(onWorld)

	Session.on("phase", onPhase)
	Session.on("reset", hideAllAuras)
	Session.on("kayakRemoved", function(model: Model)
		for _, pool in auraPools do
			hideAura(pool, model)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and KEYS[input.KeyCode] then
			useItem()
		end
	end)

	task.spawn(function()
		while true do
			refreshCrates()
			syncShields()
			checkPending()
			updateButton()
			task.wait(CRATE_REFRESH)
		end
	end)
end

function BattleController.start()
	-- Atrybut ustawia serwer spływu po odczytaniu wpisu z wioski. Może przyjść po starcie klienta, ale tryb nie zmienia się w trakcie gry.
	if workspace:GetAttribute("RaceMode") == "battle" then
		activate()
		return
	end
	local connection: RBXScriptConnection
	connection = workspace:GetAttributeChangedSignal("RaceMode"):Connect(function()
		if workspace:GetAttribute("RaceMode") == "battle" then
			connection:Disconnect()
			activate()
		end
	end)
end

return BattleController
