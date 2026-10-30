-- Panel kolejki pomostu: nazwa rzeki, trudność, „3/8, start za 25 s”, przyciski „Płyń teraz” i „Zejdź”, plus TravelNotice.
-- Serwer rozgłasza stan KAŻDEGO pomostu (PierState), a klient sam sprawdza po pozycji, na którym stoi
-- (dla TS: globalny store z websocketa + selektor po `currentPierId`).
-- Układ w pikselach dla wysokości telefonu, UIScale dopasowuje go do ekranu, jak w HudController.
-- Panel stoi między gałką ruchu (dół, lewo) a przyciskiem skoku (dół, prawo). Tylko przyciski są Active.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Piers = require(Shared:WaitForChild("content"):WaitForChild("Piers"))

local Texts = require(script.Parent.Parent.Texts)

local PierHud = {}

local COLORS = {
	text = Color3.fromRGB(245, 248, 250),
	dim = Color3.fromRGB(190, 205, 215),
	accent = Color3.fromRGB(255, 196, 70),
	panel = Color3.fromRGB(16, 34, 48),
	fill = Color3.fromRGB(70, 190, 225),
}
local FONT_BOLD = Enum.Font.GothamBold
local PANEL_HEIGHT = 122

type PierInfo = { count: number, endsAt: number? }

local player = Players.LocalPlayer

local gui: ScreenGui = nil
local panelScale: UIScale = nil
local noticeScale: UIScale = nil
local panel: Frame = nil
local titleLabel: TextLabel = nil
local statusLabel: TextLabel = nil
local noticeGroup: Frame = nil
local noticeLabel: TextLabel = nil

local piers: { [string]: PierInfo } = {} -- ostatni PierState każdego pomostu
local pierData: { [string]: any } = {} -- pierId → wpis z content/Piers (nazwa i trudność)
local currentPier: string? = nil -- pomost, na którym stoi gracz (po pozycji)
local leftPier: string? = nil -- kliknął „Zejdź”: panel wraca dopiero po wyjściu ze strefy
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

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local height = camera.ViewportSize.Y / Config.HUD_DESIGN_HEIGHT
		panelScale.Scale = math.min(height, Config.PIER_PANEL_SCALE_MAX)
		noticeScale.Scale = math.min(height, Config.HUD_SCALE_MAX)
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
		Name = "Pier",
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
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 17,
		Text = "",
	}, panel)

	actionButton(Texts.pierGo, 0, COLORS.accent, function()
		if currentPier then
			Remotes.get("PierAction"):FireServer("go", currentPier)
		end
	end)
	actionButton(Texts.pierLeave, 1, COLORS.fill, function()
		if currentPier then
			leftPier = currentPier
			panel.Visible = false
			Remotes.get("PierAction"):FireServer("leave", currentPier)
		end
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

local function showNotice(key: any)
	noticeLabel.Text = Texts.travel[key] or Texts.travelDefault
	noticeGroup.Visible = true
	noticeUntil = os.clock() + Config.UI_NOTICE_TIME
end

-- Pomost pod graczem albo nil. Ta sama próba co PierService na serwerze: pozycja w układzie strefy kontra pół rozmiaru.
local function pierAt(position: Vector3): string?
	local folder = workspace:FindFirstChild("Piers")
	if folder == nil then
		return nil
	end
	for _, zone in folder:GetChildren() do
		if zone:IsA("BasePart") and zone.Name == "QueueZone" then
			local inside = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(inside.X) <= half.X and math.abs(inside.Y) <= half.Y and math.abs(inside.Z) <= half.Z then
				local pierId = zone:GetAttribute("PierId")
				return if type(pierId) == "string" then pierId else nil
			end
		end
	end
	return nil
end

local function ownPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function refresh()
	local position = ownPosition()
	currentPier = if position then pierAt(position) else nil
	if leftPier ~= currentPier then
		leftPier = nil -- jak `refused` na serwerze: zszedł ze strefy, więc może wrócić do kolejki
	end

	local id = currentPier
	local info = if id then piers[id] else nil
	local data = if id then pierData[id] else nil
	local visible = info ~= nil and data ~= nil and info.count > 0 and leftPier == nil
	panel.Visible = visible
	if visible and info and data then
		titleLabel.Text = string.format(Texts.pierTitle, data.label, data.difficulty)
		local endsAt = info.endsAt
		if endsAt then
			local remaining = math.max(math.ceil(endsAt - workspace:GetServerTimeNow()), 0)
			statusLabel.Text = string.format(Texts.pierStatus, info.count, Config.PIER_CAPACITY, remaining)
		else
			statusLabel.Text = string.format(Texts.pierWaiting, info.count, Config.PIER_CAPACITY)
		end
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

function PierHud.start()
	for _, pier in Piers do
		pierData[pier.id] = pier
	end

	gui = make("ScreenGui", {
		Name = "PierHud",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	buildPanel()
	buildNotice()
	updateScale()
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	Remotes.get("PierState").OnClientEvent:Connect(function(pierId: string, count: number, endsAt: number?)
		piers[pierId] = { count = count, endsAt = endsAt }
	end)
	Remotes.get("TravelNotice").OnClientEvent:Connect(showNotice)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return PierHud
