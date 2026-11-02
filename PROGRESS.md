# Postęp

## ▶ NASTĘPNY KROK (stan na 2026-11-02)

River Riders: Kayak Race. Wioska (start place) i Spływ są opublikowane dla testerów. Tryby: Wyścig, Bitwa, Wodna bitwa. Testy Lune: 342. Skiny i szafka są zacommitowane, ale **jeszcze nie opublikowane**.

**Najpierw:** ręczny test szafki w Wiosce (strefa i przycisk działają, okna nie dało się kliknąć narzędziem): podpłynąć do turkusowego ringu przed budką „Szafka”, otworzyć, przejrzeć skiny i kolory, założyć, popłynąć na wyścig i sprawdzić kajak. Potem publikacja **obu** miejsc naraz (szablony `LookAssets` są w obu, sprawdzić `MeshId`). `Config.COSMETICS_ALL_USERS` odblokowuje wszystko kontom Marka — przed premierą usunąć albo zostawić świadomie.

**Skiny (13 kajaków, `content/CosmeticCatalog`):** Klasyk, Pękaty 1★, Kaczka 3★, Strzała 4★, Rekin 6★, Lodołamacz 8★, Rakieta 10★, Neon 12★, Feniks 14★, Złoty Flisak 16★, Kraken 18★, Lodowy Smok 20★, Smok 21★ (progi do dopasowania; Kaczka, Neon i Lodowy Smok docelowo Premium za Robux). Dwie drogi robienia modeli, opisane w `assets/concepts/STYLE.md`: (1) Meshy w aplikacji w Chrome — obraz Nano Banana 2 (6 kr.) albo gotowy koncept → „Obraz do 3D” Smart Topology T2.5, 15 000, tekstura, bez pozy (15 kr.) → `assets/_src/build_skin.py -- <klucz>` z `rebake` (Rekin, Neon, Lodowy Smok); (2) proste kadłuby w `assets/_src/build_simple_kayaks.py` (Strzała, Pękaty, Lodołamacz, Złoty Flisak). Szablon: części Paint (+ Cockpit, Accents, Deck…), początek = środek Hull, dno kokpitu 0,62 nad nim. Znane: w Strzale przed kokpitem wystaje czubek buta (Marek: zostaje). Do rozważenia: Rakieta od nowa przez Meshy, świecenie Neonu częścią Neon. Nadal do sprawdzenia po ostatniej publikacji: „Płyń sam”, szersze koryta, skrzynki i bramy.

**Test Marka (opublikowana wersja):**
1. Przejazdy wszystkich nowych rzek: czasy, wodospady, kamera w kanionach, czy nigdzie się nie utyka, czy kolejność trudności się zgadza.
2. Słoneczna Dolina: czy złota łąka wystarczająco odróżnia ją od Leśnej Strugi.
3. Fale po wodospadzie: paski leżą już na wodzie (zmierzone w Play), oglądnąć na żywo.
4. Solo: wyniki czekają na „Jeszcze raz” albo „Do wioski”, bez samoczynnej rundy (sprawdzone tylko testami).
5. Progi medali wg czasów Marka, zwłaszcza współczynniki średnich i trudnych rzek.

ADB: telefon bywał `offline`; pomogło przełączenie debugowania USB na telefonie i `adb kill-server`, wcześniej nie wystarczał restart samego ADB.

Opcja solo (2026-11-01): przycisk „Płyń sam” w panelu kolejki rezerwuje własny serwer bez biletu; napisana, w Play tylko panel, wyjazd do sprawdzenia po publikacji. Skrzynki i bramy z modeli też do obejrzenia po publikacji.

**Do sprawdzenia na dwóch kontach (komputer + telefon):**
1. Czy pomost prowadzi na właściwą rzekę, czekanie na grupę, zderzenia kajaków w grupie.
2. Kod błędu 2 przy teleporcie: raz na telefonie, nie powtórzył się. Jeśli wróci: `adb devices`, bez `logcat -d` z potokiem (ADB się wieszało), F9 → Server. Podejrzenia: `TeleportResult` 2 (GameNotFound) albo przestarzała para `ReserveServerAsync` + `ReservedServerAccessCode` (zamiennik: `TeleportOptions.ReservedServerId`). Sprawdzić też, czy gracz, który nie dotarł, nie blokuje czekania na grupę (`expected`, limit 15 s).
3. Test z rodziną.

Przed publiczną premierą: aktualizacja oceny zawartości (Bitwa) i dopracowanie wyglądu Bitwy, o które poprosił Marek.

Potem: analityka wg `PUBLISHING.md` (są `RaceFinished` i `RaceRating`), kosmetyka (`COSMETICS.md`), turnieje (`TOURNAMENTS.md`).

## Modele (2026-11-01)

