-- Świat Wodnej bitwy: okrągłe jezioro, wyspy, skały, drzewa na brzegu i ściana strefy. Woła go RiverBuilder.init() zamiast
-- budowy rzeki, a system nie ma własnego init ani start. Tylko wygląd: kolizje liczy KayakPhysics (2D) z ArenaLayout.obstacles,
-- a strefę rozstrzyga ArenaRules, więc ściana jest tylko rysunkiem tego, co serwer i tak już policzył.
-- (Dla TS: czysty „renderer”: dostaje dane i rysuje, żadnej logiki gry.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ArenaBuilder = {}

local GROUND_TOP = 4 -- teren brzegu (ARCHITECTURE.md)
local GROUND_BOTTOM = -12
local WATER_BOTTOM = -8
local BEACH_TOP = 2
local CARVE_TOP = 8
local GROUND_MARGIN = 110 -- zapas gruntu za plażą

local TRUNK_COLOR = Color3.fromRGB(99, 70, 46)
local LEAF_COLOR = Color3.fromRGB(70, 128, 62)
local ROCK_COLOR = Color3.fromRGB(112, 112, 116)
local WALL_COLOR = Color3.fromRGB(255, 96, 70)

local wall: { Part } = {}
local wallCenter = Vector2.zero
local shownRadius = -math.huge

-- Część czysto ozdobna: zakotwiczona, bez kolizji, dotyku i raycastów (najtańsza dla fizyki).
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

local function folder(name: string): Folder
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = workspace
	return created
end

-- Walec terenu od `bottom` do `top` wokół punktu (x, z).
local function fillDisc(center: Vector2, radius: number, bottom: number, top: number, material: Enum.Material)
	workspace.Terrain:FillCylinder(CFrame.new(center.X, (bottom + top) / 2, center.Y), top - bottom, radius, material)
end

local function buildLake(layout: any)
	-- Domyślna płyta z szablonu Studio leży na y = 0 i przebijałaby przez wodę
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local terrain = workspace.Terrain
	local center = layout.center
	local water = layout.radius + Config.BANK_MARGIN
	local beach = water + Config.BEACH_WIDTH
	local span = (beach + GROUND_MARGIN) * 2
	terrain:FillBlock(
		CFrame.new(center.X, (GROUND_TOP + GROUND_BOTTOM) / 2, center.Y),
		Vector3.new(span, GROUND_TOP - GROUND_BOTTOM, span),
		Enum.Material.Grass
	)
	-- Kolejność jak w rzece: Water wypełnia tylko pustą przestrzeń i nie zastępuje piasku.
	fillDisc(center, beach, GROUND_BOTTOM, BEACH_TOP, Enum.Material.Sand)
	fillDisc(center, beach, BEACH_TOP, CARVE_TOP, Enum.Material.Air)
	fillDisc(center, water, WATER_BOTTOM, CARVE_TOP, Enum.Material.Air)
	fillDisc(center, water, WATER_BOTTOM, 0, Enum.Material.Water)

	terrain.WaterColor = Color3.fromRGB(44, 128, 134)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.45
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 14
end

-- Drzewo z pnia i korony. Prosty kształt: jest ich dużo, a stoją daleko od kamery.
local function tree(parent: Instance, base: Vector3, height: number)
	local width = height * 0.09
	decoration(parent, Vector3.new(width, height * 0.6, width), CFrame.new(base + Vector3.yAxis * height * 0.3), TRUNK_COLOR, Enum.Material.Wood)
	local crown = decoration(parent, Vector3.one * height * 0.62, CFrame.new(base + Vector3.yAxis * height * 0.72), LEAF_COLOR, Enum.Material.Grass)
	crown.Shape = Enum.PartType.Ball
end

-- Wyspa: piaszczysty walec o promieniu kolizji, a na nim trawa i drzewo. Piasek wchodzi w miejsce wody, więc musi iść po jeziorze.
local function buildIsland(parent: Instance, island: any)
	fillDisc(island.position, island.radius, WATER_BOTTOM, BEACH_TOP, Enum.Material.Sand)
	fillDisc(island.position, island.radius * 0.75, BEACH_TOP - 1, BEACH_TOP + 1, Enum.Material.Grass)
	tree(parent, Vector3.new(island.position.X, BEACH_TOP + 0.5, island.position.Y), island.radius)
end

-- Skała z dwóch brył. Promień kolizji = rock.radius.
local function buildRock(parent: Instance, rock: any, random: Random)
	local radius = rock.radius
	for index = 1, 2 do
		local scale = if index == 1 then 1.3 else 0.9
		local offset = if index == 1 then Vector3.zero else Vector3.new(random:NextNumber(-0.5, 0.5), 0.1, random:NextNumber(-0.5, 0.5)) * radius
		local tilt = CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 2 * math.pi), random:NextNumber(-0.4, 0.4))
		decoration(
			parent,
			Vector3.one * radius * scale,
			CFrame.new(Vector3.new(rock.position.X, 0.2, rock.position.Y) + offset) * tilt,
			ROCK_COLOR,
			Enum.Material.Slate
		)
	end
