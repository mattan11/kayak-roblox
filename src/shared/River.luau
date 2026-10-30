-- Rzeka jako dane i geometria — czysta logika, bez Instance (testy: logic/River.spec).
-- Wszystko w 2D: Vector2(x, z). Punkty kontrolne wygładzamy krzywą Catmull-Rom do gęstej łamanej, a pozycję
-- gracza opisujemy współrzędnymi „rzecznymi”: s = ile przepłynął wzdłuż, lateral = ile w bok od środka.
-- (Dla TS: klasa z prekomputowanymi tablicami; query to „znajdź najbliższy odcinek” jak na mapie GPS.)

local Config = require(script.Parent.Config)

local SUBDIVISIONS = 18 -- punktów łamanej na odcinek między punktami kontrolnymi (~8 studs)
local SEARCH_WINDOW = 6 -- ile odcinków wokół podpowiedzi przeszukujemy

local River = {}
River.__index = River

export type Query = {
	index: number, -- numer odcinka; podaj jako `hint` przy następnym zapytaniu (szybciej i bez skoków na zakolach)
	s: number,
	lateral: number, -- >0 = prawa strona patrząc z nurtem
	tangent: Vector2, -- kierunek z nurtem
	normal: Vector2, -- w prawo od nurtu
	halfWidth: number,
	speed: number,
	curvature: number, -- rad/stud, >0 = rzeka skręca w prawo
	level: number, -- wysokość lustra wody (y), obniża się na wodospadach
	overshoot: number, -- ile poza końcem rzeki (<0 przed początkiem, >0 za końcem, 0 w korycie)
}

local function catmullRom(a: number, b: number, c: number, d: number, t: number): number
	return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t)
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

function River.new(data: any)
	local self = setmetatable({ id = data.id }, River)
	local controls = data.points
	local count = #controls
	local scale = data.currentScale or 1
	self.positions, self.halfWidths, self.speeds, self.distances, self.curvatures, self.tangents = {}, {}, {}, {}, {}, {}

	-- 1. Gęsta łamana
	for i = 1, count - 1 do
		local a, b, c, d = controls[math.max(i - 1, 1)], controls[i], controls[i + 1], controls[math.min(i + 2, count)]
		for step = 0, SUBDIVISIONS - 1 do
			local t = step / SUBDIVISIONS
			table.insert(self.positions, Vector2.new(catmullRom(a.x, b.x, c.x, d.x, t), catmullRom(a.z, b.z, c.z, d.z, t)))
			table.insert(self.halfWidths, (b.width + (c.width - b.width) * t) / 2)
			table.insert(self.speeds, (b.speed + (c.speed - b.speed) * t) * scale)
		end
	end
	local last = controls[count]
	table.insert(self.positions, Vector2.new(last.x, last.z))
	table.insert(self.halfWidths, last.width / 2)
	table.insert(self.speeds, last.speed * scale)

	-- 2. Odległości i styczne
	local vertices = #self.positions
	self.distances[1] = 0
	for i = 1, vertices - 1 do
		local delta = self.positions[i + 1] - self.positions[i]
		self.tangents[i] = delta.Unit
		self.distances[i + 1] = self.distances[i] + delta.Magnitude
	end
	self.vertices = vertices
	self.length = self.distances[vertices]

	-- 3. Krzywizna: o ile zmienia się kierunek na odcinku; uśredniona z okna, żeby nurt nie szarpał
	local raw = table.create(vertices, 0)
	for i = 2, vertices - 1 do
		local before, after = self.tangents[i - 1], self.tangents[i]
		local turn = wrapAngle(math.atan2(after.Y, after.X) - math.atan2(before.Y, before.X))
		raw[i] = turn / (self.distances[i + 1] - self.distances[i])
	end
	local smooth = 6
	for i = 1, vertices do
		local sum, samples = 0, 0
		for j = math.max(1, i - smooth), math.min(vertices, i + smooth) do
			sum += raw[j]
			samples += 1
		end
		self.curvatures[i] = sum / samples
	end

	-- 4. Wodospady: progi wysokości w miejscach s
	self.falls = {}
	local level = 0
	for _, fall in data.falls or {} do
		level -= fall.drop
		table.insert(self.falls, { s = fall.at * self.length, drop = fall.drop, level = level })
	end
	self.lowestLevel = level

	-- 5. Skały: ze współrzędnych rzecznych na świat (autor trasy nie musi znać X/Z)
	self.rocks = {}
	for _, rock in data.rocks or {} do
		local s = rock.at * self.length
		local center = self:pointAt(s)
		local q = self:query(center)
		local lateral = rock.side * q.halfWidth
		table.insert(self.rocks, {
			position = center + q.normal * lateral,
			radius = rock.r,
			s = s,
			lateral = lateral,
			level = q.level,
		})
	end
	return self
