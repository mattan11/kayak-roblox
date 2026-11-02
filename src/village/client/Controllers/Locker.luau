-- Szafka w wiosce: przycisk u góry w strefie szafki (workspace.Locker.LockerZone), okno ze skórkami kajaka i kolorami,
-- podgląd 3D i przycisk „Załóż”. Wzór i styl z RiverPicker: układ w pikselach dla wysokości telefonu, UIScale dopasowuje go do ekranu.
-- Stan zna serwer (CosmeticState). Klient tylko prosi o założenie (CosmeticAction "equip"), a kafelek zmienia się dopiero
-- po odpowiedzi serwera. Wybór w oknie (`selected`) to tylko podgląd: można obejrzeć też zablokowaną skórkę.
-- Podgląd to jeden ViewportFrame, budowany przy otwarciu okna i sprzątany przy zamknięciu (telefon: COSMETICS.md, sekcja 7).
-- `render()` wylicza widok z kilku zmiennych, jak czysty render w React (dla TS: `view = f(state, selected)`).
-- Tylko przyciski i okno są Active: tam dotyk nie trafia do wiosła (`processed` w PaddleInput), reszta przechodzi na wodę.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local KayakBody = require(Shared:WaitForChild("KayakBody"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Texts = require(script.Parent.Parent.Texts).locker

local Locker = {}

local COLORS = {
	text = Color3.fromRGB(245, 248, 250),
	dim = Color3.fromRGB(190, 205, 215),
	accent = Color3.fromRGB(255, 196, 70),
	panel = Color3.fromRGB(16, 34, 48),
	track = Color3.fromRGB(10, 22, 32),
	tile = Color3.fromRGB(28, 54, 72),
	locked = Color3.fromRGB(20, 38, 52),
	fresh = Color3.fromRGB(92, 200, 125),
	selected = Color3.fromRGB(245, 248, 250),
	sky = Color3.fromRGB(120, 175, 210),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local HEADER_HEIGHT = 44
local MARGIN = 10
local TAB_HEIGHT = 40
local SCROLLBAR = 6
local PREVIEW_HEIGHT = 150
local SWATCH_HEIGHT = 40
local WINDOW_SCREEN_GAP = 16 -- najmniejszy odstęp okna od krawędzi ekranu (w pikselach projektu)
local CAMERA_OFFSET = Vector3.new(0, 4.5, 10.5) -- podgląd: kamera krąży wokół kajaka w tej odległości
local CHECK_INTERVAL = Config.HUD_REFRESH

type Tile = { item: any, button: TextButton, swatch: Frame, need: TextLabel, lock: TextLabel, badge: TextLabel, stroke: UIStroke }

local player = Players.LocalPlayer

-- Ostatni stan od serwera. Do pierwszej odpowiedzi: wczytywanie, nic nie można założyć.
local state = {
	ready = false,
	failed = false,
	owned = {} :: { [string]: boolean },
	equipped = Cosmetics.defaultEquipped(),
	unseen = {} :: { [string]: boolean },
	stars = 0,
	maxStars = Cosmetics.maxStars(),
}
local selected = Cosmetics.defaultEquipped() -- podgląd w oknie, slot → id
local tab = "kayak"
local inZone = false
local isOpen = false
local checkTimer = 0

local gui: ScreenGui = nil
local openButton: TextButton = nil
local openScale: UIScale = nil
local backdrop: TextButton = nil
local windowScale: UIScale = nil
local previewHolder: Frame = nil
local nameLabel: TextLabel = nil
local starsLabel: TextLabel = nil
local statusLabel: TextLabel = nil
local equipButton: TextButton = nil
local noteLabel: TextLabel = nil
local tabButtons: { [string]: TextButton } = {}
local grids: { [string]: ScrollingFrame } = {}
local tiles: { Tile } = {}

-- Podgląd 3D: istnieje tylko przy otwartym oknie.
local viewport: ViewportFrame? = nil
local previewCamera: Camera? = nil
local previewModel: Model? = nil
local previewKey = "" -- jaki wygląd jest teraz w podglądzie; inny = przebudowa
local spinAngle = 0

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
		Font = FONT_BOLD,
		TextColor3 = COLORS.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
	for key, value in props do
		item[key] = value
	end
	return item
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local viewportSize = camera.ViewportSize
		local height = viewportSize.Y / Config.HUD_DESIGN_HEIGHT
		openScale.Scale = math.min(height, Config.PIER_PANEL_SCALE_MAX)
		local width = viewportSize.X / (Config.LOCKER_WINDOW_WIDTH + 2 * WINDOW_SCREEN_GAP)
		windowScale.Scale = math.min(height, width, Config.HUD_SCALE_MAX)
	end
end

local function owns(item: any): boolean
	return state.ready and Cosmetics.owns(item, state.owned)
end

local function minStars(item: any): number?
	return if item.unlock.kind == "stars" then item.unlock.min else nil
end

-- Kolor kafelka: kolor z katalogu, „auto” = kolor gracza z userId, skórka = jej barwa, klasyk = wybrany kolor.
local function swatchColor(item: any): Color3
	local render = item.render
	if render.kind == "color" then
		return render.color
	elseif render.kind == "auto" then
		return Cosmetics.look({ paint = item.id }, player.UserId).classicColor
	elseif render.paintable then
		return Cosmetics.look(selected, player.UserId).classicColor
	end
	return render.swatch
end

local function countUnseen(): number
	local count = 0
	for id in state.unseen do
		if Cosmetics.item(id) then
			count += 1
		end
	end
	return count
end

-- ── Podgląd 3D ──────────────────────────────────────────────────────────────────────────────────────────

local function rebuildPreview()
	local frame = viewport
	if frame == nil then
		return
	end
	local look = Cosmetics.look(selected, player.UserId)
	local key = look.template .. "|" .. tostring(look.color) .. "|" .. tostring(look.classicColor)
	if key == previewKey and previewModel then
		return
	end
	previewKey = key
	if previewModel then
		previewModel:Destroy()
	end
	local model = KayakBody.build(look)
	for _, part in KayakBody.parts(model) do
		part.Anchored = true
	end
	model.Parent = frame
	previewModel = model
end

local function openPreview()
	local camera = make("Camera", { FieldOfView = 40 }, nil)
	local frame = make("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.sky,
		Ambient = Color3.fromRGB(170, 170, 175),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-1, -2, -1),
		CurrentCamera = camera,
	}, previewHolder)
	corner(frame, 10)
	camera.Parent = frame
	viewport = frame
	previewCamera = camera
	previewKey = ""
	rebuildPreview()
end

local function closePreview()
	if viewport then
		viewport:Destroy() -- razem z kamerą i modelem
	end
	viewport = nil
	previewCamera = nil
	previewModel = nil
	previewKey = ""
end

-- Kamera krąży wokół kajaka: tańsze niż przesuwanie modelu, a wygląda tak samo.
local function spin(dt: number)
	local camera = previewCamera
	if camera == nil then
		return
	end
	spinAngle = (spinAngle + dt * Config.LOCKER_SPIN_SPEED) % (2 * math.pi)
	local position = CFrame.Angles(0, spinAngle, 0) * CAMERA_OFFSET
	camera.CFrame = CFrame.lookAt(position, Vector3.new(0, 0.3, 0))
end

-- ── Widok ───────────────────────────────────────────────────────────────────────────────────────────────

-- Sloty, w których wybór różni się od założenia.
local function changedSlots(): { string }
	local slots = {}
	for _, slot in Cosmetics.SLOTS do
		if selected[slot] ~= state.equipped[slot] then
			table.insert(slots, slot)
		end
	end
	return slots
end

-- Pierwsza zablokowana pozycja wśród zmian albo nil.
local function lockedChoice(slots: { string }): any
	for _, slot in slots do
		local item = Cosmetics.item(selected[slot])
		if item and not owns(item) then
			return item
		end
	end
	return nil
end

local function renderTiles()
	for _, tile in tiles do
		local item = tile.item
		local have = owns(item)
		local need = minStars(item)
		tile.swatch.BackgroundColor3 = swatchColor(item)
		tile.button.BackgroundColor3 = if have then COLORS.tile else COLORS.locked
		tile.lock.Visible = not have
		tile.need.Text = if need and need > 0 then string.format(Texts.need, need)
			elseif item.unlock.kind == "robux" then Texts.soon
			else ""
		tile.need.TextColor3 = if have then COLORS.dim else COLORS.accent
		tile.badge.Visible = state.unseen[item.id] == true
		local isEquipped = state.equipped[item.slot] == item.id
		local isSelected = selected[item.slot] == item.id
		tile.stroke.Enabled = isEquipped or isSelected
		tile.stroke.Color = if isEquipped then COLORS.accent else COLORS.selected
		tile.stroke.Thickness = if isEquipped then 3 else 2
	end
end

local function render()
	openButton.Visible = inZone and not isOpen
	local unseen = countUnseen()
	openButton.Text = if unseen > 0 then string.format(Texts.openNew, unseen) else Texts.open
	backdrop.Visible = isOpen
	if not isOpen then
		return
	end

	for slot, button in tabButtons do
		local active = slot == tab
		button.BackgroundColor3 = if active then COLORS.accent else COLORS.tile
		button.TextColor3 = if active then COLORS.panel else COLORS.text
		grids[slot].Visible = active
	end

	local kayakItem = Cosmetics.item(selected.kayak)
	local paintItem = Cosmetics.item(selected.paint)
	local paintable = kayakItem and kayakItem.render.paintable
	nameLabel.Text = if kayakItem and paintable and paintItem
		then string.format(Texts.nameWithPaint, kayakItem.label, paintItem.label)
		else (if kayakItem then kayakItem.label else "")
	starsLabel.Text = string.format(Texts.stars, state.stars, state.maxStars)
	noteLabel.Visible = tab == "paint" and not paintable
	noteLabel.Text = Texts.fixedLook

	local slots = changedSlots()
	local locked = lockedChoice(slots)
	local canEquip = state.ready and #slots > 0 and locked == nil
	equipButton.AutoButtonColor = canEquip
	equipButton.BackgroundColor3 = if canEquip then COLORS.accent else COLORS.tile
	equipButton.TextColor3 = if canEquip then COLORS.panel else COLORS.dim
	if state.failed then
		equipButton.Text = Texts.equip
		statusLabel.Text = Texts.failed
	elseif not state.ready then
		equipButton.Text = Texts.equip
		statusLabel.Text = Texts.loading
	elseif locked then
		equipButton.Text = Texts.locked
		local need = minStars(locked)
		statusLabel.Text = if need then string.format(Texts.lockedDetail, locked.label, need, state.stars) else Texts.soon
	elseif #slots == 0 then
		equipButton.Text = Texts.equipped
		statusLabel.Text = ""
	else
		equipButton.Text = Texts.equip
		statusLabel.Text = ""
	end
	renderTiles()
	rebuildPreview()
end

-- Obejrzana zakładka traci znaczniki „Nowe” (na serwerze, bo `unseen` jest w profilu). Wołane przy wyjściu z zakładki
-- albo zamknięciu okna, żeby gracz zdążył zobaczyć, co jest nowe.
local function markSeen(slot: string)
	for id in state.unseen do
		local item = Cosmetics.item(id)
		if item and item.slot == slot then
			Remotes.get("CosmeticAction"):FireServer("seen", slot)
			return
		end
	end
end

local function selectTab(slot: string)
	if slot ~= tab then
		markSeen(tab)
	end
	tab = slot
	render()
end

local function openLocker()
	isOpen = true
	selected = table.clone(state.equipped)
	openPreview()
	selectTab(tab)
end

local function closeLocker()
	if not isOpen then
		return
	end
	isOpen = false
	markSeen(tab)
	closePreview()
	render()
end

local function equip()
	local slots = changedSlots()
	if not state.ready or #slots == 0 or lockedChoice(slots) then
		return
	end
	for _, slot in slots do
		Remotes.get("CosmeticAction"):FireServer("equip", slot, selected[slot])
	end
end

-- ── Budowa interfejsu ───────────────────────────────────────────────────────────────────────────────────

local function buildOpenButton()
	openButton = make("TextButton", {
		Name = "OpenLocker",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Config.VILLAGE_PICKER_BUTTON_TOP),
		Size = UDim2.fromOffset(Config.LOCKER_BUTTON_WIDTH, Config.PICKER_OPEN_HEIGHT),
		BackgroundColor3 = COLORS.accent,
		Font = FONT_BOLD,
		Text = Texts.open,
		TextColor3 = COLORS.panel,
		TextSize = 22,
		Active = true,
		Visible = false,
	}, gui)
	corner(openButton, 14)
	openScale = make("UIScale", {}, openButton)
	openButton.Activated:Connect(openLocker)
