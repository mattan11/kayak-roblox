-- Tablica wyników na placu: top N dla każdej dostępnej rzeki, rzeki zmieniają się co kilka sekund.
-- Bryłę stawia VillageWorld (workspace.Boards.ResultsBoard), a tu powstaje napis i dane. Czyta te same OrderedDataStore
-- `Times_<river>`, do których spływ zapisuje czasy: wartość w milisekundach, niższa lepsza.
-- Ranking to dodatek: każde zapytanie jest w pcall, a błąd (brak API w Studio, limit, awaria Robloxa) zostawia starą listę.
-- Serwer zmienia tekst etykiet, Roblox sam replikuje je do klientów, więc nie trzeba żadnego zdarzenia.
-- (Dla TS: `setInterval` z fetchem w `try/catch` i drugi `setInterval`, który przełącza widok na danych z pamięci.)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RiverCatalog = require(Shared:WaitForChild("content"):WaitForChild("RiverCatalog"))

local RiverBoards = {}

local BOARD_COLOR = Color3.fromRGB(28, 40, 48)
local STRIPE_COLOR = Color3.fromRGB(255, 255, 255)
local TEXT_COLOR = Color3.fromRGB(245, 245, 240)
local MUTED_COLOR = Color3.fromRGB(176, 190, 196)
local GOLD_COLOR = Color3.fromRGB(255, 206, 84)

local LIST_TOP = 0.24 -- lista zajmuje dół tablicy, nad nią tytuł i nazwa rzeki
local LIST_HEIGHT = 0.73

type Row = { name: string, time: number }
type RowLabels = { frame: Frame, place: TextLabel, name: TextLabel, time: TextLabel }

local names: { [number]: string } = {} -- userId → nazwa, żeby nie pytać Robloxa przy każdym odświeżeniu
local top: { [string]: { Row } } = {} -- id rzeki → ostatnia dobra lista

local riverLabel: TextLabel
local emptyLabel: TextLabel
local rowLabels: { RowLabels } = {}

local function report(action: string, message: any)
	if not RunService:IsStudio() then
		warn(`[RiverBoards] {action}: {message}`)
	end
end

-- 83.456 → "1:23.45": dwa miejsca po przecinku, bo w czołówce czasy leżą blisko siebie.
local function formatTime(seconds: number): string
	local hundredths = math.floor(seconds * 100)
	return string.format("%d:%02d.%02d", hundredths // 6000, (hundredths // 100) % 60, hundredths % 100)
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	if names[userId] == nil then
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		if ok then
			names[userId] = name
		end
	end
	return names[userId] or "?"
end

-- Lista dla rzeki albo nil przy błędzie (nil ≠ pusta lista: pusta to „Brak wyników”, a nil zostawia stare dane).
local function readTop(riverId: string): { Row }?
	-- Sam store też w pcall: w Studio bez API potrafi rzucić już przy GetOrderedDataStore.
	local ok, page = pcall(function()
		local store = DataStoreService:GetOrderedDataStore("Times_" .. riverId)
		return store:GetSortedAsync(true, Config.RANKING_SIZE):GetCurrentPage()
	end)
	if not ok then
		report(`odczyt {riverId}`, page)
		return nil
	end
	local rows: { Row } = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId and type(entry.value) == "number" then
			table.insert(rows, { name = nameOf(userId), time = entry.value / 1000 })
		end
	end
	return rows
end

-- ── Napisy ──────────────────────────────────────────────────────────────────────────────────────────────

local function label(parent: Instance, position: UDim2, size: UDim2, color: Color3, font: Enum.Font, align: Enum.TextXAlignment): TextLabel
	local created = Instance.new("TextLabel")
	created.Position = position
	created.Size = size
	created.BackgroundTransparency = 1
	created.Font = font
	created.TextScaled = true
	created.TextColor3 = color
	created.TextXAlignment = align
	created.Text = ""
	created.Parent = parent
	return created
end

-- Wiersze powstają raz i potem zmieniamy tylko ich tekst. (Dla TS: stała lista węzłów zamiast przebudowy DOM.)
local function buildGui(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.VILLAGE_BOARD_PIXELS
	gui.LightInfluence = 0

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = BOARD_COLOR
	background.BorderSizePixel = 0
	background.Parent = gui

	local title = label(background, UDim2.fromScale(0.05, 0.03), UDim2.fromScale(0.9, 0.11), GOLD_COLOR, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	title.Text = "Najlepsze czasy"
	riverLabel = label(background, UDim2.fromScale(0.05, 0.14), UDim2.fromScale(0.9, 0.08), TEXT_COLOR, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	emptyLabel = label(background, UDim2.fromScale(0.1, 0.48), UDim2.fromScale(0.8, 0.14), MUTED_COLOR, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	emptyLabel.Text = "Brak wyników"

	local rowHeight = LIST_HEIGHT / Config.RANKING_SIZE
	for index = 1, Config.RANKING_SIZE do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromScale(0.03, LIST_TOP + (index - 1) * rowHeight)
		frame.Size = UDim2.fromScale(0.94, rowHeight)
		frame.BackgroundColor3 = STRIPE_COLOR
		frame.BackgroundTransparency = if index % 2 == 1 then 0.92 else 1
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = background

		local color = if index == 1 then GOLD_COLOR else TEXT_COLOR
		local inset, height = 0.1, 0.8 -- napis niższy od wiersza: wiersze się nie zlewają
		local place = label(frame, UDim2.fromScale(0.01, inset), UDim2.fromScale(0.1, height), color, Enum.Font.GothamBlack, Enum.TextXAlignment.Right)
		place.Text = tostring(index)
		rowLabels[index] = {
			frame = frame,
			place = place,
			name = label(frame, UDim2.fromScale(0.15, inset), UDim2.fromScale(0.55, height), color, Enum.Font.GothamBold, Enum.TextXAlignment.Left),
			time = label(frame, UDim2.fromScale(0.72, inset), UDim2.fromScale(0.26, height), color, Enum.Font.GothamBold, Enum.TextXAlignment.Right),
		}
	end

	gui.Parent = board
end

local function show(river: any)
	riverLabel.Text = `{river.label} · {river.difficulty}`
	local rows = top[river.id] or {}
	emptyLabel.Visible = #rows == 0
	for index, labels in rowLabels do
		local row = rows[index]
		labels.frame.Visible = row ~= nil
		if row then
			labels.name.Text = row.name
			labels.time.Text = formatTime(row.time)
		end
	end
end

-- ── Pętle ───────────────────────────────────────────────────────────────────────────────────────────────

local function availableRivers(): { any }
	local rivers = {}
	for _, entry in RiverCatalog do
		if entry.available then
			table.insert(rivers, entry)
		end
	end
	return rivers
end

function RiverBoards.start()
	local boards = workspace:FindFirstChild("Boards")
	local board = boards and boards:FindFirstChild("ResultsBoard")
	local rivers = availableRivers()
	if not board or not board:IsA("BasePart") or #rivers == 0 then
		return -- tablica to dodatek: bez świata wioski reszta działa dalej
	end

	buildGui(board)
	local current = 1
	show(rivers[current])

	task.spawn(function()
		while true do
			for _, river in rivers do
				top[river.id] = readTop(river.id) or top[river.id]
			end
			show(rivers[current]) -- od razu, żeby pierwsze dane nie czekały na zmianę rzeki
			task.wait(Config.RESULTS_REFRESH_TIME)
		end
	end)

	while true do
		task.wait(Config.RESULTS_ROTATE_TIME)
		current = current % #rivers + 1
		show(rivers[current])
	end
end

return RiverBoards
