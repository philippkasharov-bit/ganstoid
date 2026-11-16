"""K5: assemble sample houses from the kit in Blender and render them as the game's camera sees them.

    /tmp/bpyenv/bin/python tools/models/house_preview.py <out.png> <atlas.png> <kit_dir> [<kit_dir> ...] [--close]

One house per kit folder (the .obj parts house_kit.py writes), side by side, left to right:
stucco walls with real holes, a tiled hip roof, windows, the front door under a porch,
a garage door, corner and base trims, eave boards, gutters, downspouts, rafter tails,
a chimney, an AC unit and a meter, each placed the way HouseKit3D places it (origin at
the bottom-centre of the hole on the wall's outer face; trims and pipes stretched).
--close frames the front door and porch instead of the whole street.
A folder written `<kit_dir>:mid` gets the K6 mid-poly walls and roof: tile courses that step
like overlapping rows, rounded hip and ridge caps, a roof edge with thickness, a plinth band,
a textured stucco, a slim stucco chimney, and (LA) no gutters or downspouts.
"""
from __future__ import annotations

import math
import os
import sys

import bpy
import bmesh
import mathutils

W, D, H = 11.0, 8.0, 3.0          # the house: width, depth, storey height (m)
WALL_T = 0.25
OVERHANG = 0.45
PITCH = math.radians(22)
GAP = 6.0                         # metres between houses
SIZES = {"kit_window_sash": (1.0, 1.3), "kit_window_wide": (1.8, 1.3), "kit_window_small": (0.6, 0.6),
    "kit_door_front": (1.0, 2.1), "kit_door_garage": (2.6, 2.1)}
# wall -> openings (part, distance along the wall to its centre, sill height)
OPENINGS = {
    "front": [("kit_window_sash", 1.25, 0.9), ("kit_door_front", 3.5, 0.0), ("kit_window_wide", 7.8, 0.9)],
    "right": [("kit_door_garage", 3.6, 0.0), ("kit_window_small", 6.6, 1.6)],
    "back": [("kit_window_sash", 2.4, 0.9), ("kit_window_sash", 5.8, 0.9), ("kit_window_small", 8.7, 1.6)],
    "left": [("kit_window_sash", 2.0, 0.9), ("kit_window_sash", 4.4, 0.9)],
}
TINTS = {"paint": (0.93, 0.9, 0.82), "door": (0.12, 0.28, 0.2), "garage": (0.95, 0.94, 0.9)}


def walls(ox: float) -> dict[str, tuple]:
    """wall -> (start corner, along, out, length): a part at distance s sits at start + along*s."""
    return {
        "front": ((ox, 0.0), (1, 0), (0, -1), W),
        "right": ((ox + W, 0.0), (0, 1), (1, 0), D),
        "back": ((ox + W, D), (-1, 0), (0, 1), W),
        "left": ((ox, D), (0, -1), (-1, 0), D),
    }


class Kit:
    """The parts of one kit folder, imported once and copied for each use."""

    def __init__(self, folder: str, sheet: bpy.types.Image) -> None:
        self.parts: dict[str, bpy.types.Object] = {}
        self.sheet = sheet
        for f in sorted(os.listdir(folder)):
            if f.endswith(".obj"):
                before = set(bpy.data.objects)
                bpy.ops.wm.obj_import(filepath=os.path.join(folder, f), forward_axis="NEGATIVE_Z", up_axis="Y")
                ob = next(o for o in bpy.data.objects if o not in before)
                bpy.ops.object.select_all(action="DESELECT")   # the importer stands the part up with an object rotation:
                ob.select_set(True)                            # bake it in, or place() would overwrite it
                bpy.context.view_layer.objects.active = ob
                bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
                ob.hide_render = True
                ob.hide_viewport = True
                self._texture(ob)
                self.parts[f[:-4]] = ob

    def _texture(self, ob: bpy.types.Object) -> None:
        for i, slot in enumerate(ob.material_slots):
            name = slot.material.name.split(".")[0]
            ob.material_slots[i].material = textured(name, self.sheet)

    def place(self, name: str, wall: tuple, s: float, y: float, out: float = 0.0, sx: float = 1.0, sy: float = 1.0,
            tints: dict | None = None) -> None:
        (cx, cy), (ax, ay), (nx, ny), _ = wall
        src = self.parts[name]
        ob = src.copy()
        ob.hide_render = False
        ob.hide_viewport = False
        bpy.context.scene.collection.objects.link(ob)
        ob.location = (cx + ax * s + nx * out, cy + ay * s + ny * out, y)
        ob.rotation_euler = (0, 0, math.atan2(ny, nx) + math.pi / 2)   # parts face -Y in Blender
        ob.scale = (sx, 1.0, sy)
        if tints:   # K6: this house's paint, on the object (the mesh is shared by every copy)
            for i, slot in enumerate(ob.material_slots):
                name = ob.data.materials[i].name.split(".")[0].removeprefix("k_").split("|")[0]   # read before the switch empties it
                slot.link = "OBJECT"
                slot.material = textured(name, self.sheet, tints)


