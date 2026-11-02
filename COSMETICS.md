# Wygląd: kajaki, wyposażenie, odblokowania

Plan z 2026-10-31. Pierwsza wersja (v1): tylko odblokowania za grę, bez waluty i sklepu.
**[Z]** oznacza założenie do sprawdzenia, a nie fakt z kodu lub pomiaru.

## 0. Stan wdrożenia v1 (2026-11-02): zmiany względem planu

Decyzje Marka z 2026-11-02 są nadrzędne wobec sekcji 2, 4, 7 i 8 poniżej. Wdrożone (gałąź `agent/locker`):

- **Gwiazdki zamiast liczników.** Na każdej rzece najwyższy medal daje brąz 1★, srebro 2★, złoto 3★ (7 rzek, najwyżej 21★).
  Gwiazdek się nie wydaje: próg tylko odblokowuje, na zawsze. Nowy rodzaj `unlock = { kind = "stars", min = N }`.
  Rodzaje `stat`, `medals`, `riverMedal`, `treasures`, `shop` nie są jeszcze obsługiwane; `robux` jest w kodzie jako „nigdy za grę”, bez produktów.
- **Tylko dwa sloty:** `kayak` i `paint`. Kask, kamizelka, wiosło i ślad później (dojdą przez szablon i `Reconcile`).
- **Skórki z modeli**, nie z Part: `render = { kind = "model", template, paintable, swatch }`, szablony w `ReplicatedStorage.LookAssets`
  (tylko w Studio, brak = klasyk). Skórki z teksturą mają stały wygląd, kolor działa tylko na klasyku.

| id | Szablon | Próg |
|---|---|---|
| `kayak_classic` | `KayakClassic` | domyślny, kolor na `Paint` |
| `kayak_round` | `KayakRound` | 1★ |
| `kayak_duck` | `KayakDuck` | 3★ (docelowo Robux) |
| `kayak_racer` | `KayakRacer` | 4★ |
| `kayak_shark` | `KayakShark` | 6★ |
| `kayak_icebreaker` | `KayakIcebreaker` | 8★ |
| `kayak_rocket` | `KayakRocket` | 10★ |
| `kayak_neon` | `KayakNeon` | 12★ (docelowo Premium za Robux) |
| `kayak_phoenix` | `KayakPhoenix` | 14★ |
| `kayak_gold` | `KayakGold` | 16★ |
| `kayak_kraken` | `KayakKraken` | 18★ |
| `kayak_ice_dragon` | `KayakIceDragon` | 20★ (docelowo Premium za Robux) |
| `kayak_dragon` | `KayakDragon` | 21★ |

Kolory (tylko klasyk): `paint_auto` (kolor z `userId`, domyślny), `paint_sunset` 0★, `paint_lagoon` 1★, `paint_forest` 1★,
`paint_lemon` 2★, `paint_berry` 3★, `paint_snow` 4★, `paint_night` 5★.

- **Moduły:** `CosmeticRules` nazywa się `Shared.Cosmetics` (`stars`, `isUnlocked`, `evaluate`, `canEquip`, `sanitize`, `look`, `grantAll`).
  `LookService` na spływie tylko zakłada wygląd. Medale zostały w `Shared.Medals` (`migrate` bez zmian), `records` nie dodane.
- **Szkielet i skóra:** `Shared.KayakBody` buduje folder `Look` (szablon albo kajak z Part), `Hull` jest zawsze niewidoczny.
  `KayakService.setLook` zmienia skórę także na pływającym kajaku. `Config.STUDIO_KAYAK` działa dalej, ale tylko na spływie.
- **Szafka nie przy placu, tylko na jeziorze:** gracz cały czas pływa, więc to ring boi (`LakeLayout.locker`, ok. `(-82, 94)`,
  południowy zachód) z budką na plaży za nim, między domkami pod kątem 112° i 150°. System `VillageLocker`, strefa `workspace.Locker.LockerZone`.
- **Okno:** dwie zakładki (Kajaki, Kolory), kafelki z progiem ★ i kłódką, licznik ★, podgląd 3D (jeden `ViewportFrame`), „Załóż”.
  Wybór zablokowanej pozycji pokazuje ją w podglądzie i powód blokady. „Nowe” znika po wyjściu z zakładki lub zamknięciu okna.
