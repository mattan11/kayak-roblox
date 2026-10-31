-- Wybór rzeki w wiosce: przycisk „Wybierz rzekę” w strefie przy pomoście, okno z kafelkami 7 rzek i panel kolejki.
-- Stan to kilka zmiennych (inZone, pickerOpen, joined, voted), a `render()` wylicza z nich widoczność, jak czysty render
-- w React. Serwer rozgłasza stan KAŻDEJ rzeki (QueueState), a klient wybiera tę, do której dołączył
-- (dla TS: globalny store z websocketa + selektor po `joined`).
-- Układ w pikselach dla wysokości telefonu, UIScale dopasowuje go do ekranu, jak w HudController.
-- Panel i przycisk stoją między gałką ruchu (dół, lewo) a przyciskiem skoku (dół, prawo). Tylko przyciski i okno są Active.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Medals = require(Shared:WaitForChild("Medals"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local River = require(Shared:WaitForChild("River"))
local RiverThumbnail = require(Shared:WaitForChild("RiverThumbnail"))

local Texts = require(script.Parent.Parent.Texts)

local RiverPicker = {}

local COLORS = {
	text = Color3.fromRGB(245, 248, 250),
	dim = Color3.fromRGB(190, 205, 215),
	accent = Color3.fromRGB(255, 196, 70),
	panel = Color3.fromRGB(16, 34, 48),
	track = Color3.fromRGB(10, 22, 32),
	fill = Color3.fromRGB(70, 190, 225),
	tile = Color3.fromRGB(28, 54, 72),
	fall = Color3.fromRGB(245, 248, 250),
}
-- Kolor miniaturki wg trudności; nieznana trudność dostaje COLORS.fill.
local DIFFICULTY_COLORS: { [string]: Color3 } = {
	["Łatwa"] = Color3.fromRGB(92, 200, 125),
	["Średnia"] = Color3.fromRGB(240, 170, 60),
	["Trudna"] = Color3.fromRGB(232, 92, 80),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local PANEL_HEIGHT = 142
local HEADER_HEIGHT = 44
local WINDOW_MARGIN = 10
local SCROLLBAR = 6
local WINDOW_SCREEN_GAP = 16 -- najmniejszy odstęp okna od krawędzi ekranu (w pikselach projektu)

type Queue = { count: number, endsAt: number?, ready: number }
type Entry = { id: string, river: string?, label: string, difficulty: string, available: boolean }
type Tile = { thumb: Frame, color: Color3, data: any }

local player = Players.LocalPlayer

local gui: ScreenGui = nil
local panelScale: UIScale = nil
local openScale: UIScale = nil
local windowScale: UIScale = nil
local noticeScale: UIScale = nil
local openButton: TextButton = nil
local backdrop: TextButton = nil
local list: ScrollingFrame = nil
local panel: Frame = nil
local titleLabel: TextLabel = nil
local statusLabel: TextLabel = nil
local goButton: TextButton = nil
local noticeGroup: Frame = nil
local noticeLabel: TextLabel = nil

local entries: { Entry } = {} -- content/RiverCatalog; puste = nie ma czego wybierać
local riverData: { [string]: any } = {} -- id → dane z content/rivers (tylko te, które już istnieją)
local queues: { [string]: Queue } = {} -- ostatni QueueState każdej rzeki
local tiles: { Tile } = {}
local thumbnailsDrawn = false

local inZone = false -- gracz stoi w QueueZone (po pozycji)
local pickerOpen = false
local joined: Entry? = nil -- rzeka, do której gracz dołączył
local voted = false -- ten gracz kliknął już „Płyń teraz”
local joinedAt = 0 -- kiedy kliknął rzekę; do tej chwili + QUEUE_CONFIRM_TIME czekamy na potwierdzenie serwera
local traveling = false -- teleport w toku
local noticeUntil = 0
local refreshTimer = 0

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

local function windowSize(): Vector2
	local columns, rows = Config.PICKER_COLUMNS, Config.PICKER_ROWS
	local gap = Config.PICKER_TILE_GAP
	return Vector2.new(
		columns * Config.PICKER_TILE_WIDTH + (columns - 1) * gap + 2 * WINDOW_MARGIN + SCROLLBAR,
		rows * Config.PICKER_TILE_HEIGHT + (rows - 1) * gap + HEADER_HEIGHT + WINDOW_MARGIN
	)
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		local height = viewport.Y / Config.HUD_DESIGN_HEIGHT
		panelScale.Scale = math.min(height, Config.PIER_PANEL_SCALE_MAX)
		openScale.Scale = panelScale.Scale
		noticeScale.Scale = math.min(height, Config.HUD_SCALE_MAX)
		-- Okno jest szerokie: na ekranie 16:9 ogranicza je szerokość, nie wysokość.
		local width = viewport.X / (windowSize().X + 2 * WINDOW_SCREEN_GAP)
		windowScale.Scale = math.min(height, width, Config.HUD_SCALE_MAX)
	end
end

-- Jedno miejsce, które decyduje, co widać. Wołane po każdej zmianie stanu i przy odświeżaniu.
local function render()
	local showPanel = inZone and joined ~= nil and not traveling
	local showPicker = inZone and pickerOpen and joined == nil
	openButton.Visible = inZone and joined == nil and not pickerOpen and #entries > 0
	backdrop.Visible = showPicker
	panel.Visible = showPanel

	local entry = joined
	if showPanel and entry then
		titleLabel.Text = string.format(Texts.queueTitle, entry.label, entry.difficulty)
		local queue = queues[entry.river or entry.id]
		if queue == nil or queue.count <= 0 then
			statusLabel.Text = Texts.queueJoining -- nasz bilet jeszcze nie dotarł do lidera albo grupa właśnie startuje
		else
			local status
			if queue.endsAt then
				local remaining = math.max(math.ceil(queue.endsAt - workspace:GetServerTimeNow()), 0)
				status = string.format(Texts.queueStatus, queue.count, Config.PIER_CAPACITY, remaining)
			else
				status = string.format(Texts.queueWaiting, queue.count, Config.PIER_CAPACITY)
			end
			if queue.count > 1 then
				status ..= string.format(Texts.queueReady, queue.ready, queue.count)
			end
			statusLabel.Text = status
		end
	end
end

-- Porzuca kolejkę u siebie i zgłasza to serwerowi. Bilet żyje w MemoryStore, więc samo schowanie panelu by go nie usunęło.
local function leaveQueue()
	if joined then
		joined = nil
		voted = false
		goButton.Text = Texts.queueGo
		Remotes.get("QueueAction"):FireServer("leave")
	end
end

local function joinQueue(entry: Entry)
	if inZone and joined == nil then
		joined = entry
		joinedAt = os.clock()
		pickerOpen = false
		Remotes.get("QueueAction"):FireServer("join", entry.river or entry.id)
		render()
	end
end

-- Obrócone Frame'y z policzonych odcinków. Pozycje są w pikselach projektu, więc skaluje je UIScale okna.
local function drawThumbnail(tile: Tile)
	local river = River.new(tile.data)
	local points, marks = RiverThumbnail.sample(river, Config.PICKER_THUMB_SEGMENTS)
	local layout = RiverThumbnail.layout(points, marks, {
		width = Config.PICKER_TILE_WIDTH - 12,
		height = Config.PICKER_THUMB_HEIGHT,
		padding = Config.PICKER_THUMB_PADDING,
		maxStretch = Config.PICKER_THUMB_STRETCH,
	})
	local line = Config.PICKER_THUMB_LINE
	for _, segment in layout.segments do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(segment.x, segment.y),
			Size = UDim2.fromOffset(segment.length + line * 0.5, line), -- zakładka zasłania szczeliny na zakrętach
			Rotation = segment.rotation,
			BackgroundColor3 = tile.color,
		}, tile.thumb)
	end
	local size = Config.PICKER_THUMB_DOT
	for _, dot in layout.dots do
		local item = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(dot.x, dot.y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = COLORS.fall,
			ZIndex = 2,
		}, tile.thumb)
		corner(item, size // 2)
	end
end

-- Liczone przy pierwszym otwarciu okna, nie przy starcie: większość graczy w wiosce ma być od razu gotowa do chodzenia.
local function drawThumbnails()
	if thumbnailsDrawn then
		return
	end
	thumbnailsDrawn = true
	for _, tile in tiles do
		if tile.data then
			local ok, err = pcall(drawThumbnail, tile)
			if not ok then
				warn(`[RiverPicker] miniaturka: {err}`)
			end
		end
	end
end

-- Progi medali w trzech równych kolumnach, od brązu do złota. Tylko czasy z Config: wioska nie ma ProfileStore,
-- więc nie zna medali gracza.
local function buildMedalTimes(entry: Entry, tile: Instance, top: number)
	local times = Config.RIVER_MEDALS[entry.river or entry.id]
	if times == nil then
		return
	end
	local width = (Config.PICKER_TILE_WIDTH - 18) // #Medals.RANKS
	for rank, key in Medals.RANKS do
		label({
			Position = UDim2.fromOffset(9 + (rank - 1) * width, top),
			Size = UDim2.fromOffset(width, 16),
			Font = FONT,
			TextSize = 13,
			TextColor3 = Medals.COLORS[rank],
			Text = string.format(Texts.pickerMedalTime, Medals.clock(times[key])),
		}, tile)
	end
end

local function buildTile(entry: Entry, order: number)
	local available = entry.available == true
	local tile: any = make(if available then "TextButton" else "Frame", {
		Name = entry.id,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.tile,
		BackgroundTransparency = if available then 0 else 0.45,
	}, list)
	corner(tile, 10)

	local thumb = make("Frame", {
		Name = "Thumb",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, Config.PICKER_THUMB_HEIGHT),
		BackgroundColor3 = COLORS.track,
	}, tile)
	corner(thumb, 8)

	local textTop = 6 + Config.PICKER_THUMB_HEIGHT + 3
	label({
		Position = UDim2.fromOffset(9, textTop),
		Size = UDim2.new(1, -18, 0, 20),
		TextSize = 16,
		Text = if entry.label == Texts.pickerSoon then "" else entry.label, -- zaślepka pokazuje „Wkrótce” na miniaturce
	}, tile)
	label({
		Position = UDim2.fromOffset(9, textTop + 20),
		Size = UDim2.new(1, -18, 0, 16),
		Font = FONT,
		TextSize = 13,
		TextColor3 = DIFFICULTY_COLORS[entry.difficulty] or COLORS.dim,
		Text = entry.difficulty,
	}, tile)

	buildMedalTimes(entry, tile, textTop + 36)

	if available then
		tile.Text = ""
		tile.Active = true
		tile.Activated:Connect(function()
			joinQueue(entry)
		end)
	else
		local cover = make("Frame", {
			Position = thumb.Position,
			Size = thumb.Size,
			BackgroundColor3 = COLORS.track,
			BackgroundTransparency = 0.3,
			ZIndex = 2,
		}, tile)
		corner(cover, 8)
		label({
			Size = UDim2.fromScale(1, 1),
			TextSize = 17,
			TextColor3 = COLORS.dim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = Texts.pickerSoon,
		}, cover)
	end

	table.insert(tiles, {
		thumb = thumb,
		color = DIFFICULTY_COLORS[entry.difficulty] or COLORS.fill,
		data = riverData[entry.id],
	})
