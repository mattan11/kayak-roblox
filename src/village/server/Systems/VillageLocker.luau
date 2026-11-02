-- Szafka w świecie wioski: ring boi na jeziorze ze strefą LockerZone i budka na plaży z napisem i wystawionym kajakiem.
-- Miejsce i kolor są w content/LakeLayout.locker, liczby w Config. Osobny system i folder workspace.Locker, więc VillageWorld
-- zostaje bez zmian. Strefę sprawdza klient (Locker.luau); serwer jej nie potrzebuje, bo zakładanie i tak sprawdza posiadanie.
-- Wszystko bez kolizji: kajak to punkt 2D z fizyki, a boje ringu nie są przeszkodami (wpływa się z każdej strony).
-- (Dla TS: moduł, który raz przy starcie dopisuje fragment „DOM”, a dane bierze z pliku z układem.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local KayakBody = require(Shared:WaitForChild("KayakBody"))
local LakeLayout = require(Shared:WaitForChild("content"):WaitForChild("LakeLayout"))

local VillageLocker = {}

local ZONE_HEIGHT = 24 -- jak QueueZone: obejmuje cały kajak z wioślarzem
local ZONE_BOX = 1.7 -- bok kwadratu strefy (× promień)
local FLOOR_Y = 4 -- podłoga budki na wysokości trawy, na palach, bo plaża schodzi stopniami do wody
local BOOTH_WIDTH = 14
local BOOTH_DEPTH = 9
local WALL_HEIGHT = 8
local BOARD_PIXELS = 20

local PLANK_COLOR = Color3.fromRGB(148, 110, 72)
local POST_COLOR = Color3.fromRGB(84, 64, 48)
local WALL_COLOR = Color3.fromRGB(196, 168, 128)
local BOARD_COLOR = Color3.fromRGB(28, 40, 48)
local WHITE_COLOR = Color3.fromRGB(245, 245, 240)

-- Część czysto ozdobna: zakotwiczona, bez kolizji, dotyku i raycastów (jak w VillageWorld).
local function decoration(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Ring kul w kolorze szafki i lekko zabarwiona woda w środku, jak ringi stref startu.
local function buildRing(parent: Instance)
	local locker = LakeLayout.locker
	local center = Vector3.new(locker.position.X, 0, locker.position.Y)
	local count = Config.VILLAGE_LOCKER_BUOYS
	for index = 1, count do
		local angle = index / count * 2 * math.pi
		local spot = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * locker.radius
		local ball = decoration(parent, Vector3.one * 2.6, CFrame.new(spot + Vector3.yAxis * 0.4), locker.color, Enum.Material.SmoothPlastic)
		ball.Shape = Enum.PartType.Ball
		ball.CastShadow = false
	end
	local glow = decoration(
		parent,
		Vector3.new(0.2, locker.radius * 2, locker.radius * 2),
		CFrame.new(center + Vector3.yAxis * 0.15) * CFrame.Angles(0, 0, math.pi / 2), -- walec leży wzdłuż X, kładziemy go płasko
		locker.color,
		Enum.Material.SmoothPlastic
	)
	glow.Shape = Enum.PartType.Cylinder
	glow.Transparency = 0.8
	glow.CastShadow = false
end

-- Strefa: prostopadłościan, bo klient sprawdza pudełko (jak QueueZone), a nie koło.
local function buildZone(parent: Instance)
	local locker = LakeLayout.locker
	local side = locker.radius * ZONE_BOX
	local zone = Instance.new("Part")
	zone.Name = "LockerZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.CastShadow = false
	zone.Transparency = 1
	zone.Size = Vector3.new(side, ZONE_HEIGHT, side)
	zone.CFrame = CFrame.new(locker.position.X, ZONE_HEIGHT / 2 - 4, locker.position.Y)
	zone.Parent = parent
end

local function buildSign(board: Part)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = BOARD_PIXELS
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundColor3 = LakeLayout.locker.color
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = BOARD_COLOR
	title.Text = "Szafka"
	title.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = title
	gui.Parent = board
end

-- Budka frontem do jeziora (przód = −Z ramy): podłoga na palach, trzy ściany, dach, napis i klasyk na wystawie.
local function buildBooth(parent: Instance)
	local spot = LakeLayout.locker.sign
	local base = Vector3.new(spot.X, FLOOR_Y, spot.Y)
	local frame = CFrame.lookAt(base, Vector3.new(LakeLayout.center.X, FLOOR_Y, LakeLayout.center.Y))
	local halfWidth, halfDepth = BOOTH_WIDTH / 2, BOOTH_DEPTH / 2

	decoration(parent, Vector3.new(BOOTH_WIDTH, 0.8, BOOTH_DEPTH), frame * CFrame.new(0, -0.4, 0), PLANK_COLOR, Enum.Material.WoodPlanks)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			local post = CFrame.new(x * (halfWidth - 0.6), -3.5, z * (halfDepth - 0.6))
			decoration(parent, Vector3.new(0.8, 6, 0.8), frame * post, POST_COLOR, Enum.Material.Wood)
		end
	end
	local wallY = WALL_HEIGHT / 2
	decoration(parent, Vector3.new(BOOTH_WIDTH, WALL_HEIGHT, 0.6), frame * CFrame.new(0, wallY, halfDepth - 0.3), WALL_COLOR, Enum.Material.WoodPlanks)
	for _, x in { -1, 1 } do
		local wall = CFrame.new(x * (halfWidth - 0.3), wallY, 0)
		decoration(parent, Vector3.new(0.6, WALL_HEIGHT, BOOTH_DEPTH), frame * wall, WALL_COLOR, Enum.Material.WoodPlanks)
	end
	-- Dach lekko pochylony do jeziora, w kolorze ringu: widać z wody, że to ta sama rzecz.
	local roof = frame * CFrame.new(0, WALL_HEIGHT + 0.6, -0.4) * CFrame.Angles(math.rad(-8), 0, 0)
	decoration(parent, Vector3.new(BOOTH_WIDTH + 2, 0.8, BOOTH_DEPTH + 2.5), roof, LakeLayout.locker.color, Enum.Material.SmoothPlastic)
	local board = decoration(parent, Vector3.new(10, 2.6, 0.4), frame * CFrame.new(0, WALL_HEIGHT + 2, -halfDepth - 0.8), BOARD_COLOR, Enum.Material.WoodPlanks)
	buildSign(board)

	-- Wystawa: klasyk w poprzek budki, na dwóch kozłach. Części KayakBody leżą względem środka świata.
	local stand = frame * CFrame.new(0, 1.6, 1) * CFrame.Angles(0, math.pi / 2, 0)
	for _, z in { -1.8, 1.8 } do
		decoration(parent, Vector3.new(1.8, 1.1, 0.5), stand * CFrame.new(0, -0.95, z), POST_COLOR, Enum.Material.Wood)
	end
	local kayak = KayakBody.build(Cosmetics.look({ kayak = "kayak_classic", paint = "paint_sunset" }, 0))
	for _, part in KayakBody.parts(kayak) do
		part.Anchored = true
		part.CFrame = stand * part.CFrame
	end
	kayak.Name = "Display"
	kayak.Parent = parent

	-- Mała lampka nad wystawą, żeby kajak nie ginął w cieniu dachu.
	local light = Instance.new("PointLight")
	light.Color = WHITE_COLOR
	light.Range = 12
	light.Brightness = 0.8
	light.Parent = board
end

function VillageLocker.init()
	local folder = Instance.new("Folder")
	folder.Name = "Locker"
	buildRing(folder)
	buildZone(folder)
	buildBooth(folder)
	folder.Parent = workspace
end

return VillageLocker
