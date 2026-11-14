"""M2: player_character.glb, a 1.8 m 90s LA look: oversized hoodie, baggy
pants, white sneakers, a cap. Rigid-skinned to a simple armature (each part
on one bone), with two baked actions: Idle (breathing, 2 s) and Walk (arm
and leg swing, 1 s). Faces Blender +X (the game's heading 0).

    python3 tools/models/glb_character.py assets/models/player_character.glb
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import glb_lib as lib  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

FPS = 24
# bone: (head, tail, parent)
BONES = {
    "hips": ((0, 0, 0.95), (0, 0, 1.05), None),
    "spine": ((0, 0, 1.0), (0, 0, 1.45), "hips"),
    "head": ((0, 0, 1.45), (0, 0, 1.78), "spine"),
    "thigh.L": ((0, 0.11, 0.95), (0, 0.11, 0.52), "hips"), "shin.L": ((0, 0.11, 0.52), (0, 0.11, 0.08), "thigh.L"),
    "thigh.R": ((0, -0.11, 0.95), (0, -0.11, 0.52), "hips"), "shin.R": ((0, -0.11, 0.52), (0, -0.11, 0.08), "thigh.R"),
    "arm.L": ((0, 0.27, 1.4), (0, 0.29, 1.1), "spine"), "forearm.L": ((0, 0.29, 1.1), (0, 0.3, 0.82), "arm.L"),
    "arm.R": ((0, -0.27, 1.4), (0, -0.29, 1.1), "spine"), "forearm.R": ((0, -0.29, 1.1), (0, -0.3, 0.82), "arm.R"),
}


def parts() -> list[tuple[lib.Builder, str]]:
    """(part, bone) pairs: every part follows exactly one bone."""
    out = []
    def add(name, bone, boxes):
        b = lib.Builder(name)
        for lo, hi, mat in boxes:
            b.box(lo, hi, mat)
        out.append((b, bone))
    add("hoodie", "spine", [((-0.15, -0.25, 0.9), (0.15, 0.25, 1.42), "Hoodie"), ((-0.17, -0.27, 1.28), (0.13, 0.27, 1.44), "Hoodie"),
        ((-0.19, -0.13, 1.33), (-0.06, 0.13, 1.56), "Hoodie"), ((0.15, -0.12, 1.02), (0.17, 0.12, 1.16), "Hoodie")])   # body, shoulders, hood, pocket
    add("head", "head", [((-0.1, -0.09, 1.47), (0.11, 0.09, 1.72), "Skin"), ((-0.11, -0.1, 1.68), (0.1, 0.1, 1.79), "Cap"),
        ((0.06, -0.09, 1.68), (0.22, 0.09, 1.71), "Cap"), ((0.11, -0.015, 1.57), (0.135, 0.015, 1.62), "Skin")])   # face, cap, brim, nose
    for s, side in (("L", 1), ("R", -1)):
        y = side * 0.11
        add("thigh." + s, "thigh." + s, [((-0.1, y - 0.1, 0.5), (0.1, y + 0.1, 0.97), "Pants")])
        add("shin." + s, "shin." + s, [((-0.1, y - 0.1, 0.1), (0.1, y + 0.1, 0.53), "Pants"),
            ((-0.09, y - 0.07, 0.03), (0.2, y + 0.07, 0.12), "Sneaker"), ((-0.1, y - 0.075, 0.0), (0.21, y + 0.075, 0.035), "Sole")])
        ya = side * 0.29
        add("arm." + s, "arm." + s, [((-0.08, ya - 0.08, 1.08), (0.08, ya + 0.08, 1.42), "Hoodie")])
        add("forearm." + s, "forearm." + s, [((-0.075, ya - 0.075, 0.86), (0.075, ya + 0.075, 1.11), "Hoodie"),
            ((-0.045, ya - 0.04, 0.74), (0.05, ya + 0.04, 0.87), "Skin")])
    return out


def armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new("rig")
    ob = bpy.data.objects.new("player_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in BONES.items():
        bone = arm.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def skin(rig: bpy.types.Object) -> bpy.types.Object:
    """Every part joined into one mesh, each weighted fully to its bone."""
    objs = []
    for builder, bone in parts():
        ob = builder.finish(bevel=0.015)
        bpy.context.view_layer.objects.active = ob
        for mod in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        group = ob.vertex_groups.new(name=bone)
        group.add(range(len(ob.data.vertices)), 1.0, "REPLACE")
        objs.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "player_body"
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return body


def _turn(rig: bpy.types.Object, bone: str, world_axis: Vector, angle: float) -> Quaternion:
    """A pose rotation of `angle` round a world axis, in the bone's own space."""
    local = rig.data.bones[bone].matrix_local.to_3x3().inverted() @ world_axis
    return Quaternion(local.normalized(), angle)


def action(rig: bpy.types.Object, name: str, seconds: float, pose) -> None:
    """Bakes `pose(t)` -> {bone: angle round the left-right axis, '_rise': hips lift} over a loop."""
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    frames = int(seconds * FPS)
    side = Vector((0, 1, 0))
    for f in range(frames + 1):
        t = f / frames
        angles = pose(t)
        for bone in BONES:
            pb = rig.pose.bones[bone]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = _turn(rig, bone, side, angles.get(bone, 0.0))
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)
        hips = rig.pose.bones["hips"]
        hips.location = (0, angles.get("_rise", 0.0), 0)   # along the bone: up
        hips.keyframe_insert("location", frame=f + 1)
    act.use_fake_user = True
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    rig.animation_data.action = None


def walk(t: float) -> dict:
    s = math.sin(t * 2 * math.pi)
    knee = lambda k: max(0.0, -math.sin(t * 2 * math.pi + k)) * 0.7  # noqa: E731
    return {"thigh.L": 0.45 * s, "thigh.R": -0.45 * s, "shin.L": -knee(0.0), "shin.R": -knee(math.pi),
        "arm.L": -0.38 * s, "arm.R": 0.38 * s, "forearm.L": -0.25, "forearm.R": -0.25,
        "spine": 0.05, "_rise": 0.03 * abs(math.cos(t * 2 * math.pi))}


def idle(t: float) -> dict:
    b = math.sin(t * 2 * math.pi)
    return {"spine": 0.02 * b, "head": -0.015 * b, "arm.L": 0.03 * b, "arm.R": 0.03 * b,
        "forearm.L": -0.08, "forearm.R": -0.08, "_rise": 0.006 * b}


def build(path: str) -> None:
    lib.reset()
    bpy.context.scene.render.fps = FPS
    rig = armature()
    body = skin(rig)
    action(rig, "Idle", 2.0, idle)
    action(rig, "Walk", 1.0, walk)
    lib.export([rig, body], path)
    print("player_character:", lib.triangles(body), "triangles ->", path)


if __name__ == "__main__":
    build(sys.argv[-1])
