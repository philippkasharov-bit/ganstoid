"""M1: low-poly models for Tagged, made in Blender (bpy, headless).

People are built as separate parts so the game's rig can swing them
(legs, arms, torso, head, hair), each centred where the rig expects its
box, in metres. Shading that should differ inside a part (shoes, hands,
belt, windows) is baked as a vertex colour: the game multiplies it with
the person's or car's own colour. Cars are a body and a glass cabin, made
in a unit box (the game stretches them to each car's length and width).

Run: python3 tools/models/people_and_cars.py art/models
Exports OBJ (y up, -z forward) for Godot: x is forward, y up, z to the side.
"""
import sys, math, os
import bpy, bmesh

OUT = sys.argv[-1] if len(sys.argv) > 1 else "art/models"

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

def shade(bm, verts, grey):
    """Vertex colour (as a multiplier) on faces made of `verts`."""
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    vs = set(verts)
    for f in bm.faces:
        if all(v in vs for v in f.verts):
            for loop in f.loops:
                loop[layer] = (grey, grey, grey, 1.0)

def base_colour(bm):
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for loop in f.loops:
            loop[layer] = (1, 1, 1, 1)

# Godot axes in Blender terms: game x (forward) = B x, game y (up) = B z, game z (side) = -B y
def g(x, y, z):
    return (x, -z, y)

def loft(bm, rings):
    """Rings of (y, half_x, half_z, sides) from bottom to top, joined, capped."""
    made = []
    for y, hx, hz, n in rings:
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n + math.pi / n
            ring.append(bm.verts.new(g(math.cos(a) * hx, y, math.sin(a) * hz)))
        made.append(ring)
    for r0, r1 in zip(made, made[1:]):
        n = len(r0)
        for k in range(n):
            bm.faces.new((r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k]))
    bm.faces.new(list(reversed(made[0])))
    bm.faces.new(made[-1])
    return [v for r in made for v in r]

def box(bm, cx, cy, cz, sx, sy, sz):
    r = bmesh.ops.create_cube(bm, size=1.0)
    for v in r["verts"]:
        x, y, z = v.co.x * sx + cx, v.co.z * sy + cy, -v.co.y * sz + cz
        v.co = g(x, y, z)
    return r["verts"]

def export(ob, name):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_flat()
    path = os.path.join(OUT, name + ".obj")
    bpy.ops.wm.obj_export(filepath=path, export_selected_objects=True, export_materials=False, export_colors=True,
        export_uv=False, forward_axis="NEGATIVE_Z", up_axis="Y", export_normals=True)
    print("wrote", path)

def leg():
    bm = bmesh.new()
    loft(bm, [(-0.33, 0.07, 0.065, 8), (0.05, 0.085, 0.08, 8), (0.42, 0.1, 0.095, 8)])   # shin to thigh
    shoe = box(bm, 0.045, -0.385, 0.0, 0.26, 0.1, 0.13)
    base_colour(bm)
    shade(bm, shoe, 0.35)
    return new_obj("leg", bm)

def arm():
    bm = bmesh.new()
    loft(bm, [(-0.25, 0.05, 0.05, 7), (0.0, 0.06, 0.06, 7), (0.3, 0.07, 0.07, 7)])
    hand = box(bm, 0.0, -0.29, 0.0, 0.09, 0.1, 0.08)
    base_colour(bm)
    shade(bm, hand, 0.6)
    return new_obj("arm", bm)

def torso():
    bm = bmesh.new()
    loft(bm, [(-0.34, 0.13, 0.2, 8), (-0.2, 0.14, 0.21, 8), (0.1, 0.15, 0.24, 8), (0.27, 0.15, 0.27, 8), (0.34, 0.1, 0.17, 8)])
    belt = loft(bm, [(-0.31, 0.135, 0.205, 8), (-0.26, 0.137, 0.207, 8)])
    base_colour(bm)
    shade(bm, belt, 0.45)
    return new_obj("torso", bm)

def head():
    bm = bmesh.new()
    loft(bm, [(-0.14, 0.09, 0.09, 8), (-0.06, 0.13, 0.12, 8), (0.08, 0.135, 0.125, 8), (0.14, 0.1, 0.1, 8)])
    nose = box(bm, 0.135, -0.01, 0.0, 0.04, 0.05, 0.035)
    base_colour(bm)
    shade(bm, nose, 0.9)
    return new_obj("head", bm)

def hair():
    bm = bmesh.new()
    loft(bm, [(0.06, 0.15, 0.14, 8), (0.12, 0.14, 0.13, 8), (0.175, 0.085, 0.085, 8)])   # a cap of hair, above the eyes
    base_colour(bm)
    return new_obj("hair", bm)

def car_body():
    """Side profile (length along x, -0.5..0.5) extruded across the width: bumpers, hood, trunk."""
    bm = bmesh.new()
    prof = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.0), (0.46, 0.3), (0.22, 0.5), (-0.28, 0.5), (-0.47, 0.35), (-0.5, 0.05)]
    halves = []
    for z in (-0.5, 0.5):
        halves.append([bm.verts.new(g(x, y, z)) for x, y in prof])
    n = len(prof)
    bm.faces.new(halves[0])
    bm.faces.new(list(reversed(halves[1])))
    for k in range(n):
        bm.faces.new((halves[0][k], halves[1][k], halves[1][(k + 1) % n], halves[0][(k + 1) % n]))
    base_colour(bm)
    bumper = box(bm, 0.0, -0.45, 0.0, 1.02, 0.12, 1.02)
    shade(bm, bumper, 0.3)
    return new_obj("car_body", bm)

def car_cabin():
    """The glass house: sloped windscreen and rear window, pillars darker."""
    bm = bmesh.new()
    prof = [(-0.5, -0.5), (0.5, -0.5), (0.22, 0.5), (-0.32, 0.5)]
    halves = []
    for z in (-0.5, 0.5):
        halves.append([bm.verts.new(g(x, y, z)) for x, y in prof])
    n = len(prof)
    bm.faces.new(halves[0])
    bm.faces.new(list(reversed(halves[1])))
    for k in range(n):
        bm.faces.new((halves[0][k], halves[1][k], halves[1][(k + 1) % n], halves[0][(k + 1) % n]))
    base_colour(bm)
    roof = [v for v in halves[0] + halves[1] if v.co.z > 0.49]
    shade(bm, roof, 0.75)
    return new_obj("car_cabin", bm)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for make in (leg, arm, torso, head, hair, car_body, car_cabin):
        reset()
        export(make(), make.__name__)
