"""C3d: per-tile PUBLIC walkable shapes for the civilian navmesh.

walk  = sidewalks + crosswalks + footpaths + parks (cheap, everyone uses them)
alley = alleys and service lanes, minus the walk shapes (baked as its own region
        so its travel cost can rise for civilians and at night)
The parkway strip between the kerb and the paving (MP2b) is taken OFF the
civilian mesh: people walk the concrete, not the grass. Corners, crosswalks and
driveways stay paving, and a strip stays walkable where the paving beside it is
broken, so no street is cut off. (A separate costed region was tried first: Godot
joins each navmesh edge to one neighbour only, which left most strips as islands.)
Buildings are already cut out in public_v1.json (tools/city/public_space.py).
Usage: python3 -I nav_public.py <public_v1.json> <size_m> <out nav_public.json> <city_v1.json> <section_v1.json>
"""
import json
import os
import sys

from shapely.geometry import LineString, Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # sibling tools; -I drops the script dir
import public_space   # noqa: E402
import street_section   # noqa: E402

TILES = 8
MIN_HOLE_M2 = 0.25
MARGIN_M = 3.0   # the bake clips each tile exactly (NavigationPolygon.baking_rect)


def shapes(geom):
    out = []
    for g in getattr(geom, "geoms", [geom]):
        if g.geom_type != "Polygon" or g.area < 1.0:
            continue
        g = g.simplify(0.1)
        if g.is_empty or g.geom_type != "Polygon":
            continue
        # pinholes (left by cutting strips out of the paving) are filled: a hole that
        # collapses to a line once rounded breaks the navmesh bake for the whole tile
        holes = [h for h in g.interiors if Polygon(h).area >= MIN_HOLE_M2]
        out.append({"outer": [[round(x, 2), round(y, 2)] for x, y in list(g.exterior.coords)[:-1]],
                    "holes": [[[round(x, 2), round(y, 2)] for x, y in list(h.coords)[:-1]] for h in holes]})
    return out


OPEN_M = 0.15         # paving thinner than 0.3 m after the cut is not paving
MOUTH_PAD_M = 0.8     # paving kept either side of an alley mouth or footpath
AGENT_M = 0.42        # just over the nav agent radius (0.4)
MIN_VERGE_M2 = 4.0    # smaller scraps of parkway stay paving: not worth a nav region


def verge_of(city, section, crosswalks):
    """Parkway strips of every street, cut back at corners, crosswalks and driveways."""
    roads = [r for r in city["roads"] if float(r.get("side", 0.0)) > 0.0 and len(r["pts"]) >= 2]
    lines = [LineString(r["pts"]) for r in roads]
    corridors = [ln.buffer(float(r["w"]) / 2 + float(r["side"]), cap_style=2) for r, ln in zip(roads, lines)]
    tree = STRtree(corridors)
    rings = []
    for i, (r, ln) in enumerate(zip(roads, lines)):
        park = section["roads"].get(r["id"], {}).get("park", 0.0)
        if park <= 0.0:
            continue
        half = float(r["w"]) / 2
        ring = ln.buffer(half + park, cap_style=2).difference(ln.buffer(half, cap_style=2))
        others = [corridors[k] for k in tree.query(ring) if k != i and corridors[k].intersects(ring)
                  and not lines[k].equals(ln)]
        if others:   # a corner: the other street's band is paving, kerb to lot
            ring = ring.difference(unary_union(others))
        rings.append(ring)
    paved = [public_space.crosswalk_poly(c) for c in crosswalks]
    paved += [street_section.band_rect(a["c"], a["dir"], a["w"], a["len"]) for a in section["aprons"]]
    verge = unary_union(rings).difference(unary_union(paved).buffer(0.3))
    return unary_union([g for g in getattr(verge, "geoms", [verge]) if g.area >= MIN_VERGE_M2])


def walkable_parts(geom):
    """What is left once a person's width is taken off every edge, as separate islands."""
    inner = geom.buffer(-AGENT_M)
    return [g for g in getattr(inner, "geoms", [inner]) if g.geom_type == "Polygon" and g.area >= 0.5]


def paved_alongside(strip, paving):
    """True if one unbroken piece of paving runs the whole length of this grass strip.

    Only then is the grass redundant: everything it reaches, the concrete beside
    it reaches too. Where the sidewalk stops short, is one-sided or is missing in
    the data, the grass is the path and must stay.
    """
    width = 2.0 * strip.area / strip.length          # a long thin strip: area / half-perimeter
    reach = width + AGENT_M + 0.6
    near = strip.buffer(reach)
    window = box(*near.bounds)   # the paving of a whole tile is one huge shape: only look at this corner of it
    for k in paving.query(near, predicate="intersects"):
        local = paving.geometries[k].intersection(window)
        for part in getattr(local, "geoms", [local]):
            if part.geom_type == "Polygon" and strip.difference(part.buffer(reach)).area < 0.02 * strip.area:
                return True
    return False


