-- Wejście gracza: dotyk, klawiatura, pad → akcje wiosła. Mapowanie jest w logic/PaddleMapping (czyste, ze speckiem),
-- tu tylko adapter zdarzeń Robloxa i podpowiedzi pól na ekranie. Dla TS: listenery pointerdown/pointerup z mapą
-- pointerId → akcja; InputObject dotyku żyje przez całe dotknięcie, więc jest kluczem jak pointerId.
--
-- KayakController co klatkę pyta o currentBrace() i woła feedHeldStrokes(). Tylko pojedyncze tapnięcie trafia do
-- kolejki fizyki od razu.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local KayakPhysics = require(Shared:WaitForChild("KayakPhysics"))

local Client = script.Parent.Parent
local PaddleMapping = require(Client.logic.PaddleMapping)
local Session = require(Client.Session)
local Texts = require(Client.ui.Texts)

local PaddleInput = {}

local player = Players.LocalPlayer
local held = PaddleMapping.newHeld()
local touches: { [InputObject]: any } = {} -- palec → akcja wybrana przy dotknięciu
local keys: { [string]: any } = {}

local hints: ScreenGui? = nil
local uses = 0

local function fadeHints()
	local gui = hints
	if gui == nil then
		return
	end
	hints = nil
	local fade = TweenInfo.new(0.6)
	for _, item in gui:GetDescendants() do
		if item:IsA("Frame") then
			TweenService:Create(item, fade, { BackgroundTransparency = 1 }):Play()
		elseif item:IsA("TextLabel") then
			TweenService:Create(item, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		elseif item:IsA("UIStroke") then
			TweenService:Create(item, fade, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.7, function()
		gui:Destroy()
	end)
end

-- Ustawienie z wioski: atrybut gracza (Shared.PlayerSettings).
local function isRealistic(): boolean
	return player:GetAttribute("RealisticPaddle") == true
end

local function press(action: any)
	PaddleMapping.press(held, action)
	if action.kind == "stroke" and Session.active then
		KayakPhysics.requestStroke(Session.state, PaddleMapping.paddleSide(action.side, isRealistic()))
	end
	uses += 1
	if uses >= Config.HINT_USES then
		fadeHints()
	end
end

local function releaseAll()
	table.clear(touches)
	table.clear(keys)
	PaddleMapping.clear(held)
end

local function onBegan(input: InputObject, processed: boolean)
	if processed then
		return -- dotyk na przycisku HUD, pisanie na czacie
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		local camera = workspace.CurrentCamera
		if camera then
			-- Position nie liczy paska u góry ekranu, a pola podpowiedzi zajmują cały ekran
			local inset = GuiService:GetGuiInset()
			local size = camera.ViewportSize
			local action = PaddleMapping.classify(input.Position.X, input.Position.Y + inset.Y, size.X, size.Y, Config.BRACE_ZONE)
			touches[input] = action
			press(action)
		end
	else
		local name = input.KeyCode.Name
		local action = PaddleMapping.forKey(name)
		if action and keys[name] == nil then
			keys[name] = action
			press(action)
		end
	end
end

local function onEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		local action = touches[input]
		if action then
			touches[input] = nil
			PaddleMapping.release(held, action)
		end
	else
		local name = input.KeyCode.Name
		local action = keys[name]
		if action then
			keys[name] = nil
			PaddleMapping.release(held, action)
		end
	end
end

-- Kajak zastępuje postać: bez chodzenia, skoku i gałki na ekranie. PlayerModule ładuje się chwilę, a po respawnie
-- ControlModule potrafi wrócić, więc wyłączamy też przy każdej nowej postaci.
local function disableCharacterControls()
	GuiService.TouchControlsEnabled = false
	-- Rojo zarządza StarterPlayerScripts, więc PlayerModule zwykle w ogóle nie ma: wtedy nie ma też czego wyłączać.
	local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
	if module == nil then
		return
	end
	local controls = (require(module) :: any):GetControls()
	local function disable()
		controls:Disable()
	end
	disable()
	player.CharacterAdded:Connect(function()
		task.defer(disable)
	end)
end

local function addHint(parent: Instance, position: UDim2, title: string, detail: string)
	local cell = Instance.new("Frame")
	cell.Name = "Hint"
	cell.Active = false
	cell.Position = position
	cell.Size = UDim2.fromScale(0.5, 0.5)
	cell.BackgroundColor3 = Color3.new(1, 1, 1)
	cell.BackgroundTransparency = 0.92
	cell.BorderSizePixel = 0
	cell.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.7
	stroke.Parent = cell

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = if detail ~= "" then `{title}\n{detail}` else title
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextTransparency = 0.25
	label.TextStrokeTransparency = 0.6
	label.TextSize = 18
	label.Parent = cell
end

local function createHints()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PaddleHints"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1

	local touch = UserInputService.TouchEnabled
	local braceTop = Config.BRACE_ZONE == "top"
	local strokeY, braceY = if braceTop then 0.5 else 0, if braceTop then 0 else 0.5
	addHint(gui, UDim2.fromScale(0, strokeY), Texts.hintStrokeLeft, if touch then "" else Texts.hintKeysStrokeLeft)
	addHint(gui, UDim2.fromScale(0.5, strokeY), Texts.hintStrokeRight, if touch then "" else Texts.hintKeysStrokeRight)
	addHint(gui, UDim2.fromScale(0, braceY), Texts.hintBrace, if touch then "" else Texts.hintKeysBraceLeft)
	addHint(gui, UDim2.fromScale(0.5, braceY), Texts.hintBrace, if touch then "" else Texts.hintKeysBraceRight)

	gui.Parent = player:WaitForChild("PlayerGui")
	hints = gui
end

function PaddleInput.start()
	UserInputService.InputBegan:Connect(onBegan)
	UserInputService.InputEnded:Connect(onEnded)
	-- Po utracie okna InputEnded nie przychodzi: bez tego klawisz „trzymałby się” w nieskończoność
	UserInputService.WindowFocusReleased:Connect(releaseAll)
	createHints()
	disableCharacterControls()
end

-- Strona, po której wiosło powinno być teraz wbite (nil = nigdzie).
function PaddleInput.currentBrace(): number?
	return PaddleMapping.braceSide(held)
end

-- Przytrzymanie: następne machnięcie dokładamy dopiero, gdy poprzednie się skończy. Inaczej zwykłe kliknięcie, które
-- trwa kilka klatek, trafiłoby do kolejki drugi raz i jedno kliknięcie dałoby dwa machnięcia.
function PaddleInput.feedHeldStrokes(state: any)
	if state.queued == nil and state.strokeSide == nil then
		local side = PaddleMapping.nextHeldStroke(held)
		if side then
			KayakPhysics.requestStroke(state, PaddleMapping.paddleSide(side, isRealistic()))
		end
	end
end

return PaddleInput
