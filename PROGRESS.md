# Postęp

## ▶ NASTĘPNY KROK (stan na 2026-10-31)

River Riders: Kayak Race. Wioska (start place) i Spływ są opublikowane dla testerów. Tryby: Wyścig, Bitwa, Wodna bitwa. Testy Lune: 310.

**Do sprawdzenia na dwóch kontach (komputer + telefon):**
1. Czy pomost prowadzi na właściwą rzekę, czekanie na grupę, zderzenia kajaków w grupie.
2. Kod błędu 2 przy teleporcie: raz na telefonie, nie powtórzył się. Jeśli wróci: `adb devices`, bez `logcat -d` z potokiem (ADB się wieszało), F9 → Server. Podejrzenia: `TeleportResult` 2 (GameNotFound) albo przestarzała para `ReserveServerAsync` + `ReservedServerAccessCode` (zamiennik: `TeleportOptions.ReservedServerId`). Sprawdzić też, czy gracz, który nie dotarł, nie blokuje czekania na grupę (`expected`, limit 15 s).
3. Test z rodziną.

Przed publiczną premierą: aktualizacja oceny zawartości (Bitwa) i dopracowanie wyglądu Bitwy, o które poprosił Marek.

Potem: analityka wg `PUBLISHING.md` (są `RaceFinished` i `RaceRating`), 2–3 nowe rzeki, kosmetyka (`COSMETICS.md`), turnieje (`TOURNAMENTS.md`).

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

Odstępstwa od `ARCHITECTURE.md`: `PaddleEcho` nie wraca do nadawcy; solo krótsze wyniki i odliczanie (6 s + 5 s).
