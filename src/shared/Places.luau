-- Miejsca gry Kajaki: id → placeId i opis bieżącego miejsca (jak w Anchorfall: shared/Places).
-- Bieżące miejsce = moduł Shared.Place wstawiany przez Rojo per projekt (src/places/<miejsce>/Place.luau).
-- Brak modułu (testy Lune) → spływ. (Dla TS: mapa środowisk + `currentEnv()`.)

local Places = {}

-- placeId z Creator Hub. Wioska musi być miejscem startowym gry, a tego Roblox nie pozwala łatwo zmienić, dlatego wioska
-- używa pierwszego miejsca (startowego), a spływ dodanego później. Kod trafia do miejsc przez Rojo, więc zamiana nic nie kosztuje.
Places.IDS = {
	village = 75278412187467,
	race = 74365646024707,
}

function Places.current(): { id: string }
	local module = script.Parent:FindFirstChild("Place")
	if module and module:IsA("ModuleScript") then
		return require(module) :: any
	end
	return { id = "race" }
end

function Places.placeId(id: string): number
	return Places.IDS[id]
end

return Places