_mats: dict[str, bpy.types.Material] = {}


def textured(slot: str, sheet: bpy.types.Image, tints: dict | None = None) -> bpy.types.Material:
    """The kit's baked sheet; painted cells take this house's tint (alpha = paint mask), as kit_preview does."""
    tints = tints or TINTS
    key = slot + "|" + str(sorted(tints.items()))
    if key in _mats:
        return _mats[key]
    if os.environ.get("PLAIN"):   # debugging: flat colours, no sheet
        _mats[slot] = plain("p_" + slot, TINTS.get(slot, (0.6, 0.6, 0.6)))
        return _mats[slot]
    mat = bpy.data.materials.new("k_" + slot + "|" + str(len(_mats)))
    mat.use_nodes = True
    tree = mat.node_tree
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = sheet
    mix = tree.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["B"].default_value = (*tints.get(slot, (1.0, 1.0, 1.0)), 1.0)
    tree.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
    tree.links.new(tex.outputs["Color"], mix.inputs["A"])
    bsdf = tree.nodes["Principled BSDF"]
    tree.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.25 if slot == "glass" else 0.7
    _mats[key] = mat
    return mat


def plain(name: str, rgb: tuple, rough: float = 0.85, noise: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    if noise > 0:   # a little grain so big surfaces don't look like plastic
        tex = tree.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 40.0
        ramp = tree.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].color = (*[c * (1 - noise) for c in rgb], 1)
        ramp.color_ramp.elements[1].color = (*[min(1.0, c * (1 + noise)) for c in rgb], 1)
        tree.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        tree.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    return mat


def stucco_tex(path: str, rgb: tuple) -> bpy.types.Material:
    """K6: the game's stucco grain (art/textures/stucco.png), tiled in world space, tinting the wall colour."""
    mat = bpy.data.materials.new("stucco_tex")
    mat.use_nodes = True
    tree = mat.node_tree
    coord = tree.nodes.new("ShaderNodeTexCoord")
    mapping = tree.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (0.7, 0.7, 0.7)
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path)
    tex.projection = "BOX"
    tex.projection_blend = 0.3
    mix = tree.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.3   # the grain only shades the wall colour a little
    mix.inputs["A"].default_value = (*rgb, 1)
    bump = tree.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    tree.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    tree.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    tree.links.new(tex.outputs["Color"], mix.inputs["B"])
    tree.links.new(tex.outputs["Color"], bump.inputs["Height"])
    bsdf = tree.nodes["Principled BSDF"]
    tree.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def box(name: str, lo: tuple, hi: tuple, mat: bpy.types.Material | None = None) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = tuple(lo[i] + (v.co[i] + 0.5) * (hi[i] - lo[i]) for i in range(3))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat:
        me.materials.append(mat)
    return ob


