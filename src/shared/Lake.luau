-- Jezioro: stojąca woda z tym samym interfejsem co River, więc KayakPhysics i klient nie wiedzą, po czym płyną
-- (testy: logic/Lake.spec). Dla TS: druga implementacja tego samego interfejsu.
-- Brzeg to koło: normal wskazuje od środka, lateral to odległość od środka, a halfWidth to promień. Tym samym wzorem,
-- co brzegi rzeki, KayakPhysics.collide zatrzymuje kajak na okręgu. s jest zawsze 0: jezioro nie ma „wzdłuż”,
-- dlatego przeszkody też mają s = 0 i filtr odległości w collide ich nie pomija, a zegar spływu nigdy nie rusza.

local Config = require(script.Parent.Config)

local Lake = {}
Lake.__index = Lake

export type Layout = {
	center: Vector2,
	radius: number,
	spawn: Vector2,
	heading: number,
	obstacles: { { position: Vector2, radius: number } },
}

function Lake.new(layout: Layout)
	local radius = layout.radius
	local length = radius * 2
	local self = setmetatable({
		id = "Lake",
		still = true, -- woda stoi: efekty nurtu i kamera wzdłuż rzeki nie mają tu sensu
		center = layout.center,
		radius = radius,
		spawn = layout.spawn,
		heading = layout.heading,
		length = length,
		falls = {},
		rocks = {},
		lowestLevel = 0,
		-- Dla RiverSampler: średnica jako jeden odcinek łamanej, wzdłuż osi X
		vertices = 2,
		positions = { layout.center - Vector2.new(radius, 0), layout.center + Vector2.new(radius, 0) },
		distances = { 0, length },
		tangents = { Vector2.new(1, 0) },
		halfWidths = { radius, radius },
	}, Lake)
	for _, obstacle in layout.obstacles do
		table.insert(self.rocks, { position = obstacle.position, radius = obstacle.radius, s = 0, lateral = 0, level = 0 })
	end
	return self
end

function Lake:levelAt(_s: number): number
	return 0
end

function Lake:pointAt(s: number): Vector2
	return self.positions[1] + Vector2.new(math.clamp(s, 0, self.length), 0)
end

-- `hint` jest tylko dla zgodności z River: tu wszystko liczy się wprost.
function Lake:query(position: Vector2, _hint: number?)
	local offset = position - self.center
	local distance = offset.Magnitude
	local normal = if distance > 0 then offset / distance else Vector2.new(1, 0)
	return {
		index = 1,
		s = 0,
		lateral = distance,
		tangent = Vector2.new(normal.Y, -normal.X), -- jak w River: normal = styczna obrócona w prawo
		normal = normal,
		halfWidth = self.radius,
		speed = 0,
		curvature = 0,
		level = 0,
		overshoot = 0,
	}
end

function Lake:currentAt(_q: any): Vector2
	return Vector2.zero
end

-- Miejsce startu numer `slot` (od 1): rzędy w poprzek kursu, kolejne dalej od brzegu (kurs patrzy na jezioro). Zawsze na wodzie:
-- punkt za blisko brzegu cofamy w stronę środka, a przeszkody i inne kajaki rozsuwa już fizyka.
function Lake:spawnPoint(slot: number): Vector2
	local index = (slot - 1) % Config.VILLAGE_KAYAK_SLOTS
	local columns = Config.VILLAGE_KAYAK_COLUMNS
	local spacing = Config.VILLAGE_KAYAK_SPACING
	local forward = Vector2.new(math.cos(self.heading), math.sin(self.heading))
	local right = Vector2.new(-forward.Y, forward.X)
	local across = index % columns - (columns - 1) / 2
	local point = self.spawn + right * (across * spacing) + forward * ((index // columns) * spacing)

	local offset = point - self.center
	local limit = self.radius - Config.HULL_REACH - Config.KAYAK_RADIUS - 1
	if offset.Magnitude > limit then
		return self.center + offset.Unit * limit
	end
	return point
end

return Lake
