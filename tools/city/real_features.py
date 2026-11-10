"""MR2: what is really on the ground in central LA, straight from OpenStreetMap.

The first import took roads, buildings and a few land-use areas and invented the
rest by rule. This reads the full extract and keeps what mappers actually
surveyed, so a block looks like the block that is there:

  surfaces  parking lots, plazas and pedestrian squares, grass, gardens, sports
            pitches, playgrounds, school and hospital grounds, cemeteries,
            construction sites, rail yards, water
  barriers  fences, walls, hedges, gates
  trees     individually mapped trees
  points    traffic signals, stop signs, bus stops, street lamps, hydrants,
            benches
  crossings real marked crossings (with their marking style, and signals)
  sidewalks real sidewalk centre lines, where mapped
  lanes     what each service road really is: driveway, parking aisle, alley

Output data/city/real_v1.json. Nothing here is generated: a thing is in the
file only if it is in OpenStreetMap. Data (c) OpenStreetMap contributors, ODbL.
Usage: python3 -I real_features.py <osm extract .json, or the folder of osm_c*.json cells> <out real_v1.json>
"""
import glob
import json
import os
import sys
from collections import Counter

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # sibling tools; -I drops the script dir
import osm_import   # noqa: E402

MIN_SURFACE_M2 = 30.0
SIMPLIFY_M = 0.3

# (tag key, tag value) -> surface kind. First match wins.
SURFACES = [
    (("amenity", "parking"), "parking"), (("amenity", "parking_space"), None), (("landuse", "garages"), "parking"),
    (("highway", "pedestrian"), "plaza"), (("place", "square"), "plaza"), (("leisure", "plaza"), "plaza"),
    (("leisure", "pitch"), "pitch"), (("leisure", "track"), "pitch"), (("leisure", "sports_centre"), "sports"),
    (("leisure", "stadium"), "sports"), (("leisure", "playground"), "playground"),
    (("leisure", "garden"), "garden"), (("leisure", "dog_park"), "grass"), (("leisure", "park"), "park"),
    (("landuse", "grass"), "grass"), (("landuse", "village_green"), "grass"), (("landuse", "recreation_ground"), "grass"),
    (("natural", "grassland"), "grass"), (("natural", "scrub"), "scrub"), (("natural", "wood"), "wood"), (("landuse", "forest"), "wood"),
    (("landuse", "cemetery"), "cemetery"), (("amenity", "grave_yard"), "cemetery"),
    (("amenity", "school"), "school"), (("amenity", "college"), "school"), (("amenity", "university"), "school"),
    (("amenity", "kindergarten"), "school"), (("amenity", "hospital"), "hospital"),
    (("landuse", "construction"), "construction"), (("landuse", "brownfield"), "vacant"), (("landuse", "railway"), "railyard"),
    (("natural", "water"), "water"), (("landuse", "basin"), "water"), (("leisure", "swimming_pool"), "pool"),
    (("natural", "sand"), "sand"), (("natural", "bare_rock"), "sand"),
]
BARRIERS = {"fence": "fence", "wall": "wall", "retaining_wall": "wall", "hedge": "hedge", "guard_rail": "rail", "gate": "gate", "city_wall": "wall"}
POINTS = [(("highway", "traffic_signals"), "signal"), (("highway", "stop"), "stop"), (("highway", "bus_stop"), "bus_stop"),
          (("highway", "street_lamp"), "lamp"), (("emergency", "fire_hydrant"), "hydrant"), (("amenity", "bench"), "bench"),
          (("highway", "crossing"), None), (("amenity", "waste_basket"), "bin"), (("amenity", "vending_machine"), None)]


def kind_of(tags, table):
    for (key, value), kind in table:
        if tags.get(key) == value:
            return kind
    return None


def ring(geometry):
    return [osm_import.xy(p["lat"], p["lon"]) for p in geometry]


def on_map(pts):
    return any(0 <= x <= osm_import.SIZE and 0 <= y <= osm_import.SIZE for x, y in pts)


def r1(pts):
    return [[round(x, 1), round(y, 1)] for x, y in pts]


def polygons_of(element):
    """Closed way, or the outer rings of a multipolygon minus its inner rings."""
    if element["type"] == "way":
        pts = ring(element.get("geometry", []))
        return [Polygon(pts).buffer(0)] if len(pts) >= 4 and pts[0] == pts[-1] else []
    outers, inners = [], []
    for m in element.get("members", []):
        pts = ring(m.get("geometry", []))
        if len(pts) >= 4 and pts[0] == pts[-1]:
            (inners if m.get("role") == "inner" else outers).append(Polygon(pts).buffer(0))
    if not outers:
        return []
    return [unary_union(outers).difference(unary_union(inners)) if inners else unary_union(outers)]


