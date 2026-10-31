# Postęp

## ▶ NASTĘPNY KROK (stan na koniec 2026-10-30)

Wioska 2.0 (jeden pomost, plansza, okno z miniaturkami, tablica wyników, kolejka między serwerami) działa; Marek potwierdził test na dwóch kontach po publikacji, 2026-10-31. Następnie: medale, duchy, tryb Bitwa. Testy Lune: 129.

Do testu po publikacji (2026-10-31): medale, duchy, przycisk „Wyjdź”, proste sterowanie (tap po prawej = skręt w prawo, sprawdzone w Play) i przełącznik w wiosce. Testy Lune: 167. Następnie „rzeczna wioska”: gracze od razu w kajakach na jeziorze, bez nurtu.

**Przed publiczną premierą:** tryb Bitwa (przedmioty ze skrzynek, `VISION.md`), z aktualizacją oceny zawartości.

**Najpierw:** teleport wioska → spływ na dwóch kontach: komputer przeszedł, a telefon się nie połączył i Marek dostał **kod błędu 2**
przy teleporcie. Sprawdzić: czy błąd był na telefonie, F9 → Server (linie `[Pier]`) oraz logi telefonu. ADB zawiesiło się przy
zrzucie i `logcat` (timeout), więc najpierw `adb devices`, bez `logcat -d` z potokiem. Wcześniej raz pojawił się też komunikat „Nie udało się
wypłynąć” bez znanej przyczyny, więc to może być ten sam problem. Podejrzany: przestarzała para `ReserveServerAsync` +
`ReservedServerAccessCode`; dokumentacja zaleca `TeleportOptions.ReservedServerId` = GUID (`reserve()` w PierService).
Sprawdzić też, czy gracz, który nie dotarł, nie blokuje czekania na grupę (`expected`, limit 15 s).

**Niezacommitowane:** poprawka gałki, głosowanie „Płyń teraz”, licznik decyzji po wyścigu. Marek jeszcze nie zgodził się na commit.
Licznik nie był testowany z prawdziwymi graczami; wymaga publikacji obu miejsc.

River Riders: Kayak Race. Dwa miejsca działają osobno w Studio. Testy Lune: 129. **Nic nie jest zacommitowane.**

Sprawdzone w Play: wioska (teren, pomosty, chodzenie), panel kolejki, „Płyń teraz” z komunikatem Studio, start spływu
i wyboru rzeki (fallback), „Do wioski” z komunikatem Studio.

Potwierdzone przez Marka po publikacji: teleport z pomostu, głosowanie „Płyń teraz” na dwóch kontach, zderzenia kajaków, „Jeszcze raz”; na telefonie gra się lepiej niż na komputerze. Pierwsza próba teleportu raz zawiodła, przyczyna nieznana.

Do sprawdzenia:
1. Czy pomost prowadzi na właściwą rzekę (MemoryStore), czekanie na grupę.
   `ReserveServerAsync` jest w dokumentacji oznaczone jako przestarzałe; gdyby zawiodło, zmiana w `reserve()` w PierService.
2. Ekran wyników z przyciskami „Jeszcze raz” i „Do wioski” (nieoglądany), przelot przez wodospad, kamera w kanionie.
3. Spokojna rzeka w Play po zmianach, wyścig kilku graczy, telefon (ADB), zapis rekordu na żywo.

Telefon: gałka w wiosce wraca po powrocie z rzeki (wioska przywraca `TouchControlsEnabled`), potwierdzone przez Marka 2026-10-30.

Znane drobiazgi: dziewiąta osoba na pełnym pomoście widzi „8/8”, a „Płyń teraz” nic nie daje; ponawianie teleportu jest
w dwóch miejscach; nazwy pomostów są robocze. Przy zmianie miejsca Rojo zostawia stare skrypty: usunąć je ręcznie w Edit.

Rzeki: `Config.ACTIVE_RIVER` wybiera Test albo Mountain (teraz Mountain: 3 wodospady, kanion, bot ok. 3:05, szacunek dla człowieka ok. 2:25; spokojna: bot 2:35, szacunek ok. 2:00). Wioska nie jest jeszcze zaczęta: układ i kolejność w `VISION.md`, sekcje „Wioska i spływ” oraz „Rzeki i tryby”.

Tempo wybrane w teście 2026-10-30: 0,85 s (ciąg 23, skręt 2,4), czas Marka 1:53. Przy 0,7 s było 1:56 i hamowanie z obracaniem przestawało być potrzebne. `CURRENT_SCALE = 0.7`. Kajak bez wiosłowania utyka na
trasie i nie dopływa w 400 s (w grze obowiązuje limit 300 s) — do oceny, czy to nie za surowe.

Potem wg `RETENTION.md`: medale, międzyczasy, duch. Zdarzenia analityczne: są `RaceFinished` i `RaceRating`,
reszta listy z `PUBLISHING.md` do dodania.

Odstępstwa od `ARCHITECTURE.md`: `PaddleEcho` nie wraca do nadawcy; solo krótsze wyniki i odliczanie (6 s + 5 s).
Znane: błąd `rbxassetid://203785492` w konsoli nie pochodzi z kodu gry.
