"""M2: helpers for the .glb assets (bpy, headless). Real metres, origin at the
bottom-centre, forward along Blender +X (glTF/Godot +X: the game's cars
and people face +X at heading 0), up +Z (Godot +Y), left +Y (Godot -Z).
"""
from __future__ import annotations

import bpy  # first: bpy makes bmesh importable
import bmesh  # noqa: I001

# name -> (base colour, metallic, roughness, emission strength)
MATERIALS = {
    "Body_Paint": ((0.8, 0.8, 0.8), 0.35, 0.35, 0.0),   # white: the game tints it per car
    "Dark_Trim": ((0.03, 0.03, 0.035), 0.0, 0.6, 0.0),
    "Glass": ((0.06, 0.09, 0.12), 0.1, 0.08, 0.0),
    "Chrome": ((0.85, 0.86, 0.88), 1.0, 0.18, 0.0),
    "Tyre": ((0.025, 0.025, 0.03), 0.0, 0.9, 0.0),
    "Emissive_Head": ((1.0, 0.95, 0.82), 0.0, 0.3, 1.5),
    "Emissive_Tail": ((0.75, 0.04, 0.03), 0.0, 0.3, 1.2),
    "Hoodie": ((0.09, 0.1, 0.12), 0.0, 0.9, 0.0),
    "Pants": ((0.16, 0.22, 0.33), 0.0, 0.85, 0.0),
    "Sneaker": ((0.9, 0.9, 0.88), 0.0, 0.6, 0.0),
    "Sole": ((0.25, 0.25, 0.25), 0.0, 0.8, 0.0),
    "Skin": ((0.45, 0.3, 0.22), 0.0, 0.7, 0.0),
    "Cap": ((0.02, 0.02, 0.025), 0.0, 0.7, 0.0),
}


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    colour, metal, rough, glow = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if glow > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*colour, 1.0)
        bsdf.inputs["Emission Strength"].default_value = glow
    return mat


class Builder:
    """A bmesh filled with faces, each tagged with a named material."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.bm = bmesh.new()
        self.slots: list[str] = []

    def _slot(self, mat: str) -> int:
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def face(self, pts: list, mat: str) -> None:
        f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        f.material_index = self._slot(mat)

    def box(self, lo: tuple, hi: tuple, mat: str) -> None:
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        c = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.face([c[i] for i in q], mat)

    def slab(self, prof: list, y0: float, y1: float, mats: dict) -> None:
        """Side profile (x, z) extruded across y0..y1. mats: 'side' for both caps, and
        the strip between profile points k and k+1 by index (default 'strip')."""
        a = [(x, y0, z) for x, z in prof]
        b = [(x, y1, z) for x, z in prof]
        self.face(list(reversed(a)), mats.get("side", "Body_Paint"))
        self.face(b, mats.get("side", "Body_Paint"))
        n = len(prof)
        for k in range(n):
            j = (k + 1) % n
            self.face([a[k], a[j], b[j], b[k]], mats.get(k, mats.get("strip", "Body_Paint")))

    def finish(self, bevel: float = 0.0) -> bpy.types.Object:
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for s in self.slots:
            me.materials.append(material(s))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if bevel > 0.0:
            mod = ob.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
            mod.limit_method = "ANGLE"
            mod.harden_normals = False
        for poly in me.polygons:
            poly.use_smooth = False
        return ob


def export(objects: list, path: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
        export_animations=True, export_animation_mode="ACTIONS", export_yup=True)


def triangles(ob: bpy.types.Object) -> int:
    dg = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(dg).to_mesh()
    n = sum(len(p.vertices) - 2 for p in me.polygons)
    ob.evaluated_get(dg).to_mesh_clear()
    return n
