"""Import a real Los Angeles slice from OpenStreetMap into the Ganstoid city format.
Source data: Overpass export (highways, rail, river, landuse, parks) for a 6x6 km box
around Downtown LA: Downtown, Skid Row, Arts District, LA River + rail yards,
Boyle Heights, Chinatown, Echo Park / Elysian Park hills, Westlake, Pico-Union.
Data (c) OpenStreetMap contributors, ODbL. Usage: python3 osm_import.py <overpass.json> <out.json>"""
import json
import math
import sys

from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

S_LAT, W_LON, N_LAT, E_LON = 34.021, -118.2745, 34.075, -118.2095
LAT0 = (S_LAT + N_LAT) / 2
MX = 111320 * math.cos(math.radians(LAT0))
MY = 110540
SIZE = round(min((E_LON - W_LON) * MX, (N_LAT - S_LAT) * MY))   # square map: crop the longer side
BOX = box(0, 0, SIZE, SIZE)

HIGHWAY_TIER = {
    "motorway": "fwy", "motorway_link": "ramp", "trunk": "art", "trunk_link": "ramp",
    "primary": "art", "primary_link": "art", "secondary": "art", "secondary_link": "art",
    "tertiary": "res", "residential": "res", "unclassified": "res", "living_street": "res",
    "pedestrian": "path", "steps": "path", "path": "path", "track": "trail",
}
LANDUSE_KIND = {"industrial": "industrial", "railway": "industrial", "commercial": "commercial", "retail": "commercial"}


def xy(lat, lon):
    return ((lon - W_LON) * MX, (N_LAT - lat) * MY)


def tier_of(tags):
    hw = tags.get("highway")
    if hw == "service":
        return {"alley": "alley", None: "svc"}.get(tags.get("service"))   # drop parking aisles, driveways
    if hw == "footway":
        return "path" if tags.get("footway") in (None, "link") else None   # drop sidewalks, crossings
    return HIGHWAY_TIER.get(hw)


def pieces(geom):
    g = LineString(geom).intersection(BOX)
    for h in getattr(g, "geoms", [g]):
        if not h.is_empty and h.geom_type == "LineString" and h.length > 1:
            yield [[round(x, 1), round(y, 1)] for x, y in h.simplify(0.8).coords]


def main(src, dst, bsrc=None):
    els = json.load(open(src))["elements"]
    roads, rail, river, areas = [], [], [], []
    for e in els:
        tags, geom = e.get("tags", {}), [xy(p["lat"], p["lon"]) for p in e.get("geometry", [])]
        if len(geom) < 2:
            continue
        tier = tier_of(tags) if "highway" in tags else None
        if tier:
            for pts in pieces(geom):
                r = {"id": "base:osm_w%d_%d" % (e["id"], len(roads)), "tier": tier, "pts": pts}
                if tags.get("name"):
                    r["name"] = tags["name"]
                roads.append(r)
        elif tags.get("railway") == "rail":
            rail += list(pieces(geom))
        elif tags.get("waterway") in ("river", "canal"):
            river += list(pieces(geom))
        elif geom[0] == geom[-1] and len(geom) > 3:
            kind = LANDUSE_KIND.get(tags.get("landuse")) or ("park" if tags.get("leisure") == "park" else None)
            poly = Polygon(geom).buffer(0).intersection(BOX)
            for p in getattr(poly, "geoms", [poly]):
                if kind and p.geom_type == "Polygon" and p.area > 400:
                    areas.append({"id": "base:osm_a%d_%d" % (e["id"], len(areas)), "kind": kind,
                                  "poly": [[round(x, 1), round(y, 1)] for x, y in p.simplify(1.0).exterior.coords]})
    buildings = load_buildings(bsrc) if bsrc else []
    roads += block_alleys(roads, areas, clear_of(buildings))
    if bsrc:
        roads, buildings = reconcile_alleys(roads, buildings)
        bdst = dst.replace("city_v1.json", "buildings_v1.json")
        json.dump({"format": "ganstoid.buildings", "version": 1, "attribution": "(c) OpenStreetMap contributors, ODbL",
                   "buildings": buildings}, open(bdst, "w"), separators=(",", ":"))
        print("buildings %d -> %s" % (len(buildings), bdst))
    dead_ends, dark = loose_ends(roads), dark_spots(roads, rail)
    river_line = max(river, key=lambda p: LineString(p).length) if river else []
    data = {"format": "ganstoid.city", "version": 1, "id": "base:city", "size_m": float(SIZE),
            "source": "OpenStreetMap", "attribution": "(c) OpenStreetMap contributors, ODbL",
            "roads": roads, "areas": areas, "river": river_line, "rail": rail,
            "dead_ends": dead_ends, "dark_spots": dark, "spawn": [round(c, 1) for c in xy(34.0445, -118.2185)]}
    json.dump(data, open(dst, "w"), separators=(",", ":"))
    print("size %d m, roads %d, rail %d, areas %d, dead ends %d, dark spots %d" % (SIZE, len(roads), len(rail), len(areas), len(dead_ends), len(dark)))


