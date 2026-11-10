"""MR5: the lanes as they really are.

The first import invented alleys by rule (mid-block lanes behind rows of houses)
and threw away the service lanes OpenStreetMap types as parking aisles,
driveways and drive-throughs. This makes the lane network the surveyed one:

  1. Generated alleys ("base:gen_alley*", 320 of them, 39 km) are deleted. The
     402 alleys mappers actually surveyed stay. A real alley that ended on an
     invented one is now a real dead end, and is recorded as one.
  2. Parking aisles become tier "aisle" (LA standard two-way aisle 24 ft =
     7.3 m, one-way 14 ft = 4.3 m); driveways and drive-throughs become tier
     "drive" (12 ft = 3.7 m; one-way 3.0 m). Lanes underground, in a tunnel or
     mostly inside a building (a parking garage) are left out: they are not on
     the ground.
Both new tiers are private ground: drawn, walkable by locals, never public.

Usage: python3 -I real_lanes.py <raw osm roads.json> <city_v1.json> <buildings_unjoined.json>   (city edited in place)
Run after fix_roads.py, before road_widths.py (which leaves these lanes' widths alone).
Data (c) OpenStreetMap contributors, ODbL.
"""
import json
import os
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # sibling tools; -I drops the script dir
import osm_import   # noqa: E402

LANE_TIER = {"parking_aisle": "aisle", "driveway": "drive", "drive-through": "drive"}
WIDTH = {("aisle", False): 7.3, ("aisle", True): 4.3, ("drive", False): 3.7, ("drive", True): 3.0}
MIN_LANE_M = 4.0
MAX_INSIDE_SHARE = 0.6     # a lane more than this much inside buildings is a garage ramp
TOUCH_M = 3.0


def is_on_ground(tags):
    if tags.get("tunnel") in ("yes", "building_passage") or tags.get("covered") == "yes":
        return tags.get("tunnel") == "building_passage"   # a passage under a building is still at street level
    try:
        return int(str(tags.get("layer", "0")).split(";")[0]) >= 0
    except ValueError:
        return True


def lanes(raw, blds, tree):
    out, skipped = [], 0
    for e in raw["elements"]:
        tags = e.get("tags", {})
        if e["type"] != "way" or tags.get("highway") != "service" or tags.get("service") not in LANE_TIER:
            continue
        pts = [osm_import.xy(p["lat"], p["lon"]) for p in e.get("geometry", [])]
        if len(pts) < 2:
            continue
        line = LineString(pts).intersection(osm_import.BOX)
        parts = [g for g in getattr(line, "geoms", [line]) if g.geom_type == "LineString" and g.length >= MIN_LANE_M]
        tier = LANE_TIER[tags["service"]]
        oneway = tags.get("oneway") in ("yes", "1", "-1")
        for k, part in enumerate(parts):
            inside = sum(part.intersection(blds[j]).length for j in tree.query(part))
            if not is_on_ground(tags) or inside > MAX_INSIDE_SHARE * part.length:
                skipped += 1
                continue
            out.append({"id": "base:osm_w%d_%s%d" % (e["id"], tier, k), "tier": tier, "cls": "service:" + tags["service"],
                        "w": WIDTH[(tier, oneway)], "side": 0.0,
                        "pts": [[round(x, 1), round(y, 1)] for x, y in part.coords]})
    return out, skipped


def new_dead_ends(city, gone_lines):
    """Ends of the remaining roads that touched only a deleted alley."""
    keep = [LineString(r["pts"]) for r in city["roads"]]
    tree = STRtree(keep)
    gone = STRtree(gone_lines) if gone_lines else None
    out = []
    for i, r in enumerate(city["roads"]):
        if r["tier"] not in ("alley", "res", "art", "hill"):
            continue
        for end in (Point(r["pts"][0]), Point(r["pts"][-1])):
            if gone is None or not any(gone_lines[j].distance(end) <= TOUCH_M for j in gone.query(end.buffer(TOUCH_M))):
                continue
            if not any(j != i and keep[j].distance(end) <= TOUCH_M for j in tree.query(end.buffer(TOUCH_M))):
                out.append([round(end.x, 1), round(end.y, 1)])
    return out


def main(raw_path, city_path, bld_path):
    raw, city = json.load(open(raw_path)), json.load(open(city_path))
    blds = [Polygon(b["poly"]).buffer(0) for b in json.load(open(bld_path))["buildings"]]
    tree = STRtree(blds)
    generated = [r for r in city["roads"] if r["id"].startswith("base:gen_alley")]
    city["roads"] = [r for r in city["roads"] if not r["id"].startswith("base:gen_alley")
                     and r["tier"] not in ("aisle", "drive")]   # re-runnable: old lanes out first
    ends = new_dead_ends(city, [LineString(r["pts"]) for r in generated])
    city["dead_ends"] = city.get("dead_ends", []) + ends
    added, skipped = lanes(raw, blds, tree)
    city["roads"] += added
    json.dump(city, open(city_path, "w"), separators=(",", ":"))
    km = lambda rs: sum(LineString(r["pts"]).length for r in rs) / 1000
    print("generated alleys deleted: %d (%.1f km); real alleys that now end there, recorded as dead ends: %d" % (len(generated), km(generated), len(ends)))
    print("real lanes added: %d parking aisles (%.1f km), %d driveways and drive-throughs (%.1f km); %d left out (underground or in a garage)" % (
        sum(r["tier"] == "aisle" for r in added), km([r for r in added if r["tier"] == "aisle"]),
        sum(r["tier"] == "drive" for r in added), km([r for r in added if r["tier"] == "drive"]), skipped))


if __name__ == "__main__":
    main(*sys.argv[1:4])
