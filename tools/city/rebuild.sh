#!/usr/bin/env bash
# Rebuilds every derived city file from city_v1.json + buildings_unjoined.json, in
# the one order that works. Run after any change to roads or raw buildings.
#   tools/city/rebuild.sh [raw osm roads.json] [godot binary]
# (osm_import / fix_roads / real_lanes / road_widths are the steps before this; they
#  need the raw OSM extract and are run by hand when the road network itself changes.)
set -euo pipefail
RAW="${1:-/home/claude/osm_raw/dtla_6km.json}"
GODOT="${2:-/tmp/godot_bin/Godot_v4.7.2-stable_linux.x86_64}"
cd "$(dirname "$0")"
D=../../data/city
step() { echo; echo "== $*"; }
step "buildings off the roads, overlaps apart"; python3 -I fix_buildings.py $D/city_v1.json buildings_unjoined.json "$RAW"
step "join rows of buildings";                 python3 -I join_buildings.py buildings_unjoined.json $D/city_v1.json $D/buildings_v1.json
step "doors";                                  python3 -I doors.py $D/city_v1.json $D/buildings_v1.json
step "public space (sidewalks, crosswalks)";   python3 -I public_space.py $D/city_v1.json $D/buildings_v1.json $D/public_v1.json
step "street cross-section";                   python3 -I street_section.py $D/city_v1.json $D/buildings_v1.json $D/public_v1.json $D/section_v1.json
step "nav shapes: everything walkable";        python3 -I nav_obstacles.py $D/city_v1.json $D/buildings_v1.json nav_obstacles.json
step "nav shapes: public ground";              python3 -I nav_public.py $D/public_v1.json "$(python3 -I -c "import json;print(json.load(open('$D/city_v1.json'))['size_m'])")" nav_public.json $D/city_v1.json $D/section_v1.json $D/buildings_v1.json $D/parcels_v1.json
cd ../..
step "intersections";      python3 -I tools/city/intersections.py "$D/city_v1.json" "$D/intersections_v1.json"
step "bake full navmesh";    "$GODOT" --headless --path . -s tools/city/bake_navmesh.gd 2>&1 | grep -E "baked|unbakeable|SCRIPT ERROR" || true
step "bake public navmesh";  "$GODOT" --headless --path . -s tools/city/bake_public_navmesh.gd 2>&1 | grep -E "baked|unbakeable|SCRIPT ERROR" || true
echo; echo "done: now run debug/run_all.sh"
