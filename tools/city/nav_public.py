"""C3d: per-tile PUBLIC walkable shapes for the civilian navmesh.

walk  = sidewalks + crosswalks + footpaths + parks (cheap, everyone uses them)
alley = alleys and service lanes, minus the walk shapes (baked as its own region
        so its travel cost can rise for civilians and at night)
Buildings are already cut out in public_v1.json (tools/city/public_space.py).
Usage: python3 -I nav_public.py <public_v1.json> <size_m> <out nav_public.json>
"""
import json
import sys

from shapely.geometry import Polygon, box
from shapely.ops import unary_union

TILES = 8
MARGIN_M = 3.0   # the bake clips each tile exactly (NavigationPolygon.baking_rect)


def shapes(geom):
    out = []
    for g in getattr(geom, "geoms", [geom]):
        if g.geom_type != "Polygon" or g.area < 1.0:
            continue
        g = g.simplify(0.1)
        if g.is_empty or g.geom_type != "Polygon":
            continue
        out.append({"outer": [[round(x, 2), round(y, 2)] for x, y in list(g.exterior.coords)[:-1]],
                    "holes": [[[round(x, 2), round(y, 2)] for x, y in list(h.coords)[:-1]] for h in g.interiors]})
    return out


def main(src, size, dst):
    size = float(size)
    zones = json.load(open(src))["zones"]
    by_kind = {}
    for z in zones:
        by_kind.setdefault(z["kind"], []).append(Polygon(z["outer"], z["holes"]).buffer(0))
    walk = unary_union(by_kind.get("sidewalk", []) + by_kind.get("path", []) + by_kind.get("park", []))
    alley = unary_union(by_kind.get("alley", [])).difference(walk)
    tile = size / TILES
    out = {"tiles": TILES, "size_m": size, "walk": {}, "alley": {}}
    for tx in range(TILES):
        for ty in range(TILES):
            clip = box(tx * tile - MARGIN_M, ty * tile - MARGIN_M, (tx + 1) * tile + MARGIN_M, (ty + 1) * tile + MARGIN_M)
            out["walk"]["%d_%d" % (tx, ty)] = shapes(walk.intersection(clip))
            out["alley"]["%d_%d" % (tx, ty)] = shapes(alley.intersection(clip))
    json.dump(out, open(dst, "w"), separators=(",", ":"))
    print("walk shapes %d, alley shapes %d" % (sum(map(len, out["walk"].values())), sum(map(len, out["alley"].values()))))


if __name__ == "__main__":
    main(*sys.argv[1:4])