def block_alleys(roads, areas, clear=lambda g: True):
    """Gameplay: give every city block deep enough for two rows of lots an alley
    down its long axis (if it has none), ending on the block's own streets."""
    edges = [LineString(r["pts"]) for r in roads if r["tier"] in ("fwy", "ramp", "art", "res")]
    alleys = [LineString(r["pts"]) for r in roads if r["tier"] == "alley"]
    alley_tree = STRtree(alleys)
    parks = unary_union([Polygon(a["poly"]) for a in areas if a["kind"] == "park" and len(a["poly"]) > 3]).buffer(0)
    out = []
    for block in polygonize(unary_union(edges)):
        if not (3000 < block.area < 120000) or parks.contains(block.centroid):
            continue
        inner = block.buffer(-6)
        if inner.is_empty or any(alleys[j].intersects(inner) for j in alley_tree.query(inner)):
            continue
        rect = list(block.minimum_rotated_rectangle.exterior.coords)
        sides = [(rect[k], rect[k + 1]) for k in range(4)]
        long_a, long_b = max(sides, key=lambda e: math.dist(*e))
        short = min(math.dist(*e) for e in sides)
        if short < 50:
            continue   # too shallow for lots on both sides of an alley
        c = block.centroid
        d = ((long_b[0] - long_a[0]) / math.dist(long_a, long_b), (long_b[1] - long_a[1]) / math.dist(long_a, long_b))
        n = (-d[1], d[0])
        L = math.dist(long_a, long_b)
        # follow the real gap between buildings: try lines across the block, centre first
        for off in sorted(range(-int(short * 0.35), int(short * 0.35) + 1, 3), key=abs):
            ox, oy = c.x + n[0] * off, c.y + n[1] * off
            line = LineString([(ox - d[0] * L, oy - d[1] * L), (ox + d[0] * L, oy + d[1] * L)]).intersection(block)
            h = max((g for g in getattr(line, "geoms", [line]) if g.geom_type == "LineString"), key=lambda g: g.length, default=None)
            if h is not None and h.length > 40 and clear(h):
                out.append({"id": "base:gen_alley_%d" % len(out), "tier": "alley", "generated": True,
                            "pts": [[round(x, 1), round(y, 1)] for x, y in h.coords]})
                out += alley_forks(h, block, d, len(out), clear)
                break
    print("generated block alleys incl. forks:", len(out))
    return out


def alley_forks(alley, block, d, n0, clear=lambda g: True):
    """Split alleys into 2 ways: 1-2 branches (T or angled Y) that run out to the
    block's side street, so the alley network has forks and more ways out."""
    rnd = __import__("random").Random(n0)
    out = []
    want = rnd.choice((0, 1, 1, 2))
    for _ in range(12):
        if len(out) >= want:
            break
        q = alley.interpolate(rnd.uniform(0.25, 0.75), normalized=True)
        side = rnd.choice((-1, 1))
        ang = math.radians(rnd.choice((0, 0, 30, -30)))       # T fork or angled Y fork
        px_, py_ = -d[1] * side, d[0] * side
        bx = px_ * math.cos(ang) - py_ * math.sin(ang)
        by = px_ * math.sin(ang) + py_ * math.cos(ang)
        ray = LineString([(q.x, q.y), (q.x + bx * 400, q.y + by * 400)]).intersection(block)
        seg = ray if ray.geom_type == "LineString" else next((g for g in getattr(ray, "geoms", []) if g.geom_type == "LineString" and g.distance(q) < 0.5), None)
        if seg is not None and 12 < seg.length < 90 and clear(seg):
            out.append({"id": "base:gen_alley_%d_f%d" % (n0, len(out)), "tier": "alley", "generated": True,
                        "pts": [[round(x, 1), round(y, 1)] for x, y in seg.coords]})
    return out


BUILDING_KIND = {
    "house": "house", "detached": "house", "residential": "house", "semidetached_house": "house", "bungalow": "house",
    "terrace": "house", "apartments": "apartments", "dormitory": "apartments",
    "commercial": "commercial", "retail": "commercial", "office": "commercial", "hotel": "commercial", "supermarket": "commercial",
    "industrial": "industrial", "warehouse": "industrial", "manufacture": "industrial",
    "garage": "garage", "garages": "garage", "shed": "garage", "carport": "garage", "roof": "garage",
    "church": "civic", "school": "civic", "university": "civic", "hospital": "civic", "public": "civic",
    "civic": "civic", "government": "civic", "fire_station": "civic", "police": "civic",
}


