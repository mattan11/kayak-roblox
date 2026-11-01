-- Szablony modeli z ReplicatedStorage.LookAssets (assets/look.rbxm, źródła: assets/_src). Siatki są bez tekstur, a kolor nadaje kod,
-- więc ta sama sosna pasuje do łąki i do śniegu. Brak szablonu to nil: wołający buduje wtedy starą wersję z części.
-- (Dla TS: `const template = assets.get(name); if (!template) return fallback()`.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LookAssets = {}

local LEAFY = { "TreeRound", "TreeDouble" }
local PINES = { "TreePine", "TreePineTall" }
local ROCKS = { "RockA", "RockB", "RockC" }
local ROCK_REACH = 2.1 -- największy wymiar skały w promieniach kolizji: bryła zakrywa całe koło z fizyki

local function template(name: string): any
	local folder = ReplicatedStorage:FindFirstChild("LookAssets")
	return folder and folder:FindFirstChild(name)
end

function LookAssets.clone(name: string): any
	local source = template(name)
	return source and source:Clone()
end

-- Drzewo stojące w `base`, o wysokości `height`. False = brak szablonu.
function LookAssets.plantTree(parent: Instance, pine: boolean, base: Vector3, height: number, crown: Color3, trunk: Color3, random: Random): boolean
	local names = if pine then PINES else LEAFY
	local tree = LookAssets.clone(names[random:NextInteger(1, #names)])
	if tree == nil then
		return false
	end
	tree:ScaleTo(height / tree:GetExtentsSize().Y)
	tree:PivotTo(CFrame.new(base) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0))
	tree.Crown.Color = crown
	tree.Trunk.Color = trunk
	tree.Parent = parent
	return true
end

-- Skała w `position`, wymiar dopasowany do promienia kolizji. False = brak szablonu.
function LookAssets.placeRock(parent: Instance, position: Vector3, radius: number, color: Color3, random: Random): boolean
	local rock = LookAssets.clone(ROCKS[random:NextInteger(1, #ROCKS)])
	if rock == nil then
		return false
	end
	local size = rock.Size
	rock.Size = size * (radius * ROCK_REACH / math.max(size.X, size.Y, size.Z))
	rock.CFrame = CFrame.new(position) * CFrame.Angles(0, random:NextNumber(0, 2 * math.pi), 0)
	rock.Color = color
	rock.Parent = parent
	return true
end

return LookAssets