Styl: natywny Roblox, zasady i dziennik w `assets/concepts/STYLE.md`. Modele bez tekstur, kolor z kodu. Źródło `assets/_src/build_pilot.py` → `assets/export/pilot.fbx`; szablony `ReplicatedStorage.LookAssets` zapisane w obu miejscach, nie w Rojo (Rojo gubił `MeshId` i w grze były klocki z szachownicą), `assets/look.rbxm` to tylko kopia, moduł `shared/LookAssets`, brak szablonu = stare części. W grze: kajak (`Look` na niewidocznym `Hull`), 4 drzewa, 3 skały; `treeTint` i `groundColor` w danych rzeki. Przed publikacją sprawdzić w obu miejscach, czy `MeshId` nie jest pusty. Sprawdzone w Play: Wioska, Lodowy Żleb, Słoneczna Dolina. Po publikacji na telefonie (2026-11-01, Bitwa na Lodowym Żlebie, 150 drzew): modele widoczne, jedna próbka 46 FPS, 811 MB, CPU 119%, 37,2°C; do powtórzenia dłuższym pomiarem, bo ADB po Wi-Fi się rozłączył. Wiosło, skrzynka Bitwy i słupek bramy z `assets/_src/build_props.py` są w `LookAssets` obu miejsc (17 siatek). Boje zostają kulami z części. TreeRound i TreeDouble przebudowane w `assets/_src/build_tree.py` (korona z kęp, gruby pień, 556 tr.); `assets/look.rbxm` nie ma tej zmiany ani wiosła, skrzynki i słupka: prawdziwe szablony są w miejscach. Dalej: domy, pomost, rośliny rzek.

## Rzeki

Progi medali 2026-10-31: `BestLine` (lune `run_tests.luau BestLine`) szuka dobrej linii tą samą fizyką: Test 130 s, Easy2 122, Easy3 136, Medium1 153, Medium2 159, Mountain 184, Hard2 197. Człowiek jest szybszy (Marek 1:53 na Test), więc to punkt odniesienia, nie ideał. Złoto ≈ linia × 0,95 na łatwych, 0,92 na średnich, 0,86 na trudnych (po poszerzeniu trudnych rzek 2026-11-01 progi przeskalowane czasem bota; po poszerzeniu koryt uderzenia bota: Test 11, Medium1 26, Medium2 36, Mountain 43, Hard2 54) (poziom z +9% do czasu Marka; trudne luźniej, bo pilot traci tam więcej i to szacunek), do poprawy po przejazdach ludzi.

Nowe rzeki (2026-10-31): `Easy2` Słoneczna Dolina, `Easy3` Piaskowa Łacha, `Medium1` Sosnowy Bór, `Medium2` Czerwony Kanion, `Hard2` Lodowy Żleb. `RiverRoutes.spec` pilnuje każdej trasy z katalogu: koryto bez stykania, nurt, skały, bot w limicie. Czasy bota: Easy2 130 s, Easy3 139 s, Medium1 160 s, Medium2 169 s, Hard2 197 s. W Play obejrzany początek Easy2, Easy3, Medium2 i Hard2; `Medium1` tylko przez bota. Po publikacji na telefonie (2026-10-31): okno wyboru pokazuje 7 rzek z miniaturkami, trudnością i medalami, „Płyń teraz” solo trafia na wybrany Lodowy Żleb, pierwsze 70 s tej rzeki: 44–54 FPS, ok. 850 MB, CPU 142–159%, 41,5°C. Całe trasy, wodospady i kamera na nowych rzekach czekają na przejazd Marka.

## Sprawdzone

Po publikacji, na dwóch kontach: wioska, kolejka między serwerami, teleport z telefonu, Wodna bitwa z wynikami i kolejną rundą, tablica czasów. Telefon: 41–45 FPS, ok. 1130 MB. Duchy i sterowanie potwierdzone przez Marka. Nowa walka w Wodnej bitwie działa na dwóch kontach (2026-10-31, Marek): strumień, odepchnięcie, strefa zabija, „Wodna bitwa działa ok”. Bitwa po przeróbce opublikowana i zaakceptowana przez Marka w grze (2026-10-31): skrzynki z ikonami i „?”, wymiana przedmiotu przez wpłynięcie w inną skrzynkę, 4 przedmioty bez wiosła, siatka z ogłuszeniem 2,5 s i spowolnieniem do 40% na 4 s.

W Play 2026-10-31:
- Wodospad w górskiej rzece: spadek i lądowanie działają, kanion i kamera w porządku. Przez około sekundę po spadku kamera jest jeszcze nad górnym poziomem i kajak widać przez wodę; zostawione, bo mija samo.
- Spokojna rzeka po zmianach: buduje się i płynie bez błędów.
- Samouczek: wszystkie 4 kroki zaliczają się działaniem, na końcu „Gotowe” i `TutorialDone`.

Szary ekran na zrzutach ze Studio to artefakt zrzutu, nie gra: w tym samym miejscu i czasie po restarcie Play obraz jest poprawny. Wraca losowo, także na starcie, a HUD i logika działają wtedy normalnie, więc do oceny wyglądu w Play trzeba czasem patrzeć na samo Studio.

## Znane drobiazgi

- Dziewiąta osoba na pełnym pomoście widzi „8/8”, a „Płyń teraz” nic nie daje; ponawianie teleportu jest w dwóch miejscach; nazwy pomostów są robocze.
- Przy zmianie miejsca Rojo zostawia stare skrypty: usunąć je ręcznie w Edit.
- Kajak bez wiosłowania utyka przy brzegu i nie dopływa (limit w grze 300 s), do oceny, czy to nie za surowe.
- Błąd `rbxassetid://203785492` w konsoli nie pochodzi z kodu gry.

## Strojenie

Tempo wybrane w teście 2026-10-30: 0,85 s (ciąg 23, skręt 2,4), czas Marka 1:53. Przy 0,7 s było 1:56 i hamowanie z obracaniem przestawało być potrzebne. `CURRENT_SCALE = 0.7`. Rzeki: Mountain (bot ok. 3:05, szacunek dla człowieka ok. 2:25), Test (bot 2:35, szacunek ok. 2:00).

Odstępstwa od `ARCHITECTURE.md`: `PaddleEcho` nie wraca do nadawcy; solo wyniki czekają na „Jeszcze raz” albo „Do wioski”.
