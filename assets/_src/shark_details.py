# Oczy i zęby Rekina jako osobne części (decyzja Marka 2026-11-02): kadłub ma jeden kolor z gry, więc to, co było namalowane
# w teksturze z Meshy, wycinamy z siatki po kolorze tekstury: białe ściany przy pysku = zęby, czarne na głowie = oczy.
# Uruchomienie w otwartym Blenderze po smooth_shark.py (Kayak_Shark ma jeszcze UV i teksturę):
#   exec(open(".../shark_details.py").read())
# Wynik: assets/export/Kayak_Shark.glb z częściami Kayak_Shark, Kayak_Shark_Cockpit, Shark_Teeth, Shark_Eyes, Shark_Shine.

import bmesh
import bpy
from mathutils import Matrix, Vector

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"
WHITE, DARK = 0.75, 0.12  # jasność tekstury: powyżej = biały, poniżej = czarny
TEETH_FRONT = 0.2  # zęby w pierwszej 1/5 długości (dziób = −Y)
TEETH_BOTTOM = -0.15  # niżej leży biały brzuch, który zostaje w kolorze kadłuba
EYES_FRONT = 0.3
EYES_BOTTOM = 0.35

shark = bpy.data.objects["Kayak_Shark"]
cockpit = bpy.data.objects["Kayak_Shark_Cockpit"]
mesh = shark.data
image = next(n.image for n in mesh.materials[0].node_tree.nodes if n.type == "TEX_IMAGE")  # materiał siatki, nie obiektu
width, height = image.size
pixels = image.pixels[:]
uv = mesh.uv_layers.active.data
ys = [p.center.y for p in mesh.polygons]
low, span = min(ys), max(ys) - min(ys)


def brightness(poly):
    u = sum(uv[i].uv.x for i in poly.loop_indices) / poly.loop_total
    v = sum(uv[i].uv.y for i in poly.loop_indices) / poly.loop_total
    k = (int(v % 1 * (height - 1)) * width + int(u % 1 * (width - 1))) * 4
    return sum(pixels[k:k + 3]) / 3


teeth, eyes = set(), set()
for poly in mesh.polygons:
    c, light = poly.center, brightness(poly)
    if light > WHITE and c.y < low + span * TEETH_FRONT and c.z > TEETH_BOTTOM:
        teeth.add(poly.index)
    elif light < DARK and c.y < low + span * EYES_FRONT and c.z > EYES_BOTTOM:
        eyes.add(poly.index)


def split(name, faces, colour):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    piece = shark.copy()
    piece.data = mesh.copy()
    piece.name = piece.data.name = name
    bpy.context.collection.objects.link(piece)
    bm = bmesh.new()
    bm.from_mesh(piece.data)
    bm.faces.index_update()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in faces], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")  # luźne wierzchołki psują obrys części
    # Lekkie wypchnięcie wzdłuż normalnej: część leży tuż nad kadłubem i nie migocze razem z nim
    for vert in bm.verts:
        vert.co += vert.normal * 0.015
    bm.to_mesh(piece.data)
    bm.free()
    piece.data.materials.clear()
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = colour
    piece.data.materials.append(material)
    print("##", name, len(piece.data.polygons), "ścian")
    return piece


# Oczy z tekstury wychodzą kanciaste, więc zostaje z nich tylko położenie: w środku każdego namalowanego oka
# stawiamy gładkie, spłaszczone czarne oko i biały błysk, przyklejone do skóry (jak u Krakena).
def round_eyes():
    centres = {}
    for index in eyes:
        poly = mesh.polygons[index]
        side = 1 if poly.center.x > 0 else -1
        total, normal, count = centres.get(side, (Vector(), Vector(), 0))
        centres[side] = (total + poly.center, normal + poly.normal, count + 1)
    pieces = []
    for name, colour, radius, depth, lift, shift in (
        ("Shark_Eyes", (0.02, 0.02, 0.03, 1), 0.2, 0.09, 0.0, Vector()),
        ("Shark_Shine", (1, 1, 1, 1), 0.06, 0.04, 0.07, Vector((0, -0.06, 0.07))),
    ):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old)
        bm = bmesh.new()
        for total, normal, count in centres.values():
            centre, out = total / count, normal.normalized()
            rotation = out.to_track_quat("Z", "Y").to_matrix().to_4x4()
            matrix = Matrix.Translation(centre + shift + out * lift) @ rotation @ Matrix.Diagonal((radius, radius * 1.15, depth, 1))
            bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=1, matrix=matrix)
        data = bpy.data.meshes.new(name)
        bm.to_mesh(data)
        bm.free()
        for poly in data.polygons:
            poly.use_smooth = True
        piece = bpy.data.objects.new(name, data)
        piece.location = shark.location
        bpy.context.collection.objects.link(piece)
        material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        material.diffuse_color = colour
        data.materials.append(material)
        print("##", name, len(data.polygons), "ścian, oczu:", len(centres))
        pieces.append(piece)
    return pieces


parts = [split("Shark_Teeth", teeth, (1, 1, 1, 1))] + round_eyes()
offset = shark.location.copy()
group = [shark, cockpit] + parts
for obj in group:
    obj.location -= offset
bpy.ops.object.select_all(action="DESELECT")
for obj in group:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=EXPORT + "Kayak_Shark.glb", export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=85)
for obj in group:
    obj.location += offset
