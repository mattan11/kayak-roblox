-- HUD: odliczanie, czas, pasek trasy z kropkami graczy, miejsce, rekord, ekran wyników (medal, „Jeszcze raz”, „Do wioski”) i top 10.
-- Odświeża się 10 razy na sekundę, nie co klatkę. Układ jest w pikselach dla wysokości telefonu (Config.HUD_DESIGN_HEIGHT),
-- a UIScale każdej grupy dopasowuje go do ekranu (dla TS: jak `rem` zależny od wysokości okna).
-- Nic poza przyciskami nie jest Active, więc dotyk przechodzi przez HUD do sterowania.
--
-- W Wodnej bitwie (Session.arena) nie ma zegara, paska trasy, rekordu, medalu ani top 10: stan walki rysuje ArenaController,
-- a tu zostają odliczanie i ekran wyników z miejscami z ArenaResults.
--
-- Ranking: ReplicatedStorage.TopTimes (StringValue z JSON-em, Leaderboard na serwerze). Brak = bez kolumny top 10.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Medals = require(Shared:WaitForChild("Medals"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local RaceFormat = require(Client.logic.RaceFormat)
local Session = require(Client.Session)
local Texts = require(Client.ui.Texts)

local HudController = {}

local COLORS = {
	text = Color3.fromRGB(245, 248, 250),
	dim = Color3.fromRGB(190, 205, 215),
	accent = Color3.fromRGB(255, 196, 70),
	panel = Color3.fromRGB(16, 34, 48),
	track = Color3.fromRGB(10, 22, 32),
	fill = Color3.fromRGB(70, 190, 225),
	other = Color3.fromRGB(245, 248, 250),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local MAX_ROWS = 10
local RESULT_ROWS = Config.PIER_CAPACITY -- lewa kolumna: pod wierszami graczy stoją dwie linie medalu
local MAX_DOTS = 12
local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local river = Session.river
local arena = Session.arena
local startS = Config.START_DISTANCE
local finishS = river.length - Config.FINISH_MARGIN

local gui: ScreenGui = nil
local scales: { UIScale } = {}

local timeLabel: TextLabel = nil
local placeLabel: TextLabel = nil
local recordLabel: TextLabel = nil
local bigLabel: TextLabel = nil
local bigScale: UIScale = nil
local messageLabel: TextLabel = nil
local trackGroup: Frame = nil
local track: Frame = nil
local fill: Frame = nil
local ownDot: Frame = nil
local dots: { Frame } = {}
local panel: Frame = nil
local panelTitle: TextLabel = nil
local resultRows: { TextLabel } = {}
local medalLabel: TextLabel = nil
local goalLabel: TextLabel = nil
local topTitle: TextLabel = nil
local topRows: { TextLabel } = {}
local againButton: TextButton = nil
local votesLabel: TextLabel = nil
local villageButton: TextButton = nil
local noticeGroup: Frame = nil
local noticeLabel: TextLabel = nil

local noticeUntil = 0 -- os.clock(), do kiedy widać komunikat o podróży
local refreshTimer = 0
local shownBig = ""
local isNewRecord = false
local awardedMedal = 0 -- stopień z MedalAwarded w tym wyścigu; 0 = medal nie wzrósł
local otherHints: { [Model]: number } = {} -- ostatni odcinek rzeki każdego kajaka
local otherS: { number } = {}

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
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for key, value in props do
		item[key] = value
	end
	return item
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

-- Grupa w rogu lub na środku ekranu, skalowana wokół swojego AnchorPoint.
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

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local scale = math.min(camera.ViewportSize.Y / Config.HUD_DESIGN_HEIGHT, Config.HUD_SCALE_MAX)
		for _, item in scales do
			item.Scale = scale
		end
	end
end

local function makeDot(size: number, color: Color3, order: number): Frame
	local dot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		ZIndex = order,
		Visible = false,
	}, track)
	corner(dot, size // 2)
	return dot
end

local function buildTop()
	-- Czas i miejsce po prawej: lewy górny róg zajmują przyciski Robloxa
	local info = group("Info", Vector2.new(1, 0), UDim2.new(1, -12, 0, 8), UDim2.fromOffset(170, 74))
	timeLabel = label({
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	}, info)
	placeLabel = label({
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 16,
		TextColor3 = COLORS.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
	}, info)
	recordLabel = label({
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 18),
		Font = FONT,
		TextSize = 14,
		TextColor3 = COLORS.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = Texts.noRecord,
	}, info)

	trackGroup = group("Track", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12), UDim2.fromOffset(300, 14))
	track = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLORS.track, BackgroundTransparency = 0.35 }, trackGroup)
	corner(track, 7)
	fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = COLORS.fill, BackgroundTransparency = 0.2 }, track)
	corner(fill, 7)
	for i = 1, MAX_DOTS do
		dots[i] = makeDot(9, COLORS.other, 2)
	end
	ownDot = makeDot(14, COLORS.accent, 3)
