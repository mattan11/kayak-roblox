-- Uruchamia wszystkie testy (*.spec w tym folderze i podfolderach) i zwraca raport tekstowy.
-- Wołane przez Claude w Studio (tryb Edit, MCP execute_luau):
--   return require(game.ServerStorage.Tests:Clone().Run)()
--
-- Świeży kod przy każdym uruchomieniu: require w Studio pamięta moduł (jak cache importów w Node), więc po
-- zmianie pliku przez Rojo dostalibyśmy starą wersję. Dlatego testujemy KOPIE (Clone) folderów gry:
--  * Shared — kopia na chwilę zastępuje oryginał w ReplicatedStorage (kod serwera szuka go po nazwie),
--    po testach oryginał wraca na miejsce (Rojo dalej go śledzi);
--  * Server i Client — kopie bez rodzica (skrypty bez rodzica się nie uruchamiają, moduły da się require).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Spec = require(script.Parent.Spec)

local function collectSpecs(folder: Instance, into: { ModuleScript })
	for _, child in folder:GetDescendants() do
		if child:IsA("ModuleScript") and string.match(child.Name, "%.spec$") then
			table.insert(into, child)
		end
	end
	table.sort(into, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return into
end

return function(filter: string?): string
	local original = ReplicatedStorage:FindFirstChild("Shared")
	local shared = original:Clone()
	original.Parent = nil
	shared.Parent = ReplicatedStorage

	local results: { Spec.Result } = {}
	local ok, err = pcall(function()
		local extra = {
			shared = shared,
			server = ServerScriptService.Server:Clone(),
			client = StarterPlayer.StarterPlayerScripts.Client:Clone(),
		}
		for _, module in collectSpecs(script.Parent, {}) do
			if filter == nil or string.find(module.Name, filter, 1, true) then
				local t = Spec.new(results, module.Name, extra)
				local loaded, loadErr = pcall(function()
					require(module)(t)
				end)
				if not loaded then
					table.insert(results, { name = module.Name, ok = false, message = "nie da się wczytać: " .. tostring(loadErr) })
				end
			end
		end
	end)

	-- Zawsze przywracamy oryginał, nawet gdy coś wybuchło.
	shared:Destroy()
	original.Parent = ReplicatedStorage
	if not ok then
		return "BŁĄD uruchamiania testów: " .. tostring(err)
	end

	local passed, failed, warned = 0, {}, {}
	for _, result in results do
		for _, warning in result.warnings or {} do
			table.insert(warned, "⚠ " .. warning)
		end
		if result.ok then
			passed += 1
		else
			table.insert(failed, "✗ " .. result.name .. "\n    " .. (result.message or ""))
		end
	end
	local report = { string.format("%d ✓, %d ✗, %d ⚠", passed, #failed, #warned) }
	for _, list in { failed, warned } do
		if #list > 0 then
			table.insert(report, table.concat(list, "\n"))
		end
	end
	return table.concat(report, "\n\n")
end