def cut_grass(w, strips):
    """Take the parkway strips out of the walkable ground, except where that would cut the sidewalk.

    People walk the concrete, not the grass. But where the paving beside a strip
    is pinched off (a wall, a pole base, a gap in the data) the grass is the only
    way through, so any strip that joins two islands of paving stays walkable.
    Returns (ground, m2 of grass left walkable).
    """
    kept_m2 = 0.0
    strips = list(strips)
    if strips:
        paving = STRtree(walkable_parts(w.difference(unary_union(strips))))
        lone = [g for g in strips if not paved_alongside(g, paving)]
        ids = {id(g) for g in lone}
        kept_m2 += sum(g.area for g in lone)
        strips = [g for g in strips if id(g) not in ids]
    while strips:
        cut = w.difference(unary_union(strips))
        cut = cut.buffer(-OPEN_M).buffer(OPEN_M).intersection(w)   # drop hair-thin leftovers and point contacts
        islands = walkable_parts(cut)
        if len(islands) <= len(walkable_parts(w)):
            return cut, kept_m2
        tree = STRtree(islands)
        bridges = [g for g in strips if len({int(k) for k in tree.query(g.buffer(AGENT_M + 0.3), predicate="intersects")}) >= 2]
        if not bridges:
            return cut, kept_m2
        ids = {id(g) for g in bridges}
        kept_m2 += sum(g.area for g in bridges)
        strips = [g for g in strips if id(g) not in ids]
    return w, kept_m2


def main(src, size, dst, city_path=None, section_path=None):
    size = float(size)
    pub = json.load(open(src))
    zones = pub["zones"]
    by_kind = {}
    for z in zones:
        by_kind.setdefault(z["kind"], []).append(Polygon(z["outer"], z["holes"]).buffer(0))
    walk = unary_union(by_kind.get("sidewalk", []) + by_kind.get("path", []) + by_kind.get("park", []))
    alley = unary_union(by_kind.get("alley", [])).difference(walk)
    mouths = unary_union(by_kind.get("alley", []) + by_kind.get("path", [])).buffer(MOUTH_PAD_M)
    verge_parts, verge_tree = [], None
    if city_path and section_path:
        verge = verge_of(json.load(open(city_path)), json.load(open(section_path)), pub["crosswalks"])
        verge_parts = list(getattr(verge, "geoms", [verge]))
        verge_tree = STRtree(verge_parts)
    tile = size / TILES
    out = {"tiles": TILES, "size_m": size, "walk": {}, "alley": {}}
    grass_m2 = kept_m2 = 0.0
    for tx in range(TILES):
        for ty in range(TILES):
            clip = box(tx * tile - MARGIN_M, ty * tile - MARGIN_M, (tx + 1) * tile + MARGIN_M, (ty + 1) * tile + MARGIN_M)
            key = "%d_%d" % (tx, ty)
            w = walk.intersection(clip)
            if verge_tree is not None:   # per tile: the whole-city difference takes minutes
                v = unary_union([verge_parts[k] for k in verge_tree.query(clip)]).intersection(w)
                # alley mouths and footpaths cross the band on concrete, like a driveway
                v = v.difference(mouths.intersection(clip))
                strips = [g for g in getattr(v, "geoms", [v]) if g.geom_type == "Polygon" and g.area >= MIN_VERGE_M2]
                w, kept = cut_grass(w, strips)
                inner = box(tx * tile, ty * tile, (tx + 1) * tile, (ty + 1) * tile)
                grass_m2 += sum(g.intersection(inner).area for g in strips) - kept
                kept_m2 += kept
            out["walk"][key] = shapes(w)
            out["alley"][key] = shapes(alley.intersection(clip))
    print("walk shapes %d, alley shapes %d" % (sum(map(len, out["walk"].values())), sum(map(len, out["alley"].values()))))
    print("parkway grass taken off the civilian mesh: %.0f m2; left walkable because the paving beside it is broken: %.0f m2" % (grass_m2, kept_m2))
    json.dump(out, open(dst, "w"), separators=(",", ":"))


if __name__ == "__main__":
    main(*sys.argv[1:6])
