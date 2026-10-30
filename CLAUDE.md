# River Riot: Kayak Race — instrukcja dla Claude

Mała gra Roblox „River Riot: Kayak Race” (wyścig kajaków). Właściciel: Marek — programista JS/TS, rozmawia po polsku. Odpowiedzi,
dokumenty i komentarze w kodzie **po polsku**, z analogiami do JS/TS tam, gdzie pomagają.

- Start sesji: `PROGRESS.md` (sekcja „▶ NASTĘPNY KROK”), decyzje w `VISION.md`, płatności w `MONETIZATION.md` (nie sprzedajemy mocy).
- Gra ma zostać **prosta** (KISS). Marek równolegle robi Anchorfall — nie rozbudowywać bez potrzeby.
- Kod: Rojo (`default.project.json`, spływ: port **34900** (placeId 74365646024707), `village.project.json`: **34901** (placeId 75278412187467, miejsce startowe); 34872–34899 zostają dla innych gier), `src/shared` (czysta logika,
  testowalna), `src/server/Systems`, `src/client/Controllers`, dane tras w `src/shared/content/rivers`.
- Liczby do strojenia tylko w `src/shared/Config.luau`.
- Testy bez Studio: `C:\Users\marek\tools\lune\lune.exe run tools/lune/run_tests.luau` (z katalogu repo).
  W Studio: `return require(game.ServerStorage.Tests:Clone().Run)()`.
- Każdy ważniejszy krok: testy Lune + Play w Studio. Commit tylko na prośbę Marka.
- Pythona nie ma — skrypty pomocnicze w Node.js.
