-- Jedyny skrypt klienta. Kontrolery w Controllers/ — start dwufazowy jak na serwerze (ARCHITECTURE.md):
-- najpierw init() wszystkich (przygotowanie), potem start() (podpięcia, pętle). Dla TS: moduły z `setup()` i `run()`.
-- Błąd jednego kontrolera nie zabija reszty: HUD ma działać, nawet gdy padną efekty.
-- Ten sam kod działa w wiosce (village.project.json): kajak, kamera i efekty są wspólne, a kontrolery wyścigu nie startują.
-- Kontrolery samej wioski siedzą w podskrypcie Village, który uruchamia się sam (src/village/client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Places"))

local RACE_ONLY = { HudController = true, LeaveButton = true, GhostController = true, BattleController = true, ArenaController = true }
local inRace = Places.current().id == "race"

local controllers: { [string]: any } = {}
for _, child in script.Controllers:GetChildren() do
	if child:IsA("ModuleScript") and (inRace or not RACE_ONLY[child.Name]) then
		local ok, result = pcall(require, child)
		if ok then
			controllers[child.Name] = result
		else
			warn(`[Client] require {child.Name}: {result}`)
		end
	end
end

for name, controller in controllers do
	if typeof(controller.init) == "function" then
		local ok, err = pcall(controller.init)
		if not ok then
			warn(`[Client] init {name}: {err}`)
		end
	end
end

for _, controller in controllers do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end
