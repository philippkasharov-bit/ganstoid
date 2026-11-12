"""MF2: how high each freeway and ramp sits, from OSM layer / bridge tags, so
the renderer draws the top deck over the one beneath it (and a trench under
the street grid). Writes road["layer"] (int, 0 = ground, 1+ = up, -1 = below).

Usage: python3 -I road_layers.py <raw osm roads.json> <city_v1.json>   (city edited in place)
Run after osm_import / fix_roads (road ids carry the OSM way id: base:osm_w<id>_<n>).
"""
import json
import re
import sys

TIERS = ("fwy", "ramp")


def layer_of(tags):
    try:
        v = int(str(tags.get("layer", "")).split(";")[0])
    except ValueError:
        v = None
    if v is None:
        v = 1 if tags.get("bridge") not in (None, "no") else (-1 if tags.get("tunnel") not in (None, "no") else 0)
    return v


def main(raw_path, city_path):
    raw, city = json.load(open(raw_path)), json.load(open(city_path))
    tags = {e["id"]: e.get("tags", {}) for e in raw["elements"] if e["type"] == "way"}
    counts = {}
    for r in city["roads"]:
        if r["tier"] not in TIERS:
            continue
        m = re.match(r"base:osm_w(\d+)_", r["id"])
        lv = layer_of(tags.get(int(m.group(1)), {})) if m else 0
        r["layer"] = lv
        counts[lv] = counts.get(lv, 0) + 1
    json.dump(city, open(city_path, "w"), separators=(",", ":"))
    print("freeway/ramp pieces by layer:", dict(sorted(counts.items())))


if __name__ == "__main__":
    main(*sys.argv[1:3])
