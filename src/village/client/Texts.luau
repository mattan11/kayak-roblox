-- Wszystkie teksty interfejsu wioski w jednej tabeli (dla TS: plik tłumaczeń). %d i %s wypełnia string.format.

return {
	pickerOpen = "Wybierz rzekę",
	pickerTitle = "Wybierz rzekę",
	pickerClose = "X",
	pickerSoon = "Wkrótce",

	queueTitle = "%s · %s", -- nazwa rzeki · trudność
	queueStatus = "%d/%d, start za %d s",
	queueWaiting = "%d/%d",
	queueJoining = "Dołączam do kolejki…", -- do pierwszego QueueState, w którym już jesteśmy (serwer publikuje co 2 s)
	queueReady = " · gotowi %d/%d",
	queueWorld = "Liczymy graczy z całego świata",
	queueGo = "Płyń teraz",
	queueGoWaiting = "Czekamy…",
	queueLeave = "Zejdź",

	-- TravelNotice: serwer wysyła klucz, nie gotowe zdanie (dla TS: jak kod błędu mapowany na komunikat).
	-- Nieznany klucz = travelDefault, żeby gracz nigdy nie zobaczył surowej nazwy.
	travelDefault = "Nie udało się wypłynąć. Spróbuj jeszcze raz.",
	travel = {
		["travel.failed"] = "Nie udało się wypłynąć. Spróbuj jeszcze raz.",
		["travel.studio"] = "W Studio teleport nie działa.",
		["travel.unavailable"] = "Kolejka chwilowo nie działa. Spróbuj za chwilę.",
	},
}