end

local function buildOpenButton()
	openButton = make("TextButton", {
		Name = "OpenPicker",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(Config.PIER_PANEL_LEFT, 0, 1, -12),
		Size = UDim2.fromOffset(Config.PIER_PANEL_WIDTH, Config.PICKER_OPEN_HEIGHT),
		BackgroundColor3 = COLORS.accent,
		Font = FONT_BOLD,
		Text = Texts.pickerOpen,
		TextColor3 = COLORS.panel,
		TextSize = 24,
		Active = true,
		Visible = false,
	}, gui)
	corner(openButton, 14)
	openScale = make("UIScale", {}, openButton)
	openButton.Activated:Connect(function()
		pickerOpen = true
		drawThumbnails()
		render()
	end)
end

local function closePicker()
	pickerOpen = false
	render()
end

local function buildPicker()
	-- Tło na cały ekran: dotyk poza oknem zamyka je i nie porusza kamerą pod spodem.
	backdrop = make("TextButton", {
		Name = "Picker",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		Active = true,
		ZIndex = 10,
		Visible = false,
	}, gui)
	backdrop.Activated:Connect(closePicker)

	local size = windowSize()
	local window = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
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
		Text = Texts.pickerTitle,
	}, window)
	local close = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(HEADER_HEIGHT - 4, HEADER_HEIGHT - 8),
		BackgroundColor3 = COLORS.tile,
		Font = FONT_BOLD,
		Text = Texts.pickerClose,
		TextColor3 = COLORS.text,
		TextSize = 20,
		Active = true,
	}, window)
	corner(close, 10)
	close.Activated:Connect(closePicker)

	local width = Config.PICKER_TILE_WIDTH
	local height = Config.PICKER_TILE_HEIGHT
	local gap = Config.PICKER_TILE_GAP
	-- Rozmiar płótna liczymy sami: AbsoluteContentSize układu jest już przemnożony przez UIScale.
	local rows = math.ceil(#entries / Config.PICKER_COLUMNS)
	list = make("ScrollingFrame", {
		Name = "Rivers",
		Position = UDim2.fromOffset(WINDOW_MARGIN, HEADER_HEIGHT),
		Size = UDim2.new(1, -WINDOW_MARGIN * 2, 1, -HEADER_HEIGHT - WINDOW_MARGIN),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, rows * height + (rows - 1) * gap),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = COLORS.dim,
		Active = true,
	}, window)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(width, height),
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	for order, entry in entries do
		buildTile(entry, order)
	end
