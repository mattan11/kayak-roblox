-- Nauka pływania na jeziorze: kilka kroków, każdy zaliczany działaniem. Nowy gracz dostaje ją sam, a kto ją skończył lub
-- pominął, może ją powtórzyć przyciskiem przy ControlsToggle (LakeTutorial.replay).
-- Postęp czytamy z pozycji i kursu kajaka (workspace.Kayaks.<userId>.Hull), próbkowanych co Config.TUTORIAL_TICK. Nie
-- dotykamy fizyki ani wejścia, więc nauka nie może zablokować gry. Tylko dwa przyciski są Active, a reszta panelu
-- przepuszcza dotyk do wiosła. (Dla TS: maszyna stanów, której `update` to czysty reducer próbek pozycji.)
-- Zapamiętanie: atrybut gracza z Shared.PlayerSettings. Czekamy na SettingsLoaded, bo przed odczytem z DataStore brak
-- TutorialDone nie znaczy jeszcze „nowy gracz”. Nieudany odczyt = atrybut nie przyjdzie i nauka nie startuje sama.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LakeLayout = require(Shared:WaitForChild("content"):WaitForChild("LakeLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Texts = require(script.Parent.Parent.Texts).tutorial
local Session = require(script.Parent.Parent.Parent.Session) -- Village leży wewnątrz Client (village.project.json)

local LakeTutorial = {}

-- Te same nazwy co w PlayerSettings; moduł serwera nie jest potrzebny klientowi.
local DONE_ATTRIBUTE = "TutorialDone"
local LOADED_ATTRIBUTE = "SettingsLoaded"
local REALISTIC_ATTRIBUTE = "RealisticPaddle"

local PANEL_WIDTH = 360
local PANEL_HEIGHT = 140
local PANEL_TOP = 76 -- poniżej przycisku „Wybierz rzekę”, w pikselach projektu
local COLORS = {
	text = Color3.fromRGB(245, 248, 250),
	accent = Color3.fromRGB(255, 196, 70),
	panel = Color3.fromRGB(16, 34, 48),
	button = Color3.fromRGB(70, 190, 225),
	mark = Color3.fromRGB(255, 214, 40),
}

type Sample = { position: Vector2, heading: number, speed: number, dt: number }
type Step = { number: number, text: () -> string, update: ((Sample) -> boolean)?, target: (() -> Vector2)? }

local player = Players.LocalPlayer

local gui: ScreenGui = nil
local panel: Frame = nil
local scale: UIScale = nil
local titleLabel: TextLabel = nil
local bodyLabel: TextLabel = nil
local skipButton: TextButton = nil
local skipAllButton: TextButton = nil
local anchor: Attachment = nil
local marker: BillboardGui = nil

local stepIndex: number? = nil -- nil = nauka nie trwa
local tickTimer = 0
local lastPosition: Vector2? = nil
local lastHeading = 0
local lastSpeed = 0

-- Pamięć bieżącego kroku, zerowana przy każdym przejściu dalej.
local turned = 0 -- skręt ze znakiem, w radianach
local origin: Vector2? = nil
local braceTime = 0

local function isTouch(): boolean
	return UserInputService.TouchEnabled
end

local function isRealistic(): boolean
	return player:GetAttribute(REALISTIC_ATTRIBUTE) == true
end

-- Teksty liczone przy każdym pokazaniu: gracz może przełączyć sterowanie w trakcie nauki i opis ma się zgadzać.
local function strokeArea(): string
	return if Config.BRACE_ZONE == "bottom" then Texts.areaTop else Texts.areaBottom
end

local function turnText(direction: number): string
	-- Mapowanie jak PaddleMapping.paddleSide: zwykle dotyka się strony skrętu, a przy wiośle wskazywanym wprost strony przeciwnej.
	local side = if isRealistic() then -direction else direction
	local where = if direction == 1 then Texts.toRight else Texts.toLeft
	if isTouch() then
		return string.format(Texts.turnTouch, strokeArea(), if side == 1 then Texts.onRight else Texts.onLeft, where)
	end
	return string.format(Texts.turnKeys, if side == 1 then "D" else "A", where)
end

local function straightText(): string
	return if isTouch() then string.format(Texts.straightTouch, strokeArea()) else Texts.straightKeys
end

local function brakeText(direction: number): string
	local where = if direction == 1 then Texts.toRight else Texts.toLeft
	if isTouch() then
		local field = if Config.BRACE_ZONE == "bottom" then Texts.fieldBottom else Texts.fieldTop
		return string.format(Texts.brakeTouch, field, if direction == 1 then Texts.onRight else Texts.onLeft, where)
	end
	return string.format(Texts.brakeKeys, if direction == 1 then "E" else "Q", where)
end

local function detectTurn(direction: number): (Sample) -> boolean
	return function(_: Sample): boolean
		return turned * direction >= Config.TUTORIAL_TURN_ANGLE
	end
end

local function detectStraight(sample: Sample): boolean
	local start = origin or sample.position
	origin = start
	return (sample.position - start).Magnitude >= Config.TUTORIAL_STRAIGHT_DISTANCE
end

-- Liczymy czas trzymania wbitego wiosła po wskazanej stronie: to ono ma się liczyć, nie sam obrót.
local function detectBrake(direction: number): (Sample) -> boolean
	return function(sample: Sample): boolean
		local state = Session.state
		if state and state.brace == direction then
			braceTime += sample.dt
		end
		return braceTime >= Config.TUTORIAL_BRAKE_TIME
	end
end

local function detectZone(sample: Sample): boolean
	return (sample.position - LakeLayout.zone.position).Magnitude <= LakeLayout.zone.radius
end

local function zonePosition(): Vector2
	return LakeLayout.zone.position
end

local STEPS: { Step } = {
	{ number = 1, text = function()
		return turnText(1)
	end, update = detectTurn(1) },
	{ number = 1, text = function()
		return turnText(-1)
	end, update = detectTurn(-1) },
	{ number = 2, text = straightText, update = detectStraight },
	{ number = 3, text = function()
		return brakeText(-1)
	end, update = detectBrake(-1) },
	{ number = 3, text = function()
		return brakeText(1)
	end, update = detectBrake(1) },
	{ number = 4, text = function()
		return Texts.zone
	end, update = detectZone, target = zonePosition },
}
local STEP_COUNT = STEPS[#STEPS].number

local function resetStepMemory()
	turned = 0
	origin = nil
	braceTime = 0
end

local function render()
	local index = stepIndex
	if index == nil then
		return
	end
	local step = STEPS[index]
	titleLabel.Text = string.format(Texts.title, step.number, STEP_COUNT)
	bodyLabel.Text = step.text()
	skipButton.Text = if step.update then Texts.skip else Texts.next

	local target = step.target
	marker.Enabled = target ~= nil
	if target then
		local position = target()
		anchor.WorldPosition = Vector3.new(position.X, Config.TUTORIAL_MARKER_HEIGHT, position.Y)
	end
end

-- Zapis tylko raz: powtórka nauki nie wysyła nic, bo gracz już ma atrybut.
local function markDone()
	if player:GetAttribute(DONE_ATTRIBUTE) ~= true then
		Remotes.get("SettingAction"):FireServer("tutorialDone", true)
	end
end

local function finish(showGoodbye: boolean)
	stepIndex = nil
	marker.Enabled = false
	markDone()
	if not showGoodbye then
		panel.Visible = false
		return
	end
	titleLabel.Text = Texts.doneTitle
	bodyLabel.Text = Texts.done
	skipButton.Visible = false
	skipAllButton.Visible = false
	task.delay(Config.TUTORIAL_DONE_TIME, function()
		if stepIndex == nil then -- w tym czasie gracz mógł już kliknąć powtórkę
			panel.Visible = false
		end
	end)
end

local function advance()
	local index = stepIndex
	if index == nil then
		return
	end
	resetStepMemory()
	if index >= #STEPS then
		finish(true)
	else
		stepIndex = index + 1
		render()
	end
end

local function begin()
	if stepIndex ~= nil then
		return
	end
	stepIndex = 1
	resetStepMemory()
	lastPosition = nil
	skipButton.Visible = true
	skipAllButton.Visible = true
	panel.Visible = true
	render()
end

local function ownHull(): BasePart?
	local kayaks = workspace:FindFirstChild("Kayaks")
	local model = kayaks and kayaks:FindFirstChild(tostring(player.UserId))
	local hull = model and model:FindFirstChild("Hull")
	return if hull and hull:IsA("BasePart") then hull else nil
end

local function angleDifference(from: number, to: number): number
	local difference = to - from
	return math.atan2(math.sin(difference), math.cos(difference))
end

-- Jedna próbka co TUTORIAL_TICK. Skok pozycji (nowy kajak po respawnie) pomijamy, zamiast liczyć go jako płynięcie.
local function tick(dt: number)
	local hull = ownHull()
	if hull == nil then
		lastPosition = nil
		return
	end
	local position = Vector2.new(hull.Position.X, hull.Position.Z)
	local forward = hull.CFrame.LookVector
	local heading = math.atan2(forward.Z, forward.X) -- jak KayakPose.cframe: rosnący kurs = skręt w prawo

	local previous = lastPosition
	lastPosition = position
	if previous == nil then
		lastHeading = heading
		return
	end
	local speed = (position - previous).Magnitude / dt
	if speed > Config.MAX_KAYAK_SPEED then
		lastHeading = heading
		return
	end

	turned += angleDifference(lastHeading, heading)
	lastHeading = heading

	local index = stepIndex
	local update = index and STEPS[index].update
	if update and update({ position = position, heading = heading, speed = speed, dt = dt }) then
		advance()
	end
	lastSpeed = speed
end

local function onHeartbeat(dt: number)
	if stepIndex == nil then
		return
	end
	tickTimer += dt
	if tickTimer >= Config.TUTORIAL_TICK then
		local elapsed = tickTimer
		tickTimer = 0
		tick(elapsed)
	end
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		scale.Scale = math.min(camera.ViewportSize.Y / Config.HUD_DESIGN_HEIGHT, Config.PIER_PANEL_SCALE_MAX)
		panel.Position = UDim2.new(1, -12, 0, PANEL_TOP * scale.Scale)
	end
end

local function button(name: string, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.AnchorPoint = Vector2.new(1, 0)
	item.Position = position
	item.Size = size
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.Font = Enum.Font.GothamBold
	item.Text = text
	item.TextColor3 = COLORS.panel
	item.TextSize = 14
	item.Active = true
	item.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = item
	return item
end

local function label(position: UDim2, size: UDim2, font: Enum.Font, textSize: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Active = false
	item.Position = position
	item.Size = size
	item.BackgroundTransparency = 1
	item.Font = font
	item.TextSize = textSize
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Top
	item.TextWrapped = true
	item.Parent = panel
	return item
end

-- Panel w prawym górnym rogu: rząd przycisków leży wyżej, niż sięga kciuk trzymający telefon.
local function buildPanel()
	gui = Instance.new("ScreenGui")
	gui.Name = "LakeTutorial"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3 -- pod oknem wyboru rzeki i przełącznikiem sterowania
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = false
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	scale = Instance.new("UIScale")
	scale.Parent = panel

	titleLabel = label(UDim2.fromOffset(12, 14), UDim2.fromOffset(110, 22), Enum.Font.GothamBold, 16, COLORS.accent)
	bodyLabel = label(UDim2.fromOffset(12, 48), UDim2.new(1, -24, 0, 84), Enum.Font.GothamMedium, 16, COLORS.text)

	skipAllButton = button("SkipAll", Texts.skipAll, UDim2.fromOffset(128, 32), UDim2.new(1, -8, 0, 8), COLORS.button)
	skipButton = button("Skip", Texts.skip, UDim2.fromOffset(84, 32), UDim2.new(1, -144, 0, 8), COLORS.accent)
	skipButton.Activated:Connect(advance)
	skipAllButton.Activated:Connect(function()
		finish(false)
	end)
end

-- Znacznik nad celem kroku: obrócony kwadrat widoczny przez wszystko. Attachment w Terrain to punkt w świecie bez części.
local function buildMarker()
	anchor = Instance.new("Attachment")
	anchor.Name = "TutorialMarker"
	anchor.Parent = workspace.Terrain

	marker = Instance.new("BillboardGui")
	marker.Name = "TutorialMarker"
	marker.Adornee = anchor
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(26, 26)
	marker.Enabled = false

	local shape = Instance.new("Frame")
	shape.Active = false
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.fromScale(0.5, 0.5)
	shape.Size = UDim2.fromScale(0.7, 0.7)
	shape.Rotation = 45
	shape.BackgroundColor3 = COLORS.mark
	shape.BorderSizePixel = 0
	shape.Parent = marker
	marker.Parent = player:WaitForChild("PlayerGui")
end

-- Sama nauka tylko dla nowego: czekamy na odczyt ustawień, jak na `await` pierwszego fetcha.
local function startIfNew()
	while player:GetAttribute(LOADED_ATTRIBUTE) ~= true do
		player:GetAttributeChangedSignal(LOADED_ATTRIBUTE):Wait()
	end
	if player:GetAttribute(DONE_ATTRIBUTE) ~= true then
		begin()
	end
end

-- Przycisk „Powtórz naukę” w ControlsToggle. Moduł woła go dopiero po kliknięciu, czyli gdy panel może jeszcze powstawać.
function LakeTutorial.replay()
	if panel then
		begin()
	end
end

function LakeTutorial.start()
	buildPanel()
	buildMarker()
	updateScale()
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	player:GetAttributeChangedSignal(REALISTIC_ATTRIBUTE):Connect(render)
	RunService.Heartbeat:Connect(onHeartbeat)

	startIfNew()
end

return LakeTutorial