- **Nie zrobione w v1:** `UnlockToast` na spływie, znacznik nad budką, `nextGoal`, medale na kafelkach `RiverPicker`.
- `Config.COSMETICS_STUDIO_ALL = true`: w Studio profil zawsze z `store.Mock` (tymczasowy) i wszystko odblokowane. Poza Studio bez znaczenia.

## 1. Zasady

1. **Nie sprzedajemy mocy.** Wygląd nie zmienia fizyki. Pozycja w katalogu nie ma żadnego pola liczbowego wpływającego na ruch.
2. **Serwer decyduje** o odblokowaniu i założeniu. Klient tylko prosi, a o odblokowanie prosić w ogóle nie może.
3. **Odblokowanie jest na zawsze.** Medale i przedmioty tylko przybywają, także po zmianie progów (zapadka).
4. **Bez kar i pośpiechu** (`RETENTION.md`): liczniki tylko rosną, bez dziennych serii.
5. **Kształt nie kłamie.** Kolizje liczy `KayakPhysics` (3 koła, `KAYAK_RADIUS` 1,2, `HULL_REACH` 2,8), więc widoczny kajak musi mieć ok. 8 studs długości.

Dlaczego fizyka jest bezpieczna z założenia: `KayakPhysics` liczy punkt 2D i nie zna modelu, a `Hull` jest prowadzony przez sztywne `Align`. Wygląd to wyłącznie części bez kolizji i bez masy.

**Różnice wobec `RETENTION.md`, pkt 10:** katalog leży w `content`, nie w `Config`, bo to dane, a nie liczby do strojenia (czasy medali zostają w `Config`). Progi za kilometry i medale dnia odpadają, bo tych liczników i trybu jeszcze nie ma. Szacunek „1–2 dni” był za niski: dochodzi profil w wiosce i szafka, realnie 4–6 dni pracy **[Z]**.

## 2. Katalog (dane)

Plik `src/shared/content/CosmeticCatalog.luau`, tablica jak `RiverCatalog`. Sloty: `kayak`, `paint`, `paddle`, `helmet`, `vest`, `trail`.

```lua
{ id = "kayak_racer", slot = "kayak", label = "Strzała",
  render = { kind = "parts", shape = "racer" },  -- później: { kind = "model", template = "Kayak_Racer" }
  unlock = { kind = "stat", stat = "races", min = 25 } },
```

Pola dozwolone: `id`, `slot`, `label`, `render`, `unlock`, `hidden`, `order`. Spec odrzuca każde inne pole. `id` nigdy się nie zmienia, bo trafia do profilu.

Rodzaje `unlock` (unia z polem `kind`):

| kind | Pola | Kiedy działa |
|---|---|---|
| `default` | — | v1, ma każdy, nie trafia do profilu |
| `stat` | `stat` (`races`, `wins`, `records`), `min` | v1 |
| `medals` | `rank`, `count` (na tylu rzekach co najmniej taki medal) | v1 |
| `riverMedal` | `river`, `rank` | v1 |
| `treasures` | `river`, `count` | po skarbach, dziś `hidden = true` |
| `shop` | `price` | po walucie |
| `robux` | `productId` | po płatnościach |

Rodzaje `shop` i `robux` nigdy nie przechodzą przez `evaluate()`: nadaje je tylko serwerowy zakup.

