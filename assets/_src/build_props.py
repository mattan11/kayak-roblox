# Rekwizyty bez kredytów Meshy (STYLE.md): wiosło, skrzynka Bitwy i słupek bramy. Kolor nadaje gra.
# Boje zostają kulami z części: kula Robloxa jest gładka i tania, siatka nic by tu nie dała.
# Uruchomienie: blender.exe -b --factory-startup --python assets/_src/build_props.py
# Wynik: assets/export/props.fbx (jeden Import 3D) i render assets/export/preview/props.png.
# Oś: X w bok, Y przód−tył, Z w górę; po eksporcie Z Blendera to Y Robloxa.

import bmesh
import bpy
import math
from mathutils import Matrix, Vector

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"


def finish(bm, name, smooth):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    print("##", name, len(mesh.polygons), "tr")
    return obj


def cylinder(bm, sides, radius1, radius2, depth, matrix):
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius1, radius2=radius2, depth=depth, matrix=matrix)


# Drążek wzdłuż X, jak część Paddle (obraca nim klient przez PaddleJoint).
def build_shaft():
    bm = bmesh.new()
    cylinder(bm, 8, 0.1, 0.1, 6.8, Matrix.Rotation(math.pi / 2, 4, "Y"))
    return finish(bm, "PaddleShaft", True)


# Dwie łopaty: owal z lekkim zwężeniem do drążka, płaski jak dawny Blade.
def build_blades():
    bm = bmesh.new()
    points = 12
    for side in (-1, 1):
        for y, _ in ((-0.05, 0), (0.05, 1)):
            ring = []
            for k in range(points):
                angle = 2 * math.pi * k / points
                inner = -math.cos(angle) * side > 0
                x = 0.75 * math.cos(angle) * (0.85 if inner else 1)
                z = 0.42 * math.sin(angle) * (0.7 if inner else 1)
                ring.append(bm.verts.new((side * 3.5 + x, y, z)))
            bm.faces.new(ring if y > 0 else list(reversed(ring)))
            if y > 0:
                top = ring
            else:
                bottom = ring
        for k in range(points):
            n = (k + 1) % points
            bm.faces.new((bottom[k], bottom[n], top[n], top[k]))
    return finish(bm, "PaddleBlades", False)


# Skrzynka 3,5 studs: zaokrąglone krawędzie i wgłębione ścianki, żeby ikona nad nią nie musiała nieść całego wyglądu.
def build_crate():
    size = 3.5
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=size)
    sides = bm.faces[:]
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.22, segments=1, affect="EDGES")
    panels = [f for f in bm.faces if f.calc_area() > 4]
    bmesh.ops.inset_individual(bm, faces=panels, thickness=0.36, depth=-0.14)
    return finish(bm, "Crate", False)


# Słupek bramy: pivot u podstawy, zwężony, z grubszą głowicą. Wysokość 18 jak w RiverBuilder.buildGate.
def build_post():
    height = 18
    bm = bmesh.new()
    cylinder(bm, 8, 0.95, 0.62, height - 1.6, Matrix.Translation((0, 0, (height - 1.6) / 2)))
    cylinder(bm, 8, 0.72, 1.05, 0.5, Matrix.Translation((0, 0, height - 1.35)))
    cylinder(bm, 8, 1.05, 0.7, 1.1, Matrix.Translation((0, 0, height - 0.55)))
    return finish(bm, "GatePost", False)


bpy.ops.wm.read_factory_settings(use_empty=True)
parts = [build_shaft(), build_blades(), build_crate(), build_post()]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.fbx(
    filepath=EXPORT + "props.fbx",
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
scene.display.shading.show_backface_culling = True
scene.render.resolution_x, scene.render.resolution_y = 1000, 620
parts[0].location = parts[1].location = (0, 0, 10)
parts[2].location = (-6, 0, 3)
parts[3].location = (6, 0, 0)
camera = bpy.data.objects.new("camera", bpy.data.cameras.new("camera"))
scene.collection.objects.link(camera)
scene.camera = camera
target = Vector((0, 0, 8))
camera.location = target + Vector((0.5, -1, 0.35)).normalized() * 30
camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = EXPORT + "preview/props.png"
bpy.ops.render.render(write_still=True)
