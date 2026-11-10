## City batch C1: the fixed city (real central LA from OpenStreetMap) loaded from
## frozen data (data/city/city_v1.json, produced by tools/city/osm_import.py).
## Pure data: no drawing, no game rules. All IDs are namespaced ("base:...")
## so mods and expansions can add regions without renumbering the base city.
class_name CityData
extends RefCounted

const FORMAT := "ganstoid.city"
const SUPPORTED_VERSION := 1
const DEFAULT_PATH := "res://data/city/city_v1.json"
const BUILDINGS_PATH := "res://data/city/buildings_v1.json"
const PUBLIC_PATH := "res://data/city/public_v1.json"
const SECTION_PATH := "res://data/city/section_v1.json"
const TIERS: Array[String] = ["fwy", "ramp", "art", "res", "alley", "path", "svc", "hill", "trail"]

var size_m: float = 0.0
var roads: Array[Dictionary] = []   # {id: StringName, tier: String, name?: String, pts: PackedVector2Array}
var areas: Array[Dictionary] = []   # {id: StringName, kind: String, poly: PackedVector2Array}
var river := PackedVector2Array()
var rail: Array[PackedVector2Array] = []
var dead_ends := PackedVector2Array()
var dark_spots := PackedVector2Array()
var spawn := Vector2.ZERO
var buildings: Array[Dictionary] = []   # {id: StringName, kind: String, levels: int, poly: PackedVector2Array, door: Vector2}
var public_zones: Array[Dictionary] = []   # civilians may walk here: {kind: sidewalk|alley|path|park, outer, holes: Array[PackedVector2Array]}
var crosswalks: Array[Dictionary] = []   # {c: Vector2, dir: Vector2, len: float}
# MP2 street cross-section. Each road also gets "walk" (paving) and "park" (parkway) per side.
var kerb_m := 0.15                       # kerb lip at the roadway edge, metres
var well_r := 0.6                        # tree well / tree pit radius
var tree_wells := PackedVector2Array()   # centres of the pits MP5 plants trees in
var driveways: Array[Dictionary] = []    # cuts across the band: {c: Vector2 (on the kerb), dir: Vector2 (outward), w, len}
var kerb_ramps: Array[Dictionary] = []   # ramps at crosswalk ends, same shape (not freeway ramps)

static func load_file(path: String = DEFAULT_PATH) -> CityData:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("CityData: cannot read %s" % path)
		return null
	var raw: Variant = JSON.parse_string(text)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("CityData: %s is not a JSON object" % path)
		return null
	var city := CityData.new()
	var err := city._parse(raw)
	if err != "":
		push_error("CityData: %s: %s" % [path, err])
		return null
	city._load_buildings(BUILDINGS_PATH)
	city._load_public(PUBLIC_PATH)
	city._load_section(SECTION_PATH)
	return city

func _load_buildings(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY or raw.get("format") != "ganstoid.buildings":
		push_error("CityData: %s is not a buildings file" % path)
		return
	for b in raw.get("buildings", []):
		var poly := _pts(b["poly"])
		var door: Vector2 = Vector2(b["door"][0], b["door"][1]) if b.has("door") else poly[0]   # door: just outside the wall, facing the street
		buildings.append({"id": StringName(b["id"]), "kind": String(b["kind"]), "levels": int(b.get("levels", 1)), "poly": poly, "door": door})

func _load_public(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY or raw.get("format") != "ganstoid.public":
		push_error("CityData: %s is not a public-space file" % path)
		return
	for z in raw.get("zones", []):
		var holes: Array[PackedVector2Array] = []
		for h in z["holes"]:
			holes.append(_pts(h))
		public_zones.append({"kind": String(z["kind"]), "outer": _pts(z["outer"]), "holes": holes})
	for c in raw.get("crosswalks", []):
		crosswalks.append({"c": Vector2(c["c"][0], c["c"][1]), "dir": Vector2(c["dir"][0], c["dir"][1]), "len": float(c["len"])})

## MP2: splits each road's sidewalk band into parkway + paving and loads the
## features sitting on it (tree wells, driveway cuts, kerb ramps).
func _load_section(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY or raw.get("format") != "ganstoid.section":
		push_error("CityData: %s is not a street-section file" % path)
		return
	kerb_m = float(raw.get("kerb_m", kerb_m))
	well_r = float(raw.get("well_r", well_r))
	var by_id: Dictionary = raw.get("roads", {})
	for road in roads:
		var sec: Variant = by_id.get(String(road["id"]))
		if typeof(sec) == TYPE_DICTIONARY:
			road["walk"] = float(sec["walk"])
			road["park"] = float(sec["park"])
	tree_wells = _pts(raw.get("wells", []))
	driveways = _band_features(raw.get("aprons", []))
	kerb_ramps = _band_features(raw.get("ramps", []))

static func _band_features(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in list:
		out.append({"c": Vector2(f["c"][0], f["c"][1]), "dir": Vector2(f["dir"][0], f["dir"][1]),
			"w": float(f["w"]), "len": float(f["len"])})
	return out

func roads_of(tier: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for road in roads:
		if road["tier"] == tier:
			out.append(road)
	return out

func _parse(raw: Dictionary) -> String:
	if raw.get("format") != FORMAT:
		return "wrong format"
	if int(raw.get("version", 0)) != SUPPORTED_VERSION:
		return "unsupported version %s" % raw.get("version")
	size_m = float(raw.get("size_m", 0.0))
	if size_m <= 0.0:
		return "size_m missing"
	var err := _parse_roads(raw.get("roads", []))
	if err != "":
		return err
	for a in raw.get("areas", []):
		areas.append({"id": StringName(a["id"]), "kind": String(a["kind"]), "poly": _pts(a["poly"])})
	river = _pts(raw.get("river", []))
	for line in raw.get("rail", []):
		rail.append(_pts(line))
	dead_ends = _pts(raw.get("dead_ends", []))
	dark_spots = _pts(raw.get("dark_spots", []))
	var s: Array = raw.get("spawn", [0, 0])
	spawn = Vector2(s[0], s[1])
	return ""

func _parse_roads(list: Array) -> String:
	for r in list:
		var tier: String = r.get("tier", "")
		if not TIERS.has(tier):
			return "road %s has unknown tier '%s'" % [r.get("id"), tier]
		var road := {"id": StringName(r["id"]), "tier": tier, "pts": _pts(r["pts"])}
		if r.has("name"):
			road["name"] = String(r["name"])
		if r.has("w"):   # MP1: true roadway width (kerb to kerb) and sidewalk+parkway per side, metres
			road["w"] = float(r["w"])
			road["side"] = float(r.get("side", 0.0))
		roads.append(road)
	return ""

static func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out