end

local function buildTile(item: any, order: number, parent: Instance)
	local button: any = make("TextButton", {
		Name = item.id,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.tile,
		AutoButtonColor = true,
		Text = "",
		Active = true,
	}, parent)
	corner(button, 10)
	local stroke = make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Enabled = false }, button)

	local swatch = make("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, SWATCH_HEIGHT),
		BackgroundColor3 = COLORS.track,
	}, button)
	corner(swatch, 8)
	local lock = label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Texts.lock,
		BackgroundColor3 = COLORS.track,
		BackgroundTransparency = 0.45,
		Visible = false,
	}, swatch)
	corner(lock, 8)
	local badge = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -2, 0, 2),
		Size = UDim2.fromOffset(46, 16),
		BackgroundColor3 = COLORS.fresh,
		BackgroundTransparency = 0,
		TextSize = 11,
		TextColor3 = COLORS.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Texts.newBadge,
		ZIndex = 2,
		Visible = false,
	}, swatch)
	corner(badge, 6)

	label({
		Position = UDim2.fromOffset(8, 6 + SWATCH_HEIGHT + 4),
		Size = UDim2.new(1, -16, 0, 18),
		TextSize = 15,
		Text = item.label,
	}, button)
	local need = label({
		Position = UDim2.fromOffset(8, 6 + SWATCH_HEIGHT + 22),
		Size = UDim2.new(1, -16, 0, 16),
		Font = FONT,
		TextSize = 13,
		Text = "",
	}, button)

	button.Activated:Connect(function()
		selected[item.slot] = item.id
		render()
	end)
	table.insert(tiles, { item = item, button = button, swatch = swatch, need = need, lock = lock, badge = badge, stroke = stroke })