def shell(ox: float, stucco: bpy.types.Material, openings: dict | None = None) -> None:
    """Four walls with the openings cut through them."""
    openings = openings or OPENINGS
    for name, wall in walls(ox).items():
        (cx, cy), (ax, ay), (nx, ny), length = wall
        trim = WALL_T if name in ("right", "left") else 0.0   # side walls stop at the front and back walls' backs (no overlap)
        a = (cx + ax * trim, cy + ay * trim)
        b = (cx + ax * (length - trim), cy + ay * (length - trim))
        inner = (cx - nx * WALL_T, cy - ny * WALL_T)
        lo = (min(a[0], b[0], inner[0]), min(a[1], b[1], inner[1]), 0.0)
        hi = (max(a[0], b[0], inner[0]), max(a[1], b[1], inner[1]), H)
        w = box("wall_" + name, lo, hi, stucco)
        for part, s, sill in openings[name]:
            if part in ARCH_SIZES:
                arch_cut(w, wall, s, sill, *ARCH_SIZES[part])
                continue
            ww, hh = SIZES[part]
            px, py = cx + ax * s, cy + ay * s
            half = (abs(ax) * ww / 2 + abs(nx) * 1.0, abs(ay) * ww / 2 + abs(ny) * 1.0)
            cut = box("cut", (px - half[0], py - half[1], sill), (px + half[0], py + half[1], sill + hh))
            mod = w.modifiers.new("hole", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.object = cut
            bpy.context.view_layer.objects.active = w
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(cut, do_unlink=True)
    box("floor", (ox, 0, -0.05), (ox + W, D, 0.02), stucco)


def roof(ox: float, tiles: bpy.types.Material) -> None:
    """A hip roof over the eaves, ridge along the long side."""
    o = OVERHANG
    x0, x1, y0, y1 = ox - o, ox + W + o, -o, D + o
    rise = (y1 - y0) / 2 * math.tan(PITCH)
    inset = (y1 - y0) / 2
    r0, r1 = (x0 + inset, (y0 + y1) / 2, H + 0.02 + rise), (x1 - inset, (y0 + y1) / 2, H + 0.02 + rise)
    bm = bmesh.new()
    e = H + 0.02   # the eave line: just over the rafter tails' tops
    c = [bm.verts.new(p) for p in ((x0, y0, e), (x1, y0, e), (x1, y1, e), (x0, y1, e))]
    r = [bm.verts.new(r0), bm.verts.new(r1)]
    for face in ((c[0], c[1], r[1], r[0]), (c[2], c[3], r[0], r[1]), (c[1], c[2], r[1]), (c[3], c[0], r[0])):
        bm.faces.new(face)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.12)
    me = bpy.data.meshes.new("roof")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("roof", me)
    ob.data.materials.append(tiles)
    bpy.context.scene.collection.objects.link(ob)


COURSE_M = 0.34     # K6: tile rows, measured up the slope
COURSE_LIP = 0.03   # each row's lower edge stands this proud of the one under it
CAP_R = 0.075       # hip and ridge caps


def roof_mid(ox: float, tiles: bpy.types.Material, caps: bpy.types.Material, pitch: float = PITCH,
        course: float = COURSE_M, round_caps: bool = True) -> None:
    """K6: the same hip roof in stepped tile courses, with rounded caps on the hips and the ridge
    (shingle: narrower courses and flat caps)."""
    o = OVERHANG
    x0, x1, y0, y1 = ox - o, ox + W + o, -o, D + o
    e = H + 0.02
    rise = (y1 - y0) / 2 * math.tan(pitch)
    inset = (y1 - y0) / 2
    r0 = mathutils.Vector((x0 + inset, (y0 + y1) / 2, e + rise))
    r1 = mathutils.Vector((x1 - inset, (y0 + y1) / 2, e + rise))
    c = [mathutils.Vector(p) for p in ((x0, y0, e), (x1, y0, e), (x1, y1, e), (x0, y1, e))]
    faces = [(c[0], c[1], r1, r0), (c[2], c[3], r0, r1), (c[1], c[2], r1, r1), (c[3], c[0], r0, r0)]
    bm = bmesh.new()
    for a, b, rb, ra in faces:
        n = (b - a).cross(ra - a).normalized()
        if n.z < 0:
            n = -n
        slope = (ra - a).length
        rows = max(1, int(slope / course))
        for k in range(rows):
            t0, t1 = k / rows, (k + 1) / rows
            lo_a, lo_b = a.lerp(ra, t0), b.lerp(rb, t0)
            hi_a, hi_b = a.lerp(ra, t1), b.lerp(rb, t1)
            lip = n * COURSE_LIP
            quad = [lo_a + lip, lo_b + lip, hi_b, hi_a]   # each row tilts a little more than the roof: it steps
            if (lo_b - lo_a).length < 0.01 and (hi_b - hi_a).length < 0.01:
                continue
            bm.faces.new([bm.verts.new(p) for p in quad])
            bm.faces.new([bm.verts.new(p) for p in (lo_a, lo_b, lo_b + lip, lo_a + lip)])   # the row's front edge
    edge = [bm.verts.new(p) for p in c]   # the roof's thickness at the eaves
    for i in range(4):
        a, b = c[i], c[(i + 1) % 4]
        bm.faces.new([bm.verts.new(p) for p in (a, b, b - mathutils.Vector((0, 0, 0.1)), a - mathutils.Vector((0, 0, 0.1)))])
    for v in edge:
        bm.verts.remove(v)
    me = bpy.data.meshes.new("roof_mid")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("roof_mid", me)
    ob.data.materials.append(tiles)
    bpy.context.scene.collection.objects.link(ob)
    for a, b in ((c[0], r0), (c[1], r1), (c[2], r1), (c[3], r0), (r0, r1)):   # hips and the ridge
        cap(a, b, caps, sides=6 if round_caps else 2)


