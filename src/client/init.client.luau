-- Jedyny skrypt klienta. Kontrolery w Controllers/ — start dwufazowy jak na serwerze (ARCHITECTURE.md):
-- najpierw init() wszystkich (przygotowanie), potem start() (podpięcia, pętle). Dla TS: moduły z `setup()` i `run()`.
-- Błąd jednego kontrolera nie zabija reszty: HUD ma działać, nawet gdy padną efekty.

local controllers: { [string]: any } = {}
for _, child in script.Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
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
