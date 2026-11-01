# Styl modeli River Riders: natywny Roblox (od 2026-11-01)

Każde zamówienie w Meshy buduje prompt z tego pliku. Uwagi Marka do wyników trafiają do „Dziennika poprawek” i do promptów.
Pipeline i pułapki importu jak w Anchorfall (`ASSET_TOOLS.md`, `assets/README.md`, `assets/concepts/STYLE.md` tamtego repo), ale **bez jego bajkowego stylu, palety i wzorców**.

## Styl
- Proste, czyste bryły, lekko zaokrąglone krawędzie, jak klocki lub zabawka.
- Płaskie, nasycone kolory, wygląd gładkiego plastiku. Bez malowanej tekstury, szumu, gradientów i realizmu.
- Mało detali, czytelna sylwetka z kamery kajaka i na telefonie.
- Skala w studach, obok postaci Robloxa (około 5 studs).

## Narzędzie
- Koncept: Meshy, tekst → obraz, `nano-banana` (3 kr.), 2 wersje; `nano-banana-2` (6 kr.), gdy tańszy gubi styl. Format 1:1.
- Model: obraz → 3D, `meshy-t2.5`, tekstura 2K, siatka z zapasem, odchudzanie u nas.
- Blender: scalenie wierzchołków przed odchudzaniem (`remove_doubles`), podgląd z `use_backface_culling`, podział zestawu po niepołączonych bryłach, przemalowanie na wspólną paletę (najwyżej 256 px).
- Zestawy: kilka obiektów z odstępami na jednym obrazie, jeden model 3D, podział w Blenderze. Kajak, domy i punkty charakterystyczne osobno.

## Budżety
| Asset | Trójkąty |
|---|---|
| Kajak | ≤ 1500 |
| Wiosło | ≤ 200 |
| Skała | ≤ 200 |
| Drzewo | ≤ 400 |
| Skrzynka, boja | ≤ 150 |
| Brama | ≤ 300 |
| Dom | ≤ 1500 |

## Początek promptu
```
Native Roblox game style: simple clean toy-like shapes built from smooth rounded blocks, softly rounded edges, flat solid saturated colors, smooth plastic look, no painted texture, no noise, no gradients, no realism, no outlines. Few details, strong simple silhouette. <OBIEKT>. Alone on a plain light grey background, three-quarter view, whole object visible, no ground, no shadow.
```
Zestaw: `Exactly <N> separate objects in one row with wide empty gaps between them, not touching, all the same scale: <LISTA>.`

## Zakazy
Rekwizyty i tło wokół obiektu, cień na ziemi, dym, napisy, styl bajkowy, krzywe belki, tekstura drewna lub kamienia.

## Dziennik poprawek
- 2026-11-01 (pilotaż, 63 kr.): styl konceptów wyszedł dobrze (`concepts/pilot`). Zestawy działają: arkusz daje osobne obiekty, a nitkę między drzewami tnie `build_pilot.py`. Modele prostych brył z Meshy (kajak, skały) miały luki i ściany w środku, więc takie kształty budujemy w Blenderze według konceptu, a Meshy zostaje dla brył złożonych i zestawów roślin. Modele bez tekstury, kolor z gry (`MeshPart.Color`, SmoothPlastic).
