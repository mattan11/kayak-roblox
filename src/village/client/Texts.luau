-- Wszystkie teksty interfejsu wioski w jednej tabeli (dla TS: plik tłumaczeń). %d i %s wypełnia string.format.

return {
	settings = {
		open = "Ustawienia",
		replay = "Powtórz naukę pływania",
		controlsTitle = "Sterowanie",
		controlsSimple = "Proste",
		controlsRealistic = "Realistyczne",
		controlsSimpleDetail = "Dotykasz strony, w którą chcesz skręcić: po prawej skręcasz w prawo.",
		controlsRealisticDetail = "Dotykasz strony, po której ma iść wiosło, jak w prawdziwym kajaku: wiosło po prawej skręca w lewo.",
		ghostsTitle = "Twój rekord na rzece",
		ghostsVisible = "Widoczny",
		ghostsHidden = "Ukryty",
		ghostsVisibleDetail = "W wyścigu obok płyną przezroczyste kajaki: błękitny to Twój najlepszy przejazd, złoty to rekord świata.",
		ghostsHiddenDetail = "W wyścigu nie widać przezroczystych kajaków z Twoim rekordem i rekordem świata.",
	},

	pickerOpen = "Wybierz rzekę",
	pickerTitle = "Wybierz rzekę",
	pickerClose = "X",
	pickerSoon = "Wkrótce",
	pickerMedalTime = "● %s", -- próg medalu na kafelku, kolor mówi który

	pickerNoMedals = "Bez medali i rekordów", -- na kafelku w strefie Bitwa
	arenaGo = "Do bitwy", -- przycisk w strefie Wodnej bitwy: bez wyboru rzeki, od razu kolejka
	modes = { race = "Wyścig", battle = "Bitwa", arena = "Wodna bitwa" },

	queueTitle = "%s · %s · %s", -- nazwa rzeki · trudność · tryb
	queueStatus = "%d/%d, start za %d s",
	queueWaiting = "%d/%d",
	queueJoining = "Dołączam do kolejki…", -- do pierwszego QueueState, w którym już jesteśmy (serwer publikuje co 2 s)
	queueNeedPlayers = "Potrzeba %d graczy", -- Wodna bitwa: gracz czeka sam
	queueReady = " · gotowi %d/%d",
	queueWorld = "Liczymy graczy z całego świata",
	queueGo = "Płyń teraz",
	queueGoWaiting = "Czekamy…",
	queueLeave = "Zejdź",
	queueSolo = "Płyń sam",

	-- Szafka (Locker): skórki kajaka i kolory. Gwiazdki: brąz 1, srebro 2, złoto 3 na każdej rzece.
	locker = {
		open = "Szafka",
		openNew = "Szafka · nowe: %d",
		title = "Szafka",
		close = "X",
		tabs = { kayak = "Kajaki", paint = "Kolory" },
		stars = "★ %d/%d", -- gwiazdki gracza / najwięcej
		need = "★ %d", -- próg na kafelku
		lock = "🔒",
		newBadge = "Nowe",
		soon = "Wkrótce",
		nameWithPaint = "%s · %s", -- skórka · kolor
		equip = "Załóż",
		equipped = "Założone",
		locked = "Zablokowane",
		lockedDetail = "%s: potrzeba %d★, masz %d★. Zdobywaj medale na rzekach.",
		loading = "Wczytuję…",
		failed = "Nie udało się wczytać. Wygląd zostaje domyślny.",
		fixedLook = "Ta skórka ma stały kolor. Kolor zmienia tylko Klasyka.",
	},


	-- LakeTutorial. Kierunki i pola dopasowuje kontroler do sterowania gracza.
	tutorial = {
		title = "Nauka %d/%d",
		skip = "Pomiń",
		next = "Dalej",
		skipAll = "Pomiń wszystko",
		areaTop = "u góry",
		areaBottom = "u dołu",
		onLeft = "po lewej",
		onRight = "po prawej",
		toLeft = "w lewo",
		toRight = "w prawo",
		fieldTop = "górne pole",
		fieldBottom = "dolne pole",
		turnTouch = "Dotknij %s %s: skręcasz %s.",
		turnKeys = "Naciśnij %s, aby skręcić %s.",
		straightTouch = "Płyń prosto: dotykaj %s na zmianę lewo i prawo.",
		straightKeys = "Płyń prosto: naciskaj na zmianę A i D.",
		brakeTouch = "Przytrzymaj %s %s: hamujesz i obracasz %s.",
		brakeKeys = "Przytrzymaj %s: hamujesz i obracasz %s.",
		zone = "Płyń do żółtego pola.",
		doneTitle = "Gotowe",
		done = "Wybierz rzekę i płyń! Na rzece prąd znosi na zakrętach, a środkiem płynie się najszybciej.",
	},

	-- TravelNotice: serwer wysyła klucz, nie gotowe zdanie (dla TS: jak kod błędu mapowany na komunikat).
	-- Nieznany klucz = travelDefault, żeby gracz nigdy nie zobaczył surowej nazwy.
	travelDefault = "Nie udało się wypłynąć. Spróbuj jeszcze raz.",
	travel = {
		["travel.failed"] = "Nie udało się wypłynąć. Spróbuj jeszcze raz.",
		["travel.studio"] = "W Studio teleport nie działa.",
		["travel.unavailable"] = "Kolejka chwilowo nie działa. Spróbuj za chwilę.",
	},
}
