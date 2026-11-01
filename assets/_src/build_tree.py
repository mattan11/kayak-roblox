# Okrągłe drzewo według dębu z Anchorfall (korona z kilku zlanych kęp, gruby pień), w gładkim stylu Robloxa, bez tekstury.
# Uruchomienie: blender.exe -b --factory-startup --python assets/_src/build_tree.py -- TreeRound (albo TreeDouble)
# Wynik: assets/export/<nazwa>.fbx i render w assets/export/preview/. Pivot u podstawy pnia, wysokość około 20 studs.

import bmesh
import bpy
import math
import sys
from mathutils import Matrix, Vector

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"
CROWN_TRIS = 420
# (x, y, z, promień): duża kępa w środku i mniejsze wokół; lekko nierówno, żeby sylwetka nie była kulą
VARIANTS = {
	"TreeRound": [(0, 0, 14.2, 5.8), (-4.6, 1.2, 12.2, 4.3), (4.4, -1.6, 12.6, 4.5), (1.0, 4.6, 11.8, 3.9), (-0.8, -4.4, 12.8, 4.0), (0.8, 0.4, 16.2, 3.6)],
	"TreeDouble": [(-3.4, 0.6, 13.6, 5.2), (4.2, -0.8, 13.0, 4.8), (0.4, 3.8, 12.2, 3.8), (0.2, -3.6, 12.0, 3.6), (-7.0, -0.8, 11.8, 3.2), (7.6, 1.2, 11.6, 3.0), (-0.6, 0.2, 16.0, 3.4)],
}
NAME = sys.argv[sys.argv.index("--") + 1]
CLUMPS = VARIANTS[NAME]
GREEN = (0.3, 0.6, 0.3, 1)
BROWN = (0.49, 0.36, 0.27, 1)


def crown():
    bm = bmesh.new()
    for x, y, z, radius in CLUMPS:
        bmesh.ops.create_icosphere(bm, subdivisions=3, radius=radius, matrix=Matrix.Translation((x, y, z)))
    mesh = bpy.data.meshes.new(NAME + "_Crown")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(NAME + "_Crown", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Voxel zlewa kępy w jedną powłokę, wygładzenie zaokrągla zagłębienia, a odchudzanie zostawia gładką sylwetkę
    remesh = obj.modifiers.new("remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.5
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth = obj.modifiers.new("smooth", "SMOOTH")
    smooth.factor, smooth.iterations = 0.6, 12
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate = obj.modifiers.new("decimate", "DECIMATE")
    decimate.ratio = CROWN_TRIS / sum(len(p.vertices) - 2 for p in mesh.polygons)
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    finish(obj, GREEN)
    return obj


# Pień z rozszerzeniem u ziemi i dwa grube konary wchodzące w koronę.
def trunk():
    bm = bmesh.new()
    rings = [(0, 2.5), (0.8, 1.95), (2.5, 1.55), (6, 1.4), (10, 1.2)]
    sides = 10
    verts = []
    for height, radius in rings:
        ring = []
        for k in range(sides):
            angle = 2 * math.pi * k / sides
            ring.append(bm.verts.new((radius * math.cos(angle), radius * math.sin(angle), height)))
        verts.append(ring)
    for level in range(len(rings) - 1):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((verts[level][k], verts[level][n], verts[level + 1][n], verts[level + 1][k]))
    bm.faces.new(list(reversed(verts[0])))
    bm.faces.new(verts[-1])
    for start, end, radius in (((0, 0, 6.5), (-3.8, 1.0, 11), 0.55), ((0, 0, 7.5), (3.6, -1.2, 11.2), 0.5)):
        direction = Vector(end) - Vector(start)
        rotation = direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
        middle = (Vector(start) + Vector(end)) / 2
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius * 1.3, radius2=radius * 0.9, depth=direction.length, matrix=Matrix.Translation(middle) @ rotation)
    mesh = bpy.data.meshes.new(NAME + "_Trunk")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(NAME + "_Trunk", mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj, BROWN)
    return obj


def finish(obj, color):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    for poly in obj.data.polygons:
        poly.use_smooth = True
    material = bpy.data.materials.new(obj.name)
    material.diffuse_color = color
    obj.data.materials.append(material)
    corners = [Vector(c) for c in obj.bound_box]
    size = tuple(round(max(c[i] for c in corners) - min(c[i] for c in corners), 1) for i in range(3))
    print("##", obj.name, len(obj.data.polygons), "tr, rozmiar", size)


bpy.ops.wm.read_factory_settings(use_empty=True)
parts = [crown(), trunk()]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.fbx(
    filepath=EXPORT + NAME + ".fbx",
    use_selection=True,
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z",
    axis_up="Y",
    object_types={"MESH"},
    add_leaf_bones=False,
    bake_anim=False,
)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.light = "STUDIO"
scene.display.shading.show_backface_culling = True
scene.display.shading.background_type = "VIEWPORT"
scene.display.shading.background_color = (0.75, 0.85, 0.92)
scene.render.resolution_x, scene.render.resolution_y = 800, 800
camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
scene.collection.objects.link(camera)
scene.camera = camera
target = Vector((0, 0, 10))
camera.location = target + Vector((0.45, -1, 0.15)).normalized() * 42
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = EXPORT + "preview/" + NAME + ".png"
bpy.ops.render.render(write_still=True)
