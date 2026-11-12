"""MP8: buildings on lots that OpenStreetMap left empty.

Many LA County lots in the extract carry a house, apartments, shop or works
but no building was ever mapped there, which leaves bare blocks on the map.
For each such lot (under 8% covered by mapped buildings) this places one
footprint: the lot pulled in by a setback that suits its use, kept clear of
existing buildings, at a typical height for that use. Civic, parking, open and
other lots stay as they are (parks, schools, car parks are open ground).

Usage: python3 -I fill_buildings.py <parcels_v1.json> <buildings_v1.json> <city_v1.json>   (buildings edited in place)
Run after join_buildings, before doors.
"""
import json
import sys

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

# use: [setback m, levels, building kind, max share of the lot]
FILL = {
    "house": [3.0, 1, "house", 0.55],
    "apartments": [2.0, 3, "apartments", 0.7],
    "commercial": [0.8, 2, "commercial", 0.85],
    "industrial": [1.5, 1, "industrial", 0.8],
}
EMPTY_SHARE = 0.08
MIN_LOT_M2 = 60.0
MIN_BLD_M2 = 40.0
CLEAR_M = 1.0


def main(parcels_path, bld_path, city_path):
    lots = json.load(open(parcels_path))["parcels"]
    data = json.load(open(bld_path))
    blds = [Polygon(b["poly"]).buffer(0) for b in data["buildings"]]
    tree = STRtree(blds)
    city = json.load(open(city_path))
    roads = [LineString(r["pts"]).buffer(r.get("w", 6.0) * 0.5 + 0.5) for r in city["roads"] if len(r["pts"]) >= 2]
    road_tree = STRtree(roads)
    data["buildings"] = [b for b in data["buildings"] if not b["id"].startswith("base:fill_")]   # re-runnable
    added = {}
    for n, lot in enumerate(lots):
        rule = FILL.get(lot["use"])
        if rule is None:
            continue
        g = Polygon(lot["poly"]).buffer(0)
        if g.area < MIN_LOT_M2:
            continue
        near = [blds[i] for i in tree.query(g)]
        if sum(g.intersection(b).area for b in near) / g.area >= EMPTY_SHARE:
            continue
        shape = g.buffer(-rule[0], join_style=2)
        if near:
            shape = shape.difference(unary_union(near).buffer(CLEAR_M))
        hits = [roads[i] for i in road_tree.query(shape)]
        if hits:
            shape = shape.difference(unary_union(hits))
        parts = [p for p in getattr(shape, "geoms", [shape]) if p.geom_type == "Polygon"]
        if not parts:
            continue
        best = max(parts, key=lambda p: p.area)
        if best.area < MIN_BLD_M2:
            continue
        if best.area > g.area * rule[3]:   # not wall to wall: scale toward the lot's middle
            best = best.buffer(-(best.area - g.area * rule[3]) / max(best.length, 1.0), join_style=2)
            if best.is_empty or best.geom_type != "Polygon" or best.area < MIN_BLD_M2:
                continue
        best = best.simplify(0.4)
        data["buildings"].append({"id": "base:fill_%d" % n, "kind": rule[2], "levels": rule[1],
                                  "poly": [[round(x, 1), round(y, 1)] for x, y in best.exterior.coords]})
        added[rule[2]] = added.get(rule[2], 0) + 1
    json.dump(data, open(bld_path, "w"), separators=(",", ":"))
    print("buildings added on empty lots:", added, "total", sum(added.values()))


if __name__ == "__main__":
    main(*sys.argv[1:4])
