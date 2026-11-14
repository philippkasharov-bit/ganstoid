"""M2: car_90s_sedan.glb, a boxy 1990s West Coast sedan sat low (~4.5 m).

Body (one mesh: paint, dark trim, glass, chrome, head and tail lamps) with
the wheel wells cut in by booleans, and four wheel children (wheel_FL ..
wheel_RR) whose origins are their hubs, so the game can spin them.

    python3 tools/models/glb_car.py assets/models/car_90s_sedan.glb
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import math  # noqa: E402

import bpy  # noqa: E402
import glb_lib as lib  # noqa: E402

LENGTH = 4.5
HALF_W = 0.9
WHEEL_X = 1.42
WHEEL_R = 0.33
WHEEL_W = 0.22
WHEEL_Y = HALF_W - WHEEL_W * 0.5 - 0.02
BODY_PROFILE = [(-2.25, 0.2), (2.25, 0.2), (2.28, 0.48), (2.24, 0.78), (1.05, 0.86), (-1.5, 0.88), (-2.24, 0.86), (-2.28, 0.52)]
GLASS_PROFILE = [(1.05, 0.86), (0.2, 1.36), (-0.95, 1.38), (-1.5, 0.88)]


def body() -> bpy.types.Object:
    """The shell (bevelled, wheel wells cut) joined with its trims, glass and lamps."""
    shell = lib.Builder("car_body")
    shell.slab(BODY_PROFILE, -HALF_W, HALF_W, {"side": "Body_Paint", 0: "Dark_Trim"})
    ob = shell.finish(bevel=0.025)
    for i, (x, y) in enumerate((x, y) for x in (WHEEL_X, -WHEEL_X) for y in (-1, 1)):
        _well(ob, x, y, i)
    _apply(ob)   # cut the wells on the closed shell alone: booleans fail on overlapping trims
    trims = _trims().finish(bevel=0.012)
    _apply(trims)
    bpy.ops.object.select_all(action="DESELECT")
    trims.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    return ob


def _trims() -> lib.Builder:
    b = lib.Builder("trims")
    b.slab(GLASS_PROFILE, -HALF_W * 0.86, HALF_W * 0.86, {"side": "Glass", 0: "Glass", 1: "Body_Paint", 2: "Glass", 3: "Body_Paint"})
    for y in (-1, 1):   # B-pillars between the side windows, in paint, and the mirrors
        b.box((-0.12, y * HALF_W * 0.87 - 0.02, 0.88), (0.0, y * HALF_W * 0.87 + 0.02, 1.36), "Body_Paint")
        b.box((0.98, y * HALF_W - 0.02, 0.9), (1.1, y * (HALF_W + 0.1), 0.99), "Dark_Trim")
    b.box((2.22, -HALF_W - 0.01, 0.26), (2.32, HALF_W + 0.01, 0.42), "Chrome")   # bumpers
    b.box((-2.32, -HALF_W - 0.01, 0.26), (-2.22, HALF_W + 0.01, 0.42), "Chrome")
    b.box((2.27, -0.5, 0.5), (2.3, 0.5, 0.7), "Dark_Trim")   # grille
    for y in (-0.68, 0.68):
        b.box((2.27, y - 0.17, 0.56), (2.31, y + 0.17, 0.7), "Emissive_Head")
        b.box((-2.31, y - 0.16, 0.6), (-2.27, y + 0.16, 0.74), "Emissive_Tail")
    return b


def _apply(ob: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def _well(ob: bpy.types.Object, x: float, side: int, i: int) -> None:
    """A wheel well: a cylinder subtracted from the body's side."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=WHEEL_R + 0.07, depth=0.5, location=(x, side * HALF_W, WHEEL_R), rotation=(1.5708, 0, 0))
    cutter = bpy.context.active_object
    cutter.name = "well_%d" % i
    mod = ob.modifiers.new("well_%d" % i, "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    cutter.hide_render = True
    cutter["cutter"] = True


def wheel(name: str, x: float, y: float) -> bpy.types.Object:
    """Tyre and chrome rim, built round its own hub (origin), axle along Y."""
    b = lib.Builder(name)
    sides = 16
    for k in range(sides):
        a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
        p = lambda a, r, yy: (r * math.cos(a), yy, r * math.sin(a))  # noqa: E731
        hw = WHEEL_W * 0.5
        b.face([p(a0, WHEEL_R, -hw), p(a1, WHEEL_R, -hw), p(a1, WHEEL_R, hw), p(a0, WHEEL_R, hw)], "Tyre")
        for yy, flip in ((hw, False), (-hw, True)):
            ring = [p(a0, WHEEL_R, yy), p(a1, WHEEL_R, yy), p(a1, WHEEL_R * 0.62, yy), p(a0, WHEEL_R * 0.62, yy)]
            b.face(list(reversed(ring)) if flip else ring, "Tyre")
            hub = [(0, yy * 1.08, 0), p(a1, WHEEL_R * 0.62, yy * 1.08), p(a0, WHEEL_R * 0.62, yy * 1.08)]
            b.face(list(reversed(hub)) if flip else hub, "Chrome")   # the rim: lowrider chrome
    ob = b.finish()
    ob.location = (x, y, WHEEL_R)
    return ob


def build(path: str) -> None:
    lib.reset()
    car = body()
    wheels = [wheel("wheel_%s%s" % (fr, lr), x, side * WHEEL_Y)
        for fr, x in (("F", WHEEL_X), ("R", -WHEEL_X)) for lr, side in (("L", 1), ("R", -1))]
    for w in wheels:
        w.parent = car
    for ob in [o for o in bpy.data.objects if o.get("cutter")]:
        bpy.data.objects.remove(ob)
    lib.export([car, *wheels], path)
    print("car_90s_sedan:", lib.triangles(car), "body triangles,", lib.triangles(wheels[0]), "per wheel ->", path)


if __name__ == "__main__":
    build(sys.argv[-1])