end

local function actionButton(text: string, anchorX: number, color: Color3, onClick: () -> ()): TextButton
	local button: any = make("TextButton", {
		AnchorPoint = Vector2.new(anchorX, 1),
		Position = UDim2.new(anchorX, if anchorX == 0 then 12 else -12, 1, -8),
		Size = UDim2.new(0.5, -16, 0, Config.UI_BUTTON_HEIGHT),
		BackgroundColor3 = color,
		Font = FONT_BOLD,
		Text = text,
		TextColor3 = COLORS.panel,
		TextSize = 17,
		Active = true,
	}, panel)
	corner(button, 10)
	button.Activated:Connect(onClick)
	return button
end

local function buildPanel()
	panel = make("Frame", {
		Name = "Queue",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(Config.PIER_PANEL_LEFT, 0, 1, -8),
		Size = UDim2.fromOffset(Config.PIER_PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.12,
		Visible = false,
	}, gui)
	corner(panel, 14)
	panelScale = make("UIScale", {}, panel)

	titleLabel = label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 18,
		TextColor3 = COLORS.accent,
		Text = "",
	}, panel)
	statusLabel = label({
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 17,
		Text = "",
	}, panel)
	label({
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 0, 18),
		Font = FONT,
		TextSize = 13,
		TextColor3 = COLORS.dim,
		Text = Texts.queueWorld,
	}, panel)

	goButton = actionButton(Texts.queueGo, 0, COLORS.accent, function()
		if joined and not voted then
			Remotes.get("QueueAction"):FireServer("ready")
		end
	end)
	actionButton(Texts.queueLeave, 1, COLORS.fill, function()
		leaveQueue()
		render()
	end)