end

local function buildCenter()
	local center = group("Center", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.36), UDim2.fromOffset(420, 150))
	bigLabel = label({
		Size = UDim2.new(1, 0, 0, 110),
		TextSize = 96,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		Text = "",
	}, center)
	bigScale = make("UIScale", {}, bigLabel)
	messageLabel = label({
		Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Text = "",
	}, center)
end

local function buildRows(parent: Frame, into: { TextLabel }, count: number)
	for i = 1, count do
		into[i] = label({
			Position = UDim2.fromOffset(0, 30 + (i - 1) * 22),
			Size = UDim2.new(1, 0, 0, 21),
			Font = FONT,
			TextSize = 15,
			TextStrokeTransparency = 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Visible = false,
		}, parent)
	end
end

-- Gwiazdki po wyścigu (Config.FEEDBACK_ENABLED), ocena idzie do Analytics na serwerze.
local function buildFeedback(parent: Frame)
	if not Config.FEEDBACK_ENABLED then
		return
	end
	local row = make("Frame", {
		Name = "Feedback",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.fromOffset(274, 34),
		BackgroundTransparency = 1,
	}, parent)
	local ask = label({ Size = UDim2.new(0, 104, 1, 0), Font = FONT, TextSize = 14, Text = Texts.feedbackAsk }, row)
	local function send(stars: number)
		Remotes.get("Feedback"):FireServer(stars)
		ask.Text = Texts.feedbackThanks
	end
	for stars = 1, 5 do
		local button = make("TextButton", {
			Position = UDim2.fromOffset(104 + (stars - 1) * 34, 0),
			Size = UDim2.fromOffset(34, 34),
			BackgroundTransparency = 1,
			Font = FONT_BOLD,
			Text = "★",
			TextSize = 26,
			TextColor3 = COLORS.accent,
			Active = true,
		}, row)
		button.Activated:Connect(function()
			send(stars)
		end)
	end
end

local function actionButton(text: string, right: number, color: Color3, parent: Frame): TextButton
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -right, 1, -8),
		Size = UDim2.fromOffset(Config.UI_ACTION_WIDTH, Config.UI_BUTTON_HEIGHT),
		BackgroundColor3 = color,
		Font = FONT_BOLD,
		Text = text,
		TextColor3 = COLORS.panel,
		TextSize = 17,
		Active = true,
	}, parent)
	corner(button, 10)
	return button
end

-- Przycisk po kliknięciu czeka na serwer: dla TS `disabled={pending}` + inny napis.
local function setButton(button: TextButton, text: string, enabled: boolean)
	button.Text = text
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = if enabled then 0 else 0.45
end

local function resetActions()
	setButton(againButton, Texts.again, true)
	setButton(villageButton, Texts.toVillage, true)
end

local function buildActions(parent: Frame)
	againButton = actionButton(Texts.again, 14, COLORS.accent, parent)
	villageButton = actionButton(Texts.toVillage, 14 + Config.UI_ACTION_WIDTH + 8, COLORS.fill, parent)
	votesLabel = label({
		Position = UDim2.new(0, 14, 1, -(Config.UI_BUTTON_HEIGHT + 36)),
		Size = UDim2.new(1, -28, 0, 22),
		TextSize = 16,
		TextColor3 = COLORS.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
	}, parent)

	againButton.Activated:Connect(function()
		if againButton.Active then
			setButton(againButton, Texts.againWaiting, false)
			Remotes.get("RaceAction"):FireServer("again")
		end
	end)
	villageButton.Activated:Connect(function()
		if villageButton.Active then
			setButton(villageButton, Texts.toVillageWaiting, false)
			setButton(againButton, Texts.again, false)
			Remotes.get("RaceAction"):FireServer("village")
		end
	end)
