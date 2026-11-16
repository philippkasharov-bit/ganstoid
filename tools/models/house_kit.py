"""K2: the house kit, built in Blender (bpy, headless). See the project doc
claude/ganstoid-house-kit-spec.md for sizes and the placement rules.

Openings have their origin at the bottom-centre of the hole on the wall's
outer plane; trims and pipes are one metre long (the game stretches them).

K5 (mid-poly): same parts, names, sizes and origins, so the game places them
as before; now with real profiles: moulded casings and head crowns, sills
with a drip, sashes that sit at two depths with glazing bars, a six-panel
door with a knob and lantern, a sectional garage door with a window row,
a K-style gutter, chamfered posts and boards, a finned AC unit.

    python3 tools/models/house_kit.py art/models/kit
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_lib as kit  # noqa: E402

REVEAL = 0.2      # wall depth shown inside an opening
CASING = 0.08     # trim round an opening, on the wall face
SOFT = dict(bevel_m=0.004, segments=1, min_edge=0.04)   # small parts that repeat: one soft step
ROUND = dict(bevel_m=0.008, segments=2, min_edge=0.04)  # parts seen close (doors, porch): rounder


def casing_profile(c: float) -> list[tuple[float, float]]:
    """A backband casing across its width c (0 = outer edge, c = the hole), out of the wall."""
    return [(0.0, 0.0), (0.0, 0.026), (0.01, 0.036), (0.028, 0.036), (0.036, 0.028), (c, 0.02), (c, 0.0)]


def opening(p: kit.Part, w: float, h: float, casing: float = CASING) -> None:
    """The reveal lining inside the hole, the moulded casing round it and a crown over it."""
    hw = w / 2
    p.box(-hw, -hw + 0.03, 0, h, -REVEAL, 0, "paint")
    p.box(hw - 0.03, hw, 0, h, -REVEAL, 0, "paint")
    p.box(-hw, hw, h - 0.03, h, -REVEAL, 0, "paint")
    prof = casing_profile(casing)
    p.along_y([(-hw - casing + u, z) for u, z in prof], 0, h + casing, "paint")                # left jamb
    p.along_y([(hw + casing - u, z) for u, z in reversed(prof)], 0, h + casing, "paint")       # right jamb
    p.along_x([(h + casing - u, z) for u, z in reversed(prof)], -hw - casing, hw + casing, "paint")   # head
    top = h + casing
    crown = [(top, 0.0), (top, 0.038), (top + 0.018, 0.048), (top + 0.045, 0.062), (top + 0.07, 0.062), (top + 0.07, 0.0)]
    p.along_x(crown, -hw - casing - 0.035, hw + casing + 0.035, "paint")


def sill(p: kit.Part, w: float) -> None:
    """A sill sloping out to a front lip with a drip under it, and the stool inside."""
    prof = [(0.0, -0.06), (-0.012, 0.075), (-0.03, 0.088), (-0.05, 0.088), (-0.062, 0.072), (-0.062, -0.06)]
    p.along_x(prof, -w / 2 - 0.1, w / 2 + 0.1, "paint")
    p.box(-w / 2, w / 2, 0, 0.03, -REVEAL, 0, "paint")


def sash(p: kit.Part, x0: float, x1: float, y0: float, y1: float, z: float, bars: int = 0, rails: int = 0) -> None:
    """One sash: a frame 0.05 thick at depth z, glazing bars across (`bars` upright, `rails` level)."""
    t, d = 0.05, 0.045
    p.box(x0, x0 + t, y0, y1, z - d, z, "paint")
    p.box(x1 - t, x1, y0, y1, z - d, z, "paint")
    p.box(x0 + t, x1 - t, y0, y0 + t * 1.3, z - d, z, "paint")   # the bottom rail is a little deeper
    p.box(x0 + t, x1 - t, y1 - t, y1, z - d, z, "paint")
    for k in range(1, bars + 1):
        x = x0 + (x1 - x0) * k / (bars + 1)
        p.box(x - 0.011, x + 0.011, y0 + t, y1 - t, z - d + 0.01, z - 0.008, "paint")
    for k in range(1, rails + 1):
        y = y0 + (y1 - y0) * k / (rails + 1)
        p.box(x0 + t, x1 - t, y - 0.011, y + 0.011, z - d + 0.01, z - 0.008, "paint")


def window(name: str, w: float, h: float, split: str, glass: str = "glass") -> kit.Part:
    """A window: lining, casing, crown, sill, glass, and its sashes ('sash', 'mullion' or 'none').
    No bevel: a house has 10-15 of them and the profiles already catch the light (K6 budget)."""
    p = kit.Part(name, bevel=False)
    opening(p, w, h)
    sill(p, w)
    p.quad([(-w / 2, 0.03, -0.15), (w / 2, 0.03, -0.15), (w / 2, h - 0.03, -0.15), (-w / 2, h - 0.03, -0.15)], glass)
    x0, x1 = -w / 2 + 0.03, w / 2 - 0.03
    if split == "sash":   # double-hung: the upper sash sits in front, they overlap at the meeting rail
        sash(p, x0, x1, 0.03, h / 2 + 0.025, -0.11, bars=1)
        sash(p, x0, x1, h / 2 - 0.025, h - 0.03, -0.065, bars=1)
    elif split == "mullion":   # a slider: two sashes either side of a centre mullion
        p.box(-0.04, 0.04, 0.03, h - 0.03, -0.15, -0.07, "paint")
        sash(p, x0, -0.04, 0.03, h - 0.03, -0.11, rails=1)
        sash(p, 0.04, x1, 0.03, h - 0.03, -0.075, rails=1)
    else:
        sash(p, x0, x1, 0.03, h - 0.03, -0.09)
    return p


def arc(w: float, spring: float, n: int = 12) -> list[tuple[float, float]]:
    """K6: the half round over an arched opening, right spring point to left: (x, y)."""
    import math
    r = w / 2
    return [(r * math.cos(math.pi * k / n), spring + r * math.sin(math.pi * k / n)) for k in range(n + 1)]


def arched_opening(p: kit.Part, w: float, spring: float, depth: float = 0.28) -> None:
    """K6: a deep plaster reveal (Spanish stucco wraps into the hole): straight jambs, then the arch."""
    hw = w / 2
    p.box(-hw, -hw + 0.02, 0, spring, -depth, 0, "concrete")
    p.box(hw - 0.02, hw, 0, spring, -depth, 0, "concrete")
    pts = arc(w, spring)
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        p.quad([(ax, ay, -depth), (bx, by, -depth), (bx, by, 0.0), (ax, ay, 0.0)], "concrete")


def arch_shape(w: float, spring: float, inset: float = 0.0) -> list[tuple[float, float]]:
    """The outline of an arched opening (bottom left, bottom right, up and over), `inset` in from it."""
    return [(-w / 2 + inset, inset), (w / 2 - inset, inset)] + arc(w - 2 * inset, spring)


def window_arch() -> kit.Part:
    """K6, Spanish: an arched window in a deep plaster reveal, a wooden frame round it, a tile sill."""
    w, spring = 1.0, 1.0
    p = kit.Part("kit_window_arch", bevel=False)
    arched_opening(p, w, spring)
    z = -0.2
    p.quad([(x, y, z) for x, y in arch_shape(w, spring, 0.03)], "glass")
    pts = arc(w - 0.06, spring)
    inner = arc(w - 0.16, spring)
    for (ax, ay), (bx, by), (cx, cy), (dx, dy) in zip(pts, pts[1:], inner[1:], inner):   # the frame follows the arch
        p.quad([(ax, ay, z + 0.04), (bx, by, z + 0.04), (cx, cy, z + 0.04), (dx, dy, z + 0.04)], "paint")
    p.box(-w / 2 + 0.03, -w / 2 + 0.08, 0.03, spring, z, z + 0.04, "paint")
    p.box(w / 2 - 0.08, w / 2 - 0.03, 0.03, spring, z, z + 0.04, "paint")
    p.box(-w / 2 + 0.03, w / 2 - 0.03, 0.03, 0.09, z, z + 0.04, "paint")
    p.box(-0.02, 0.02, 0.09, spring + w / 2 - 0.08, z, z + 0.035, "paint")   # the cross bar
    p.box(-w / 2 + 0.08, w / 2 - 0.08, spring - 0.02, spring + 0.02, z, z + 0.035, "paint")
    p.along_x([(0.0, -0.28), (-0.02, 0.06), (-0.05, 0.075), (-0.07, 0.06), (-0.07, -0.28)], -w / 2 - 0.08, w / 2 + 0.08, "roof_tile")   # tile sill
    return p


def door_arch() -> kit.Part:
    """K6, Spanish: an arched plank door, iron strap hinges and a ring pull, in a deep reveal."""
    w, spring = 1.1, 1.85
    p = kit.Part("kit_door_arch", **SOFT)
    arched_opening(p, w, spring)
    leaf = arch_shape(w, spring, 0.02)
    front, back = -0.18, -0.23
    p.quad([(x, y, front) for x, y in leaf], "door")
    p.quad([(x, y, back) for x, y in reversed(leaf)], "door")
    for (ax, ay), (bx, by) in zip(leaf, leaf[1:] + leaf[:1]):
        p.quad([(ax, ay, back), (bx, by, back), (bx, by, front), (ax, ay, front)], "door")
    for x in (-0.33, -0.11, 0.11, 0.33):   # plank joints
        top = spring + ((w / 2 - 0.02) ** 2 - x * x) ** 0.5
        p.box(x - 0.006, x + 0.006, 0.05, top - 0.04, front, front + 0.006, "metal")
    for y in (0.35, 1.55):   # strap hinges
        p.box(-w / 2 + 0.04, -0.05, y, y + 0.06, front, front + 0.012, "metal")
        p.ball(-0.05, y + 0.03, front + 0.012, 0.025, "metal", rings=3, sides=8)
    p.tube(0.36, front + 0.03, 1.0, 1.02, 0.06, 10, "metal")      # ring pull
    p.box(0.33, 0.39, 1.06, 1.12, front, front + 0.02, "metal")
    p.along_x([(0.0, 0.0), (0.0, 0.45), (-0.02, 0.47), (-0.17, 0.47), (-0.17, 0.0)], -0.75, 0.75, "concrete")   # the step
    return p


def door_front() -> kit.Part:
    p = kit.Part("kit_door_front", **ROUND)
    opening(p, 1.0, 2.1, 0.1)
    p.box(-0.47, 0.47, 0, 2.07, -0.17, -0.13, "door")
    for (x0, x1) in ((-0.38, -0.05), (0.05, 0.38)):   # six raised panels
        for (y0, y1) in ((0.15, 0.72), (0.86, 1.42), (1.56, 1.95)):
            p.box(x0, x1, y0, y1, -0.13, -0.115, "door")
            p.box(x0 + 0.04, x1 - 0.04, y0 + 0.04, y1 - 0.04, -0.115, -0.105, "door")
    p.box(-0.45, 0.45, 0.02, 0.12, -0.13, -0.124, "metal")    # kick plate
    p.box(0.3, 0.36, 0.9, 1.1, -0.13, -0.12, "metal")         # escutcheon
    p.ball(0.33, 1.0, -0.085, 0.032, "metal")                 # knob
    p.box(0.315, 0.345, 1.16, 1.2, -0.13, -0.11, "metal")     # deadbolt
    step = [(0.0, 0.0), (0.0, 0.55), (-0.02, 0.57), (-0.17, 0.57), (-0.17, 0.0)]   # a nosed concrete step
    p.along_x(step, -0.75, 0.75, "concrete")
    p.box(0.7, 0.86, 1.62, 2.0, 0.0, 0.03, "metal")           # lantern: back plate,
    p.box(0.76, 0.8, 1.9, 1.94, 0.03, 0.12, "metal")          # arm,
    p.tube(0.78, 0.15, 1.66, 1.9, 0.06, 6, "glass")           # glass,
    p.tube(0.78, 0.15, 1.9, 1.94, 0.075, 6, "metal")          # roof
    p.tube(0.78, 0.15, 1.63, 1.66, 0.07, 6, "metal")          # and base
    return p


def door_garage() -> kit.Part:
    p = kit.Part("kit_door_garage", **SOFT)
    opening(p, 2.6, 2.1, 0.1)
    for k in range(4):
        y0 = 0.02 + k * 0.52
        p.box(-1.27, 1.27, y0, y0 + 0.49, -0.12, -0.09, "garage")
        p.box(-1.27, 1.27, y0 + 0.485, y0 + 0.5, -0.125, -0.12, "garage")   # the joint between sections
        if k == 3:   # the top section has a row of four little windows
            for j in range(4):
                cx = -0.96 + j * 0.64
                p.box(cx - 0.26, cx + 0.26, y0 + 0.1, y0 + 0.39, -0.09, -0.08, "garage")
                p.quad([(cx - 0.22, y0 + 0.14, -0.079), (cx + 0.22, y0 + 0.14, -0.079), (cx + 0.22, y0 + 0.35, -0.079), (cx - 0.22, y0 + 0.35, -0.079)], "glass")
        else:   # two long raised panels per section
            for cx in (-0.63, 0.63):
                p.box(cx - 0.56, cx + 0.56, y0 + 0.09, y0 + 0.4, -0.09, -0.078, "garage")
    p.box(-0.18, 0.18, 0.45, 0.49, -0.078, -0.05, "metal")   # handle
    p.box(-1.27, 1.27, 0.0, 0.02, -0.12, -0.08, "metal")      # rubber seal
    p.box(-1.4, 1.4, -0.02, 0.0, 0.0, 0.3, "concrete")
    return p


def trims() -> list[kit.Part]:
    base = kit.Part("kit_trim_base", **SOFT)
    base.along_x([(0.0, 0.0), (0.0, 0.032), (0.33, 0.032), (0.35, 0.02), (0.38, 0.018), (0.38, 0.0)], -0.5, 0.5, "paint")
    corner = kit.Part("kit_trim_corner", **SOFT)
    ch = 0.015
    corner.along_y([(-0.07 + ch, -0.07), (0.07 - ch, -0.07), (0.07, -0.07 + ch), (0.07, 0.07 - ch),
        (0.07 - ch, 0.07), (-0.07 + ch, 0.07), (-0.07, 0.07 - ch), (-0.07, -0.07 + ch)], 0, 1, "paint")
    eave = kit.Part("kit_eave_board", **SOFT)
    eave.along_x([(0.0, 0.0), (0.0, 0.03), (-0.19, 0.03), (-0.205, 0.042), (-0.22, 0.042), (-0.22, 0.0)], -0.5, 0.5, "paint")
    gutter = kit.Part("kit_gutter", **SOFT)   # K-style: flat back, ogee front, thin walls (open ends: the run is tiled)
    outer = [(0.0, 0.03), (-0.12, 0.03), (-0.12, 0.115), (-0.105, 0.14), (-0.07, 0.135), (-0.05, 0.155), (-0.02, 0.15), (0.0, 0.158)]
    inner = [(0.0, 0.15), (-0.02, 0.142), (-0.05, 0.147), (-0.07, 0.127), (-0.098, 0.132), (-0.112, 0.112), (-0.112, 0.038), (0.0, 0.038)]
    gutter.along_x(outer + inner, -0.5, 0.5, "metal", cap=False)
    pipe = kit.Part("kit_downspout", **SOFT)
    c = 0.012
    rect = [(-0.035 + c, 0.03), (0.035 - c, 0.03), (0.035, 0.03 + c), (0.035, 0.1 - c), (0.035 - c, 0.1), (-0.035 + c, 0.1), (-0.035, 0.1 - c), (-0.035, 0.03 + c)]
    pipe.along_y(rect, 0.15, 1, "metal")
    pipe.box(-0.045, 0.045, 0.6, 0.63, 0.0, 0.11, "metal")   # a strap to the wall
    pipe.along_x([(0.0, 0.03), (0.15, 0.03), (0.15, 0.1), (0.06, 0.3), (0.0, 0.3)], -0.035, 0.035, "metal")   # the shoe kicks out at the foot
    rafter = kit.Part("kit_rafter", **SOFT)
    tail = [(0.0, 0.0), (0.0, 0.38), (-0.02, 0.43), (-0.06, 0.46), (-0.1, 0.45), (-0.13, 0.41), (-0.14, 0.36), (-0.14, 0.0)]
    rafter.along_x(tail, -0.04, 0.04, "rafter")
    return [base, corner, eave, gutter, pipe, rafter]


def porch() -> kit.Part:
    p = kit.Part("kit_porch", **ROUND)
    p.along_x([(0.0, 0.0), (0.0, 1.8), (0.15, 1.8), (0.17, 1.78), (0.17, 0.0)], -1.2, 1.2, "concrete")   # slab, nosed edge
    p.along_x([(0.0, 1.8), (0.0, 2.15), (0.06, 2.15), (0.085, 2.13), (0.085, 1.8)], -0.6, 0.6, "concrete")  # a low step in front
    ch = 0.018
    for x in (-1.05, 1.05):
        p.box(x - 0.11, x + 0.11, 0.17, 0.4, 1.54, 1.76, "paint")     # post base
        p.box(x - 0.125, x + 0.125, 0.37, 0.4, 1.525, 1.775, "paint")  # its cap
        post = [(x - 0.07 + ch, 1.58), (x + 0.07 - ch, 1.58), (x + 0.07, 1.58 + ch), (x + 0.07, 1.72 - ch),
            (x + 0.07 - ch, 1.72), (x - 0.07 + ch, 1.72), (x - 0.07, 1.72 - ch), (x - 0.07, 1.58 + ch)]
        p.along_y(post, 0.4, 2.45, "paint")
        p.box(x - 0.1, x + 0.1, 2.45, 2.5, 1.55, 1.75, "paint")      # capital
        p.box(x - 0.12, x + 0.12, 2.5, 2.55, 1.53, 1.77, "paint")
    p.along_x([(2.55, 1.56), (2.55, 1.74), (2.62, 1.76), (2.72, 1.76), (2.72, 1.56)], -1.25, 1.25, "paint")   # beam, moulded front
    p.box(-1.3, 1.3, 2.72, 2.8, 0.0, 1.98, "rafter")   # the roof's frame; K6: the game lays the roof on it in the house's own roof
    return p


def extras() -> list[kit.Part]:
    stack = kit.Part("kit_chimney", bevel_m=0.01, segments=1, min_edge=0.3)
    stack.box(-0.38, 0.38, 0, 1, -0.3, 0.3, "brick")
    cap = kit.Part("kit_chimney_cap", **SOFT)
    cap.box(-0.46, 0.46, 0, 0.06, -0.38, 0.38, "concrete")
    cap.box(-0.42, 0.42, 0.06, 0.1, -0.34, 0.34, "concrete")      # a washed crown
    for cx in (-0.15, 0.15):
        cap.tube(cx, 0.0, 0.1, 0.42, 0.075, 12, "metal")          # two flues
        cap.tube(cx, 0.0, 0.42, 0.45, 0.09, 12, "metal")          # and their rims
    cap.box(-0.28, 0.28, 0.55, 0.57, -0.13, 0.13, "metal")        # rain cap on legs
    for cx in (-0.25, 0.25):
        cap.box(cx - 0.012, cx + 0.012, 0.42, 0.55, -0.012, 0.012, "metal")
    ac = kit.Part("kit_ac_unit", **SOFT)
    ac.box(-0.33, 0.33, 0.04, 0.42, 0, 0.5, "ac")
    for k in range(7):   # front louvres
        y = 0.08 + k * 0.045
        ac.box(-0.28, 0.28, y, y + 0.02, 0.5, 0.52, "metal")
    for k in range(6):   # side fins
        z = 0.06 + k * 0.07
        ac.box(0.33, 0.34, 0.08, 0.38, z, z + 0.035, "metal")
    ac.tube(0.0, 0.25, 0.42, 0.43, 0.16, 16, "metal")              # fan grille ring on top
    ac.box(-0.15, 0.15, 0.425, 0.435, 0.24, 0.26, "metal")
    for cx in (-0.28, 0.28):
        ac.box(cx - 0.03, cx + 0.03, 0.0, 0.04, 0.02, 0.48, "metal")   # feet
    ac.tube(-0.25, 0.05, 0.1, 0.5, 0.012, 6, "metal")              # pipes into the wall
    ac.tube(-0.2, 0.05, 0.1, 0.5, 0.009, 6, "metal")
    meter = kit.Part("kit_meter", **SOFT)
    meter.box(-0.15, 0.15, 1.15, 1.55, 0, 0.15, "metal")
    meter.box(-0.16, 0.16, 1.53, 1.56, 0, 0.17, "metal")           # hood over it
    meter.tube(0.0, 0.16, 1.3, 1.42, 0.07, 12, "glass")
    meter.ball(0.0, 1.42, 0.16, 0.07, "glass", rings=4, sides=12)  # the dome
    meter.along_y([(-0.025, 0.03), (0.025, 0.03), (0.025, 0.08), (-0.025, 0.08)], 0.2, 1.15, "metal")   # conduit down to the ground
    meter.box(-0.04, 0.04, 0.95, 1.0, 0.02, 0.09, "metal")        # a clamp
    return [stack, cap, ac, meter]


def all_parts() -> list[kit.Part]:
    return [window("kit_window_sash", 1.0, 1.3, "sash"), window("kit_window_wide", 1.8, 1.3, "mullion"),
        window("kit_window_small", 0.6, 0.6, "none", "frosted"), door_front(), door_garage(), *trims(), porch(), *extras(),
        window_arch(), door_arch()]


def main(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for part in all_parts():
        kit.reset()
        ob = part.finish()
        print(f"{ob.name}: {kit.triangles(ob)} triangles -> {kit.export(ob, out_dir)}")


if __name__ == "__main__":
    main(sys.argv[-1] if len(sys.argv) > 1 else "art/models/kit")
