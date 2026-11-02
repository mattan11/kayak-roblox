# Skin kajaka z Meshy (STYLE.md): GLB → jeden model gry z teksturą, na tej samej osi co Hull.
# Uruchomienie: blender.exe -b --factory-startup --python assets/_src/build_skin.py -- dragon
# Wynik: assets/export/Kayak_<Nazwa>.glb i render w assets/export/preview/. Dziób = −Y w Blenderze (−Z w Robloxie),
# środek modelu = środek Hull, dno 0,6 studs pod nim, jak Paint klasycznego kajaka. Kokpit dostaje osobne ciemne dno
# (Kayak_<Nazwa>_Cockpit) na wysokości siedzenia: model z Meshy jest w środku pusty, więc bez dna widać przez niego wodę.

import bmesh
import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

ROOT = "C:/Users/marek/Documents/roblox-kayak/assets/"
SKINS = {
    # bow: znak osi Y, na której stoi głowa w pliku z Meshy; length: długość w studs (fizyka liczy 8, dekoracje mogą wystawać);
    # height: spłaszczenie w pionie, żeby postać siedziała w kokpicie, a nie tonęła w wysokim kadłubie
    # align: obrót do najdłuższej osi (zestawy z Meshy leżą pod kątem), bow liczony już po obrocie
    "dragon": {"name": "Dragon", "bow": -1, "length": 10.0, "height": 0.65, "tris": 3500},
    "phoenix": {"name": "Phoenix", "bow": 1, "length": 10.0, "height": 0.65, "tris": 4000, "align": True},
    "kraken": {"name": "Kraken", "bow": -1, "length": 10.0, "height": 0.7, "tris": 4000, "align": True},
    "duck": {"name": "Duck", "bow": -1, "length": 9.0, "height": 0.75, "tris": 3000, "align": True},
    "rocket": {"name": "Rocket", "bow": -1, "length": 9.0, "height": 0.75, "tris": 3000, "align": True},
    "shark": {"name": "Shark", "bow": 1, "length": 9.0, "height": 0.75, "tris": 3000, "align": True},
    # Druga generacja (2026-11-02): Rekin i Rakieta osobno zamiast z zestawu, Kraken na meshy-7.1
    "kraken2": {"name": "Kraken", "bow": -1, "length": 10.0, "height": 0.7, "tris": 4500, "align": True},
    "shark2": {"name": "Shark", "bow": 1, "length": 9.5, "height": 0.8, "tris": 6000, "align": True},
    "rocket2": {"name": "Rocket", "bow": -1, "length": 9.5, "height": 0.8, "tris": 3500, "align": True},
    # Trzecia generacja Rekina (2026-11-02): obraz Nano Banana 2 → Smart Topology T2.5, zęby i oczy w teksturze
    "shark3": {"name": "Shark", "bow": -1, "length": 10.45, "height": 0.88, "tris": 6000, "align": True, "rebake": True},
    # Premium (2026-11-02): koncepty z assets/concepts/kayaks wgrane w aplikacji Meshy, te same ustawienia co Rekin 3
    "neon": {"name": "Neon", "bow": -1, "shape_cockpit": True, "length": 10.0, "height": 0.8, "tris": 6000, "align": True, "rebake": True},
    "ice_dragon": {"name": "IceDragon", "bow": 1, "length": 10.5, "height": 0.75, "tris": 6000, "align": True, "rebake": True},
}
TEXTURE = 1024
BOTTOM = -0.6
FLOOR = 0.62  # dno kokpitu względem środka Hull: tuż pod siedzeniem (Seat w KayakService: HULL_HEIGHT / 2 + 0.1, grubość 0,2)
DARK = 0.12  # jasność tekstury, poniżej której punkt uznajemy za wnętrze kokpitu

key = sys.argv[sys.argv.index("--") + 1]
skin = SKINS[key]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=ROOT + "_ai/kayaks/" + key + ".glb")
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
for other in [o for o in bpy.context.scene.objects if o != obj]:
    bpy.data.objects.remove(other)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
obj.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

mesh = obj.data
if skin.get("align"):
    middle = sum((v.co for v in mesh.vertices), Vector()) / len(mesh.vertices)
    sxx = sum((v.co.x - middle.x) ** 2 for v in mesh.vertices)
    syy = sum((v.co.y - middle.y) ** 2 for v in mesh.vertices)
    sxy = sum((v.co.x - middle.x) * (v.co.y - middle.y) for v in mesh.vertices)
    mesh.transform(Matrix.Translation(-middle))
    mesh.transform(Matrix.Rotation(math.pi / 2 - 0.5 * math.atan2(2 * sxy, sxx - syy), 4, "Z"))
points = [v.co for v in mesh.vertices]
low = Vector(min(p[i] for p in points) for i in range(3))
high = Vector(max(p[i] for p in points) for i in range(3))
factor = skin["length"] / (high.y - low.y)
center = (low + high) / 2
flip = -1 if skin["bow"] > 0 else 1  # głowa ma trafić na −Y
for vertex in mesh.vertices:
    p = (vertex.co - center) * factor
    vertex.co = Vector((p.x * flip, p.y * flip, p.z * skin.get("height", 1)))