end

local function buildPanel()
	panel = group("Results", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), UDim2.fromOffset(600, 356))
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.12
	panel.Visible = false
	corner(panel, 14)

	local left = make("Frame", {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(0.5, -30, 1, -24),
		BackgroundTransparency = 1,
	}, panel)
	panelTitle = label({ Size = UDim2.new(1, 0, 0, 26), TextSize = 20, TextColor3 = COLORS.accent, Text = Texts.resultsTitle }, left)
	buildRows(left, resultRows, RESULT_ROWS)
	local medalTop = 30 + RESULT_ROWS * 22 + 2
	medalLabel = label({
		Position = UDim2.fromOffset(0, medalTop),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 17,
		TextStrokeTransparency = 1,
		Text = "",
	}, left)
	goalLabel = label({
		Position = UDim2.fromOffset(0, medalTop + 22),
		Size = UDim2.new(1, 0, 0, 20),
		Font = FONT,
		TextSize = 15,
		TextColor3 = COLORS.dim,
		TextStrokeTransparency = 1,
		Text = "",
	}, left)

	local right = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 12),
		Size = UDim2.new(0.5, -30, 1, -24),
		BackgroundTransparency = 1,
	}, panel)
	topTitle = label({ Size = UDim2.new(1, 0, 0, 26), TextSize = 20, TextColor3 = COLORS.accent, Text = Texts.topTitle }, right)
	buildRows(right, topRows, MAX_ROWS)

	buildFeedback(panel)
	buildActions(panel)
end

-- Komunikat o podróży ma własną etykietę: messageLabel nadpisuje updateCenter przy każdym odświeżeniu.
-- Tworzony po panelu wyników, więc rysuje się nad nim (ZIndexBehavior.Sibling).
local function buildNotice()
	noticeGroup = group("Notice", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 32), UDim2.fromOffset(460, 34))
	noticeGroup.BackgroundColor3 = COLORS.panel
	noticeGroup.BackgroundTransparency = 0.12
	noticeGroup.Visible = false
	corner(noticeGroup, 10)
	noticeLabel = label({
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, noticeGroup)
end

-- Serwer przysyła klucz, tekst jest w Texts.travel. Komunikat oznacza, że podróż się nie odbyła:
-- odblokowujemy przyciski, bo gracz zostaje na tym serwerze (np. teleport nie działa w Studio).
local function showNotice(key: any)
	noticeLabel.Text = Texts.travel[key] or Texts.travelDefault
	noticeGroup.Visible = true
	noticeUntil = os.clock() + Config.UI_NOTICE_TIME
	resetActions()
end

local function setRow(row: TextLabel, place: number, name: string, seconds: number?, own: boolean)
	row.Text = string.format(Texts.resultRow, place, name)
	if not arena then
		row.Text ..= "  " .. RaceFormat.time(seconds)
	end
	row.Font = if own then FONT_BOLD else FONT
	row.TextColor3 = if own then COLORS.accent else COLORS.text
	row.Visible = true
end

local function hideRows(rows: { TextLabel }, from: number)
	for i = from, #rows do
		rows[i].Visible = false
	end
end

-- Serwer może nie mieć rankingu (brak obiektu, pusty albo uszkodzony JSON): wtedy kolumna znika.
local function readTop()
	local value = ReplicatedStorage:FindFirstChild("TopTimes")
	if value == nil or not value:IsA("StringValue") or value.Value == "" then
		return {}
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(value.Value)
	end)
	return RaceFormat.parseTop(if ok then decoded else nil)
end

-- Ile osób zostaje, a ile odpływa. Solo nie ma czego pokazywać.
local function showVotes(again: number, leaving: number, undecided: number)
	local total = again + leaving + undecided
	if total <= 1 then
		votesLabel.Text = ""
	elseif leaving > 0 and leaving == total - 1 and villageButton.Active then
		votesLabel.Text = Texts.votesAlone
	else
		votesLabel.Text = string.format(Texts.votes, again, leaving, undecided)
	end
