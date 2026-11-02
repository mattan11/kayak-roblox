-- Kajaki graczy: szkielet z części, skóra z KayakBody, posadzenie w Seat, własność sieciowa, echo wiosła. Kontrakt nazw: ARCHITECTURE.md.
-- Wygląd (skórka i kolor) ustawia setLook po wczytaniu profilu; do tego czasu kajak ma wygląd domyślny (COSMETICS.md, sekcja 6).
-- Kajak jest jeden na gracza i wraca przy nowym wyścigu (place). Sterowanie to dwa sztywne Align z celem, który
-- ustawia klient, a serwer ustawia cel tylko przy rozstawieniu. Przód kajaka = −Z modelu (jak LookVector),
-- czyli orientacja to CFrame.lookAt(pozycja, pozycja + (cos heading, 0, sin heading)).
-- Pętla pilnująca sprawdza każdego gracza co pół sekundy: siedzi w swoim kajaku? Jedno miejsce załatwia respawn,
-- wyskoczenie z fotela i późne wczytanie postaci. (Dla TS: reconcile loop, jak w Reacie/Kubernetesie, zamiast
-- osobnych handlerów na każde zdarzenie.)

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local KayakBody = require(Shared:WaitForChild("KayakBody"))
local LookAssets = require(Shared:WaitForChild("LookAssets"))
local Places = require(Shared:WaitForChild("Places"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local KayakService = {}

local KAYAK_Y = 0.3 -- nad lustrem wody (y = 0)
local CHECK_INTERVAL = 0.5
local COLLISION_GROUP = "Kayakers" -- postacie w kajakach nie zderzają się ze sobą (zderzenia liczy KayakPhysics)

local HULL_LENGTH = KayakBody.HULL_LENGTH
local HULL_WIDTH = KayakBody.HULL_WIDTH
local HULL_HEIGHT = KayakBody.HULL_HEIGHT

local PADDLE_KINDS = { stroke = true, brace = true, release = true }

local kayaks: { [Player]: Model } = {}
local looks: { [Player]: Cosmetics.Look } = {} -- wygląd z profilu; brak = domyślny dla userId
local container: Folder

-- Każda część poza Hull: bez kolizji i bez masy (ARCHITECTURE.md). Hull też bez kolizji: ruch liczy fizyka 2D.
local function shell(model: Model, class: string, name: string, size: Vector3, cframe: CFrame, color: Color3): any
	local part = Instance.new(class) :: any
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Parent = model
	return part
end

local function weld(part0: BasePart, part1: BasePart)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = part0
	joint.Part1 = part1
	joint.Parent = part1
end

-- W Studio Config.STUDIO_KAYAK podmienia skórkę na spływie (test szablonu bez szafki). W wiosce nie, żeby dało się sprawdzić szafkę.
local function resolveLook(look: Cosmetics.Look): Cosmetics.Look
	local override = Config.STUDIO_KAYAK
	if override and RunService:IsStudio() and Places.current().id == "race" then
		return { template = override, color = nil, classicColor = look.classicColor }
	end
	return look
end

-- Skóra na niewidocznym Hull: stary folder Look precz, nowy spawany do Hull w jego bieżącym położeniu.
-- Części KayakBody leżą tak, jakby Hull stał w środku świata, więc wystarczy je przemnożyć przez CFrame Hull.
local function attachLook(model: Model, look: Cosmetics.Look)
	local hull = model.PrimaryPart :: BasePart
	local old = model:FindFirstChild(KayakBody.NAME)
	if old then
		old:Destroy()
	end
	local body = KayakBody.build(resolveLook(look))
	for _, part in KayakBody.parts(body) do
		part.Anchored = false
		part.CFrame = hull.CFrame * part.CFrame
		weld(hull, part)
	end
	body.Parent = model
end

-- Model budowany w środku świata, bez rodzica. Wołający ustawia go przez PivotTo.
function KayakService.build(userId: number, look: Cosmetics.Look?): Model
	local model = Instance.new("Model")
	model.Name = tostring(userId)
	model:SetAttribute("Finished", false)
	local dark = Color3.fromRGB(34, 36, 40)

	-- Hull to szkielet: zawsze niewidoczny, rozmiar bez zmian. Widać skórę z KayakBody.
	local hull = shell(model, "Part", "Hull", Vector3.new(HULL_WIDTH, HULL_HEIGHT, HULL_LENGTH), CFrame.identity, dark)
	hull.Massless = false
	hull.Transparency = 1
	hull.RootPriority = 127 -- korzeniem złożenia zostaje Hull, także gdy siądzie w nim postać
	model.PrimaryPart = hull
	attachLook(model, look or Cosmetics.look(nil, userId))

	local seat = shell(model, "Seat", "Seat", Vector3.new(1.3, 0.2, 1.3), CFrame.new(0, HULL_HEIGHT / 2 + 0.1, 0.2), dark)
	seat.Transparency = 1
	seat.CanTouch = true -- fotel w Robloxie opiera się na zdarzeniach dotyku
	weld(hull, seat)

	-- Wiosło: drążek wzdłuż X (walec Robloxa tak leży), obraca nim klient przez PaddleJoint.
	local paddleAt = CFrame.new(0, 2, -0.9)
	local paddle = shell(model, "Part", "Paddle", Vector3.new(6, 0.2, 0.2), paddleAt, Color3.fromRGB(200, 200, 205))
	paddle.Shape = Enum.PartType.Cylinder
	local paddleLook = LookAssets.clone("Paddle")
	if paddleLook then
		paddle.Transparency = 1
		paddleLook.Name = "PaddleLook"
		paddleLook.Parent = model
		paddleLook:PivotTo(paddleAt)
		for _, part in paddleLook:GetChildren() do
			part.Anchored = false
			weld(paddle, part)
		end
	else
		for _, side in { -1, 1 } do
			local blade = shell(model, "Part", "Blade", Vector3.new(1, 0.6, 0.08), paddleAt * CFrame.new(side * 3.3, 0, 0), dark)
			weld(paddle, blade)
		end
	end
	local joint = Instance.new("Motor6D")
	joint.Name = "PaddleJoint"
	joint.Part0 = hull
	joint.Part1 = paddle
	joint.C0 = paddleAt
	joint.Parent = hull

	local root = Instance.new("Attachment")
	root.Name = "Root"
	root.Parent = hull

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = root
	alignPosition.RigidityEnabled = true
	alignPosition.Parent = hull

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = root
	alignOrientation.RigidityEnabled = true
	alignOrientation.Parent = hull

	return model
end

-- Posadzenie, jeśli jeszcze nie siedzi. Bez postaci (albo gdy martwa) nic nie robi: pętla spróbuje znowu.
local function seatPlayer(player: Player, kayak: Model)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not character.PrimaryPart then
		return
	end
	local seat = kayak:FindFirstChild("Seat") :: Seat
	if seat.Occupant == humanoid then
		return
	end
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP
		end
	end
	character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	seat:Sit(humanoid)
	-- Nowe złożenie (kajak + postać): własność trzeba potwierdzić, inaczej przejąłby je serwer.
	local hull = kayak.PrimaryPart :: BasePart
	hull:SetNetworkOwner(player)
end

-- Kajak gracza albo nil.
function KayakService.get(player: Player): Model?
	return kayaks[player]
end

-- Stawia kajak gracza (tworzy, jeśli go nie ma) w punkcie, nieruchomo. Ten sam kajak wraca przy każdym wyścigu.
function KayakService.place(player: Player, position: Vector2, heading: number)
	local kayak = kayaks[player]
	local isNew = kayak == nil
	if not kayak then
		kayak = KayakService.build(player.UserId, looks[player])
		kayaks[player] = kayak
	end
	local hull = (kayak :: Model).PrimaryPart :: any

	local at = Vector3.new(position.X, KAYAK_Y, position.Y)
	local pose = CFrame.lookAt(at, at + Vector3.new(math.cos(heading), 0, math.sin(heading)))
	hull.AlignPosition.Position = at
	hull.AlignOrientation.CFrame = pose
	kayak:SetAttribute("Finished", false)
	kayak:PivotTo(pose)
	if isNew then
		kayak.Parent = container
	end
	hull:SetNetworkOwner(player) -- wymaga części w workspace, stąd dopiero po Parent
	seatPlayer(player, kayak)
end

-- Wygląd z profilu (Cosmetics.look). Kajak, który już pływa, od razu zmienia skórę; nowy dostanie ją w place().
-- Nowe części w złożeniu: własność sieciową trzeba potwierdzić, inaczej przejąłby ją serwer (szarpnięcie kajaka).
function KayakService.setLook(player: Player, look: Cosmetics.Look)
	looks[player] = look
	local kayak = kayaks[player]
	if kayak == nil then
		return
	end
	attachLook(kayak, look)
	local hull = kayak.PrimaryPart :: BasePart
	if hull:IsDescendantOf(workspace) then
		hull:SetNetworkOwner(player)
	end
end

-- Gracz na mecie: klient przestaje sterować.
function KayakService.setFinished(player: Player)
	local kayak = kayaks[player]
	if kayak then
		kayak:SetAttribute("Finished", true)
	end
end

function KayakService.init()
	container = Instance.new("Folder")
	container.Name = "Kayaks"
	container.Parent = workspace

	if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

	-- Wiosło: tylko animacja u innych, ale klientowi i tak nie ufamy (limit + sprawdzenie typów i zakresów).
	-- Nadawca niczego z powrotem nie dostaje: swoje wiosło animuje sam.
	local echo = Remotes.get("PaddleEcho") :: any
	Remotes.onServer("Paddle", 8, 12, function(player: Player, kind: any, side: any)
		if not PADDLE_KINDS[kind] or not kayaks[player] then
			return
		end
		local validSide = side == 1 or side == -1 or (kind == "release" and side == nil)
		if not validSide then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				echo:FireClient(other, player.UserId, kind, side)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local kayak = kayaks[player]
		kayaks[player] = nil
		looks[player] = nil
		if kayak then
			kayak:Destroy()
		end
	end)
end

function KayakService.start()
	while true do
		task.wait(CHECK_INTERVAL)
		for player, kayak in kayaks do
			seatPlayer(player, kayak)
		end
	end
end

return KayakService
