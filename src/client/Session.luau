-- Wspólny stan klienta: jedno miejsce, z którego czytają kontrolery (dla TS: mały store + EventEmitter).
-- Zapisuje go tylko KayakController; reszta czyta i słucha zdarzeń:
--   "paddle" (model, kind, side)  machnięcie/wbicie, swoje albo cudze; kind: "stroke" | "brace" | "release"
--   "hit" (strength)              uderzenie własnego kajaka (state.lastHit czyta i zeruje tylko KayakController)
--   "phase" (phase, endsAt)       zmiana fazy wyścigu
--   "reset" ()                    nowy stan fizyki po Reset
--   "kayakRemoved" (model)        kajak zniknął, sprzątamy rekordy

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local River = require(Shared:WaitForChild("River"))
local Config = require(Shared:WaitForChild("Config"))

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

local rivers = Shared:WaitForChild("content"):WaitForChild("rivers")
local riverModule = rivers:FindFirstChild(waitForRiverId()) or rivers:WaitForChild(Config.ACTIVE_RIVER)

local Session = {
	river = River.new(require(riverModule)),
	phase = "waiting",
	phaseEndsAt = 0,
	state = nil :: any, -- KayakPhysics.State; nil do pierwszego Reset
	active = false, -- czy gracz właśnie steruje (faza racing, kajak gotowy, przed metą)
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
