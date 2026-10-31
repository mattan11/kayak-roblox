-- Miniaturka rzeki jako czysta matematyka: punkty świata → odcinki i kropki w prostokącie (spec: logic/RiverThumbnail.spec).
-- Bez Instance: Frame'y tworzy dopiero RiverPicker w wiosce. (Dla TS: funkcja licząca atrybuty <line>, a rysuje komponent.)
-- Odcinek to środek, długość i kąt, bo tak ustawia się obrócony Frame: AnchorPoint (0.5, 0.5), Position, Size, Rotation.
-- Rzeki są długie i wąskie, więc dłuższa oś idzie w poziomie, start jest po lewej, a oś poprzeczna może się rozciągnąć.

local RiverThumbnail = {}

export type Segment = { x: number, y: number, length: number, rotation: number } -- środek, piksele; rotation w stopniach
export type Dot = { x: number, y: number }
export type Layout = { segments: { Segment }, dots: { Dot } }
export type Box = {
	width: number,
	height: number,
	padding: number, -- wolny margines z każdej strony
	maxStretch: number, -- ile razy jedna oś może być mocniej przeskalowana niż druga (1 = wierne proporcje)
}

-- Równe próbki wzdłuż rzeki zamiast setek wierzchołków łamanej: `count` odcinków to `count` Frame'ów.
-- `river` to obiekt z River.new. Zwraca punkty przebiegu i punkty wodospadów.
function RiverThumbnail.sample(river: any, count: number): ({ Vector2 }, { Vector2 })
	local points = table.create(count + 1)
	for i = 0, count do
		points[i + 1] = river:pointAt(river.length * i / count)
	end
	local marks = {}
	for _, fall in river.falls do
		table.insert(marks, river:pointAt(fall.s))
	end
	return points, marks
end

-- Skala osi: ile pikseli na stud. Zerowy rozpiętość osi (prosta rzeka) nie ogranicza skali.
local function axisScales(spanU: number, spanV: number, box: Box): (number, number)
	local fitU = if spanU > 0 then (box.width - 2 * box.padding) / spanU else math.huge
	local fitV = if spanV > 0 then (box.height - 2 * box.padding) / spanV else math.huge
	local uniform = math.min(fitU, fitV)
	if uniform == math.huge then
		return 1, 1 -- wszystkie punkty w jednym miejscu
	end
	return math.min(fitU, uniform * box.maxStretch), math.min(fitV, uniform * box.maxStretch)
end

-- `points` to przebieg w kolejności z nurtem, `marks` to punkty do zaznaczenia kropką. Mniej niż 2 punkty = pusty wynik.
function RiverThumbnail.layout(points: { Vector2 }, marks: { Vector2 }, box: Box): Layout
	local result: Layout = { segments = {}, dots = {} }
	if #points < 2 then
		return result
	end

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, point in points do
		minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
		minZ, maxZ = math.min(minZ, point.Y), math.max(maxZ, point.Y)
	end

	-- Współrzędne miniaturki: u w poziomie (wzdłuż dłuższej osi), v w pionie.
	local flip = maxZ - minZ > maxX - minX
	local minU, maxU = if flip then minZ else minX, if flip then maxZ else maxX
	local minV, maxV = if flip then minX else minZ, if flip then maxX else maxZ
	local function axes(point: Vector2): (number, number)
		if flip then
			return point.Y, point.X
		end
		return point.X, point.Y
	end

	local firstU = axes(points[1])
	local lastU = axes(points[#points])
	local mirror = firstU > lastU -- start ma być po lewej
	local scaleU, scaleV = axisScales(maxU - minU, maxV - minV, box)
	local middleU, middleV = (minU + maxU) / 2, (minV + maxV) / 2

	local function project(point: Vector2): Vector2
		local u, v = axes(point)
		local across = (u - middleU) * scaleU
		return Vector2.new(
			box.width / 2 + (if mirror then -across else across),
			box.height / 2 + (v - middleV) * scaleV
		)
	end

	local previous = project(points[1])
	for i = 2, #points do
		local current = project(points[i])
		local delta = current - previous
		local length = delta.Magnitude
		if length > 0 then
			local center = (previous + current) / 2
			table.insert(result.segments, {
				x = center.X,
				y = center.Y,
				length = length,
				rotation = math.deg(math.atan2(delta.Y, delta.X)),
			})
		end
		previous = current
	end

	for _, mark in marks do
		local dot = project(mark)
		table.insert(result.dots, { x = dot.X, y = dot.Y })
	end
	return result
end

return RiverThumbnail
