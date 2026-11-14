"""M2: render a .glb from the game's angle (Cycles, CPU) to check it before Godot.

    python3 tools/models/glb_preview.py <in.glb> <out.png> [frame]
"""
from __future__ import annotations

import math
import sys

import bpy


def main(src: str, out: str, frame: int) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    scene = bpy.context.scene
    scene.frame_set(frame)
    bpy.ops.mesh.primitive_plane_add(size=30)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(45), 0, math.radians(-35))
    sun.data.energy = 3.0
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.color = (0.5, 0.52, 0.55)
    scene.world = world
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 6.0
    cam.location = (9, -9, 7.4)
    cam.rotation_euler = (math.radians(60), 0, math.radians(45))
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.render.resolution_x, scene.render.resolution_y = 1000, 700
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    main(args[0], args[1], int(args[2]) if len(args) > 2 else 1)
