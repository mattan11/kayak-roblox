-- Jedyny skrypt klienta wioski. Start dwufazowy jak w src/client/init.client.luau: najpierw init() wszystkich kontrolerów,
-- potem start(). Dla TS: moduły z `setup()` i `run()`. Błąd jednego kontrolera nie zabija reszty.
-- Tylko kontrolery wioski: ten skrypt to podfolder Village w src/client (village.project.json), a kajak, kamerę i efekty
-- uruchamia src/client/init.client.luau. PaddleInput chowa tam gałkę i skok, tak samo jak na spływie.

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
