-- Efekty wody z gotowych pul: wszystkie części powstają raz przy starcie i nigdy nie są niszczone (telefon!). Dla TS:
-- object pool jak przy cząsteczkach w canvasie. Budżet = suma FX_* w Config (58 części + 1 emiter rozbryzgów).
--
-- Co widać: smugi nurtu płyną z River:currentAt (długość zależy od prędkości, więc prąd i wiry są czytelne), piana
-- w bystrzach i wokół skał, obracające się smugi w wirach za skałami, fala od dziobu i kilwater, rozbryzgi wioseł.
-- Pozycje idą zbiorczo przez workspace:BulkMoveTo (dużo tańsze niż pojedyncze .CFrame).
-- Stojąca woda (river.still, jezioro): bez nurtu nie ma smug, piany ani wirów, więc te pule są puste, a losowanie nie rusza.
-- Zostają fala od dziobu, kilwater i rozbryzgi wioseł.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Client = script.Parent.Parent
local KayakPose = require(Client.logic.KayakPose)
local RiverSampler = require(Client.logic.RiverSampler)
local Session = require(Client.Session)

local WaterEffects = {}

local STREAK_COLOR = Color3.fromRGB(205, 232, 245)
local FOAM_COLOR = Color3.new(1, 1, 1)
local FLAT_THICKNESS = 0.05
local DISC_ROTATION = CFrame.Angles(0, 0, math.pi / 2) -- walec ma oś X, kładziemy go płasko na wodzie
local BULK_MODE = Enum.BulkMoveMode.FireCFrameChanged
local TRANSPARENCY_STEP = 0.04 -- mniejsze zmiany przezroczystości pomijamy, zapis właściwości kosztuje
local MAX_SPAWNS_PER_FRAME = 2

type Slot = {
	part: BasePart,
	active: boolean,
	age: number,
	life: number,
	fadeIn: number,
	fadeOut: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	rotation: CFrame,
	opacity: number, -- docelowa nieprzezroczystość 0..1
	shown: number, -- ostatnio ustawiona Transparency
	-- Tylko smugi wiru: ruch po okręgu
	omega: number?,
	angle: number,
	radius: number,
	centerX: number,
	centerZ: number,
}

local rng = Random.new()
local river = Session.river
local folder: Folder = nil

local streaks: { Slot } = {}
local foam: { Slot } = {}
local eddies: { Slot } = {}
local wakes: { Slot } = {}
local pools = { streaks, foam, eddies, wakes }

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local rockSpots: { any } = {} -- skały z policzonym środkiem wiru
local nearRocks: { any } = {}

local fxLevel = 0 -- lustro wody dla następnego launch (spawn* ustawia je przed wywołaniem)
local streakBudget, foamBudget, eddyBudget = 0, 0, 0
local wakeTimer, rockTimer, braceTimer = 0, 0, 0

local spray: ParticleEmitter = nil
local sprayAttachment: Attachment = nil
local strokeSound: Sound = nil
local hitSound: Sound = nil

