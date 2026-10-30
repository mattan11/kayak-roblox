-- Globalny ranking czasów: OrderedDataStore, jeden na rzekę, klucz = userId, wartość = czas w milisekundach.
-- Klient czyta ReplicatedStorage.TopTimes (StringValue): JSON [{ userId, name, time }], od najszybszego.
-- Ranking to dodatek: każde zapytanie jest w pcall, a błąd (brak API w Studio, limit, awaria Robloxa) zostawia starą
-- listę. Ważny jest tylko warn poza Studio. (Dla TS: `try/catch` wokół fetcha, UI pokazuje ostatnie dobre dane.)

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local RaceLogic = require(script.Parent.Parent.RaceLogic)
local RiverBuilder = require(script.Parent.RiverBuilder)

local Leaderboard = {}

local value: StringValue
local names: { [number]: string } = {} -- userId → nazwa, żeby nie pytać Robloxa przy każdym odświeżeniu

local function report(action: string, message: any)
	if not RunService:IsStudio() then
		warn(`[Leaderboard] {action}: {message}`)
	end
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	if names[userId] == nil then
		local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		if ok then
			names[userId] = name
		end
	end
	return names[userId] or "?"
end

-- Sam store też w pcall: w Studio bez API potrafi rzucić już tutaj.
local function orderedStore(): OrderedDataStore?
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "Times_" .. RiverBuilder.river.id)
	if ok then
		return store
	end
	report("store", store)
	return nil
end

-- Pobiera top N i publikuje je w TopTimes.
function Leaderboard.refresh()
	local store = orderedStore()
	if not store then
		return
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(true, Config.RANKING_SIZE):GetCurrentPage()
	end)
	if not ok then
		report("odczyt", page)
		return
	end
	local rows = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId and type(entry.value) == "number" then
			table.insert(rows, { userId = userId, name = nameOf(userId), time = RaceLogic.scoreToTime(entry.value) })
		end
	end
	value.Value = HttpService:JSONEncode(rows)
end

-- Nowy rekord osobisty. UpdateAsync, nie SetAsync: na innym serwerze mógł właśnie wpaść lepszy czas tego gracza.
function Leaderboard.submit(userId: number, time: number)
	local store = orderedStore()
	if not store then
		return
	end
	local score = RaceLogic.timeToScore(time)
	local ok, err = pcall(function()
		store:UpdateAsync(tostring(userId), function(old: number?)
			if old and old <= score then
				return nil -- nil = bez zmian
			end
			return score
		end)
	end)
	if ok then
		Leaderboard.refresh()
	else
		report("zapis", err)
	end
end

function Leaderboard.init()
	value = Instance.new("StringValue")
	value.Name = "TopTimes"
	value.Value = "[]"
	value.Parent = ReplicatedStorage
end

function Leaderboard.start()
	Leaderboard.refresh()
end

return Leaderboard
