"""MP1: true road widths from real LA street standards + OSM lane counts.

Adds to every road in city_v1.json:
  "w"    roadway width, kerb to kerb (m)
  "side" sidewalk + parkway width on each side (m), 0 where there is none
  "cls"  OSM highway class (and "lanes" when tagged)
Widths follow the City of LA street designations (Complete Street Design Manual
E-211-213): Boulevard I 30.5 m roadway / 5.5 m sides, Boulevard II 24.4 / 4.6,
Avenue I 21.3 / 4.6, Avenue II 17.1 / 4.6, Avenue III 14.0 / 4.0,
Collector 12.2 / 4.0, Local 11.0 / 3.7, Local Limited 9.1 / 3.0, alley 6.1.
Roadway = lanes x 3.35 m (11 ft) + 2.45 m (8 ft) parking per kerb side
(+ a 3.35 m centre turn lane on 4+ lane two-way major streets), clamped to the
class's LA range. One-way ways (one side of a divided boulevard, or a one-way
street) get their own lanes + one parking side. Freeways: 3.66 m lanes + 3 m
shoulders, no sidewalk.
Where real buildings stand closer than the standard allows (old narrow streets
and alleys, or OSM centre lines a little off), the roadway is narrowed to the
clearance most of the street actually has (20th percentile of building
distance sampled every 5 m), never below the tier's minimum.
MR3: with the Assessor parcels given, a street is then also fitted between the real
property lines on either side of it (fit_to_lots), which is the true right of way.
Usage: python3 -I road_widths.py <raw osm roads.json> <city_v1.json> <buildings_v1.json> [parcels_v1.json]   (city edited in place)
"""
import json
import sys

LANE_M, PARK_M, TURN_M, FWY_LANE_M, FWY_SHOULDER_M = 3.35, 2.45, 3.35, 3.66, 3.0
# class -> (default lanes, min roadway, max roadway, side width, side width when 6+ lanes)
CLASSES = {
    "primary": (4, 17.1, 30.5, 4.6, 5.5),
    "secondary": (4, 14.0, 24.4, 4.6, 4.6),
    "tertiary": (2, 12.2, 21.3, 4.0, 4.0),
    "residential": (2, 9.1, 12.2, 3.7, 3.7),
    "unclassified": (2, 9.1, 12.2, 3.0, 3.0),
    "living_street": (1, 6.0, 9.1, 3.0, 3.0),
}
LINK_OF = {"primary_link": "primary", "secondary_link": "secondary", "tertiary_link": "tertiary"}
FIXED = {"alley": (6.1, 0.0), "svc": (6.0, 0.0), "path": (2.5, 0.0), "trail": (2.0, 0.0)}


def lanes_of(tags, default):
    try:
        return max(1, int(str(tags.get("lanes", default)).split(";")[0]))
    except ValueError:
        return default