end

-- Wysokość lustra wody w odległości s od startu.
function River:levelAt(s: number): number
	local level = 0
	for _, fall in self.falls do
		if s >= fall.s then
			level = fall.level
		end
	end
	return level
end

-- Punkt na środku rzeki w odległości s od startu.
function River:pointAt(s: number): Vector2
	local distances = self.distances
	local low, high = 1, self.vertices
	while high - low > 1 do
		local middle = (low + high) // 2
		if distances[middle] <= s then
			low = middle
		else
			high = middle
		end
	end
	local span = distances[high] - distances[low]
	local t = math.clamp((s - distances[low]) / span, 0, 1)
	return self.positions[low]:Lerp(self.positions[high], t)
end

-- Współrzędne rzeczne punktu. `hint` = index z poprzedniego zapytania: bez niego szukamy w całej rzece,
-- a z nim tylko obok — szybciej, a kajak nie „przeskoczy” na sąsiednie zakole.
function River:query(position: Vector2, hint: number?): Query
	local segments = self.vertices - 1
	local first, final = 1, segments
	if hint then
		first, final = math.max(1, hint - SEARCH_WINDOW), math.min(segments, hint + SEARCH_WINDOW)
	end
	local bestIndex, bestT, bestDistance = first, 0, math.huge
	for i = first, final do
		local a = self.positions[i]
		local segment = self.positions[i + 1] - a
		local t = math.clamp((position - a):Dot(segment) / segment:Dot(segment), 0, 1)
		local distance = (a + segment * t - position).Magnitude
		if distance < bestDistance then
			bestIndex, bestT, bestDistance = i, t, distance
		end
	end

	local i, t = bestIndex, bestT
	local a = self.positions[i]
	local tangent = self.tangents[i]
	local normal = Vector2.new(-tangent.Y, tangent.X)
	local offset = position - a
	local along = offset:Dot(tangent)
	local segmentLength = self.distances[i + 1] - self.distances[i]
	local overshoot = 0
	if i == 1 and along < 0 then
		overshoot = along
	elseif i == segments and along > segmentLength then
		overshoot = along - segmentLength
	end
	local s = self.distances[i] + segmentLength * t
	return {
		index = i,
		s = s,
		level = self:levelAt(s),
		lateral = offset:Dot(normal),
		tangent = tangent,
		normal = normal,
		halfWidth = self.halfWidths[i] + (self.halfWidths[i + 1] - self.halfWidths[i]) * t,
		speed = self.speeds[i] + (self.speeds[i + 1] - self.speeds[i]) * t,
		curvature = self.curvatures[i] + (self.curvatures[i + 1] - self.curvatures[i]) * t,
		overshoot = overshoot,
	}
end

-- Prędkość wody w punkcie opisanym przez query. Używa jej fizyka i efekty klienta (piana, smugi nurtu).
function River:currentAt(q: Query): Vector2
	local edge = math.min(math.abs(q.lateral) / q.halfWidth, 1)
	local speed = q.speed * (1 - Config.EDGE_SLOWDOWN * edge * edge)
	local flow = q.tangent * speed

	-- Znoszenie na zewnętrzny brzeg zakrętu
	local limit = q.speed * Config.BEND_PUSH_MAX
	flow -= q.normal * math.clamp(q.curvature * Config.BEND_PUSH * q.speed, -limit, limit)

	for _, rock in self.rocks do
		local along = q.s - rock.s
		local eddyRadius = rock.radius * Config.EDDY_RADIUS
		local reach = rock.radius + Config.ROCK_DIVERT_RANGE
		if along > 0 and along < eddyRadius * 2 then
			-- Wir za skałą: woda zwalnia i zawraca, można się w nim schować
			local distance = Vector2.new(along - eddyRadius, q.lateral - rock.lateral).Magnitude
			if distance < eddyRadius then
				flow = flow:Lerp(q.tangent * (-q.speed * Config.EDDY_BACKFLOW), 1 - distance / eddyRadius)
			end
		elseif along <= 0 and along > -reach then
			-- Poduszka przed skałą: woda rozpycha się na boki
			local side = q.lateral - rock.lateral
			if math.abs(side) < reach then
				local weight = (1 - math.abs(side) / reach) * (1 + along / reach)
				flow += q.normal * ((if side >= 0 then 1 else -1) * q.speed * Config.ROCK_DIVERT * weight)
			end
		end
	end
	return flow
end

return River