def surfaces(elements):
    out, count = [], Counter()
    for e in elements:
        if e["type"] == "node":
            continue
        kind = kind_of(e.get("tags", {}), SURFACES)
        if kind is None or e.get("tags", {}).get("parking") in ("underground", "multi-storey", "rooftop"):
            continue
        for geom in polygons_of(e):
            geom = geom.intersection(osm_import.BOX)
            for p in getattr(geom, "geoms", [geom]):
                if p.geom_type != "Polygon" or p.area < MIN_SURFACE_M2:
                    continue
                p = p.simplify(SIMPLIFY_M)
                out.append({"kind": kind, "poly": r1(list(p.exterior.coords)[:-1]),
                            "holes": [r1(list(h.coords)[:-1]) for h in p.interiors]})
                count[kind] += 1
    return out, count


def lines(elements):
    barriers, crossings, sidewalks, lanes = [], [], [], {}
    for e in elements:
        if e["type"] != "way":
            continue
        tags = e.get("tags", {})
        pts = ring(e.get("geometry", []))
        if len(pts) < 2 or not on_map(pts):
            continue
        if tags.get("barrier") in BARRIERS:
            barriers.append({"kind": BARRIERS[tags["barrier"]], "pts": r1(pts)})
        elif tags.get("highway") == "footway" and tags.get("footway") == "crossing":
            crossings.append({"pts": r1(pts), "markings": tags.get("crossing:markings", tags.get("crossing", "")),
                              "signals": tags.get("crossing:signals") == "yes" or tags.get("crossing") == "traffic_signals"})
        elif tags.get("highway") == "footway" and tags.get("footway") == "sidewalk":
            sidewalks.append(r1(pts))
        elif tags.get("highway") == "service" and tags.get("service"):
            lanes[str(e["id"])] = tags["service"]
    return barriers, crossings, sidewalks, lanes


def nodes(elements):
    trees, points, count = [], [], Counter()
    for e in elements:
        if e["type"] != "node":
            continue
        tags = e.get("tags", {})
        x, y = osm_import.xy(e["lat"], e["lon"])
        if not (0 <= x <= osm_import.SIZE and 0 <= y <= osm_import.SIZE):
            continue
        if tags.get("natural") == "tree":
            trees.append([round(x, 1), round(y, 1)])
            continue
        kind = kind_of(tags, POINTS)
        if kind:
            points.append({"kind": kind, "p": [round(x, 1), round(y, 1)]})
            count[kind] += 1
    return trees, points, count


def load(src):
    """One extract file, or a folder of osm_c*.json cells (things on a seam are in two cells: kept once)."""
    paths = sorted(glob.glob(os.path.join(src, "osm_c*.json"))) if os.path.isdir(src) else [src]
    seen, out = set(), []
    for path in paths:
        for e in json.load(open(path, encoding="utf-8"))["elements"]:
            key = (e["type"], e["id"])
            if key not in seen:
                seen.add(key)
                out.append(e)
    return out


def main(src, dst):
    elements = load(src)
    surf, surf_n = surfaces(elements)
    barriers, crossings, sidewalks, lanes = lines(elements)
    trees, points, point_n = nodes(elements)
    json.dump({"format": "ganstoid.real", "version": 1, "source": "(c) OpenStreetMap contributors, ODbL",
               "surfaces": surf, "barriers": barriers, "trees": trees, "points": points,
               "crossings": crossings, "sidewalks": sidewalks, "lanes": lanes}, open(dst, "w"), separators=(",", ":"))
    walk_km = sum(LineString(s).length for s in sidewalks) / 1000
    print("wrote %s (%d OSM elements read)" % (dst, len(elements)))
    print("  surfaces %d: %s" % (len(surf), ", ".join("%s %d" % kv for kv in surf_n.most_common())))
    print("  barriers %d (%s)" % (len(barriers), ", ".join("%s %d" % kv for kv in Counter(b["kind"] for b in barriers).most_common())))
    print("  trees %d; points %d: %s" % (len(trees), len(points), ", ".join("%s %d" % kv for kv in point_n.most_common())))
    print("  real crossings %d (with signals %d); real sidewalk lines %d (%.1f km); typed service lanes %d (%s)" % (
        len(crossings), sum(c["signals"] for c in crossings), len(sidewalks), walk_km, len(lanes),
        ", ".join("%s %d" % kv for kv in Counter(lanes.values()).most_common(4))))


if __name__ == "__main__":
    main(*sys.argv[1:3])