| # | id | Slot | Nazwa | Warunek |
|---|---|---|---|---|
| 1 | `kayak_classic` | kajak | Klasyk | domyślny |
| 2 | `paint_auto` | kolor | Barwa załogi (dzisiejszy kolor z `userId`) | domyślny |
| 3 | `paddle_basic` | wiosło | Zwykłe | domyślny |
| 4 | `helmet_none` | kask | Bez kasku | domyślny |
| 5 | `vest_none` | kamizelka | Bez kamizelki | domyślny |
| 6 | `trail_foam` | ślad | Piana | domyślny |
| 7 | `vest_orange` | kamizelka | Pomarańczowa | 1 ukończony wyścig |
| 8 | `paint_sunset` | kolor | Zachód słońca | 3 wyścigi |
| 9 | `paddle_wood` | wiosło | Drewniane | brąz na 1 rzece |
| 10 | `paint_forest` | kolor | Las | 10 wyścigów |
| 11 | `helmet_red` | kask | Czerwony | 1 wygrana z innymi |
| 12 | `vest_blue` | kamizelka | Niebieska | 5 pobitych rekordów |
| 13 | `trail_river` | ślad | Błękit | srebro na 1 rzece |
| 14 | `paddle_carbon` | wiosło | Karbonowe | 5 wygranych |
| 15 | `kayak_round` | kajak | Pękaty | brąz na `Mountain` |
| 16 | `kayak_racer` | kajak | Strzała | 25 wyścigów |
| 17 | `trail_gold` | ślad | Złoty | złoto na 1 rzece |
| 18 | `helmet_gold` | kask | Złoty | złoto na 2 rzekach |
| 19 | `kayak_bottle` | kajak | Butelkowiec | później: pełna kolekcja skarbów, `hidden` |
| 20 | `kayak_dragon` | kajak | Smok | później: Robux, `hidden`, przykład modelu |

Tempo **[Z]**: pierwsza nagroda po pierwszym wyścigu, kolejna po ok. 10 minutach gry. `kayak_round` to przedmiot „dla odważnych”: wymaga wyjścia na trudną rzekę.

## 3. Medale

Czasy w `Config.RIVER_MEDALS[riverId] = { gold, silver, bronze }` (sekundy). Propozycja **[Z]**, punkt wyjścia to bot i czas Marka z `PROGRESS.md`:

| Rzeka | Brąz | Srebro | Złoto | Podstawa |
|---|---|---|---|---|
| `Test` (Leśna Struga) | 2:40 | 2:15 | 1:58 | bot 2:35; Marek 1:53 **[Z: ten czas padł na tej rzece]** |
| `Mountain` (Górski Potok) | 3:10 | 2:45 | 2:25 | bot 3:05; szacunek człowieka 2:25 |

- Reguła: brąz to trochę wolniej niż bot, złoto wymaga czystego przejazdu dobrego gracza.
- Po publikacji strojenie z `RaceFinished`, cel **[Z]**: brąz ok. 70% graczy na rzece, srebro 30%, złoto 5–10%.
- Lepiej zacząć od surowych progów: poluzowanie niczego nie psuje, a zaostrzenie zostawia stare medale.
- Rzeka bez wpisu nie daje medali. Spec wymaga wpisu dla każdej rzeki `available`.
- Medal liczy serwer z czasu przyjętego przez `RaceLogic` i zapisuje najwyższy zdobyty stopień.
- Tryb Bitwa i Rzeka tygodnia nie dają medali stałych, dopóki nie zostanie to osobno postanowione.

## 4. Zapis w ProfileStore

Wspólny szablon dla obu miejsc, w `src/server/PlayerProfile.luau`:

```lua
{
  bestTimes = {}, races = 0, wins = 0,      -- jak dziś
  schema = 0,                               -- 0 w szablonie celowo, patrz migracja
  records = 0,                              -- pobicia istniejącego rekordu (pierwszy czas się nie liczy)
  medals = {},                              -- [riverId] = 1 brąz | 2 srebro | 3 złoto
  cosmetics = {
    owned = {},                             -- [itemId] = { via = "play", at = os.time() }
    unseen = {},                            -- [itemId] = true, znacznik „Nowe” w szafce
    equipped = { kayak = "kayak_classic", paint = "paint_auto", paddle = "paddle_basic",
                 helmet = "helmet_none", vest = "vest_none", trail = "trail_foam" },
  },
}
```

- `equipped` nigdy nie ma pustego slotu, bo `Reconcile` wypełniłby go domyślnym. „Bez kasku” to przedmiot `helmet_none`.
- `via` (`play`, później `shop`, `robux`, `grant`) odróżnia źródło przy zwrotach i analizie.
- Pól `wallet`, `treasures`, `receipts` **nie dodajemy teraz**. Dojdą przez szablon i `Reconcile`, a `owned` i `unlock` są na nie gotowe.
- Rozmiar: 100 przedmiotów to ok. 3–4 KB **[Z]**, daleko od limitu 4 MB.

**Migracja.** `Reconcile` dopisuje brakujące pola, więc gdyby szablon miał `schema = 1`, stary profil dostałby numer bez migracji. Dlatego szablon ma 0, a po `Reconcile`:

