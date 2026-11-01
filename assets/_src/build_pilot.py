# Pilotaż modeli (STYLE.md): GLB z Meshy → lekkie MeshPart bez tekstury, kolor nadaje gra (SmoothPlastic, MeshPart.Color).
# Dzięki temu ta sama siatka drzewa czy skały pasuje do każdej rzeki, a telefon nie ładuje tekstur.
# Uruchomienie: blender.exe -b --factory-startup --python assets/_src/build_pilot.py
# Wynik: assets/export/pilot.fbx (jeden Import 3D) i rendery w assets/export/preview/.
# Skala: 1 jednostka = 1 stud, przód = −Y w Blenderze (po eksporcie −Z w Robloxie), pivot w środku lub u podstawy.

import bmesh
import bpy
import math
import os
import random
from mathutils import Vector

ROOT = "C:/Users/marek/Documents/roblox-kayak/assets/"
AI = ROOT + "_ai/pilot/"
EXPORT = ROOT + "export/"
PREVIEW = EXPORT + "preview/"

TREE_HEIGHT = {"Round": 20, "Double": 18, "Pine": 22, "PineTall": 26}
TREE_CROWN_TRIS = 300
TREE_TRUNK_TRIS = 60
KAYAK_LENGTH = 8
KAYAK_WIDTH = 2.4

COLORS = {"Crown": (0.2, 0.62, 0.22, 1), "Trunk": (0.42, 0.24, 0.13, 1), "Rock": (0.5, 0.52, 0.55, 1), "Hull": (0.3, 0.8, 0.45, 1), "Cockpit": (0.05, 0.06, 0.08, 1)}


def load(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=AI + name + ".glb")
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    obj = new[0]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.parent = None
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)  # szwy UV, inaczej odchudzanie robi dziury (STYLE.md)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def separate(obj):
    before = set(bpy.data.objects)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [obj] + [o for o in bpy.data.objects if o not in before]


