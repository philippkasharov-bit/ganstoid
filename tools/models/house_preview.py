"""K5: assemble sample houses from the kit in Blender and render them as the game's camera sees them.

    /tmp/bpyenv/bin/python tools/models/house_preview.py <out.png> <atlas.png> <kit_dir> [<kit_dir> ...] [--close]

One house per kit folder (the .obj parts house_kit.py writes), side by side, left to right:
stucco walls with real holes, a tiled hip roof, windows, the front door under a porch,
a garage door, corner and base trims, eave boards, gutters, downspouts, rafter tails,
a chimney, an AC unit and a meter, each placed the way HouseKit3D places it (origin at
the bottom-centre of the hole on the wall's outer face; trims and pipes stretched).
--close frames the front door and porch instead of the whole street.
"""
from __future__ import annotations

import math
import os
import sys

import bpy
import bmesh

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

    def place(self, name: str, wall: tuple, s: float, y: float, out: float = 0.0, sx: float = 1.0, sy: float = 1.0) -> None:
        (cx, cy), (ax, ay), (nx, ny), _ = wall
        src = self.parts[name]
        ob = src.copy()
        ob.hide_render = False
        ob.hide_viewport = False
        bpy.context.scene.collection.objects.link(ob)
        ob.location = (cx + ax * s + nx * out, cy + ay * s + ny * out, y)
        ob.rotation_euler = (0, 0, math.atan2(ny, nx) + math.pi / 2)   # parts face -Y in Blender
        ob.scale = (sx, 1.0, sy)


_mats: dict[str, bpy.types.Material] = {}


def textured(slot: str, sheet: bpy.types.Image) -> bpy.types.Material:
    """The kit's baked sheet; painted cells take this house's tint (alpha = paint mask), as kit_preview does."""
    if slot in _mats:
        return _mats[slot]
    if os.environ.get("PLAIN"):   # debugging: flat colours, no sheet
        _mats[slot] = plain("p_" + slot, TINTS.get(slot, (0.6, 0.6, 0.6)))
        return _mats[slot]
    mat = bpy.data.materials.new("k_" + slot)
    mat.use_nodes = True
    tree = mat.node_tree
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = sheet
    mix = tree.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["B"].default_value = (*TINTS.get(slot, (1.0, 1.0, 1.0)), 1.0)
    tree.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
    tree.links.new(tex.outputs["Color"], mix.inputs["A"])
    bsdf = tree.nodes["Principled BSDF"]
    tree.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.25 if slot == "glass" else 0.7
    _mats[slot] = mat
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


def shell(ox: float, stucco: bpy.types.Material) -> None:
    """Four walls with the openings cut through them."""
    for name, wall in walls(ox).items():
        (cx, cy), (ax, ay), (nx, ny), length = wall
        trim = WALL_T if name in ("right", "left") else 0.0   # side walls stop at the front and back walls' backs (no overlap)
        a = (cx + ax * trim, cy + ay * trim)
        b = (cx + ax * (length - trim), cy + ay * (length - trim))
        inner = (cx - nx * WALL_T, cy - ny * WALL_T)
        lo = (min(a[0], b[0], inner[0]), min(a[1], b[1], inner[1]), 0.0)
        hi = (max(a[0], b[0], inner[0]), max(a[1], b[1], inner[1]), H)
        w = box("wall_" + name, lo, hi, stucco)
        for part, s, sill in OPENINGS[name]:
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


def dress(kit: Kit, ox: float) -> None:
    """Every kit part where the game puts it."""
    ws = walls(ox)
    for name, wall in ws.items():
        length = wall[3]
        for part, s, sill in OPENINGS[name]:
            kit.place(part, wall, s, sill)
        kit.place("kit_trim_base", wall, length / 2, 0.0, sx=length)
        kit.place("kit_trim_corner", wall, 0.0, 0.0, sy=H)
        if name in ("front", "back"):   # the eaves run along the long sides
            kit.place("kit_eave_board", wall, length / 2, H, out=OVERHANG, sx=length + 2 * OVERHANG)
            kit.place("kit_gutter", wall, length / 2, H, out=OVERHANG, sx=length + 2 * OVERHANG)
            for k in range(int(length / 0.6) + 1):
                kit.place("kit_rafter", wall, 0.05 + k * 0.6, H)
            kit.place("kit_downspout", wall, 0.3, 0.0, out=OVERHANG - 0.06, sy=H)
            kit.place("kit_downspout", wall, length - 0.3, 0.0, out=OVERHANG - 0.06, sy=H)
    kit.place("kit_porch", ws["front"], 3.5, 0.0)
    kit.place("kit_meter", ws["front"], 5.2, 0.0)
    kit.place("kit_ac_unit", ws["back"], 4.1, 0.0)
    chimney_top = H + 2.2
    kit.place("kit_chimney", ws["left"], 6.4, 0.0, out=0.3, sy=chimney_top)
    kit.place("kit_chimney_cap", ws["left"], 6.4, chimney_top, out=0.3)


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


def main() -> None:
    args = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")] if "--" in sys.argv else sys.argv[1:]
    close = "--close" in sys.argv
    out, atlas, folders = args[0], args[1], args[2:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sheet = bpy.data.images.load(os.path.abspath(atlas))
    sheet.alpha_mode = "CHANNEL_PACKED"
    stucco = plain("stucco", (0.8, 0.68, 0.52), noise=0.08)
    tiles = plain("tiles", (0.62, 0.3, 0.2), noise=0.18)
    for i, folder in enumerate(folders):
        ox = i * (W + GAP)
        shell(ox, stucco)
        roof(ox, tiles)
        dress(Kit(folder, sheet), ox)
    stage(len(folders))
    camera(len(folders), os.path.abspath(out), close)
    print("rendered", out)


if __name__ == "__main__":
    main()