local function newPart(disc: boolean, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = "WaterFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = 1
	part.Shape = if disc then Enum.PartType.Cylinder else Enum.PartType.Block
	part.Size = Vector3.new(0.16, FLAT_THICKNESS, 3)
	part.Parent = folder
	return part
end

local function fillPool(pool: { Slot }, count: number, disc: boolean, color: Color3)
	for _ = 1, count do
		table.insert(pool, {
			part = newPart(disc, color),
			active = false,
			age = 0,
			life = 1,
			fadeIn = 0.2,
			fadeOut = 0.4,
			x = 0,
			z = 0,
			vx = 0,
			vz = 0,
			rotation = CFrame.identity,
			opacity = 0.5,
			shown = 1,
			omega = nil,
			angle = 0,
			radius = 0,
			centerX = 0,
			centerZ = 0,
		})
	end
end

local function acquire(pool: { Slot }): Slot?
	for _, slot in pool do
		if not slot.active then
			return slot
		end
	end
	return nil
end

local function flatRotation(dx: number, dz: number): CFrame
	return CFrame.Angles(0, math.atan2(-dx, -dz), 0)
end

-- Wspólne uruchomienie paska lub krążka; reszta (rozmiar, obrót) zależy od rodzaju.
local function launch(slot: Slot, x: number, z: number, vx: number, vz: number, life: number, opacity: number)
	slot.active = true
	slot.age = 0
	slot.life = life
	slot.fadeIn = life * 0.25
	slot.fadeOut = life * 0.4
	slot.x, slot.z = x, z
	slot.vx, slot.vz = vx, vz
	slot.opacity = opacity
	slot.omega = nil
end

local function spawnStreak(focus: Vector2, q: any)
	local slot = acquire(streaks)
	if slot == nil then
		return
	end
	-- Potęga skupia smugi bliżej gracza, gdzie są najlepiej widoczne
	local offset = -Config.FX_BEHIND + (Config.FX_AHEAD + Config.FX_BEHIND) * rng:NextNumber() ^ 1.6
	local point, at = RiverSampler.atFraction(river, q.s + offset, rng:NextNumber(-0.92, 0.92))
	if at.overshoot ~= 0 or (point - focus).Magnitude > Config.FX_RADIUS then
		return
	end
	local flow = river:currentAt(at)
	local speed = flow.Magnitude
	if speed < 0.5 then
		return
	end
	local length = math.clamp(speed * Config.FX_STREAK_PER_SPEED, Config.FX_STREAK_MIN, Config.FX_STREAK_MAX)
	local opacity = 0.3 + 0.3 * KayakPose.rapids(speed)
	fxLevel = at.level
	launch(slot, point.X, point.Y, flow.X, flow.Y, Config.FX_STREAK_LIFE * rng:NextNumber(0.8, 1.2), opacity)
	slot.rotation = flatRotation(flow.X, flow.Y)
	slot.part.Size = Vector3.new(0.16, FLAT_THICKNESS, length)
end

local function spawnFoamAt(point: Vector2, flow: Vector2, size: number, opacity: number)
	local slot = acquire(foam)
	if slot then
		launch(slot, point.X, point.Y, flow.X, flow.Y, rng:NextNumber(0.8, 1.4), opacity)
		slot.rotation = DISC_ROTATION
		slot.part.Size = Vector3.new(FLAT_THICKNESS, size, size)
	end
end

-- Pół piany przy skałach, pół w bystrzu; na spokojnej wodzie bez skał po prostu nic się nie pojawia.
local function spawnFoam(focus: Vector2, q: any)
	local count = #nearRocks
	if count > 0 and rng:NextNumber() < 0.5 then
		local rock = nearRocks[rng:NextInteger(1, count)]
		local angle = rng:NextNumber(0, 2 * math.pi)
		local point = rock.position + Vector2.new(math.cos(angle), math.sin(angle)) * (rock.radius + 0.6)
		local flow = river:currentAt(river:query(point, rock.index))
		fxLevel = rock.level
		spawnFoamAt(point, flow * 0.5, rng:NextNumber(1.2, 2.6), 0.75)
		return
	end
	local offset = -Config.FX_BEHIND + (Config.FX_AHEAD + Config.FX_BEHIND) * rng:NextNumber()
	local point, at = RiverSampler.atFraction(river, q.s + offset, rng:NextNumber(-0.95, 0.95))
	local rapids = KayakPose.rapids(at.speed)
	if at.overshoot == 0 and rapids > 0 and rng:NextNumber() < rapids and (point - focus).Magnitude <= Config.FX_RADIUS then
		fxLevel = at.level
		spawnFoamAt(point, river:currentAt(at), rng:NextNumber(1.5, 3.5), 0.45 + 0.3 * rapids)
	end
end

local function spawnEddy()
	local count = #nearRocks
	local slot = if count > 0 then acquire(eddies) else nil
	if slot == nil then
		return
	end
	local rock = nearRocks[rng:NextInteger(1, count)]
	local radius = rock.eddyRadius * rng:NextNumber(0.3, 0.95)
	fxLevel = rock.level
	launch(slot, 0, 0, 0, 0, rng:NextNumber(1.2, 1.8), 0.55)
	slot.centerX, slot.centerZ = rock.eddyCenter.X, rock.eddyCenter.Y
	slot.radius = radius
	slot.angle = rng:NextNumber(0, 2 * math.pi)
	slot.omega = rock.eddySpin / radius
	slot.part.Size = Vector3.new(0.25, FLAT_THICKNESS, math.clamp(radius * 0.9, 1, 3))
end

local function spawnWakeStrip(x: number, z: number, dx: number, dz: number, vx: number, vz: number, length: number, opacity: number)
	local slot = acquire(wakes)
	if slot then
		fxLevel = if Session.state then Session.state.height else 0
		launch(slot, x, z, vx, vz, 0.8, opacity)
		slot.rotation = flatRotation(dx, dz)
		slot.part.Size = Vector3.new(0.45, FLAT_THICKNESS, length)
	end
end

-- Fala od dziobu (dwa paski rozchodzące się na boki) i kilwater (zostaje na wodzie za rufą).
local function emitWake(position: Vector3, forward: Vector3, speed: number)
	local fx, fz = forward.X, forward.Z
	local rx, rz = -fz, fx
	local strength = math.min(speed / Config.POSE_FULL_SPEED, 1)
	local bowX, bowZ = position.X + fx * 3.5, position.Z + fz * 3.5
	local spread = speed * 0.2
	local opacity = 0.35 + 0.3 * strength
	for side = -1, 1, 2 do
		-- Pasek odchylony ~35° od kursu, płynie w bok
		local dx, dz = fx * 0.82 + rx * side * 0.57, fz * 0.82 + rz * side * 0.57
		local x, z = bowX + rx * side * 0.9, bowZ + rz * side * 0.9
		spawnWakeStrip(x, z, dx, dz, rx * side * spread, rz * side * spread, 2 + 2 * strength, opacity)
	end
	spawnWakeStrip(position.X - fx * 5, position.Z - fz * 5, fx, fz, 0, 0, 2.5 + 3 * strength, 0.25 + 0.3 * strength)
end

local function updateWakes(dt: number, cameraPosition: Vector3)
	wakeTimer += dt
	if wakeTimer < Config.FX_WAKE_INTERVAL then
		return
	end
	wakeTimer = 0
	local state = Session.state
	for _, model in Session.kayaks do
		local hull = model.PrimaryPart
		if hull and (hull.Position - cameraPosition).Magnitude <= Config.FX_RADIUS then
			local own = model == Session.ownModel and state ~= nil
			local speed = if own then state.velocity.Magnitude else hull.AssemblyLinearVelocity.Magnitude
			if speed >= Config.FX_WAKE_MIN_SPEED then
				emitWake(hull.Position, hull.CFrame.LookVector, speed)
			end
		end
	end
end

local function refreshNearRocks(s: number, focus: Vector2)
	table.clear(nearRocks)
	for _, rock in rockSpots do
		local along = rock.s - s
		if along > -Config.FX_BEHIND and along < Config.FX_AHEAD and (rock.position - focus).Magnitude <= Config.FX_RADIUS then
			table.insert(nearRocks, rock)
		end
	end
end

local function updateSlots(dt: number)
	local moved = 0
	for _, pool in pools do
		for _, slot in pool do
			if slot.active then
				slot.age += dt
				if slot.age >= slot.life then
					slot.active = false
					slot.shown = 1
					slot.part.Transparency = 1
				else
					local omega = slot.omega
					if omega then
						slot.angle += omega * dt
						local cosine, sine = math.cos(slot.angle), math.sin(slot.angle)
						slot.x = slot.centerX + cosine * slot.radius
						slot.z = slot.centerZ + sine * slot.radius
						slot.rotation = flatRotation(-sine, cosine) -- styczna do okręgu
					else
						slot.x += slot.vx * dt
						slot.z += slot.vz * dt
					end
					moved += 1
					moveParts[moved] = slot.part
					moveFrames[moved] = CFrame.new(slot.x, slot.y, slot.z) * slot.rotation

					local fade = math.min(slot.age / slot.fadeIn, (slot.life - slot.age) / slot.fadeOut, 1)
					local transparency = 1 - slot.opacity * fade
					if math.abs(transparency - slot.shown) > TRANSPARENCY_STEP then
						slot.shown = transparency
						slot.part.Transparency = transparency
					end
				end
			end
		end
	end
	for i = #moveParts, moved + 1, -1 do
		moveParts[i], moveFrames[i] = nil, nil
	end
	if moved > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, BULK_MODE)
	end
