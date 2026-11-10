"""MC2: buildings that stand on roads, and buildings that overlap each other.

OpenStreetMap draws a building's whole outline even where a street runs under
it (a skybridge, a parking deck over an alley, an archway) and draws parking
garages with their service lanes inside. On a flat map that puts walls across
streets. This pass makes the ground plan honest:

  1. Streets always win. Where an arterial, residential or hill road crosses a
     building, the roadway (plus the kerb) is cut out of the building. What is
     left on either side stays as separate buildings.
  2. Alleys and service lanes tagged as a passage (tunnel / building_passage /
     covered) get a PASSAGE_M wide gap cut through the building the same way.
  3. Alleys and service lanes that are NOT a tagged passage but run inside a
     building (garage ramps, loading docks drawn indoors) are trimmed back to
     the wall instead: the lane ends where the building begins.
  4. Two buildings overlapping by more than OVERLAP_M2: the smaller is dropped
     if it sits mostly inside the bigger (a roof part drawn twice); otherwise
     the overlap is cut out of the bigger one.
  5. Scraps under MIN_PART_M2 left by a cut are dropped (small sheds that were
     never cut are kept).

Usage: python3 -I fix_buildings.py <city_v1.json> <buildings_unjoined.json> <raw osm roads.json>   (first two edited in place)
Run after road_widths.py (needs "w"), before join_buildings.py.
"""
import json
import sys

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

STREET_TIERS = ("art", "res", "hill")
LANE_TIERS = ("alley", "svc")
KERB_M = 0.3
PASSAGE_M = 4.0
MIN_CROSS_M2 = 1.0        # ignore a road merely brushing a wall
MIN_PART_M2 = 12.0
MIN_INSIDE_M = 2.0        # a lane must run this far inside a building to be trimmed
MIN_LANE_M = 6.0          # a trimmed lane shorter than this is dropped
OVERLAP_M2 = 2.0
INSIDE_SHARE = 0.6


def polys(geom):
    return [g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "Polygon" and not g.is_empty]


def lines(geom):
    return [g for g in getattr(geom, "geoms", [geom]) if g.geom_type == "LineString" and g.length > 0]


def way_tags(raw_path):
    return {e["id"]: e.get("tags", {}) for e in json.load(open(raw_path))["elements"] if e["type"] == "way"}


def tags_of(road, tags):
    if not road["id"].startswith("base:osm_w"):
        return {}
    return tags.get(int(road["id"][len("base:osm_w"):].split("_")[0]), {})


def is_passage(t):
    return t.get("tunnel") in ("yes", "building_passage") or t.get("covered") in ("yes", "arcade", "colonnade")


def carve(city, blds, tags):
    """Steps 1-3. Returns (new building list, counts)."""
    shapes = [Polygon(b["poly"]).buffer(0) for b in blds]
    tree = STRtree(shapes)
    cuts = {}          # building index -> [corridor polygons]
    trim = {}          # road index -> [building polygons]
    n = {"street": 0, "passage": 0, "trimmed": 0}
    for ri, road in enumerate(city["roads"]):
        tier = road["tier"]
        if tier not in STREET_TIERS + LANE_TIERS or len(road["pts"]) < 2:
            continue
        line = LineString(road["pts"])
        w = float(road.get("w", 6.0))
        passage = tier in LANE_TIERS and is_passage(tags_of(road, tags))
        if tier in STREET_TIERS:
            corridor = line.buffer(w / 2 + KERB_M, cap_style=2)
        else:
            corridor = line.buffer(min(w, PASSAGE_M) / 2 + 0.2, cap_style=2)
        for bi in tree.query(corridor):
            if shapes[bi].intersection(corridor).area < MIN_CROSS_M2:
                continue
            if tier in STREET_TIERS or passage:
                cuts.setdefault(int(bi), []).append(corridor)
                n["street" if tier in STREET_TIERS else "passage"] += 1
            elif line.intersection(shapes[bi]).length >= MIN_INSIDE_M:
                # only when the lane itself runs inside: one that merely passes close to a
                # wall is left alone (and a second run of this tool then changes nothing)
                trim.setdefault(ri, []).append(shapes[bi])
    out = []
    for bi, b in enumerate(blds):
        if bi not in cuts:
            out.append((b, shapes[bi]))
            continue
        parts = [p for p in polys(shapes[bi].difference(unary_union(cuts[bi]))) if p.area >= MIN_PART_M2]
        for k, p in enumerate(parts):
            nb = dict(b)
            if len(parts) > 1:
                nb["id"] = "%s_p%d" % (b["id"], k)
            out.append((nb, p))
    roads = []
    for ri, road in enumerate(city["roads"]):
        if ri not in trim:
            roads.append(road)
            continue
        n["trimmed"] += 1
        left = [g for g in lines(LineString(road["pts"]).difference(unary_union(trim[ri]).buffer(0.2))) if g.length >= MIN_LANE_M]
        for k, g in enumerate(left):
            nr = dict(road)
            nr["pts"] = [[round(x, 1), round(y, 1)] for x, y in g.coords]
            if len(left) > 1:
                nr["id"] = "%s_t%d" % (road["id"], k)
            roads.append(nr)
    city["roads"] = roads
    return out, n


def unoverlap(items):
    """Step 4 on [(building, polygon)]. Returns (items, dropped, cut)."""
    shapes = [p for _, p in items]
    tree = STRtree(shapes)
    gone, dropped, cut = set(), 0, 0
    order = sorted(range(len(shapes)), key=lambda i: shapes[i].area)   # small ones first
    for i in order:
        if i in gone:
            continue
        for j in tree.query(shapes[i]):
            j = int(j)
            if j == i or j in gone or shapes[j].area < shapes[i].area:
                continue
            both = shapes[i].intersection(shapes[j]).area
            if both <= OVERLAP_M2:
                continue
            if both >= INSIDE_SHARE * shapes[i].area:
                gone.add(i)
                dropped += 1
                break
            rest = [p for p in polys(shapes[j].difference(shapes[i].buffer(0.05))) if p.area >= MIN_PART_M2]
            if rest:
                shapes[j] = max(rest, key=lambda p: p.area)
                cut += 1
    return [(b, shapes[k]) for k, (b, _) in enumerate(items) if k not in gone], dropped, cut


def main(city_path, bld_path, raw_path):
    city, raw = json.load(open(city_path)), json.load(open(bld_path))
    before = len(raw["buildings"])
    items, n = carve(city, raw["buildings"], way_tags(raw_path))
    items, dropped, cut = unoverlap(items)
    out = []
    for b, p in items:
        if p.is_empty:
            continue
        b["poly"] = [[round(x, 1), round(y, 1)] for x, y in list(p.exterior.coords)[:-1]]
        out.append(b)
    raw["buildings"] = out
    json.dump(city, open(city_path, "w"), separators=(",", ":"))
    json.dump(raw, open(bld_path, "w"), separators=(",", ":"))
    print("buildings %d -> %d" % (before, len(out)))
    print("  streets cut through buildings: %d crossings; tagged passages opened: %d" % (n["street"], n["passage"]))
    print("  lanes trimmed back to the wall: %d" % n["trimmed"])
    print("  overlapping pairs: %d smaller ones dropped, %d cut apart" % (dropped, cut))


if __name__ == "__main__":
    main(*sys.argv[1:4])