bottom = min(v.co.z for v in mesh.vertices)
for vertex in mesh.vertices:
    vertex.co.z += BOTTOM - bottom
# Pełna siatka zostaje jako źródło wypalania tekstury (rebake), zanim kadłub zostanie odchudzony
source = None
if skin.get("rebake"):
    source = obj.copy()
    source.data = mesh.copy()
    bpy.context.collection.objects.link(source)

bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)  # szwy UV przed odchudzaniem, inaczej dziury (STYLE.md)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(mesh)
bm.free()
tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
decimate = obj.modifiers.new("decimate", "DECIMATE")
decimate.ratio = min(skin["tris"] / tris, 1)
bpy.ops.object.modifier_apply(modifier=decimate.name)
for poly in mesh.polygons:
    poly.use_smooth = True



# Smart Topology daje setki drobnych wysp UV, a odchudzanie miesza UV sąsiednich wysp: na kadłubie wychodzą ciemne
# kropki (Rekin 3, 2026-11-02). Przy „rebake” odchudzona siatka dostaje nowe UV, a kolor wypalamy z pełnego modelu.
def rebake():
    for other in bpy.context.scene.objects:
        other.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    image = bpy.data.images.new("Kayak_" + skin["name"] + "_baked", 2048, 2048)
    material = bpy.data.materials.new("Baked")
    material.use_nodes = True
    node = material.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    shader = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    material.node_tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
    material.node_tree.nodes.active = node
    obj.data.materials.clear()
    obj.data.materials.append(material)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    source.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.cage_extrusion = 0.05
    bake.max_ray_distance = 0.3
    bake.margin = 16
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    bpy.data.objects.remove(source)
    obj.select_set(True)
    print("## tekstura wypalona z pełnego modelu")


if source:
    rebake()
texture = next(n.image for n in obj.active_material.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)


