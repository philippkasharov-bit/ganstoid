"""M3: the Meshy player (Magnific, rigged by Meshy) made game-ready in Blender.

Takes the Meshy clips (each export carries one action on the same skeleton),
puts them all on one armature as actions with the given names,
turns the figure to face +X (the game's heading 0), keeps real scale and the
feet at Z = 0, and exports player_character.glb.

    python3 tools/models/meshy_player.py assets/models/player_character.glb Idle=<idle.glb> Walk=<walk.glb> Punch=<punch.glb>

PL2: `Name=<file.glb>#<Action>` takes one named action from a file holding several
(e.g. the old player's Idle and Punch onto a new Meshy rig: same 24-bone skeleton).
`--in-place Walk` turns a clip that walks off (Meshy text-to-motion does) into one
that walks on the spot, keeping the bob, and cuts it to the best seamless loop.
"""
from __future__ import annotations

import math
import sys

import bpy


def clip(path: str) -> bpy.types.Action:
    """Imports a Meshy export; returns its action (the mesh and rig come from the first one).
    `file.glb#Name` picks the action called Name among those the file brought."""
    path, _, want = path.partition("#")
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    act = rig.animation_data.action
    if want:
        fresh = [a for a in bpy.data.actions if a not in acts_before]
        act = next((a for a in fresh if a.name == want), None) or next(a for a in fresh if a.name.split(".")[0] == want)
    return act, rig, new


def in_place_loop(rig: bpy.types.Object, act: bpy.types.Action) -> None:
    """PL2: the clip walks on the spot (the hips' drift over the ground taken out,
    the bob kept) and is cut to the stretch whose first and last poses match best."""
    rig.animation_data.action = act
    scene = bpy.context.scene
    s, e = int(act.frame_range[0]), int(act.frame_range[1])
    hips = rig.pose.bones["Hips"]
    pos, pose = {}, {}
    for f in range(s, e + 1):
        scene.frame_set(f)
        pos[f] = (rig.matrix_world @ hips.head).copy()
        pose[f] = [b.matrix_basis.to_quaternion() for b in rig.pose.bones]
    best, loop = None, (s, e)
    for a in range(s, min(e, s + 30)):
        for b in range(a + 40, e + 1):
            d = sum(1.0 - abs(qa.dot(qb)) for qa, qb in zip(pose[a], pose[b])) - 0.0004 * (b - a)
            if best is None or d < best:
                best, loop = d, (a, b)
    a, b = loop
    to_bone = (rig.matrix_world.to_3x3() @ hips.bone.matrix_local.to_3x3()).inverted()
    for f in range(a, b + 1):
        scene.frame_set(f)
        drift = pos[a] + (pos[b] - pos[a]) * ((f - a) / (b - a)) - pos[a]
        drift.z = 0.0
        hips.location = hips.location - to_bone @ drift
        hips.keyframe_insert("location", frame=f)
    for fc in act.fcurves:   # keep a..b, starting at frame 0
        drop = [i for i, k in enumerate(fc.keyframe_points) if k.co.x < a - 0.01 or k.co.x > b + 0.01]
        for i in reversed(drop):   # by index, from the end: a removed point invalidates later references
            fc.keyframe_points.remove(fc.keyframe_points[i], fast=True)
        fc.update()
        for k in fc.keyframe_points:
            k.co.x -= a
            k.handle_left.x -= a
            k.handle_right.x -= a
    rig.animation_data.action = None
    print("in place: loop %d..%d of %d..%d, walked %.2f m" % (a, b, s, e, (pos[b] - pos[a]).length))


def main(out: str, clips: list[str], in_place: tuple[str, ...] = ()) -> None:
    """`clips`: Name=path pairs; the first one's mesh and rig are kept, the rest give only their action."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    acts = []
    rig, objs = None, []
    for pair in clips:
        name, path = pair.split("=", 1)
        act, this_rig, new = clip(path)
        if rig is None:
            rig, objs = this_rig, new
        else:
            for o in new:   # only its action is needed
                bpy.data.objects.remove(o, do_unlink=True)
        acts.append((act, name))
    for track in list(rig.animation_data.nla_tracks):   # PL2: the importer's own track; ours come below
        rig.animation_data.nla_tracks.remove(track)
    for act, name in acts:
        if name in in_place:
            in_place_loop(rig, act)
    for act, name in acts:
        act.name = name
        act.use_fake_user = True
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, int(act.frame_range[0]), act)
    rig.animation_data.action = None
    keep = {act for act, _ in acts}
    for extra in [x for x in bpy.data.actions if x not in keep]:   # PL2: leftovers of the imports
        bpy.data.actions.remove(extra)
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
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    still = tuple(args[args.index("--in-place") + 1].split(",")) if "--in-place" in args else ()
    if "--in-place" in args:
        i = args.index("--in-place")
        args = args[:i] + args[i + 2:]
    main(args[0], args[1:], still)