end

local function burst(position: Vector3, count: number)
	sprayAttachment.WorldPosition = position
	spray:Emit(count)
end

-- Miejsce łopaty przy kajaku.
local function bladePoint(hull: BasePart, side: number): Vector3
	local cframe = hull.CFrame
	local point = cframe.Position + cframe.RightVector * (side * 3.2) + cframe.LookVector * 0.8
	return Vector3.new(point.X, cframe.Position.Y - Config.KAYAK_RIDE_Y + Config.FX_WATER_Y, point.Z)
end

local function updateBraceSpray(dt: number)
	local state = Session.state
	local hull = Session.ownHull
	if state and hull and state.brace then
		braceTimer += dt
		if braceTimer >= Config.FX_BRACE_SPRAY_INTERVAL then
			braceTimer = 0
			burst(bladePoint(hull, state.brace), 2)
		end
	end
end

local function onPaddle(model: Model?, kind: string, side: number)
	local hull = model and model.PrimaryPart
	local camera = workspace.CurrentCamera
	if hull == nil or camera == nil or kind == "release" then
		return
	end
	if (hull.Position - camera.CFrame.Position).Magnitude > Config.FX_RADIUS then
		return
	end
	burst(bladePoint(hull, side), if kind == "brace" then 10 else 6)
	if model == Session.ownModel then
		strokeSound.PlaybackSpeed = rng:NextNumber(0.9, 1.15)
		strokeSound:Play()
	end
