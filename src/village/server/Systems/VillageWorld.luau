-- Świat wioski: jezioro, światło, domki, drzewa, ognisko, tablice i boje. Wszystko powstaje raz, w init().
-- Gracz nie chodzi, tylko pływa kajakiem, więc nic poza terenem nie ma kolizji: kajak to punkt 2D (ARCHITECTURE.md), a boje
-- do omijania liczy fizyka z LakeLayout.obstacles. Tu powstają tylko ich bryły, z tych samych danych.
-- Inne systemy biorą stąd części QueueZone z workspace.Piers (po jednej na strefę, tryb w atrybucie Mode) i
-- workspace.Boards.ResultsBoard (RiverBoards dopisuje na niej wyniki).
-- (Dla TS: moduł z efektem ubocznym `init()`, który buduje „DOM” raz przy starcie, a LakeLayout to jego dane wejściowe.)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LookAssets = require(Shared:WaitForChild("LookAssets"))
local Content = Shared:WaitForChild("content")
local LakeLayout = require(Content:WaitForChild("LakeLayout"))
local RiverCatalog = require(Content:WaitForChild("RiverCatalog"))

local VillageWorld = {}

local GROUND_TOP = 4 -- teren jak na spływie (ARCHITECTURE.md)
local GROUND_BOTTOM = -12
local CARVE_TOP = 8 -- powietrze wycinamy trochę ponad teren
local LAKE_BOTTOM = -8
local SHALLOWS_BOTTOM = -2 -- płycizna przy brzegu
local SHALLOWS_WIDTH = 10
local BEACH_LOW = 1.5 -- plaża schodzi do wody dwoma stopniami, które wygładza teren
local BEACH_HIGH = 3

local LAKE_CENTER = Vector3.new(LakeLayout.center.X, 0, LakeLayout.center.Y)
local CAMPFIRE = Vector3.new(Config.VILLAGE_CAMPFIRE_X, GROUND_TOP, Config.VILLAGE_CAMPFIRE_Z)
local SHORE = Config.VILLAGE_LAKE_RADIUS + Config.VILLAGE_BEACH_WIDTH -- tu kończy się plaża

local HILL_RADIUS = 32 -- wzgórza dookoła zasłaniają koniec mapy
local HILL_DISTANCE = 222
local HILL_STEP = 60
local HILL_CENTER_Y = -6

local HOUSE_DISTANCE = SHORE + 14 -- od środka jeziora: tuż za plażą, widać je z wody
local HOUSE_SCALE = 1.4
local TREE_RING_WIDTH = 54 -- drzewa w pasie tej szerokości za plażą
local ZONE_HEIGHT = 24 -- strefa kolejki: wysoka, obejmuje cały kajak z wioślarzem
local ZONE_BOX = 1.7 -- bok kwadratu strefy (× promień): wypełnia ring, narożniki wystają tylko trochę
local ZONE_MAST_EVERY = 5 -- co tyle boi w ringu maszt widoczny z daleka

local GRASS_COLOR = Color3.fromRGB(92, 148, 72)
local SAND_COLOR = Color3.fromRGB(214, 196, 146)
local TRUNK_COLOR = Color3.fromRGB(99, 70, 46)
local PLANK_COLOR = Color3.fromRGB(148, 110, 72)
local ORANGE_COLOR = Color3.fromRGB(244, 128, 44)
local RED_COLOR = Color3.fromRGB(224, 60, 52)
local WHITE_COLOR = Color3.fromRGB(245, 245, 240)
local POST_COLOR = Color3.fromRGB(84, 64, 48)
local STONE_COLOR = Color3.fromRGB(112, 112, 116)
local WINDOW_COLOR = Color3.fromRGB(150, 196, 214)
local BOARD_COLOR = Color3.fromRGB(28, 40, 48)
local TEXT_COLOR = Color3.fromRGB(245, 245, 240)
local MUTED_COLOR = Color3.fromRGB(150, 164, 170)
local TITLE_COLOR = Color3.fromRGB(255, 206, 84)
local DIFFICULTY_COLORS = {
	["Łatwa"] = Color3.fromRGB(98, 196, 126),
	["Średnia"] = Color3.fromRGB(236, 172, 72),
	["Trudna"] = Color3.fromRGB(232, 96, 84),
}
local LEAF_COLORS = { Color3.fromRGB(70, 128, 62), Color3.fromRGB(88, 145, 60), Color3.fromRGB(58, 112, 72) }