1. `schema == 0`: `medals` z `bestTimes` i `Config.RIVER_MEDALS`, `records` zostaje 0 (historii nie da się odtworzyć), potem `schema = 1`.
2. Przy każdym wczytaniu, niezależnie od `schema`: `evaluate()` nadaje przedmioty należne wg statystyk (idempotentne) i dopisuje je do `unseen`. Dzięki temu dopisanie przedmiotu do katalogu działa wstecz bez migracji.
3. Przy każdym wczytaniu `sanitize()`: slot z nieznanym, nieposiadanym lub źle przypisanym przedmiotem wraca do domyślnego.

Stare serwery, które jeszcze działają, nie usuwają nieznanych pól, więc przejście jest bezpieczne, ale **oba miejsca publikujemy razem**.

## 5. ProfileStore w wiosce i blokada sesji

**Dostęp.** Dziś pakiet leży w `src/server/Packages`, poza drzewem wioski. Bez przenoszenia, wzorem wstawki `Place`, w `village.project.json` pod `Server`:

```json
"Packages": { "$path": "src/server/Packages" },
"PlayerProfile": { "$path": "src/server/PlayerProfile.luau" }
```

Ścieżka `script.Parent.Packages` działa wtedy tak samo w obu miejscach. Nie dajemy tego do `src/shared`: kod serwera nie ma trafiać do klienta. Oba miejsca są w tym samym doświadczeniu, więc widzą ten sam store `Profiles`.

`PlayerProfile` przejmuje z `PlayerData` wczytywanie i zwalnianie sesji oraz daje `get(player)` i `onLoaded`. Rzeczy spływowe (rekord, `Leaderboard`, medale) zostają w `PlayerData`.

**Blokada przy teleporcie.** Odczytane z `ProfileStore.luau`:

- Sesję zwalnia `EndSession` w `PlayerRemoving`, więc rozwiązanie jest takie samo jak w `TravelService`: nic nie zapisujemy ręcznie.
- Gdy serwer docelowy trafi na żywą sesję, prosi o jej zakończenie przez `MessagingService`, czeka 5 s, potem co 10 s, a przejmuje po ok. 40 s (`SESSION_STEAL`).
- Czekanie gwarantuje świeże dane: założony kask zdąży się zapisać, bo nowa sesja startuje dopiero po zwolnieniu starej.

**Skutki i obsługa:**

- **Nowość:** dziś wioska nie trzyma sesji, więc spływ wczytuje profil od razu. Po zmianie może czekać do ok. 5 s **[Z: zmierzyć]**. Gra działa dalej, bo `enroll` nie czeka na profil, a wygląd dochodzi po wczytaniu.
- Nieudany teleport niczego nie zmienia: gracz nie opuścił serwera, sesja trwa.
- Sesji **nie kończymy przed teleportem**. Skróciłoby to czekanie, ale przy nieudanym teleporcie trzeba by ją odzyskiwać, a do tego ruszać `MatchService`. Wracamy do tego tylko, gdy pomiar wyjdzie źle.
- Profil `nil`: wioska pokazuje domyślny wygląd i szafkę z napisem „Nie udało się wczytać”, zakładanie wyłączone. Spływ gra bez zapisu, jak dziś.
- Dłuższa kolejka zapisów na tym samym kluczu przy szybkich teleportach to opóźnienie, nie utrata danych **[Z]**.
- Każdy wczytany profil to jedna subskrypcja `MessagingService` obok tematów `MatchService`. Sprawdzić limity przy pełnej wiosce **[Z]**.

**Studio.** Bez dostępu do API ProfileStore działa na danych tymczasowych, ale z włączonym dostępem pisze do prawdziwych profili. Flaga `Config.COSMETICS_STUDIO_ALL` działa tylko przy `RunService:IsStudio()`, używa `store.Mock` i daje wszystkie przedmioty.

## 6. Skąd spływ wie, co gracz założył

**Z własnego profilu i tylko stamtąd.** Nie używamy danych teleportu, bo przechodzą przez klienta, ani wpisu w MemoryStore, bo to druga kopia tej samej prawdy. Wioska zapisuje `equipped`, spływ je czyta, a blokada sesji gwarantuje kolejność.

