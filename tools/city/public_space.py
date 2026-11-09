"""C3c: public space of the real city = what civilians may walk.

Public = sidewalks (strip beside every street, outside the roadway), crosswalks
(across every street arm at every junction), alleys, footpaths and parks, minus
buildings. Everything else (yards, lots, gaps between buildings) is NOT public:
it is trespass-walkable, used only by locals/crew/player (layer 2, see C3d).
Freeways and ramps have no sidewalks.

Usage: python3 -I public_space.py <city_v1.json> <buildings_v1.json> <out public_v1.json>
"""
import json
import math
import sys

from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

ROADWAY = {"art": 14.0, "res": 6.0}   # fallback widths; MP1 roads carry their own "w" / "side" (road_widths.py)
SIDEWALK_M = 2.5


def w_of(r):
    return r.get("w", ROADWAY[r["tier"]])


def side_of(r):
    return r.get("side", SIDEWALK_M) or SIDEWALK_M
ALLEY_HALF = 1.5
PATH_HALF = 1.25
CROSS_THICK = 2.5
CROSS_OFFSET = 2.5       # crosswalk centre sits this far beyond the crossing street's kerb
JUNCTION_MERGE_M = 8.0
CROSS_REACH_M = 40.0     # a crosswalk extends across medians/dual carriageways up to this far each way
AGENT_RADIUS_M = 0.42    # slightly above the nav agent radius (0.4)
MIN_ISLAND_M2 = 40.0     # walkable scraps smaller than this (after agent clearance) are dropped
SIMPLIFY_M = 0.15


def polys(geom):
    if geom.is_empty:
        return []
    return list(geom.geoms) if hasattr(geom, "geoms") else [geom]


def load(city_path, bld_path):
    city = json.load(open(city_path))
    blds = json.load(open(bld_path))["buildings"]
    return city, unary_union([Polygon(b["poly"]).buffer(0) for b in blds])


def street_lines(city):
    return [(r, LineString(r["pts"])) for r in city["roads"] if r["tier"] in ROADWAY]