def cap(a: mathutils.Vector, b: mathutils.Vector, mat: bpy.types.Material, sides: int = 6) -> None:
    """A half-round tile cap from a to b, sitting on the roof line."""
    axis = (b - a)
    length = axis.length
    d = axis.normalized()
    side = d.cross(mathutils.Vector((0, 0, 1)))
    if side.length < 1e-4:
        side = mathutils.Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    if up.z < 0:
        up = -up
    bm = bmesh.new()
    ring_a, ring_b = [], []
    for k in range(sides + 1):
        t = math.pi * k / sides
        off = side * math.cos(t) * CAP_R + up * (math.sin(t) * CAP_R + 0.01)
        ring_a.append(bm.verts.new(a + off))
        ring_b.append(bm.verts.new(b + off))
    for k in range(sides):
        bm.faces.new((ring_a[k], ring_a[k + 1], ring_b[k + 1], ring_b[k]))
    me = bpy.data.meshes.new("cap")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cap", me)
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)


def plinth(ox: float, mat: bpy.types.Material) -> None:
    """K6: a darker band round the foot of the walls, a little proud, its top chamfered."""
    t, hgt = 0.035, 0.45
    box("plinth", (ox - t, -t, 0.0), (ox + W + t, D + t, hgt), mat)
    box("plinth_top", (ox - t * 0.5, -t * 0.5, hgt), (ox + W + t * 0.5, D + t * 0.5, hgt + 0.025), mat)


def stucco_chimney(ox: float, mat: bpy.types.Material, cap_mat: bpy.types.Material) -> None:
    """K6, LA: a slim stucco chimney against the side wall, stepping in once, with a small cap."""
    x, y = ox - 0.28, 5.6
    box("chim_base", (x - 0.28, y - 0.55, 0.0), (x + 0.28, y + 0.55, H - 0.6), mat)
    box("chim_shoulder", (x - 0.2, y - 0.4, H - 0.6), (x + 0.28, y + 0.4, H - 0.35), mat)
    box("chim_stack", (x - 0.16, y - 0.32, H - 0.35), (x + 0.2, y + 0.32, H + 2.0), mat)
    box("chim_cap", (x - 0.22, y - 0.38, H + 2.0), (x + 0.26, y + 0.38, H + 2.1), cap_mat)
    box("chim_top", (x - 0.12, y - 0.24, H + 2.1), (x + 0.16, y + 0.24, H + 2.3), cap_mat)


# K6: the street of four that shows Phil's picks: a mix of roofs, a Spanish house, colours, wear.
STYLES = [
    {"name": "bungalow", "roof": "tile", "stucco": (0.86, 0.77, 0.6), "tints": {"paint": (0.95, 0.93, 0.86), "door": (0.12, 0.28, 0.2), "garage": (0.95, 0.94, 0.9)}},
    {"name": "worn pink", "roof": "shingle", "stucco": (0.84, 0.66, 0.62), "worn": True, "bars": True,
        "tints": {"paint": (0.62, 0.5, 0.4), "door": (0.45, 0.12, 0.1), "garage": (0.8, 0.78, 0.72)}},
    {"name": "spanish", "roof": "tile", "spanish": True, "stucco": (0.94, 0.92, 0.87), "tints": {"paint": (0.36, 0.22, 0.14), "door": (0.3, 0.17, 0.1), "garage": (0.4, 0.26, 0.16)}},
    {"name": "worn mint", "roof": "shingle", "stucco": (0.66, 0.78, 0.7), "worn": True,
        "tints": {"paint": (0.92, 0.9, 0.84), "door": (0.14, 0.2, 0.38), "garage": (0.9, 0.9, 0.86)}},
]
SPANISH_OPENINGS = dict(OPENINGS, front=[("arch_window", 1.25, 0.8), ("arch_door", 3.5, 0.0), ("kit_window_wide", 7.8, 0.9)])
ARCH_SIZES = {"arch_window": (1.0, 1.5), "arch_door": (1.1, 2.4)}


