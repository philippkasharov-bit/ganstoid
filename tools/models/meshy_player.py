"""M3: the Meshy player (Magnific, rigged by Meshy) made game-ready in Blender.

Takes the Idle and Walking clips (each Meshy export carries one action on the
same skeleton), puts both on one armature as actions named Idle and Walk,
turns the figure to face +X (the game's heading 0), keeps real scale and the
feet at Z = 0, and exports player_character.glb.

    python3 tools/models/meshy_player.py <idle.glb> <walk.glb> assets/models/player_character.glb
"""
from __future__ import annotations

import math
import sys

import bpy


def clip(path: str) -> bpy.types.Action:
    """Imports a Meshy export; returns its action (the mesh and rig come from the first one)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    act = rig.animation_data.action
    return act, rig, new


def main(idle_path: str, walk_path: str, out: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    idle, rig, objs = clip(idle_path)
    walk, _, extra = clip(walk_path)
    for o in extra:   # only its action is needed
        bpy.data.objects.remove(o, do_unlink=True)
    for act, name in ((idle, "Idle"), (walk, "Walk")):
        act.name = name
        act.use_fake_user = True
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, int(act.frame_range[0]), act)
    rig.animation_data.action = None
    root = next(o for o in objs if o.parent is None)
    _face_x(root)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        if o.name in bpy.data.objects:
            o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=False,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_yup=True)
    print("player:", out)


def _face_x(root: bpy.types.Object) -> None:
    """Meshy figures face -Y in Blender (glTF +Z); the game wants +X."""
    root.rotation_mode = "XYZ"
    root.rotation_euler.z += math.radians(90)


if __name__ == "__main__":
    main(*sys.argv[-3:])