-- Domki wokół brzegu, frontem do jeziora. Kąt w stopniach od +X; północ (270°) zostaje wolna dla tablic przy strefach startu.
local HOUSES = {
	{ angle = 315, wall = Color3.fromRGB(196, 168, 128), roof = Color3.fromRGB(150, 74, 56) },
	{ angle = 350, wall = Color3.fromRGB(176, 144, 110), roof = Color3.fromRGB(84, 96, 112) },
	{ angle = 25, wall = Color3.fromRGB(206, 190, 160), roof = Color3.fromRGB(84, 96, 112) },
	{ angle = 58, wall = Color3.fromRGB(196, 168, 128), roof = Color3.fromRGB(128, 84, 58) },
	{ angle = 112, wall = Color3.fromRGB(176, 144, 110), roof = Color3.fromRGB(128, 84, 58) },
	{ angle = 150, wall = Color3.fromRGB(206, 190, 160), roof = Color3.fromRGB(150, 74, 56) },
	{ angle = 185, wall = Color3.fromRGB(196, 168, 128), roof = Color3.fromRGB(84, 96, 112) },
	{ angle = 225, wall = Color3.fromRGB(176, 144, 110), roof = Color3.fromRGB(150, 74, 56) },
}

local function housePosition(house: any): Vector3
	local angle = math.rad(house.angle)
	return LAKE_CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * HOUSE_DISTANCE
end

-- Część czysto ozdobna: zakotwiczona, bez kolizji, dotyku i raycastów (najtańsza dla fizyki).
local function decoration(
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	castShadow: boolean
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = castShadow
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function folder(name: string): Folder
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = workspace
	return created
end

-- ── Teren ───────────────────────────────────────────────────────────────────────────────────────────────

-- Walec terenu w jeziorze: warstwa od `bottom` do `top`.
local function fillLake(terrain: Terrain, material: Enum.Material, bottom: number, top: number, radius: number)
	local center = CFrame.new(LAKE_CENTER.X, (bottom + top) / 2, LAKE_CENTER.Z)
	terrain:FillCylinder(center, top - bottom, radius, material)
end

local function buildTerrain()
	-- Domyślna płyta i punkt pojawienia z szablonu Studio leżą na y = 0, czyli teraz w jeziorze
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, GRASS_COLOR)
	terrain:SetMaterialColor(Enum.Material.Sand, SAND_COLOR)

	local size = Config.VILLAGE_SIZE
	terrain:FillBlock(
		CFrame.new(0, (GROUND_TOP + GROUND_BOTTOM) / 2, 0),
		Vector3.new(size, GROUND_TOP - GROUND_BOTTOM, size),
		Enum.Material.Grass
	)

	-- Niecka warstwami, od największej. Wycinamy też pod lustrem: Water wypełnia tylko pustą przestrzeń i nie zastępuje piasku.
	local radius = Config.VILLAGE_LAKE_RADIUS
	local beach = Config.VILLAGE_BEACH_WIDTH
	fillLake(terrain, Enum.Material.Sand, GROUND_BOTTOM, BEACH_HIGH, radius + beach)
	fillLake(terrain, Enum.Material.Air, BEACH_HIGH, CARVE_TOP, radius + beach)
	fillLake(terrain, Enum.Material.Air, BEACH_LOW, CARVE_TOP, radius + beach / 2)
	fillLake(terrain, Enum.Material.Air, SHALLOWS_BOTTOM, CARVE_TOP, radius)
	fillLake(terrain, Enum.Material.Air, LAKE_BOTTOM, CARVE_TOP, radius - SHALLOWS_WIDTH)
	fillLake(terrain, Enum.Material.Water, LAKE_BOTTOM, 0, radius)

	-- Wzgórza dookoła: ostatnie, bo stoją poza jeziorem i nie mogą być niczym przykryte
	for offset = -HILL_STEP * 3.5, HILL_STEP * 3.5, HILL_STEP do
		for _, spot in { Vector2.new(offset, HILL_DISTANCE), Vector2.new(offset, -HILL_DISTANCE), Vector2.new(HILL_DISTANCE, offset), Vector2.new(-HILL_DISTANCE, offset) } do
			terrain:FillBall(Vector3.new(spot.X, HILL_CENTER_Y, spot.Y), HILL_RADIUS, Enum.Material.Grass)
		end
	end

	terrain.WaterColor = Color3.fromRGB(44, 128, 134)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.45
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 14
end