def bounds(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    low = Vector(min(p[i] for p in points) for i in range(3))
    high = Vector(max(p[i] for p in points) for i in range(3))
    return low, high


# Nitka łącząca dwa drzewa: w poprzek osi X najdłuższy pas prawie bez wierzchołków, a w nim usuwamy ściany.
def cut_thread(obj):
    xs = sorted(v.co.x for v in obj.data.vertices)
    low, high = xs[0], xs[-1]
    bins = [0] * 200
    for x in xs:
        bins[min(int((x - low) / (high - low) * 200), 199)] += 1
    best, start, run = (0, 0), None, 0
    for index, count in enumerate(bins):
        if count <= 6:
            start = index if start is None else start
            run = index - start + 1
            if run > best[1]:
                best = (start, run)
        else:
            start = None
    left = low + best[0] / 200 * (high - low)
    right = low + (best[0] + best[1]) / 200 * (high - low)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    doomed = [f for f in bm.faces if left <= f.calc_center_median().x <= right]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    print("## nitka:", round(left, 3), round(right, 3), "usuniete sciany", len(doomed))


# Podział drzewa na koronę i pień po kolorze tekstury z Meshy (zielone kontra brązowe).
def split_tree(obj):
    image = obj.data.materials[0].node_tree.nodes
    tex = next(n for n in image if n.type == "TEX_IMAGE").image
    width, height = tex.size
    pixels = tex.pixels[:]
    uv = obj.data.uv_layers.active.data
    crown, trunk = [], []
    for poly in obj.data.polygons:
        u = sum(uv[i].uv.x for i in poly.loop_indices) / poly.loop_total
        v = sum(uv[i].uv.y for i in poly.loop_indices) / poly.loop_total
        x, y = int(u * (width - 1)) % width, int(v * (height - 1)) % height
        r, g = pixels[(y * width + x) * 4], pixels[(y * width + x) * 4 + 1]
        (crown if g > r else trunk).append(poly.index)
    return piece(obj, crown), piece(obj, trunk)


def piece(obj, faces):
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.collection.objects.link(copy)
    keep = set(faces)
    bm = bmesh.new()
    bm.from_mesh(copy.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bm.to_mesh(copy.data)
    bm.free()
    return copy


def close(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    open_edges = [e for e in bm.edges if e.is_boundary]
    if open_edges:
        bmesh.ops.holes_fill(bm, edges=open_edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


def decimate(obj, target):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > target:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("d", "DECIMATE")
        modifier.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def finish(obj, name, color, smooth):
    obj.name = obj.data.name = name
    for key in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(key)
    obj.data.materials.clear()
    material = bpy.data.materials.get(color) or bpy.data.materials.new(color)
    material.diffuse_color = COLORS[color]
    obj.data.materials.append(material)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    print("##", name, sum(1 for _ in obj.data.polygons), "tr, rozmiar", tuple(round(v, 2) for v in bounds(obj)[1] - bounds(obj)[0]))


# Przesunięcie i skala do całości zestawu części: wspólny pivot, oś pionowa Z.
def place(parts, factor, offset):
    for obj in parts:
        for vertex in obj.data.vertices:
            vertex.co = (vertex.co + offset) * factor


def build_trees():
    pieces = separate(load("trees"))
    # Sklejone nitką drzewa to najszersza bryła: dopiero w niej pas bez wierzchołków oznacza nitkę, a nie przerwę
    glued = max(pieces, key=lambda p: bounds(p)[1].x - bounds(p)[0].x)
    cut_thread(glued)
    pieces.remove(glued)
    pieces += separate(glued)
    pieces = [p for p in pieces if len(p.data.polygons) > 200]
    # Kolejność w modelu z Meshy: od lewej koncepcji do prawej; nazwy po kształcie (szerokość korony do wysokości)
    pieces.sort(key=lambda p: (bounds(p)[1].z - bounds(p)[0].z) / (bounds(p)[1].x - bounds(p)[0].x))
    names = ["Double", "Round", "Pine", "PineTall"]
    for shape, tree in zip(names, pieces):
        crown, trunk = split_tree(tree)
        low, high = bounds(tree)
        base = Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))
        factor = TREE_HEIGHT[shape] / (high.z - low.z)
        place([crown, trunk], factor, base)
        close(crown)
        close(trunk)
        decimate(crown, TREE_CROWN_TRIS)
        decimate(trunk, TREE_TRUNK_TRIS)
        finish(crown, "Tree" + shape + "_Crown", "Crown", True)
        finish(trunk, "Tree" + shape + "_Trunk", "Trunk", True)
        bpy.data.objects.remove(tree)


# Skały i kajak z Meshy miały luki i ściany w środku, więc powstają tu według konceptów rocks_b i kayak_a: czysta siatka, zero kredytów.
def mesh_object(name, verts, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_rocks():
    for name, seed, stretch in (("A", 3, (1, 0.9, 0.72)), ("B", 7, (1, 1, 0.8)), ("C", 11, (0.85, 1, 0.68))):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1)
        generator = random.Random(seed)
        for vertex in bm.verts:
            vertex.co *= generator.uniform(0.9, 1.08)
            vertex.co = Vector(vertex.co[i] * stretch[i] for i in range(3))
        mesh = bpy.data.meshes.new("Rock" + name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("Rock" + name, mesh)
        bpy.context.collection.objects.link(obj)
        finish(obj, "Rock" + name, "Rock", False)


# Przekrój kadłuba: łódka z płaskim pokładem i zaokrąglonym dnem, dziób i rufa schodzą do krawędzi.
def build_kayak():
    stations, sides = 22, 12
    half = KAYAK_WIDTH / 2
    verts, faces = [], []
    for s in range(stations):
        t = s / (stations - 1)
        along = 2 * t - 1
        width = half * max(1 - abs(along) ** 2.4, 0.015)
        lift = 0.28 * abs(along) ** 2.6  # dziób i rufa lekko w górę
        depth = 0.72 * max(1 - abs(along) ** 3, 0.05)
        for k in range(sides):
            angle = 2 * math.pi * k / sides
            x, z = math.cos(angle), math.sin(angle)
            deck = 0.28 * max(z, 0) ** 0.7
            bottom = depth * max(-z, 0) ** 0.8
            verts.append((width * math.copysign(abs(x) ** 0.75, x), KAYAK_LENGTH * (t - 0.5), lift + deck * (0.3 + 0.7 * width / half) - bottom))
    for s in range(stations - 1):
        for k in range(sides):
            n = (k + 1) % sides
            a, b = s * sides + k, s * sides + n
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple((stations - 1) * sides + k for k in range(sides)))
    hull = mesh_object("Kayak_Hull", verts, faces)
    close(hull)
    # Obrzeże kokpitu i ciemne dno: postać i tak zasłania środek, więc bez prawdziwej dziury
    ring = 20
    rx, ry = 0.74, 1.35
    top = 0.33
    rim_verts, rim_faces, floor_verts = [], [], []
    for k in range(ring):
        angle = 2 * math.pi * k / ring
        c, n = math.cos(angle), math.sin(angle)
        for scale, height in ((1.12, top - 0.1), (1.1, top + 0.08), (1.0, top + 0.1), (0.96, top - 0.04)):
            rim_verts.append((rx * scale * c, ry * scale * n, height))
        floor_verts.append((rx * 0.97 * c, ry * 0.97 * n, top - 0.03))
    for k in range(ring):
        n = (k + 1) % ring
        for level in range(3):
            rim_faces.append((k * 4 + level, n * 4 + level, n * 4 + level + 1, k * 4 + level + 1))
    rim = mesh_object("Kayak_Rim", rim_verts, rim_faces)
    bm = bmesh.new()
    bm.from_mesh(rim.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(rim.data)
    bm.free()
    floor = mesh_object("Kayak_Cockpit", floor_verts, [tuple(range(ring))])
    bmesh_join(hull, rim)
    finish(hull, "Kayak_Hull", "Hull", True)
    finish(floor, "Kayak_Cockpit", "Cockpit", True)


def bmesh_join(target, other):
    bm = bmesh.new()
    bm.from_mesh(target.data)
    bm.from_mesh(other.data)
    bm.to_mesh(target.data)
    bm.free()
    bpy.data.objects.remove(other)


def render(names, filename, eye):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_backface_culling = True  # Roblox nie rysuje tylnych ścian
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = (0.75, 0.85, 0.92)
    scene.render.resolution_x, scene.render.resolution_y = 1000, 620
    shown = [o for o in bpy.data.objects if o.type == "MESH"]
    groups = sorted({o.name.split("_")[0] for o in shown if o.name.split("_")[0].startswith(names)})
    for obj in shown:
        obj.hide_render = obj.name.split("_")[0] not in groups
        if not obj.hide_render:
            obj.location.x = groups.index(obj.name.split("_")[0]) * (28 if names == "Tree" else 4)
    bpy.context.view_layer.update()
    target = [o for o in shown if not o.hide_render]
    points = [o.matrix_world @ v.co for o in target for v in o.data.vertices]
    low = Vector(min(p[i] for p in points) for i in range(3))
    high = Vector(max(p[i] for p in points) for i in range(3))
    center, size = (low + high) / 2, (high - low).length
    camera = scene.camera
    camera.location = center + Vector(eye).normalized() * size * 1.5
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = PREVIEW + filename
    bpy.ops.render.render(write_still=True)
    for obj in shown:
        obj.location = (0, 0, 0)
        obj.hide_render = False
    bpy.context.view_layer.update()


bpy.ops.wm.read_factory_settings(use_empty=True)
os.makedirs(PREVIEW, exist_ok=True)
build_trees()
build_rocks()
build_kayak()
for block in list(bpy.data.objects):
    if block.type != "MESH":
        bpy.data.objects.remove(block)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.fbx(
    filepath=EXPORT + "pilot.fbx",
    use_selection=True,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z",
    axis_up="Y",
    object_types={"MESH"},
    use_mesh_modifiers=True,
    add_leaf_bones=False,
    bake_anim=False,
)
camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
bpy.context.scene.collection.objects.link(camera)
bpy.context.scene.camera = camera
render("Tree", "trees.png", (0.25, -1, 0.3))
render("Rock", "rocks.png", (0.3, -1, 0.5))
render("Kayak", "kayak.png", (0.75, -1, 0.7))
