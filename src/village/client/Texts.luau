-- Wszystkie teksty interfejsu wioski w jednej tabeli (dla TS: plik tłumaczeń). %d i %s wypełnia string.format.

return {
	pierTitle = "%s · %s", -- nazwa rzeki · trudność
	pierStatus = "%d/%d, start za %d s",
	pierWaiting = "%d/%d",
	pierGo = "Płyń teraz",
	pierLeave = "Zejdź",

	-- TravelNotice: serwer wysyła klucz, nie gotowe zdanie (dla TS: jak kod błędu mapowany na komunikat).
	-- Nieznany klucz = travelDefault, żeby gracz nigdy nie zobaczył surowej nazwy.
	travelDefault = "Nie udało się wypłynąć. Spróbuj jeszcze raz.",
	travel = {
		["travel.failed"] = "Nie udało się wypłynąć. Spróbuj jeszcze raz.",
		["travel.studio"] = "W Studio teleport nie działa.",
	},
}
