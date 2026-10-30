-- Jedyny skrypt serwera wioski. Start dwufazowy jak w src/server/init.server.luau: najpierw init() WSZYSTKICH systemów,
-- dopiero potem start(). Błąd jednego systemu nie zabija reszty (kolejka ma działać np. bez świata).
-- (Dla TS: jak kontener DI: rejestracja wszystkich serwisów, potem uruchomienie.)

local systems: { [string]: any } = {}
for _, child in script.Systems:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, result = pcall(require, child)
		if ok then
			systems[child.Name] = result
		else
			warn(`[Server] require {child.Name}: {result}`)
		end
	end
end

for name, system in systems do
	if typeof(system.init) == "function" then
		local ok, err = pcall(system.init)
		if not ok then
			warn(`[Server] init {name}: {err}`)
		end
	end
end

for _, system in systems do
	if typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end

print("[Server] Wioska gotowa")
