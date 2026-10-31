-- Wszystkie teksty interfejsu w jednej tabeli (dla TS: plik tłumaczeń). %d i %s wypełnia string.format.

return {
	hintStrokeLeft = "W lewo",
	hintStrokeRight = "W prawo",
	hintBrace = "Hamuj i skręć",
	hintKeysStrokeLeft = "A / ←",
	hintKeysStrokeRight = "D / →",
	hintKeysBraceLeft = "Q",
	hintKeysBraceRight = "E",

	waiting = "Czekamy na graczy…",
	startIn = "Start za %d s",
	go = "START!",
	nextRace = "Dołączysz w następnym wyścigu",
	finished = "Meta! %s",
	newRecord = "Nowy rekord!",

	place = "Miejsce %d/%d",
	record = "Rekord %s",
	noRecord = "Rekord –:––",

	resultsTitle = "Wyniki",
	resultsTitleRecord = "Wyniki — nowy rekord!",
	topTitle = "Top 10",
	resultRow = "%d. %s",
	noResults = "Nikt nie dopłynął",

	-- Indeks = stopień medalu (Medals.RANKS).
	medalNames = { "Brąz", "Srebro", "Złoto" },
	medalNamesOf = { "brązu", "srebra", "złota" },
	medalNew = "Nowy medal: %s!",
	medalHeld = "Twój medal: %s",
	medalNone = "Bez medalu",
	medalGoal = "Do %s brakuje %.1f s",
	medalTop = "Masz najwyższy medal",

	feedbackAsk = "Jak się grało?",
	feedbackThanks = "Dzięki!",

	votes = "Płyną dalej: %d · Do wioski: %d · Decydują: %d",
	votesAlone = "Zostajesz sam: reszta wraca do wioski",
	again = "Jeszcze raz",
	againWaiting = "Czekamy…",
	toVillage = "Do wioski",
	toVillageWaiting = "Płyniemy…",

	-- TravelNotice: serwer wysyła klucz, nie gotowe zdanie (dla TS: jak kod błędu mapowany na komunikat).
	-- Nieznany klucz = travelDefault, żeby gracz nigdy nie zobaczył surowej nazwy.
	travelDefault = "Nie udało się wrócić do wioski. Spróbuj jeszcze raz.",
	travel = {
		["travel.failed"] = "Nie udało się wrócić do wioski. Spróbuj jeszcze raz.",
		["travel.studio"] = "W Studio teleport nie działa.",
	},
}
