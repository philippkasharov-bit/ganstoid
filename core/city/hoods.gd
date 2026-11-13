## T1: the turf map as Los Angeles knows it: the city's street blocks (the
## faces between its streets), each named for the streets it fronts ("Daly
## & Main"), grouped into real neighbourhoods (hoods) and districts
## (tools/city/hoods.py builds data/city/hoods_v1.json). Turf, block money
## and police budgets are all held per block. A block key is Vector2i(id,
## BLOCK_Y); a point on a street belongs to the nearest block.
class_name Hoods
extends RefCounted

const PATH := "res://data/city/hoods_v1.json"
const BLOCK_Y := -100000      # marks a key as a block (x is its id), never a grid cell
const GRID_M := 80.0
const NEAREST_M := 90.0       # further than this from every block: no block (the old grid takes over)

static var _data: Hoods
static var _tried := false

var blocks: Array[Dictionary] = []   # {poly: PackedVector2Array, c: Vector2, hood: String, name: String, next: PackedInt32Array}
var districts: Dictionary = {}       # hood name -> district name
var _grid: Dictionary = {}           # Vector2i -> PackedInt32Array of block ids

## The city's blocks and hoods (null when the file is missing).
static func data() -> Hoods:
	if not _tried:
		_tried = true
		_data = _load()
	return _data

static func _load() -> Hoods:
	if not FileAccess.file_exists(PATH):
		return null
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var h := Hoods.new()
	for d in raw["hoods"]:
		h.districts[d["name"]] = d["district"]
	for b in raw["blocks"]:
		var poly := PackedVector2Array()
		for p in b["poly"]:
			poly.append(Vector2(p[0], p[1]))
		h.blocks.append({"poly": poly, "c": Vector2(b["c"][0], b["c"][1]), "hood": b["hood"], "name": b["name"], "next": PackedInt32Array(b["next"])})
		var key := Vector2i((Vector2(b["c"][0], b["c"][1]) / GRID_M).floor())
		if not h._grid.has(key):
			h._grid[key] = PackedInt32Array()
		h._grid[key].append(h.blocks.size() - 1)
	return h

static func is_block(key: Vector2i) -> bool:
	return key.y == BLOCK_Y

## The block at `p` (the one it stands in, else the nearest), or (-1, BLOCK_Y).
func key_of(p: Vector2) -> Vector2i:
	var c := Vector2i((p / GRID_M).floor())
	var best := -1
	var best_d := NEAREST_M * NEAREST_M
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for i in _grid.get(Vector2i(x, y), PackedInt32Array()):
				if Geometry2D.is_point_in_polygon(p, blocks[i]["poly"]):
					return Vector2i(i, BLOCK_Y)
				var d: float = (blocks[i]["c"] as Vector2).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = i
	return Vector2i(best, BLOCK_Y)

func block(key: Vector2i) -> Dictionary:
	return blocks[key.x] if is_block(key) and key.x >= 0 and key.x < blocks.size() else {}

func neighbours(key: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in block(key).get("next", PackedInt32Array()):
		out.append(Vector2i(i, BLOCK_Y))
	return out

## "Daly & Main" / "Pico Gardens" / "Boyle Heights" for where `key` is.
func name_of(key: Vector2i) -> String:
	return block(key).get("name", "")

func hood_of(key: Vector2i) -> String:
	return block(key).get("hood", "")

func district_of(key: Vector2i) -> String:
	return districts.get(hood_of(key), "")

var _centres: Dictionary = {}

## Each hood's middle (the average of its blocks), for its name on the map.
func hood_centres() -> Dictionary:
	if _centres.is_empty():
		var sums := {}
		for b in blocks:
			var s: Array = sums.get(b["hood"], [Vector2.ZERO, 0])
			sums[b["hood"]] = [s[0] + b["c"], s[1] + 1]
		for name in sums:
			_centres[name] = sums[name][0] / sums[name][1]
	return _centres
