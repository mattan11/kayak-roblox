-- Runner testów jednostkowych BEZ Roblox Studio — na Lune (https://lune-org.github.io/docs).
-- Uruchomienie z katalogu repo:
--   C:\Users\marek\tools\lune\lune.exe run tools/lune/run_tests.luau [filtr]
-- (filtr = fragment nazwy speca, np. "Combat" — jak argument Run.luau w Studio).
--
-- Jak to działa (dla TS: jak jest/vitest z wirtualnym DOM zamiast przeglądarki):
--  1. `rojo build default.project.json` składa miejsce (.rbxl) dokładnie tak jak w Studio — te same reguły
--     Rojo (init.luau, *.server/*.client, .rbxm, .csv), więc nie piszemy własnego mapowania plików;
--  2. @lune/roblox wczytuje je jako drzewo instancji (FindFirstChild, GetChildren, IsA, Source działają);
--  3. własny `require(ModuleScript)` kompiluje `.Source` przez @lune/luau i uruchamia z globalami jak w Robloxie
--     (script, game, Vector3, CFrame, Enum, task, math.noise...) — z cache, jak cache importów w Node;
--  4. specy (*.spec) dostają `t` ze Spec.luau — ten sam mini-Jest co w Studio — i raport jak z Run.luau.
-- Specy, które potrzebują prawdziwego silnika (Play, fizyka, modele z Studio), są w SKIPPED niżej.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local Perlin = require("./perlin")
local Random = require("./random")

-- Specy pomijane poza Studio: nazwa speca → powód (pokazywany w raporcie).
local SKIPPED: { [string]: string } = {}

-- ── 1. Miejsce z Rojo ────────────────────────────────────────────────────────────────────────────────────

-- Katalog repo = pierwszy w górę od bieżącego, który ma default.project.json (działa też z podkatalogu).
local function findRepoRoot(): string
	local dir = string.gsub(process.cwd, "[/\\]+$", "")
	while true do
		if fs.isFile(dir .. "/default.project.json") then
			return dir
		end
		local parent = string.match(dir, "^(.*)[/\\][^/\\]+$")
		if parent == nil or parent == dir then
			error("nie znaleziono default.project.json — uruchom z katalogu repo", 0)
		end
		dir = parent
	end
end

local root = findRepoRoot()
local tempDir = process.env.TEMP or process.env.TMPDIR or "/tmp"
-- Osobny plik na proces (kilku agentów naraz w różnych worktree nie nadpisuje sobie miejsca).
local placePath = string.format("%s/kayak-tests-%d-%d.rbxl", tempDir, os.time(), math.random(1, 1e9))

local build = process.exec("rojo", { "build", "default.project.json", "-o", placePath }, { cwd = root })
if not build.ok then
	stdio.ewrite("rojo build nie powiódł się:\n" .. build.stdout .. build.stderr .. "\n")
	process.exit(2)
end
local game = roblox.deserializePlace(fs.readFile(placePath))
pcall(fs.removeFile, placePath)

-- ── 2. Metody Instance, których Lune nie ma (dopisujemy minimum potrzebne kodowi gry) ─────────────────────

-- WaitForChild: drzewo jest kompletne od razu, więc „czekanie” = FindFirstChild albo błąd (w Studio byłby
-- nieskończony yield z ostrzeżeniem).
roblox.implementMethod("Instance", "WaitForChild", function(instance, name: string)
	local child = instance:FindFirstChild(name)
	if child == nil then
		error(string.format("WaitForChild: brak %s w %s (Lune)", name, instance:GetFullName()), 2)
	end
	return child
end)

-- LocalizationTable:GetEntries — Rojo zapisuje CSV jako JSON we właściwości Contents (klucze małą literą,
-- a Roblox zwraca Key / Source / Values / Context / Example).
roblox.implementMethod("LocalizationTable", "GetEntries", function(instance)
	local entries = {}
	for _, row in serde.decode("json", instance.Contents) do
		table.insert(entries, {
			Key = row.key or "",
			Source = row.source or "",
			Values = row.values or {},
			Context = row.context or "",
			Example = row.example or "",
		})
	end
	return entries
end)

-- MeshPart.MeshId: nowe .rbxm zapisują siatkę jako MeshContent (typ Content), a Lune nie wylicza z niego starej
-- właściwości MeshId (w Studio to aliasy; odczyt w Lune rzuca „missing default value”). Raz po wczytaniu
-- przepisujemy MeshId = Uri z MeshContent; brak siatki = "" jak w Robloxie.
for _, part in game:GetDescendants() do
	if part:IsA("MeshPart") then
		part.MeshId = part.MeshContent.Uri or ""
	end
end

-- ── 3. require(ModuleScript) jak w Robloxie ─────────────────────────────────────────────────────────────

local mathWithNoise = table.clone(math)
mathWithNoise.noise = Perlin.noise -- w Lune nie ma math.noise; wartości inne niż w Robloxie, zakres ten sam

-- loadstring tylko kompiluje (jak w Studio z MCP) — dla Syntax.spec.
local function loadstringShim(source: string, chunkName: string?)
	local ok, result = pcall(luau.load, source, { debugName = chunkName or "loadstring" })
	if ok then
		return result
	end
	return nil, (string.gsub(tostring(result), "\n.*", "")) -- pierwsza linia, bez śladu stosu Lune
end

-- Instancje z Lune to userdata tworzone na nowo przy każdym dostępie, więc kluczem cache jest pełna ścieżka
-- (w Studio require pamięta po samej instancji — efekt ten sam, moduł wykonuje się raz).
local cache: { [string]: { value: any } } = {}
local loading: { [string]: boolean } = {}

local requireModule: (module: any) -> any

local function makeEnv(script: any): { [string]: any }
	return {
		script = script,
		require = requireModule,
		game = game,
		workspace = game:GetService("Workspace"),
		math = mathWithNoise,
		task = task,
		loadstring = loadstringShim,
		tick = os.clock,
		time = os.clock,
		-- Typy danych Robloxa z @lune/roblox (ta sama semantyka: ==, operatory, typeof).
		Axes = roblox.Axes,
		BrickColor = roblox.BrickColor,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		Enum = roblox.Enum,
		Faces = roblox.Faces,
		Font = roblox.Font,
		Instance = roblox.Instance,
		Random = Random, -- własny zamiennik (random.luau)
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		Ray = roblox.Ray,
		Rect = roblox.Rect,
		Region3 = roblox.Region3,
		Region3int16 = roblox.Region3int16,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector2int16 = roblox.Vector2int16,
		Vector3 = roblox.Vector3,
		Vector3int16 = roblox.Vector3int16,
	}
end

function requireModule(module: any): any
	if typeof(module) ~= "Instance" or not module:IsA("ModuleScript") then
		error("require: oczekiwano ModuleScript, jest " .. typeof(module), 2)
	end
	local key = module:GetFullName()
	local cached = cache[key]
	if cached then
		return cached.value
	end
	if loading[key] then
		error("require: cykl zależności przy " .. key, 2)
	end
	loading[key] = true
	-- injectGlobals = globale Lune (print, typeof, string...) pod naszymi — jak globalne API Robloxa.
	local chunk = luau.load(module.Source, { debugName = key, environment = makeEnv(module), injectGlobals = true })
	local ok, value = pcall(chunk)
	loading[key] = nil
	if not ok then
		error(string.format("require(%s): %s", key, tostring(value)), 0)
	end
	cache[key] = { value = value }
	return value
end

-- ── 4. Specy ─────────────────────────────────────────────────────────────────────────────────────────────

local filter = process.args[1]
local tests = game:GetService("ServerStorage"):FindFirstChild("Tests")
local Spec = requireModule(tests:FindFirstChild("Spec"))

local specs = {}
for _, child in tests:GetDescendants() do
	if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") then
		table.insert(specs, child)
	end
end
table.sort(specs, function(a, b)
	return a:GetFullName() < b:GetFullName()
end)

local extra = {
	shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared"),
	server = game:GetService("ServerScriptService"):FindFirstChild("Server"),
	client = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"),
}

local results = {}
local skipped = {}
for _, module in specs do
	if filter == nil or string.find(module.Name, filter, 1, true) then
		if SKIPPED[module.Name] then
			table.insert(skipped, "– " .. module.Name .. ": " .. SKIPPED[module.Name])
		else
			local t = Spec.new(results, module.Name, extra)
			local loaded, loadErr = pcall(function()
				requireModule(module)(t)
			end)
			if not loaded then
				table.insert(results, { name = module.Name, ok = false, message = "nie da się wczytać: " .. tostring(loadErr) })
			end
		end
	end
end

-- Błędy z Lune niosą ślad stosu (runner, pcall w Spec...) — w raporcie wystarczy sam komunikat, jak w Studio.
local function trimTrace(message: string): string
	local cut = string.find(message, "\n%s*stack traceback:") or string.find(message, "\n%s*%[Stack Begin%]")
	return if cut then string.sub(message, 1, cut - 1) else message
end

-- Raport w formacie Run.luau (+ lista pominiętych).
local passed, failed, warned = 0, {}, {}
for _, result in results do
	for _, warning in result.warnings or {} do
		table.insert(warned, "⚠ " .. warning)
	end
	if result.ok then
		passed += 1
	else
		table.insert(failed, "✗ " .. result.name .. "\n    " .. trimTrace(result.message or ""))
	end
end
local report = { string.format("%d ✓, %d ✗, %d ⚠, %d pominiętych (Lune)", passed, #failed, #warned, #skipped) }
for _, list in { failed, warned, skipped } do
	if #list > 0 then
		table.insert(report, table.concat(list, "\n"))
	end
end
print(table.concat(report, "\n\n"))
process.exit(if #failed > 0 then 1 else 0)