def width_for(tier, tags):
    hw = tags.get("highway", "")
    oneway = tags.get("oneway") in ("yes", "1", "-1") or tags.get("junction") == "roundabout"
    if tier in ("fwy", "ramp"):
        lanes = lanes_of(tags, 4 if tier == "fwy" else 1)
        return lanes * FWY_LANE_M + (FWY_SHOULDER_M if tier == "fwy" else 2.0), 0.0
    if tier in FIXED:
        return FIXED[tier]
    cls = CLASSES.get(LINK_OF.get(hw, hw), CLASSES["residential"])
    default_lanes, lo, hi, side, side_wide = cls
    lanes = lanes_of(tags, max(1, default_lanes // 2) if oneway else default_lanes)
    if oneway:
        return round(min(hi, lanes * LANE_M + PARK_M), 1), side
    turn = TURN_M if lanes >= 4 and hw in ("primary", "secondary") else 0.0
    roadway = min(hi, max(lo, lanes * LANE_M + 2 * PARK_M + turn))
    return round(roadway, 1), (side_wide if lanes >= 6 else side)


MIN_W = {"art": 9.0, "res": 6.0, "alley": 3.5, "svc": 3.5, "hill": 6.0}
SAMPLE_M = 5.0


def clearance_cap(line, tree, blds):
    """Twice the 20th-percentile distance from the centre line to the nearest building."""
    dists = []
    for k in range(int(line.length // SAMPLE_M) + 1):
        p = line.interpolate(k * SAMPLE_M)
        near = tree.query(p.buffer(20.0))
        d = min((blds[j].distance(p) for j in near), default=20.0)
        if d > 0.0:   # inside a building = tunnel/arcade: not a width limit
            dists.append(d)
    if not dists:
        return None
    dists.sort()
    return 2.0 * dists[len(dists) // 5] - 0.4


OWN_WIDTH = ("aisle", "drive")
LOT_REACH_M = 45.0
LOT_PERCENTILE = 0.3
MIN_SIDE_M = 1.2
LOT_TIERS = ("art", "res", "hill", "alley")


def lot_half_width(line, lot_tree, lots):
    """How far the street really reaches from its centre line: the distance to the
    nearest property line, taken as the 30th percentile along the street (junctions
    and open ground have no lot nearby and would otherwise stretch it)."""
    dists = []
    for k in range(int(line.length // SAMPLE_M) + 1):
        p = line.interpolate(k * SAMPLE_M)
        d = min((lots[j].distance(p) for j in lot_tree.query(p.buffer(LOT_REACH_M))), default=None)
        if d is not None and d > 0.5:   # 0 = the line runs across a lot (a private road): no evidence
            dists.append(d)
    if len(dists) < 3:
        return None
    dists.sort()
    return dists[int(len(dists) * LOT_PERCENTILE)]


def fit_to_lots(road, half):
    """MR3: the roadway plus its sidewalk may not reach past the real property line.
    The roadway gives way first, down to the tier's minimum; then the sidewalk does."""
    w, side = road["w"], road["side"]
    if half is None or w / 2 + side <= half + 0.3:
        return False
    w = 2 * (half - side)
    if w < MIN_W[road["tier"]]:
        w = MIN_W[road["tier"]]
        side = max(MIN_SIDE_M, half - w / 2) if side > 0 else 0.0
        if road["tier"] == "alley":
            w = max(3.0, min(w, 2 * half))
    road["w"], road["side"] = round(w, 1), round(side, 1)
    return True


def main(raw_path, city_path, bld_path, parcels_path=None):
    from shapely.geometry import LineString, Polygon
    from shapely.strtree import STRtree
    blds = [Polygon(b["poly"]).buffer(0) for b in json.load(open(bld_path))["buildings"]]
    tree = STRtree(blds)
    lots = [Polygon(l["poly"]).buffer(0) for l in json.load(open(parcels_path))["parcels"]] if parcels_path else []
    lot_tree = STRtree(lots) if lots else None
    fitted = 0
    tags_by_way = {e["id"]: e.get("tags", {}) for e in json.load(open(raw_path))["elements"] if e["type"] == "way"}
    city = json.load(open(city_path))
    found = 0
    for r in city["roads"]:
        if r["tier"] in OWN_WIDTH:
            continue   # real_lanes.py sized these from LA lot standards
        way = None
        if r["id"].startswith("base:osm_w"):
            way = int(r["id"][len("base:osm_w"):].split("_")[0])
        tags = tags_by_way.get(way, {})
        found += int(bool(tags))
        r["w"], r["side"] = width_for(r["tier"], tags)
        if r["tier"] in MIN_W:
            cap = clearance_cap(LineString(r["pts"]), tree, blds)
            if cap is not None and cap < r["w"]:
                r["w"] = round(max(MIN_W[r["tier"]], cap), 1)
        if lot_tree is not None and r["tier"] in LOT_TIERS:
            fitted += int(fit_to_lots(r, lot_half_width(LineString(r["pts"]), lot_tree, lots)))
        if tags.get("highway"):
            r["cls"] = tags["highway"]
        if "lanes" in tags:
            r["lanes"] = tags["lanes"]
    json.dump(city, open(city_path, "w"), separators=(",", ":"))
    by_tier = {}
    for r in city["roads"]:
        by_tier.setdefault(r["tier"], []).append(r["w"])
    print("roads %d, matched to OSM tags %d" % (len(city["roads"]), found))
    if lot_tree is not None:
        print("streets narrowed to fit between the real property lines: %d" % fitted)
    for t, ws in sorted(by_tier.items()):
        ws.sort()
        print("  %-6s n=%5d  roadway m: min %.1f  median %.1f  max %.1f" % (t, len(ws), ws[0], ws[len(ws) // 2], ws[-1]))


if __name__ == "__main__":
    main(*sys.argv[1:5])
