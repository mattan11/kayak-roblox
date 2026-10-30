-- Punkt rzeki ze współrzędnych rzecznych: odwrotność River:query (testy: logic/RiverSampler.spec).
-- Efekty wody losują miejsca „s studs dalej, x w bok”. query bez podpowiedzi przeszukuje całą rzekę, więc
-- najpierw szukamy odcinka po tablicy odległości, a query dostaje go jako hint.

local RiverSampler = {}

local function segmentAt(river: any, s: number): number
	local distances = river.distances
	local low, high = 1, river.vertices
	while high - low > 1 do
		local middle = (low + high) // 2
		if distances[middle] <= s then
			low = middle
		else
			high = middle
		end
	end
	return low
end

local function pointOn(river: any, s: number, i: number, lateral: number): (Vector2, any)
	local tangent = river.tangents[i]
	local normal = Vector2.new(-tangent.Y, tangent.X)
	local point = river.positions[i] + tangent * (s - river.distances[i]) + normal * lateral
	return point, river:query(point, i)
end

-- lateral w studs (jak Query.lateral).
function RiverSampler.at(river: any, s: number, lateral: number): (Vector2, any)
	local clamped = math.clamp(s, 0, river.length)
	return pointOn(river, clamped, segmentAt(river, clamped), lateral)
end

-- fraction: -1 = lewy brzeg, 1 = prawy.
function RiverSampler.atFraction(river: any, s: number, fraction: number): (Vector2, any)
	local clamped = math.clamp(s, 0, river.length)
	local i = segmentAt(river, clamped)
	return pointOn(river, clamped, i, fraction * river.halfWidths[i])
end

return RiverSampler
