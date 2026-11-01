-- Wszystkie liczby do strojenia w jednym miejscu (jak plik .env / constants.ts). Jednostki: studs, sekundy, radiany.

local Config = {
	ACTIVE_RIVER = "Mountain", -- która rzeka z content/rivers się wczytuje (wybór mapy przyjdzie z wioską)
	ACTIVE_MODE = "race", -- tryb w Studio: "race", "battle" albo "arena"; poza Studio decyduje wpis z wioski, a jego brak to "race"

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
	RESULTS_TIME = 10, -- ekran wyników w grupie; solo czeka na decyzję gracza
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

	-- Medale
	-- Czasy w sekundach (COSMETICS.md, sekcja 3). Rzeka bez wpisu nie daje medali, spec wymaga wpisu dla każdej dostępnej.
	RIVER_MEDALS = {
		Test = { gold = 123, silver = 135, bronze = 156 },
		Easy2 = { gold = 116, silver = 127, bronze = 146 },
		Easy3 = { gold = 129, silver = 141, bronze = 163 },
		Medium1 = { gold = 140, silver = 156, bronze = 183 },
		Medium2 = { gold = 146, silver = 162, bronze = 191 },
		Mountain = { gold = 158, silver = 175, bronze = 205 },
		Hard2 = { gold = 170, silver = 187, bronze = 219 },
	},

	-- Duchy
	GHOST_SAMPLE_INTERVAL = 0.5, -- co ile s serwer zostawia próbkę przejazdu
	GHOST_TIME_SCALE = 100, -- czas próbki w setnych sekundy
	GHOST_POSITION_SCALE = 10, -- pozycja co 0,1 stud
	GHOST_HEADING_STEPS = 256, -- pełny obrót dzielimy na tyle kroków
	GHOST_MAX_SAMPLES = 640, -- RACE_TIME_LIMIT co 0,5 s plus punkt na mecie (sprawdza spec)
	GHOST_MAX_COORD = 20000, -- dalej niż tyle studs od środka świata = uszkodzony ślad
	GHOST_MAX_BYTES = 40000, -- limit JSON-a jednego śladu; limit klucza DataStore to 4 MB, zapas zostaje też dla remote
	GHOST_TOP_REFRESH = 120, -- co ile s najwyżej serwer pyta o rekord świata
	GHOST_SAVE_TRIES = 3, -- prób zapisu
	GHOST_SAVE_WAIT = 2, -- odstęp między próbami
	GHOST_CLOSE_WAIT = 20, -- tyle s najdłużej serwer czeka przy zamknięciu na trwający zapis
	GHOST_TRANSPARENCY = 0.6,
	GHOST_VISIBLE_RADIUS = 200, -- dalej od kamery duch znika (telefon)
	GHOST_OWN_COLOR = Color3.fromRGB(150, 225, 255),
	GHOST_WORLD_COLOR = Color3.fromRGB(255, 205, 80),
	GHOST_HULL_LENGTH = 5.2, -- wymiary jak w KayakService
	GHOST_TIP_LENGTH = 1.4,
	GHOST_HULL_WIDTH = 2,
	GHOST_HULL_HEIGHT = 1,

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
	LEAVE_CONFIRM_TIME = 6, -- po tylu sekundach bez decyzji okno „Opuścić rzekę?” się zamyka
	LEAVE_TOP_OFFSET = 64, -- przycisk pod paskiem menu Robloxa
	QUEUE_CONFIRM_TIME = 4, -- jak długo klient czeka na potwierdzenie dołączenia do kolejki
	UI_TOP_SAFE = 60, -- pasek menu Robloxa zajmuje tyle pikseli ekranu od góry; wyższy margines bierzemy z GetGuiInset
	UI_PANEL_MARGIN = 6, -- odstęp panelu wyników od dolnej krawędzi ekranu
	UI_NOTICE_TIME = 4, -- jak długo widać komunikat o podróży
	UI_BUTTON_HEIGHT = 48, -- wysokość dużych przycisków (w pikselach projektu HUD)
	UI_ACTION_WIDTH = 130, -- szerokość przycisków na ekranie wyników
	PIER_PANEL_WIDTH = 290,
	PIER_PANEL_RIGHT = 12, -- odstęp panelu kolejki od prawej krawędzi: stoi z boku kajaka, tak jak panel nauki
	PIER_PANEL_SCALE_MAX = 1.3, -- niższe niż HUD_SCALE_MAX, żeby na tablecie panel nie wjechał pod przycisk skoku
	PICKER_OPEN_HEIGHT = 58, -- wysokość przycisku „Wybierz rzekę”
	PICKER_COLUMNS = 4, -- kafelki w rzędzie
	PICKER_ROWS = 2, -- rzędy widoczne bez przewijania
	PICKER_TILE_WIDTH = 172,
	PICKER_TILE_HEIGHT = 146,
	PICKER_TILE_GAP = 8,
	PICKER_THUMB_HEIGHT = 82, -- miniaturka rzeki na górze kafelka (pod nią nazwa, trudność i progi medali)
	PICKER_THUMB_PADDING = 8, -- margines wewnątrz miniaturki
	PICKER_THUMB_SEGMENTS = 28, -- Frame'ów na rzekę; 7 rzek to niecałe 200 Frame'ów, tworzonych raz
	PICKER_THUMB_LINE = 4, -- grubość linii rzeki
	PICKER_THUMB_DOT = 9, -- średnica kropki wodospadu
	PICKER_THUMB_STRETCH = 3, -- rzeki są długie i wąskie: oś poprzeczna może urosnąć tyle razy

	-- Wioska
	VILLAGE_SIZE = 560, -- bok kwadratu terenu
	VILLAGE_LAKE_Z = 0, -- środek jeziora (x = 0), układ boi: content/LakeLayout
	VILLAGE_LAKE_RADIUS = 170, -- kilka do kilkunastu sekund pływania w każdą stronę
	VILLAGE_KAYAK_SPACING = 7, -- rozsunięcie kajaków w punkcie startu (w poprzek i wzdłuż kursu)
	VILLAGE_KAYAK_COLUMNS = 5, -- kajaków w rzędzie
	VILLAGE_KAYAK_SLOTS = 20, -- po tylu graczach numeracja miejsc zaczyna się od nowa (zderzenia rozsuną ewentualny tłok)
	VILLAGE_BEACH_WIDTH = 16,
	VILLAGE_ZONE_RADIUS = 24, -- ring żółtych boi: strefa startu
	VILLAGE_ZONE_BUOYS = 20,
	VILLAGE_TREES = 44,
	VILLAGE_CAMPFIRE_X = 20, -- ognisko na południowym brzegu, między domkami
	VILLAGE_CAMPFIRE_Z = 158,
	VILLAGE_BOARD_CLEARANCE = 3, -- dolna krawędź tablic nad ziemią
	VILLAGE_BOARD_PIXELS = 20, -- gęstość SurfaceGui na tablicach (pikseli na stud)
	VILLAGE_BOARD_Z = -170, -- obie tablice na północnej plaży, po bokach strefy startu
	VILLAGE_RIVER_BOARD_X = -48,
	VILLAGE_RIVER_BOARD_WIDTH = 40,
	VILLAGE_RIVER_BOARD_HEIGHT = 28,
	VILLAGE_RESULTS_BOARD_X = 48,
	VILLAGE_RESULTS_BOARD_WIDTH = 44,
	VILLAGE_RESULTS_BOARD_HEIGHT = 32,
	VILLAGE_PICKER_BUTTON_WIDTH = 200, -- „Wybierz rzekę”: u góry, na środku, poza zasięgiem kciuków
	VILLAGE_PICKER_BUTTON_TOP = 12,
	VILLAGE_NOTICE_TOP = 80, -- komunikat o podróży pod tym przyciskiem
	RESULTS_ROTATE_TIME = 6, -- co tyle s tablica pokazuje następną rzekę
	RESULTS_REFRESH_TIME = 60, -- co tyle s nowy odczyt rankingów
	TUTORIAL_ALWAYS = false, -- true: nauka przy każdym wejściu (tylko do testów), false: tylko nowi gracze
	TUTORIAL_TICK = 0.1, -- co ile s nauka odczytuje pozycję kajaka
	TUTORIAL_TURN_ANGLE = 0.35, -- krok „skręć”: tyle radianów w dobrą stronę (ok. 20°)
	TUTORIAL_STRAIGHT_DISTANCE = 30, -- krok „płyń prosto”: tyle studs od punktu startu kroku
	TUTORIAL_BRAKE_TIME = 0.6, -- krok „hamuj”: tyle sekund trzymania wiosła po wskazanej stronie
	TUTORIAL_MARKER_HEIGHT = 9, -- znacznik celu nad wodą
	TUTORIAL_DONE_TIME = 4, -- jak długo widać „Gotowe”

	-- Podróż
	PIER_CAPACITY = 8, -- limit graczy na pomoście i w wyścigu (VISION.md)
	PIER_COUNTDOWN = 30, -- najstarszy bilet czeka najwyżej tyle
	PIER_SCAN_INTERVAL = 0.25, -- co ile s serwer sprawdza, kto stoi w strefie kolejki
	MATCH_TICKET_PREFIX = "Tickets_", -- MemoryStore: mapa biletów rzeki (klucz = userId)
	MATCH_TICKET_TTL = 60, -- bilet wygasa po tylu s bez odnowienia (serwer padł)
	MATCH_TICKET_RENEW = 10, -- co ile s serwer gracza odnawia bilet
	MATCH_LEADER_MAP = "MatchLeader", -- MemoryStore: mapa z blokadą lidera
	MATCH_LEADER_TTL = 10, -- blokada wygasa po tylu s bez odnowienia
	MATCH_LEADER_RENEW = 3, -- co ile s serwery próbują wziąć albo odnowić blokadę
	MATCH_TICK = 2, -- co ile s lider rozdziela grupy i publikuje QueueState
	MATCH_RANGE = 200, -- bilety czytane na rzekę (limit GetRangeAsync)
	MATCH_TOPIC = "Match", -- MessagingService: grupa gotowa
	QUEUE_STATE_TOPIC = "QueueState", -- MessagingService: stan kolejek od lidera
	MATCH_PUBLISH_TIMES = 2, -- Match idzie tyle razy, bo dostawa nie jest gwarantowana
	MATCH_PUBLISH_GAP = 2, -- odstęp między wysyłkami
	MATCH_TAKEN_TIMEOUT = 15, -- bilet zabrany, a Match nie doszedł: po tylu s gracz dostaje travel.failed
	MATCH_JOIN_COOLDOWN = 2, -- najmniejszy odstęp między dołączeniami gracza (każde to zapis w MemoryStore)
	MATCH_FAIL_LIMIT = 3, -- tyle błędów MemoryStore z rzędu włącza tryb lokalny
	MATCH_PROBE_INTERVAL = 30, -- w trybie lokalnym co tyle s sprawdzamy, czy MemoryStore wrócił
	MATCH_WARN_INTERVAL = 30, -- ten sam błąd usługi ostrzega najwyżej raz na tyle s
	TRAVEL_TRIES = 3, -- prób teleportu (ARCHITECTURE.md)
	TRAVEL_RETRY_WAIT = 2, -- odstęp między próbami
	TRAVEL_FLOOD_WAIT = 6, -- odstęp po wyniku Flooded (za dużo teleportów naraz)
	TRAVEL_TIMEOUT = 30, -- po tylu s bez wieści od Robloxa uznajemy, że gracz nie odleciał
	RACE_TICKET_MAP = "Races", -- MemoryStore: wpisy wyścigów (klucz = privateServerId)
	RACE_TICKET_TTL = 600, -- wpis wygasa po 10 min
	RACE_TICKET_TRIES = 3, -- prób odczytu wpisu na spływie
	RACE_TICKET_WAIT = 1,
	RACE_GATHER_TIME = 15, -- najdłuższe czekanie na grupę przed pierwszym odliczaniem
	AGAIN_COUNTDOWN = 3, -- odliczanie, gdy wszyscy kliknęli „Jeszcze raz”

	-- Bitwa
	BATTLE_TICK = 0.1, -- co ile s serwer sprawdza skrzynki i siatki (jak RACE_SAMPLE_INTERVAL)
	BATTLE_CRATE_SPACING = 120, -- co tyle studs wzdłuż rzeki rząd skrzynek
	BATTLE_CRATE_START = 60, -- pierwszy rząd tyle za linią startu
	BATTLE_CRATE_FINISH_CLEAR = 40, -- ostatni rząd najbliżej tyle przed metą
	BATTLE_CRATE_LANE = 0.55, -- boczne skrzynki: ułamek halfWidth od środka (środkowa leży na osi)
	BATTLE_CRATE_RADIUS = 5, -- zebranie: odległość środka kajaka od skrzynki (przy 55 studs/s to 2 odczyty na przejazd)
	BATTLE_CRATE_RESPAWN = 8, -- skrzynka wraca po tylu s
	BATTLE_CRATE_ROCK_CLEAR = 6, -- najmniejszy odstęp skrzynki od krawędzi skały
	BATTLE_CRATE_FALL_CLEAR = 35, -- bez skrzynek tyle studs przed i za wodospadem
	BATTLE_USE_COOLDOWN = 1, -- najmniejszy odstęp między użyciami przedmiotów
	BATTLE_BOOST_TIME = 3,
	BATTLE_MAX_SPEED = 75, -- limit anty-oszustwo w Bitwie: boost daje więcej niż wyścig
	BATTLE_BOOST_THRUST = 1.6, -- mnożnik ciągu wiosłowania w czasie boostu (klient, KayakPhysics)
	BATTLE_STUN_TIME = 2.5, -- bez wiosłowania, kajak płynie z prądem
	BATTLE_PROTECT_TIME = 4, -- ochrona po końcu ogłuszenia
	BATTLE_CANNON_RANGE = 60,
	BATTLE_CANNON_ARC_COS = 0.7, -- stożek przed dziobem: około 45° w każdą stronę
	BATTLE_BEND_SLACK = 1.5, -- cel najdalej zasięg × tyle wzdłuż rzeki: nie strzelamy przez brzeg do sąsiedniego zakola
	BATTLE_NET_BEHIND = 9, -- siatka powstaje tyle za środkiem kajaka
	BATTLE_NET_RADIUS = 5, -- kto wpłynie tak blisko, wpadł w siatkę
	BATTLE_NET_LIFETIME = 20, -- nietrafiona siatka znika po tylu s
	BATTLE_NET_SLOW_TIME = 4, -- siatka spowalnia tyle s, licząc od trafienia (czyli dłużej niż ogłuszenie)
	BATTLE_NET_SLOW = 0.4, -- ułamek prędkości, także z prądu, w czasie spowolnienia
	-- Wagi losowania skrzynki „?”: front = prowadzący, back = ostatni; miejsca pomiędzy mają wagi pośrednie. Kolejność i lista: BattleRules.ITEMS.
	BATTLE_ITEM_WEIGHTS = {
		boost = { front = 2, back = 4 },
		shield = { front = 4, back = 2 },
		net = { front = 4, back = 1 },
		cannon = { front = 0, back = 5 },
	},

	-- Wodna bitwa
	ARENA_RIVER = "Arena", -- wartość `river` w kolejce i workspace.RiverId; to nie plik z content/rivers, tylko content/ArenaLayout
	ARENA_MIN_PLAYERS = 2, -- poniżej tego runda nie rusza, a kolejka czeka bez końca (odliczanie od drugiego biletu)
	ARENA_RADIUS = 180, -- promień jeziora i początkowy promień strefy
	ARENA_SPAWN_RING = 150, -- okrąg miejsc startowych
	ARENA_HEALTH = 100,
	ARENA_CANNON_RANGE = 70,
	ARENA_CANNON_ARC_COS = 0.5, -- stożek przed dziobem: około 60° w każdą stronę, razem około 120°
	ARENA_STREAM_DPS = 8, -- obrażenia strumienia na sekundę
	ARENA_FLANK_MULTIPLIER = 1.5, -- mnożnik obrażeń z boku i z tyłu
	ARENA_FRONT_ARC_COS = 0.7, -- „z przodu” celu: około 45° od jego dziobu, reszta to bok i tył
	ARENA_TANK_SECONDS = 4, -- pełny zbiornik starcza na tyle s strumienia
	ARENA_TANK_FULL_TIME = 9, -- s ładowania od zera do pełna przy płynięciu
	ARENA_TANK_IDLE_TIME = 60, -- s ładowania od zera do pełna w miejscu
	ARENA_TANK_FULL_SPEED = 12, -- od tej prędkości (studs/s) ładowanie jest pełne; samo wiosłowanie daje około 18
	ARENA_TANK_INTERVAL = 0.25, -- ArenaTank do gracza nie częściej niż co tyle s
	ARENA_HIT_INTERVAL = 0.3, -- ArenaHit i ArenaPush najwyżej co tyle s
	ARENA_PUSH_PER_SECOND = 12, -- o tyle studs/s strumień rozpędza ofiarę w każdej sekundzie trafiania
	ARENA_ZONE_END_RADIUS = 40,
	ARENA_ZONE_TIME = 120, -- po tylu s strefa ma końcowy promień
	ARENA_ZONE_DPS = 5, -- obrażenia na sekundę poza strefą
	ARENA_ROUND_TIME = 180, -- limit rundy; potem wygrywa największa wytrzymałość
	ARENA_ALONE_TIME = 15, -- samotny gracz na serwerze zarezerwowanym wraca do wioski po tylu s
	ARENA_TICK = 0.1, -- co ile s serwer liczy strumienie, zbiorniki, strefę i fazy (jak RACE_SAMPLE_INTERVAL)
	ARENA_BURN_MAX_STEP = 1, -- najdłuższy odcinek czasu liczony naraz: przycięcie serwera nie zabija jednym obiegiem
	ARENA_STATE_INTERVAL = 1, -- co ile s ArenaState odświeża promień strefy
	ARENA_FIRE_RATE = 10, -- limit zapytań ArenaFire na sekundę: wysoki, bo odrzucone `false` zostawiłoby strumień otwarty, a sam handler tylko ustawia flagę
	ARENA_FIRE_BURST = 12,
	ARENA_TREES = 40, -- drzewa na brzegu
	ARENA_WALL_SEGMENTS = 40, -- panele ściany strefy
	ARENA_WALL_HEIGHT = 16,
	ARENA_WALL_STEP = 0.5, -- ściana przesuwa się co tyle studs: każdy ruch to replikacja wszystkich paneli
}

return Config
