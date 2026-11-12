## MP3a: street junctions (signals, stop signs) and bus stops, from
## data/city/intersections_v1.json. Pure data + the signal clock.
## A signal gives the leg pair nearest east-west GREEN_S of green, YELLOW_S of
## amber, then the other pair; every junction's cycle starts at its own offset.
class_name Junctions
extends RefCounted

const PATH := "res://data/city/intersections_v1.json"
const CELL_M := 60.0
const GREEN_S := 24.0
const YELLOW_S := 4.0
const CYCLE_S := (GREEN_S + YELLOW_S) * 2.0

var list: Array = []        # {c: Vector2, kind, legs: [[dir: Vector2, w, tier]], offset}
var bus_stops: Array = []   # {c: Vector2, dir: Vector2}
var _grid := {}

static func load_file(path: String = PATH) -> Junctions:
	var j := Junctions.new()
	if not FileAccess.file_exists(path):
		return j
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		return j
	for x in raw.get("junctions", []):
		var legs: Array = []
		for l in x["legs"]:
			legs.append([Vector2(l[0], l[1]), float(l[2]), String(l[3])])
		var c := Vector2(x["c"][0], x["c"][1])
		var item := {"c": c, "kind": String(x["kind"]), "legs": legs, "offset": float(absi(hash(c)) % 1000) / 1000.0 * CYCLE_S}
		j.list.append(item)
		var key := Vector2i((c / CELL_M).floor())
		if not j._grid.has(key):
			j._grid[key] = []
		j._grid[key].append(item)
	for b in raw.get("bus_stops", []):
		j.bus_stops.append({"c": Vector2(b["c"][0], b["c"][1]), "dir": Vector2(b["dir"][0], b["dir"][1])})
	return j

## Junctions within `r` metres of `p`.
func near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var lo := Vector2i(((p - Vector2(r, r)) / CELL_M).floor())
	var hi := Vector2i(((p + Vector2(r, r)) / CELL_M).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for j in _grid.get(Vector2i(x, y), []):
				if j["c"].distance_to(p) <= r:
					out.append(j)
	return out

## "green", "yellow" or "red" for someone driving in direction `heading_dir` into junction `j` at `seconds`.
static func light(j: Dictionary, heading_dir: Vector2, seconds: float) -> String:
	var t := fposmod(seconds + j["offset"], CYCLE_S)
	var east_west := absf(heading_dir.x) >= absf(heading_dir.y)
	var phase := t if east_west else fposmod(t - (GREEN_S + YELLOW_S), CYCLE_S)
	if phase < GREEN_S:
		return "green"
	if phase < GREEN_S + YELLOW_S:
		return "yellow"
	return "red"
