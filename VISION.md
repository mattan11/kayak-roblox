# River Riders: Kayak Race — wizja (folder `roblox-kayak`)

Po polsku tytuł w Roblox: **River Riders: Wyścig Kajaków** (ustawić ręcznie, bez automatycznego tłumaczenia).

Prosta gra Roblox na krótkie rundy: wyścig kajaków w dół rzeki, solo albo ze znajomymi. Przyjazna telefonom.
Robiona równolegle z Anchorfall — ma zostać **mała i prosta**.

## Decyzje (2026-10-29)

- **Sterowanie = dwa przyciski.** Tapnięcie po lewej / prawej stronie ekranu (klawiatura A/D lub strzałki,
  pad L2/R2) = jedno pełne machnięcie wiosłem po tej stronie. Machnięcie ma **stałą długość** (~0,85 s, żeby każde było decyzją, a nie spamem).
- Tapnięcie w trakcie machnięcia czeka w kolejce (max 1). Spam nic nie daje — telefon i komputer równo,
  autoclicker bez sensu. **Przytrzymanie** = machnięcia jedno po drugim (odpoczynek dla kciuka).
- **Domyślnie gracz wskazuje kierunek:** tap po prawej to skręt w prawo, czyli wiosło po lewej (fizyka bez zmian). Test z rodziną 2026-10-31: odwrotne sterowanie myliło. W wiosce jest przełącznik „Sterowanie: realistyczne”.
- **Nurt robi grę:** sam niesie kajak (na prostej można odpocząć), na zakrętach znosi na zewnętrzny brzeg,
  w bystrzach jest szybki i wąsko. Najszybciej płynie środek rzeki, przy brzegu woda jest wolniejsza.
- **Uderzenie w skałę / brzeg / inny kajak = odbicie i utrata prędkości.** Bez śmierci, bez restartu.
- **Fizyka jest „udawana”**, nie woda Robloxa: kajak to punkt na płaszczyźnie (2D) liczony przez nasz kod,
  woda z terenu tylko wygląda. Kajakiem steruje urządzenie gracza (płynnie na telefonie), serwer mierzy czas.
- Wyścig 2–3 min. Bez broni w M1 — najpierw samo pływanie ma dawać frajdę.

## Wioska i spływ (decyzje 2026-10-30)

- **Dwa miejsca:** wioska (spotkania, wybór rzeki) i jedno miejsce „Spływ”. Rzeki to pliki danych, serwer spływu wczytuje
  wybraną i buduje teren przy starcie. Nowa rzeka nie wymaga nowego miejsca. Do zmierzenia: czas budowy terenu po teleporcie.
- **Jezioro = lobby:** gracz od razu pływa w kajaku po jeziorze bez nurtu, a samouczek uczy sterowania. Strefa startu to ring żółtych boi; wybór rzeki to kolejka między serwerami („3/8, start za 25 s”). Odliczanie ok. 30 s rusza z pierwszą osobą,
  a komplet startuje od razu. Przycisk „Płyń teraz” to głos: rusza, gdy kliknie cała kolejka, a solo od razu.
- **Teleport grupy:** wioska tworzy serwer zarezerwowany (`ReserveServer`) i przenosi cały pomost. Na spływie spotykają się
  gracze z tej samej wioski. Globalne dobieranie (MemoryStore) dopiero, gdy dane pokażą wiele wiosek z pustymi pomostami.
- **Po wyścigu:** każdy decyduje za siebie: „Jeszcze raz” (ta sama grupa, bez ładowania) albo „Do wioski”. Licznik pokazuje, ile osób płynie dalej, wraca i się waha. Brak decyzji = zostaje.
- **Znajomi:** ten sam pomost. Zaproszony trafia najpierw do wioski.
- **Liczba graczy:** limit 8 na wyścig; 10 po teście na telefonie.
- **Bezpieczeństwo i błędy:** wybór rzeki po stronie serwera (np. MemoryStore pod identyfikatorem serwera), nie przez dane
  teleportu z klienta. Nieudany teleport: ponowienie, potem powrót na pomost.
- **Duchy:** najlepsze przejazdy płyną obok gracza, żeby wyścig solo też był rywalizacją.
- **Kolejność:** wioska z pomostami → serwer zarezerwowany i teleport → „Jeszcze raz” → duchy.

## Rzeki i tryby (decyzje 2026-10-30)

- **Na start 7 stałych rzek:** 3 łatwe, 2 średnie, 2 trudne. Mają trwały ranking i medale. Jest już jedna łatwa (`Test`,
  do nazwania) i jedna trudna (`Mountain`), czyli do zrobienia 2 łatwe, 2 średnie, 1 trudna.
- **Rzeka tygodnia (po duchach):** generowana z ziarna wyliczonego z numeru tygodnia, ta sama dla wszystkich, z osobnym
  rankingiem i bez publikacji. Bot sprawdza każdą trasę; gdy utknie, generator bierze następne ziarno. Najpierw próba na
  kilku trasach, czy są ciekawe, a nie tylko przejezdne.
- **Rotacja stałych rzek** dopiero przy większej liczbie graczy: w wiosce np. 3 aktywne, rankingi zostają.
- **Tryb „Bitwa” (osobny, po podstawowym wyścigu):** ta sama rzeka, ale po drodze pływające skrzynki z przedmiotami.
  Osobny pomost i kolejka. Pomysły: siatka zostawiona na wodzie (zatrzymuje na parę sekund), uderzenie wiosłem z bliska
  (ogłuszenie: kilka sekund bez wiosłowania, kajak płynie z prądem), przyspieszenie na plecach fali, tarcza przed jednym atakiem.
  - Bez wpływu na rekordy, medale i rankingi: czasy z tego trybu są osobne albo wcale.
  - Słabsi w wyścigu dostają lepsze przedmioty, a ogłuszony ma chwilę ochrony przed kolejnym atakiem.
  - Przedmioty rozstrzyga serwer: klient prosi o użycie, serwer sprawdza posiadanie, zasięg i czas odnowienia, a dopiero
    potem wysyła skutek do kajaka ofiary (fizykę liczy jej urządzenie).
  - Skrzynki to dane rzeki, więc tryb działa na każdej trasie.
- **Armatka wodna:** jeden z przedmiotów trybu Bitwa, automatyczne celowanie w najbliższego gracza przed dziobem (kciuki są zajęte wiosłowaniem).
- **Wodna bitwa (po premierze, gdy będą gracze):** battle royale na jeziorze na kodzie trybu Bitwa. Polewanie zdejmuje wytrzymałość, wygrywa ostatni na wodzie, strefa kurczy się do środka, odpadający szybko wchodzą do następnej rundy. Wymaga 4–8 graczy naraz.
- **Kolejność całości:** wioska 2.0 i kolejka → medale → duchy → tryb Bitwa (**wymagany przed publiczną premierą**, decyzja Marka 2026-10-31) → pozostałe stałe rzeki → waluta, kosmetyki, skarby (`MONETIZATION.md`, plan w `COSMETICS.md`) → Rzeka tygodnia → turnieje (`TOURNAMENTS.md`).

## Monetyzacja

Nie sprzedajemy mocy: płatne są skiny, a nie przewaga w wyścigu. Szczegóły i cele długoterminowe w `MONETIZATION.md`.

## Później (nie w M1)

Dwójki (jeden wiosłuje, drugi rzuca), model kajaka z Blendera.