end

-- Stan medalu na ekranie wyników. `seconds` to czas gracza z RaceResults, czyli przyjęty przez serwer.
-- Atrybutu brak, gdy profil się nie wczytał: gramy bez zapisu, więc nie ma czego pokazywać.
-- MedalAwarded przychodzi przed RaceResults, a atrybut może się spóźnić, dlatego bierzemy wyższą z obu wartości.
local function showMedal(seconds: number?)
	local attribute = player:GetAttribute(Medals.ATTRIBUTE)
	if type(attribute) ~= "number" or seconds == nil or Config.RIVER_MEDALS[river.id] == nil then
		medalLabel.Text = ""
		goalLabel.Text = ""
		return
	end
	local held = math.max(attribute, awardedMedal)
	if held == 0 then
		medalLabel.Text = Texts.medalNone
		medalLabel.TextColor3 = COLORS.dim
	else
		local template = if awardedMedal > 0 then Texts.medalNew else Texts.medalHeld
		medalLabel.Text = string.format(template, Texts.medalNames[held])
		medalLabel.TextColor3 = Medals.COLORS[held]
	end
	local goal, missing = Medals.nextGoal(river.id, held, seconds)
	goalLabel.Text = if goal then string.format(Texts.medalGoal, Texts.medalNamesOf[goal], missing) else Texts.medalTop
end