`MatchService`, `MatchQueue` i bilety **nie wymagają żadnej zmiany**.

Przebieg na spływie:

1. Gracz dołącza, `enroll` stawia kajak z wyglądem domyślnym (`KayakService.place`).
2. Profil się wczytuje: `sanitize`, potem `LookService` woła `KayakService.setLook(player, look)` i zakłada wyposażenie.
3. Kajak zmienia wygląd, zwykle w trakcie zbierania grupy lub odliczania (`RACE_GATHER_TIME` 15 s + 10 s). Spóźniony profil zmienia tylko wygląd, nigdy czas.
4. Atrybut kajaka `LookTrail` niesie id śladu dla wszystkich klientów.

Spływ w v1 tylko czyta `equipped`. Zmiana wyglądu odbywa się wyłącznie w wiosce, a nowy przedmiot nie zakłada się sam.

## 7. Modele: dziś z Part, później z Blendera

**Podział kajaka na szkielet i skórę.** Dziś `KayakService.build` miesza jedno z drugim.

- **Szkielet** (zostaje w `KayakService`, stały dla wszystkich): `Hull`, `Seat`, `Paddle`, `PaddleJoint`, `Root`, oba `Align`. `Hull` i `Paddle` stają się niewidoczne, rozmiary bez zmian. Kontrakt z `ARCHITECTURE.md` i klient (`resolveRig`, `KayakVisuals`, kamera, efekty) zostają nietknięte.
- **Skóra** (nowy `src/shared/KayakBody.luau`): folder `Look` z widocznymi częściami, spawanymi do `Hull` i `Paddle`, zawsze przez jedną funkcję: `CanCollide/CanTouch/CanQuery = false`, `Massless = true`.
- Moduł jest w `shared`, bo ten sam kod buduje podgląd w szafce u klienta.
- Zmiana wyglądu: usuń `Look`, zbuduj nowy, potwierdź `SetNetworkOwner` (komentarz w `seatPlayer`: nowe złożenie wymaga potwierdzenia).

`render` to jedna ścieżka dla obu rodzajów modeli:

| Rodzaj | Dziś | Później |
|---|---|---|
| Kajak | `{ kind = "parts", shape }`: parametry kształtu (klasyk, racer, round ze `SpecialMesh` jak kajaki przy pomoście) | `{ kind = "model", template }`: `MeshPart` w folderze `Look`, `Hull` dalej niewidoczny |
| Kolor | `Color3` na częściach oznaczonych jako lakier; `paint_auto` to dzisiejsze `COLORS[userId % 6]` | to samo przez `MeshPart.Color` lub kolor tekstury |
| Wiosło | drążek i dwie łopaty | `MeshPart` przyspawany do `Paddle` |
| Kask, kamizelka | `Accessory` z `Handle` (Part + `SpecialMesh`), `Humanoid:AddAccessory` na `HatAttachment` i `BodyFrontAttachment`, co obsługuje R6, R15 i skalę postaci **[Z: sprawdzić na kilku awatarach]** | `MeshPart` jako `Handle` |
| Ślad | kolor pasków z istniejącej puli `wakes` | to samo, ewentualnie drugi kolor |

**Modele później:** szablony w `ReplicatedStorage.LookAssets` z `assets/look.rbxm`, wpięte w **oba** pliki projektu Rojo. Układ jak kajak: środek w `Hull`, przód −Z, ok. 8 studs. Brak szablonu oznacza powrót do klasyka zamiast błędu. Eksport wg skilla `roblox-3d-assets`.

**Obudowa rozmiaru** (spec dla `parts`, Studio dla modeli): długość 7,5–8,5, szerokość do 2,4, wysokość do 1,6 studs, a wiosło jak dziś (`bladePoint` zakłada zasięg 3,2).

**Telefon, 8 graczy:**

| Pozycja | Budżet **[Z]** |
|---|---|
| Kajak z Part | do 14 części (dziś 10) |
| Kask + kamizelka | do 4 części |
| Razem 8 graczy | do 144 części, plus stałe 58 z puli efektów |
| Kajak z modelu | 1–2 `MeshPart`, do ok. 3000 trójkątów, jedna wspólna tekstura |

