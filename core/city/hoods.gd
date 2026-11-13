## T1: the turf map as Los Angeles knows it: the city's street blocks (the
## faces between its streets), each named for the streets it fronts ("Daly
## & Main"), grouped into real neighbourhoods (hoods) and districts
## (tools/city/hoods.py builds data/city/hoods_v1.json). Block money and
## police budgets are held per block; T2: turf is held per STREET: each
## named street's run through a hood (cut into stretches of ~300 m) is a
## capture point, and every block belongs to the street it fronts. A block
## key is Vector2i(id, BLOCK_Y), a street Vector2i(id, STREET_Y); a point
## on a road belongs to the nearest block (and so to its street).
class_name Hoods
extends RefCounted

const PATH := "res://data/city/hoods_v1.json"
const BLOCK_Y := -100000      # marks a key as a block (x is its id), never a grid cell
const STREET_Y := -200000     # T2: marks a key as a street (capture point)
const GRID_M := 80.0
const NEAREST_M := 90.0       # further than this from every block: no block (the old grid takes over)

static var _data: Hoods
static var _tried := false

var blocks: Array[Dictionary] = []   # {poly: PackedVector2Array, c: Vector2, hood: String, name: String, next: PackedInt32Array, street: int}
var streets: Array[Dictionary] = []  # T2: {name, hood, c: Vector2, pts: PackedVector2Array, next: PackedInt32Array}
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
		h.blocks.append({"poly": poly, "c": Vector2(b["c"][0], b["c"][1]), "hood": b["hood"], "name": b["name"], "next": PackedInt32Array(b["next"]), "street": int(b.get("street", -1))})
		var key := Vector2i((Vector2(b["c"][0], b["c"][1]) / GRID_M).floor())
		if not h._grid.has(key):
			h._grid[key] = PackedInt32Array()
		h._grid[key].append(h.blocks.size() - 1)
	for st in raw.get("streets", []):
		var pts := PackedVector2Array()
		for p in st["pts"]:
			pts.append(Vector2(p[0], p[1]))
		h.streets.append({"name": st["name"], "hood": st["hood"], "c": Vector2(st["c"][0], st["c"][1]), "pts": pts, "next": PackedInt32Array(st["next"])})
	return h

static func is_street(key: Vector2i) -> bool:
	return key.y == STREET_Y

## T2: the street (capture point) `p` belongs to, or (-1, STREET_Y).
func street_of(p: Vector2) -> Vector2i:
	var b := block(key_of(p))
	return Vector2i(int(b.get("street", -1)), STREET_Y)

func street(key: Vector2i) -> Dictionary:
	return streets[key.x] if is_street(key) and key.x >= 0 and key.x < streets.size() else {}

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

## A block's or a street's dictionary, whichever the key is.
func place(key: Vector2i) -> Dictionary:
	return street(key) if is_street(key) else block(key)

func neighbours(key: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in place(key).get("next", PackedInt32Array()):
		out.append(Vector2i(i, key.y))
	return out

## "Daly & Main" / "Pico Gardens" / "Boyle Heights" for where `key` is.
func name_of(key: Vector2i) -> String:
	return place(key).get("name", "")

func hood_of(key: Vector2i) -> String:
	return place(key).get("hood", "")

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

var _street_blocks: Dictionary = {}

## T2: the blocks that belong to street `key` (its turf on the map).
func blocks_of(key: Vector2i) -> Array:
	if _street_blocks.is_empty():
		for i in blocks.size():
			var sid: int = blocks[i]["street"]
			if not _street_blocks.has(sid):
				_street_blocks[sid] = []
			_street_blocks[sid].append(blocks[i]["poly"])
	return _street_blocks.get(key.x, []) if is_street(key) else []