def stucco_style(path: str, rgb: tuple, worn: bool) -> bpy.types.Material:
    """The stucco; worn: dirt streaks running down from the top, grime near the ground, a few patched spots."""
    mat = stucco_tex(path, rgb)
    if not worn:
        return mat
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    base = bsdf.inputs["Base Color"].links[0].from_socket
    coord = tree.nodes.new("ShaderNodeTexCoord")
    streak_map = tree.nodes.new("ShaderNodeMapping")
    streak_map.inputs["Scale"].default_value = (1.6, 1.6, 0.45)   # a little longer in z: stains run down, in blotches
    streaks = tree.nodes.new("ShaderNodeTexNoise")
    streaks.inputs["Scale"].default_value = 1.4
    streaks.inputs["Detail"].default_value = 6.0
    s_ramp = tree.nodes.new("ShaderNodeValToRGB")
    s_ramp.color_ramp.elements[0].position, s_ramp.color_ramp.elements[1].position = 0.55, 0.75
    s_ramp.color_ramp.elements[0].color, s_ramp.color_ramp.elements[1].color = (1, 1, 1, 1), (0.8, 0.76, 0.7, 1)
    sep = tree.nodes.new("ShaderNodeSeparateXYZ")
    ground = tree.nodes.new("ShaderNodeMapRange")   # darker in the bottom 0.8 m (splash, dirt)
    ground.inputs["From Min"].default_value, ground.inputs["From Max"].default_value = 0.0, 0.8
    ground.inputs["To Min"].default_value, ground.inputs["To Max"].default_value = 0.72, 1.0
    patch = tree.nodes.new("ShaderNodeTexVoronoi")
    patch.inputs["Scale"].default_value = 0.9
    p_ramp = tree.nodes.new("ShaderNodeValToRGB")
    p_ramp.color_ramp.elements[0].position, p_ramp.color_ramp.elements[1].position = 0.06, 0.08
    p_ramp.color_ramp.elements[0].color, p_ramp.color_ramp.elements[1].color = (1.12, 1.1, 1.06, 1), (1, 1, 1, 1)
    m1 = tree.nodes.new("ShaderNodeMix"); m1.data_type = "RGBA"; m1.blend_type = "MULTIPLY"; m1.inputs["Factor"].default_value = 1.0
    m2 = tree.nodes.new("ShaderNodeMix"); m2.data_type = "RGBA"; m2.blend_type = "MULTIPLY"; m2.inputs["Factor"].default_value = 1.0
    m3 = tree.nodes.new("ShaderNodeMix"); m3.data_type = "RGBA"; m3.blend_type = "MULTIPLY"; m3.inputs["Factor"].default_value = 1.0
    L = tree.links.new
    L(coord.outputs["Object"], streak_map.inputs["Vector"]); L(streak_map.outputs["Vector"], streaks.inputs["Vector"])
    L(streaks.outputs["Fac"], s_ramp.inputs["Fac"])
    L(coord.outputs["Object"], sep.inputs["Vector"]); L(sep.outputs["Z"], ground.inputs["Value"])
    L(coord.outputs["Object"], patch.inputs["Vector"]); L(patch.outputs["Distance"], p_ramp.inputs["Fac"])
    L(base, m1.inputs["A"]); L(s_ramp.outputs["Color"], m1.inputs["B"])
    L(m1.outputs["Result"], m2.inputs["A"]); L(ground.outputs["Result"], m2.inputs["B"])
    L(m2.outputs["Result"], m3.inputs["A"]); L(p_ramp.outputs["Color"], m3.inputs["B"])
    L(m3.outputs["Result"], bsdf.inputs["Base Color"])
    return mat


def arch_cut(w: bpy.types.Object, wall: tuple, s: float, sill: float, ww: float, hh: float) -> None:
    """An arched hole: square up to the springing line, a half round over it."""
    (cx, cy), (ax, ay), (nx, ny), _ = wall
    px, py = cx + ax * s, cy + ay * s
    half = (abs(ax) * ww / 2 + abs(nx) * 1.0, abs(ay) * ww / 2 + abs(ny) * 1.0)
    spring = sill + hh - ww / 2
    cuts = [box("cut", (px - half[0], py - half[1], sill), (px + half[0], py + half[1], spring))]
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=ww / 2, radius2=ww / 2, depth=2.0)
    me = bpy.data.meshes.new("arc")
    bm.to_mesh(me)
    bm.free()
    arc = bpy.data.objects.new("arc", me)
    bpy.context.scene.collection.objects.link(arc)
    arc.location = (px, py, spring)
    arc.rotation_euler = (math.pi / 2, 0, math.atan2(ny, nx) + math.pi / 2)
    cuts.append(arc)
    for cut in cuts:
        mod = w.modifiers.new("arch", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cut
        bpy.context.view_layer.objects.active = w
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cut, do_unlink=True)


