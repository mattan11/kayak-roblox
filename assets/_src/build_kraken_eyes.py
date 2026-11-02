# Nowe oczy Krakena: jedno oko z Meshy wyszło krzywe. Zamiast poprawiać teksturę stawiamy dwa symetryczne oczy z brył
# (turkusowa obwódka, czarna źrenica, biały błysk) na miejscu tych namalowanych. Kolory nadaje gra, jak u Kaczki.
# Uruchomienie w otwartym Blenderze, gdy w scenie jest Kayak_Kraken z assets/export/Kayak_Kraken.glb:
#   exec(open(".../build_kraken_eyes.py").read())
# Wynik: assets/export/Kayak_Kraken.glb z częściami Kayak_Kraken, Kayak_Kraken_Cockpit, Kraken_EyeRing, Kraken_Pupil, Kraken_Shine.
# Stare, krzywe oko (lewe, ok. (-0.57, -3.96, 0.87)) zamalowano w teksturze kolorem skóry z czoła; poprawiona tekstura:
# assets/_ai/kayaks/kraken2_fixed_eyes.png (poza gitem).

import bmesh
import bpy
from mathutils import Matrix, Vector

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"
EYE = Vector((1.08, -3.66, 0.97))  # środek prawego oka (namalowane oko z Meshy), lewe to lustro
HEAD = Vector((0, -3.3, 0.55))  # środek głowy: oczy patrzą od niego na zewnątrz
COLORS = {"EyeRing": (0.24, 0.86, 0.82, 1), "Pupil": (0.02, 0.02, 0.03, 1), "Shine": (1, 1, 1, 1)}


# Głowa z Meshy nie jest symetryczna, więc oko nie może stać w lustrzanym punkcie: promień od środka głowy w stronę
# oka trafia w skórę i tam oko się przykleja, z kierunkiem z normalnej powierzchni (oko leży na głowie, nie odstaje).
def eye_frame(side):
    kraken = bpy.data.objects["Kayak_Kraken"]
    start = Vector((0, EYE.y, EYE.z))
    direction = Vector((EYE.x * side, 0, 0)).normalized()
    origin = kraken.matrix_world.inverted() @ (kraken.matrix_world @ start)
    hit, location, normal, _ = kraken.ray_cast(origin + direction * 3, -direction)
    if not hit:
        centre = Vector((EYE.x * side, EYE.y, EYE.z))
        return centre, (centre - Vector((0, HEAD.y, HEAD.z))).normalized()
    out = (normal + direction * 0.5).normalized()
    return location, out


def disc(bm, centre, out, radius, depth, lift):
    rotation = out.to_track_quat("Z", "Y").to_matrix().to_4x4()
    matrix = Matrix.Translation(centre + out * lift) @ rotation @ Matrix.Diagonal((radius, radius, depth, 1))
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1, matrix=matrix)


def part(name, key, build):
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old)
    bm = bmesh.new()
    for side in (-1, 1):
        build(bm, *eye_frame(side))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new(name)
    material.diffuse_color = COLORS[key]
    material.use_nodes = True
    next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = COLORS[key]
    mesh.materials.append(material)
    return obj


kraken = bpy.data.objects["Kayak_Kraken"]
cockpit = bpy.data.objects["Kayak_Kraken_Cockpit"]
eyes = [
    part("Kraken_EyeRing", "EyeRing", lambda bm, c, o: disc(bm, c, o, 0.34, 0.12, -0.04)),
    part("Kraken_Pupil", "Pupil", lambda bm, c, o: disc(bm, c, o, 0.2, 0.08, 0.04)),
    part("Kraken_Shine", "Shine", lambda bm, c, o: disc(bm, c + Vector((0, -0.06, 0.08)), o, 0.06, 0.04, 0.1)),
]
for obj in eyes:
    obj.location = kraken.location
    print("##", obj.name, len(obj.data.polygons), "ścian")

# Eksport w układzie modelu: na chwilę przesuwamy wszystko do zera
offset = kraken.location.copy()
group = [kraken, cockpit] + eyes
for obj in group:
    obj.location -= offset
bpy.ops.object.select_all(action="DESELECT")
for obj in group:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=EXPORT + "Kayak_Kraken.glb", export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=85)
for obj in group:
    obj.location += offset
