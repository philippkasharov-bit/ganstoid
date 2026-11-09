"""Road layout audit: finds out-of-place road geometry in the frozen city.

Checks (each finding = a location + category):
  dup        two roads of the same tier running on top of each other (>= 25 m within 2 m)
  near_gap   a road end stops 1.5-8 m short of another road (looks broken)
  stub       a street/alley piece shorter than 8 m hanging off the network
  kink       a street turns back on itself (> 150 deg within 12 m) - zigzag artefact
  thru_bldg  a street/alley segment passes through a building
  alley_hug  an alley runs alongside a street closer than 7 m for >= 25 m (redundant)
  island     a tiny street network (< 150 m total) not touching the map edge
Usage: python3 -I audit_roads.py <city_v1.json> <buildings_v1.json> <out findings.json>
"""
import json
import math
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

STREETS = ("art", "res", "alley", "hill")


def load(city_path, bld_path):
    city = json.load(open(city_path))
    roads = [(r, LineString(r["pts"])) for r in city["roads"] if r["tier"] in STREETS and len(r["pts"]) >= 2]
    blds = [Polygon(b["poly"]).buffer(0) for b in json.load(open(bld_path))["buildings"]]
    return city, roads, blds


def dups(roads, tree):
    out = []
    for i, (r, ln) in enumerate(roads):
        for j in tree.query(ln.buffer(2.0)):
            if j <= i or roads[j][0]["tier"] != r["tier"]:
                continue
            shared = ln.intersection(roads[j][1].buffer(2.0))
            if shared.length >= 25.0:
                out.append(("dup", shared.interpolate(0.5, normalized=True), "%s / %s" % (r["id"], roads[j][0]["id"])))
    return out


def ends(roads, tree, size):
    out = []
    for i, (r, ln) in enumerate(roads):
        for end in (Point(ln.coords[0]), Point(ln.coords[-1])):
            if min(end.x, end.y) < 15 or max(end.x, end.y) > size - 15:
                continue
            ds = [roads[j][1].distance(end) for j in tree.query(end.buffer(8.0)) if j != i]
            if ds and 1.5 < min(ds) <= 8.0:
                out.append(("near_gap", end, r["id"]))
            elif not ds and ln.length < 8.0:
                out.append(("stub", end, r["id"]))
    return out


def kinks(roads):
    out = []
    for r, ln in roads:
        pts = list(ln.coords)
        for k in range(1, len(pts) - 1):
            a, b, c = pts[k - 1], pts[k], pts[k + 1]
            if math.dist(a, b) > 12 or math.dist(b, c) > 12:
                continue
            v1, v2 = (b[0] - a[0], b[1] - a[1]), (c[0] - b[0], c[1] - b[1])
            n = math.hypot(*v1) * math.hypot(*v2)
            if n and (v1[0] * v2[0] + v1[1] * v2[1]) / n < math.cos(math.radians(150)):
                out.append(("kink", Point(b), r["id"]))
    return out


def through_buildings(roads, blds):
    tree, out = STRtree(blds), []
    for r, ln in roads:
        for k in tree.query(ln):
            inside = ln.intersection(blds[k])
            if inside.length > 4.0:
                out.append(("thru_bldg", inside.interpolate(0.5, normalized=True), r["id"]))
    return out


def alley_hugs(roads, tree):
    out = []
    for i, (r, ln) in enumerate(roads):
        if r["tier"] != "alley":
            continue
        for j in tree.query(ln.buffer(7.0)):
            if roads[j][0]["tier"] in ("art", "res") and ln.intersection(roads[j][1].buffer(7.0)).length >= 25.0:
                out.append(("alley_hug", ln.interpolate(0.5, normalized=True), r["id"]))
                break
    return out


def islands(roads, size):
    net = unary_union([ln.buffer(1.0) for r, ln in roads if r["tier"] in ("art", "res", "hill")])
    out = []
    for g in getattr(net, "geoms", [net]):
        b = g.bounds
        if g.area / 2.0 < 150.0 and min(b[0], b[1]) > 15 and max(b[2], b[3]) < size - 15:
            out.append(("island", g.centroid, ""))
    return out


def main(city_path, bld_path, dst):
    city, roads, blds = load(city_path, bld_path)
    tree = STRtree([ln for _, ln in roads])
    found = dups(roads, tree) + ends(roads, tree, city["size_m"]) + kinks(roads) + through_buildings(roads, blds) + alley_hugs(roads, tree) + islands(roads, city["size_m"])
    counts = {}
    for cat, _, _ in found:
        counts[cat] = counts.get(cat, 0) + 1
    print("road pieces checked: %d" % len(roads))
    for cat in sorted(counts, key=lambda c: -counts[c]):
        print("  %-10s %d" % (cat, counts[cat]))
    json.dump([{"cat": c, "at": [round(p.x), round(p.y)], "road": rid} for c, p, rid in found], open(dst, "w"))


if __name__ == "__main__":
    main(*sys.argv[1:4])
