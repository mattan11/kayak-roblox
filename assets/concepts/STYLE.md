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
- Model: obraz → 3D, `meshy-t2.5`, tekstura 2K. Zawsze dużo trójkątów (15–20 tys., decyzja Marka: bez wpływu na cenę), odchudzanie u nas w Blenderze.
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
- 2026-11-01 (skiny): ChatGPT daje koncepty w stylu gry, Leonardo odjeżdża w realizm; Neon i Lodowy Smok zrobione w Meshy z wzorcami `kraken.png` i `dragon.png`. Zestaw trzech kajaków z jednego obrazu rozdzielił się, ale kosztem jakości i kokpitów na wylot: modele skinów osobno, a kokpit i obrys poprawiamy w Blenderze. Generować 15–20 tys. trójkątów.
- 2026-11-02 (Kaczka): model z Meshy miał dziury, plamy i krzywą symetrię, więc zbudowana od nowa w `_src/build_duck.py` (proste bryły, kolory z gry). Pułapka: przy wycinaniu otworu kokpitu ściany kadłuba odwróciły się do środka; Blender je rysuje, Roblox nie (widać było wodę przez pokład). Kierunek ścian ustalać przed wycięciem, z objętości ze znakiem, i sprawdzać w Blenderze z „Backface Culling”. Kraken: krzywe oko zamalowane w teksturze, nowe oczy z brył przyklejone do głowy promieniem (`_src/build_kraken_eyes.py`).
- 2026-11-02 (Feniks, Rekin): dziury w modelach z Meshy zaklejamy w Blenderze; gdy `holes_fill` nie daje rady (sąsiednie krawędzie nie-rozmaitościowe), łatka wachlarzem do środka dziury. Rekin: kadłub w jednym kolorze, zęby wycięte z siatki po białej teksturze, oczy z brył (`_src/shark_details.py`, `_src/smooth_shark.py`).
- 2026-11-02 (Rekin 3, z aplikacji Meshy w Chrome): obraz Nano Banana 2 (6 kr.) → „Obraz do 3D” na ustawieniach z Anchorfall: Smart Topology `meshy-t2.5`, 15 000 wielokątów, tekstura, bez pozy (15 kr.). Zamówienie z aplikacji, więc działa darmowe „Spróbuj ponownie”. Model dobry (szczelny, zęby i oczy w teksturze), ale Smart Topology ma setki drobnych wysp UV: po odchudzeniu na kadłubie wychodzą ciemne kropki. Rozwiązanie: `"rebake": True` w `build_skin.py` — nowe UV na odchudzonej siatce i kolor wypalony z pełnego modelu (Cycles, Diffuse Color). Kółko ustawień przy „Obraz do 3D” otwiera się dopiero kliknięciem przez JS (Claude w Chrome).
