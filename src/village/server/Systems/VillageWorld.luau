-- Świat wioski: teren z jeziorem, światło, domki, drzewa, ognisko, pomost, tablice, miejsce pojawienia. Wszystko powstaje raz, w init().
-- Układ: jezioro na północy (−Z), jeden szeroki pomost na jego południowym brzegu (x = 0) z planszą rzek przy wejściu,
-- plac z ogniskiem i tablicą wyników oraz domki na lądzie (+Z).
-- W przeciwieństwie do spływu postać chodzi tu po świecie, więc teren, domki, pnie i deski mają kolizje.
-- Inne systemy biorą stąd tylko workspace.Piers (jedna strefa `QueueZone`) i workspace.Boards.ResultsBoard (RiverBoards dopisuje
-- na niej wyniki). (Dla TS: moduł z efektem ubocznym `init()`, który buduje „DOM” raz przy starcie.)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RiverCatalog = require(Shared:WaitForChild("content"):WaitForChild("RiverCatalog"))

local VillageWorld = {}

local GROUND_TOP = 4 -- teren jak na spływie (ARCHITECTURE.md)
local GROUND_BOTTOM = -12
local CARVE_TOP = 8 -- powietrze wycinamy trochę ponad teren
local LAKE_BOTTOM = -8
local SHALLOWS_BOTTOM = -2 -- płycizna przy brzegu: postać sama wyjdzie z wody
local SHALLOWS_WIDTH = 10
local BEACH_LOW = 1.5 -- plaża schodzi do wody dwoma stopniami, które wygładza teren
local BEACH_HIGH = 3

local LAKE_CENTER = Vector3.new(0, 0, Config.VILLAGE_LAKE_Z)
local CAMPFIRE = Vector3.new(Config.VILLAGE_CAMPFIRE_X, GROUND_TOP, Config.VILLAGE_CAMPFIRE_Z)
local PLAZA_CENTER = Vector3.new(0, 0, Config.VILLAGE_SPAWN_Z - 12)
local PLAZA_RADIUS = 24
local PATH_WIDTH = 10

local HILL_RADIUS = 32 -- wzgórza za granicą mapy zasłaniają jej koniec
local HILL_DISTANCE = 165
local HILL_STEP = 60
local HILL_CENTER_Y = -6

local GRASS_COLOR = Color3.fromRGB(92, 148, 72)
local SAND_COLOR = Color3.fromRGB(214, 196, 146)
local DIRT_COLOR = Color3.fromRGB(150, 122, 88)
local TRUNK_COLOR = Color3.fromRGB(99, 70, 46)
local PLANK_COLOR = Color3.fromRGB(148, 110, 72)
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

-- Domki stoją frontem do placu. Układ na oko, z dala od pomostu.
local HOUSES = {
	{ x = -70, z = 88, wall = Color3.fromRGB(196, 168, 128), roof = Color3.fromRGB(150, 74, 56) },
	{ x = 70, z = 88, wall = Color3.fromRGB(176, 144, 110), roof = Color3.fromRGB(84, 96, 112) },
	{ x = -110, z = 60, wall = Color3.fromRGB(206, 190, 160), roof = Color3.fromRGB(84, 96, 112) },
	{ x = 110, z = 60, wall = Color3.fromRGB(196, 168, 128), roof = Color3.fromRGB(128, 84, 58) },
	{ x = -36, z = 126, wall = Color3.fromRGB(176, 144, 110), roof = Color3.fromRGB(128, 84, 58) },
	{ x = 36, z = 126, wall = Color3.fromRGB(206, 190, 160), roof = Color3.fromRGB(150, 74, 56) },
}

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