def arch_fill(wall: tuple, s: float, sill: float, ww: float, hh: float, mat: bpy.types.Material, depth: float) -> None:
    """What sits in an arched hole, `depth` back from the wall face: a door leaf or a pane, arch-topped."""
    (cx, cy), (ax, ay), (nx, ny), _ = wall
    spring = sill + hh - ww / 2
    pts = [(-ww / 2, sill), (ww / 2, sill), (ww / 2, spring)]
    pts += [(ww / 2 * math.cos(math.pi * k / 12), spring + ww / 2 * math.sin(math.pi * k / 12)) for k in range(1, 12)]
    pts += [(-ww / 2, spring)]
    bm = bmesh.new()
    vs = [bm.verts.new((cx + ax * (s + u) - nx * depth, cy + ay * (s + u) - ny * depth, z)) for u, z in pts]
    face = bm.faces.new(vs)
    bmesh.ops.extrude_face_region(bm, geom=[face])
    me = bpy.data.meshes.new("fill")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("fill", me)
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    solid = ob.modifiers.new("t", "SOLIDIFY")
    solid.thickness = 0.04


def awning(ox: float, tiles: bpy.types.Material, wood: bpy.types.Material, at: float = 3.5) -> None:
    """A little tiled shed roof over the front door on two wooden brackets (Spanish)."""
    w, out, top, drop = 1.9, 0.75, 2.85, 0.32
    x0, x1 = ox + at - w / 2, ox + at + w / 2
    bm = bmesh.new()
    rows = 4
    for k in range(rows):
        t0, t1 = k / rows, (k + 1) / rows
        y0, y1 = -out * (1 - t0), -out * (1 - t1)
        z0, z1 = top - drop * (1 - t0), top - drop * (1 - t1)
        quad = [(x0, y0, z0 + 0.03), (x1, y0, z0 + 0.03), (x1, y1, z1), (x0, y1, z1)]
        bm.faces.new([bm.verts.new(p) for p in quad])
        bm.faces.new([bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y0, z0 + 0.03), (x0, y0, z0 + 0.03))])
    me = bpy.data.meshes.new("awning")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("awning", me)
    ob.data.materials.append(tiles)
    bpy.context.scene.collection.objects.link(ob)
    ob.modifiers.new("t", "SOLIDIFY").thickness = 0.05
    for x in (x0 + 0.12, x1 - 0.12):
        box("bracket", (x - 0.05, -out + 0.05, top - drop - 0.08), (x + 0.05, 0.0, top - drop + 0.02), wood)
        box("brace", (x - 0.04, -0.12, top - drop - 0.5), (x + 0.04, 0.0, top - drop - 0.08), wood)


def bars(wall: tuple, s: float, sill: float, ww: float, hh: float, mat: bpy.types.Material) -> None:
    """Iron bars over a window, a hand in front of the wall."""
    (cx, cy), (ax, ay), (nx, ny), _ = wall
    off = 0.07
    def at(u: float, z: float) -> tuple:
        return (cx + ax * (s + u) + nx * off, cy + ay * (s + u) + ny * off, z)
    n = max(3, int(ww / 0.13))
    for k in range(n + 1):
        u = -ww / 2 - 0.05 + (ww + 0.1) * k / n
        a, b = at(u, sill - 0.05), at(u, sill + hh + 0.05)
        box("bar", (min(a[0], b[0]) - 0.012, min(a[1], b[1]) - 0.012, a[2]), (max(a[0], b[0]) + 0.012, max(a[1], b[1]) + 0.012, b[2]), mat)
    for z in (sill + 0.02, sill + hh - 0.02):
        a, b = at(-ww / 2 - 0.06, z), at(ww / 2 + 0.06, z)
        box("band", (min(a[0], b[0]) - 0.015, min(a[1], b[1]) - 0.015, z - 0.02), (max(a[0], b[0]) + 0.015, max(a[1], b[1]) + 0.015, z + 0.02), mat)


