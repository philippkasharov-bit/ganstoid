"""K2: render the house kit laid out in a row in front of a stucco wall
(Cycles, CPU), so the parts can be judged before they go into the game.

    python3 tools/models/kit_preview.py [art/textures/kit_atlas.png] <out.png>
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import house_kit  # noqa: E402
import kit_lib as kit  # noqa: E402

ROW = [("kit_window_sash", 0.9), ("kit_window_wide", 0.9), ("kit_window_small", 1.5), ("kit_door_front", 0.17),
    ("kit_door_garage", 0.0), ("kit_porch", 0.0), ("kit_ac_unit", 0.6), ("kit_meter", 0.0), ("kit_chimney_cap", 0.0)]
GAP = 0.9


def lay_out() -> float:
    parts = {p.name: p for p in house_kit.all_parts()}
    x = 0.0
    for name, y in ROW:
        ob = parts[name].finish()
        width = ob.dimensions.x
        ob.location = (x + width / 2, 0, y)
        x += width + GAP
    return x


def stage(length: float) -> None:
    wall = kit.Part("wall")
    wall.box(-1.0, length + 1.0, -0.4, 3.6, -0.6, -0.21, "brick")
    stucco = wall.finish()
    stucco.data.materials[kit.SLOTS.index("brick")] = _stucco()
    ground = kit.Part("ground")
    ground.box(-2.0, length + 2.0, -0.42, -0.4, -1.0, 4.0, "concrete")
    ground.finish()
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sun.data.energy = 3.5
    bpy.context.scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.color = (0.55, 0.57, 0.6)
    bpy.context.scene.world = world


def _stucco() -> bpy.types.Material:
    mat = bpy.data.materials.new("stucco")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.78, 0.66, 0.52, 1.0)
    return mat


def camera(length: float, out: str) -> None:
    """Ortho, 30 degrees down and 25 across, like the game's camera, framing the whole row."""
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = length * 1.04
    target = bpy.data.objects.new("target", None)
    target.location = (length / 2, 0, 1.3)
    bpy.context.scene.collection.objects.link(target)
    yaw, pitch = math.radians(25), math.radians(30)
    cam.location = (length / 2 + 30 * math.sin(yaw) * math.cos(pitch), -30 * math.cos(yaw) * math.cos(pitch), 1.3 + 30 * math.sin(pitch))
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.view_settings.view_transform = "Standard"
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.device = "CPU"
    scene.render.resolution_x, scene.render.resolution_y = 2000, 640
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)


TINTS = {"paint": (0.93, 0.9, 0.82), "door": (0.12, 0.28, 0.2), "garage": (0.95, 0.94, 0.9)}   # one house's colours, for the look


def textured(sheet: str) -> None:
    """K3: every slot material reads the baked sheet; painted cells take this house's tint (alpha = paint mask)."""
    image = bpy.data.images.load(sheet)
    image.alpha_mode = "CHANNEL_PACKED"   # alpha is the paint mask, not transparency
    for slot in kit.SLOTS:
        tree = kit.material(slot).node_tree
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        mix = tree.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["B"].default_value = (*TINTS.get(slot, (1.0, 1.0, 1.0)), 1.0)
        tree.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
        tree.links.new(tex.outputs["Color"], mix.inputs["A"])
        tree.links.new(mix.outputs["Result"], tree.nodes["Principled BSDF"].inputs["Base Color"])


if __name__ == "__main__":
    kit.reset()
    span = lay_out()
    if len(sys.argv) > 2 and sys.argv[-2].endswith(".png"):
        textured(os.path.abspath(sys.argv[-2]))
    stage(span)
    camera(span, sys.argv[-1])
