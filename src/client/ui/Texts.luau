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

	-- Tryb Bitwa. Ikony to zwykłe znaki, bez wgrywanych obrazków. Klucze items = BattleRules.ITEMS.
	battle = {
		stunned = "Ogłuszony!",
		boost = "Przyspieszenie!",
		shieldHit = "Tarcza zatrzymała atak!",
		noTarget = "Nikogo w zasięgu",
		crateMark = "?",
		stars = "★ ★ ★",
		items = {
			boost = { icon = "⚡", name = "Przyspieszenie" },
			shield = { icon = "🛡", name = "Tarcza" },
			net = { icon = "🕸", name = "Siatka" },
			splash = { icon = "💦", name = "Wiosło" },
			cannon = { icon = "🌊", name = "Armatka" },
		},
	},

	-- Wodna bitwa. Ikona to zwykły znak, bez wgrywanych obrazków.
	arena = {
		fire = "STRUMIEŃ",
		empty = "PUSTO", -- zbiornik pusty: ładuje się w ruchu
		fireIcon = "🌊",
		health = "Wytrzymałość %d",
		alive = "Na wodzie: %d",
		zoneWarning = "Wracaj do strefy!",
		outSelf = "Odpadasz! Miejsce %d",
		outOther = "%s odpada",
		watching = "Oglądasz do końca rundy",
		winner = "Wygrywa %s!",
		winnerSelf = "Wygrywasz!",
		nextRound = "Dołączysz w następnej rundzie",
		resultsTitle = "Wyniki bitwy",
		ownPlace = "Twoje miejsce: %d",
	},

	-- TravelNotice: serwer wysyła klucz, nie gotowe zdanie (dla TS: jak kod błędu mapowany na komunikat).
	-- Nieznany klucz = travelDefault, żeby gracz nigdy nie zobaczył surowej nazwy.
	travelDefault = "Nie udało się wrócić do wioski. Spróbuj jeszcze raz.",
	travel = {
		["travel.failed"] = "Nie udało się wrócić do wioski. Spróbuj jeszcze raz.",
		["travel.studio"] = "W Studio teleport nie działa.",
	},
}