def dress(kit: Kit, ox: float, mid: bool = False, style: dict | None = None) -> None:
    """Every kit part where the game puts it."""
    ws = walls(ox)
    style = style or {}
    tints = style.get("tints")
    openings = SPANISH_OPENINGS if style.get("spanish") else OPENINGS
    for name, wall in ws.items():
        length = wall[3]
        for part, s, sill in openings[name]:
            if part.startswith("arch_"):
                continue   # built by street(): arched holes are not kit parts
            kit.place(part, wall, s, sill, tints=tints)
        if not style.get("spanish"):   # smooth stucco corners and no base board on a Spanish house
            kit.place("kit_trim_base", wall, length / 2, 0.0, sx=length, tints=tints)
            kit.place("kit_trim_corner", wall, 0.0, 0.0, sy=H, tints=tints)
        if name in ("front", "back"):   # the eaves run along the long sides
            kit.place("kit_eave_board", wall, length / 2, H, out=OVERHANG, sx=length + 2 * OVERHANG, tints=tints)
            for k in range(int(length / 0.6) + 1):
                kit.place("kit_rafter", wall, 0.05 + k * 0.6, H, tints=tints)
            if not mid:   # K6, LA: it hardly rains; most houses have no gutters or downspouts
                kit.place("kit_gutter", wall, length / 2, H, out=OVERHANG, sx=length + 2 * OVERHANG)
                kit.place("kit_downspout", wall, 0.3, 0.0, out=OVERHANG - 0.06, sy=H)
                kit.place("kit_downspout", wall, length - 0.3, 0.0, out=OVERHANG - 0.06, sy=H)
    if not style.get("spanish"):
        kit.place("kit_porch", ws["front"], 3.5, 0.0, tints=tints)
    kit.place("kit_meter", ws["front"], 5.2, 0.0, tints=tints)
    kit.place("kit_ac_unit", ws["back"], 4.1, 0.0, tints=tints)
    if not mid:   # the mid house gets a stucco chimney instead (stucco_chimney)
        chimney_top = H + 2.2
        kit.place("kit_chimney", ws["left"], 6.4, 0.0, out=0.3, sy=chimney_top)
        kit.place("kit_chimney_cap", ws["left"], 6.4, chimney_top, out=0.3)


def street_house(kit: Kit, ox: float, style: dict, stucco_png: str, mats: dict) -> None:
    """K6: one house of the street in its style."""
    stucco = stucco_style(stucco_png, style["stucco"], style.get("worn", False))
    tile = style["roof"] == "tile"
    shell(ox, stucco, SPANISH_OPENINGS if style.get("spanish") else OPENINGS)
    pitch = math.radians(14) if style.get("spanish") else PITCH
    roof_mid(ox, mats["tiles"] if tile else mats["shingle"], mats["caps"] if tile else mats["shingle_caps"], pitch,
        COURSE_M if tile else 0.22, round_caps=tile)
    plinth(ox, mats["plinth"])
    if not style.get("spanish"):
        stucco_chimney(ox, stucco, mats["plinth"])
    ws = walls(ox)
    if style.get("spanish"):
        wall = ws["front"]
        for part, s, sill in SPANISH_OPENINGS["front"]:
            if part.startswith("arch_"):
                ww, hh = ARCH_SIZES[part]
                arch_fill(wall, s, sill, ww, hh, mats["wood"] if part == "arch_door" else mats["glass"], 0.14 if part == "arch_door" else 0.1)
        awning(ox, mats["tiles"], mats["wood"])
    if style.get("bars"):
        for name in ("front", "left"):
            for part, s, sill in OPENINGS[name]:
                if part.startswith("kit_window"):
                    ww, hh = SIZES[part]
                    bars(ws[name], s, sill, ww, hh, mats["iron"])
    dress(kit, ox, True, style)


def stage(n: int) -> None:
    ground = box("ground", (-8, -12, -0.1), (n * (W + GAP) + 2, D + 8, 0.0), plain("grass", (0.36, 0.42, 0.24), noise=0.25))
    ground.data.materials.append(plain("grass", (0.36, 0.42, 0.24)))
    for i in range(n):   # a driveway to each garage
        ox = i * (W + GAP)
        box("drive", (ox + W, 2.2, -0.08), (ox + W + 5, 5.0, 0.01), plain("concrete", (0.66, 0.65, 0.62), noise=0.15))
        box("path", (ox + 3.0, -3.5, -0.08), (ox + 4.0, -2.0, 0.01), plain("concrete", (0.66, 0.65, 0.62), noise=0.15))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(-125))   # the game's afternoon sun from the south-west
    sun.data.energy = 3.2
    sun.data.angle = math.radians(1.5)
    bpy.context.scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.7, 0.8, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    bpy.context.scene.world = world


