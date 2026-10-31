# Architektura (kontrakt między serwerem a klientem)

## Podział odpowiedzialności

- `src/shared` — czysta logika, gotowa i przetestowana: `Config`, `River`, `KayakPhysics`, `Remotes`, `RateLimit`,
  `content/rivers/Test`. Liczby tylko w `Config`.
- `src/server/init.server.luau` + `Systems/*` — start dwufazowy jak w Rocket Forge: `init()` wszystkich, potem `start()`.
- `src/client/init.client.luau` + `Controllers/*` — to samo po stronie klienta.
- `Remotes.onServer(name, rate, burst, handler)` na serwerze (limit zapytań), `Remotes.get(name)` wszędzie indziej.

## Kto o czym decyduje

- **Klient** liczy fizykę swojego kajaka (`KayakPhysics.step`) i ustawia cele `AlignPosition.Position` oraz
  `AlignOrientation.CFrame`. Kajak należy sieciowo do gracza (`SetNetworkOwner`), więc ruch sam się replikuje.
- **Serwer** ma fazy wyścigu, czas, zapis rekordów. Odczytuje pozycję kajaka z `Hull.Position` i sam liczy `s`
  przez `River:query`. Sprawdza też oszustwa: prędkość ponad rozsądny limit albo skok pozycji = odrzucenie wyniku.

## Świat

- Współrzędne: `Vector2(x, z)` to `Vector3(x, y, z)`. Lustro wody: **y = 0**, teren brzegu: y = 4.
- Rzeka: `River.new(require(Shared.content.rivers.Test))`, ta sama na serwerze i kliencie.
- `workspace.Kayaks` — folder (tworzy serwer); kajak to Model o nazwie `tostring(userId)`, `PrimaryPart` = `Hull`.
  Części: `Hull` (korzeń), `Seat`, `Paddle` (część wiosła na `Motor6D` o nazwie `PaddleJoint` w Hull),
  `Attachment` w Hull o nazwie `Root`, `AlignPosition` i `AlignOrientation` w Hull (OneAttachment, Rigid).
  Wszystko `CanCollide = false`, `Massless = true` oprócz Hull. Rozmiar kajaka ok. 2 × 1 × 8 studs.
- Atrybut kajaka `Finished` (bool) — gracz na mecie, klient przestaje sterować.

## Fazy wyścigu (`RaceState`: phase, phaseEndsAt)

`waiting` (brak graczy) → `countdown` (10 s, do dołączania; ostatnie 3 s duże odliczanie) → `racing` (do mety
wszystkich albo limitu 300 s; po pierwszym na mecie reszta ma 60 s) → `results` (10 s, `RaceResults`) → `countdown`.

- Na początku `countdown` serwer tworzy kajaki i wysyła każdemu `Reset(x, z, heading)` (rozstawienie w poprzek
  rzeki co `SLOT_SPACING`, przy `START_DISTANCE`).
- Klient liczy fizykę tylko w fazie `racing`, do mety. Gracz, który wszedł w trakcie wyścigu, płynie sam dla
  siebie od startu (czas liczony od jego `Reset`) i wchodzi do następnego wyścigu.
- Rekord osobisty na trasę: `ProfileStore` (`src/server/Packages`), wysyłany przez `PersonalBest`.

## Dwa miejsca (kontrakt wioska ↔ spływ)

- **Wioska:** `village.project.json`, port 34901, placeId 75278412187467 (miejsce startowe). Kod: `src/village/server`,
  `src/village/client`, wspólne `src/shared`.
- **Spływ:** `default.project.json`, port 34900, placeId 74365646024707. Kod: `src/server`, `src/client`.
- `Shared.Places`: `Places.placeId("race")`, `Places.current().id` ("village" | "race").
- Kolejka: `Shared.MatchQueue` + `Systems/MatchService`, sekcja „Wioska 2.0”. Stan gracza: atrybuty `QueueRiver`, `QueueReady`, `QueueTraveling`.

### Przejście wioska → spływ (wzór: Anchorfall `TravelService`, `PLAN_WORLD.md`)

1. Pomost kończy odliczanie. Serwer wioski: `TeleportService:ReserveServerAsync(placeId)` → (kod, privateServerId).
2. Zapis w MemoryStore (`MemoryStoreService:GetSortedMap("Races")`, klucz `privateServerId`, wygasa po 10 min):
   `{ river = "Mountain", expected = liczba graczy }`.
3. `TeleportAsync(placeId, gracze, options)` z `TeleportOptions.ReservedServerAccessCode = kod`.
4. Serwer spływu czyta wpis po `game.PrivateServerId`. **Wyboru rzeki nie bierzemy z danych teleportu:** przechodzą przez
   klienta i służą tylko jako podpowiedź. Brak wpisu (Studio, błąd) → `Config.ACTIVE_RIVER`.
