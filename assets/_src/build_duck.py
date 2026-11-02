# Kaczka od nowa według konceptu `concepts/kayaks/duck.png`: model z Meshy miał dziury, plamy tekstury i krzywą symetrię.
# Proste bryły, idealna symetria, bez tekstury: każda część ma jeden kolor, który nadaje gra (jak drzewa i skały).
# Uruchomienie: blender.exe -b --factory-startup --python assets/_src/build_duck.py
#   albo w otwartym Blenderze: exec(open(".../build_duck.py").read()) — wtedy model zostaje w scenie do obejrzenia.
# Układ jak build_skin.py: dziób −Y, środek kadłuba w (0, 0, 0), dno kokpitu na wysokości siedzenia.
# Wynik: assets/export/Kayak_Duck.glb, części: Duck_Body (żółty), Duck_Accents (czarny ogon i skrzydełka),
# Duck_Beak (pomarańczowy), Duck_Eyes (czarne),
# Duck_Shine (białe błyski), Duck_Cockpit (ciemne dno).

import bmesh
import bpy
import math
from mathutils import Matrix, Vector

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"
LENGTH = 9.0
HALF_WIDTH = 1.65
DEPTH = 0.8  # kadłub pod linią pokładu
DECK = 0.32  # wysokość pokładu przy kokpicie, jak klasyk
COCKPIT = Vector((0, 0.35, DECK - 0.02))  # środek otworu, lekko ku rufie
COCKPIT_RX, COCKPIT_RY = 1.0, 1.6  # szerzej niż na koncepcie: postać Robloxa ma szerokie biodra
COLORS = {
    "Body": (1.0, 0.78, 0.12, 1),
    "Beak": (1.0, 0.45, 0.05, 1),
    "Accents": (0.05, 0.05, 0.06, 1),
    "Eyes": (0.02, 0.02, 0.03, 1),
    "Shine": (1, 1, 1, 1),
    "Cockpit": (0.04, 0.04, 0.05, 1),
}


# recalc=False: normalne liczone wcześniej, osobno dla każdej zamkniętej bryły. Na kadłubie z wyciętym otworem
# recalc_face_normals potrafi odwrócić całość do środka, a Roblox nie rysuje tylnych ścian (w grze prześwitywała woda).
def new_object(name, bm, smooth=True, recalc=True):
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ellipsoid(bm, center, radii, segments=24, rings=14):
    matrix = Matrix.Translation(center) @ Matrix.Diagonal((radii[0], radii[1], radii[2], 1))
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1, matrix=matrix)


# Kadłub: przekroje wzdłuż Y. Dziób i rufa zaokrąglone (kaczka, nie strzała), dno pękate, pokład lekko wypukły.
def hull(bm):
    stations, sides = 48, 28
    rows = []
    for s in range(stations):
        t = s / (stations - 1)
        along = 2 * t - 1
        width = HALF_WIDTH * max(1 - abs(along) ** 3.2, 0.0) ** 0.5
        depth = DEPTH * max(1 - abs(along) ** 3, 0.0) ** 0.5
        lift = 0.18 * max(along, 0) ** 2  # rufa lekko w górę pod ogonem
        y = LENGTH / 2 * along
        ring = []
        for k in range(sides):
            angle = 2 * math.pi * k / sides
            c, z = math.cos(angle), math.sin(angle)
            x = width * math.copysign(abs(c) ** 0.8, c)
            top = DECK + 0.12 * (width / HALF_WIDTH)
            height = top * max(z, 0) ** 0.6 - depth * max(-z, 0) ** 0.75
            ring.append(bm.verts.new((x, y, height + lift)))
        rows.append(ring)
    for s in range(stations - 1):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((rows[s][k], rows[s][n], rows[s + 1][n], rows[s + 1][k]))
    for ring, reverse in ((rows[0], True), (rows[-1], False)):
        center = bm.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((ring[k], center, ring[n]) if reverse else (ring[n], center, ring[k]))