end

local function onHit(strength: number)
	local hull = Session.ownHull
	if hull == nil then
		return
	end
	local power = math.min(strength / Config.HIT_FULL_STRENGTH, 1)
	local position = hull.Position
	burst(position + hull.CFrame.LookVector * 3, math.floor(10 + 20 * power))
	hitSound.Volume = 0.3 + 0.5 * power
	hitSound:Play()
end

local function updateCurrentEffects(dt: number, focus: Vector2, q: any)
	rockTimer -= dt
	if rockTimer <= 0 then
		rockTimer = Config.FX_ROCKS_REFRESH
		refreshNearRocks(q.s, focus)
	end

	streakBudget = math.min(streakBudget + Config.FX_STREAK_RATE * dt, MAX_SPAWNS_PER_FRAME)
	while streakBudget >= 1 do
		streakBudget -= 1
		spawnStreak(focus, q)
	end
	foamBudget = math.min(foamBudget + Config.FX_FOAM_RATE * dt, MAX_SPAWNS_PER_FRAME)
	while foamBudget >= 1 do
		foamBudget -= 1
		spawnFoam(focus, q)
	end
	eddyBudget = math.min(eddyBudget + Config.FX_EDDY_RATE * dt, MAX_SPAWNS_PER_FRAME)
	while eddyBudget >= 1 do
		eddyBudget -= 1
		spawnEddy()
	end
end

local function frame(dt: number)
	updateSlots(dt)

	local state = Session.state
	local camera = workspace.CurrentCamera
	if state == nil or camera == nil then
		return
	end
	local q = state.lastQuery
	if q == nil then
		return
	end
	local focus = state.position

	if not river.still then
		updateCurrentEffects(dt, focus, q)
	end
	updateWakes(dt, camera.CFrame.Position)
	updateBraceSpray(dt)
end

local function createSpray()
	local anchor = Instance.new("Part")
	anchor.Name = "WaterFxSpray"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = folder

	sprayAttachment = Instance.new("Attachment")
	sprayAttachment.Parent = anchor

	spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds" -- wbudowana w klienta, bez uploadu
	spray.Rate = 0
	spray.Lifetime = NumberRange.new(0.3, 0.6)
	spray.Speed = NumberRange.new(5, 12)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.Acceleration = Vector3.new(0, -40, 0)
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.2),
	})
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Color = ColorSequence.new(Color3.new(1, 1, 1))
	spray.Parent = sprayAttachment
end

local function newSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id -- dźwięki wbudowane w klienta (te same co dźwięki postaci)
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local function prepareRocks()
	for _, rock in river.rocks do
		local radius = rock.radius * Config.EDDY_RADIUS
		local center, at = RiverSampler.at(river, rock.s + radius, rock.lateral)
		-- Wir kręci się w stronę środka rzeki, a tempo rośnie z nurtem
		local direction = if rock.lateral >= 0 then -1 else 1
		table.insert(rockSpots, {
			position = rock.position,
			radius = rock.radius,
			s = rock.s,
			index = at.index,
			eddyCenter = center,
			level = rock.level,
			eddyRadius = radius,
			eddySpin = direction * (at.speed * Config.EDDY_BACKFLOW + 2),
		})
	end
end

function WaterEffects.start()
	folder = Instance.new("Folder")
	folder.Name = "WaterFx"
	folder.Parent = workspace

	if not river.still then
		fillPool(streaks, Config.FX_STREAKS, false, STREAK_COLOR)
		fillPool(foam, Config.FX_FOAM, true, FOAM_COLOR)
		fillPool(eddies, Config.FX_EDDY, false, STREAK_COLOR)
		prepareRocks()
	end
	fillPool(wakes, Config.FX_WAKE, false, FOAM_COLOR)
	createSpray()

	strokeSound = newSound("rbxasset://sounds/action_swim.mp3", 0.25)
	hitSound = newSound("rbxasset://sounds/impact_water.mp3", 0.5)

	Session.on("paddle", onPaddle)
	Session.on("hit", onHit)
	RunService.Heartbeat:Connect(frame)
end

return WaterEffects