- **Ślad nie dodaje ani jednej części.** `emitWake` przekazuje kolor do `spawnWakeStrip`, a ten ustawia `Color` tylko przy zmianie. Pula `FX_WAKE` (16) zostaje wspólna. Bez `Trail`, `Beam` i własnych emiterów.
- Części skóry mają `CastShadow = false` poza kadłubem.
- Wygląd zmienia się rzadko i zdarzeniowo: żadnej pracy co klatkę.
- Podgląd w szafce to jeden `ViewportFrame`, a nie osiem. Budowany przy otwarciu okna, usuwany po zamknięciu.
- Test na najsłabszym telefonie Marka przy 8 kajakach przed dodaniem modeli.

## 8. Szafka w wiosce i powiadomienia

**Miejsce.** Szopa „Szafka” przy placu, ok. `(28, 104)`, frontem do placu **[Z]**. To skraj placu, gdzie `treeFits` nie stawia drzew, między tablicą wyników a domkiem. Obok stoi wyeksponowany kajak-ozdoba i tablica z napisem. Budują je nowy system `VillageLocker.luau` i folder `workspace.Locker` ze strefą `LockerZone`. Dzięki temu `VillageWorld` zostaje bez zmian. Liczby w `Config`. Pozycję obejrzeć w Studio.

**Okno.** Kontroler `src/village/client/Controllers/Locker.luau`, wzór i styl z `RiverPicker`:

- W strefie pojawia się przycisk „Szafka”, w tym samym miejscu co „Wybierz rzekę” (strefy się nie pokrywają).
- Układ dla wysokości 400: po lewej podgląd (kajak + manekin z Part z kaskiem i kamizelką), po prawej 6 zakładek slotów i siatka kafelków z przewijaniem. Cele dotyku co najmniej `UI_BUTTON_HEIGHT` tam, gdzie się da.
- Kafelek: posiadany, założony (obwódka), nowy (znacznik), zablokowany (kłódka i warunek z postępem, np. „Wyścigi 7/10”).
- Kliknięcie zablokowanego pokazuje podgląd bez zakładania. Podgląd jest tylko lokalny.
- Kliknięcie posiadanego wysyła `CosmeticAction`. Kafelek zmienia się dopiero po `CosmeticState` od serwera.
- Przedmioty `hidden` są niewidoczne.

**Powiadomienia:**

- Spływ: `CosmeticUnlocked` po mecie lub po wygranej, nowy kontroler `UnlockToast.luau` z własnym `ScreenGui`, bez ruszania `HudController`. Medal i przedmiot w jednym krótkim komunikacie: „Srebro: Górski Potok” i „Nowe: Błękit”. Pokazywane po mecie, nigdy w trakcie płynięcia.
- Wioska: po wczytaniu, gdy `unseen` nie jest puste, komunikat „Nowe w szafce: 2” i znacznik nad szopą (`BillboardGui`).
- `unseen` jest w profilu, więc gracz nie zgubi nagrody, jeśli wyjdzie zaraz po mecie. Otwarcie zakładki czyści jej znaczniki przez `("seen", slot)`.

Później, tanio: `CosmeticRules.nextGoal(stats)` da cel „Do nowego koloru: 2 wyścigi” na ekran wyników (`RETENTION.md`) oraz medale na kafelkach `RiverPicker`.

## 9. Bezpieczeństwo

Nowe zdarzenia w `Remotes`:

| Nazwa | Kierunek | Treść |
|---|---|---|
| `CosmeticState` | serwer → gracz | `owned`, `equipped`, `unseen`, statystyki, `medals`, flaga `ready` |
| `CosmeticAction` | klient → serwer | `("equip", slot, itemId)` albo `("seen", slot)` |
| `CosmeticUnlocked` | serwer → gracz | lista `itemId`, opcjonalnie `(riverId, medal)` |

