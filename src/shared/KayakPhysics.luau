-- Fizyka kajaka — czysta logika 2D (testy: logic/KayakPhysics.spec). Liczona na urządzeniu gracza, serwer jej nie
-- potrzebuje do jazdy. Pozycja = Vector2(x, z), kurs w radianach: przód = (cos, sin), rosnący kurs = skręt w prawo.
-- Prędkości liczymy WZGLĘDEM WODY: opór i ster działają tylko wtedy, gdy kajak porusza się inaczej niż nurt.
-- side: -1 = lewa strona, 1 = prawa.

local Config = require(script.Parent.Config)

local KayakPhysics = {}

local HULL_POINTS = { 0, 1, -1 } -- środek, dziób, rufa (× Config.HULL_REACH)

export type State = {
	position: Vector2,
	height: number, -- y lustra wody pod kajakiem albo wyżej, gdy spada z wodospadu
	fallSpeed: number,
	velocity: Vector2,
	heading: number,
	spin: number, -- prędkość obrotu (rad/s)
	strokeSide: number?, -- trwające machnięcie
	strokeTime: number, -- ile już trwa
	queued: number?, -- następne machnięcie (kolejka max 1: spam nic nie daje)
	brace: number?, -- wiosło wbite po tej stronie
	accumulator: number, -- reszta czasu do pełnego kroku
	hint: number?, -- ostatni odcinek rzeki
	lastQuery: any?, -- ostatnie współrzędne rzeczne (dla kamery i efektów)
	lastHit: number, -- siła ostatniego uderzenia; efekty odczytują i zerują
	strokes: number, -- licznik rozpoczętych machnięć
}

function KayakPhysics.new(position: Vector2, heading: number): State
	return {
		position = position,
		height = 0,
		fallSpeed = 0,
		velocity = Vector2.zero,
		heading = heading,
		spin = 0,
		strokeSide = nil,
		strokeTime = 0,
		queued = nil,
		brace = nil,
		accumulator = 0,
		hint = nil,
		lastQuery = nil,
		lastHit = 0,
		strokes = 0,
	}
end

function KayakPhysics.requestStroke(state: State, side: number)
	if state.queued == nil then
		state.queued = side
	end
end

-- Wbicie trwa tak długo, jak gracz trzyma pole; nil = wyjęcie wiosła. Przerywa machnięcie.
function KayakPhysics.setBrace(state: State, side: number?)
	state.brace = side
	if side then
		state.strokeSide = nil
		state.queued = nil
	end
end

