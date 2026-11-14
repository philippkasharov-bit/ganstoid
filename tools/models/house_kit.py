"""K2: the house kit, built in Blender (bpy, headless). See the project doc
claude/ganstoid-house-kit-spec.md for sizes and the placement rules.

Openings have their origin at the bottom-centre of the hole on the wall's
outer plane; trims and pipes are one metre long (the game stretches them).

    python3 tools/models/house_kit.py art/models/kit
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_lib as kit  # noqa: E402

REVEAL = 0.2      # wall depth shown inside an opening
CASING = 0.08     # trim round an opening, on the wall face


def opening(p: kit.Part, w: float, h: float, casing: float = CASING) -> None:
    """The reveal lining inside the hole and the casing round it."""
    hw = w / 2
    p.box(-hw, -hw + 0.03, 0, h, -REVEAL, 0, "paint")
    p.box(hw - 0.03, hw, 0, h, -REVEAL, 0, "paint")
    p.box(-hw, hw, h - 0.03, h, -REVEAL, 0, "paint")
    p.box(-hw - casing, -hw, 0, h + casing, 0, 0.025, "paint")
    p.box(hw, hw + casing, 0, h + casing, 0, 0.025, "paint")
    p.box(-hw - casing - 0.03, hw + casing + 0.03, h, h + casing + 0.04, 0, 0.035, "paint")   # head trim


def sill(p: kit.Part, w: float) -> None:
    p.box(-w / 2 - 0.1, w / 2 + 0.1, -0.05, 0.0, -0.06, 0.07, "paint")
    p.box(-w / 2, w / 2, 0, 0.03, -REVEAL, 0, "paint")


def window(name: str, w: float, h: float, split: str, glass: str = "glass") -> kit.Part:
    """A window: lining, casing, sill, glass, and its sash bars ('sash', 'mullion' or 'none')."""
    p = kit.Part(name)
    opening(p, w, h)
    sill(p, w)
    p.quad([(-w / 2, 0.03, -0.13), (w / 2, 0.03, -0.13), (w / 2, h - 0.03, -0.13), (-w / 2, h - 0.03, -0.13)], glass)
    bar = 0.045
    p.box(-w / 2 + 0.03, -w / 2 + 0.03 + bar, 0.03, h - 0.03, -0.13, -0.09, "paint")   # stiles
    p.box(w / 2 - 0.03 - bar, w / 2 - 0.03, 0.03, h - 0.03, -0.13, -0.09, "paint")
    if split == "sash":
        p.box(-w / 2, w / 2, h / 2 - bar / 2, h / 2 + bar / 2, -0.13, -0.08, "paint")   # meeting rail
        p.box(-0.015, 0.015, 0.03, h - 0.03, -0.13, -0.1, "paint")                    # muntin
    elif split == "mullion":
        p.box(-bar, bar, 0.03, h - 0.03, -0.13, -0.08, "paint")
    return p


def door_front() -> kit.Part:
    p = kit.Part("kit_door_front")
    opening(p, 1.0, 2.1, 0.1)
    p.box(-0.47, 0.47, 0, 2.07, -0.17, -0.13, "door")
    for x0, y0, y1 in ((-0.38, 0.15, 0.95), (0.05, 0.15, 0.95), (-0.38, 1.1, 1.95), (0.05, 1.1, 1.95)):
        p.box(x0, x0 + 0.33, y0, y1, -0.13, -0.12, "door")   # raised panels
    p.box(0.33, 0.38, 1.0, 1.06, -0.12, -0.08, "metal")      # knob
    p.box(-0.75, 0.75, -0.17, 0.0, 0.0, 0.55, "concrete")   # the step
    p.box(0.72, 0.84, 1.7, 1.92, 0.0, 0.1, "metal")          # porch lamp
    p.box(0.74, 0.82, 1.74, 1.88, 0.1, 0.13, "glass")
    return p


def door_garage() -> kit.Part:
    p = kit.Part("kit_door_garage")
    opening(p, 2.6, 2.1, 0.1)
    for k in range(4):
        y0 = 0.02 + k * 0.52
        p.box(-1.27, 1.27, y0, y0 + 0.49, -0.12, -0.09, "garage")
    p.box(-1.4, 1.4, -0.02, 0.0, 0.0, 0.3, "concrete")
    return p


def trims() -> list[kit.Part]:
    base = kit.Part("kit_trim_base")
    base.box(-0.5, 0.5, 0, 0.35, 0, 0.03, "paint")
    base.box(-0.5, 0.5, 0.35, 0.38, 0, 0.015, "paint")
    corner = kit.Part("kit_trim_corner")
    corner.box(-0.07, 0.07, 0, 1, -0.07, 0.07, "paint")
    eave = kit.Part("kit_eave_board")
    eave.box(-0.5, 0.5, -0.22, 0, 0, 0.03, "paint")
    gutter = kit.Part("kit_gutter")
    gutter.box(-0.5, 0.5, -0.12, -0.1, 0.03, 0.15, "metal")   # bottom
    gutter.box(-0.5, 0.5, -0.12, 0, 0.13, 0.15, "metal")     # front lip
    gutter.box(-0.5, 0.5, -0.12, -0.02, 0.03, 0.05, "metal")  # back
    pipe = kit.Part("kit_downspout")
    pipe.box(-0.035, 0.035, 0.15, 1, 0.03, 0.1, "metal")
    pipe.box(-0.035, 0.035, 0.0, 0.15, 0.03, 0.3, "metal")   # the shoe kicks out at the foot
    rafter = kit.Part("kit_rafter")
    rafter.box(-0.04, 0.04, -0.14, 0, 0, 0.38, "rafter")
    rafter.slab((0, -0.0, 0.38), (0, -0.07, 0.46), 0.04, 0.07, "rafter")   # the cut tail
    return [base, corner, eave, gutter, pipe, rafter]


def porch() -> kit.Part:
    p = kit.Part("kit_porch")
    p.box(-1.2, 1.2, 0, 0.17, 0, 1.8, "concrete")
    for x in (-1.05, 1.05):
        p.box(x - 0.11, x + 0.11, 0.17, 0.4, 1.54, 1.76, "paint")   # post base
        p.box(x - 0.07, x + 0.07, 0.4, 2.5, 1.58, 1.72, "paint")
        p.box(x - 0.1, x + 0.1, 2.45, 2.55, 1.55, 1.75, "paint")   # cap
    p.box(-1.25, 1.25, 2.55, 2.72, 1.56, 1.74, "paint")            # beam
    p.slab((0, 3.0, 0.0), (0, 2.8, 2.0), 1.35, 0.09, "roof_tile")
    p.box(-1.35, 1.35, 2.62, 2.8, 1.98, 2.02, "paint")              # front fascia
    return p


def extras() -> list[kit.Part]:
    stack = kit.Part("kit_chimney")
    stack.box(-0.38, 0.38, 0, 1, -0.3, 0.3, "brick")
    cap = kit.Part("kit_chimney_cap")
    cap.box(-0.46, 0.46, 0, 0.1, -0.38, 0.38, "concrete")
    cap.tube(0.12, 0.0, 0.1, 0.45, 0.09, 8, "metal")
    ac = kit.Part("kit_ac_unit")
    ac.box(-0.33, 0.33, 0, 0.42, 0, 0.5, "ac")
    for k in range(5):
        ac.box(-0.28, 0.28, 0.06 + k * 0.065, 0.085 + k * 0.065, 0.5, 0.515, "metal")   # grille
    meter = kit.Part("kit_meter")
    meter.box(-0.15, 0.15, 1.15, 1.55, 0, 0.15, "metal")
    meter.tube(0.0, 0.16, 1.3, 1.42, 0.07, 8, "glass")
    meter.box(-0.025, 0.025, 0.2, 1.15, 0.03, 0.08, "metal")   # conduit down to the ground
    return [stack, cap, ac, meter]


def all_parts() -> list[kit.Part]:
    return [window("kit_window_sash", 1.0, 1.3, "sash"), window("kit_window_wide", 1.8, 1.3, "mullion"),
        window("kit_window_small", 0.6, 0.6, "none", "frosted"), door_front(), door_garage(), *trims(), porch(), *extras()]


def main(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for part in all_parts():
        kit.reset()
        ob = part.finish()
        print(f"{ob.name}: {kit.triangles(ob)} triangles -> {kit.export(ob, out_dir)}")


if __name__ == "__main__":
    main(sys.argv[-1] if len(sys.argv) > 1 else "art/models/kit")
