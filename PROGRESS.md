# Postęp

## ▶ NASTĘPNY KROK (stan na koniec 2026-10-30)

River Riot: Kayak Race. Dwa miejsca działają osobno w Studio. Testy Lune: 104. **Nic nie jest zacommitowane.**

Sprawdzone w Play: wioska (teren, pomosty, chodzenie), panel kolejki, „Płyń teraz” z komunikatem Studio, start spływu
i wyboru rzeki (fallback), „Do wioski” z komunikatem Studio.

Do sprawdzenia:
1. Publikacja obu miejsc i test teleportu (2 konta): serwer zarezerwowany, MemoryStore, wybór rzeki, czekanie na grupę.
   `ReserveServerAsync` jest w dokumentacji oznaczone jako przestarzałe; gdyby zawiodło, zmiana w `reserve()` w PierService.
2. Ekran wyników z przyciskami „Jeszcze raz” i „Do wioski” (nieoglądany), przelot przez wodospad, kamera w kanionie.
3. Spokojna rzeka w Play po zmianach, wyścig kilku graczy, telefon (ADB), zapis rekordu na żywo.

Znane drobiazgi: dziewiąta osoba na pełnym pomoście widzi „8/8”, a „Płyń teraz” nic nie daje; ponawianie teleportu jest
w dwóch miejscach; nazwy pomostów są robocze. Przy zmianie miejsca Rojo zostawia stare skrypty: usunąć je ręcznie w Edit.

Rzeki: `Config.ACTIVE_RIVER` wybiera Test albo Mountain (teraz Mountain: 3 wodospady, kanion, bot ok. 3:05, szacunek dla człowieka ok. 2:25; spokojna: bot 2:35, szacunek ok. 2:00). Wioska nie jest jeszcze zaczęta: układ i kolejność w `VISION.md`, sekcje „Wioska i spływ” oraz „Rzeki i tryby”.

Tempo wybrane w teście 2026-10-30: 0,85 s (ciąg 23, skręt 2,4), czas Marka 1:53. Przy 0,7 s było 1:56 i hamowanie z obracaniem przestawało być potrzebne. `CURRENT_SCALE = 0.7`. Kajak bez wiosłowania utyka na
trasie i nie dopływa w 400 s (w grze obowiązuje limit 300 s) — do oceny, czy to nie za surowe.

Potem wg `RETENTION.md`: medale, międzyczasy, duch. Zdarzenia analityczne: są `RaceFinished` i `RaceRating`,
reszta listy z `PUBLISHING.md` do dodania.

Odstępstwa od `ARCHITECTURE.md`: `PaddleEcho` nie wraca do nadawcy; solo krótsze wyniki i odliczanie (6 s + 5 s).
Znane: błąd `rbxassetid://203785492` w konsoli nie pochodzi z kodu gry.
