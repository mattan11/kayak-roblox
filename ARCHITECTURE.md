# Architektura (kontrakt między serwerem a klientem)

## Podział odpowiedzialności

- `src/shared` — czysta logika, gotowa i przetestowana: `Config`, `River`, `KayakPhysics`, `Remotes`, `RateLimit`,
  `content/rivers/Test`. Liczby tylko w `Config`.
- `src/server/init.server.luau` + `Systems/*` — start dwufazowy jak w Rocket Forge: `init()` wszystkich, potem `start()`.
- `src/client/init.client.luau` + `Controllers/*` — to samo po stronie klienta.
- `Remotes.onServer(name, rate, burst, handler)` na serwerze (limit zapytań), `Remotes.get(name)` wszędzie indziej.

## Wspólny kod wioski i spływu

`village.project.json` montuje całe `src/client` jako `Client`, a `src/village/client` jako jego podskrypt `Client.Village` (uruchamia się
sam i startuje tylko kontrolery wioski). `KayakService` jest podpięty jako `Server.KayakService`, a używa go system `VillageKayaks`.
Wioska nie startuje `HudController`, `LeaveButton` ani `GhostController` (`RACE_ONLY` w `src/client/init.client.luau`).
`Session.river` to tam `Lake` (interfejs jak `River`, `still = true`), `Session.phase` to stałe `"free"`. Atrybut `QueueTraveling` zabiera stery.

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
   dane gracza są zapisane, bo `ProfileStore` zwalnia sesję przy wyjściu. Od szafki wioska też trzyma sesję profilu
   (sekcja „Wygląd i szafka”), więc spływ może poczekać kilka sekund na jej zwolnienie.

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

## Tryb Bitwa (kontrakt z 2026-10-31)

Ta sama rzeka co wyścig, ale po drodze skrzynki z przedmiotami. Bez wpływu na rekordy, medale, duchy i rankingi. Sterowanie to te same pola, przedmiot to jeden duży przycisk.

- **Wybór:** w oknie rzek przełącznik „Wyścig” / „Bitwa”. `QueueAction("join", river, mode)`, `mode` = `"race"` | `"battle"`. Kolejki są osobne: klucz biletów to rzeka i tryb. `QueueState` niesie `(river, count, endsAt, ready, mode)`.
- **Wpis `Races`:** `{ river, expected, mode }`. Serwer spływu ustawia atrybut `workspace.RaceMode`, brak wpisu = `"race"`. W Studio: `Config.ACTIVE_MODE`.
- **Skrzynki:** `BattleRules.crates(river)`: co `BATTLE_CRATE_SPACING` studs wzdłuż rzeki, po 3 w poprzek, z dala od skał i wodospadów. W rzędzie dwie skrzynki pokazują ikonę przedmiotu, a jedna to „?”. Serwer sprawdza zebranie po pozycji `Hull` i odnawia skrzynkę po `BATTLE_CRATE_RESPAWN` s. Klient rysuje je z tych samych danych; `workspace.Crates` nie istnieje, stan zebrania idzie przez `BattleCrate(index, available)`.
- **Przedmioty:** jeden naraz. Gracz celuje w wybraną skrzynkę, a wpłynięcie w inną wymienia przedmiot (skrzynka z tym samym zostaje). Skrzynkę „?” losuje serwer, tym lepiej, im dalej od prowadzącego:
  - `boost`: 3 s mocniejszego ciągu,
  - `shield`: blokuje jeden atak,
  - `net`: siatka na wodzie za kajakiem, pierwszego, kto w nią wpłynie, ogłusza i na 4 s spowalnia do 40% prędkości, także z prądu,
  - `cannon`: armatka wodna, automatycznie w najbliższego gracza w stożku przed dziobem, zasięg 60 studs.
- **Skutki:** `stun`: 2,5 s bez wiosłowania, kajak płynie z prądem, potem 4 s ochrony. Kajak zawsze dalej się porusza i nikt nie wypada z wyścigu.
- **Serwer decyduje:** klient wysyła `BattleUse()`. Serwer sprawdza posiadanie, czas odnowienia i zasięg z pozycji `Hull`, a potem wysyła skutek do ofiary. Fizykę liczy urządzenie gracza.
- **Zdarzenia `Remotes`:** `BattleUse` (klient → serwer), `BattleItem` (serwer → gracz: id przedmiotu lub nil), `BattleEffect` (serwer → gracz: `"stun"` | `"slow"` | `"boost"` | `"shieldHit"`, czas), `BattleCrate` (serwer → wszyscy), `BattleWorld` (serwer → wszyscy: `"net"`, x, z, id, aktywna).
- **Fizyka:** `KayakPhysics` dostaje `state.stunUntil`, `state.boostUntil`, `state.slowUntil` (czas z `os.clock` klienta) i nic poza tym. Bez wpływu w trybie wyścigu.
- **Liczby:** `Config`, sekcja `-- Bitwa`.

## Strefy na jeziorze i Wodna bitwa (kontrakt z 2026-10-31)

**Trzy strefy w wiosce**, każda z własnym ringiem boi i kolorem. `LakeLayout.zones = { { id, mode, label, color, position, radius } }`:

- `race` (żółta): okno rzek, wyścig,
- `battle` (czerwona): okno rzek, tryb Bitwa z przedmiotami,
- `arena` (niebieska): bez wyboru rzeki, od razu kolejka Wodnej bitwy.

Przełącznik Wyścig/Bitwa w `RiverPicker` znika: o trybie decyduje strefa. W `workspace.Piers` są Part `QueueZone` z atrybutem `Mode`. `MatchService` przyjmuje `join` tylko dla trybu strefy, w której gracz stoi.