- **Nie ma zdarzenia „odblokuj”.** Odblokowanie powstaje wyłącznie na serwerze: z czasu przyjętego przez `RaceLogic` i z liczników profilu.
- `CosmeticAction` idzie przez `Remotes.onServer` (limit ok. 4/s, zryw 8 **[Z]**). Handler sprawdza typy, slot, istnienie przedmiotu, `item.slot == slot`, posiadanie oraz wczytany profil. Błąd przepada po cichu.
- Spływ nie ufa wiosce: `sanitize` przy każdym wczytaniu, więc uszkodzony profil daje najwyżej wygląd domyślny.
- Strefy szafki nie sprawdzamy na serwerze celowo: gracz może założyć tylko to, co ma, więc nic to nie chroni.
- Katalog w `ReplicatedStorage` jest publiczny i to jest w porządku. Ceny też. Nigdy nie decyduje kopia u klienta.
- Oszust zmieni u siebie wygląd lokalnie, ale zobaczy to tylko on.
- Wygrane można nabijać drugim kontem. Daje to wyłącznie wygląd, więc akceptujemy to w v1. Rankingu to nie dotyka.
- Później: `shop` i `robux` tylko po potwierdzeniu po stronie serwera, `ProcessReceipt` idempotentny przez `receipts` w profilu i działający w każdym miejscu, gdzie można kupić. Bez płatnych losowań (`MONETIZATION.md`).

## 10. Kroki i podział pracy

Warunek wejścia: commit stanu bazowego (commit tylko na prośbę Marka). `Config`, `Remotes`, `VillageWorld` i oba `Texts` są wśród zmienionych plików.

| Krok | Agent | Co | Pliki (wyłączne) | Bramka |
|---|---|---|---|---|
| 1 | A: Dane | Katalog, reguły, medale, kontrakt sieciowy | nowe: `content/CosmeticCatalog`, `CosmeticRules`, specy; **`Config`, `Remotes`** | testy Lune |
| 2 | B: Profil | Wspólny profil, migracja, wioska w ProfileStore | nowy `src/server/PlayerProfile`, `PlayerData`, `village.project.json`, nowy `src/village/server/Systems/VillageCosmetics` (tylko stan i `equip`) | publikacja obu miejsc, pomiar czekania, stare konto bez utraty danych |
| 3 | C: Spływ | Medale i nagrody w wyścigu, skóra, wyposażenie, ślad, komunikat | nowe: `shared/KayakBody`, `shared/GearBody`, `Systems/LookService`, `Controllers/UnlockToast`; `KayakService`, `WaterEffects`, `src/client/ui/Texts` | Play: kajak i ślad; 8 kajaków na telefonie |
| 4 | D: Wioska | Szafka: świat, okno, podgląd, komunikat | nowe: `Systems/VillageLocker`, `Controllers/Locker`; `src/village/client/Texts` | Play na telefonie |
| 5 | Główny | Test całości, dokumenty | `ARCHITECTURE.md`, `PROGRESS.md`, `VISION.md` | test końcowy z sekcji 11 |

**Kolejność:** A, potem B, potem C i D równolegle. Oba odwołują się tylko do modułów z kroków 1–2 oraz do `KayakBody` (podgląd), więc **C najpierw kończy `KayakBody`** albo D startuje po tym pliku.

**Bez konfliktów:**

- `Config` i `Remotes` zmienia wyłącznie A i od razu dopisuje wszystko, co potrzebne reszcie. Inni tych plików nie ruszają, a brakujący klucz zgłaszają głównemu agentowi.
- Systemy i kontrolery ładują się same z folderów, więc nowe pliki nie wymagają zmian w skryptach `init`.
- Nikt nie rusza `MatchService`, `MatchQueue`, `RiverPicker`, `VillageWorld`, `HudController` ani `RaceService`.
- `PlayerData` ma wywołanie zwrotne `onProgress` (wzór: `TravelService.onGiveUp`), a nagrody obsługuje `LookService`, więc `RaceService` zostaje bez zmian.

## 11. Testy

**Lune:**

- `CosmeticCatalog.spec`: unikalne `id`; poprawne sloty; dokładnie jeden `default` na slot; tylko dozwolone pola; warunki wskazują istniejące rzeki i statystyki; `shop` i `robux` są `hidden` w v1.
- `CosmeticRules.spec`: `medalFor` na granicach; `evaluate` idempotentne, zapadka po zmianie progów; `shop`/`robux` nigdy nie nadawane; `canEquip` odrzuca obcy slot, brak posiadania, śmieciowe typy; `sanitize`; migracja `schema` 0 z `bestTimes`, migracja dwukrotna daje ten sam wynik; profil z samymi `bestTimes`, `races`, `wins` po scaleniu z szablonem.
- `Medals`: każda rzeka `available` ma czasy, `gold < silver < bronze`.
- `KayakBody.spec`: dla każdego kształtu limit części, wszystkie części `Massless` i bez kolizji, obudowa rozmiaru **[Z: `Instance.new` działa w tym runnerze; sprawdzić]**.
- Niezależność fizyki: źródła `KayakPhysics` i `KayakController` nie wymagają modułów wyglądu.
- `ClientSyntax.spec` sprawdza tylko klienta spływu, bo runner buduje `default.project.json`. Kod wioski trzeba trzymać cienki, logikę w `shared`, a kontroler `Locker` weryfikować w Play.

