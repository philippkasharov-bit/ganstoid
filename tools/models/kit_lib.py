"""K2: shared helpers for the Blender house kit (bpy, headless).

Parts are built in game axes (x along the wall, y up, z out of the wall)
and mapped to Blender's (x, -z, y) on the way in, like
people_and_cars.py. Every face carries a material slot naming the cell of
the kit texture sheet it will use (K3), and a vertex colour whose red
channel is the glow mask (1 on glass, so lit windows glow at night).
"""
from __future__ import annotations

import math
import os

import bpy  # first: bpy makes the bmesh module importable
import bmesh  # noqa: I001

# material slot -> preview colour (the baked sheet replaces these in K3)
MATERIALS: dict[str, tuple[float, float, float]] = {
    "paint": (0.93, 0.91, 0.86), "door": (0.45, 0.22, 0.14), "glass": (0.24, 0.32, 0.42),
    "frosted": (0.72, 0.78, 0.8), "garage": (0.85, 0.85, 0.83), "concrete": (0.72, 0.7, 0.66),
    "roof_tile": (0.7, 0.33, 0.22), "metal": (0.35, 0.36, 0.37), "brick": (0.6, 0.32, 0.25),
    "rafter": (0.5, 0.36, 0.24), "ac": (0.78, 0.79, 0.8),
}
GLOWS = {"glass", "frosted"}
BEVEL_M = 0.006
BEVEL_MIN_EDGE_M = 0.3   # sash bars and knobs stay sharp: the triangles go where they show
SLOTS = list(MATERIALS)


def g(x: float, y: float, z: float) -> tuple[float, float, float]:
    """Game axes to Blender axes."""
    return (x, -z, y)


class Part:
    """A bmesh being filled with faces, each tagged with its material slot."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.bm = bmesh.new()

    def quad(self, pts: list[tuple[float, float, float]], mat: str) -> None:
        verts = [self.bm.verts.new(g(*p)) for p in pts]
        face = self.bm.faces.new(verts)
        face.material_index = SLOTS.index(mat)

    def box(self, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: str) -> None:
        """An axis-aligned box, all six faces facing out."""
        c = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        for face in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.quad([c[i] for i in face], mat)

    def tube(self, cx: float, cz: float, y0: float, y1: float, r: float, sides: int, mat: str) -> None:
        """An upright round post or pipe from y0 to y1 (capped)."""
        ring = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
        for k in range(sides):
            (ax, az), (bx, bz) = ring[k], ring[(k + 1) % sides]
            self.quad([(ax, y0, az), (bx, y0, bz), (bx, y1, bz), (ax, y1, az)], mat)
        self.quad([(x, y1, z) for x, z in ring], mat)

    def slab(self, a: tuple[float, float, float], b: tuple[float, float, float], half_w: float, thick: float, mat: str) -> None:
        """A sloped board from a to b (both on x = 0), half_w wide along x, thick downwards."""
        top = [(-half_w, a[1], a[2]), (half_w, a[1], a[2]), (half_w, b[1], b[2]), (-half_w, b[1], b[2])]
        bottom = [(x, y - thick, z) for x, y, z in top]
        self.quad(top, mat)
        self.quad(list(reversed(bottom)), mat)
        for i in range(4):
            j = (i + 1) % 4
            self.quad([bottom[i], bottom[j], top[j], top[i]], mat)

    def finish(self) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)   # boxes share corners: weld so edges are solid
        solid = [e for e in self.bm.edges if len(e.link_faces) == 2 and e.calc_length() >= BEVEL_MIN_EDGE_M]   # mid-poly: big hard edges catch a sliver of light
        bmesh.ops.bevel(self.bm, geom=solid, offset=BEVEL_M, segments=1, affect="EDGES", clamp_overlap=True)
        _glow_mask(self.bm)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for slot in SLOTS:
            me.materials.append(material(slot))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def _glow_mask(bm: bmesh.types.BMesh) -> None:
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for face in bm.faces:
        red = 1.0 if SLOTS[face.material_index] in GLOWS else 0.0
        for loop in face.loops:
            loop[layer] = (red, 1.0, 1.0, 1.0)


def material(slot: str) -> bpy.types.Material:
    mat = bpy.data.materials.get(slot)
    if mat is None:
        mat = bpy.data.materials.new(slot)
        mat.diffuse_color = (*MATERIALS[slot], 1.0)
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*MATERIALS[slot], 1.0)
    return mat


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def export(ob: bpy.types.Object, out_dir: str) -> str:
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    path = os.path.join(out_dir, ob.name + ".obj")
    bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True, export_materials=True, export_colors=True,
        export_uv=True, forward_axis="NEGATIVE_Z", up_axis="Y", export_normals=True)
    return path


def triangles(ob: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)