**Wodna bitwa** to tryb `arena` w miejscu Spływ:

- Kolejka: `mode = "arena"`, `river = "Arena"`, klucz biletów `Arena_arena`. Start przy co najmniej 2 graczach, do 8. Solo czeka, a panel pokazuje „Potrzeba 2 graczy”.
- Świat: `content/ArenaLayout.luau` z polami jak `LakeLayout`: `center`, `radius`, `spawnRing`, `obstacles` (wyspy i skały jako koła). Serwer buduje okrągłe jezioro zamiast rzeki, klient używa `Lake`. `workspace.RaceMode = "arena"`, `RiverId = "Arena"`.
- Zasady: każdy ma 100 wytrzymałości. Przycisk strzela armatką: automatycznie w najbliższego gracza w stożku przed dziobem, zasięg 70 studs, 15 obrażeń, odnowienie 1 s. Serwer sprawdza wszystko z pozycji `Hull`.
- Kurcząca się strefa: pierścień zwęża się od `radius` do 40 studs przez 120 s; poza nim 5 obrażeń na sekundę.
- Koniec: zostaje jeden gracz albo mija 180 s (wygrywa ten z największą wytrzymałością). Odpadnięty zostaje na wodzie bez strzelania i ogląda do końca rundy. Potem `results` i automatyczna kolejna runda.
- Bez wpływu na rekordy, medale i rankingi. Wyniki: miejsca wg kolejności odpadania.

**Zdarzenia `Remotes`:** `ArenaFire` (klient → serwer), `ArenaState` (serwer → wszyscy: faza, koniec fazy, promień strefy, liczba żywych), `ArenaHealth` (serwer → gracz: wytrzymałość), `ArenaHit` (serwer → wszyscy: strzelający, cel lub nil), `ArenaOut` (serwer → wszyscy: userId, nazwa, miejsce), `ArenaResults` (serwer → wszyscy: lista).

**Liczby:** `Config`, sekcja `-- Wodna bitwa`.

### Walka w Wodnej bitwie 2.0 (2026-10-31)

Strumień zamiast pojedynczych strzałów. `ArenaFire(true/false)` otwiera i zamyka strumień, a serwer liczy co 0,1 s: zbiornik, cel, obrażenia i odepchnięcie.

- **Zbiornik:** pełny starcza na 4 s strumienia. Ładuje się w ruchu: pełne ładowanie w 8–10 s przy płynięciu, bardzo wolno w miejscu. Prędkość serwer bierze z pozycji `Hull`. Klient dostaje `ArenaTank(0..1)`.
- **Obrażenia:** 8 na sekundę, trafienie w bok lub tył × 1,5, liczone z kursu celu.
- **Odepchnięcie:** `ArenaPush(dx, dz)` idzie do ofiary, a jej klient dodaje to do prędkości kajaka.
- **Osłony:** strumień nie przechodzi przez `ArenaLayout.obstacles` (przecięcie odcinka z kołem).
- **Cel:** szerszy stożek, najbliższy gracz; `ArenaHit` dalej pokazuje strumień innym.

## Wygląd i szafka (kontrakt z 2026-11-02, plan w `COSMETICS.md`)

Skórki kajaka i kolory klasyka. Wygląd nigdy nie zmienia fizyki: `Hull` jest zawsze niewidoczny i ma stały rozmiar, a widać folder `Look`.

- **Moduły:** `content/CosmeticCatalog` (dane), `Shared.Cosmetics` (gwiazdki, odblokowania, `canEquip`, `sanitize`, `look`),
  `Shared.KayakBody` (widoczne części z szablonu `ReplicatedStorage.LookAssets` albo z Part; ten sam kod buduje kajak na serwerze i podgląd w szafce).
- **Profil:** `src/server/PlayerProfile.luau` (szablon, migracja, `get`, `onLoaded`, `start`), wspólny dla obu miejsc.
  `village.project.json` montuje pod `Server` także `Packages` i `PlayerProfile`, więc ścieżka `script.Parent.Packages` jest ta sama.
  `PlayerData` (spływ) używa go dla rekordów i medali. Pole `cosmetics = { owned, unseen, equipped }`.
- **Kajak:** `KayakService.setLook(player, look)` zmienia skórę pływającego kajaka (nowy `Look` spawany do `Hull`, potem `SetNetworkOwner`),
  a nowy kajak dostaje ostatni wygląd w `place`. `look` = `Cosmetics.look(equipped, userId)` = `{ template, color?, classicColor }`.
  Brak szablonu = klasyk, brak klasyka = kajak z Part. W Studio `Config.STUDIO_KAYAK` nadpisuje skórkę tylko na spływie.
- **Wioska:** `Systems/VillageCosmetics` (stan i zakładanie), `Systems/VillageLocker` (ring, budka, strefa `workspace.Locker.LockerZone`),
  kontroler `Controllers/Locker`. Miejsce w `LakeLayout.locker`.
- **Spływ:** `Systems/LookService` po wczytaniu profilu woła `KayakService.setLook`. Spływ tylko czyta `equipped`.

### Zdarzenia `Remotes`

- `CosmeticState` (serwer → gracz, wioska): `{ ready, failed, owned = { [id] = true }, equipped, unseen, stars, maxStars }`.
- `CosmeticAction` (klient → serwer, wioska): `("sync")`, `("equip", slot, itemId)`, `("seen", slot)`. Limit `COSMETIC_ACTION_RATE`/`BURST`.
  Handler sprawdza typy, slot, istnienie, `item.slot == slot`, posiadanie i wczytany profil. Nie ma zdarzenia „odblokuj”.
