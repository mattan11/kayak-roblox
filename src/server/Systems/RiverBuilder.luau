-- Świat z danych rzeki: teren, woda, światło, skały, drzewa, bramy, miejsce pojawienia. Wszystko powstaje raz, w init().
-- Tylko wygląd: kolizje liczy KayakPhysics (2D), więc ozdoby nie mają kolizji i nie biorą udziału w raycastach.
-- Rzeka powstaje dopiero w init(), bo wybór przychodzi z MemoryStore (RaceTicket). Plik init.server.luau woła ten init()
-- jako pierwszy, więc inne systemy czytają RiverBuilder.river najwcześniej w swoim init(), nigdy przy require.
-- (Dla TS: zamiast `export const river` mamy `await loadRiver()` na starcie aplikacji, przed resztą serwisów.)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lake = require(Shared:WaitForChild("Lake"))
local LookAssets = require(Shared:WaitForChild("LookAssets"))
local River = require(Shared:WaitForChild("River"))
local ArenaLayout = require(Shared:WaitForChild("content"):WaitForChild("ArenaLayout"))

local RaceTicket = require(script.Parent.Parent.RaceTicket)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

local RiverBuilder = {}

RiverBuilder.river = nil :: any -- gotowe po init(); w trybie arena to Lake o id "Arena" (ten sam interfejs, inne systemy czytają tylko .id)
RiverBuilder.expected = nil :: number? -- ilu graczy wysłała wioska; nil = na nikogo nie czekamy (Studio, brak wpisu)
RiverBuilder.mode = "race" -- "race" | "battle" | "arena"; ostateczna wartość po init(), do klienta idzie atrybutem workspace.RaceMode

local rivers = Shared:WaitForChild("content"):WaitForChild("rivers")
local river: any = nil
local riverData: any = nil

local GROUND_TOP = 4 -- teren brzegu (ARCHITECTURE.md)
local GROUND_BOTTOM = -12
local WATER_BOTTOM = -8
local BEACH_TOP = 2
local CARVE_TOP = 8 -- powietrze wycinamy trochę ponad teren
local CARVE_STEP = 2 -- co który punkt łamanej stawiamy cylinder

local GRASS_COLOR = Color3.fromRGB(92, 148, 72)
local SAND_COLOR = Color3.fromRGB(214, 196, 146)
local TRUNK_COLOR = Color3.fromRGB(99, 70, 46)
local LEAF_COLORS = { Color3.fromRGB(70, 128, 62), Color3.fromRGB(88, 145, 60), Color3.fromRGB(58, 112, 72) }
local ROCK_COLORS = { Color3.fromRGB(112, 112, 116), Color3.fromRGB(94, 92, 96), Color3.fromRGB(128, 122, 114) }

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

-- Cylindry wzdłuż jednego odcinka rzeki: warstwa materiału od `bottom` do `top`, promień = halfWidth + margin.
local function fillSection(terrain: Terrain, section: any, material: Enum.Material, bottom: number, top: number, margin: number)
	if bottom >= top then
		return -- taras wyżej niż teren: nie ma czego wycinać
	end
	local function fill(index: number)
		local point = river.positions[index]
		local center = CFrame.new(point.X, (bottom + top) / 2, point.Y)
		terrain:FillCylinder(center, top - bottom, river.halfWidths[index] + margin, material)
	end
	for index = section.first, section.last, CARVE_STEP do
		fill(index)
	end
	fill(section.last)
end

