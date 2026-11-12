"""MP3a: intersections and bus stops (until the real ones come from the full OSM extract).

Junctions = points where 3+ street ends meet (residential, arterial, hill).
  signal: an arterial is one of the streets (LA signals its arterial crossings)
  stop:   residential-only junctions (all-way or two-way stops)
Bus stops: along arterials every BUS_EVERY_M on the right-hand kerb.

Usage: python3 -I intersections.py <city_v1.json> <out intersections_v1.json> [real_v1.json]
With real_v1.json (the full OSM extract), a junction gets a signal or stop sign only
where OpenStreetMap has one mapped (highway=traffic_signals / stop within SNAP_M);
other junctions are uncontrolled. Bus stops dropped (Phil: no buses).
"""
import json
import math
import sys
from collections import defaultdict

JOIN_M = 4.0
BUS_EVERY_M = 400.0
STREETS = ("res", "art", "hill")


SNAP_M = 22.0


def real_controls(real_path):
    if not real_path:
        return None
    pts = json.load(open(real_path))["points"]
    grid = defaultdict(list)
    for p in pts:
        if p["kind"] in ("signal", "stop"):
            grid[(int(p["p"][0] // 50), int(p["p"][1] // 50))].append(p)
    return grid


def control_at(grid, x, y):
    best, best_d = None, SNAP_M
    for gx in range(int(x // 50) - 1, int(x // 50) + 2):
        for gy in range(int(y // 50) - 1, int(y // 50) + 2):
            for p in grid.get((gx, gy), []):
                d = math.hypot(p["p"][0] - x, p["p"][1] - y)
                if d < best_d or (p["kind"] == "signal" and d < SNAP_M and best and best["kind"] == "stop"):
                    best, best_d = p, d
    return best["kind"] if best else None


def main(city_path, out_path, real_path=None):
    city = json.load(open(city_path))
    grid = real_controls(real_path)
    # every vertex of every street: an end is one leg in, a through point two
    at = defaultdict(list)
    for r in city["roads"]:
        if r["tier"] not in STREETS:
            continue
        pts = r["pts"]
        for i, p in enumerate(pts):
            at[(round(p[0] / JOIN_M), round(p[1] / JOIN_M))].append((r, i))
    junctions = []
    for key, lst in at.items():
        roads = {id(r) for r, i in lst}
        legs = []
        for r, i in lst:
            pts = r["pts"]
            for j in (i - 1, i + 1):
                if 0 <= j < len(pts):
                    a, b = pts[i], pts[j]
                    d = math.hypot(a[0] - b[0], a[1] - b[1]) or 1.0
                    legs.append([round((a[0] - b[0]) / d, 3), round((a[1] - b[1]) / d, 3), round(r.get("w", 8.0), 1), r["tier"]])
        if len(roads) < 2 or len(legs) < 3:
            continue
        x = sum(r["pts"][i][0] for r, i in lst) / len(lst)
        y = sum(r["pts"][i][1] for r, i in lst) / len(lst)
        kind = ("signal" if any(l[3] == "art" for l in legs) else "stop") if grid is None else control_at(grid, x, y)
        if kind is None:
            continue   # an uncontrolled junction: nothing stands there
        junctions.append({"c": [round(x, 1), round(y, 1)], "kind": kind, "legs": legs})
    stops = []
    for r in ([] if grid is not None else city["roads"]):
        if r["tier"] != "art":
            continue
        pts, carry = r["pts"], BUS_EVERY_M * 0.5
        for k in range(len(pts) - 1):
            ax, ay = pts[k]
            bx, by = pts[k + 1]
            seg = math.hypot(bx - ax, by - ay)
            t = carry
            while t < seg:
                dx, dy = (bx - ax) / seg, (by - ay) / seg
                off = r.get("w", 14.0) * 0.5 + 1.5
                stops.append({"c": [round(ax + dx * t - dy * off, 1), round(ay + dy * t + dx * off, 1)], "dir": [round(dx, 3), round(dy, 3)]})
                t += BUS_EVERY_M
            carry = t - seg
    json.dump({"format": "ganstoid.intersections", "junctions": junctions, "bus_stops": stops}, open(out_path, "w"), separators=(",", ":"))
    print("junctions %d (signals %d, stops %d), bus stops %d" % (len(junctions), sum(j["kind"] == "signal" for j in junctions), sum(j["kind"] == "stop" for j in junctions), len(stops)))


if __name__ == "__main__":
    main(*sys.argv[1:4])