local function showResults(rows: { any })
	local ownId = player.UserId
	local ownTime: number? = nil
	local shown = 0
	if type(rows) == "table" then
		for place, row in rows do
			if type(row) == "table" and row.userId == ownId then
				ownTime = row.time
			end
			if shown < RESULT_ROWS and type(row) == "table" then
				shown += 1
				setRow(resultRows[shown], place, tostring(row.name), row.time, row.userId == ownId)
			end
		end
	end
	showMedal(ownTime)
	hideRows(resultRows, shown + 1)
	if shown == 0 then
		local first = resultRows[1]
		first.Text = Texts.noResults
		first.Font = FONT
		first.TextColor3 = COLORS.dim
		first.Visible = true
	end

	local top = readTop()
	for i, entry in top do
		setRow(topRows[i], i, entry.name, entry.time, entry.userId == ownId)
	end
	hideRows(topRows, #top + 1)
	topTitle.Visible = #top > 0

	panelTitle.Text = if isNewRecord then Texts.resultsTitleRecord else Texts.resultsTitle
	resetActions()
	votesLabel.Text = ""
	panel.Visible = true
end

-- Wodna bitwa: miejsca zamiast czasów, kolumna top 10 pusta. Wiersze to { userId, name, place }, kolejność = miejsce.
local function showArenaResults(rows: any)
	local ownPlace: number? = nil
	local shown = 0
	if type(rows) == "table" then
		for index, row in rows do
			if type(row) == "table" then
				local place = if type(row.place) == "number" then row.place else index
				if row.userId == player.UserId then
					ownPlace = place
				end
				if shown < RESULT_ROWS then
					shown += 1
					setRow(resultRows[shown], place, tostring(row.name), nil, row.userId == player.UserId)
				end
			end
		end
	end
	hideRows(resultRows, shown + 1)
	medalLabel.Text = if ownPlace then string.format(Texts.arena.ownPlace, ownPlace) else ""
	medalLabel.TextColor3 = COLORS.accent
	goalLabel.Text = ""
	hideRows(topRows, 1)
	topTitle.Visible = false
	panelTitle.Text = Texts.arena.resultsTitle
	resetActions()
	votesLabel.Text = ""
	panel.Visible = true
end

local function setBig(text: string)
	if text == shownBig then
		return
	end
	shownBig = text
	bigLabel.Text = text
	if text ~= "" then
		bigScale.Scale = 1.5
		TweenService:Create(bigScale, POP, { Scale = 1 }):Play()
	end
end

local function updateCenter(now: number)
	local phase = Session.phase
	local big, message = "", ""
	if phase == "waiting" then
		message = Texts.waiting
	elseif phase == "countdown" then
		local remaining = math.ceil(Session.phaseEndsAt - now)
		if remaining <= Config.HUD_COUNTDOWN_BIG and remaining > 0 then
			big = tostring(remaining)
		elseif remaining > 0 then
			message = string.format(Texts.startIn, remaining)
		end
	elseif phase == "racing" then
		local began = Session.raceBeganAt
		if Session.state == nil then
			message = if arena then Texts.arena.nextRound else Texts.nextRace -- wszedł, gdy nie można już dołączyć, a kajaka jeszcze nie ma
		elseif Session.finishTime then
			message = string.format(Texts.finished, RaceFormat.time(Session.finishTime))
			if isNewRecord then
				message ..= " " .. Texts.newRecord
			end
		elseif began and now - began < Config.HUD_GO_TIME then
			big = Texts.go
		end
	end
	setBig(big)
	messageLabel.Text = message
end

local function raceTime(now: number): number?
	if Session.finishTime then
		return Session.finishTime
	end
	if Session.phase ~= "racing" or Session.state == nil then
		return nil
	end
	return if Session.startedAt then now - Session.startedAt else 0
end

-- Pasek trasy: postęp, kropki i (przy okazji policzone s wszystkich) miejsce gracza.
local function updateTrack()
	local state = Session.state
	local q = state and state.lastQuery
	trackGroup.Visible = q ~= nil
	if q == nil then
		return
	end
	local mine = q.s
	local progress = RaceFormat.progress(mine, startS, finishS)
	fill.Size = UDim2.fromScale(progress, 1)
	ownDot.Position = UDim2.fromScale(progress, 0.5)
	ownDot.Visible = true

	local count = 0
	for _, model in Session.kayaks do
		local hull = model.PrimaryPart
		if model ~= Session.ownModel and hull then
			local position = hull.Position
			local at = river:query(Vector2.new(position.X, position.Z), otherHints[model])
			otherHints[model] = at.index
			count += 1
			otherS[count] = at.s
			local dot = dots[count]
			if dot then
				dot.Position = UDim2.fromScale(RaceFormat.progress(at.s, startS, finishS), 0.5)
				dot.Visible = true
			end
		end
	end
	for i = count + 1, MAX_DOTS do
		dots[i].Visible = false
	end

	if Session.phase == "racing" then
		placeLabel.Text = string.format(Texts.place, RaceFormat.place(mine, otherS, count), count + 1)
	else
		placeLabel.Text = ""
	end
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	updateCenter(now)
	if not arena then
		local seconds = raceTime(now)
		timeLabel.Text = if seconds then RaceFormat.time(seconds) else ""
		updateTrack()
	end
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

function HudController.start()
	gui = make("ScreenGui", {
		Name = "Hud",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	buildTop()
	buildCenter()
	buildPanel()
	buildNotice()
	updateScale()
	if arena then
		timeLabel.Parent.Visible = false -- zegar, miejsce i rekord
		trackGroup.Visible = false
	end
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	Session.on("phase", function(phase: string)
		if phase == "countdown" then
			panel.Visible = false
			isNewRecord = false
			awardedMedal = 0
		end
	end)
	Session.on("kayakRemoved", function(model: Model)
		otherHints[model] = nil
	end)

	Remotes.get("TravelNotice").OnClientEvent:Connect(showNotice)
	if arena then
		Remotes.get("ArenaResults").OnClientEvent:Connect(showArenaResults)
	else
		Remotes.get("RaceResults").OnClientEvent:Connect(showResults)
	end
	Remotes.get("RaceVotes").OnClientEvent:Connect(showVotes)
	-- Bitwa nie ma rekordów: etykieta tylko by myliła.
	local function showRecordLabel()
		recordLabel.Visible = workspace:GetAttribute("RaceMode") ~= "battle"
	end
	workspace:GetAttributeChangedSignal("RaceMode"):Connect(showRecordLabel)
	showRecordLabel()
	Remotes.get("PersonalBest").OnClientEvent:Connect(function(best: number?, newRecord: boolean?)
		recordLabel.Text = if best then string.format(Texts.record, RaceFormat.time(best)) else Texts.noRecord
		if newRecord then
			isNewRecord = true
		end
	end)
	Remotes.get("MedalAwarded").OnClientEvent:Connect(function(_riverId: string, rank: number)
		awardedMedal = rank
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return HudController
