-- Menu ustawień w wiosce: jeden przycisk „Ustawienia”, a dopiero po kliknięciu lista opcji z opisami.
-- Stan zna serwer: klient prosi o zmianę i pokazuje atrybuty gracza. (Dla TS: kontrolowane przełączniki w rozwijanym panelu.)
-- Elementy są Active, więc dotyk na nich nie rusza wiosłem (PaddleInput dostaje `processed`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local LakeTutorial = require(script.Parent.LakeTutorial)
local Texts = require(script.Parent.Parent.Texts).settings

local ControlsToggle = {}

local PANEL_COLOR = Color3.fromRGB(16, 32, 46)
local ACCENT = Color3.fromRGB(255, 196, 70)
local WHITE = Color3.new(1, 1, 1)

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function makeButton(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Active = true
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = if color == ACCENT then PANEL_COLOR else WHITE
	button.TextSize = 14
	button.Parent = parent
	corner(button, 10)
	return button
end

local function makeLabel(parent: Instance, position: UDim2, size: UDim2, font: Enum.Font, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = WHITE
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

-- Opcja: nazwa, przycisk ze stanem i zdanie, co dokładnie robi wybrany stan.
local function addOption(panel: Frame, top: number, title: string, onClick: () -> ()): (TextButton, TextLabel)
	makeLabel(panel, UDim2.fromOffset(12, top + 8), UDim2.fromOffset(190, 20), Enum.Font.GothamBold, 15).Text = title
	local button = makeButton(panel, title, UDim2.new(1, -130, 0, top), UDim2.fromOffset(118, 34), ACCENT)
	button.Activated:Connect(onClick)
	local detail = makeLabel(panel, UDim2.fromOffset(12, top + 40), UDim2.new(1, -24, 0, 54), Enum.Font.Gotham, 13)
	return button, detail
end

function ControlsToggle.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ControlsToggle"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6

	local open = makeButton(gui, "Open", UDim2.fromOffset(12, Config.LEAVE_TOP_OFFSET), UDim2.fromOffset(120, 36), PANEL_COLOR)
	open.BackgroundTransparency = 0.25
	open.Text = Texts.open

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.Position = UDim2.fromOffset(12, Config.LEAVE_TOP_OFFSET + 42)
	panel.Size = UDim2.fromOffset(350, 262)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)

	local function isOn(attribute: string): boolean
		return player:GetAttribute(attribute) == true
	end

	local controlsButton, controlsDetail = addOption(panel, 10, Texts.controlsTitle, function()
		Remotes.get("SettingAction"):FireServer("realistic", not isOn("RealisticPaddle"))
	end)
	local ghostsButton, ghostsDetail = addOption(panel, 110, Texts.ghostsTitle, function()
		Remotes.get("SettingAction"):FireServer("hideGhosts", not isOn("HideGhosts"))
	end)

	local replay = makeButton(panel, "Replay", UDim2.new(0, 12, 1, -46), UDim2.new(1, -24, 0, 36), Color3.fromRGB(70, 92, 112))
	replay.Text = Texts.replay
	replay.Activated:Connect(function()
		panel.Visible = false
		LakeTutorial.replay()
	end)

	local function show()
		local realistic = isOn("RealisticPaddle")
		controlsButton.Text = if realistic then Texts.controlsRealistic else Texts.controlsSimple
		controlsDetail.Text = if realistic then Texts.controlsRealisticDetail else Texts.controlsSimpleDetail
		local hidden = isOn("HideGhosts")
		ghostsButton.Text = if hidden then Texts.ghostsHidden else Texts.ghostsVisible
		ghostsDetail.Text = if hidden then Texts.ghostsHiddenDetail else Texts.ghostsVisibleDetail
	end

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
	player:GetAttributeChangedSignal("RealisticPaddle"):Connect(show)
	player:GetAttributeChangedSignal("HideGhosts"):Connect(show)
	show()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return ControlsToggle