end

-- Siatka kafelków jednego slotu. Rozmiar płótna liczymy sami: AbsoluteContentSize jest już przemnożony przez UIScale.
local function buildGrid(slot: string, parent: Instance, top: number)
	local items = Cosmetics.list(slot)
	local columns = Config.LOCKER_COLUMNS
	local rows = math.ceil(#items / columns)
	local gap = Config.LOCKER_TILE_GAP
	local grid = make("ScrollingFrame", {
		Name = slot,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, rows * Config.LOCKER_TILE_HEIGHT + (rows - 1) * gap + 4),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = COLORS.dim,
		Active = true,
		Visible = false,
	}, parent)
	make("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3) }, grid) -- miejsce na obwódkę kafelka
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(Config.LOCKER_TILE_WIDTH, Config.LOCKER_TILE_HEIGHT),
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	for order, item in items do
		buildTile(item, order, grid)
	end
	grids[slot] = grid
end

local function buildWindow()
	-- Tło na cały ekran: dotyk poza oknem zamyka je i nie porusza kamerą pod spodem.
	backdrop = make("TextButton", {
		Name = "Locker",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		Active = true,
		ZIndex = 10,
		Visible = false,
	}, gui)
	backdrop.Activated:Connect(closeLocker)

	local window = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Config.LOCKER_WINDOW_WIDTH, Config.LOCKER_WINDOW_HEIGHT),
		BackgroundColor3 = COLORS.panel,
		Active = true, -- inaczej dotyk w okno przeszedłby do tła i je zamknął
	}, backdrop)
	corner(window, 14)
	windowScale = make("UIScale", {}, window)

	label({ -- wyśrodkowany, bo przy lewej krawędzi leżą przyciski Robloxa
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		TextSize = 22,
		TextColor3 = COLORS.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Texts.title,
	}, window)
	local close = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(HEADER_HEIGHT - 4, HEADER_HEIGHT - 8),
		BackgroundColor3 = COLORS.tile,
		Font = FONT_BOLD,
		Text = Texts.close,
		TextColor3 = COLORS.text,
		TextSize = 20,
		Active = true,
	}, window)
	corner(close, 10)
	close.Activated:Connect(closeLocker)

	-- Lewa kolumna: podgląd, nazwa, gwiazdki, stan i „Załóż” na dole (duży cel dotyku).
	local previewWidth = Config.LOCKER_PREVIEW_WIDTH
	local left = make("Frame", {
		Name = "Left",
		Position = UDim2.fromOffset(MARGIN, HEADER_HEIGHT),
		Size = UDim2.new(0, previewWidth, 1, -HEADER_HEIGHT - MARGIN),
		BackgroundTransparency = 1,
	}, window)
	previewHolder = make("Frame", {
		Name = "PreviewHolder",
		Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT),
		BackgroundColor3 = COLORS.track,
	}, left)
	corner(previewHolder, 10)
	nameLabel = label({
		Position = UDim2.fromOffset(2, PREVIEW_HEIGHT + 4),
		Size = UDim2.new(1, -4, 0, 22),
		TextSize = 17,
		Text = "",
	}, left)
	starsLabel = label({
		Position = UDim2.fromOffset(2, PREVIEW_HEIGHT + 26),
		Size = UDim2.new(1, -4, 0, 20),
		TextSize = 16,
		TextColor3 = COLORS.accent,
		Text = "",
	}, left)
	statusLabel = label({
		Position = UDim2.fromOffset(2, PREVIEW_HEIGHT + 46),
		Size = UDim2.new(1, -4, 0, 34),
		Font = FONT,
		TextSize = 13,
		TextColor3 = COLORS.dim,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	}, left)
	equipButton = make("TextButton", {
		Name = "Equip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Config.UI_BUTTON_HEIGHT),
		BackgroundColor3 = COLORS.accent,
		Font = FONT_BOLD,
		Text = Texts.equip,
		TextColor3 = COLORS.panel,
		TextSize = 19,
		Active = true,
	}, left)
	corner(equipButton, 10)
	equipButton.Activated:Connect(equip)

	-- Prawa kolumna: dwie zakładki i siatka kafelków.
	local rightX = MARGIN * 2 + previewWidth
	local right = make("Frame", {
		Name = "Right",
		Position = UDim2.fromOffset(rightX, HEADER_HEIGHT),
		Size = UDim2.new(1, -rightX - MARGIN, 1, -HEADER_HEIGHT - MARGIN),
		BackgroundTransparency = 1,
	}, window)
	for index, slot in Cosmetics.SLOTS do
		local button = make("TextButton", {
			Name = "Tab_" .. slot,
			Position = UDim2.new((index - 1) / #Cosmetics.SLOTS, if index > 1 then 4 else 0, 0, 0),
			Size = UDim2.new(1 / #Cosmetics.SLOTS, -4, 0, TAB_HEIGHT),
			BackgroundColor3 = COLORS.tile,
			Font = FONT_BOLD,
			Text = Texts.tabs[slot],
			TextColor3 = COLORS.text,
			TextSize = 17,
			Active = true,
		}, right)
		corner(button, 10)
		button.Activated:Connect(function()
			selectTab(slot)
		end)
		tabButtons[slot] = button
	end
	noteLabel = label({
		Position = UDim2.fromOffset(2, TAB_HEIGHT + 4),
		Size = UDim2.new(1, -4, 0, 18),
		Font = FONT,
		TextSize = 13,
		TextColor3 = COLORS.accent,
		Text = "",
		Visible = false,
	}, right)
	for _, slot in Cosmetics.SLOTS do
		buildGrid(slot, right, TAB_HEIGHT + 24)
	end
end

-- ── Strefa i stan ───────────────────────────────────────────────────────────────────────────────────────

-- Najpierw kajak; postać zostaje na czas, gdy kajaka jeszcze nie ma (dołączanie, odrodzenie).
local function ownPosition(): Vector3?
	local kayaks = workspace:FindFirstChild("Kayaks")
	local model = kayaks and kayaks:FindFirstChild(tostring(player.UserId))
	local hull = model and model:FindFirstChild("Hull")
	if hull and hull:IsA("BasePart") then
		return hull.Position
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Pozycja w układzie strefy kontra pół rozmiaru, jak QueueZone w RiverPicker.
local function insideZone(position: Vector3?): boolean
	local folder = workspace:FindFirstChild("Locker")
	local zone = folder and folder:FindFirstChild("LockerZone")
	if position == nil or zone == nil or not zone:IsA("BasePart") then
		return false
	end
	local inside = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(inside.X) <= half.X and math.abs(inside.Y) <= half.Y and math.abs(inside.Z) <= half.Z
end

local function onHeartbeat(dt: number)
	if isOpen then
		spin(dt)
	end
	checkTimer += dt
	if checkTimer < CHECK_INTERVAL then
		return
	end
	checkTimer = 0
	local wasInZone = inZone
	inZone = insideZone(ownPosition())
	if not inZone and isOpen then
		closeLocker() -- wypłynięcie ze strefy zamyka okno
	elseif inZone ~= wasInZone then
		render()
	end
end

-- Stan od serwera. Pola sprawdzamy, bo to dane z sieci (choć od serwera, lepiej nie wywrócić interfejsu).
local function onState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	state.ready = payload.ready == true
	state.failed = payload.failed == true
	state.owned = if type(payload.owned) == "table" then payload.owned else {}
	state.unseen = if type(payload.unseen) == "table" then payload.unseen else {}
	if type(payload.equipped) == "table" then
		state.equipped = payload.equipped
	end
	state.stars = if type(payload.stars) == "number" then payload.stars else 0
	state.maxStars = if type(payload.maxStars) == "number" then payload.maxStars else Cosmetics.maxStars()
	if not isOpen then
		selected = table.clone(state.equipped)
	end
	render()
end

function Locker.start()
	gui = make("ScreenGui", {
		Name = "Locker",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	buildOpenButton()
	buildWindow()
	updateScale()
	render()
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	Remotes.get("CosmeticState").OnClientEvent:Connect(onState)
	Remotes.get("CosmeticAction"):FireServer("sync") -- stan mógł przyjść, zanim powstał ten kontroler
	RunService.Heartbeat:Connect(onHeartbeat)
end

return Locker
