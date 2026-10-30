-- Wygląd kajaka liczony bez Instance (testy: logic/KayakPose.spec). Tylko „na oko”: nie wpływa na fizykę.
-- Konwencja kursu z KayakPhysics: przód = (cos, sin) w płaszczyźnie XZ, rosnący kurs = skręt w prawo.
-- Model (KayakService): dziób w stronę LookVector (−Z), wiosło wzdłuż osi X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local KayakPose = {}

local TWO_PI = 2 * math.pi

function KayakPose.wrapAngle(angle: number): number
	return (angle + math.pi) % TWO_PI - math.pi
end

-- Interpolacja kąta najkrótszą drogą (bez obrotu „dookoła” przy przejściu przez ±π).
function KayakPose.lerpAngle(from: number, to: number, t: number): number
	return from + KayakPose.wrapAngle(to - from) * t
end

-- Wygładzanie niezależne od FPS: ułamek drogi do celu w tej klatce (`x += (cel - x) * alpha`).
function KayakPose.smoothing(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- CFrame kajaka z kursu. Kąt obrotu wokół Y: LookVector = (−sin θ, 0, −cos θ), stąd θ = −kurs − π/2.
function KayakPose.cframe(x: number, y: number, z: number, heading: number, pitch: number, roll: number): CFrame
	return CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(pitch, -heading - math.pi / 2, roll)
end

-- 0..1: jak bardzo „bystrzowa” jest woda (efekty i fale).
function KayakPose.rapids(riverSpeed: number): number
	return math.clamp((riverSpeed - Config.RAPID_SPEED_FROM) / (Config.RAPID_SPEED_FULL - Config.RAPID_SPEED_FROM), 0, 1)
end

-- Cel kołysania: pochylenie dziobu, przechył (roll > 0 = prawa burta w górę) i wysokość fali.
-- Trzy liczby zamiast tabeli, bo to wołane co klatkę. strokePower = 0..1, strokeSide = -1/1/nil.
function KayakPose.target(
	clock: number,
	speed: number,
	spin: number,
	strokeSide: number?,
	strokePower: number,
	riverSpeed: number
): (number, number, number)
	local waves = 1 + KayakPose.rapids(riverSpeed) * Config.POSE_RAPIDS_WAVES
	local pitch = math.min(speed / Config.POSE_FULL_SPEED, 1) * Config.POSE_SPEED_PITCH
		+ math.sin(clock * 2.1) * Config.POSE_WAVE_PITCH * waves

	-- Na zakręcie kajak kładzie się do środka, przy machnięciu lekko na stronę wiosła
	local roll = math.clamp(-spin * Config.POSE_TURN_ROLL, -Config.POSE_ROLL_MAX, Config.POSE_ROLL_MAX)
		+ math.sin(clock * 1.6 + 1) * Config.POSE_WAVE_ROLL * waves
	if strokeSide then
		roll -= strokeSide * strokePower * Config.POSE_STROKE_ROLL
	end

	return pitch, roll, math.sin(clock * 1.8) * Config.POSE_BOB * waves
end

-- Wiosło w trakcie machnięcia (t = 0..1). Yaw > 0 przesuwa prawą łopatę w stronę dziobu, roll < 0 opuszcza prawą.
-- Łopata wchodzi z przodu, przechodzi w wodzie do tyłu, wychodzi.
function KayakPose.paddleStroke(side: number, t: number): (number, number)
	return side * Config.PADDLE_SWEEP * math.cos(math.pi * t), -side * Config.PADDLE_DIP * math.sin(math.pi * t)
end

-- Wiosło wbite: łopata w wodzie przy biodrze, trzymana.
function KayakPose.paddleBrace(side: number): (number, number)
	return -side * Config.PADDLE_BRACE_YAW, -side * Config.PADDLE_BRACE_DIP
end

return KayakPose
