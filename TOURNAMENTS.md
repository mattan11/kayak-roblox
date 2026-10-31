# Turnieje

Plan z 2026-10-31. Bez kodu. **[Z]** oznacza założenie do sprawdzenia.

## Zasady

- **Wstęp za darmo, nagrody tylko w grze:** skiny, odznaki, miejsce na tablicy. Bez Robuxów, bez wymiany na cokolwiek o wartości poza grą.
- **Bez wpisowego i bez płatnych przewag.** Wygląd nie zmienia czasu (`COSMETICS.md`).
- **Bez kar za nieobecność:** turniej to dodatek, a opuszczony nie zabiera niczego (`RETENTION.md`).
- Przed wdrożeniem sprawdzić aktualne Community Standards Roblox.

## Format, który działa przy małej liczbie graczy

Jeden wspólny termin z drabinką wymagałby wielu graczy online naraz. Dlatego zaczynamy od **turnieju czasowego**.

1. **Weekendowy puchar:** od piątku do niedzieli jedna wybrana rzeka. Każdy płynie, ile chce, liczy się najlepszy czas. Działa przy jednym graczu i wszystkich strefach czasowych.
2. **Finał na żywo (później, gdy będą gracze):** 8 najlepszych z pucharu dostaje wspólny wyścig o stałej porze.

## Nagrody (przykład **[Z]**)

| Miejsce | Nagroda |
|---|---|
| Każdy, kto ukończy puchar | odznaka uczestnika sezonu |
| Złoto na rzece w pucharze | ślad sezonowy |
| Top 100 | kolor sezonowy |
| Top 10 | kask sezonowy |
| Top 3 | wyjątkowy kajak sezonu i nazwa na tablicy mistrzów w wiosce |

Nagrody sezonowe są niedostępne w sklepie i nie wracają, co daje im wartość pokazową. Przy kilku graczach „top 100” dostaną wszyscy, więc progi powinny być też procentowe **[Z]**.

## Technika

- **Dane turnieju:** `content/Tournaments.luau`: `{ id, river, startsAt, endsAt, rewards }`. Czas UTC.
- **Ranking:** osobny `OrderedDataStore` `Cup_<id>`, zapis tylko z czasu przyjętego przez serwer spływu.
- **Nagrody:** po końcu turnieju, przy wczytaniu profilu, serwer sprawdza miejsce i nadaje przedmiot przez `CosmeticRules`, zapisując `via = "cup"`. Idempotentnie, więc gracz offline odbiera nagrodę przy powrocie.
- **Oszustwa:** to pierwsze miejsce, gdzie oszustwo daje coś rzadkiego. Fizyka jest po stronie klienta, więc przed turniejem z rzadkimi nagrodami trzeba zaostrzyć kontrolę prędkości i rozważyć sprawdzanie zapisu przejazdu. Czasy z konta z niepewnym wynikiem nie dają nagrody top.
- **Wioska:** tablica turniejowa obok tablicy wyników (czas do końca, top 10), a w oknie rzek baner pucharu.
- **Tryb Bitwa nie liczy się do turnieju.**

## Kolejność

Po: wioska i kolejka, medale, duchy, kosmetyki (katalog i `owned`). Pierwszy puchar dopiero, gdy regularnie gra kilkadziesiąt osób **[Z]**, inaczej ranking będzie pusty.
