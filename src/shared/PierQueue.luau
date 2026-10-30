-- Kolejka jednego pomostu: czysta logika bez Instance i bez zegara (testy: logic/PierQueue.spec). Czas `now` podaje wołający.
-- Zasady (VISION.md): 30 s od pierwszej osoby, przy komplecie skrót do 5 s, „Płyń teraz” rusza od razu z całą kolejką.
-- Kolejka zna tylko userId. Teleportem i strefami zajmuje się Systems/PierService.
-- (Dla TS: jak reducer. Dane wchodzą, stan się zmienia, efekty uboczne robi ktoś inny.)

local Config = require(script.Parent.Config)

local PierQueue = {}
PierQueue.__index = PierQueue

function PierQueue.new()
	return setmetatable({
		members = {} :: { number }, -- userId w kolejności wejścia
		endsAt = nil :: number?, -- koniec odliczania; nil = pusty pomost
	}, PierQueue)
end

function PierQueue:count(): number
	return #self.members
end

function PierQueue:has(id: number): boolean
	return table.find(self.members, id) ~= nil
end

-- Zwraca, czy gracz wszedł (false: już jest albo komplet).
function PierQueue:join(id: number, now: number): boolean
	if self:has(id) or #self.members >= Config.PIER_CAPACITY then
		return false
	end
	table.insert(self.members, id)
	if self.endsAt == nil then
		self.endsAt = now + Config.PIER_COUNTDOWN
	end
	if #self.members >= Config.PIER_CAPACITY then
		self.endsAt = math.min(self.endsAt, now + Config.PIER_FULL_COUNTDOWN)
	end
	return true
end

-- Zwraca, czy gracz wyszedł. Wyjście ostatniego kasuje odliczanie, wyjście kogoś innego go nie cofa
-- (raz skrócony czas zostaje: nikt nie powinien czekać dłużej przez to, że ktoś zrezygnował).
function PierQueue:leave(id: number): boolean
	local index = table.find(self.members, id)
	if index == nil then
		return false
	end
	table.remove(self.members, index)
	if #self.members == 0 then
		self.endsAt = nil
	end
	return true
end

-- Oddaje całą kolejkę do startu i czyści pomost.
function PierQueue:_take(): { number }
	local group = self.members
	self.members, self.endsAt = {}, nil
	return group
end

-- „Płyń teraz”: tylko ktoś z kolejki. Zwraca grupę albo nil.
function PierQueue:go(id: number): { number }?
	if not self:has(id) then
		return nil
	end
	return self:_take()
end

-- Upływ czasu. Zwraca grupę, gdy odliczanie się skończyło, inaczej nil.
function PierQueue:tick(now: number): { number }?
	if self.endsAt == nil or now < self.endsAt then
		return nil
	end
	return self:_take()
end

return PierQueue