# Obręcz kokpitu: gruby wałek wokół owalu, jak na koncepcie.
def rim(bm):
    ring, tube = 32, 8
    rows = []
    for k in range(ring):
        angle = 2 * math.pi * k / ring
        c, s = math.cos(angle), math.sin(angle)
        out = Vector((c / COCKPIT_RX, s / COCKPIT_RY, 0)).normalized()
        base = COCKPIT + Vector((COCKPIT_RX * 0.98 * c, COCKPIT_RY * 0.98 * s, 0.16))
        row = []
        for j in range(tube):
            a = 2 * math.pi * j / tube
            row.append(bm.verts.new(base + out * (0.2 * math.cos(a)) + Vector((0, 0, 0.14 * math.sin(a)))))
        rows.append(row)
    for k in range(ring):
        n = (k + 1) % ring
        for j in range(tube):
            m = (j + 1) % tube
            bm.faces.new((rows[k][j], rows[n][j], rows[n][m], rows[k][m]))


# Szyja jako bryła obrotowa: u dołu szeroko rozlana po pokładzie, wyżej węższa i wchodzi w głowę.
# Dzięki temu głowa wyrasta z kadłuba płynnie, bez „kołnierza” z osobnej kuli.
def neck(bm):
    profile = [(0.15, 1.35), (0.42, 1.1), (0.62, 0.86), (0.82, 0.74), (1.0, 0.72), (1.2, 0.78)]  # (wysokość, promień)
    sides = 28
    rows = []
    for z, radius in profile:
        rows.append([bm.verts.new((radius * math.cos(2 * math.pi * k / sides), -3.15 + radius * 0.95 * math.sin(2 * math.pi * k / sides), z)) for k in range(sides)])
    for r in range(len(rows) - 1):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((rows[r][k], rows[r][n], rows[r + 1][n], rows[r + 1][k]))


def body():
    bm = bmesh.new()
    hull(bm)
    # Normalne kadłuba na zewnątrz: zamknięta bryła o ujemnej objętości ze znakiem ma ściany odwrócone do środka.
    bm.normal_update()
    volume = sum(f.verts[0].co.dot(f.verts[i].co.cross(f.verts[i + 1].co)) for f in bm.faces for i in range(1, len(f.verts) - 1))
    if volume < 0:
        for face in bm.faces:
            face.normal_flip()
        bm.normal_update()
    # Otwór kokpitu w pokładzie: bez niego ciemne dno leży pod pokładem i go nie widać
    inside = [f for f in bm.faces if f.calc_center_median().z > 0.1
              and ((f.calc_center_median().x - COCKPIT.x) / COCKPIT_RX) ** 2 + ((f.calc_center_median().y - COCKPIT.y) / COCKPIT_RY) ** 2 < 0.82]
    bmesh.ops.delete(bm, geom=inside, context="FACES")
    before = set(bm.faces)
    rim(bm)
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in before])  # obręcz to zamknięty torus
    ellipsoid(bm, (0, -3.25, 1.4), (1.0, 1.0, 0.95), 28, 16)  # głowa
    before = set(bm.faces)
    neck(bm)
    neck_faces = [f for f in bm.faces if f not in before]
    centre = Vector((0, -3.15, 0.7))
    for face in neck_faces:  # szyja jest otwarta z obu końców: normalne od osi na zewnątrz
        if face.normal.dot(face.calc_center_median() - centre) < 0:
            face.normal_flip()
    return new_object("Duck_Body", bm, recalc=False)


# Kontur skrzydła z boku (u = ku rufie, v = w górę): zaokrąglony bark z przodu, końcówka uniesiona ku tyłowi
# i trzy ząbki lotek na dolnej krawędzi. Płaski kształt wyciągamy na grubość i zaokrąglamy krawędzie fazą.
WING_OUTLINE = [
    (0.0, 0.05), (0.08, 0.3), (0.3, 0.46), (0.65, 0.52), (1.05, 0.56), (1.45, 0.68), (1.85, 0.86), (2.05, 0.9),
    (2.0, 0.66), (1.8, 0.42), (1.55, 0.3), (1.62, 0.08), (1.38, 0.1), (1.2, -0.02), (1.22, -0.22),
    (0.98, -0.12), (0.78, -0.2), (0.74, -0.38), (0.5, -0.3), (0.22, -0.24), (0.05, -0.12),
]
WING_THICKNESS = 0.24