end

local function buildShore(parent: Instance, layout: any, random: Random)
	local inner = layout.radius + Config.BANK_MARGIN + Config.BEACH_WIDTH + Config.TREE_MIN_BANK_DISTANCE
	for index = 1, Config.ARENA_TREES do
		local angle = index / Config.ARENA_TREES * 2 * math.pi
		local distance = inner + random:NextNumber(0, GROUND_MARGIN - Config.TREE_MIN_BANK_DISTANCE)
		local spot = layout.center + Vector2.new(math.cos(angle), math.sin(angle)) * distance
		tree(parent, Vector3.new(spot.X, GROUND_TOP - 0.5, spot.Y), random:NextNumber(14, 26))
	end
end

-- Postać rodzi się na plaży; bez tego spadłaby do wody (KayakService zaraz sadza ją w kajaku).
local function buildSpawn(layout: any)
	local spot = layout.center + Vector2.new(0, layout.radius + Config.BANK_MARGIN + Config.BEACH_WIDTH + 12)
	local location = Instance.new("SpawnLocation")
	location.Anchored = true
	location.Neutral = true
	location.Duration = 0 -- bez pola ochronnego
	location.Transparency = 1
	location.Size = Vector3.new(8, 1, 8)
	location.CFrame = CFrame.new(spot.X, GROUND_TOP, spot.Y)
	location.Parent = workspace
end

-- Ściana strefy to pierścień z płaskich paneli: Roblox nie ma pustego walca, a pliku siatki nie wgrywamy.
local function buildWall(parent: Instance, layout: any)
	wallCenter = layout.center
	for _ = 1, Config.ARENA_WALL_SEGMENTS do
		local part = decoration(parent, Vector3.one, CFrame.identity, WALL_COLOR, Enum.Material.Neon)
		part.Transparency = 0.6
		part.CastShadow = false
		table.insert(wall, part)
	end
	ArenaBuilder.setZone(layout.radius)
end

-- Ustawia ścianę na promieniu strefy. Strefa zwęża się o ok. 1 stud/s, więc wystarczy co ARENA_WALL_STEP studs:
-- każda zmiana to replikacja wszystkich paneli do wszystkich graczy. (Dla TS: throttle na kosztownym renderze.)
function ArenaBuilder.setZone(radius: number)
	if math.abs(radius - shownRadius) < Config.ARENA_WALL_STEP then
		return
	end
	shownRadius = radius
	local count = #wall
	local height = Config.ARENA_WALL_HEIGHT
	local size = Vector3.new(2 * radius * math.sin(math.pi / count) + 0.3, height, 0.6)
	for index, part in wall do
		local angle = index / count * 2 * math.pi
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = Vector3.new(wallCenter.X, height / 2 - 2, wallCenter.Y) + outward * radius
		part.Size = size
		part.CFrame = CFrame.lookAt(at, at + outward)
	end
end

function ArenaBuilder.build(layout: any)
	buildLake(layout)
	-- Stałe ziarno: to jezioro wygląda tak samo na każdym serwerze.
	local random = Random.new(2026)
	local scenery = folder("ArenaScenery")
	for _, island in layout.islands do
		buildIsland(scenery, island)
	end
	for _, rock in layout.rocks do
		buildRock(scenery, rock, random)
	end
	buildShore(scenery, layout, random)
	buildSpawn(layout)
	buildWall(folder("ArenaZone"), layout)
end

return ArenaBuilder
