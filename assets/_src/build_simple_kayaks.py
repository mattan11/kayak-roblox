# Cztery proste kajaki według konceptów z `concepts/kayaks`: Strzała (racer.png), Pękaty (round.png),
# Lodołamacz (icebreaker.png) i Złoty Flisak (gold.png). Meshy przy prostych bryłach dawał dziury i ściany w środku
# (STYLE.md, 2026-11-01), więc kadłub liczymy sami: jedna funkcja z parametrami, różnią się proporcje i ozdoby.
# Bez tekstur: każda część ma jeden kolor, który nadaje gra (jak Kaczka, drzewa i skały).
# Uruchomienie: blender.exe -b --factory-startup --python assets/_src/build_simple_kayaks.py [-- racer round ...]
#   albo w otwartym Blenderze: exec(open(".../build_simple_kayaks.py").read()) — modele zostają w scenie.
# Układ: dziób −Y, środek kadłuba (Hull) w (0, 0, 0), dno 0,6 pod nim, dno kokpitu na FLOOR, jak w build_skin.py.
# Wynik: assets/export/Kayak_<Nazwa>.glb, części Kayak_<Nazwa> (Paint) i Kayak_<Nazwa>_<Część>.

import bmesh
import bpy
import math
import sys
from mathutils import Matrix, Vector

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"
BOTTOM = -0.6
FLOOR = 0.62  # dno kokpitu względem środka Hull (siedzenie w KayakService)
DECK = 0.7  # pokład przy kokpicie: krawędź otworu tuż nad dnem, postać siedzi w środku, a nie na wieku
SHEER = 0.15  # linia burty: tu schodzą się pokład i dno, na niej leży czubek dziobu i rufy
STATIONS, SIDES = 56, 32

# length/width: wymiary w studs; ends: ostrość końców (mniej = ostrzej); crown: wypukłość pokładu ku końcom;
# cockpit: półosie otworu (x, y) i przesunięcie ku rufie; colors: kolory części do podglądu (w grze nadaje je szablon).
KAYAKS = {
    "racer": {
        "name": "Racer", "length": 10.5, "width": 2.4, "ends": 1.25, "fullness": 0.75, "crown": 0.25, "rocker": 0.05,
        "cockpit": (0.85, 1.8, 0.0), "colors": {"Paint": (0.0, 0.42, 1.0), "Accents": (0.95, 0.97, 1.0)},
    },
    "round": {
        "name": "Round", "length": 7.6, "width": 3.1, "ends": 3.0, "fullness": 0.5, "crown": 0.1, "rocker": 0.2,
        "cockpit": (1.0, 1.55, 0.25), "colors": {"Paint": (1.0, 0.42, 0.05)},
    },
    # Szablon KayakIcebreaker w grze jest powiększony ×1,1 wokół dna kokpitu (decyzja Marka 2026-11-02), a jego płyty
    # nazywają się Paint, żeby brały kolor gracza razem z kadłubem. Przy przebudowie: oba kroki powtórzyć w szablonie.
    "icebreaker": {
        "name": "Icebreaker", "length": 9.0, "width": 2.9, "ends": 1.9, "fullness": 0.65, "crown": 0.15, "rocker": 0.12,
        "cockpit": (0.95, 1.5, 0.3), "colors": {"Paint": (0.27, 0.55, 0.86), "Deck": (0.94, 0.95, 0.97), "Accents": (0.33, 0.6, 0.9)},
    },
    "gold": {
        "name": "Gold", "length": 9.4, "width": 2.5, "ends": 1.5, "fullness": 0.75, "crown": 0.2, "rocker": 0.1,
        "cockpit": (0.92, 1.5, 0.35), "colors": {"Paint": (1.0, 0.72, 0.1), "Accents": (1.0, 0.8, 0.2)},
    },
}
COCKPIT_COLOR = (0.04, 0.04, 0.05, 1)


def new_object(name, bm, smooth=True, recalc=True):
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def orient_outward(bm, faces):
    # Zamknięta bryła o ujemnej objętości ze znakiem ma ściany do środka; Roblox nie rysuje tylnych ścian (Kaczka).
    volume = sum(f.verts[0].co.dot(f.verts[i].co.cross(f.verts[i + 1].co)) for f in faces for i in range(1, len(f.verts) - 1))
    if volume < 0:
        for face in faces:
            face.normal_flip()
    bm.normal_update()