def wing(bm, side):
    place = Matrix.Translation((side * 1.58, -0.35, 0.12)) @ Matrix.Rotation(side * 0.22, 4, "Y")
    local = bmesh.new()
    verts = [local.verts.new((0, u, v)) for u, v in WING_OUTLINE]
    face = local.faces.new(verts if side > 0 else list(reversed(verts)))
    extruded = bmesh.ops.extrude_face_region(local, geom=[face])
    moved = [g for g in extruded["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(local, verts=moved, vec=(side * WING_THICKNESS, 0, 0))
    bmesh.ops.recalc_face_normals(local, faces=local.faces)
    bmesh.ops.bevel(local, geom=local.edges[:], offset=0.07, segments=3, affect="EDGES", clamp_overlap=True)
    bmesh.ops.triangulate(local, faces=local.faces)
    bmesh.ops.transform(local, matrix=place, verts=local.verts)
    mesh = bpy.data.meshes.new("wing_tmp")
    local.to_mesh(mesh)
    local.free()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


# Ogon i skrzydełka osobno: mają własny kolor (czarny, decyzja Marka).
def accents():
    bm = bmesh.new()
    # Ogon: dwa zaokrąglone piórka do góry przy rufie
    for side, tilt in ((-0.28, -0.3), (0.28, 0.3)):
        matrix = Matrix.Translation((side, 4.15, 0.85)) @ Matrix.Rotation(-0.55, 4, "X") @ Matrix.Rotation(tilt, 4, "Y") @ Matrix.Diagonal((0.24, 0.32, 0.62, 1))
        bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=10, radius=1, matrix=matrix)
    for side in (-1, 1):
        wing(bm, side)
    return new_object("Duck_Accents", bm)


def beak():
    bm = bmesh.new()
    ellipsoid(bm, (0, -4.25, 1.27), (0.62, 0.62, 0.17), 20, 10)  # górna część
    ellipsoid(bm, (0, -4.15, 1.05), (0.52, 0.52, 0.13), 20, 10)  # dolna, lekko otwarta
    return new_object("Duck_Beak", bm)


def eyes():
    bm = bmesh.new()
    for side in (-1, 1):
        ellipsoid(bm, (side * 0.6, -3.72, 1.7), (0.2, 0.16, 0.24), 14, 10)
    return new_object("Duck_Eyes", bm)


def shine():
    bm = bmesh.new()
    for side in (-1, 1):
        ellipsoid(bm, (side * 0.68, -3.84, 1.79), (0.06, 0.05, 0.07), 10, 6)
    return new_object("Duck_Shine", bm)


def cockpit():
    bm = bmesh.new()
    ring = 24
    verts = [bm.verts.new(COCKPIT + Vector((COCKPIT_RX * math.cos(2 * math.pi * k / ring), COCKPIT_RY * math.sin(2 * math.pi * k / ring), 0))) for k in range(ring)]
    bm.faces.new(verts)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return new_object("Duck_Cockpit", bm, smooth=False)


def paint(obj, key):
    material = bpy.data.materials.get("Duck_" + key) or bpy.data.materials.new("Duck_" + key)
    material.diffuse_color = COLORS[key]
    material.use_nodes = True
    node = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = COLORS[key]
    obj.data.materials.append(material)


for old in [m for m in bpy.data.meshes if m.name.startswith("Duck_")]:
    bpy.data.meshes.remove(old)
for old in [o for o in bpy.data.objects if o.name.startswith("Duck_")]:
    bpy.data.objects.remove(old)
parts = {"Body": body(), "Accents": accents(), "Beak": beak(), "Eyes": eyes(), "Shine": shine(), "Cockpit": cockpit()}
for key, obj in parts.items():
    paint(obj, key)
    print("##", obj.name, len(obj.data.polygons), "ścian,", [round(d, 2) for d in obj.dimensions])

bpy.ops.object.select_all(action="DESELECT")
for obj in parts.values():
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=EXPORT + "Kayak_Duck.glb", export_format="GLB", use_selection=True)
