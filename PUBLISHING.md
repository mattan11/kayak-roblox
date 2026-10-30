# Publikacja testowa, dane i feedback

Stan na 2026-10-30. Roblox często zmienia te zasady i nazwy menu, więc przed publikacją sprawdź linki.
Założenia oznaczam słowem **założenie**. Zakładam, że Marek ma 18+ i konto w dobrym stanie.

## Najważniejsze przed startem

Od 2026 nowa gra domyślnie trafia **tylko do osób 16+ po age checku**. Dostęp dla młodszych (Roblox Kids 5–8,
Select 9–15) to osobna ścieżka z oceną. Dla poligonu to wystarczy, ale testerów wybieraj pod to, a dane nie będą
opisywać dzieci, które mogą być naturalną publicznością tej gry.

## Krok po kroku

### 1. Publikacja prywatna

1. W Studio [File > Publish](https://create.roblox.com/docs/production/publishing/publish-games-and-places): ikona,
   miniatura, nazwa, gatunek, opis. Gra na razie dostępna tylko dla Ciebie.
2. [Włącz API](https://create.roblox.com/docs/cloud-services/data-stores): File > Experience Settings > Security >
   **Enable Studio Access to API Services**. Działa tylko w opublikowanej grze.
3. **Studio i gra na żywo używają tych samych data store'ów.** Roblox odradza włączanie tego w grze na żywo.
   Dlatego zrób dwie gry: `Kajaki TEST` (API włączone, tu grzebiesz) i właściwą (API wyłączone). Oba z tego samego Rojo.
4. Sprawdź zapis i odczyt rekordu po wyjściu i powrocie. Podgląd: [Data Stores Manager](https://create.roblox.com/docs/cloud-services/data-stores/data-stores-manager).

### 2. Wiek i treść

1. Age check na koncie (twarz lub dokument). [Wymagania](https://create.roblox.com/docs/production/publishing/publish-games-and-places):
   konto w dobrym stanie, co najmniej 2 dni, age check, odpowiedź na pierwsze pytanie ankiety.
2. Ankieta: Creator Dashboard > gra > Publish settings > [Content rating](https://create.roblox.com/docs/production/promotion/content-maturity).
   Wypełnij **całą**, uczciwie, wg najbardziej dojrzałej treści w grze. Bez etykiety Roblox ogranicza grywalność.
   Odpowiedź „nie” na pierwsze pytanie i publikacja bez reszty daje etykietę **Content May Vary** (tylko 16+).
   Kajaki powinny dostać Minimal lub Mild (założenie, wynik daje ankieta).
3. Dostęp dla młodszych [wymaga dodatkowo](https://create.roblox.com/docs/production/publishing/publish-games-and-places):
   weryfikacji dokumentem (18+), 2FA, 2 miesięcy Roblox Plus/Premium albo zwrotnej opłaty 1000 Robux oraz
   [oceny Kids and Select](https://create.roblox.com/docs/production/publishing/kids-and-select). Postęp: Audience Reach w Creator Hub.

   Sprzeczność w źródłach: dokumentacja podaje próg **250** odtworzeń przez „highly engaged” graczy w 60 dni,
   a [post o globalnym wdrożeniu](https://devforum.roblox.com/t/roblox-kids-and-select-global-launch-upcoming-updates-to-eligibility-ads-manager-and-expedited-review/4685717)
   **500**. Obowiązuje to, co pokaże Audience Reach. Na tym etapie nie płać: najpierw dane z 16+.

### 3. Strona gry

- [Ikona](https://create.roblox.com/docs/production/publishing/experience-icons): kwadrat min. 512×512, ma być czytelna w 150×150.
  Jeden kajak w spienionej wodzie, bez tekstu.
- [Miniatury](https://create.roblox.com/docs/production/publishing/thumbnails): 16:9, 1920×1080, poniżej 3 MB,
  nic ważnego na dole (zasłania to licznik graczy). Prawdziwa scena z gry: bystrza, kilka kajaków.
  Bez własnej miniatury gra [nie dostanie wyświetleń z Home](https://create.roblox.com/docs/discovery).
- [Opis](https://create.roblox.com/docs/production/publishing/publish-games-and-places): pierwsze zdanie streszcza grę.
  Bez upychania słów kluczowych, opis zgodny z grą. Np. „Wyścig kajaków w dół rzeki, dwa przyciski, runda 2–3 minuty”.
- Docelowa nazwa zamiast roboczej. Sprawdź dozwolone urządzenia i liczbę graczy na serwerze (założenie: 8).

### 4. Dostęp: od wąskiego do szerokiego

Ustawienia: Creator Dashboard > gra > Publish settings > [Manage Audience > Manage access](https://create.roblox.com/docs/production/publishing/publish-games-and-places).

| Etap | Kto | Jak | Po co |
|------|-----|-----|-------|
| A | do 10 osób | Studio: File > Invite early testers | czy działa, czy bawi |
| B | wszyscy znajomi | zakładka Public, włączone **Friends** | pierwsze liczby |
| C | publicznie, ograniczony zasięg | Friends wyłączone + Audience > Advanced Settings > **Exclude from recommendations** | test na obcych z linku |
| D | pełny | wyłączone Exclude | gdy funnel i D1 są OK |

- Early testers: jako dorosły dodasz znajomych 16+. **Trusted friends** w dowolnym wieku (poniżej 9 lat ze zgodą rodzica).
- Do 3 rozsyłaj linki z [Share Links](https://create.roblox.com/docs/production/promotion/share-links) (Creations >
  Share Links): osobny link na kanał pokaże, który przyprowadza graczy.
- Gra pod grupą nie ma trybu Friends, więc na test zostaw ją na koncie osobistym.
- [Serwery prywatne](https://create.roblox.com/docs/en-us/production/monetization/private-servers.md) wymagają gry publicznej, czyli od etapu C.
- Reklamy zostaw na później. Użytkownicy z reklam są [wyłączeni z sygnałów rankingowych](https://create.roblox.com/docs/discovery),
  a przy tej skali lepiej najpierw dowieźć pętlę.

### 5. Telefon

Zanim dasz link komukolwiek: test opublikowanej wersji przez ADB na Mi Note 10 Lite. Klatki, tapnięcia po obu stronach,
wyniki po restarcie.

## Co czytać w Creator Dashboard

Wejście: Creator Hub > gra > Analytics. Sekcje: [Acquisition, Retention, Engagement, Monetization, Insights](https://create.roblox.com/docs/production/analytics).

| Pytanie | Gdzie | Uwagi |
|---------|-------|-------|
| Czy wracają? | Retention: D1, D7, D30 | [Liczone dla nowych, wg daty pierwszej gry](https://create.roblox.com/docs/en-us/production/analytics/retention). D7 kohorty widać po 7 dniach |
| Czy zmiana pomogła? | Retention: kohorty dzienne i tygodniowe | porównuj kohorty przed i po zmianie |
| Ile grają? | Engagement: średni czas sesji | runda to 2–3 min, więc sesja 3 min = jedna runda |
| Czy przechodzą? | Funnels | własne zdarzenia, niżej |
| Czy wchodzą z miniatury? | Acquisition: Play Through Rate | ma sens dopiero przy wyświetleniach z rekomendacji |
| Co piszą? | Audience > Feedback | [komentarze z API i strony gry](https://devforum.roblox.com/t/playerfeedback-api-prompt-player-feedback-in-experiences/4034161) |

**Progi małej gry.** Benchmarki do podobnych gier wymagają [100+ DAU](https://create.roblox.com/docs/production/analytics).
Pełne KPI według [starszej strony](https://create.roblox.com/docs/production/analytics/analytics-dashboard)
wymagają ponad 10 DAU i 10 godzin gry przez 7 dni z rzędu oraz potwierdzonego e-maila i 2FA do włączenia. Sprawdź,
co pokaże Dashboard.

**Punkt odniesienia.** Roblox [nie podaje](https://create.roblox.com/docs/production/analytics) liczb docelowych, tylko
porównanie z podobnymi grami. Jedyny mocny publiczny zestaw to
[GameAnalytics](https://gamedevreports.substack.com/p/gameanalytics-key-roblox-and-roblox), sierpień 2025–lipiec 2026,
500+ gier z min. 1 mln MAU:

| | Mediana | Top 1% |
|---|---|---|
| D1 | 10,3% | 22,2% |
| D7 | 1,6% | 9,1% |
| D30 | 0,5% | 4,7% |
| Długość sesji | 9,8 min | 21,1 min |

To gry dużo większe niż nasza, a znajomi pewnie zawyżą wyniki (założenie). Porównuj się głównie z **poprzednią wersją siebie**.
Liczby typu „40% D1 to super” krążą po blogach. Nie używaj ich, GameAnalytics uważa je za zawyżone.

**Mała próbka** (moje wyliczenie): przy 20 nowych graczach jedna osoba to 5 punktów procentowych.
Do około 30 graczy (założenie) czytaj liczby osób i funnel, nie procenty, a retencję traktuj jako wskazówkę.

## Własne zdarzenia (AnalyticsService)

[Zasady](https://create.roblox.com/docs/production/analytics/custom-events):

- Tylko **z serwera** i tylko w **opublikowanej** grze. Ze Studia nic nie idzie, więc test wymaga publikacji.
- Wykresy pojawiają się do 24 godzin później (Analytics > Explore i Funnels).
- [Limity](https://create.roblox.com/docs/production/analytics/event-types): 100 nazw zdarzeń, 10 funnelów, 3 pola własne,
  120 + 20 × CCU wywołań na minutę. Dane znikają po 90 dniach od ostatniego zdarzenia.
- Pola to [napisy o małej liczbie wartości](https://create.roblox.com/docs/production/analytics/custom-fields), np. `River - Test`.
  Nigdy userId ani dokładny czas (limit 8000 kombinacji). Czas idzie w `value`.

```luau
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")

-- Funnel jednorazowy (jak onboarding w aplikacji webowej)
AnalyticsService:LogOnboardingFunnelStepEvent(player, 1, "Joined")

-- Funnel powtarzalny: osobne ID na każdy wyścig (jak traceId requestu)
local raceId = HttpService:GenerateGUID(false)
AnalyticsService:LogFunnelStepEvent(player, "Race", raceId, 2, "Started")

-- Zdarzenie z wartością i polami
AnalyticsService:LogCustomEvent(player, "RaceFinished", timeSeconds, {
	[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "River - Test",
	[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = "Mode - Solo",
})
```

[Funnel](https://create.roblox.com/docs/production/analytics/funnel-events): numeruj kroki od 1 w stałej kolejności.
Pominięty krok liczy się jako zaliczony, powtórzony liczy się raz. Filtry działają na pierwszy krok.
Trzymaj to w jednym module `Analytics` w `src/server/Systems`, żeby nazwy nie rozjechały się po kodzie.

## Feedback

- **Obserwacja, najcenniejsze.** 3–5 osób gra przy Tobie na telefonie, a Ty milczysz. Notuj, gdzie się gubią.
- **Oficjalne okno.** [`SocialService:PromptFeedbackSubmissionAsync`](https://create.roblox.com/docs/reference/engine/classes/SocialService)
  po ukończonym wyścigu. Wyniki: Audience > Feedback. Limit: 1 opinia dziennie na grę. Własnych pytań i ocen
  [jeszcze nie ma](https://devforum.roblox.com/t/playerfeedback-api-prompt-player-feedback-in-experiences/4034161).
- **Własna ankieta jednym tapnięciem.** Raz, po 3. wyścigu: „Jeszcze raz?” lub „Co przeszkadza?” (sterowanie / za trudno /
  za nudno / lag). Bez wolnego tekstu. Przycisk wysyła zdarzenie `SurveyAnswer`, można pominąć, nie ma nagrody.
- **Testerzy.** Grupa ze znajomych na czacie, stałe 3 pytania po każdej wersji: Co było najfajniejsze? Gdzie chciałeś
  wyjść? Co zmieniłbyś jako pierwsze?
- **Grupa Roblox i Discord.** Grupa to łatwy kanał ogłoszeń. Discord ma sens dopiero przy kilkudziesięciu graczach.
  [Linki społecznościowe](https://create.roblox.com/docs/production/promotion/social-media-links) dodasz po weryfikacji 16+,
  do 3 na stronie gry i zobaczą je tylko zweryfikowani 16+. W samej grze linków podawać nie wolno.
  [Można napisać](https://devforum.roblox.com/t/age-checks-to-access-chat-studio-team-create-and-links-on-roblox/4079702),
  że są na stronie gry.

## Pętla: hipoteza → zmiana → pomiar

Przed zmianą zapisz w `PROGRESS.md` jedną linijkę:

> **Hipoteza:** Skrócenie czekania po mecie do 3 s podniesie liczbę wyścigów na sesję z X do Y.
> **Metryka:** wyścigi na sesję (`SessionEnd`). **Decyzja:** poniżej Y wracam do pomysłu, powyżej zostawiam.

1. Sprawdź w funnelu, gdzie jest największy spadek. Tam pracuj.
2. Jedna zmiana naraz, data publikacji w dzienniku. Dwie zmiany w jednym tygodniu to wynik nie do odczytania.
3. Czekaj: 1–2 dni na zdarzenia, 8 dni na D7 nowej kohorty.
4. Porównaj kohorty przed i po, a przy małej próbce dorzuć rozmowę z testerami.
5. Zapisz wniosek, także gdy zmiana nie zadziałała. Właśnie ten dziennik jest celem poligonu.

Rytm (założenie): jedna zmiana na tydzień. Roblox [sugeruje](https://create.roblox.com/docs/en-us/production/analytics/retention)
drobne aktualizacje co 2–4 tygodnie, większe co 2–3 miesiące, ale to już dla gry z publicznością.

## Co przenieść do Anchorfall

1. **Moduł `Analytics`** i konwencja nazw zdarzeń oraz funnelów, plus zasada „zero wysokiej kardynalności w polach”.
2. **Procedura publikacji**: co blokuje, ile trwa age check i ocena Kids and Select. Największa gra potrzebuje tego wcześniej,
   zwłaszcza że dostęp poniżej 16 lat zależy od engagementu z 16+. To może zmienić plan startu.
3. **Rozdział TEST/LIVE** dla data store'ów i wersji.
4. **Funnel pierwszej sesji**: Anchorfall ma dłuższy start, więc jego funnel musi być gotowy przed testami.
5. **Dziennik hipotez** i minimalna próbka, od której wierzysz liczbom.
6. **Skrypt testów z ludźmi**: obserwacja, stałe pytania, ankieta jednym tapnięciem.
7. **Co działa na retencję**: duch, cel na ekranie wyników i brak kar. Sprawdzone tanio tutaj, drogo tam.
8. **Czego nie mierzyć**: zdarzenia, których nikt nie czytał przez miesiąc, wylatują.

## Zdarzenia do dodania w tej grze

| # | Zdarzenie | Typ | Kiedy | Value / pola | Pytanie |
|---|-----------|-----|-------|--------------|---------|
| 1 | Onboarding: `Joined` → `FirstStroke` → `FirstHalfway` → `FirstFinish` → `SecondRaceStarted` | onboarding funnel | pierwsza sesja | kroki 1–5 | Gdzie odpadają nowi? |
| 2 | `Race`: `Countdown` → `Started` → `Halfway` → `Finished` → `NextRace` | funnel, GUID na wyścig | każdy wyścig | pola: rzeka, tryb | Ile wyścigów kończy się metą i kolejną rundą? |
| 3 | `RaceFinished` | custom | meta | value: czas (s); rzeka, tryb, medal | Czy balans trasy pasuje do 2–3 min? |
| 4 | `RaceAbandoned` | custom | `PlayerRemoving` w `racing` | value: % trasy; rzeka, tryb | W którym miejscu wychodzą? |
| 5 | `RaceHits` | custom | meta | value: liczba zderzeń; rzeka, odcinek | Który odcinek jest za trudny? |
| 6 | `SessionEnd` | custom | `PlayerRemoving` | value: wyścigi w sesji; pierwsza sesja tak/nie | Czy działa „jeszcze jedna runda”? |
| 7 | `InviteSent` | custom | zamknięcie promptu | miejsce przycisku | Czy zapraszają? |
| 8 | `SurveyAnswer` | custom | ankieta | value: 1; odpowiedź | Co przeszkadza najbardziej? |

Krok `FirstStroke` serwer zobaczy z remote `Stroke`. Wszystko loguje serwer, klient niczego sam nie zgłasza,
a `InviteSent` i `SurveyAnswer` idą przez remote z limitem (`Remotes.onServer`) i walidacją wartości.

## Źródła

Publikacja: [publikowanie gier](https://create.roblox.com/docs/production/publishing/publish-games-and-places),
[Kids and Select](https://create.roblox.com/docs/production/publishing/kids-and-select),
[content maturity](https://create.roblox.com/docs/production/promotion/content-maturity),
[globalne wdrożenie Kids and Select](https://devforum.roblox.com/t/roblox-kids-and-select-global-launch-upcoming-updates-to-eligibility-ads-manager-and-expedited-review/4685717),
[data stores](https://create.roblox.com/docs/cloud-services/data-stores),
[ikony](https://create.roblox.com/docs/production/publishing/experience-icons),
[miniatury](https://create.roblox.com/docs/production/publishing/thumbnails),
[share links](https://create.roblox.com/docs/production/promotion/share-links),
[serwery prywatne](https://create.roblox.com/docs/en-us/production/monetization/private-servers.md).

Dane: [analytics](https://create.roblox.com/docs/production/analytics),
[retencja](https://create.roblox.com/docs/en-us/production/analytics/retention),
[dashboard](https://create.roblox.com/docs/production/analytics/analytics-dashboard),
[discovery](https://create.roblox.com/docs/discovery),
[custom events](https://create.roblox.com/docs/production/analytics/custom-events),
[funnels](https://create.roblox.com/docs/production/analytics/funnel-events),
[limity zdarzeń](https://create.roblox.com/docs/production/analytics/event-types),
[pola własne](https://create.roblox.com/docs/production/analytics/custom-fields),
[GameAnalytics przez GameDev Reports](https://gamedevreports.substack.com/p/gameanalytics-key-roblox-and-roblox).

Feedback: [PlayerFeedback API](https://devforum.roblox.com/t/playerfeedback-api-prompt-player-feedback-in-experiences/4034161),
[SocialService](https://create.roblox.com/docs/reference/engine/classes/SocialService),
[linki społecznościowe](https://create.roblox.com/docs/production/promotion/social-media-links).