-- Odcinki o jednym poziomie wody. Niższy odcinek zaczynamy o promień za progiem, bo jego cylindry sięgają też w górę
-- rzeki: wycięcie kończy się wtedy dokładnie na progu wodospadu.
local function sections(reach: number): { any }
	local list = {}
	for index = 1, river.vertices do
		local level = river:levelAt(river.distances[index] - river.halfWidths[index] - reach)
		local section = list[#list]
		if section == nil or section.level ~= level then
			section = { first = index, last = index, level = level }
			table.insert(list, section)
		end
		section.last = index
	end
	return list
end

local function buildTerrain()
	-- Domyślna płyta z szablonu Studio leży na y = 0 i przebijałaby przez wodę
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Enum.Material.Grass, GRASS_COLOR)
	terrain:SetMaterialColor(Enum.Material.Sand, SAND_COLOR)
	local tint = riverData.groundColor -- opcjonalnie { r, g, b }: ten sam materiał, inny krajobraz
	if tint then
		terrain:SetMaterialColor((Enum.Material :: any)[riverData.ground], Color3.fromRGB(tint[1], tint[2], tint[3]))
	end

	-- Blok gruntu: prostokąt obejmujący rzekę + zapas
	local minimum, maximum = river.positions[1], river.positions[1]
	for index, point in river.positions do
		local reach = Vector2.one * river.halfWidths[index]
		minimum = minimum:Min(point - reach)
		maximum = maximum:Max(point + reach)
	end
	local padding = Vector2.one * Config.TERRAIN_PADDING
	minimum -= padding
	maximum += padding
	local middle, span = (minimum + maximum) / 2, maximum - minimum
	local groundBottom = river.lowestLevel + GROUND_BOTTOM
	terrain:FillBlock(
		CFrame.new(middle.X, (GROUND_TOP + groundBottom) / 2, middle.Y),
		Vector3.new(span.X, GROUND_TOP - groundBottom, span.Y),
		(Enum.Material :: any)[riverData.ground or "Grass"]
	)

	-- Koryto warstwami, od góry rzeki w dół. Wycinamy też pod lustrem: Water wypełnia tylko pustą przestrzeń
	-- i nie zastępuje piasku. Sąsiednie cylindry nachodzą na siebie, więc warstwy idą całymi przebiegami.
	local bank = Config.BANK_MARGIN
	local beach = bank + (riverData.beach or Config.BEACH_WIDTH)
	local bed = (Enum.Material :: any)[riverData.bed or "Sand"]
	for _, section in sections(beach) do
		local level = section.level
		fillSection(terrain, section, bed, level + GROUND_BOTTOM, level + BEACH_TOP, beach) -- dno i plaża
		fillSection(terrain, section, Enum.Material.Air, level + BEACH_TOP, CARVE_TOP, beach) -- zdjęcie gruntu znad plaży
		fillSection(terrain, section, Enum.Material.Air, level + WATER_BOTTOM, CARVE_TOP, bank)
		fillSection(terrain, section, Enum.Material.Water, level + WATER_BOTTOM, level, bank)
		if riverData.terraces then
			-- Niżej ściana przy wodzie, wyżej coraz szerzej. Pierwszy taras jest ponad lustrem wody poprzedniego odcinka.
			fillSection(terrain, section, Enum.Material.Air, level + 10, CARVE_TOP, bank + 12)
			fillSection(terrain, section, Enum.Material.Air, level + 16, CARVE_TOP, bank + 30)
		end
	end

	-- Woda górskiej rzeki: zielono-turkusowa, trochę przejrzysta, z drobną falą
	terrain.WaterColor = Color3.fromRGB(44, 128, 134)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.45
	terrain.WaterWaveSize = riverData.waveSize or 0.12
	terrain.WaterWaveSpeed = 14
end

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

-- ── Skały ───────────────────────────────────────────────────────────────────────────────────────────────