def junctions(lines):
    """Points where streets cross or one ends on another, merged within JUNCTION_MERGE_M."""
    tree = STRtree([ln for _, ln in lines])
    raw = []
    for i, (_, a) in enumerate(lines):
        for j in tree.query(a.buffer(1.5)):
            if j <= i:
                continue
            b = lines[j][1]
            hit = a.intersection(b)
            if hit.is_empty:
                for end in (Point(a.coords[0]), Point(a.coords[-1])):
                    if b.distance(end) < 1.5:
                        raw.append(end)
                for end in (Point(b.coords[0]), Point(b.coords[-1])):
                    if a.distance(end) < 1.5:
                        raw.append(end)
            else:
                raw.extend(g.centroid for g in (hit.geoms if hasattr(hit, "geoms") else [hit]))
    merged, cell = [], {}
    for p in raw:
        key = (int(p.x // JUNCTION_MERGE_M), int(p.y // JUNCTION_MERGE_M))
        if not any(q.distance(p) < JUNCTION_MERGE_M for k in _near(key) for q in cell.get(k, [])):
            cell.setdefault(key, []).append(p)
            merged.append(p)
    return merged


def _near(key):
    return [(key[0] + dx, key[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)]


def crosswalks(lines, juncs, reach):
    """One crosswalk across each street arm leaving a junction."""
    tree = STRtree([ln for _, ln in lines])
    out = []
    for jp in juncs:
        near = [lines[k] for k in tree.query(jp.buffer(4.0)) if lines[k][1].distance(jp) < 4.0]
        if len(near) < 2:
            continue
        kerb = max(w_of(r) for r, _ in near) / 2 + CROSS_OFFSET
        for road, ln in near:
            s = ln.project(jp)
            for sign in (-1, 1):
                at = s + sign * kerb
                if at <= 0.5 or at >= ln.length - 0.5:
                    continue
                c, c2 = ln.interpolate(at), ln.interpolate(at + sign * 1.0)
                d = (c2.x - c.x, c2.y - c.y)
                n = math.hypot(*d) or 1.0
                dn = (d[0] / n, d[1] / n)
                c, length = span(c, dn, reach, w_of(road) + 2 * side_of(road))
                out.append({"c": [round(c.x, 1), round(c.y, 1)], "dir": [round(dn[0], 3), round(dn[1], 3)], "len": round(length, 1)})
    return out


def span(c, d, reach, default_len):
    """Stretch a crosswalk across the whole street corridor, medians included."""
    px, py = -d[1], d[0]
    probe = LineString([(c.x - px * CROSS_REACH_M, c.y - py * CROSS_REACH_M), (c.x + px * CROSS_REACH_M, c.y + py * CROSS_REACH_M)])
    for part in polys_of_lines(probe.intersection(reach)):
        if part.distance(c) < 0.1 and default_len <= part.length < 2 * CROSS_REACH_M - 1:
            return part.interpolate(0.5, normalized=True), part.length
    return c, default_len


def polys_of_lines(geom):
    return [g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "LineString"]


def crosswalk_poly(cw):
    dx, dy = cw["dir"]
    px, py = -dy, dx
    hl, ht = cw["len"] / 2, CROSS_THICK / 2
    cx, cy = cw["c"]
    return Polygon([(cx + px * hl + dx * ht, cy + py * hl + dy * ht), (cx - px * hl + dx * ht, cy - py * hl + dy * ht),
                    (cx - px * hl - dx * ht, cy - py * hl - dy * ht), (cx + px * hl - dx * ht, cy + py * hl - dy * ht)])


def street_reach(lines):
    return unary_union([ln.buffer(w_of(r) / 2 + side_of(r), cap_style=2) for r, ln in lines])


def sidewalk_ring(lines, reach):
    roadway = unary_union([ln.buffer(w_of(r) / 2, cap_style=2) for r, ln in lines])
    return reach.difference(roadway)


def alleys_and_paths(city):
    alley = [LineString(r["pts"]).buffer(ALLEY_HALF, cap_style=2) for r in city["roads"] if r["tier"] in ("alley", "svc")]
    path = [LineString(r["pts"]).buffer(PATH_HALF, cap_style=2) for r in city["roads"] if r["tier"] in ("path", "trail")]
    return unary_union(alley), unary_union(path)


def walkable_mask(public):
    """Drop slivers too thin for a person and tiny cut-off scraps (crosswalk stubs, median bits)."""
    keep = [g for g in polys(public.buffer(-AGENT_RADIUS_M)) if g.area >= MIN_ISLAND_M2]
    return unary_union(keep).buffer(AGENT_RADIUS_M + 0.05)


def zone_json(kind, geom):
    out = []
    for p in polys(geom.simplify(SIMPLIFY_M)):
        if p.area < 0.5:
            continue
        out.append({"kind": kind, "outer": [[round(x, 1), round(y, 1)] for x, y in p.exterior.coords],
                    "holes": [[[round(x, 1), round(y, 1)] for x, y in h.coords] for h in p.interiors]})
    return out


def main(city_path, bld_path, dst):
    city, bld = load(city_path, bld_path)
    lines = street_lines(city)
    juncs = junctions(lines)
    reach = street_reach(lines)
    cws = crosswalks(lines, juncs, reach)
    cross = unary_union([crosswalk_poly(c) for c in cws])
    walk = unary_union([sidewalk_ring(lines, reach), cross]).difference(bld)
    alley, path = alleys_and_paths(city)
    alley, path = alley.difference(bld), path.difference(bld)
    park = unary_union([Polygon(a["poly"]).buffer(0) for a in city["areas"] if a["kind"] == "park"]).difference(bld)
    mask = walkable_mask(unary_union([walk, alley, path, park]))
    walk, alley, path, park = (g.intersection(mask) for g in (walk, alley, path, park))
    zones = zone_json("sidewalk", walk) + zone_json("alley", alley) + zone_json("path", path) + zone_json("park", park)
    check(city, lines, unary_union([walk, alley, path, park]), len(juncs), len(cws))
    json.dump({"format": "ganstoid.public", "version": 1, "city": city["id"], "zones": zones, "crosswalks": cws},
              open(dst, "w"), separators=(",", ":"))
    print("wrote %s: %d zones, %d crosswalks" % (dst, len(zones), len(cws)))


def check(city, lines, public, n_junc, n_cw):
    """Every street must be reachable on public ground alone (civilians never need to trespass)."""
    comps = polys(public)
    comps.sort(key=lambda p: -p.area)
    tree = STRtree(comps)
    in_main = total = 0
    stranded = []
    for road, ln in lines:
        mid = ln.interpolate(0.5, normalized=True)
        near = [k for k in tree.query(mid.buffer(w_of(road) / 2 + side_of(road) + 1.0))]
        total += 1
        if any(k == 0 for k in near):
            in_main += 1
        else:
            stranded.append((round(mid.x), round(mid.y), road.get("name", "")))
    print("junctions %d, crosswalks %d, public components %d (largest %.0f%% of area)" % (
        n_junc, n_cw, len(comps), 100 * comps[0].area / sum(c.area for c in comps)))
    print("streets on the main public network: %d/%d (%.1f%%)" % (in_main, total, 100 * in_main / total))
    for s in stranded[:8]:
        print("  stranded:", s)
    assert in_main / total > 0.97, "streets cut off from the public network"


if __name__ == "__main__":
    main(*sys.argv[1:4])