-- Te same wartości co RiverBuilder: wioska i spływ wyglądają jak jedno miejsce.
local function buildLighting()
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(96, 104, 112)
	Lighting.OutdoorAmbient = Color3.fromRGB(136, 146, 150)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.8

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(200, 218, 228)
	atmosphere.Decay = Color3.fromRGB(106, 130, 140)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1
	atmosphere.Parent = Lighting
end

-- ── Domki ───────────────────────────────────────────────────────────────────────────────────────────────

-- Bryła, dach, drzwi, dwa okna, komin. Dach to obrócony o 45° prostopadłościan: dolna połowa chowa się w ścianach,
-- górna daje dwuspadowy dach z jednej części. Front domku = −Z w lokalnym CFrame (tak działa CFrame.lookAt).
local function buildHouse(parent: Instance, house: any)
	local scale = HOUSE_SCALE
	local width, depth, height = 16 * scale, 12 * scale, 9 * scale
	local position = housePosition(house) + Vector3.yAxis * GROUND_TOP
	local base = CFrame.lookAt(position, Vector3.new(LAKE_CENTER.X, GROUND_TOP, LAKE_CENTER.Z))
	decoration(parent, Vector3.new(width, height + 1, depth), base * CFrame.new(0, height / 2 - 0.5, 0), house.wall, Enum.Material.WoodPlanks, true)

	local roofSide = (depth + 2) / math.sqrt(2)
	decoration(
		parent,
		Vector3.new(width - 0.1, roofSide, roofSide), -- węższy o włos: boki nie migoczą ze ścianą (z-fighting)
		base * CFrame.new(0, height, 0) * CFrame.Angles(math.pi / 4, 0, 0),
		house.roof,
		Enum.Material.Slate,
		true
	)

	local front = -depth / 2 - 0.1
	decoration(parent, Vector3.new(3, 6, 0.3) * scale, base * CFrame.new(0, 3 * scale, front), TRUNK_COLOR, Enum.Material.Wood, false)
	for _, side in { -1, 1 } do
		decoration(parent, Vector3.new(3, 2.6, 0.3) * scale, base * CFrame.new(side * 5 * scale, 5 * scale, front), WINDOW_COLOR, Enum.Material.Glass, false)
	end
	decoration(parent, Vector3.new(2, 7, 2) * scale, base * CFrame.new(width / 4, height + 4 * scale, depth / 5), STONE_COLOR, Enum.Material.Slate, false)
end

-- ── Drzewa ──────────────────────────────────────────────────────────────────────────────────────────────