-- Kamień z 2–3 obróconych brył: pierwsza główna, reszta mniejsza, z boku. Promień kolizji = rock.radius.
local function buildRock(parent: Instance, rock: any, random: Random)
	local radius = rock.radius
	local spot = Vector3.new(rock.position.X, rock.level + 0.2, rock.position.Y)
	if LookAssets.placeRock(parent, spot, radius, ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)], random) then
		return
	end
	for index = 1, random:NextInteger(2, 3) do
		local scale = if index == 1 then 1 else 0.7
		local size = Vector3.new(
			radius * random:NextNumber(1.1, 1.5),
			radius * random:NextNumber(1.0, 1.5),
			radius * random:NextNumber(1.1, 1.5)
		) * scale
		local offset = if index == 1
			then Vector3.zero
			else Vector3.new(random:NextNumber(-0.5, 0.5), random:NextNumber(-0.1, 0.2), random:NextNumber(-0.5, 0.5)) * radius
		local tilt = CFrame.Angles(random:NextNumber(-0.5, 0.5), random:NextNumber(0, 2 * math.pi), random:NextNumber(-0.5, 0.5))
		decoration(
			parent,
			size,
			CFrame.new(Vector3.new(rock.position.X, rock.level + 0.2, rock.position.Y) + offset) * tilt,
			ROCK_COLORS[random:NextInteger(1, #ROCK_COLORS)],
			if random:NextNumber() < 0.5 then Enum.Material.Slate else Enum.Material.Basalt,
			true
		)
	end
end

-- ── Drzewa ──────────────────────────────────────────────────────────────────────────────────────────────

-- Kolor korony z palety, opcjonalnie przesunięty w stronę barwy rzeki (`treeTint = { r, g, b }`: śnieg, złota łąka).
local function leafColor(random: Random): Color3
	local color = LEAF_COLORS[random:NextInteger(1, #LEAF_COLORS)]
	local tint = riverData.treeTint
	return if tint then color:Lerp(Color3.fromRGB(tint[1], tint[2], tint[3]), 0.75) else color
end

-- Liściaste: pień + dwie kule korony.
local function leafyTree(parent: Instance, base: Vector3, height: number, random: Random)
	local color = leafColor(random)
	if LookAssets.plantTree(parent, false, base, height, color, TRUNK_COLOR, random) then
		return
	end
	local width = height * 0.09
	decoration(parent, Vector3.new(width, height * 0.6, width), CFrame.new(base + Vector3.yAxis * height * 0.3), TRUNK_COLOR, Enum.Material.Wood, false)
	local crown = height * 0.62
	local top = decoration(parent, Vector3.one * crown, CFrame.new(base + Vector3.yAxis * height * 0.72), color, Enum.Material.Grass, true)
	top.Shape = Enum.PartType.Ball
	local side = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)).Unit * crown * 0.4
	local small = decoration(parent, Vector3.one * crown * 0.7, CFrame.new(top.CFrame.Position + side - Vector3.yAxis * crown * 0.15), color, Enum.Material.Grass, false)
	small.Shape = Enum.PartType.Ball
end

-- Iglaste: pień + trzy coraz węższe walce („stożek” schodkowy; Roblox nie ma stożka wśród prostych części).
local function pineTree(parent: Instance, base: Vector3, height: number, random: Random)
	local color = leafColor(random):Lerp(Color3.fromRGB(30, 70, 60), 0.4)
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

local function buildTrees(parent: Instance, random: Random)
	local planted = 0
	local s = 0
	while s < river.length and planted < Config.MAX_TREES do
		s += Config.TREE_SPACING
		local center = river:pointAt(s)
		local q = river:query(center)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local fromCenter = q.halfWidth + random:NextNumber(Config.TREE_MIN_BANK_DISTANCE, Config.TREE_MAX_BANK_DISTANCE)
		local spot = center + q.normal * (side * fromCenter)
		-- Pytamy o rzekę jeszcze raz, bez podpowiedzi: spot może leżeć przy sąsiednim zakolu.
		local nearest = river:query(spot)
		if math.abs(nearest.lateral) > nearest.halfWidth + Config.TREE_MIN_BANK_DISTANCE then
			local base = Vector3.new(spot.X, GROUND_TOP - 0.5, spot.Y)
			local height = random:NextNumber(14, 26)
			if not riverData.pinesOnly and random:NextNumber() < 0.5 then
				leafyTree(parent, base, height, random)
			else
				pineTree(parent, base, height, random)
			end
			planted += 1
		end
	end
end

-- ── Góry i wodospady ────────────────────────────────────────────────────────────────────────────────────

-- Skalne szczyty ze śniegiem na czubku: kule terenu poza korytem.
local function buildPeaks(random: Random)
	local terrain = workspace.Terrain
	for _ = 1, riverData.peaks or 0 do
		local center = river:pointAt(random:NextNumber(0, river.length))
		local q = river:query(center)
		local radius = random:NextNumber(30, 70)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local spot = center + q.normal * (side * (q.halfWidth + radius + random:NextNumber(12, 90)))
		local nearest = river:query(spot)
		if math.abs(nearest.lateral) > nearest.halfWidth + radius + 8 then
			local height = GROUND_TOP + radius * 0.25
			terrain:FillBall(Vector3.new(spot.X, height, spot.Y), radius, Enum.Material.Rock)
			terrain:FillBall(Vector3.new(spot.X, height + radius * 0.8, spot.Y), radius * 0.38, Enum.Material.Snow)
		end
	end
end

-- Wodospad na oko: biała zasłona wody, piana u dołu i mgiełka.
local function buildFall(parent: Instance, fall: any)
	local center = river:pointAt(fall.s)
	local q = river:query(center)
	local width = (q.halfWidth + Config.BANK_MARGIN) * 2
	local top = fall.level + fall.drop
	local forward = Vector3.new(q.tangent.X, 0, q.tangent.Y)
	local middle = Vector3.new(center.X, top - fall.drop / 2, center.Y)
	local white = Color3.fromRGB(238, 246, 250)
	local curtain = decoration(parent, Vector3.new(width, fall.drop + 1, 1.5), CFrame.lookAt(middle, middle + forward), white, Enum.Material.SmoothPlastic, false)
	curtain.Transparency = 0.06
	local foamAt = Vector3.new(center.X, fall.level + 0.5, center.Y) + forward * 6
	local foam = decoration(parent, Vector3.new(width, 0.3, 11), CFrame.lookAt(foamAt, foamAt + forward), white, Enum.Material.SmoothPlastic, false)
	foam.Transparency = 0.12

	local mist = Instance.new("ParticleEmitter")
	mist.Rate = 45
	mist.Lifetime = NumberRange.new(0.8, 1.6)
	mist.Speed = NumberRange.new(3, 7)
	mist.SpreadAngle = Vector2.new(70, 70)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Size = NumberSequence.new(3, 7)
	mist.Transparency = NumberSequence.new(0.45, 1)
	mist.LightEmission = 0.3
	mist.Parent = foam
end

-- ── Bramy ───────────────────────────────────────────────────────────────────────────────────────────────

local function bannerText(banner: Part, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = gui
	gui.Parent = banner
end

-- Brama nad rzeką: dwa słupy na brzegach i baner z napisem widocznym z obu stron.
local function buildGate(parent: Instance, s: number, text: string, color: Color3)
	local center = river:pointAt(s)
	local q = river:query(center)
	local reach = q.halfWidth + Config.BANK_MARGIN + 2
	local height = 18
	for _, side in { -1, 1 } do
		local foot = center + q.normal * (side * reach)
		local post = LookAssets.clone("GatePost")
		if post then
			post.CFrame = CFrame.new(foot.X, q.level + height / 2 - 2, foot.Y)
			post.Color = Color3.fromRGB(70, 60, 52)
			post.Parent = parent
		else
			decoration(parent, Vector3.new(1.4, height, 1.4), CFrame.new(foot.X, q.level + height / 2 - 2, foot.Y), Color3.fromRGB(70, 60, 52), Enum.Material.Wood, true)
		end
	end
	local origin = Vector3.new(center.X, q.level + height - 4, center.Y)
	local forward = Vector3.new(q.tangent.X, 0, q.tangent.Y)
	local banner = decoration(parent, Vector3.new(reach * 2, 5, 0.6), CFrame.lookAt(origin, origin + forward), color, Enum.Material.Fabric, true)
	bannerText(banner, Enum.NormalId.Front, text)
	bannerText(banner, Enum.NormalId.Back, text)
end

-- Postać rodzi się na brzegu przy starcie; bez tego spadłaby do wody (KayakService zaraz sadza ją w kajaku).
local function buildSpawn()
	local center = river:pointAt(0)
	local q = river:query(center)
	local spot = center + q.normal * (q.halfWidth + Config.BANK_MARGIN + Config.BEACH_WIDTH + 12)
	local location = Instance.new("SpawnLocation")
	location.Anchored = true
	location.Neutral = true
	location.Duration = 0 -- bez pola ochronnego
	location.Transparency = 1
	location.Size = Vector3.new(8, 1, 8)
	location.CFrame = CFrame.new(spot.X, GROUND_TOP, spot.Y)
	location.Parent = workspace
end

-- Nazwa z wpisu wioski, a gdy go nie ma albo rzeki nie znamy: Config.ACTIVE_RIVER.
local function chooseRiver()
	local function isKnown(name: string): boolean
		local module = rivers:FindFirstChild(name)
		return module ~= nil and module:IsA("ModuleScript")
	end
	local name, expected, mode = RaceTicket.parse(RaceTicket.read(), isKnown)
	RiverBuilder.expected = expected
	RiverBuilder.mode = RaceTicket.resolveMode(mode, RunService:IsStudio())
	if RiverBuilder.mode == "arena" then
		river = Lake.new(ArenaLayout)
		river.id = Config.ARENA_RIVER
	else
		riverData = require(rivers:WaitForChild(name or Config.ACTIVE_RIVER))
		river = River.new(riverData)
	end
	RiverBuilder.river = river
end

function RiverBuilder.init()
	chooseRiver()
	-- Klient buduje swoją rzekę z tego atrybutu (Session.luau). Id rzeki = nazwa pliku w content/rivers, a w trybie arena "Arena".
	workspace:SetAttribute("RiverId", river.id)
	workspace:SetAttribute("RaceMode", RiverBuilder.mode)
	local started = os.clock()
	buildLighting()
	if RiverBuilder.mode == "arena" then
		ArenaBuilder.build(ArenaLayout)
		print(string.format("[RiverBuilder] jezioro bitwy gotowe w %.1f s", os.clock() - started))
		return
	end
	buildTerrain()

	-- Stałe ziarno: ta sama rzeka wygląda tak samo na każdym serwerze.
	local random = Random.new(2026)
	local rocks = folder("Rocks")
	for _, rock in river.rocks do
		buildRock(rocks, rock, random)
	end
	buildTrees(folder("Trees"), random)
	buildPeaks(random)
	local falls = folder("Falls")
	for _, fall in river.falls do
		buildFall(falls, fall)
	end

	local gates = folder("Gates")
	buildGate(gates, Config.START_LINE, "START", Color3.fromRGB(46, 140, 84))
	buildGate(gates, river.length - Config.FINISH_MARGIN, "FINISH", Color3.fromRGB(196, 60, 52))
	buildSpawn()
	print(string.format("[RiverBuilder] %s gotowa w %.1f s", river.id, os.clock() - started)) -- VISION: czas budowy po teleporcie
end

return RiverBuilder
