-- Skóra kajaka: widoczne części (model „Look”) budowane z wyglądu z Cosmetics.look. Szkielet (Hull, Seat, Paddle, Align)
-- zostaje w KayakService i jest taki sam dla wszystkich, więc wygląd nigdy nie zmienia fizyki (COSMETICS.md, sekcja 7).
-- Moduł jest w `shared`, bo ten sam kod buduje kajak na serwerze i podgląd w szafce u klienta.
-- Części leżą tak, jakby Hull stał w środku świata (CFrame.identity), przód = −Z. Wołający przesuwa je i spawa.
-- Brak szablonu skórki = klasyk, a brak klasyka = stary kajak z części, nigdy błąd.
-- (Dla TS: fabryka komponentu z fallbackiem: `return template ? clone(template) : <ClassicFromParts/>`.)

local LookAssets = require(script.Parent.LookAssets)

local KayakBody = {}

KayakBody.HULL_LENGTH = 5.2
KayakBody.TIP_LENGTH = 1.4 -- dziób i rufa; razem 8 studs
KayakBody.HULL_WIDTH = 2
KayakBody.HULL_HEIGHT = 1
KayakBody.CLASSIC = "KayakClassic"
KayakBody.NAME = "Look"

local DARK = Color3.fromRGB(34, 36, 40)

-- Każda część skóry: bez kolizji, dotyku, raycastów i masy. Jedno miejsce, więc żadna skórka nie zmieni ruchu.
function KayakBody.prepare(part: BasePart)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function shell(parent: Instance, class: string, name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
	local part = Instance.new(class) :: any
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	KayakBody.prepare(part)
	part.Parent = parent
	return part
end

-- Czubek z dwóch klinów ułożonych płasko (trójkąt widać z góry), dotykających się na osi kajaka.
-- Klin ma kąt prosty przy (−Y, +Z), a ostrze przy (−Y, −Z): lokalne Y kierujemy w bok, Z zostawiamy wzdłuż kajaka.
-- `facing` = obrót całości: bez obrotu czubek celuje w −Z (dziób), o 180° w +Z (rufa).
local function tip(parent: Instance, name: string, facing: CFrame, color: Color3)
	local zBase = -KayakBody.HULL_LENGTH / 2 - KayakBody.TIP_LENGTH / 2
	local size = Vector3.new(KayakBody.HULL_HEIGHT, KayakBody.HULL_WIDTH / 2, KayakBody.TIP_LENGTH)
	for _, side in { -1, 1 } do
		local place = CFrame.fromMatrix(
			Vector3.new(side * KayakBody.HULL_WIDTH / 4, 0, zBase),
			Vector3.new(0, -side, 0),
			Vector3.new(side, 0, 0),
			Vector3.zAxis
		)
		shell(parent, "WedgePart", name, size, facing * place, color)
	end
end

-- Stary kajak z części: kadłub w kolorze, dziób, rufa i ciemny kokpit. Część „Paint” to kadłub, jak w szablonach.
local function fromParts(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = KayakBody.NAME
	local size = Vector3.new(KayakBody.HULL_WIDTH, KayakBody.HULL_HEIGHT, KayakBody.HULL_LENGTH)
	shell(model, "Part", "Paint", size, CFrame.identity, color)
	tip(model, "Bow", CFrame.identity, color)
	tip(model, "Stern", CFrame.Angles(0, math.pi, 0), color)
	shell(model, "Part", "Cockpit", Vector3.new(1.5, 0.1, 3), CFrame.new(0, KayakBody.HULL_HEIGHT / 2 + 0.02, -0.2), DARK)
	return model
end

-- Widoczne części kajaka. `look` z Cosmetics.look: { template, color?, classicColor }.
-- Kolor trafia na część Paint tylko w klasyku (skórki z teksturą mają stały wygląd).
function KayakBody.build(look: any): Model
	local model = LookAssets.clone(look.template)
	local color = look.color
	if model == nil and look.template ~= KayakBody.CLASSIC then
		model = LookAssets.clone(KayakBody.CLASSIC)
		color = look.classicColor
	end
	if model == nil then
		return fromParts(look.classicColor)
	end
	model.Name = KayakBody.NAME
	local paint = model:FindFirstChild("Paint")
	if color and paint and paint:IsA("BasePart") then
		paint.Color = color
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			KayakBody.prepare(part)
		end
	end
	return model
end

-- Wszystkie części skóry (do spawania z Hull albo zakotwiczenia w podglądzie).
function KayakBody.parts(model: Model): { BasePart }
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	return parts
end

return KayakBody