# Otwór kokpitu: z góry na siatkę padają promienie, a te, które trafiają w ciemną teksturę wnętrza, wyznaczają owal.
def cockpit_outline():
    width, height = texture.size
    pixels = texture.pixels[:]
    uv = mesh.uv_layers.active.data
    low = Vector(min(v.co[i] for v in mesh.vertices) for i in range(3))
    high = Vector(max(v.co[i] for v in mesh.vertices) for i in range(3))
    hits = []
    step = 0.08
    x = low.x
    while x <= high.x:
        y = low.y
        while y <= high.y:
            hit, location, _, index = obj.ray_cast(Vector((x, y, high.z + 1)), Vector((0, 0, -1)))
            if hit and abs(x) < (high.x - low.x) / 4:
                poly = mesh.polygons[index]
                u = sum(uv[i].uv.x for i in poly.loop_indices) / poly.loop_total
                v = sum(uv[i].uv.y for i in poly.loop_indices) / poly.loop_total
                px = (int(v % 1 * (height - 1)) * width + int(u % 1 * (width - 1))) * 4
                hits.append((x, y, location.z, sum(pixels[px:px + 3]) / 3))
            y += step
        x += step
    # Wnętrze jest ciemne i leży niżej niż reszta pokładu, więc ciemne, ale wysokie oczy głowy nie wchodzą do owalu
    middle = sorted(h[2] for h in hits)[len(hits) // 2]
    dark = sorted(h[3] for h in hits)
    print("## jasność trafień: min", round(dark[0], 3), "10%", round(dark[len(dark) // 10], 3), "z mediana", round(middle, 2), "trafień", len(hits))
    found = [(h[0], h[1]) for h in hits if h[3] < DARK and h[2] < middle]
    span = max(h[1] for h in hits) - min(h[1] for h in hits)
    if len(found) < 40 or skin.get("shape_cockpit"):  # shape_cockpit: kadłub ciemny jak wnętrze (Neon)
        # Bez ciemnej tekstury (szary środek, ciemny kadłub) kokpit to zagłębienie: najniższe trafienia w środkowej części pokładu
        core = [h for h in hits if abs(h[1] - (max(g[1] for g in hits) + min(g[1] for g in hits)) / 2) < span * 0.3]
        depth = sorted(h[2] for h in core)
        cut = depth[0] + (depth[len(depth) // 2] - depth[0]) * 0.5
        found = [(h[0], h[1]) for h in core if h[2] < cut]
        print("## kokpit z kształtu, punktów", len(found))
    if not found:
        raise SystemExit("## brak ciemnego wnętrza kokpitu w teksturze: model do ponownego zamówienia")
    xs, ys = [p[0] for p in found], [p[1] for p in found]
    return Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)), (max(xs) - min(xs)) / 2 + step, (max(ys) - min(ys)) / 2 + step


center, rx, ry = cockpit_outline()
# Krawędź otworu ma wypaść tuż nad dnem: wtedy postać siedzi w kokpicie, a nie na wieku. Model z Meshy jest zwykle
# niższy w tym miejscu, więc podnosimy cały kadłub, zamiast dno.
rim = []
for k in range(24):
    angle = 2 * math.pi * k / 24
    start = Vector((center.x + rx * 1.2 * math.cos(angle), center.y + ry * 1.12 * math.sin(angle), 10))
    hit, location, _, _ = obj.ray_cast(start, Vector((0, 0, -1)))
    if hit:
        rim.append(location.z)
lift = FLOOR + 0.08 - sorted(rim)[len(rim) // 2]
for vertex in mesh.vertices:
    vertex.co.z += lift
print("## podniesienie kadłuba", round(lift, 2))
ring = 24
floor_mesh = bpy.data.meshes.new("Kayak_" + skin["name"] + "_Cockpit")
floor_mesh.from_pydata([(center.x + rx * math.cos(2 * math.pi * k / ring), center.y + ry * math.sin(2 * math.pi * k / ring), FLOOR) for k in range(ring)], [], [tuple(range(ring))])
floor = bpy.data.objects.new(floor_mesh.name, floor_mesh)
bpy.context.collection.objects.link(floor)
bm = bmesh.new()
bm.from_mesh(floor_mesh)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(floor_mesh)
bm.free()
dark = bpy.data.materials.new("CockpitDark")
dark.diffuse_color = (0.04, 0.04, 0.05, 1)
floor_mesh.materials.append(dark)
print("## dno kokpitu: środek", [round(c, 2) for c in center], "półosie", round(rx, 2), round(ry, 2))



# Tekstura ze Smart Topology to setki małych wysp UV na czarnym tle. Po odchudzeniu i zmniejszeniu tekstury brzegi wysp
# łapią czerń i na kadłubie wychodzą ciemne kropki (Rekin 3, 2026-11-02). Kolor brzegów wysp rozlewamy w przerwy.
def pad_islands(margin=2, steps=24):
    import numpy as np

    width, height = texture.size
    pixels = np.array(texture.pixels[:], dtype=np.float32).reshape(height, width, 4)
    mask = np.zeros((height, width), dtype=bool)
    uv = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        corners = [(uv[i].uv.x % 1 * (width - 1), uv[i].uv.y % 1 * (height - 1)) for i in poly.loop_indices]
        for k in range(1, len(corners) - 1):
            (ax, ay), (bx, by), (cx, cy) = corners[0], corners[k], corners[k + 1]
            x0, x1 = int(min(ax, bx, cx)), int(max(ax, bx, cx)) + 1
            y0, y1 = int(min(ay, by, cy)), int(max(ay, by, cy)) + 1
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
            area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if abs(area) < 1e-9:
                continue
            w1 = ((gx - ax) * (cy - ay) - (cx - ax) * (gy - ay)) / area
            w2 = ((bx - ax) * (gy - ay) - (gx - ax) * (by - ay)) / area
            inside = (w1 >= -0.01) & (w2 >= -0.01) & (w1 + w2 <= 1.01)
            mask[gy[inside].clip(0, height - 1), gx[inside].clip(0, width - 1)] = True
    shifts = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    known = mask.copy()
    for _ in range(margin):  # brzeg wyspy jest już rozmyty z czernią, więc też idzie do wymiany
        known &= np.logical_and.reduce([np.roll(known, s, axis=(0, 1)) for s in shifts])
    for _ in range(steps):
        total = np.zeros_like(pixels)
        count = np.zeros((height, width), dtype=np.float32)
        for s in shifts:
            total += np.roll(pixels * known[..., None], s, axis=(0, 1))
            count += np.roll(known, s, axis=(0, 1))
        fresh = ~known & (count > 0)
        pixels[fresh] = total[fresh] / count[fresh][:, None]
        known |= fresh
    texture.pixels[:] = pixels.ravel()
    print("## wyspy UV: pokrycie", round(float(mask.mean()), 2))


if not skin.get("rebake"):
    pad_islands()
texture.scale(TEXTURE, TEXTURE)
obj.name = mesh.name = "Kayak_" + skin["name"]
floor.select_set(True)

size = obj.dimensions
print("##", obj.name, sum(len(p.vertices) - 2 for p in mesh.polygons), "tr, rozmiar", [round(v, 2) for v in size])
bpy.ops.export_scene.gltf(filepath=ROOT + "export/" + obj.name + ".glb", export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=85)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_backface_culling = True
scene.display.shading.background_type = "VIEWPORT"
scene.display.shading.background_color = (0.75, 0.85, 0.92)
scene.render.resolution_x, scene.render.resolution_y = 900, 520
camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
scene.collection.objects.link(camera)
scene.camera = camera
camera.location = Vector((-6, -9, 5.5))
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
os.makedirs(ROOT + "export/preview", exist_ok=True)
scene.render.filepath = ROOT + "export/preview/" + obj.name + ".png"
bpy.ops.render.render(write_still=True)
