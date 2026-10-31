-- Przełącznik sterowania w wiosce: proste (tap po prawej = skręt w prawo) albo realistyczne (tap po prawej = wiosło po prawej).
-- Stan zna serwer: klient prosi o zmianę i pokazuje atrybut gracza. (Dla TS: kontrolowany przełącznik.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Texts = require(script.Parent.Parent.Texts)

local ControlsToggle = {}

local ATTRIBUTE = "RealisticPaddle" -- jak PlayerSettings.ATTRIBUTE; moduł serwera nie jest potrzebny klientowi

function ControlsToggle.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ControlsToggle"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4

	local button = Instance.new("TextButton")
	button.Name = "Toggle"
	button.Position = UDim2.fromOffset(12, 64)
	button.Size = UDim2.fromOffset(220, 36)
	button.BackgroundColor3 = Color3.fromRGB(16, 32, 46)
	button.BackgroundTransparency = 0.25
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 14
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local function realistic(): boolean
		return player:GetAttribute(ATTRIBUTE) == true
	end
	local function show()
		button.Text = if realistic() then Texts.controlsRealistic else Texts.controlsSimple
	end
	button.Activated:Connect(function()
		Remotes.get("SettingAction"):FireServer("realistic", not realistic())
	end)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(show)
	show()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return ControlsToggle