def load_buildings(src):
    out = []
    for e in json.load(open(src))["elements"]:
        geom = [xy(p["lat"], p["lon"]) for p in e.get("geometry", [])]
        if len(geom) < 4 or geom[0] != geom[-1]:
            continue
        tags = e.get("tags", {})
        poly = Polygon(geom).buffer(0).intersection(BOX)
        for p in getattr(poly, "geoms", [poly]):
            if p.geom_type != "Polygon" or p.area < 8:
                continue
            try:
                levels = int(float(tags.get("building:levels", 0))) or round(float(tags.get("height", 0)) / 3.5)
            except ValueError:
                levels = 0
            out.append({"id": "base:bld_%d_%d" % (e["id"], len(out)), "kind": BUILDING_KIND.get(tags.get("building"), "building"),
                        "levels": max(1, levels), "poly": [[round(x, 1), round(y, 1)] for x, y in p.simplify(0.4).exterior.coords]})
    return out


def clear_of(buildings):
    """Test: does a 2.4 m wide corridor along this line avoid real buildings?
    (Sheds/garages under 60 m2 don't count: they get removed.)"""
    polys = [Polygon(b["poly"]) for b in buildings]
    tree = STRtree(polys) if polys else None

    def clear(g):
        if tree is None:
            return True
        corridor = g.buffer(1.2)
        return all(polys[j].area < 60 or buildings[j]["kind"] == "garage"
                   for j in tree.query(corridor) if polys[j].intersects(corridor))
    return clear


def reconcile_alleys(roads, buildings):
    """Generated alleys may not run through real buildings. Small sheds/garages in
    the way are removed; if a real building blocks it, the alley piece is dropped.
    Then forks/alleys left hanging are dropped until every alley end meets a road."""
    polys = [Polygon(b["poly"]) for b in buildings]
    tree = STRtree(polys)
    remove_b, keep = set(), []
    for r in roads:
        if not r.get("generated"):
            keep.append(r)
            continue
        corridor = LineString(r["pts"]).buffer(1.2)
        hits = [j for j in tree.query(corridor) if polys[j].intersects(corridor)]
        if all(polys[j].area < 60 or buildings[j]["kind"] == "garage" for j in hits):
            remove_b.update(hits)
            keep.append(r)
    for _ in range(5):
        geoms = [LineString(r["pts"]) for r in keep]
        t2 = STRtree(geoms)
        nxt = []
        for i, r in enumerate(keep):
            if r.get("generated") and not all(
                    any(j != i and geoms[j].distance(Point(e)) < 3 for j in t2.query(Point(e).buffer(3)))
                    for e in (r["pts"][0], r["pts"][-1])):
                continue
            nxt.append(r)
        if len(nxt) == len(keep):
            break
        keep = nxt
    print("alleys kept %d of %d generated; sheds removed %d" % (
        sum(1 for r in keep if r.get("generated")), sum(1 for r in roads if r.get("generated")), len(remove_b)))
    return keep, [b for k, b in enumerate(buildings) if k not in remove_b]


def loose_ends(roads):
    """Real dead ends (cul-de-sacs, alley ends): street/alley ends touching no other road.
    Service roads and footpaths are left out: they end at parking lots and sidewalks."""
    geoms = [LineString(r["pts"]) for r in roads]
    tree = STRtree(geoms)
    out = []
    for i, r in enumerate(roads):
        if r["tier"] not in ("res", "alley") or r["pts"][0] == r["pts"][-1]:
            continue
        for e in (r["pts"][0], r["pts"][-1]):
            if min(e[0], e[1], SIZE - e[0], SIZE - e[1]) < 12:
                continue
            p = Point(e)
            if not any(j != i and geoms[j].distance(p) < 3 for j in tree.query(p.buffer(3))):
                out.append(e)
    return out


def dark_spots(roads, rail):
    """Underpasses (boulevards crossing freeways) and rail-yard points."""
    fw = [LineString(r["pts"]) for r in roads if r["tier"] == "fwy"]
    tree = STRtree(fw)
    spots = []
    for r in roads:
        if r["tier"] != "art":
            continue
        g = LineString(r["pts"])
        for j in tree.query(g):
            x = g.intersection(fw[j])
            for h in getattr(x, "geoms", [x]):
                if not x.is_empty and h.geom_type == "Point" and all(math.dist((h.x, h.y), s) > 60 for s in spots):
                    spots.append([round(h.x, 1), round(h.y, 1)])
    for line in rail:
        g = LineString(line)
        for k in range(1, int(g.length // 400)):
            q = g.interpolate(k * 400)
            if all(math.dist((q.x, q.y), s) > 150 for s in spots):
                spots.append([round(q.x, 1), round(q.y, 1)])
    return spots


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
