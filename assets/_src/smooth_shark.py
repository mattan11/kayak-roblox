# Wygładzenie Rekina bez przebudowy (decyzja Marka 2026-11-02): kształt z Meshy zostaje, znikają tylko pogięcia i postrzępienia.
# 1. scalenie rozciętych szwów, 2. zaklejenie małych dziur przy pysku, 3. usunięcie drobnych „okruchów” siatki,
# 4. kilka przejść wygładzania Laplace'a (zachowuje objętość, lekko), 5. jeden kolor z gry (tekstura z plamą odpada).
# Uruchomienie w otwartym Blenderze, gdy w scenie jest Kayak_Shark z assets/export/Kayak_Shark.glb:
#   exec(open(".../smooth_shark.py").read())

import bmesh
import bpy

EXPORT = "C:/Users/marek/Documents/roblox-kayak/assets/export/"

shark = bpy.data.objects["Kayak_Shark"]
cockpit = bpy.data.objects["Kayak_Shark_Cockpit"]
bm = bmesh.new()
bm.from_mesh(shark.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.01)
holes = [e for e in bm.edges if e.is_boundary]
bmesh.ops.holes_fill(bm, edges=holes, sides=40)  # duży otwór kokpitu (dużo krawędzi) zostaje otwarty
islands = []
seen = set()
for face in bm.faces:
    if face in seen:
        continue
    stack, island = [face], []
    seen.add(face)
    while stack:
        current = stack.pop()
        island.append(current)
        for edge in current.edges:
            for other in edge.link_faces:
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
    islands.append(island)
crumbs = [f for island in islands if len(island) < 40 for f in island]
bmesh.ops.delete(bm, geom=crumbs, context="FACES")
for _ in range(6):
    bmesh.ops.smooth_laplacian_vert(bm, verts=bm.verts, lambda_factor=0.6, lambda_border=0.0, use_x=True, use_y=True, use_z=True, preserve_volume=True)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.to_mesh(shark.data)
bm.free()
for poly in shark.data.polygons:
    poly.use_smooth = True
print("## dziury zaklejone:", len(holes), "okruchy usunięte:", len(crumbs), "ścian:", len(shark.data.polygons))

offset = shark.location.copy()
for obj in (shark, cockpit):
    obj.location -= offset
bpy.ops.object.select_all(action="DESELECT")
shark.select_set(True)
cockpit.select_set(True)
bpy.ops.export_scene.gltf(filepath=EXPORT + "Kayak_Shark.glb", export_format="GLB", use_selection=True, export_image_format="JPEG", export_jpeg_quality=85)
for obj in (shark, cockpit):
    obj.location += offset