-- Ozdoba, po której da się chodzić albo o którą można się oprzeć.
local function solid(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, castShadow: boolean): Part
	local part = decoration(parent, size, cframe, color, material, castShadow)
	part.CanCollide = true
	part.CanQuery = true
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
	terrain:SetMaterialColor(Enum.Material.Ground, DIRT_COLOR)

	local size = Config.VILLAGE_SIZE
	terrain:FillBlock(
		CFrame.new(0, (GROUND_TOP + GROUND_BOTTOM) / 2, 0),
		Vector3.new(size, GROUND_TOP - GROUND_BOTTOM, size),
		Enum.Material.Grass
	)

	-- Plac i ścieżka do plaży: ta sama wysokość co trawa, inny materiał
	terrain:FillCylinder(CFrame.new(PLAZA_CENTER.X, GROUND_TOP / 2, PLAZA_CENTER.Z), GROUND_TOP, PLAZA_RADIUS, Enum.Material.Ground)
	local beachEdge = LAKE_CENTER.Z + Config.VILLAGE_LAKE_RADIUS + Config.VILLAGE_BEACH_WIDTH
	local pathLength = PLAZA_CENTER.Z - beachEdge
	terrain:FillBlock(
		CFrame.new(0, GROUND_TOP / 2, beachEdge + pathLength / 2),
		Vector3.new(PATH_WIDTH, GROUND_TOP, pathLength),
		Enum.Material.Ground
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
	for offset = -HILL_STEP * 2.5, HILL_STEP * 2.5, HILL_STEP do
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
	local width, depth, height = 16, 12, 9
	local position = Vector3.new(house.x, GROUND_TOP, house.z)
	local base = CFrame.lookAt(position, Vector3.new(PLAZA_CENTER.X, GROUND_TOP, PLAZA_CENTER.Z))
	solid(parent, Vector3.new(width, height + 1, depth), base * CFrame.new(0, height / 2 - 0.5, 0), house.wall, Enum.Material.WoodPlanks, true)

	local roofSide = (depth + 2) / math.sqrt(2)
	solid(
		parent,
		Vector3.new(width - 0.1, roofSide, roofSide), -- węższy o włos: boki nie migoczą ze ścianą (z-fighting)
		base * CFrame.new(0, height, 0) * CFrame.Angles(math.pi / 4, 0, 0),
		house.roof,
		Enum.Material.Slate,
		true
	)

	local front = -depth / 2 - 0.1
	decoration(parent, Vector3.new(3, 6, 0.3), base * CFrame.new(0, 3, front), TRUNK_COLOR, Enum.Material.Wood, false)
	for _, side in { -1, 1 } do
		decoration(parent, Vector3.new(3, 2.6, 0.3), base * CFrame.new(side * 5, 5, front), WINDOW_COLOR, Enum.Material.Glass, false)
	end
	decoration(parent, Vector3.new(2, 7, 2), base * CFrame.new(width / 4, height + 4, depth / 5), STONE_COLOR, Enum.Material.Slate, false)
end

-- ── Drzewa ──────────────────────────────────────────────────────────────────────────────────────────────

-- Liściaste: pień + dwie kule korony. Pień ma kolizję, korona jest ponad głowami.
local function leafyTree(parent: Instance, base: Vector3, height: number, random: Random)
	local color = LEAF_COLORS[random:NextInteger(1, #LEAF_COLORS)]
	local width = height * 0.09
	solid(parent, Vector3.new(width, height * 0.6, width), CFrame.new(base + Vector3.yAxis * height * 0.3), TRUNK_COLOR, Enum.Material.Wood, false)
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
	local width = height * 0.07
	solid(parent, Vector3.new(width, height * 0.5, width), CFrame.new(base + Vector3.yAxis * height * 0.25), TRUNK_COLOR, Enum.Material.Wood, false)
	local layer = height * 0.24
	for index = 0, 2 do
		local diameter = height * (0.5 - index * 0.13)
		local center = base + Vector3.yAxis * (height * 0.3 + layer * (index + 0.5))
		-- Walec w Robloxie leży wzdłuż osi X, więc obracamy go do pionu.
		local tier = decoration(parent, Vector3.new(layer, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Grass, index == 0)
		tier.Shape = Enum.PartType.Cylinder
	end
end

-- Czy w tym miejscu może stać drzewo: nie na plaży, nie na podejściu do pomostu, nie na placu ani w domku.
local function treeFits(spot: Vector3): boolean
	local fromLake = (spot - Vector3.new(LAKE_CENTER.X, spot.Y, LAKE_CENTER.Z)).Magnitude
	local shore = Config.VILLAGE_LAKE_RADIUS + Config.VILLAGE_BEACH_WIDTH
	if fromLake < shore + 6 then
		return false
	end
	if spot.Z > LAKE_CENTER.Z and fromLake < shore + 24 then
		return false
	end
	if (spot - Vector3.new(PLAZA_CENTER.X, spot.Y, PLAZA_CENTER.Z)).Magnitude < PLAZA_RADIUS + 8 or math.abs(spot.X) < PATH_WIDTH then
		return false
	end
	for _, house in HOUSES do
		if (spot - Vector3.new(house.x, spot.Y, house.z)).Magnitude < 18 then
			return false
		end
	end
	return true
end

local function buildTrees(parent: Instance, random: Random)
	local reach = Config.VILLAGE_BOUNDS - 6
	local planted = 0
	for _ = 1, Config.VILLAGE_TREES * 20 do -- limit prób: po kilku chybieniach idziemy dalej, ale pętla zawsze się kończy
		if planted >= Config.VILLAGE_TREES then
			break
		end
		local spot = Vector3.new(random:NextNumber(-reach, reach), GROUND_TOP - 0.5, random:NextNumber(-reach, reach))
		if treeFits(spot) then
			local height = random:NextNumber(16, 28)
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
		local seat = solid(parent, Vector3.new(7, 1.6, 1.6), center * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.6, 9), TRUNK_COLOR, Enum.Material.Wood, false)
		seat.Shape = Enum.PartType.Cylinder
	end
end

-- ── Tablice ─────────────────────────────────────────────────────────────────────────────────────────────

-- Wspólna bryła obu tablic: dwa słupy, belka i deska zwrócona do punktu `facing`. Zwraca deskę, napis to SurfaceGui na jej froncie.
-- Słupy mają kolizję, a deska jest ponad głowami. Słupy wchodzą w ziemię, bo plaża schodzi stopniami do wody.
local function buildBoard(parent: Instance, name: string, x: number, z: number, width: number, height: number, facing: Vector3): Part
	local center = Vector3.new(x, GROUND_TOP + Config.VILLAGE_BOARD_CLEARANCE + height / 2, z)
	local frame = CFrame.lookAt(center, Vector3.new(facing.X, center.Y, facing.Z))
	local board = decoration(parent, Vector3.new(width, height, 0.6), frame, POST_COLOR, Enum.Material.WoodPlanks, true)
	board.Name = name

	local postHeight = height + Config.VILLAGE_BOARD_CLEARANCE + 4
	for _, side in { -1, 1 } do
		local offset = CFrame.new(side * (width / 2 - 2), height / 2 - postHeight / 2 + 1, 0.7)
		solid(parent, Vector3.new(1, postHeight, 1), frame * offset, POST_COLOR, Enum.Material.Wood, true)
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
	line("Wejdź na pomost i wybierz", 0.05, 0.18, 0.9, 0.07, TEXT_COLOR, Enum.TextXAlignment.Center, Enum.Font.GothamBold)
	local top, height = 0.28, 0.69 / #RiverCatalog
	for index, entry in RiverCatalog do
		local y = top + (index - 1) * height + height * 0.1
		local nameColor = if entry.available then TEXT_COLOR else MUTED_COLOR
		line(entry.label, 0.06, y, 0.56, height * 0.8, nameColor, Enum.TextXAlignment.Left, Enum.Font.GothamBold)
		line(entry.difficulty, 0.64, y, 0.3, height * 0.8, DIFFICULTY_COLORS[entry.difficulty], Enum.TextXAlignment.Right, Enum.Font.GothamBold)
	end
	gui.Parent = board
end

local function buildBoards(parent: Instance)
	local riverBoard = buildBoard(
		parent,
		"RiverBoard",
		Config.VILLAGE_RIVER_BOARD_X,
		Config.VILLAGE_RIVER_BOARD_Z,
		Config.VILLAGE_RIVER_BOARD_WIDTH,
		Config.VILLAGE_RIVER_BOARD_HEIGHT,
		PLAZA_CENTER -- na wprost idącego z placu do pomostu
	)
	buildRiverList(riverBoard)

	buildBoard(
		parent,
		"ResultsBoard",
		Config.VILLAGE_RESULTS_BOARD_X,
		Config.VILLAGE_RESULTS_BOARD_Z,
		Config.VILLAGE_RESULTS_BOARD_WIDTH,
		Config.VILLAGE_RESULTS_BOARD_HEIGHT,
		Vector3.new(0, 0, Config.VILLAGE_SPAWN_Z) -- napis ma być czytelny od razu po pojawieniu się
	)
end

-- ── Pomost ──────────────────────────────────────────────────────────────────────────────────────────────

-- Kajak-ozdoba przy pomoście. Kadłub to spłaszczona kula (SpecialMesh), więc ma ostre końce przy jednej części.
local function buildKayak(parent: Instance, frame: CFrame, sideSign: number, color: Color3)
	local side = sideSign * (Config.PIER_WIDTH / 2 + 2.5)
	local moored = frame * CFrame.new(side, Config.KAYAK_RIDE_Y, -Config.PIER_LENGTH * 0.55) * CFrame.Angles(0, sideSign * 0.08, 0)
	local hull = decoration(parent, Vector3.new(2.4, 1.2, 9), moored, color, Enum.Material.SmoothPlastic, true)
	local shape = Instance.new("SpecialMesh")
	shape.MeshType = Enum.MeshType.Sphere
	shape.Parent = hull
	local cockpit = decoration(parent, Vector3.new(1.3, 0.3, 2.4), moored * CFrame.new(0, 0.5, 0), POST_COLOR, Enum.Material.SmoothPlastic, false)
	local cockpitShape = Instance.new("SpecialMesh")
	cockpitShape.MeshType = Enum.MeshType.Sphere
	cockpitShape.Parent = cockpit
	decoration(parent, Vector3.new(6, 0.18, 0.18), moored * CFrame.new(0, 0.75, 0.6), POST_COLOR, Enum.Material.Wood, false)
	for _, reach in { -3, 3 } do
		decoration(parent, Vector3.new(1, 0.1, 0.6), moored * CFrame.new(reach, 0.75, 0.6), color, Enum.Material.SmoothPlastic, false)
	end
end

-- Deski w poprzek, słupy w wodzie.
local function buildDock(parent: Instance, frame: CFrame, random: Random)
	local width = Config.PIER_WIDTH
	local length = Config.PIER_LENGTH
	local spacing = Config.PIER_PLANK_SPACING
	local y = Config.PIER_DECK_Y - 0.2
	local planks = math.floor(length / spacing)
	for index = 0, planks - 1 do
		-- Deski trzymają postać; drobne różnice koloru zastępują teksturę.
		local color = PLANK_COLOR:Lerp(POST_COLOR, random:NextNumber(0, 0.2))
		solid(parent, Vector3.new(width, 0.4, spacing - 0.1), frame * CFrame.new(0, y, -(index + 0.5) * spacing), color, Enum.Material.WoodPlanks, false)
	end
	local postHeight = Config.PIER_DECK_Y + 6
	local postY = Config.PIER_DECK_Y - postHeight / 2
	for _, along in { length * 0.5, length - 1 } do
		for _, side in { -1, 1 } do
			decoration(parent, Vector3.new(0.7, postHeight, 0.7), frame * CFrame.new(side * (width / 2 - 0.2), postY, -along), POST_COLOR, Enum.Material.Wood, false)
		end
	end
end

-- Strefa kolejki nad deskami, poza samym wejściem. Bezpośrednio w workspace.Piers: folder ma tylko tę strefę.
local function buildQueueZone(parent: Instance, frame: CFrame)
	local start = Config.PIER_QUEUE_START
	local length = Config.PIER_LENGTH - start
	local height = 8
	local zone = Instance.new("Part")
	zone.Name = "QueueZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = true
	zone.CastShadow = false
	zone.Transparency = 1
	zone.Size = Vector3.new(Config.PIER_WIDTH, height, length)
	zone.CFrame = frame * CFrame.new(0, Config.PIER_DECK_Y + height / 2 - 0.5, -(start + length / 2))
	zone.Parent = parent
end

-- Jeden pomost na osi x = 0: początek na plaży, kierunek prosto na środek jeziora (−Z).
local function buildPier(zones: Instance, docks: Instance, random: Random)
	local origin = Vector3.new(0, 0, LAKE_CENTER.Z + Config.VILLAGE_LAKE_RADIUS + Config.PIER_START_ON_BEACH)
	local frame = CFrame.lookAt(origin, Vector3.new(0, 0, LAKE_CENTER.Z))
	buildDock(docks, frame, random)
	buildKayak(docks, frame, 1, DIFFICULTY_COLORS["Łatwa"])
	buildKayak(docks, frame, -1, DIFFICULTY_COLORS["Trudna"])
	buildQueueZone(zones, frame)
end

-- ── Granice i pojawianie się ────────────────────────────────────────────────────────────────────────────

-- Niewidzialne ściany: wzgórza są za łagodne, żeby same zatrzymały postać.
local function buildBounds(parent: Instance)
	local reach = Config.VILLAGE_BOUNDS
	for _, wall in { { x = 1, z = 0 }, { x = -1, z = 0 }, { x = 0, z = 1 }, { x = 0, z = -1 } } do
		local size = if wall.x ~= 0 then Vector3.new(2, 200, reach * 2) else Vector3.new(reach * 2, 200, 2)
		local part = solid(parent, size, CFrame.new(wall.x * reach, 50, wall.z * reach), STONE_COLOR, Enum.Material.SmoothPlastic, false)
		part.Transparency = 1
	end
end

local function buildSpawn()
	local location = Instance.new("SpawnLocation")
	location.Anchored = true
	location.Neutral = true
	location.Duration = 0 -- bez pola ochronnego
	location.Transparency = 1
	location.Size = Vector3.new(8, 1, 8)
	location.CFrame = CFrame.new(0, GROUND_TOP, Config.VILLAGE_SPAWN_Z)
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

	buildPier(folder("Piers"), folder("Docks"), random)
	buildBoards(folder("Boards"))

	buildBounds(folder("Bounds"))
	buildSpawn()
end

return VillageWorld