-- Liściaste: pień + dwie kule korony.
local function leafyTree(parent: Instance, base: Vector3, height: number, random: Random)
	local color = LEAF_COLORS[random:NextInteger(1, #LEAF_COLORS)]
	if LookAssets.plantTree(parent, false, base, height, color, TRUNK_COLOR, random) then
		return
	end
	local width = height * 0.09
	decoration(parent, Vector3.new(width, height * 0.6, width), CFrame.new(base + Vector3.yAxis * height * 0.3), TRUNK_COLOR, Enum.Material.Wood, false)
	local crown = height * 0.62
	local top = decoration(parent, Vector3.one * crown, CFrame.new(base + Vector3.yAxis * height * 0.72), color, Enum.Material.Grass, true)
	top.Shape = Enum.PartType.Ball
	local side = Vector3.new(random:NextNumber(0.2, 1), 0, random:NextNumber(0.2, 1)).Unit * crown * 0.4
	local small = decoration(parent, Vector3.one * crown * 0.7, CFrame.new(top.CFrame.Position + side - Vector3.yAxis * crown * 0.15), color, Enum.Material.Grass, false)
	small.Shape = Enum.PartType.Ball
end

-- Iglaste: pień + trzy coraz węższe walce („stożek” schodkowy; Roblox nie ma stożka wśród prostych części).
local function pineTree(parent: Instance, base: Vector3, height: number, random: Random)
	local color = LEAF_COLORS[random:NextInteger(1, #LEAF_COLORS)]:Lerp(Color3.fromRGB(30, 70, 60), 0.4)
	if LookAssets.plantTree(parent, true, base, height, color, TRUNK_COLOR, random) then
		return
	end
	local width = height * 0.07
	decoration(parent, Vector3.new(width, height * 0.5, width), CFrame.new(base + Vector3.yAxis * height * 0.25), TRUNK_COLOR, Enum.Material.Wood, false)
	local layer = height * 0.24
	for index = 0, 2 do
		local diameter = height * (0.5 - index * 0.13)
		local center = base + Vector3.yAxis * (height * 0.3 + layer * (index + 0.5))
		-- Walec w Robloxie leży wzdłuż osi X, więc obracamy go do pionu.
		local tier = decoration(parent, Vector3.new(layer, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Grass, index == 0)
		tier.Shape = Enum.PartType.Cylinder
	end
end

-- Czy w tym miejscu może stać drzewo: nie w domku i nie w ognisku.
local function treeFits(spot: Vector3): boolean
	if (spot - Vector3.new(CAMPFIRE.X, spot.Y, CAMPFIRE.Z)).Magnitude < 16 then
		return false
	end
	for _, house in HOUSES do
		local position = housePosition(house)
		if (spot - Vector3.new(position.X, spot.Y, position.Z)).Magnitude < 22 then
			return false
		end
	end
	return true
end

-- Drzewa w pierścieniu za plażą, losowane we współrzędnych biegunowych: każde stoi blisko brzegu, więc widać je z wody.
local function buildTrees(parent: Instance, random: Random)
	local planted = 0
	for _ = 1, Config.VILLAGE_TREES * 20 do -- limit prób: po kilku chybieniach idziemy dalej, ale pętla zawsze się kończy
		if planted >= Config.VILLAGE_TREES then
			break
		end
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = random:NextNumber(SHORE + 6, SHORE + 6 + TREE_RING_WIDTH)
		local spot = LAKE_CENTER + Vector3.new(math.cos(angle) * distance, GROUND_TOP - 0.5, math.sin(angle) * distance)
		if treeFits(spot) then
			local height = random:NextNumber(20, 34)
			if random:NextNumber() < 0.5 then
				leafyTree(parent, spot, height, random)
			else
				pineTree(parent, spot, height, random)
			end
			planted += 1
		end
	end
end

-- ── Ognisko ─────────────────────────────────────────────────────────────────────────────────────────────

-- Krąg kamieni, trzy polana, ogień i światło, cztery kłody do siedzenia.
local function buildCampfire(parent: Instance)
	local center = CFrame.new(CAMPFIRE)
	for index = 1, 8 do
		local angle = index / 8 * 2 * math.pi
		decoration(parent, Vector3.new(1.4, 1, 1.4), center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.3, 3), STONE_COLOR, Enum.Material.Slate, false)
	end
	for index = 1, 3 do
		local angle = index / 3 * 2 * math.pi
		decoration(parent, Vector3.new(4, 0.7, 0.7), center * CFrame.Angles(0, angle, 0.4) * CFrame.new(0, 0.6, 0), TRUNK_COLOR, Enum.Material.Wood, false)
	end

	local core = decoration(parent, Vector3.one, center * CFrame.new(0, 1.2, 0), TRUNK_COLOR, Enum.Material.Wood, false)
	core.Transparency = 1
	local fire = Instance.new("Fire")
	fire.Size = 7
	fire.Heat = 8
	fire.Color = Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = core
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 22
	light.Brightness = 1.5
	light.Parent = core

	for index = 1, 4 do
		local angle = (index + 0.5) / 4 * 2 * math.pi
		local seat = decoration(parent, Vector3.new(7, 1.6, 1.6), center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.6, 9), TRUNK_COLOR, Enum.Material.Wood, false)
		seat.Shape = Enum.PartType.Cylinder
	end
end

-- ── Tablice ─────────────────────────────────────────────────────────────────────────────────────────────

-- Wspólna bryła obu tablic: dwa słupy, belka i deska zwrócona do punktu `facing`. Zwraca deskę, napis to SurfaceGui na jej froncie.
-- Słupy wchodzą w ziemię, bo plaża schodzi stopniami do wody.
local function buildBoard(parent: Instance, name: string, x: number, z: number, width: number, height: number, facing: Vector3): Part
	local center = Vector3.new(x, GROUND_TOP + Config.VILLAGE_BOARD_CLEARANCE + height / 2, z)
	local frame = CFrame.lookAt(center, Vector3.new(facing.X, center.Y, facing.Z))
	local board = decoration(parent, Vector3.new(width, height, 0.6), frame, POST_COLOR, Enum.Material.WoodPlanks, true)
	board.Name = name

	local postHeight = height + Config.VILLAGE_BOARD_CLEARANCE + 4
	for _, side in { -1, 1 } do
		local offset = CFrame.new(side * (width / 2 - 2), height / 2 - postHeight / 2 + 1, 0.7)
		decoration(parent, Vector3.new(1, postHeight, 1), frame * offset, POST_COLOR, Enum.Material.Wood, true)
	end
	decoration(parent, Vector3.new(width + 1.5, 0.8, 1.4), frame * CFrame.new(0, height / 2 + 0.4, 0.2), PLANK_COLOR, Enum.Material.WoodPlanks, true)
	return board
end

-- Napis na planszy rzek: tytuł i po jednym wierszu na rzekę. Lista stała, więc wystarczy ją złożyć raz.
local function buildRiverList(board: Part)
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

	local function line(text: string, x: number, y: number, width: number, height: number, color: Color3, align: Enum.TextXAlignment, font: Enum.Font)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.fromScale(x, y)
		label.Size = UDim2.fromScale(width, height)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = color
		label.TextXAlignment = align
		label.Text = text
		label.Parent = background
	end

	line("Rzeki", 0.05, 0.03, 0.9, 0.15, TITLE_COLOR, Enum.TextXAlignment.Center, Enum.Font.GothamBlack)
	line("Wpłyń w żółty lub czerwony ring i wybierz", 0.05, 0.18, 0.9, 0.07, TEXT_COLOR, Enum.TextXAlignment.Center, Enum.Font.GothamBold)
	local top, height = 0.28, 0.69 / #RiverCatalog
	for index, entry in RiverCatalog do
		local y = top + (index - 1) * height + height * 0.1
		local nameColor = if entry.available then TEXT_COLOR else MUTED_COLOR
		line(entry.label, 0.06, y, 0.56, height * 0.8, nameColor, Enum.TextXAlignment.Left, Enum.Font.GothamBold)
		line(entry.difficulty, 0.64, y, 0.3, height * 0.8, DIFFICULTY_COLORS[entry.difficulty], Enum.TextXAlignment.Right, Enum.Font.GothamBold)
	end
	gui.Parent = board
end

-- Tablica strefy: kolor ringu i ciemny napis, więc rozpoznać ją można z daleka, zanim da się przeczytać słowo.
local function buildZoneSign(parent: Instance, zone: any)
	local board = buildBoard(parent, `Sign_{zone.id}`, zone.sign.X, zone.sign.Y, LakeLayout.signWidth, LakeLayout.signHeight, LAKE_CENTER)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.VILLAGE_BOARD_PIXELS
	gui.LightInfluence = 0

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundColor3 = zone.color
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = BOARD_COLOR
	title.Text = zone.label
	title.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = title

	gui.Parent = board
end

-- Obie tablice na plaży, po bokach strefy wyścigu, zwrócone do środka jeziora: kajak widzi je od razu po starcie.
local function buildBoards(parent: Instance)
	local riverBoard = buildBoard(
		parent,
		"RiverBoard",
		Config.VILLAGE_RIVER_BOARD_X,
		Config.VILLAGE_BOARD_Z,
		Config.VILLAGE_RIVER_BOARD_WIDTH,
		Config.VILLAGE_RIVER_BOARD_HEIGHT,
		LAKE_CENTER
	)
	buildRiverList(riverBoard)

	buildBoard(
		parent,
		"ResultsBoard",
		Config.VILLAGE_RESULTS_BOARD_X,
		Config.VILLAGE_BOARD_Z,
		Config.VILLAGE_RESULTS_BOARD_WIDTH,
		Config.VILLAGE_RESULTS_BOARD_HEIGHT,
		LAKE_CENTER
	)
end

-- ── Boje i strefa startu ────────────────────────────────────────────────────────────────────────────────

local function ball(parent: Instance, diameter: number, position: Vector3, color: Color3): Part
	local part = decoration(parent, Vector3.one * diameter, CFrame.new(position), color, Enum.Material.SmoothPlastic, false)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Boja z masztem: kula na wodzie, tyczka i kuleczka na szczycie. Średnica kuli to dwa promienie z LakeLayout, czyli to samo koło, które liczy fizyka.
local function buoy(parent: Instance, position: Vector2, radius: number, color: Color3, topColor: Color3)
	local base = Vector3.new(position.X, radius * 0.3, position.Y)
	ball(parent, radius * 2, base, color)
	local mast = radius + 3
	decoration(parent, Vector3.new(0.4, mast, 0.4), CFrame.new(base + Vector3.yAxis * (radius + mast / 2 - 0.5)), POST_COLOR, Enum.Material.Wood, false)
	ball(parent, 1.4, base + Vector3.yAxis * (radius + mast), topColor)
end

local function buildBuoys(parent: Instance)
	for _, obstacle in LakeLayout.buoys do
		buoy(parent, obstacle.position, obstacle.radius, RED_COLOR:Lerp(ORANGE_COLOR, 0.6), WHITE_COLOR)
	end
	for _, gate in LakeLayout.slalom do
		buoy(parent, gate.position, gate.radius, ORANGE_COLOR, WHITE_COLOR)
	end
end

-- Ring z boi w kolorze strefy i lekko zabarwiona woda w środku. Boje ringu nie są przeszkodami: przez ring wpływa się z każdej strony.
local function buildZoneRing(parent: Instance, zone: any)
	local center = Vector3.new(zone.position.X, 0, zone.position.Y)
	local count = Config.VILLAGE_ZONE_BUOYS
	for index = 1, count do
		local angle = index / count * 2 * math.pi
		local spot = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * zone.radius
		if index % ZONE_MAST_EVERY == 0 then
			buoy(parent, Vector2.new(spot.X, spot.Z), 1.5, zone.color, zone.color)
		else
			ball(parent, 3, spot + Vector3.yAxis * 0.4, zone.color)
		end
	end

	local glow = decoration(
		parent,
		Vector3.new(0.2, zone.radius * 2, zone.radius * 2),
		CFrame.new(center + Vector3.yAxis * 0.15) * CFrame.Angles(0, 0, math.pi / 2), -- walec leży wzdłuż X, kładziemy go płasko
		zone.color,
		Enum.Material.SmoothPlastic,
		false
	)
	glow.Shape = Enum.PartType.Cylinder
	glow.Transparency = 0.8
end

-- Strefa kolejki, bezpośrednio w workspace.Piers. Prostopadłościan, bo RiverPicker i MatchService sprawdzają pudełko, a nie koło.
-- Tryb niesie atrybut Mode: wszystkie części nazywają się tak samo, a kod pyta tylko „w której stoję i jaki ma tryb”.
local function buildQueueZone(parent: Instance, zone: any)
	local side = zone.radius * ZONE_BOX
	local part = Instance.new("Part")
	part.Name = "QueueZone"
	part:SetAttribute("Mode", zone.mode)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(side, ZONE_HEIGHT, side)
	part.CFrame = CFrame.new(zone.position.X, ZONE_HEIGHT / 2 - 4, zone.position.Y)
	part.Parent = parent
end

-- ── Pojawianie się ──────────────────────────────────────────────────────────────────────────────────────

-- Punkt odrodzenia nad jeziorem. Bez kolizji i dotyku, bo nie może zatrzymywać kajaka; postać od razu siada w kajaku.
local function buildSpawn()
	local location = Instance.new("SpawnLocation")
	location.Anchored = true
	location.CanCollide = false
	location.CanTouch = false
	location.CanQuery = false
	location.CastShadow = false
	location.Neutral = true
	location.Duration = 0 -- bez pola ochronnego
	location.Transparency = 1
	location.Size = Vector3.new(8, 1, 8)
	location.CFrame = CFrame.new(LakeLayout.spawn.X, 3, LakeLayout.spawn.Y)
	location.Parent = workspace
end

function VillageWorld.init()
	buildTerrain()
	buildLighting()

	-- Stałe ziarno: wioska wygląda tak samo na każdym serwerze.
	local random = Random.new(2026)
	local houses = folder("Houses")
	for _, house in HOUSES do
		buildHouse(houses, house)
	end
	buildTrees(folder("Trees"), random)
	buildCampfire(folder("Campfire"))

	buildBoards(folder("Boards"))
	buildBuoys(folder("Buoys"))
	local startZones = folder("StartZone")
	local piers = folder("Piers")
	for _, zone in LakeLayout.zones do
		buildZoneRing(startZones, zone)
		buildZoneSign(startZones, zone)
		buildQueueZone(piers, zone)
	end
	buildSpawn()
end

return VillageWorld
