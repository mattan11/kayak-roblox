-- Duchy na ekranie: najwyżej dwa półprzezroczyste kajaki (własny rekord i rekord świata). Tylko wygląd: części są lokalne,
-- bez kolizji i poza Session.kayaks, więc KayakPhysics ich nie widzi. Ślady przysyła serwer (GhostData).
-- Zegar ducha rusza razem z Session.startedAt, czyli na linii startu tego gracza, tak samo w grupie i solo.
-- Pętla klatki nie tworzy tabel: tablice parts i targets powstają raz (dla TS: jak obiekt z puli zamiast nowego co klatkę).
-- CFrame-y są nieuniknione, bo BulkMoveTo ich wymaga; to jedyne wartości powstające w klatce.
-- Telefon: ukryty model nie ma rodzica (zero rysowania), bez cieni, a daleki duch znika. Model tworzymy dopiero przy
-- pierwszym śladzie, więc nowy gracz nie płaci za nic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GhostTrack = require(Shared:WaitForChild("GhostTrack"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Client = script.Parent.Parent
local KayakPose = require(Client.logic.KayakPose)
local Session = require(Client.Session)

local GhostController = {}

type Ghost = {
	color: Color3,
	model: Model?,
	parts: { BasePart },
	offsets: { CFrame }, -- położenie każdej części względem środka kajaka
	targets: { CFrame }, -- ta sama tablica co klatkę, argument BulkMoveTo
	track: any, -- GhostTrack.Track albo nil
	cursor: number,
	shown: boolean,
}

local function newGhost(color: Color3): Ghost
	return { color = color, model = nil, parts = {}, offsets = {}, targets = {}, track = nil, cursor = 1, shown = false }
end

local ghosts: { [string]: Ghost } = {
	own = newGhost(Config.GHOST_OWN_COLOR),
	world = newGhost(Config.GHOST_WORLD_COLOR),
}
local pool: { Ghost } = { ghosts.own, ghosts.world } -- tablica, żeby iterować bez niespodzianek
local folder: Folder

local function addPart(ghost: Ghost, class: string, size: Vector3, offset: CFrame)
	local part = Instance.new(class) :: BasePart
	part.Size = size
	part.CFrame = offset
	part.Color = ghost.color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = Config.GHOST_TRANSPARENCY
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = ghost.model
	table.insert(ghost.parts, part)
	table.insert(ghost.offsets, offset)
	table.insert(ghost.targets, offset)
end

-- Kadłub i czubki jak w KayakService.tip: dwa kliny płasko, razem trójkąt widziany z góry.
local function build(ghost: Ghost)
	if ghost.model then
		return
	end
	ghost.model = Instance.new("Model")
	local length, tipLength = Config.GHOST_HULL_LENGTH, Config.GHOST_TIP_LENGTH
	local width, height = Config.GHOST_HULL_WIDTH, Config.GHOST_HULL_HEIGHT
	addPart(ghost, "Part", Vector3.new(width, height, length), CFrame.identity)

	local tipSize = Vector3.new(height, width / 2, tipLength)
	for _, facing in { CFrame.identity, CFrame.Angles(0, math.pi, 0) } do
		for _, side in { -1, 1 } do
			local place = CFrame.fromMatrix(
				Vector3.new(side * width / 4, 0, -length / 2 - tipLength / 2),
				Vector3.new(0, -side, 0),
				Vector3.new(side, 0, 0),
				Vector3.zAxis
			)
			addPart(ghost, "WedgePart", tipSize, facing * place)
		end
	end
end

local function hide(ghost: Ghost)
	if ghost.shown then
		ghost.shown = false
		;(ghost.model :: Model).Parent = nil
	end
end

local function place(ghost: Ghost, elapsed: number, cameraPosition: Vector3)
	local track = ghost.track
	if track == nil then
		hide(ghost)
		return
	end
	local x, y, z, heading, cursor = GhostTrack.evaluate(track, elapsed, ghost.cursor)
	ghost.cursor = cursor
	if (Vector3.new(x, y, z) - cameraPosition).Magnitude > Config.GHOST_VISIBLE_RADIUS then
		hide(ghost)
		return
	end
	if not ghost.shown then
		ghost.shown = true
		;(ghost.model :: Model).Parent = folder
	end
	local root = KayakPose.cframe(x, y, z, heading, 0, 0)
	local offsets, targets = ghost.offsets, ghost.targets
	for i = 1, #offsets do
		targets[i] = root * offsets[i]
	end
	-- FireCFrameChanged to najtańszy tryb: bez zdarzeń Changed innych właściwości.
	workspace:BulkMoveTo(ghost.parts, targets, Enum.BulkMoveMode.FireCFrameChanged)
end

local function frame()
	local startedAt = Session.startedAt
	local camera = workspace.CurrentCamera
	if Session.phase ~= "racing" or not Session.active or startedAt == nil or camera == nil then
		for _, ghost in pool do
			hide(ghost)
		end
		return
	end
	local elapsed = workspace:GetServerTimeNow() - startedAt
	local cameraPosition = camera.CFrame.Position
	for _, ghost in pool do
		place(ghost, elapsed, cameraPosition)
	end
end

-- Pełna lista na ten wyścig: duch, którego w niej nie ma, znika. Serwer i tak jest źródłem prawdy, a walidacja chroni
-- pętlę klatki przed błędem w danych.
local function onGhostData(list: any)
	for _, ghost in pool do
		ghost.track = nil
	end
	if type(list) ~= "table" then
		return
	end
	for _, entry in list do
		local ghost = ghosts[entry.kind]
		if ghost and GhostTrack.validate(entry.track) then
			build(ghost)
			ghost.track, ghost.cursor = entry.track, 1
		end
	end
end

function GhostController.start()
	folder = Instance.new("Folder")
	folder.Name = "Ghosts"
	folder.Parent = workspace
	Remotes.get("GhostData").OnClientEvent:Connect(onGhostData)
	RunService.PreRender:Connect(frame)
end

return GhostController