**Play w Studio:** flaga `COSMETICS_STUDIO_ALL`, każdy przedmiot na kajaku, zmiana wyglądu po usadzeniu nie odbiera sterowania, wiosło dalej się animuje, ślad u dwóch graczy (Test Server).

**Po publikacji (Studio tego nie sprawdzi):**

1. Stare konto: medale i nagrody wstecz, stare rekordy nietknięte.
2. Założenie kasku, od razu „Wybierz rzekę”: kask widoczny na spływie, zapisany czas czekania.
3. Złoty przejazd, wyjście zaraz po mecie: nagroda jest, „Nowe” w wiosce.
4. Nieudany teleport: zakładanie dalej działa.
5. Porównanie czasu tego samego przejazdu i bota na kajakach `classic` i `racer`: identyczna fizyka.
6. Telefon + komputer, 8 kajaków: FPS względem stanu sprzed zmian.

## 12. Ryzyka

| Ryzyko | Skutek | Obsługa |
|---|---|---|
| Wolniejsze wczytanie profilu na spływie | Wygląd dochodzi później | Pomiar w kroku 2; zapasowo koniec sesji przed teleportem |
| Zapomnienie o publikacji obu miejsc | Rozjazd katalogu lub szablonu | Publikacja razem, punkt w `PROGRESS.md` |
| Problem teleportu na telefonie (kod błędu 2) dalej otwarty | Test kroków 2–5 niemiarodajny | Najpierw zamknąć `PROGRESS.md`, „NASTĘPNY KROK” |
| Zmiana `Look` na trwającym złożeniu psuje własność sieciową | Szarpnięcie kajaka | `SetNetworkOwner` po zmianie; awaryjnie zmiana tylko przy `place` |
| Kaski na fryzurach i dużych awatarach | Brzydkie przenikanie | `Accessory`, test na kilku awatarach, kask opcjonalny |
| Czasy medali złe na starcie | Złoto za łatwe lub poza zasięgiem | Surowy start, strojenie z danych, zapadka |
| Zakres rośnie (KISS, Anchorfall) | Opóźnienie wzrostu retencji | Cięcie: najpierw kolor, ślad, medale; kształty i kaski potem |
| Kosmetyki przed duchami i rzekami, wbrew `VISION.md` i etapom `RETENTION.md` | Praca nad D7 przed potwierdzeniem D1 | Decyzja nr 1 |

## 13. Decyzje Marka (2026-10-31)

Ustalone: 1. medale od razu, reszta po duchach. 2. Czas 1:53 padł na `Test`, startujemy od surowych progów. 3. Kask i kamizelka widoczne także w wiosce.
Pytania 4 i 5 są rozstrzygnięte wg rekomendacji, dopóki Marek nie zdecyduje inaczej.

## 14. Pytania oryginalne

1. **Kolejność:** robimy to teraz, przed duchami i kolejnymi rzekami? Rekomendacja: medale teraz, bo to też pkt 2 w `RETENTION.md`, reszta po duchach.
2. **Czasy medali:** czy czas 1:53 padł na `Test`? Czy zaczynamy od surowych progów z sekcji 3?
3. **Wyposażenie w wiosce:** czy kask i kamizelka mają być widoczne na postaci także w wiosce? Rekomendacja: tak.
4. **Wygrane jako warunek:** zostawiamy `helmet_red` i `paddle_carbon`, skoro mała gra często jest pusta? Rekomendacja: zostawić, ale tylko dwa przedmioty.
5. **Miejsce szafki:** przy placu, czy szopa przy brzegu obok pomostu? Rekomendacja: plac.
