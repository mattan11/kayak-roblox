-- Czysta logika sterowania (testy: logic/PaddleMapping.spec). Bez Instance: punkt na ekranie albo nazwa klawisza
-- zamienia się w akcję, a `held` pamięta, co jest trzymane. Dla TS: reducer, a PaddleInput to tylko adapter zdarzeń.

local PaddleMapping = {}

export type Action = { kind: string, side: number } -- kind: "stroke" | "brace"; side: -1 lewa, 1 prawa

local STROKE_LEFT: Action = { kind = "stroke", side = -1 }
local STROKE_RIGHT: Action = { kind = "stroke", side = 1 }
local BRACE_LEFT: Action = { kind = "brace", side = -1 }
local BRACE_RIGHT: Action = { kind = "brace", side = 1 }

-- Klucze to nazwy KeyCode (a nie same Enumy): klawiatura i pad idą tą samą ścieżką, a tabelę da się testować w Lune.
local KEYS: { [string]: Action } = {
	A = STROKE_LEFT,
	D = STROKE_RIGHT,
	Left = STROKE_LEFT,
	Right = STROKE_RIGHT,
	Q = BRACE_LEFT,
	E = BRACE_RIGHT,
	ButtonL2 = STROKE_LEFT,
	ButtonR2 = STROKE_RIGHT,
	ButtonL1 = BRACE_LEFT,
	ButtonR1 = BRACE_RIGHT,
}

-- Punkt na ekranie → akcja. braceZone z Config: "bottom" albo "top".
function PaddleMapping.classify(x: number, y: number, width: number, height: number, braceZone: string): Action
	local left = x < width / 2
	local top = y < height / 2
	local brace = if braceZone == "top" then top else not top
	if brace then
		return if left then BRACE_LEFT else BRACE_RIGHT
	end
	return if left then STROKE_LEFT else STROKE_RIGHT
end

-- Po której stronie kajaka idzie wiosło. Domyślnie gracz wskazuje kierunek: tap po prawej to skręt w prawo, czyli wiosło
-- po lewej (lewe wiosło pcha dziób w prawo). W trybie realistycznym gracz wskazuje samo wiosło.
function PaddleMapping.paddleSide(side: number, realistic: boolean): number
	return if realistic then side else -side
end

function PaddleMapping.forKey(keyName: string): Action?
	return KEYS[keyName]
end

-- Liczniki, nie boole: dwa palce w tym samym polu nie mogą się nawzajem „puścić”.
function PaddleMapping.newHeld()
	return {
		stroke = { [-1] = 0, [1] = 0 },
		brace = { [-1] = 0, [1] = 0 },
		latestBrace = nil :: number?,
		lastStroke = 1,
	}
end

function PaddleMapping.press(held, action: Action)
	local counts = held[action.kind]
	counts[action.side] += 1
	if action.kind == "brace" then
		held.latestBrace = action.side
	else
		held.lastStroke = action.side
	end
end

function PaddleMapping.release(held, action: Action)
	local counts = held[action.kind]
	counts[action.side] = math.max(counts[action.side] - 1, 0)
end

function PaddleMapping.clear(held)
	for _, counts in { held.stroke, held.brace } do
		counts[-1], counts[1] = 0, 0
	end
	held.latestBrace = nil
end

-- Po której stronie wiosło ma być wbite: ostatnio wciśnięte pole, jeśli wciąż trzymane.
function PaddleMapping.braceSide(held): number?
	local latest = held.latestBrace
	if latest and held.brace[latest] > 0 then
		return latest
	end
	if held.brace[-1] > 0 then
		return -1
	end
	return if held.brace[1] > 0 then 1 else nil
end

-- Kolejne machnięcie z przytrzymania. Trzymane obie strony = na zmianę, jak prawdziwe wiosłowanie.
function PaddleMapping.nextHeldStroke(held): number?
	local left, right = held.stroke[-1] > 0, held.stroke[1] > 0
	local side: number? = nil
	if left and right then
		side = -held.lastStroke
	elseif left then
		side = -1
	elseif right then
		side = 1
	end
	if side then
		held.lastStroke = side
	end
	return side
end

return PaddleMapping
