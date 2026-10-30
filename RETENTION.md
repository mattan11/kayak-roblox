# Retencja: jak zachęcić do powrotu i ścigania się

Stan na 2026-10-30. Gra ma zostać prosta, więc liczy się kolejność: mało kodu, dużo powodów do następnej rundy.
Szacunki pracy i oceny efektu to **moje założenia**, nie dane. Prawdę pokażą pomiary (`PUBLISHING.md`).
Szacunki zakładają, że działa już krok 2 z `PROGRESS.md` (wyścig kilku graczy). Dziś kodu gry jeszcze nie ma.

## Główna myśl

Mała gra będzie zwykle mieć pusto. Jeśli zabawa wymaga obcych ludzi na serwerze, nie zadziała.
Dlatego najpierw **rywalizacja asynchroniczna**: z własnym rekordem, duchem i czasami znajomych. Działa przy 1 graczu.

Co na to Roblox:

- W [rekomendacjach](https://create.roblox.com/docs/discovery) najważniejsze sygnały to m.in. play days i odsetek
  szybkich wyjść po pierwszej grze. Wspólne dni ze znajomymi (joiny, zaproszenia, serwery prywatne) są na liście „ważne”.
- Od [sierpnia 2026](https://devforum.roblox.com/t/boost-your-discovery-by-building-games-people-want-to-play/4779042)
  Home mocniej waży długoterminową retencję i monetyzację.
- [Dokumentacja retencji](https://create.roblox.com/docs/en-us/production/analytics/retention) radzi: D1 to jasna pętla
  i frajda w około 5 minut, D7 to cele i różnorodność, D30 to nowości i funkcje społeczne, m.in. rankingi.
  To ten sam porządek co niżej.

Monetyzacji na razie nie dodajemy. To poligon, a cel to powód, żeby wrócić jutro.

## Mechaniki wg stosunku efekt/koszt

| # | Mechanika | Praca | Efekt | Wskaźnik do obserwowania |
|---|-----------|-------|-------|--------------------------|
| 1 | Szybki restart solo | 0,5 dnia | bardzo duży | wyścigi na sesję |
| 2 | Rekord osobisty, medale, ekran „ile brakło” | 1 dzień | bardzo duży | wyścigi na sesję, D1 |
| 3 | Międzyczasy względem rekordu | 0,5 dnia | duży | odsetek pobitych rekordów |
| 4 | Duch własnego rekordu | 1–1,5 dnia | duży | wyścigi na sesję, D1 |
| 5 | Zaproszenie znajomych | 0,5 dnia | duży | zaproszenia, sesje wspólne |
| 6 | Serwery prywatne (darmowe) | 0,5 dnia | średni | sesje wspólne |
| 7 | Ranking znajomych + duch znajomego | 2 dni | duży | D7, sesje wspólne |
| 8 | Ranking globalny trasy | 1 dzień | średni | wejścia w ranking |
| 9 | Codzienna trasa | 2–3 dni | duży | D7, play days |
| 10 | Kosmetyki kajaków za grę | 1–2 dni | średni | D7 |
| 11 | Roblox Events i ogłoszenia | 1 godz. na akcję | mały/średni | wejścia z eventu |
| 12 | Powiadomienia | 1 dzień | średni | CTR, turn-off rate |
| 13 | Kolejne rzeki | 1–2 dni na rzekę | duży, ale drogi | D7, D30 |

## Szczegóły

**1. Szybki restart solo.** W `ARCHITECTURE.md` po mecie jest `results` 10 s i `countdown` 10 s, czyli 20 s czekania.
Gdy gracz jest sam na serwerze, skrócić to do 2–3 s i dać duży przycisk „Jeszcze raz”. Tanie, a wprost wydłuża sesję.

**2. Rekord i medale.** `PersonalBest` już jest w planie. Dodać brąz, srebro i złoto na trasę, czasy w `Config`,
wyliczone z bota z testów balansu. Medal to cel dla kogoś, kto nie ma szans na górę rankingu.

**3. Międzyczasy.** 3–4 punkty na trasie, na ekranie `+0,4 s` lub `-0,2 s` względem rekordu. Serwer i tak liczy `s`.
Gracz wie w połowie, że idzie na rekord, i nie wychodzi.

**4. Duch.** Serwer co 0,2 s zapisuje pozycję z `Hull.Position` i kurs. Tak jak przy czasie, nie ufamy danym z klienta.

- Rozmiar (moje wyliczenie): 3 min × 5 próbek/s = 900 próbek. Po 6 bajtów to ok. 5 KB, dużo poniżej
  [limitu 4 MB na klucz](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).
- Własny duch w profilu ProfileStore, po jednym na trasę. Klient odtwarza go z interpolacją jako półprzezroczysty kajak
  bez kolizji.
- Zapis tylko przy nowym rekordzie, po weryfikacji wyniku.

**5. Zaproszenia.** Przycisk „Zaproś” na ekranie wyników i przed startem.
[Prompt wywołuje klient](https://create.roblox.com/docs/production/promotion/invite-prompts):
`CanSendGameInviteAsync` w `pcall`, potem `PromptGameInvite`. Do zaproszenia można dołożyć `LaunchData` (do 200 znaków)
i odczytać je na serwerze przez `GetJoinData()`. Na początek: „ściga się z Tobą” + rekord zapraszającego.
Bez nagród za zaproszenia, bo łatwo je farmić.

**6. Serwery prywatne.** [Włącza się w Creator Dashboard](https://create.roblox.com/docs/en-us/production/monetization/private-servers.md):
Audience > Access Settings > Allow private servers. Można bez opłat (Requires Robux wyłączone).
Gra musi być wcześniej **publiczna**, a dzieci poniżej 13 lat mogą nie móc dołączyć, zależnie od ustawień rodzica.
Kod prawie bez zmian, tylko test (`game.PrivateServerId`). Później można dać właścicielowi przycisk startu.

**7. Ranking znajomych.** Dla małej gry ważniejszy niż globalny: nikt nie pobije nieznanej czołówki,
ale znajomego już tak. `Players:GetFriendsAsync` da listę, serwer czyta czasy z ordered store i trzyma je w pamięci
przez kilka minut. Trzeba pilnować [budżetu odczytów](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)
`60 + 40 × gracze` na minutę na serwer, więc np. max 50 znajomych. Tę samą ścieżką: duch najlepszego znajomego.

**8. Ranking globalny.** Własna tablica na [ordered data store](https://create.roblox.com/docs/tutorials/use-case-tutorials/data-storage/create-leaderboard),
osobny klucz na rzekę, czas jako liczba całkowita (setne sekundy). Budżet listowania jest mały
(`5 + 2 × gracze`), więc wynik odświeżać rzadko i cache'ować.

Wbudowany [ranking Friends/Global](https://create.roblox.com/docs/players/leaderboards) odpada na razie: jest w becie,
aktywny może być tylko jeden na grę, a dokumentacja nie mówi, czy niższy wynik wygrywa. My mamy czasy i kilka tras.

**9. Codzienna trasa.** Bez generowania rzek. Ta sama rzeka, inny układ skał z ziarna daty UTC, wspólny dla wszystkich.
`Random.new(ziarno)` daje to samo na serwerze i kliencie, a skały to tylko dane `{at, side, r}`.

- Zmiana następuje na początku wyścigu, nie w trakcie. Działający serwer dostaje nowy układ w następnej rundzie.
- Test Lune: bot przepływa układ z 30 dni, sprawdza też minimalny prześwit.
- Ranking dnia w [sorted map](https://create.roblox.com/docs/cloud-services/memory-stores/sorted-map) z wygaśnięciem
  np. 48 h (maks. 45 dni). Sorted map to nie trwały zapis: do profilu trafia sam medal dnia.
- Dowolna liczba prób, bez kar. Nagroda: medal dnia i licznik, który tylko rośnie.

**10. Kosmetyki.** Bez waluty i bez sklepu: odblokowania za progi. Np. kolor za każde 10 km, wzór za 10 złotych medali,
ślad wody za 20 medali dnia. Tylko wygląd, fizyka jest równa. Lista w `Config`, stan w profilu.

**11. Events.** [Bez kodu](https://create.roblox.com/docs/production/promotion/experience-events): Engagement >
Events & Updates. Gracze mogą zapisać się na powiadomienie o starcie, można mieć 10 aktywnych wydarzeń.
Dobre na „Puchar weekendu” lub premierę rzeki. Update'y: do 60 znaków, raz na 3 dni, idą do osób z włączonymi powiadomieniami.
Do Trending trzeba 1000 RSVP, więc tego nie planujemy.

**12. Powiadomienia.** [Warunki](https://create.roblox.com/docs/en-us/production/promotion/experience-notifications):
min. 100 wizyt, opt-in, wiek 13+, max 1 dziennie na grę, zasięg zależy od reakcji graczy, a dostawa nie jest gwarantowana.
Prosić o zgodę (`PromptOptIn`) po pierwszym rekordzie, nie po wejściu do gry. Prompt pokazuje się najwyżej raz na 30 dni.
Jedyna treść na start: „{imię} pobił Twój czas na {rzeka}”. Bez fałszywego pośpiechu: dokumentacja każe go unikać.

**13. Rzeki.** Dane w `content/rivers`, ale każda to strojenie i kolejny ranking. Dokładać dopiero, gdy dane pokażą,
że gracze znają jedyną trasę i odchodzą. Najlepiej każdą z jedną cechą: bystrza, ciasne zakręty, rozlewiska.

## Cele „jeszcze jedna runda”

Po każdym wyścigu pokazać **jeden** najbliższy cel, wybrany w tej kolejności:

1. „0,8 s do srebra” (blisko medalu)
2. „Duch uciekł o 1,2 s” (blisko rekordu)
3. „Anka ma czas 2:14, brakuje Ci 3 s” (znajomy)
4. „Do nowego koloru: 1,2 km”
5. „Trasa dnia czeka”

Do tego przycisk „Jeszcze raz” jako główny. Reguła: cel osiągalny w jednej rundzie, a przegrana pokazana jako „mało brakowało”.

## Czego nie robić

- **Streaków z resetem** i nagród za logowanie dzień po dniu. Liczniki tylko rosną, opuszczony dzień nic nie zabiera.
- Dziennych limitów prób, energii i fałszywego pośpiechu.
- Lootboxów i płatnej przewagi. Monetyzacja to osobny temat, a tu zepsułaby porównywalność czasów.
- Rankingu bez weryfikacji. Fizyka jest po stronie klienta, więc wynik wchodzi tylko po
  sprawdzeniu na serwerze: prędkość, skoki pozycji, `s` rosnące bez przeskoków.

Uwaga: zderzenia z innymi kajakami psują czas w trybie wieloosobowym. Jeśli zaczną denerwować, dzienny ranking
liczyć tylko z przejazdów solo.

## Kolejność wdrożenia

| Etap | Co | Kiedy | Praca (założenie) |
|------|----|-------|-------------------|
| 0 | 1, 2, 3 + zdarzenia analityczne | przed pierwszą publikacją | 2–3 dni |
| 1 | 4, 5 | test ze znajomymi | 2 dni |
| 2 | 7, 6, 8 | gdy pętla daje frajdę, przy wyjściu do publicznej | 3–4 dni |
| 3 | 9, 10 | gdy D1 jest OK, a D7 słabe | 3–5 dni |
| 4 | 11, 12, 13 | gdy jest publiczność, do której da się mówić | w miarę potrzeby |

Po każdym etapie: pomiar, dopiero potem następny. Jeśli gracze nie wracają po mechanice 4, kolejne mechaniki tego nie uratują,
trzeba wrócić do samego pływania.

## Decyzje z 2026-10-30: rzeki i tryby

Szczegóły w `VISION.md`, sekcja „Rzeki i tryby”.

- **7 stałych rzek** (3 łatwe, 2 średnie, 2 trudne) zamiast 5–10 na poziom. Mniej tras skupia graczy na pomostach, a nauka
  rzeki jest celem: gracz wraca po lepszy czas.
- **Rzeka tygodnia:** nowa trasa i osobny ranking co tydzień, bez kary za opuszczenie tygodnia.
- **Tryb Bitwa:** zabawa ze znajomymi obok poważnych rankingów.
- **Cele długoterminowe:** waluta, kosmetyki, medale, skarby na rzekach (`MONETIZATION.md`).

Założenie do sprawdzenia w danych: czy gracze rzeczywiście odchodzą z nudy trasą. Zanim powstanie Rzeka tygodnia, porównać
to z funnelem z `PUBLISHING.md`.
