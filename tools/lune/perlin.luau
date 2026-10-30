-- Zamiennik math.noise dla Lune (tam go nie ma): klasyczny „improved Perlin noise” 3D Kena Perlina (2002).
-- Własności jak w Robloxie: gładki, deterministyczny, 0 w punktach całkowitych, wynik zwykle w −0,5..0,5.
-- Konkretne wartości RÓŻNIĄ SIĘ od Robloxa (inna tablica permutacji) — testy nie mogą polegać na liczbach
-- z szumu, tylko na jego własnościach. (Dla TS: jak pakiet `perlin-noise` zamiast natywnego API.)

local Perlin = {}

-- Tablica permutacji z referencyjnej implementacji Perlina, powtórzona dwa razy (bez modulo przy indeksach).
local PERMUTATION = {
	151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240,
	21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88,
	237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83,
	111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216,
	80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186,
	3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17,
	182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129,
	22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238,
	210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184,
	84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195,
	78, 66, 215, 61, 156, 180,
}
local p = table.create(512)
for i = 0, 511 do
	p[i] = PERMUTATION[(i % 256) + 1]
end

-- Krzywa wygładzania 6t⁵ − 15t⁴ + 10t³ (ciągła pierwsza i druga pochodna).
local function fade(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(t: number, a: number, b: number): number
	return a + t * (b - a)
end

-- Iloczyn skalarny odległości z jednym z 12 gradientów (krawędzie sześcianu), wybranym przez hash.
local function grad(hash: number, x: number, y: number, z: number): number
	local h = hash % 16
	local u = if h < 8 then x else y
	local v = if h < 4 then y elseif h == 12 or h == 14 then x else z
	return (if h % 2 == 0 then u else -u) + (if math.floor(h / 2) % 2 == 0 then v else -v)
end

function Perlin.noise(x: number, y: number?, z: number?): number
	local yy, zz = y or 0, z or 0
	local fx, fy, fz = math.floor(x), math.floor(yy), math.floor(zz)
	local X, Y, Z = fx % 256, fy % 256, fz % 256
	local xf, yf, zf = x - fx, yy - fy, zz - fz
	local u, v, w = fade(xf), fade(yf), fade(zf)

	local A = p[X] + Y
	local AA, AB = p[A] + Z, p[A + 1] + Z
	local B = p[X + 1] + Y
	local BA, BB = p[B] + Z, p[B + 1] + Z

	local result = lerp(
		w,
		lerp(
			v,
			lerp(u, grad(p[AA], xf, yf, zf), grad(p[BA], xf - 1, yf, zf)),
			lerp(u, grad(p[AB], xf, yf - 1, zf), grad(p[BB], xf - 1, yf - 1, zf))
		),
		lerp(
			v,
			lerp(u, grad(p[AA + 1], xf, yf, zf - 1), grad(p[BA + 1], xf - 1, yf, zf - 1)),
			lerp(u, grad(p[AB + 1], xf, yf - 1, zf - 1), grad(p[BB + 1], xf - 1, yf - 1, zf - 1))
		)
	)
	-- Klasyczny Perlin daje ok. −1..1; Roblox ok. −0,5..0,5 — skalujemy, żeby kod gry (np. WorldMap: „× 2”)
	-- dostawał podobny zakres.
	return result * 0.5
end

return Perlin
