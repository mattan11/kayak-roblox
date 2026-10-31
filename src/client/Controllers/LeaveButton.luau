-- Opuszczenie rzeki w trakcie gry: mały przycisk pod menu Robloxa i okno potwierdzenia.
-- Ten róg jest poza miejscem, gdzie leżą kciuki, a dotyk w przycisk nie jest wiosłowaniem (PaddleInput pomija dotyk na GUI).
-- Okno nie zatrzymuje wyścigu i zamyka się samo, więc przypadkowe kliknięcie niczego nie psuje.
-- (Dla TS: komponent z lokalnym stanem `confirming` i timeoutem.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local LeaveButton = {}

local TOP_OFFSET = Config.LEAVE_TOP_OFFSET
local COLORS = {
	panel = Color3.fromRGB(16, 32, 46),
	stay = Color3.fromRGB(255, 196, 64),
	leave = Color3.fromRGB(70, 92, 112),
	text = Color3.new(1, 1, 1),
	dark = Color3.fromRGB(16, 32, 46),
}
local TEXTS = {
	open = "Wyjdź",
	question = "Opuścić rzekę?",
	detail = "Ten przejazd się nie zaliczy.",
	stay = "Płynę dalej",
	leave = "Do wioski",
}

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(class)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function button(text: string, color: Color3, textColor: Color3, props: { [string]: any }, parent: Instance): TextButton
	local instance = make("TextButton", props, parent)
	instance.BackgroundColor3 = color
	instance.Font = Enum.Font.GothamBold
	instance.Text = text
	instance.TextColor3 = textColor
	instance.Active = true
	corner(instance, 10)
	return instance
end

function LeaveButton.start()
	local player = Players.LocalPlayer
	local gui = make("ScreenGui", {
		Name = "LeaveRiver",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	local open = button(TEXTS.open, COLORS.panel, COLORS.text, {
		Name = "Open",
		Position = UDim2.fromOffset(12, TOP_OFFSET),
		Size = UDim2.fromOffset(72, 34),
		BackgroundTransparency = 0.35,
		TextSize = 14,
	}, gui)

	local dialog = make("Frame", {
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP_OFFSET),
		Size = UDim2.fromOffset(320, 138),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.08,
		Active = true, -- dotyk w okno nie wiosłuje
		Visible = false,
	}, gui)
	corner(dialog, 12)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = TEXTS.question,
		TextColor3 = COLORS.text,
		TextSize = 20,
	}, dialog)
	make("TextLabel", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = TEXTS.detail,
		TextColor3 = COLORS.text,
		TextSize = 15,
	}, dialog)

	-- Główny przycisk to „Płynę dalej”: pomyłka zostawia gracza w wyścigu.
	local stay = button(TEXTS.stay, COLORS.stay, COLORS.dark, {
		Name = "Stay",
		Position = UDim2.fromOffset(12, 74),
		Size = UDim2.fromOffset(180, 52),
		TextSize = 17,
	}, dialog)
	local leave = button(TEXTS.leave, COLORS.leave, COLORS.text, {
		Name = "Leave",
		Position = UDim2.fromOffset(204, 74),
		Size = UDim2.fromOffset(104, 52),
		TextSize = 15,
	}, dialog)

	local openedAt = 0
	local function close()
		dialog.Visible = false
		open.Visible = true
	end

	open.Activated:Connect(function()
		dialog.Visible = true
		open.Visible = false
		local stamp = os.clock()
		openedAt = stamp
		task.delay(Config.LEAVE_CONFIRM_TIME, function()
			if openedAt == stamp and dialog.Visible then
				close()
			end
		end)
	end)
	stay.Activated:Connect(close)
	leave.Activated:Connect(function()
		close()
		Remotes.get("RaceAction"):FireServer("village")
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return LeaveButton
