## MR2: what is really on the ground, as surveyed (OpenStreetMap) and as recorded
## (LA County Assessor parcels). Loaded beside CityData; every list is empty when
## its file is missing, so the game still runs on the older data alone.
##   surfaces   {kind, poly}            parking lots, plazas, grass, pitches, school grounds ...
##   lots       {use, poly}             real property lines and what the county says is on them
##   barriers   {kind, pts}             fences, walls, hedges
##   trees      PackedVector2Array      individually mapped trees
##   points     {kind, p}               signals, stop signs, bus stops, lamps, hydrants, benches
##   crossings  {pts, markings, signals} real marked crossings
class_name CityReal
extends RefCounted

const REAL_PATH := "res://data/city/real_v1.json"
const PARCELS_PATH := "res://data/city/parcels_v1.json"

var surfaces: Array[Dictionary] = []
var lots: Array[Dictionary] = []
var barriers: Array[Dictionary] = []
var trees := PackedVector2Array()
var points: Array[Dictionary] = []
var crossings: Array[Dictionary] = []

static var _loaded: CityReal

## The surveyed city, read once and shared (the view, the lights and the sim all ask).
static func load_files() -> CityReal:
	if _loaded == null:
		_loaded = _read_all()
	return _loaded

static func _read_all() -> CityReal:
	var real := CityReal.new()
	var raw: Dictionary = _read(REAL_PATH, "ganstoid.real")
	for s in raw.get("surfaces", []):
		real.surfaces.append({"kind": String(s["kind"]), "poly": _pts(s["poly"])})
	for b in raw.get("barriers", []):
		real.barriers.append({"kind": String(b["kind"]), "pts": _pts(b["pts"])})
	real.trees = _pts(raw.get("trees", []))
	for p in raw.get("points", []):
		real.points.append({"kind": String(p["kind"]), "p": Vector2(p["p"][0], p["p"][1])})
	for c in raw.get("crossings", []):
		real.crossings.append({"pts": _pts(c["pts"]), "markings": String(c["markings"]), "signals": bool(c["signals"])})
	for lot in _read(PARCELS_PATH, "ganstoid.parcels").get("parcels", []):
		real.lots.append({"use": String(lot["use"]), "poly": _pts(lot["poly"])})
	return real

static func _read(path: String, format: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY or raw.get("format") != format:
		push_error("CityReal: %s is not a %s file" % [path, format])
		return {}
	return raw

static func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out
