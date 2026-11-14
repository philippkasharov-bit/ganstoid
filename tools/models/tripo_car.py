"""M3: the Tripo sedan (Magnific, from a reference image) made game-ready in Blender.

Applies the import transform, sets the length to LENGTH metres, stands it on
Z = 0 facing +X (the game's heading 0), cuts the four tyres out of the body
into wheel children whose origins are their hubs (so the game can spin
them), and exports car_90s_sedan.glb with the body named car_body.

    python3 tools/models/tripo_car.py <tripo.glb> assets/models/car_90s_sedan.glb
"""
from __future__ import annotations

import sys

import bpy
import bmesh
from mathutils import Vector

LENGTH = 4.9
TYRE_R = 0.36
WHEEL_OUT = 0.6        # tyre faces sit further than this from the centre line
TYRE_W = 0.24


def load(path: str) -> bpy.types.Object:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    ob = next(o for o in bpy.data.objects if o.type == "MESH")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    lo, hi = _bounds(ob)
    k = LENGTH / (hi.x - lo.x)
    for v in ob.data.vertices:
        v.co = Vector(((v.co.x - (lo.x + hi.x) / 2) * k, (v.co.y - (lo.y + hi.y) / 2) * k, (v.co.z - lo.z) * k))
    ob.name = "car_body"
    return ob


def _bounds(ob: bpy.types.Object) -> tuple[Vector, Vector]:
    cs = [v.co for v in ob.data.vertices]
    return Vector([min(c[i] for c in cs) for i in range(3)]), Vector([max(c[i] for c in cs) for i in range(3)])


def hubs(ob: bpy.types.Object) -> list[Vector]:
    """The four hubs: the middle of the low outer vertices in each quarter (FL, FR, RL, RR)."""
    out = []
    for fx in (1, -1):
        for fy in (1, -1):
            pts = [v.co for v in ob.data.vertices if v.co.z < TYRE_R * 2 and v.co.y * fy > WHEEL_OUT and v.co.x * fx > 0.6]
            xs = sorted(p.x for p in pts)
            mid_x = xs[len(xs) // 2] if xs else fx * 1.5
            out.append(_refine(ob, Vector((mid_x, fy, TYRE_R))))
    return out


def _refine(ob: bpy.types.Object, rough: Vector) -> Vector:
    """The hub as the tyre's own middle: the centre of the outer vertices within the tyre circle round `rough`."""
    side = 1 if rough.y > 0 else -1
    pts = [v.co for v in ob.data.vertices if v.co.y * side > WHEEL_OUT
        and (Vector((v.co.x, v.co.z)) - Vector((rough.x, rough.z))).length < TYRE_R]
    xs, zs = [p.x for p in pts], [p.z for p in pts]
    outer = max(abs(p.y) for p in pts)
    return Vector(((min(xs) + max(xs)) / 2, side * (outer - TYRE_W / 2), max(zs) / 2))


def cut_wheel(body: bpy.types.Object, hub: Vector, name: str) -> bpy.types.Object:
    """Moves the faces round `hub` (within the tyre, on the outer side) into their own object."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    side = 1 if hub.y > 0 else -1
    paint = _paint_test(body, bm)
    take = [f for f in bm.faces if f.calc_center_median().y * side > WHEEL_OUT and not paint(f)
        and all((Vector((v.co.x, v.co.z)) - Vector((hub.x, hub.z))).length < TYRE_R + 0.02 for v in f.verts)]
    wheel = bmesh.new()
    vmap = {}
    for f in take:
        verts = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = wheel.verts.new(v.co - hub)
            verts.append(vmap[v])
        try:
            wheel.faces.new(verts)
        except ValueError:
            pass
    bmesh.ops.delete(bm, geom=take, context="FACES_ONLY")
    bm.to_mesh(body.data)
    bm.free()
    me = bpy.data.meshes.new(name)
    wheel.to_mesh(me)
    wheel.free()
    for mat in body.data.materials:
        me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = hub
    return ob


def _paint_test(body: bpy.types.Object, bm: bmesh.types.BMesh):
    """f -> True when the face is the car's red paint (a fender lip), which stays on the body."""
    uv = bm.loops.layers.uv.active
    img = next((n.image for m in body.data.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE"), None)
    if uv is None or img is None:
        return lambda f: False
    px, w, h = img.pixels[:], img.size[0], img.size[1]
    def red(f) -> bool:
        u = sum(l[uv].uv.x for l in f.loops) / len(f.loops) % 1.0
        v = sum(l[uv].uv.y for l in f.loops) / len(f.loops) % 1.0
        i = (int(v * (h - 1)) * w + int(u * (w - 1))) * 4
        return px[i] - max(px[i + 1], px[i + 2]) > 0.1
    return red


def _copy_uvs(body: bpy.types.Object, wheel: bpy.types.Object) -> None:
    """Re-projects the wheel's UVs from the body's nearest faces (the cut copies positions only)."""
    if not body.data.uv_layers:
        return
    wheel.data.uv_layers.new(name=body.data.uv_layers[0].name)
    mod = wheel.modifiers.new("uv", "DATA_TRANSFER")
    mod.object = body
    mod.use_loop_data = True
    mod.data_types_loops = {"UV"}
    mod.loop_mapping = "POLYINTERP_NEAREST"
    bpy.context.view_layer.objects.active = wheel
    bpy.ops.object.modifier_apply(modifier="uv")


def main(src: str, out: str) -> None:
    body = load(src)
    original = body.copy()
    original.data = body.data.copy()
    bpy.context.scene.collection.objects.link(original)   # kept untouched for the wheels' UVs
    names = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
    wheels = []
    for hub, name in zip(hubs(body), names):
        w = cut_wheel(body, hub, name)
        wheels.append(w)
    for w in wheels:
        _copy_uvs(original, w)   # from the uncut body: the cut copied positions only
        w.parent = body
    bpy.data.objects.remove(original, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in [body, *wheels]:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("car:", [round(x, 2) for x in body.dimensions], [tuple(round(c, 2) for c in w.location) for w in wheels], "->", out)


if __name__ == "__main__":
    main(*sys.argv[-2:])