# Przekrój kadłuba w danym miejscu: półszerokość, wysokość linii burty i zasięg w górę i w dół od niej.
# Na końcach wszystko schodzi do jednego punktu na linii burty, więc dziób jest ostry albo zaokrąglony, nie ścięty.
def section(spec, along):
    edge = max(1 - abs(along) ** spec["ends"], 0.0)
    width = max(spec["width"] / 2 * edge ** spec["fullness"], 0.01)
    mid = SHEER + spec["rocker"] * abs(along) ** 3  # końce lekko zadarte
    top = DECK - 0.1 * along ** 2
    up = (top - SHEER) * edge ** 0.35
    down = (SHEER - BOTTOM) * edge ** 0.5
    return width, mid, up, down


# Kadłub z przekrojów wzdłuż Y. Warstwa `band` zapisuje pas ściany: 1 = góra od burty (Lodołamacz ma dwa kolory).
def hull(spec):
    bm = bmesh.new()
    band = bm.faces.layers.int.new("band")
    rows = []
    for s in range(STATIONS):
        along = 2 * s / (STATIONS - 1) - 1
        width, mid, up, down = section(spec, along)
        y = spec["length"] / 2 * along
        ring = []
        for k in range(SIDES):
            angle = 2 * math.pi * k / SIDES
            c, z = math.cos(angle), math.sin(angle)
            x = width * math.copysign(abs(c) ** 0.7, c)
            crown = spec["crown"] * (width / (spec["width"] / 2)) * max(z, 0) ** 2  # pokład wypukły na środku szerokości
            height = mid + (up + crown) * max(z, 0) ** 0.5 - down * max(-z, 0) ** 0.7
            ring.append(bm.verts.new((x, y, height)))
        rows.append(ring)
    for s in range(STATIONS - 1):
        for k in range(SIDES):
            n = (k + 1) % SIDES
            face = bm.faces.new((rows[s][k], rows[s][n], rows[s + 1][n], rows[s + 1][k]))
            face[band] = 1 if 1 <= k < SIDES // 2 - 1 else 0  # od burty w górę, bez pasa na samej burcie
    for ring, reverse in ((rows[0], True), (rows[-1], False)):
        center = bm.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
        for k in range(SIDES):
            n = (k + 1) % SIDES
            bm.faces.new((ring[k], center, ring[n]) if reverse else (ring[n], center, ring[k]))
    bm.normal_update()
    orient_outward(bm, bm.faces)
    rx, ry, shift = spec["cockpit"]
    hole = [f for f in bm.faces if f.calc_center_median().z > 0.2
            and (f.calc_center_median().x / rx) ** 2 + ((f.calc_center_median().y - shift) / ry) ** 2 < 0.95]  # brzeg chowa się pod obręczą
    bmesh.ops.delete(bm, geom=hole, context="FACES")
    return bm


# Wałek wokół otworu kokpitu (jak na wszystkich konceptach), dokładany do bryły w kolorze `part`.
def rim(bm, spec, thickness=0.17):
    rx, ry, shift = spec["cockpit"]
    ring, tube = 36, 8
    rows = []
    for k in range(ring):
        angle = 2 * math.pi * k / ring
        c, s = math.cos(angle), math.sin(angle)
        out = Vector((c / rx, s / ry, 0)).normalized()
        base = Vector((rx * 0.97 * c, shift + ry * 0.97 * s, DECK + 0.05))
        rows.append([bm.verts.new(base + out * (thickness * math.cos(2 * math.pi * j / tube)) + Vector((0, 0, thickness * 0.8 * math.sin(2 * math.pi * j / tube)))) for j in range(tube)])
    faces = []
    for k in range(ring):
        n = (k + 1) % ring
        for j in range(tube):
            m = (j + 1) % tube
            faces.append(bm.faces.new((rows[k][j], rows[n][j], rows[n][m], rows[k][m])))
    bm.normal_update()
    orient_outward(bm, faces)


def cockpit(spec):
    rx, ry, shift = spec["cockpit"]
    bm = bmesh.new()
    verts = [bm.verts.new((rx * math.cos(2 * math.pi * k / 28), shift + ry * math.sin(2 * math.pi * k / 28), FLOOR)) for k in range(28)]
    bm.faces.new(verts)  # wierzchołki przeciwnie do wskazówek zegara z góry: ściana patrzy w górę
    # Bez recalc: na pojedynczej ścianie potrafi ją odwrócić w dół, a Roblox jej wtedy nie rysuje (Złoty Flisak z wodą w środku;
    # w szablonie KayakGold dno jest obrócone o 180°, więc po przebudowie Złotego ten obrót trzeba zdjąć)
    return new_object("Kayak_" + spec["name"] + "_Cockpit", bm, smooth=False, recalc=False)