def camera(n: int, out: str, close: bool) -> None:
    """Ortho, 30 degrees down and 45 round, like the game; the whole street or one front door."""
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    span = n * W + (n - 1) * GAP
    if close:
        target, cam.data.ortho_scale = (3.5, 0.0, 1.4), 7.0
        scene.render.resolution_x, scene.render.resolution_y = 900 * n, 900
    else:
        target, cam.data.ortho_scale = (span / 2, D / 2, 1.5), span * 1.0
        scene.render.resolution_x, scene.render.resolution_y = 1800, 950
    yaw, pitch = math.radians(-35), math.radians(30)
    dist = 60.0
    cam.location = (target[0] + dist * math.sin(yaw) * math.cos(pitch), target[1] - dist * math.cos(yaw) * math.cos(pitch), target[2] + dist * math.sin(pitch))
    look = bpy.data.objects.new("target", None)
    look.location = target
    scene.collection.objects.link(look)
    track = cam.constraints.new("TRACK_TO")
    track.target = look
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.render.filepath = out
    if close and n > 1:   # one door per house: render each and put them side by side
        frames = []
        for i in range(n):
            look.location = (i * (W + GAP) + 3.5, 0.0, 1.4)
            cam.location = (look.location[0] + dist * math.sin(yaw) * math.cos(pitch), look.location[1] - dist * math.cos(yaw) * math.cos(pitch), 1.4 + dist * math.sin(pitch))
            scene.render.resolution_x = 900
            scene.render.filepath = out.replace(".png", f"_{i}.png")
            bpy.ops.render.render(write_still=True)
            frames.append(scene.render.filepath)
        print("CLOSE", " ".join(frames))
    else:
        bpy.ops.render.render(write_still=True)


def houses(n: int, out: str) -> None:
    """One render per house, framed whole from the game's angle: <out>_<i>.png."""
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 17.0
    look = bpy.data.objects.new("target", None)
    scene.collection.objects.link(look)
    track = cam.constraints.new("TRACK_TO")
    track.target = look
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.render.resolution_x, scene.render.resolution_y = 1000, 760
    yaw, pitch, dist = math.radians(-35), math.radians(30), 60.0
    for i in range(n):
        look.location = (i * (W + GAP) + W / 2, D / 2 - 1.0, 1.6)
        cam.location = (look.location[0] + dist * math.sin(yaw) * math.cos(pitch), look.location[1] - dist * math.cos(yaw) * math.cos(pitch), 1.6 + dist * math.sin(pitch))
        scene.render.filepath = out.replace(".png", f"_{i}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    args = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")] if "--" in sys.argv else sys.argv[1:]
    close = "--close" in sys.argv
    out, atlas, folders = args[0], args[1], args[2:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sheet = bpy.data.images.load(os.path.abspath(atlas))
    sheet.alpha_mode = "CHANNEL_PACKED"
    stucco = plain("stucco", (0.8, 0.68, 0.52), noise=0.08)
    tiles = plain("tiles", (0.62, 0.3, 0.2), noise=0.18)
    stucco_mid = stucco_tex(os.path.join(os.path.dirname(os.path.abspath(atlas)), "stucco.png"), (0.8, 0.68, 0.52))
    plinth_mat = plain("plinth", (0.6, 0.5, 0.4), noise=0.1)
    caps = plain("caps", (0.55, 0.25, 0.16), rough=0.6, noise=0.12)
    if folders and folders[0].endswith(":street"):   # K6: four houses, each rendered on its own
        png = os.path.join(os.path.dirname(os.path.abspath(atlas)), "stucco.png")
        mats = {"tiles": tiles, "caps": caps, "plinth": plinth_mat,
            "shingle": plain("shingle", (0.34, 0.33, 0.32), noise=0.2), "shingle_caps": plain("shingle_caps", (0.28, 0.27, 0.26), noise=0.15),
            "wood": plain("wood", (0.3, 0.17, 0.1), noise=0.2), "glass": plain("glass", (0.18, 0.24, 0.3), rough=0.15),
            "iron": plain("iron", (0.06, 0.06, 0.06), rough=0.5)}
        kit_parts = Kit(folders[0].rsplit(":", 1)[0], sheet)
        for i, style in enumerate(STYLES):
            street_house(kit_parts, i * (W + GAP), style, png, mats)
        stage(len(STYLES))
        houses(len(STYLES), os.path.abspath(out))
        return
    for i, entry in enumerate(folders):
        folder, _, how = entry.partition(":")
        mid = how == "mid"
        ox = i * (W + GAP)
        shell(ox, stucco_mid if mid else stucco)
        if mid:
            roof_mid(ox, tiles, caps)
            plinth(ox, plinth_mat)
            stucco_chimney(ox, stucco_mid, plinth_mat)
        else:
            roof(ox, tiles)
        dress(Kit(folder, sheet), ox, mid)
    stage(len(folders))
    camera(len(folders), os.path.abspath(out), close)
    print("rendered", out)


if __name__ == "__main__":
    main()
