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
    loft(bm, [(-0.33, 0.065, 0.06, 10), (-0.12, 0.08, 0.075, 10), (0.02, 0.078, 0.075, 10), (0.2, 0.095, 0.09, 10), (0.42, 0.105, 0.1, 10)])   # ankle, calf, knee, thigh
    shoe = box(bm, 0.05, -0.385, 0.0, 0.27, 0.09, 0.12)
    toe = box(bm, 0.17, -0.395, 0.0, 0.07, 0.07, 0.11)
    sole = box(bm, 0.05, -0.425, 0.0, 0.28, 0.025, 0.125)
    base_colour(bm)
    shade(bm, shoe + toe, 0.32)
    shade(bm, sole, 0.9)   # G5: white soles
    return new_obj("leg", bm)

def arm():
    bm = bmesh.new()
    loft(bm, [(-0.22, 0.045, 0.045, 9), (-0.05, 0.055, 0.055, 9), (0.02, 0.052, 0.052, 9), (0.18, 0.065, 0.065, 9), (0.3, 0.075, 0.075, 9)])   # wrist, forearm, elbow, upper arm, shoulder
    hand = loft(bm, [(-0.33, 0.04, 0.025, 8), (-0.27, 0.05, 0.03, 8), (-0.22, 0.045, 0.04, 8)])
    thumb = box(bm, 0.03, -0.27, 0.035, 0.03, 0.06, 0.025)
    base_colour(bm)
    shade(bm, hand + thumb, 0.62)
    return new_obj("arm", bm)

def torso():
    bm = bmesh.new()
    loft(bm, [(-0.34, 0.13, 0.19, 12), (-0.2, 0.135, 0.2, 12), (-0.02, 0.15, 0.22, 12), (0.18, 0.16, 0.26, 12), (0.28, 0.14, 0.27, 12), (0.33, 0.09, 0.15, 12)])   # hips, waist, chest, shoulders
    belt = loft(bm, [(-0.31, 0.134, 0.196, 12), (-0.26, 0.135, 0.198, 12)])
    collar = loft(bm, [(0.3, 0.095, 0.16, 12), (0.335, 0.085, 0.14, 12)])
    base_colour(bm)
    shade(bm, belt, 0.42)
    shade(bm, collar, 0.85)
    return new_obj("torso", bm)

def head():
    bm = bmesh.new()
    loft(bm, [(-0.15, 0.06, 0.06, 10), (-0.12, 0.1, 0.095, 10), (-0.04, 0.125, 0.115, 10), (0.06, 0.135, 0.125, 10), (0.13, 0.115, 0.105, 10), (0.16, 0.06, 0.06, 10)])   # jaw to crown
    nose = box(bm, 0.13, -0.01, 0.0, 0.04, 0.05, 0.03)
    ears = box(bm, 0.0, 0.0, 0.125, 0.04, 0.06, 0.02) + box(bm, 0.0, 0.0, -0.125, 0.04, 0.06, 0.02)
    eyes = box(bm, 0.115, 0.035, 0.045, 0.02, 0.02, 0.03) + box(bm, 0.115, 0.035, -0.045, 0.02, 0.02, 0.03)
    base_colour(bm)
    shade(bm, nose, 0.9)
    shade(bm, ears, 0.92)
    shade(bm, eyes, 0.15)
    return new_obj("head", bm)

def hair():
    bm = bmesh.new()
    loft(bm, [(0.075, 0.145, 0.135, 10), (0.11, 0.145, 0.135, 10), (0.15, 0.12, 0.115, 10), (0.185, 0.06, 0.06, 10)])   # a cap of hair, above the eyes
    back = box(bm, -0.07, 0.02, 0.0, 0.06, 0.12, 0.24)   # down the back of the head
    base_colour(bm)
    return new_obj("hair", bm)

def slab(bm, prof, z0, z1):
    """Profile (x, y) extruded from z0 to z1, both ends capped; returns its verts."""
    halves = [[bm.verts.new(g(x, y, z)) for x, y in prof] for z in (z0, z1)]
    n = len(prof)
    bm.faces.new(halves[0])
    bm.faces.new(list(reversed(halves[1])))
    for k in range(n):
        bm.faces.new((halves[0][k], halves[1][k], halves[1][(k + 1) % n], halves[0][(k + 1) % n]))
    return halves[0] + halves[1]

def inset(prof, by):
    """The profile pulled in towards its middle (a bevelled side)."""
    return [(x * (1 - by), (y + 0.1) * (1 - by) - 0.1) for x, y in prof]

def arch(bm, x, side):
    """A dark half-oval over a wheel, just proud of the side."""
    pts = [(x + 0.1 * math.cos(a), -0.5 + 0.62 * math.sin(a)) for a in [math.pi * k / 8 for k in range(9)]]
    verts = [bm.verts.new(g(px, py, side)) for px, py in pts]
    bm.faces.new(verts if side > 0 else list(reversed(verts)))
    return verts

def car_body():
    """G5: a bevelled side profile (bumpers, hood, windscreen base, deck, trunk), wheel
    arches, dark rocker, door seams, grille and black plastic bumpers."""
    bm = bmesh.new()
    prof = [(-0.5, -0.42), (-0.49, -0.5), (0.49, -0.5), (0.5, -0.42), (0.5, -0.05), (0.47, 0.18), (0.38, 0.3), (0.2, 0.42),
        (0.16, 0.5), (-0.3, 0.5), (-0.36, 0.42), (-0.46, 0.34), (-0.5, 0.1)]
    slab(bm, prof, -0.44, 0.44)
    slab(bm, inset(prof, 0.06), -0.5, -0.44)
    slab(bm, inset(prof, 0.06), 0.44, 0.5)
    base_colour(bm)
    dark = []
    for side in (-0.505, 0.505):
        dark += arch(bm, 0.32, side) + arch(bm, -0.32, side)
    rocker = box(bm, 0.0, -0.44, 0.0, 0.62, 0.1, 1.012)
    seams = box(bm, 0.06, 0.05, 0.0, 0.006, 0.7, 1.01) + box(bm, -0.2, 0.05, 0.0, 0.006, 0.7, 1.01)
    grille = box(bm, 0.502, -0.12, 0.0, 0.01, 0.16, 0.6)
    bumpers = box(bm, 0.5, -0.36, 0.0, 0.05, 0.14, 1.02) + box(bm, -0.5, -0.36, 0.0, 0.05, 0.14, 1.02)
    shade(bm, dark, 0.12)
    shade(bm, rocker, 0.45)
    shade(bm, seams, 0.55)
    shade(bm, grille + bumpers, 0.25)
    return new_obj("car_body", bm)

def car_cabin():
    """G5: the glass house: raked windscreen and rear window, a dark B-pillar,
    the roof panel darker (it reads as metal over the glass)."""
    bm = bmesh.new()
    prof = [(-0.5, -0.5), (0.5, -0.5), (0.3, 0.3), (0.2, 0.5), (-0.3, 0.5), (-0.38, 0.3)]
    slab(bm, prof, -0.46, 0.46)
    slab(bm, inset(prof, 0.08), -0.5, -0.46)
    slab(bm, inset(prof, 0.08), 0.46, 0.5)
    base_colour(bm)
    roof = [v for v in bm.verts if v.co.z > 0.45]
    pillar = box(bm, -0.04, 0.0, 0.0, 0.07, 0.95, 1.012)
    shade(bm, roof, 0.75)
    shade(bm, pillar, 0.3)
    return new_obj("car_cabin", bm)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for make in (leg, arm, torso, head, hair, car_body, car_cabin):
        reset()
        export(make(), make.__name__)
