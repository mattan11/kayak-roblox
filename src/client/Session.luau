-- Wspólny stan klienta: jedno miejsce, z którego czytają kontrolery (dla TS: mały store + EventEmitter).
-- Zapisuje go tylko KayakController; reszta czyta i słucha zdarzeń:
--   "paddle" (model, kind, side)  machnięcie/wbicie, swoje albo cudze; kind: "stroke" | "brace" | "release"
--   "hit" (strength)              uderzenie własnego kajaka (state.lastHit czyta i zeruje tylko KayakController)
--   "phase" (phase, endsAt)       zmiana fazy wyścigu
--   "reset" ()                    nowy stan fizyki po Reset
--   "kayakRemoved" (model)        kajak zniknął, sprzątamy rekordy
--   "arenaState" ()               nowy stan Wodnej bitwy: Session.arenaRadius, Session.arenaAlive
--
-- W wiosce rzeką jest Lake, a faza to stałe "free": bez zegara i mety, reszta kontrolerów działa tak samo.
-- W Wodnej bitwie (RiverId == "Arena") rzeką też jest Lake, a fazę niesie ArenaState zamiast RaceState. Faza walki
-- nazywa się tu "racing", więc sterowanie i HUD nie potrzebują osobnej gałęzi.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local River = require(Shared:WaitForChild("River"))
local Lake = require(Shared:WaitForChild("Lake"))
local Config = require(Shared:WaitForChild("Config"))
local Places = require(Shared:WaitForChild("Places"))

local inVillage = Places.current().id == "village"

-- Serwer wybiera rzekę po starcie i ogłasza ją atrybutem workspace.RiverId. Ten moduł czeka na niego już przy require,
-- więc każdy kontroler może spokojnie czytać Session.river, nawet na górze pliku: dostanie gotową rzekę.
-- Kontrolery ładują się dopiero po tym czekaniu, a zdarzenia z serwera czekają w kolejce na ich podpięcie.
-- (Dla TS: jak top-level await w module. Importujący czeka, aż moduł się dokończy.)
local function waitForRiverId(): string
	while true do
		local id = workspace:GetAttribute("RiverId")
		if type(id) == "string" then
			return id
		end
		workspace:GetAttributeChangedSignal("RiverId"):Wait()
	end
end

local ARENA_ID = "Arena"
local riverId: string? = if inVillage then nil else waitForRiverId()

-- Układ areny w pcall: uszkodzony lub brakujący plik nie może zatrzymać całego klienta (na tym require czekają kontrolery).
-- ArenaLayout ma pola jak LakeLayout, a spawn i heading nie są klientowi potrzebne, bo miejsce startu podaje Reset.
local function loadArena(content: Instance): any?
	local module = content:FindFirstChild("ArenaLayout")
	if module == nil then
		warn("[Session] brak content/ArenaLayout")
		return nil
	end
	local ok, result = pcall(function()
		return Lake.new(require(module :: ModuleScript) :: any)
	end)
	if not ok then
		warn(`[Session] ArenaLayout: {result}`)
		return nil
	end
	return result
end

local function loadWater(): any
	local content = Shared:WaitForChild("content")
	if inVillage then
		return Lake.new(require(content:WaitForChild("LakeLayout")))
	end
	if riverId == ARENA_ID then
		local arena = loadArena(content)
		if arena then
			return arena
		end
	end
	local rivers = content:WaitForChild("rivers")
	return River.new(require(rivers:FindFirstChild(riverId :: string) or rivers:WaitForChild(Config.ACTIVE_RIVER)))
end

local Session = {
	river = loadWater(),
	arena = riverId == ARENA_ID, -- Wodna bitwa: wiadomo od razu, jeszcze przed pierwszym stanem z serwera
	arenaRadius = nil :: number?, -- promień strefy wg ostatniego ArenaState
	arenaAlive = nil :: number?, -- liczba żywych wg ostatniego ArenaState
	phase = if inVillage then "free" else "waiting",
	phaseEndsAt = 0,
	state = nil :: any, -- KayakPhysics.State; nil do pierwszego Reset
	active = false, -- czy gracz właśnie steruje (racing przed metą albo free, kajak gotowy)
	ownModel = nil :: Model?,
	ownHull = nil :: BasePart?, -- ustawiany dopiero, gdy kajak ma komplet części
	kayaks = {} :: { Model }, -- wszystkie kajaki (też własny); tablica, żeby iterować bez alokacji
	raceBeganAt = nil :: number?, -- kiedy ten gracz dostał zielone światło (napis START!)
	startedAt = nil :: number?, -- kiedy ruszył zegar: jak na serwerze, na linii START_LINE (spóźniony: od Reset)
	finishTime = nil :: number?, -- czas na mecie zmierzony lokalnie (na ekran; oficjalny liczy serwer)
}

local listeners: { [string]: { (...any) -> () } } = {}

function Session.on(event: string, callback: (...any) -> ())
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], callback)
end

function Session.emit(event: string, ...: any)
	for _, callback in listeners[event] or {} do
		callback(...)
	end
end

return Session
