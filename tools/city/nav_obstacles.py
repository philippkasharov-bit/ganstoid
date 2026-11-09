"""Clean, non-overlapping obstacle polygons per nav tile for the navmesh bake.
Buildings that touch/overlap are merged (row houses, complexes); enclosed courtyards
are filled (unreachable); river channel is an obstacle except at boulevard bridges;
freeways and ramps are obstacles except where a street crosses over/under them.
Usage: python3 nav_obstacles.py <city_v1.json> <buildings_v1.json> <out.json>"""
import json
import sys

from shapely.geometry import LineString, Polygon, box
from shapely.ops import unary_union

TILES, RIVER_HALF, BRIDGE_GAP = 8, 16.0, 18.0


def main(city_p, bld_p, out_p):
    city, blds = json.load(open(city_p)), json.load(open(bld_p))["buildings"]
    size = city["size_m"]
    polys = []
    for b in blds:
        p = Polygon(b["poly"]).buffer(0)
        if p.is_valid and p.area > 1:
            polys.append(p)
    river = LineString(city["river"]).buffer(RIVER_HALF, cap_style=2)
    arts = unary_union([LineString(r["pts"]) for r in city["roads"] if r["tier"] == "art"])
    bridges = river.intersection(arts).buffer(BRIDGE_GAP)
    # freeways: no walking on them; crossing only where a street goes over/under
    fwys = unary_union([LineString(r["pts"]).buffer(7 if r["tier"] == "fwy" else 4, cap_style=2)
                        for r in city["roads"] if r["tier"] in ("fwy", "ramp")])
    streets = unary_union([LineString(r["pts"]) for r in city["roads"] if r["tier"] in ("art", "res", "path")])
    crossings = fwys.intersection(streets).buffer(10)
    obstacles = unary_union(polys + [river.difference(bridges), fwys.difference(crossings)])
    tile = size / TILES
    out = {}
    for tx in range(TILES):
        for ty in range(TILES):
            clip = obstacles.intersection(box(tx * tile - 3, ty * tile - 3, (tx + 1) * tile + 3, (ty + 1) * tile + 3))
            shapes = []
            for g in getattr(clip, "geoms", [clip]):
                if g.geom_type != "Polygon" or g.area < 1:
                    continue
                g = Polygon(g.exterior).simplify(0.3).buffer(0)   # fill courtyards, drop slivers
                for h in getattr(g, "geoms", [g]):
                    if h.geom_type == "Polygon" and h.area > 1:
                        shapes.append([[round(x, 2), round(y, 2)] for x, y in list(h.exterior.coords)[:-1]])
            out["%d_%d" % (tx, ty)] = shapes
    json.dump({"tiles": TILES, "size_m": size, "obstacles": out}, open(out_p, "w"), separators=(",", ":"))
    print("obstacles per tile:", sum(len(v) for v in out.values()))


if __name__ == "__main__":
    main(*sys.argv[1:4])