# Ozdoby kładziemy na powierzchni kadłuba: promień z góry (albo z boku) trafia w kadłub, część dostaje jego normalną.
def surface(hull_obj, x, y, side=0):
    if side == 0:
        start, direction = Vector((x, y, 5)), Vector((0, 0, -1))
    else:
        start, direction = Vector((side * 5, y, x)), Vector((-side, 0, 0))
    hit, location, normal, _ = hull_obj.ray_cast(start, direction)
    return (location, normal) if hit else (None, None)


# Płaski kształt wyciągnięty na grubość, z fazą, położony na kadłubie według normalnej. Kontur (u, v): u biegnie
# wzdłuż kadłuba (ku rufie), v w poprzek, po powierzchni.
def decal(bm, outline, location, normal, thickness, lift=0.01, bevel=0.03):
    local = bmesh.new()
    face = local.faces.new([local.verts.new((u, v, 0)) for u, v in outline])
    extruded = bmesh.ops.extrude_face_region(local, geom=[face])
    bmesh.ops.translate(local, verts=[g for g in extruded["geom"] if isinstance(g, bmesh.types.BMVert)], vec=(0, 0, thickness))
    bmesh.ops.recalc_face_normals(local, faces=local.faces)
    if bevel:
        bmesh.ops.bevel(local, geom=local.edges[:], offset=bevel, segments=2, affect="EDGES", clamp_overlap=True)
    up = normal.normalized()
    along = (Vector((0, 1, 0)) - up * up.y).normalized()
    across = up.cross(along)
    rotation = Matrix((along, across, up)).transposed().to_4x4()
    if rotation.determinant() < 0:  # lewa burta: odbicie odwróciłoby ściany
        rotation = Matrix((along, -across, up)).transposed().to_4x4()
    bmesh.ops.transform(local, matrix=Matrix.Translation(location - up * (thickness * 0.5 - lift)) @ rotation, verts=local.verts)
    mesh = bpy.data.meshes.new("decal_tmp")
    local.to_mesh(mesh)
    local.free()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


# Pas wzdłuż osi pokładu (Strzała): pasek punktów rzutowanych na pokład, od dziobu do kokpitu i od kokpitu do rufy.
def stripe(bm, hull_obj, spec, half=0.16, lift=0.012):
    rx, ry, shift = spec["cockpit"]
    for start, end in ((-spec["length"] / 2 + 0.25, shift - ry - 0.15), (shift + ry + 0.15, spec["length"] / 2 - 0.25)):
        count = 24
        rows = []
        for i in range(count + 1):
            y = start + (end - start) * i / count
            taper = min(1.0, (min(abs(y - (-spec["length"] / 2)), abs(spec["length"] / 2 - y))) / 1.2) ** 0.7
            row = []
            for x in (-half * taper - 0.002, half * taper + 0.002):
                location, normal = surface(hull_obj, x, y)
                row.append(bm.verts.new(location + normal * lift))
            rows.append(row)
        for i in range(count):
            bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))


def star_outline(radius, points=5, inner=0.45):
    return [(radius * (1 if i % 2 == 0 else inner) * math.sin(math.pi * i / points), radius * (1 if i % 2 == 0 else inner) * -math.cos(math.pi * i / points)) for i in range(points * 2)][::-1]


