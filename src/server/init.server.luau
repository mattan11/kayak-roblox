-- Jedyny skrypt serwera (ARCHITECTURE.md). Wszystko inne to moduły w Systems/.
-- Start dwufazowy: najpierw init() WSZYSTKICH systemów (świat, foldery, remoty), dopiero potem start() (pętle).
-- Dzięki temu żaden system nie zacznie pracować, zanim inny, od którego zależy, się nie przygotuje.
-- (Dla TS: jak kontener DI — najpierw rejestracja wszystkich serwisów, potem uruchomienie.)

local systems: { [string]: any } = {}
for _, child in script.Systems:GetChildren() do
	if child:IsA("ModuleScript") then
		systems[child.Name] = require(child)
	end
end

local function init(name: string, system: any)
	if typeof(system.init) == "function" then
		local ok, err = pcall(system.init)
		if not ok then
			warn(`[Server] init {name}: {err}`)
		end
	end
end

-- RiverBuilder pierwszy: wybiera rzekę (MemoryStore, może chwilę potrwać), a pozostałe systemy biorą ją w swoim init().
init("RiverBuilder", systems.RiverBuilder)
for name, system in systems do
	if name ~= "RiverBuilder" then
		init(name, system)
	end
end

for _, system in systems do
	if typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end

print("[Server] River Riders: spływ gotowy")