local function wrapAngle(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Odbicie od ściany: `out` wskazuje DO ściany, `arm` to punkt uderzenia względem środka kajaka.
-- Uderzenie poza środkiem obraca kajak: to zwykły moment siły (iloczyn wektorowy ramienia i siły).
local function bounce(state: State, out: Vector2, restitution: number, arm: Vector2)
	local into = state.velocity:Dot(out)
	if into <= 0 then
		return
	end
	local along = state.velocity - out * into
	if into > Config.HIT_MIN_SPEED then
		along *= Config.HIT_FRICTION
		state.lastHit = math.max(state.lastHit, into)
		if into > Config.HIT_SPIN_MIN_SPEED then
			state.spin += (arm.X * -out.Y + arm.Y * out.X) * into * Config.HIT_SPIN
		end
	end
	state.velocity = along - out * (into * restitution)
end

local function collide(state: State, river: any, others: { Vector2 }?)
	-- Kajak w zderzeniach = trzy koła wzdłuż kadłuba: dziób, środek, rufa. Dzięki temu rufa naprawdę o coś zahacza.
	local forward = Vector2.new(math.cos(state.heading), math.sin(state.heading))
	local radius = Config.KAYAK_RADIUS
	for _, offset in HULL_POINTS do
		local arm = forward * (offset * Config.HULL_REACH)
		local q = river:query(state.position + arm, state.hint)
		local point = state.position + arm

		-- Końce rzeki: niewidzialna ściana
		if q.overshoot ~= 0 then
			state.position -= q.tangent * q.overshoot
			bounce(state, q.tangent * math.sign(q.overshoot), 0, Vector2.zero)
		end

		-- Brzegi
		local limit = q.halfWidth - radius
		if math.abs(q.lateral) > limit then
			local side = math.sign(q.lateral)
			state.position -= q.normal * (side * (math.abs(q.lateral) - limit))
			bounce(state, q.normal * side, Config.BOUNCE, arm)
		end

		-- Skały: koło z kołem
		for _, rock in river.rocks do
			if math.abs(q.s - rock.s) < rock.radius + radius + 1 then
				local delta = point - rock.position
				local distance = delta.Magnitude
				local minimum = rock.radius + radius
				if distance < minimum and distance > 0 then
					local away = delta / distance
					state.position += away * (minimum - distance)
					bounce(state, -away, Config.BOUNCE, arm)
				end
			end
		end
	end

	-- Inne kajaki: każdy klient rozwiązuje tylko swój kajak, więc każda strona cofa się o połowę
	for _, other in others or {} do
		local delta = state.position - other
		local distance = delta.Magnitude
		local minimum = Config.KAYAK_CONTACT
		if distance < minimum and distance > 0 then
			local away = delta / distance
			state.position += away * ((minimum - distance) / 2)
			bounce(state, -away, Config.BOUNCE, Vector2.zero)
		end
	end
end

local function fixedStep(state: State, river: any, others: { Vector2 }?, dt: number): number?
	local started: number? = nil
	if state.strokeSide == nil and state.queued ~= nil and state.brace == nil then
		state.strokeSide, state.queued, state.strokeTime = state.queued, nil, 0
		state.strokes += 1
		started = state.strokeSide
	end

	local q = river:query(state.position, state.hint)
	state.hint = q.index
	state.lastQuery = q
	local current = river:currentAt(q)

	local forward = Vector2.new(math.cos(state.heading), math.sin(state.heading))
	local right = Vector2.new(-forward.Y, forward.X)
	local relative = state.velocity - current
	local forwardSpeed = relative:Dot(forward)
	local sideSpeed = relative:Dot(right)

	local dragForward = Config.DRAG_FORWARD
	local thrust, torque = 0, 0

	if state.strokeSide then
		-- Sinus: wiosło wchodzi w wodę, największa siła w połowie, wychodzi
		local power = math.sin(math.pi * state.strokeTime / Config.STROKE_TIME)
		thrust = Config.STROKE_THRUST * power
		torque = -state.strokeSide * Config.STROKE_TURN * power
		state.strokeTime += dt
		if state.strokeTime >= Config.STROKE_TIME then
			state.strokeSide = nil
		end
	end

	if state.brace then
		-- Wiosło jak ster: im szybciej woda je opływa, tym mocniej obraca
		local flow = math.clamp(relative.Magnitude / Config.BRACE_FULL_SPEED, 0, 1)
		local still = Config.BRACE_TURN_STILL
		torque = state.brace * Config.BRACE_TURN * (still + (1 - still) * flow)
		dragForward += Config.BRACE_DRAG
	elseif current.Magnitude > 0 then
		-- Nurt powoli ustawia dziób z prądem. Stojąca woda nie ma kierunku, więc na jeziorze kajak trzyma swój kurs.
		local flowHeading = math.atan2(current.Y, current.X)
		torque += wrapAngle(flowHeading - state.heading) * Config.ALIGN_TO_FLOW
	end

	state.velocity += (forward * (thrust - forwardSpeed * dragForward) - right * (sideSpeed * Config.DRAG_LATERAL)) * dt
	state.spin += (torque - state.spin * Config.DRAG_ANGULAR) * dt
	state.heading = wrapAngle(state.heading + state.spin * dt)
	state.position += state.velocity * dt

	collide(state, river, others)

	-- Wodospad: ruch w poziomie liczy się dalej tak samo, a kajak spada, aż dotknie niższej wody
	if state.height > q.level then
		state.fallSpeed += Config.FALL_GRAVITY * dt
		state.height -= state.fallSpeed * dt
		if state.height <= q.level then
			state.lastHit = math.max(state.lastHit, state.fallSpeed)
			state.height, state.fallSpeed = q.level, 0
		end
	else
		state.height = q.level
	end
	return started
end

-- Krok o dowolnym dt (klatka gry). Zwraca stronę machnięcia, które właśnie się zaczęło (do animacji), albo nil.
function KayakPhysics.step(state: State, river: any, others: { Vector2 }?, dt: number): number?
	state.accumulator = math.min(state.accumulator + dt, 0.25) -- po przycięciu gry nie nadrabiamy w nieskończoność
	local started: number? = nil
	while state.accumulator >= Config.STEP do
		state.accumulator -= Config.STEP
		started = fixedStep(state, river, others, Config.STEP) or started
	end
	return started
end

return KayakPhysics