def build(key):
    spec = KAYAKS[key]
    name = "Kayak_" + spec["name"]
    # Stare obiekty, siatki i materiały precz, inaczej nowe dostaną „.001” i taka nazwa trafi do Robloxa
    for collection in (bpy.data.objects, bpy.data.meshes, bpy.data.materials):
        for old in [item for item in collection if item.name.startswith(name)]:
            collection.remove(old)
    bm = hull(spec)
    parts = {}
    if key == "icebreaker":
        # Dwa kolory jak na koncepcie: biała góra, niebieski dół. Krawędź podziału biegnie wzdłuż pasa ścian kadłuba.
        top = bm.copy()
        for mesh_bm, keep in ((bm, 0), (top, 1)):
            band = mesh_bm.faces.layers.int["band"]
            bmesh.ops.delete(mesh_bm, geom=[f for f in mesh_bm.faces if f[band] != keep], context="FACES")
            bmesh.ops.delete(mesh_bm, geom=[v for v in mesh_bm.verts if not v.link_faces], context="VERTS")
        parts["Deck"] = new_object(name + "_Deck", top, recalc=False)
    rim(bm, spec)
    paint = new_object(name, bm, recalc=False)
    parts["Paint"] = paint
    probe = paint if key != "icebreaker" else None
    if key == "icebreaker":
        # Do rzutowania potrzebny cały kadłub: łączymy na chwilę dół z górą
        probe = paint.copy()
        probe.data = paint.data.copy()
        bpy.context.scene.collection.objects.link(probe)
        joined = bmesh.new()
        joined.from_mesh(probe.data)
        joined.from_mesh(parts["Deck"].data)
        joined.to_mesh(probe.data)
        joined.free()
        probe.data.update()
    bpy.context.view_layer.update()

    accents = bmesh.new()
    if key == "racer":
        stripe(accents, probe, spec)
    elif key == "gold":
        location, normal = surface(probe, 0, -spec["length"] / 2 + 1.5)
        decal(accents, star_outline(0.42), location, normal, 0.1, lift=0.03, bevel=0.025)
    elif key == "icebreaker":
        length = spec["length"]
        for side in (-1, 1):
            # Dwie płyty pancerza na burcie, każda z nitami na końcach
            for y, w in ((-1.5, 1.6), (1.4, 1.4)):
                location, normal = surface(probe, SHEER - 0.05, y, side)
                outline = [(-w / 2, -0.26), (w / 2, -0.26), (w / 2 + 0.2, 0.0), (w / 2, 0.28), (-w / 2, 0.28), (-w / 2 - 0.2, 0.0)]
                decal(accents, outline, location, normal, 0.12, lift=0.04)
                for u in (-w / 2 + 0.12, w / 2 - 0.12):
                    nail = location + normal * 0.13 + Vector((0, u, 0))
                    bmesh.ops.create_uvsphere(accents, u_segments=8, v_segments=5, radius=0.07, matrix=Matrix.Translation(nail))
        # Osłona dziobu: powłoka kadłuba z przodu, pogrubiona na zewnątrz (dopasowuje się do kształtu)
        shell = bmesh.new()
        shell.from_mesh(probe.data)
        bmesh.ops.delete(shell, geom=[f for f in shell.faces if f.calc_center_median().y > -length / 2 + 0.75], context="FACES")
        bmesh.ops.delete(shell, geom=[v for v in shell.verts if not v.link_faces], context="VERTS")
        shell.normal_update()
        for vert in shell.verts:
            vert.co += vert.normal * 0.03
        bmesh.ops.solidify(shell, geom=shell.faces[:], thickness=-0.1)
        mesh = bpy.data.meshes.new("shell_tmp")
        shell.to_mesh(mesh)
        shell.free()
        accents.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        # Trójkątne łaty na pokładzie z przodu i z tyłu, czubkiem ku końcowi kajaka
        for y, toward in ((-length / 2 + 1.7, -1), (length / 2 - 1.6, 1)):
            for side in (-1, 1):
                location, normal = surface(probe, side * 0.5, y)
                outline = [(toward * 0.75, 0.0), (-toward * 0.35, side * 0.38), (-toward * 0.35, -side * 0.02)]
                if toward * side < 0:
                    outline = outline[::-1]
                decal(accents, outline, location, normal, 0.05, lift=0.015, bevel=0.015)
        bpy.data.objects.remove(probe)
    if accents.faces:
        parts["Accents"] = new_object(name + "_Accents", accents, recalc=key != "racer")
        if key == "racer":
            # Pas ma tylko górną stronę: jej normalna musi patrzeć w górę
            mesh = parts["Accents"].data
            if sum(p.normal.z for p in mesh.polygons) < 0:
                mesh.flip_normals()
    else:
        accents.free()
    parts["Cockpit"] = cockpit(spec)

    for part, obj in parts.items():
        color = COCKPIT_COLOR if part == "Cockpit" else (*spec["colors"][part][:3], 1)
        material = bpy.data.materials.new(obj.name)
        material.diffuse_color = color
        material.use_nodes = True
        next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = color
        obj.data.materials.append(material)
        print("##", obj.name, sum(len(p.vertices) - 2 for p in obj.data.polygons), "tr,", [round(d, 2) for d in obj.dimensions])
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts.values():
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=EXPORT + name + ".glb", export_format="GLB", use_selection=True)
    return parts


keys = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(KAYAKS)
for key in keys:
    build(key)
