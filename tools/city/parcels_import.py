"""MR2: real lot lines. Imports the LA County Assessor parcels for the map area.

Every parcel is a real piece of land with what the county says is on it. Output
data/city/parcels_v1.json:
  parcels: [{id, poly, use, desc, year, units}]
    use   one of house, apartments, commercial, industrial, civic, parking,
          vacant, open, other  (from the Assessor's UseType / UseDescription)
    desc  the Assessor's own description ("Stores", "Five or more apartments", ...)
    year  year the main building was built (0 if unknown)
    units dwelling units on the lot
It also gives buildings their real use: with --buildings the "kind" of every
building in buildings_unjoined.json is replaced by the use of the parcel it
stands on (OSM leaves 2,396 buildings untyped and guesses many others).

Source: Los Angeles County Assessor parcel layer (public GIS). Coordinates are
projected exactly as osm_import.py does, so parcels line up with the streets.
Usage: python3 -I parcels_import.py <dir with page_N.json> <out parcels_v1.json> [--buildings buildings_unjoined.json]
"""
import glob
import json
import os
import sys

from shapely.geometry import Polygon, box, shape
from shapely.strtree import STRtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # sibling tools; -I drops the script dir
import osm_import   # noqa: E402

SIMPLIFY_M = 0.2
MIN_PARCEL_M2 = 20.0
MIN_ON_MAP = 0.5          # a parcel must be at least half inside the map to count

# (UseType, words in UseDescription) -> use. First match wins; description beats type.
BY_WORDS = [
    (("parking",), "parking"),
    (("vacant",), "vacant"),
    (("single", "two units", "three units", "four units", "double", "duplex", "mobile", "manufactured"), "house"),
    (("five or more", "apartment", "rooming", "boarding", "condominium", "own-your-own", "hotel", "motel"), "apartments"),
    (("warehous", "manufactur", "industrial", "lumber", "food processing", "packing", "mineral", "wrecking", "open storage"), "industrial"),
    (("church", "school", "college", "hospital", "government", "library", "museum", "cemeter", "utility", "institution", "home for aged"), "civic"),
    (("park", "golf", "recreation", "athletic", "stadium", "open space"), "open"),
    (("store", "office", "shopping", "restaurant", "bank", "service", "auto", "theater", "club", "market", "commercial", "professional", "wholesale", "nurser", "bowling"), "commercial"),
]
BY_TYPE = {"residential": "house", "commercial": "commercial", "industrial": "industrial", "government": "civic",
           "institutional": "civic", "recreational": "open", "miscellaneous": "other"}
# Parcel use -> building kind, where the parcel says more than OSM did.
KIND_OF_USE = {"house": "house", "apartments": "apartments", "commercial": "commercial", "industrial": "industrial", "civic": "civic"}


def use_of(props):
    desc = (props.get("UseDescription") or "").lower()
    for words, use in BY_WORDS:
        if any(w in desc for w in words):
            return use
    return BY_TYPE.get((props.get("UseType") or "").lower(), "other")


def to_map(geom):
    """GeoJSON geometry (lon, lat) -> shapely polygons in map metres."""
    out = []
    g = shape(geom)
    for part in getattr(g, "geoms", [g]):
        if part.geom_type != "Polygon":
            continue
        ring = [osm_import.xy(lat, lon) for lon, lat in part.exterior.coords]
        holes = [[osm_import.xy(lat, lon) for lon, lat in h.coords] for h in part.interiors]
        p = Polygon(ring, holes).buffer(0)
        out.extend(q for q in getattr(p, "geoms", [p]) if q.geom_type == "Polygon")
    return out


def load(pages_dir):
    seen, parcels = set(), []
    for path in sorted(glob.glob(os.path.join(pages_dir, "page_*.json"))):
        for f in json.load(open(path, encoding="utf-8-sig"))["features"]:
            props = f["properties"]
            if props["OBJECTID"] in seen or not f.get("geometry"):
                continue
            seen.add(props["OBJECTID"])
            for k, p in enumerate(to_map(f["geometry"])):
                inside = p.intersection(osm_import.BOX)
                if p.area < MIN_PARCEL_M2 or inside.area < MIN_ON_MAP * p.area:
                    continue
                p = p.simplify(SIMPLIFY_M)
                parcels.append(({"id": "lot:%s_%d" % (props.get("AIN") or props["OBJECTID"], k), "use": use_of(props),
                                 "desc": (props.get("UseDescription") or "").strip(), "year": int(props.get("YearBuilt1") or 0),
                                 "units": int(props.get("Units1") or 0)}, p))
    return parcels


def retype_buildings(bld_path, parcels):
    """Each building takes the use of the parcel under its middle."""
    raw = json.load(open(bld_path))
    tree = STRtree([p for _, p in parcels])
    changed = typed = 0
    for b in raw["buildings"]:
        mid = Polygon(b["poly"]).buffer(0).representative_point()
        hits = [k for k in tree.query(mid) if parcels[k][1].contains(mid)]
        if not hits:
            continue
        info = parcels[min(hits, key=lambda k: parcels[k][1].area)][0]
        kind = KIND_OF_USE.get(info["use"])
        if kind is None or b["kind"] == "garage":
            continue
        typed += int(b["kind"] == "building")
        changed += int(b["kind"] != kind)
        b["kind"] = kind
        if info["year"]:
            b["year"] = info["year"]
    json.dump(raw, open(bld_path, "w"), separators=(",", ":"))
    print("buildings given their parcel's real use: %d changed kind, of them %d had no kind at all" % (changed, typed))


def main(pages_dir, dst, *rest):
    parcels = load(pages_dir)
    out = []
    for info, p in parcels:
        info["poly"] = [[round(x, 1), round(y, 1)] for x, y in list(p.exterior.coords)[:-1]]
        out.append(info)
    json.dump({"format": "ganstoid.parcels", "version": 1, "source": "Los Angeles County Assessor parcels (public GIS)", "parcels": out},
              open(dst, "w"), separators=(",", ":"))
    by_use = {}
    for info, p in parcels:
        by_use.setdefault(info["use"], [0, 0.0])
        by_use[info["use"]][0] += 1
        by_use[info["use"]][1] += p.area
    covered = sum(a for _, a in by_use.values())
    print("wrote %s: %d parcels covering %.0f%% of the map" % (dst, len(out), 100 * covered / osm_import.BOX.area))
    for use, (n, a) in sorted(by_use.items(), key=lambda kv: -kv[1][1]):
        print("  %-11s %6d lots  %5.1f ha" % (use, n, a / 1e4))
    if len(rest) == 2 and rest[0] == "--buildings":
        retype_buildings(rest[1], parcels)


if __name__ == "__main__":
    main(*sys.argv[1:])