end

local function buildNotice()
	noticeGroup = make("Frame", {
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 34),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.12,
		ZIndex = 20,
		Visible = false,
	}, gui)
	corner(noticeGroup, 10)
	noticeScale = make("UIScale", {}, noticeGroup)
	noticeLabel = label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	}, noticeGroup)
end

-- TravelNotice oznacza nieudaną podróż, więc gracz wraca do przycisku i może wybrać rzekę od nowa.
local function showNotice(key: any)
	noticeLabel.Text = Texts.travel[key] or Texts.travelDefault
	noticeGroup.Visible = true
	noticeUntil = os.clock() + Config.UI_NOTICE_TIME
	leaveQueue()
	render()
end

-- Czy gracz stoi w strefie: pozycja w układzie strefy kontra pół rozmiaru.
local function isInZone(position: Vector3): boolean
	local folder = workspace:FindFirstChild("Piers")
	if folder == nil then
		return false
	end
	for _, zone in folder:GetChildren() do
		if zone:IsA("BasePart") and zone.Name == "QueueZone" then
			local inside = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(inside.X) <= half.X and math.abs(inside.Y) <= half.Y and math.abs(inside.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function ownPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Prawdę o kolejce trzyma serwer w atrybutach gracza: mógł odrzucić „join” albo sam zdjąć gracza z kolejki.
local function syncWithServer()
	local river = player:GetAttribute("QueueRiver")
	traveling = player:GetAttribute("QueueTraveling") == true
	if river then
		for _, entry in entries do
			if (entry.river or entry.id) == river then
				joined = entry
			end
		end
	elseif joined and os.clock() - joinedAt > Config.QUEUE_CONFIRM_TIME then
		joined = nil
	end
	voted = joined ~= nil and player:GetAttribute("QueueReady") == true
	goButton.Text = if voted then Texts.queueGoWaiting else Texts.queueGo
end

local function refresh()
	syncWithServer()
	local position = ownPosition()
	inZone = position ~= nil and isInZone(position)
	if not inZone then
		pickerOpen = false
		leaveQueue()
	end
	render()

	if noticeGroup.Visible and os.clock() >= noticeUntil then
		noticeGroup.Visible = false
	end
end

local function onHeartbeat(dt: number)
	refreshTimer += dt
	if refreshTimer >= Config.HUD_REFRESH then
		refreshTimer = 0
		refresh()
	end
end

-- Moduł z content albo nil. Treść tworzy osobny etap prac, a brak pliku nie może wyłączyć całego interfejsu wioski.
local function loadModule(module: Instance?): any
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[RiverPicker] {module.Name}: {result}`)
		return nil
	end
	return result
end

local function loadContent()
	local content = Shared:WaitForChild("content")
	local catalog = loadModule(content:FindFirstChild("RiverCatalog"))
	if catalog == nil then
		warn("[RiverPicker] brak content/RiverCatalog, przycisk wyboru rzeki się nie pojawi")
		return
	end
	entries = catalog
	local rivers = content:FindFirstChild("rivers")
	for _, entry in entries do
		riverData[entry.id] = loadModule(rivers and rivers:FindFirstChild(entry.id))
	end
end

function RiverPicker.start()
	loadContent()

	gui = make("ScreenGui", {
		Name = "RiverPicker",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	buildOpenButton()
	buildPicker()
	buildPanel()
	buildNotice()
	updateScale()
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	Remotes.get("QueueState").OnClientEvent:Connect(function(river: string, count: number, endsAt: number?, ready: number?)
		queues[river] = { count = count, endsAt = endsAt, ready = ready or 0 }
	end)
	Remotes.get("TravelNotice").OnClientEvent:Connect(showNotice)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return RiverPicker
