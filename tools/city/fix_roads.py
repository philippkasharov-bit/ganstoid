"""C3f: fix the out-of-place road geometry found by audit_roads.py.

  1. generated alleys running inside a freeway corridor (>= 20 m)   -> deleted
  2. generated alleys hugging a street (< 7 m away for >= 25 m)     -> deleted
  3. duplicate roads of one tier on top of each other               -> shorter one deleted
  4. tiny street islands (< 150 m, not at the map edge)             -> deleted
  5. generated alleys left with a loose end by 1-4                  -> deleted (repeat)
  6. road ends stopping 1.5-8 m short of another road               -> extended to touch it
     (unless the extension would cut through a building); ends that crossed a
     road and stick out 1.5-8 m past it                              -> trimmed back
  7. "buildings" a street/alley runs through for > 4 m (skybridges,
     canopies drawn over the street)                                -> deleted from the
     unjoined source; re-run join_buildings.py + doors.py afterwards
Usage: python3 -I fix_roads.py <city_v1.json> <buildings_unjoined.json>   (both edited in place)
"""
import json
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points, unary_union
from shapely.strtree import STRtree

import audit_roads as audit

FWY_HALF_M = 14.0
LOOSE_END_M = 3.0


def is_generated(road):
    return road["id"].startswith("base:gen_alley")


def drop_ids(city, ids):
    city["roads"] = [r for r in city["roads"] if r["id"] not in ids]


def freeway_and_hugging_alleys(city):
    fwy = unary_union([LineString(r["pts"]).buffer(FWY_HALF_M) for r in city["roads"] if r["tier"] in ("fwy", "ramp")])
    streets = [LineString(r["pts"]) for r in city["roads"] if r["tier"] in ("art", "res")]
    tree, out = STRtree(streets), set()
    for r in city["roads"]:
        if not is_generated(r):
            continue
        ln = LineString(r["pts"])
        if ln.intersection(fwy).length >= 20.0:
            out.add(r["id"])
            continue
        if any(ln.intersection(streets[j].buffer(7.0)).length >= 25.0 for j in tree.query(ln.buffer(7.0))):
            out.add(r["id"])
    return out


def duplicates_and_islands(city, blds):
    roads = [(r, LineString(r["pts"])) for r in city["roads"] if r["tier"] in audit.STREETS and len(r["pts"]) >= 2]
    tree = STRtree([ln for _, ln in roads])
    out = set()
    for cat, _, rid in audit.dups(roads, tree):
        a, b = rid.split(" / ")
        la, lb = [ln.length for r, ln in roads if r["id"] in (a, b)][:2]
        out.add(a if la < lb else b)
    for _, at, _ in audit.islands(roads, city["size_m"]):
        out.update(r["id"] for r, ln in roads if ln.distance(at) < 80.0 and ln.length < 150.0 and r["tier"] in ("art", "res", "hill"))
    return out


def loose_generated(city):
    """Generated alleys with an end touching nothing (their parent alley was deleted)."""
    lines = [LineString(r["pts"]) for r in city["roads"]]
    tree, dead = STRtree(lines), [Point(p) for p in city.get("dead_ends", [])]
    out = set()
    for i, r in enumerate(city["roads"]):
        if not is_generated(r):
            continue
        for end in (Point(r["pts"][0]), Point(r["pts"][-1])):
            touching = [j for j in tree.query(end.buffer(LOOSE_END_M)) if j != i and lines[j].distance(end) <= LOOSE_END_M]
            if not touching and not any(d.distance(end) < 12.0 for d in dead):
                out.add(r["id"])
    return out


def extend_short_ends(city, bld_tree, blds):
    lines = [LineString(r["pts"]) for r in city["roads"]]
    tree, size, fixed = STRtree(lines), city["size_m"], 0
    for i, r in enumerate(city["roads"]):
        if r["tier"] not in audit.STREETS:
            continue
        for at_start in (True, False):
            end = Point(r["pts"][0] if at_start else r["pts"][-1])
            if min(end.x, end.y) < 15 or max(end.x, end.y) > size - 15:
                continue
            near = [j for j in tree.query(end.buffer(8.0)) if j != i and city["roads"][j]["tier"] in audit.STREETS]
            if not near:
                continue
            j = min(near, key=lambda k: lines[k].distance(end))
            d = lines[j].distance(end)
            if not 1.5 < d <= 8.0:
                continue
            target = nearest_points(lines[j], end)[0]
            hop = LineString([end, target])
            if any(blds[k].intersects(hop) for k in bld_tree.query(hop)):
                continue
            prev = r["pts"][1] if at_start else r["pts"][-2]
            out_dir = (end.x - prev[0], end.y - prev[1])
            hop_dir = (target.x - end.x, target.y - end.y)
            if out_dir[0] * hop_dir[0] + out_dir[1] * hop_dir[1] < 0:
                # overshoot: the road already crossed that road and sticks out a few metres -> trim it back
                cut = trim_overshoot(r["pts"], lines[j], at_start)
                if cut is not None:
                    r["pts"] = cut
                    fixed += 1
                continue
            pt = [round(target.x, 1), round(target.y, 1)]
            r["pts"] = [pt] + r["pts"] if at_start else r["pts"] + [pt]
            fixed += 1
    return fixed


def trim_overshoot(pts, other, at_start):
    """Cut the road's end back to where it crosses `other` (within its last 10 m)."""
    seq = pts if not at_start else pts[::-1]
    line = LineString(seq)
    hit = line.intersection(other)
    cands = [g for g in getattr(hit, "geoms", [hit]) if g.geom_type == "Point" and line.length - line.project(g) <= 10.0]
    if not cands:
        return None
    s = max(line.project(g) for g in cands)
    kept = [p for p in seq if line.project(Point(p)) < s - 0.05]
    cut_pt = line.interpolate(s)
    kept.append([round(cut_pt.x, 1), round(cut_pt.y, 1)])
    if len(kept) < 2:
        return None
    return kept if not at_start else kept[::-1]


def skybridges(city, raw):
    lines = [LineString(r["pts"]) for r in city["roads"] if r["tier"] in ("art", "res", "alley")]
    tree, out = STRtree(lines), set()
    for b in raw["buildings"]:
        poly = Polygon(b["poly"]).buffer(0)
        if any(poly.intersection(lines[k]).length > 4.0 for k in tree.query(poly)):
            out.add(b["id"])
    return out


def main(city_path, bld_path):
    city, raw = json.load(open(city_path)), json.load(open(bld_path))
    blds = [Polygon(b["poly"]).buffer(0) for b in raw["buildings"]]
    gone = freeway_and_hugging_alleys(city)
    print("generated alleys in freeway corridors or hugging streets: %d" % len(gone))
    gone |= duplicates_and_islands(city, blds)
    drop_ids(city, gone)
    cascade = 0
    while True:
        loose = loose_generated(city)
        if not loose:
            break
        cascade += len(loose)
        drop_ids(city, loose)
    print("roads deleted: %d (+%d generated alleys left with a loose end)" % (len(gone), cascade))
    print("short road ends extended to meet their road: %d" % extend_short_ends(city, STRtree(blds), blds))
    bridges = skybridges(city, raw)
    raw["buildings"] = [b for b in raw["buildings"] if b["id"] not in bridges]
    print("skybridge/canopy 'buildings' over streets deleted: %d" % len(bridges))
    json.dump(city, open(city_path, "w"), separators=(",", ":"))
    json.dump(raw, open(bld_path, "w"), separators=(",", ":"))


if __name__ == "__main__":
    main(*sys.argv[1:3])
