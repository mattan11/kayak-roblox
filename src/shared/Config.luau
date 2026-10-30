-- Wszystkie liczby do strojenia w jednym miejscu (jak plik .env / constants.ts). Jednostki: studs, sekundy, radiany.

local Config = {
	ACTIVE_RIVER = "Mountain", -- która rzeka z content/rivers się wczytuje (wybór mapy przyjdzie z wioską)

	-- Wiosłowanie
	STROKE_TIME = 0.85, -- długość jednego machnięcia (stała, niezależnie od tempa tapania)
	STROKE_THRUST = 23, -- przyspieszenie do przodu w szczycie machnięcia (studs/s²)
	STROKE_TURN = 2.4, -- przyspieszenie obrotu w szczycie machnięcia (rad/s²); lewe wiosło → skręt w prawo

	-- Wbicie wiosła (dolne pola ekranu, Q/E, L1/R1): prawie nawrót w miejscu. Wiosło działa jak hamulec i ster:
	-- skręt W STRONĘ wbicia, mocniejszy, im szybciej woda opływa kajak.
	BRACE_TURN = 8.0, -- przyspieszenie obrotu (rad/s²) przy pełnej prędkości względem wody
	BRACE_TURN_STILL = 0.6, -- ułamek obrotu dostępny, gdy kajak stoi względem wody
	BRACE_FULL_SPEED = 12, -- od tej prędkości względem wody obrót jest pełny
	BRACE_DRAG = 2.5, -- dodatkowy opór (hamowanie względem nurtu)
	BRACE_ZONE = "bottom", -- które pola ekranu to wbicie: "bottom" albo "top" (do sprawdzenia na telefonie)

	-- Opór wody (względem nurtu). Mały do przodu, duży w bok — kajak płynie tam, gdzie patrzy dziób.
	DRAG_FORWARD = 0.7,
	DRAG_LATERAL = 4.0,
	DRAG_ANGULAR = 3.0,
	ALIGN_TO_FLOW = 0.4, -- jak mocno nurt sam ustawia dziób z prądem (pomaga początkującym)

	-- Nurt
	BEND_PUSH = 50, -- siła znoszenia na zewnątrz zakrętu (× krzywizna × prędkość nurtu)
	BEND_PUSH_MAX = 0.35, -- znoszenie najwyżej 35% prędkości nurtu
	EDGE_SLOWDOWN = 0.5, -- przy samym brzegu nurt jest o tyle wolniejszy niż na środku

	-- Skały zmieniają prąd
	EDDY_RADIUS = 2.2, -- wir za skałą: promień (× promień skały), środek tyle samo za skałą
	EDDY_BACKFLOW = 0.3, -- w środku wiru woda płynie w górę rzeki z tym ułamkiem prędkości nurtu
	ROCK_DIVERT_RANGE = 6, -- „poduszka” przed skałą: zasięg ponad promień skały
	ROCK_DIVERT = 0.35, -- odpychanie wody na boki (ułamek prędkości nurtu)

	-- Zderzenia
	KAYAK_RADIUS = 1.2, -- kajak w zderzeniach = trzy koła o tym promieniu wzdłuż kadłuba
	HULL_REACH = 2.8, -- odległość dziobu i rufy od środka
	KAYAK_CONTACT = 4, -- odległość środków dwóch kajaków przy zderzeniu
	HIT_SPIN = 0.09, -- jak mocno uderzenie poza środkiem obraca kajak
	HIT_SPIN_MIN_SPEED = 5, -- słabsze dotknięcia nie obracają (inaczej kajak drga przy ścianie)
	BOUNCE = 0.35, -- ile prędkości „w ścianę” wraca po odbiciu
	HIT_FRICTION = 0.6, -- ile prędkości wzdłuż ściany zostaje po uderzeniu

	HIT_MIN_SPEED = 2.5, -- słabsze dotknięcia nie hamują (kajak ślizga się po brzegu)

	FALL_GRAVITY = 70, -- spadanie z wodospadu (studs/s²)

	-- Fizyka liczona w stałych krokach (te same wyniki przy 30 i 120 FPS)
	STEP = 1 / 60,

	-- Wyścig
	START_DISTANCE = 15, -- gdzie stoją kajaki na starcie (studs od początku rzeki)
	START_LINE = 25, -- od tej linii liczy się czas
	FINISH_MARGIN = 30, -- meta tyle przed końcem rzeki
	SLOT_SPACING = 6, -- odstęp kajaków na starcie (w poprzek rzeki)
	RESPAWN_AFTER_FINISH = 5,

	-- Serwer
	COUNTDOWN_TIME = 10, -- faza countdown: dołączanie + odliczanie
	RACE_TIME_LIMIT = 300, -- twardy limit wyścigu
	FINISH_GRACE = 60, -- po pierwszym na mecie reszta ma tyle czasu
	RESULTS_TIME = 10, -- ekran wyników
	SOLO_RESULTS_TIME = 6, -- solo krócej: szybki restart to najtańszy sposób na „jeszcze jedną rundę”
	SOLO_COUNTDOWN_TIME = 5,
	SLOT_ROW_SPACING = 9, -- gdy kajaki nie mieszczą się w poprzek: odstęp kolejnego rzędu (w górę rzeki)
	RACE_SAMPLE_INTERVAL = 0.1, -- co ile serwer odczytuje pozycje kajaków
	MAX_KAYAK_SPEED = 55, -- limit anty-oszustwo: nurt 28 + wiosłowanie 18 + zapas (spec sprawdza bota)
	JUMP_ALLOWANCE = 150, -- ile studs „zapasu” na szarpnięcie (lag): tyle kajak może nadrobić naraz
	OFF_RIVER_TOLERANCE = 12, -- ile poza koryto (ponad halfWidth) to już oszustwo
	HINT_SEARCH_LIMIT = 30, -- większy ruch między odczytami = szukamy odcinka rzeki w całej rzece

	-- Świat
	BANK_MARGIN = 2, -- koryto w terenie szersze niż halfWidth (cylindry co 2 punkty nie zwężą go przy brzegu)
	BEACH_WIDTH = 9, -- pas piasku między wodą a trawą
	TERRAIN_PADDING = 150, -- zapas gruntu wokół rzeki
	MAX_TREES = 150,
	TREE_SPACING = 19, -- co tyle studs wzdłuż rzeki próba postawienia drzewa
	TREE_MIN_BANK_DISTANCE = 12, -- najbliżej brzegu
	TREE_MAX_BANK_DISTANCE = 100, -- najdalej od brzegu
	RANKING_SIZE = 10, -- globalny ranking: top N

	-- Klient
	-- Sterowanie
	HINT_USES = 8, -- po tylu dotknięciach podpowiedzi pól gasną
	GLIDE_DRAG = 1.5, -- wytracanie prędkości po mecie (kajak dopływa, zamiast stanąć w miejscu)

	-- Wygląd kajaka (na oko, nie wpływa na fizykę)
	KAYAK_RIDE_Y = 0.3, -- wysokość środka kadłuba nad lustrem wody (jak KAYAK_Y na serwerze)
	POSE_SMOOTH = 8, -- szybkość dochodzenia do celu kołysania
	POSE_TURN_ROLL = 0.18, -- przechył na radian/s obrotu
	POSE_ROLL_MAX = 0.35,
	POSE_STROKE_ROLL = 0.06, -- przechył na stronę wiosła przy machnięciu
	POSE_SPEED_PITCH = 0.06, -- dziób w górę przy pełnej prędkości
	POSE_FULL_SPEED = 36, -- „pełna prędkość” dla kamery i wyglądu (studs/s)
	POSE_WAVE_PITCH = 0.015,
	POSE_WAVE_ROLL = 0.02,
	POSE_BOB = 0.1, -- wysokość fali na spokojnej wodzie
	POSE_RAPIDS_WAVES = 2, -- w bystrzach fale ×(1 + tyle)
	RAPID_SPEED_FROM = 18, -- od tej prędkości nurtu woda zaczyna być bystrzem
	RAPID_SPEED_FULL = 26, -- pełne bystrze

	-- Wiosło (Motor6D PaddleJoint; drążek jest 2 studs nad kadłubem, więc łopata musi zejść mocno w dół)
	PADDLE_SWEEP = 0.7, -- wychylenie przód-tył (rad)
	PADDLE_DIP = 0.7, -- opuszczenie łopaty
	PADDLE_BRACE_YAW = 0.35, -- wbicie: łopata za biodrem
	PADDLE_BRACE_DIP = 0.8,
	PADDLE_SMOOTH = 18,
	PADDLE_BRACE_TIMEOUT = 5, -- cudze wbicie wygasa po tylu s (PaddleEcho jest zawodny, „release” może zginąć)
	TORSO_TWIST = 0.6, -- skręt tułowia gracza względem obrotu wiosła

	-- Kamera
	CAMERA_DISTANCE = 15,
	CAMERA_DISTANCE_SPEED = 5, -- dodatkowe oddalenie przy pełnej prędkości
	CAMERA_HEIGHT = 8.5,
	CAMERA_PULL_OUT_SMOOTH = 2.5, -- jak wolno kamera wraca po minięciu ściany
	CAMERA_PULL_RISE = 7, -- o ile kamera unosi się przy ścianie, żeby dalej widzieć rzekę
	CAMERA_LOOK_AHEAD = 12,
	CAMERA_RIVER_BLEND = 0.5, -- 0 = patrzy jak kajak, 1 = wzdłuż rzeki
	CAMERA_TURN_SMOOTH = 3.5,
	CAMERA_SPEED_SMOOTH = 2,
	CAMERA_FOV = 70,
	CAMERA_FOV_SPEED = 10, -- dodatkowy FOV przy pełnej prędkości
	CAMERA_SHAKE = 1.2, -- drżenie przy najmocniejszym uderzeniu (studs)
	CAMERA_SHAKE_DECAY = 6,
	HIT_FULL_STRENGTH = 15, -- od takiego state.lastHit uderzenie ma pełny efekt

	-- Efekty wody. Pule razem = 58 części + 1 emiter; więcej nigdy nie powstanie.
	FX_RADIUS = 150,
	FALL_PITCH = 0.018, -- pochylenie dziobu na 1 stud/s spadania
	FX_WATER_Y = 0.3, -- wysokość pasków nad lustrem wody
	FX_AHEAD = 110, -- zasięg losowania wzdłuż rzeki przed graczem
	FX_BEHIND = 15, -- i za nim
	FX_STREAKS = 22,
	FX_FOAM = 12,
	FX_EDDY = 8,
	FX_WAKE = 16,
	FX_STREAK_RATE = 16, -- nowych smug na sekundę
	FX_FOAM_RATE = 10,
	FX_EDDY_RATE = 6,
	FX_STREAK_LIFE = 1.6,
	FX_STREAK_PER_SPEED = 0.35, -- długość smugi na stud/s nurtu
	FX_STREAK_MIN = 1.5,
	FX_STREAK_MAX = 9,
	FX_WAKE_MIN_SPEED = 6, -- wolniej nie ma fali od dziobu ani kilwatera
	FX_WAKE_INTERVAL = 0.16,
	FX_BRACE_SPRAY_INTERVAL = 0.12,
	FX_ROCKS_REFRESH = 0.3, -- co ile s sprawdzamy, które skały są blisko

	-- HUD
	HUD_REFRESH = 0.1, -- HUD odświeża się 10 razy na sekundę, nie co klatkę
	HUD_DESIGN_HEIGHT = 400, -- układ projektowany na wysokość telefonu w poziomie
	HUD_SCALE_MAX = 1.6,
	HUD_COUNTDOWN_BIG = 3, -- ostatnie sekundy duże na środku ekranu
	HUD_GO_TIME = 1, -- jak długo widać „START!”
	FEEDBACK_ENABLED = true, -- gwiazdki po wyścigu

	-- Interfejs
	UI_NOTICE_TIME = 4, -- jak długo widać komunikat o podróży
	UI_BUTTON_HEIGHT = 48, -- wysokość dużych przycisków (w pikselach projektu HUD)
	UI_ACTION_WIDTH = 130, -- szerokość przycisków na ekranie wyników
	PIER_PANEL_WIDTH = 290,
	PIER_PANEL_LEFT = 0.42, -- lewa krawędź panelu pomostu (ułamek szerokości): gałka ruchu po lewej, skok po prawej
	PIER_PANEL_SCALE_MAX = 1.3, -- niższe niż HUD_SCALE_MAX, żeby na tablecie panel nie wjechał pod przycisk skoku

	-- Wioska
	VILLAGE_SIZE = 300, -- bok kwadratu terenu
	VILLAGE_BOUNDS = 142, -- niewidzialne ściany tyle od środka
	VILLAGE_LAKE_Z = -30, -- środek jeziora (x = 0)
	VILLAGE_LAKE_RADIUS = 90,
	VILLAGE_BEACH_WIDTH = 16,
	VILLAGE_SPAWN_Z = 110, -- miejsce pojawienia (x = 0), po stronie lądu
	VILLAGE_TREES = 32,
	PIER_START_ON_BEACH = 14, -- początek pomostu tyle od brzegu wody
	PIER_LENGTH = 38,
	PIER_STUB_LENGTH = 16, -- zaślepka „Wkrótce”
	PIER_WIDTH = 7,
	PIER_PLANK_SPACING = 2.1,
	PIER_DECK_Y = 2.6, -- wierzch desek, trochę poniżej górnego stopnia plaży
	PIER_QUEUE_START = 8, -- strefa kolejki zaczyna się tyle od początku pomostu

	-- Podróż
	PIER_CAPACITY = 8, -- limit graczy na pomoście i w wyścigu (VISION.md)
	PIER_COUNTDOWN = 30, -- odliczanie od pierwszej osoby
	PIER_FULL_COUNTDOWN = 5, -- przy komplecie skraca się do tylu sekund
	PIER_SCAN_INTERVAL = 0.25, -- co ile s serwer sprawdza, kto stoi w strefie kolejki
	TRAVEL_TRIES = 3, -- prób teleportu (ARCHITECTURE.md)
	TRAVEL_RETRY_WAIT = 2, -- odstęp między próbami
	TRAVEL_TIMEOUT = 30, -- po tylu s bez wieści od Robloxa uznajemy, że gracz nie odleciał
	RACE_TICKET_MAP = "Races", -- MemoryStore: wpisy wyścigów (klucz = privateServerId)
	RACE_TICKET_TTL = 600, -- wpis wygasa po 10 min
	RACE_TICKET_TRIES = 3, -- prób odczytu wpisu na spływie
	RACE_TICKET_WAIT = 1,
	RACE_GATHER_TIME = 15, -- najdłuższe czekanie na grupę przed pierwszym odliczaniem
	AGAIN_COUNTDOWN = 3, -- odliczanie, gdy wszyscy kliknęli „Jeszcze raz”
}

return Config