5. Serwer spływu ustawia atrybut `workspace.RiverId`. Klient buduje `Session.river` dopiero po pojawieniu się tego atrybutu.
6. Pierwsze odliczanie rusza, gdy dotrą wszyscy z `expected` albo po 15 s.
7. Nieudany teleport (`TeleportInitFailed` lub błąd `pcall`): do 3 prób co 2 s, potem gracz wraca na pomost. Po teleporcie
   dane gracza są zapisane, bo `ProfileStore` zwalnia sesję przy wyjściu. Wioska na razie nie używa `ProfileStore`.

### Przejście spływ → wioska

Zwykły `TeleportAsync(Places.placeId("village"), { gracz })`. W Studio teleport nie działa: gracz dostaje komunikat
i zostaje na miejscu (`RunService:IsStudio()`), bez błędów.

### Po wyścigu

Ekran wyników ma przyciski „Jeszcze raz” i „Do wioski”. Wyścig wraca automatycznie po `results` i odliczaniu. Gdy wszyscy
na serwerze kliknęli „Jeszcze raz”, odliczanie skraca się do 3 s. Serwer zarezerwowany: nikt obcy nie dołączy.

### Nowe zdarzenia w `Remotes`

Wioska: `PierState` (serwer → wszyscy: pierId, liczba, koniec odliczania z `GetServerTimeNow`), `PierAction` (klient → serwer:
"leave" | "go", pierId), `TravelNotice` (serwer → gracz: klucz tekstu, np. błąd teleportu).
Spływ: `RaceAction` (klient → serwer: "again" | "village").

### Uzupełnienia po implementacji

- `RiverBuilder.river` jest dostępne dopiero po `RiverBuilder.init()`; `init.server.luau` woła go jako pierwszego.
- `RaceTicket` czyta wpis z MemoryStore, `Systems/TravelService` wraca do wioski, `Systems/MatchService` obsługuje kolejkę.
- `TravelNotice` niesie klucz `travel.studio` albo `travel.failed` i idzie tylko po nieudanej podróży.
- `PaddleEcho` nie wraca do nadawcy.
- Do sprawdzenia po publikacji: `ReserveServerAsync` i `ReservedServerAccessCode` są w dokumentacji oznaczone jako przestarzałe,
  a następca (`TeleportOptions.ReservedServerId`) nie wyjaśnia związku z `game.PrivateServerId`. Kod rezerwacji jest w `reserve()` w `MatchService`.

## Wioska 2.0 (kontrakt z 2026-10-31, zastępuje pomosty i kolejkę lokalną)

- **Jeden pomost** z fizyczną planszą rzek. `content/RiverCatalog.luau` zastępuje `content/Piers.luau`: lista
  `{ id, river, label, difficulty, available }`. `id` to nazwa pliku z `content/rivers`, 7 pozycji (3/2/2), dostępne `Test` i `Mountain`.
- **Plansza:** gracz w strefie przy pomoście dostaje przycisk „Wybierz rzekę”, który otwiera okno z miniaturkami. Miniaturka
  to przebieg rzeki narysowany z danych `River`, bez wgrywanych obrazków. Jedna strefa: Part `QueueZone` w `workspace.Piers`.
- **Tablica wyników:** fizyczna, w wiosce, top 10 na rzekę z `OrderedDataStore` `Times_<river>`, nazwy jak w spływowym
  `Leaderboard`. Zmienia rzekę co kilka sekund, odświeżanie co 60 s, wszystko w `pcall`. W Studio pokazuje „Brak wyników”.

### Kolejka między serwerami (MemoryStore)

- `MatchQueue` (`src/shared`, czysta logika ze speckiem): wejście to lista biletów `{ userId, serverId, joinedAt, ready }`, wyjście to decyzja,
  które bilety startują. Start rzeki: 8 biletów, albo najstarszy czeka `PIER_COUNTDOWN` (30 s), albo wszyscy `ready`.
- Bilety: `MemoryStoreService:GetSortedMap("Tickets_<river>")`, klucz `userId`, wygasają po 60 s, serwer gracza odnawia je co 10 s.
- Lider: tylko jeden serwer wioski rozdziela grupy. Blokada przez `UpdateAsync` na kluczu `Leader` z wygaśnięciem 10 s, odnawiana co 3 s.
- Grupa: lider usuwa bilety, robi `ReserveServerAsync`, zapisuje wpis w mapie `Races` jak dotąd i ogłasza przez
  `MessagingService` temat `Match` `{ code, userIds, river }`. Każdy serwer teleportuje swoich graczy: `TeleportAsync` z `ReservedServerAccessCode`.
- Stan kolejki: lider publikuje temat `QueueState` co 2 s `{ river → { count, endsAt, ready } }`, a każdy serwer przekazuje go klientom.
- Awaria MemoryStore lub Studio: tryb lokalny, ten serwer sam jest liderem w pamięci, teleport pomijany z `travel.studio`.

### Zdarzenia `Remotes`

- `QueueState` (serwer → wszyscy): `(river, count, endsAt, ready)`, zastępuje `PierState`.
- `QueueAction` (klient → serwer): `("join", river)`, `("leave")`, `("ready")`, zastępuje `PierAction`.
- `TravelNotice` bez zmian.
