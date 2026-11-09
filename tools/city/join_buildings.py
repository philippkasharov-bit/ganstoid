"""C3c2: join some neighbouring homes into rows (terraces, duplexes, townhouse strings).

Real OSM footprints keep small gaps between neighbours. Here a seeded ~35% of
close house/apartment pairs get their gap filled so they read as one joined
building. Never closes a gap that a road, alley or path uses, never joins
across a third building, and caps a row at MAX_ROW buildings. Deterministic.
Usage: python3 -I join_buildings.py <unjoined.json> <city_v1.json> <out buildings_v1.json>
"""
import json
import sys
import zlib

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

JOIN_KINDS = {"house", "apartments"}
MAX_GAP_M = 2.5
MIN_GAP_M = 0.05
MIN_FACING_M = 6.0
JOIN_PERCENT = 35
MAX_ROW = 6
ROAD_CLEAR_M = 1.5


def pair_roll(a, b):
    return zlib.crc32(("%s|%s" % tuple(sorted((a, b)))).encode()) % 100


def main(src, city_path, dst):
    raw = json.load(open(src))
    blds = raw["buildings"]
    geoms = [Polygon(b["poly"]).buffer(0) for b in blds]
    city = json.load(open(city_path))
    roads = unary_union([LineString(r["pts"]).buffer(ROAD_CLEAR_M) for r in city["roads"] if r["tier"] in ("art", "res", "alley", "svc", "path", "hill")])
    tree = STRtree(geoms)
    parent = list(range(len(blds)))
    size = [1] * len(blds)
    bridges = {}

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i, g in enumerate(geoms):
        if blds[i]["kind"] not in JOIN_KINDS:
            continue
        for j in tree.query(g.buffer(MAX_GAP_M)):
            if j <= i or blds[j]["kind"] not in JOIN_KINDS or blds[i]["kind"] != blds[j]["kind"]:
                continue
            gap = g.distance(geoms[j])
            if not (MIN_GAP_M <= gap <= MAX_GAP_M) or pair_roll(blds[i]["id"], blds[j]["id"]) >= JOIN_PERCENT:
                continue
            r = gap + 0.05
            hull = unary_union([g, geoms[j]]).convex_hull   # clips the rounded buffer bulges at the ends
            lens = g.buffer(r).intersection(geoms[j].buffer(r)).intersection(hull).difference(g).difference(geoms[j])
            if lens.is_empty or lens.area / gap < MIN_FACING_M or lens.intersects(roads):
                continue
            if any(k not in (i, j) and geoms[k].intersects(lens) for k in tree.query(lens)):
                continue
            ri, rj = find(i), find(j)
            if ri == rj or size[ri] + size[rj] > MAX_ROW:
                continue
            parent[rj] = ri
            size[ri] += size[rj]
            bridges.setdefault(i, []).append((j, lens))
            bridges.setdefault(j, []).append((i, lens))
    groups = {}
    for i in range(len(blds)):
        groups.setdefault(find(i), []).append(i)
    out, joined_rows, joined_n = [], 0, 0
    for members in groups.values():
        first = blds[members[0]]
        if len(members) == 1:
            out.append(first)
            continue
        parts = [geoms[m] for m in members] + [l for m in members for _, l in bridges.get(m, [])]
        merged = unary_union(parts).buffer(0.3, join_style=2).buffer(-0.3, join_style=2)   # closes hairline slits
        if merged.geom_type != "Polygon":
            out.extend(blds[m] for m in members)   # could not merge cleanly: leave the originals
            continue
        joined_rows += 1
        joined_n += len(members)
        out.append({"id": first["id"], "kind": first["kind"], "levels": max(blds[m]["levels"] for m in members),
                    "poly": [[round(x, 1), round(y, 1)] for x, y in merged.simplify(0.05).exterior.coords]})
    raw["buildings"] = out
    json.dump(raw, open(dst, "w"), separators=(",", ":"))
    print("buildings %d -> %d; %d rows joined from %d homes" % (len(blds), len(out), joined_rows, joined_n))


if __name__ == "__main__":
    main(*sys.argv[1:4])
