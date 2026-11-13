"""Turf map data (T1): the real city cut into street blocks, grouped into
named hoods and districts.

Blocks are the faces of the street network (streets, avenues, freeways and
the map edge; alleys and footpaths do not split a block). Each block gets a
gang-style name from the two streets it fronts most ("Daly & Main"), the
hood whose seed it is nearest to, and that hood's district. Hood seeds are
real Los Angeles neighbourhoods inside the map (approximate centres).

Usage: python3 -I tools/city/hoods.py data/city/city_v1.json data/city/hoods_v1.json
"""
import json, math, sys
from shapely.geometry import LineString, Polygon, box
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

S_LAT, W_LON, N_LAT, E_LON = 34.021, -118.2745, 34.075, -118.2095
LAT0 = (S_LAT + N_LAT) / 2
MX = 111320 * math.cos(math.radians(LAT0))
MY = 110540

def m(lat, lon):
    return ((lon - W_LON) * MX, (N_LAT - lat) * MY)

# district -> [(hood, lat, lon)]
SEEDS = {
    "Downtown": [("Bunker Hill", 34.0530, -118.2500), ("Civic Center", 34.0545, -118.2440), ("Historic Core", 34.0475, -118.2505),
                 ("Financial District", 34.0505, -118.2575), ("South Park", 34.0415, -118.2625), ("Fashion District", 34.0380, -118.2510),
                 ("Skid Row", 34.0435, -118.2430), ("Little Tokyo", 34.0505, -118.2395), ("Arts District", 34.0410, -118.2330),
                 ("Toy District", 34.0465, -118.2455), ("Produce District", 34.0320, -118.2400)],
    "Chinatown": [("Chinatown", 34.0625, -118.2385), ("Solano Canyon", 34.0705, -118.2330), ("Victor Heights", 34.0680, -118.2495)],
    "Echo Park": [("Angelino Heights", 34.0710, -118.2555), ("Temple-Beaudry", 34.0610, -118.2585)],
    "Westlake": [("Westlake", 34.0560, -118.2705), ("Pico-Union", 34.0450, -118.2720)],
    "Lincoln Heights": [("Lincoln Heights", 34.0690, -118.2135), ("Mission Junction", 34.0640, -118.2265)],
    "Boyle Heights": [("Pico Gardens", 34.0455, -118.2245), ("Aliso Village", 34.0525, -118.2265), ("Mariachi Plaza", 34.0470, -118.2185),
                      ("The Flats", 34.0365, -118.2255), ("Wyvernwood", 34.0285, -118.2165), ("Hollenbeck", 34.0560, -118.2165)],
    "Central-Alameda": [("Central-Alameda", 34.0255, -118.2460), ("Industrial District", 34.0280, -118.2340), ("Historic South-Central", 34.0300, -118.2600)],
}
SPLIT_TIERS = {"art", "res", "svc", "fwy", "hill", "ramp"}
MIN_AREA, MAX_AREA = 900.0, 400000.0

def main(city_path, out_path):
    city = json.load(open(city_path))
    size = city["size_m"]
    lines, named = [], []
    for r in city["roads"]:
        if r["tier"] not in SPLIT_TIERS or len(r["pts"]) < 2:
            continue
        ls = LineString(r["pts"])
        lines.append(ls)
        if r.get("name"):
            named.append((ls, r["name"]))
    edge = box(0, 0, size, size).exterior
    faces = [p for p in polygonize(unary_union(lines + [edge])) if MIN_AREA <= p.area <= MAX_AREA]
    seeds = [(h, d, m(lat, lon)) for d, hs in SEEDS.items() for h, lat, lon in hs]
    river = city.get("river", [])
    side = lambda x, y: _east_of_river(river, x, y)
    tree = STRtree([n[0] for n in named])
    blocks = []
    for i, f in enumerate(faces):
        f = f.simplify(0.8)
        c = f.representative_point()
        hood, _ = _nearest([s for s in seeds if side(*s[2]) == side(c.x, c.y)] or seeds, c)
        blocks.append({"id": i, "poly": [[round(x, 1), round(y, 1)] for x, y in list(f.exterior.coords)[:-1]],
                       "c": [round(c.x, 1), round(c.y, 1)], "hood": hood[0], "name": _name(f, tree, named)})
    _neighbours(blocks)
    streets = _streets(city, blocks)
    hoods = [{"name": h, "district": d} for d, hs in SEEDS.items() for h, _, _ in hs]
    json.dump({"format": "ganstoid.hoods", "version": 2, "districts": list(SEEDS.keys()), "hoods": hoods, "blocks": blocks, "streets": streets}, open(out_path, "w"))
    print("blocks", len(blocks), "hoods", len(hoods), "streets", len(streets))

def _east_of_river(river, x, y):
    """The LA River splits the map: a hood never reaches across it."""
    if len(river) < 2:
        return True
    for (x0, y0), (x1, y1) in zip(river, river[1:]):
        if min(y0, y1) <= y <= max(y0, y1) and y1 != y0:
            return x > x0 + (x1 - x0) * (y - y0) / (y1 - y0)
    return x > river[-1][0] if y > river[-1][1] else x > river[0][0]

def _nearest(seeds, c):
    best = min(seeds, key=lambda s: (c.x - s[2][0]) ** 2 + (c.y - s[2][1]) ** 2)
    return (best[0], best[1]), 0

def _name(face, tree, named):
    ring = face.exterior.buffer(4.0)
    share = {}
    for idx in tree.query(ring):
        ls, name = named[idx]
        share[name] = share.get(name, 0.0) + ls.intersection(ring).length
    top = [n for n, _ in sorted(share.items(), key=lambda kv: -kv[1])[:2]]
    short = [_plain(n) for n in top]
    return " & ".join(short) if short else "the block"

def _plain(n):
    for word in ("North ", "South ", "East ", "West "):
        if n.startswith(word):
            n = n[len(word):]
    return n.replace(" Street", "").replace(" Avenue", "").replace(" Boulevard", "").replace(" Road", "").replace(" Drive", "").replace(" Place", "")

def _unused(top):
    short = [n.replace(" Street", "").replace(" Avenue", "").replace(" Boulevard", "").replace(" Road", "").replace(" Drive", "") for n in top]
    return " & ".join(short) if short else "the block"

def _neighbours(blocks):
    polys = [Polygon(b["poly"]).buffer(9.0) for b in blocks]
    tree = STRtree(polys)
    for i, p in enumerate(polys):
        blocks[i]["next"] = [int(j) for j in tree.query(p) if j != i and polys[j].intersects(p)]

STREET_TIERS = {"art", "res", "hill"}
STRETCH_M = 320.0     # a street longer than this inside one hood is split into capture points
MIN_STRETCH_M = 45.0

def _streets(city, blocks):
    """Capture points: each named street's run through a hood, cut into
    stretches of at most STRETCH_M. Every block belongs to the stretch it
    fronts most; stretches next to each other (sharing a corner or a block)
    are neighbours."""
    from shapely.geometry import MultiLineString
    from shapely.ops import linemerge, substring
    by_hood = {}
    for b in blocks:
        by_hood.setdefault(b["hood"], []).append(Polygon(b["poly"]))
    areas = {h: unary_union(ps).buffer(14.0) for h, ps in by_hood.items()}
    lines = {}
    for r in city["roads"]:
        if r["tier"] in STREET_TIERS and r.get("name") and len(r["pts"]) > 1:
            lines.setdefault(_plain(r["name"]), []).append(LineString(r["pts"]))
    out = []
    for name, ls in lines.items():
        u = unary_union(ls)
        merged = linemerge(u) if u.geom_type == "MultiLineString" else u
        for hood, area in areas.items():
            part = merged.intersection(area)
            for piece in getattr(part, "geoms", [part]):
                if piece.geom_type != "LineString" or piece.length < MIN_STRETCH_M:
                    continue
                cuts = max(1, round(piece.length / STRETCH_M))
                for k in range(cuts):
                    seg = substring(piece, piece.length * k / cuts, piece.length * (k + 1) / cuts)
                    mid = seg.interpolate(0.5, normalized=True)
                    out.append({"id": len(out), "name": name, "hood": hood, "c": [round(mid.x, 1), round(mid.y, 1)],
                                "pts": [[round(x, 1), round(y, 1)] for x, y in seg.coords], "len": round(seg.length)})
    _front(blocks, out)
    _street_neighbours(out, blocks)
    return out

def _front(blocks, streets):
    """Each block joins the stretch (in its own hood) that runs along most of its edge."""
    geoms = [LineString(s["pts"]) for s in streets]
    tree = STRtree(geoms)
    for b in blocks:
        ring = Polygon(b["poly"]).exterior.buffer(12.0)
        best, best_len = -1, 0.0
        for i in tree.query(ring):
            if streets[i]["hood"] != b["hood"]:
                continue
            l = geoms[i].intersection(ring).length
            if l > best_len:
                best, best_len = int(i), l
        if best < 0:   # backstreets only: the nearest stretch in the hood
            c = Polygon(b["poly"]).centroid
            near = [i for i, s in enumerate(streets) if s["hood"] == b["hood"]]
            best = min(near, key=lambda i: geoms[i].distance(c)) if near else -1
        b["street"] = best

def _street_neighbours(streets, blocks):
    geoms = [LineString(s["pts"]).buffer(16.0) for s in streets]
    tree = STRtree(geoms)
    for i, g in enumerate(geoms):
        streets[i]["next"] = sorted({int(j) for j in tree.query(g) if j != i and geoms[j].intersects(g)})
    for b in blocks:   # stretches fronting neighbouring blocks touch too
        for n in b["next"]:
            a, c = b["street"], blocks[n]["street"]
            if a >= 0 and c >= 0 and a != c and c not in streets[a]["next"]:
                streets[a]["next"].append(c)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
