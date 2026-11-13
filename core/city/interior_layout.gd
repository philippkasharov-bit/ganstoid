## R3D14: the inside of a building as the sim knows it (the 3D view draws the
## same thing): rooms split from the footprint in its own frame (along its
## longest wall), inner walls with a doorway each, the front door as a gap in
## the outer wall (where the city data puts it), and furniture against the
## walls, clear of doorways, each tied to the container it holds (kitchen
## drawers, bedroom wardrobe, bathroom cabinet, shop register, stock room).
## Walls and furniture are solid (InteriorSolid moves a body inside, or in
## and out through the front door). Seeded by the building id, so it is the same
## every time; a few recent layouts are cached.
class_name InteriorLayout
extends RefCounted

const WALL_T := 0.12
const DOOR_GAP := 0.95        # inner doorways
const FRONT_DOOR := 1.1       # the front door (BuildingMesh3D draws it this wide)
const MIN_ROOM := 2.6
const TARGET_M2 := 16.0
const CACHE := 24
## room kind -> [name, [width along the wall, depth, height], container ("" none)]
const FURNITURE := {
	"living": [["sofa", [2.0, 0.9, 0.8], ""], ["tv", [1.4, 0.45, 1.0], ""], ["table", [1.0, 0.6, 0.45], ""], ["shelf", [1.0, 0.4, 1.8], "bedroom"]],
	"kitchen": [["fridge", [0.75, 0.7, 1.8], "kitchen"], ["stove", [0.7, 0.65, 0.9], "kitchen"], ["counter", [1.4, 0.65, 0.9], "kitchen"], ["counter", [1.4, 0.65, 0.9], "kitchen"], ["table", [1.2, 0.8, 0.75], ""]],
	"bath": [["tub", [1.6, 0.75, 0.55], ""], ["toilet", [0.45, 0.65, 0.75], ""], ["sink", [0.6, 0.45, 0.85], "bathroom"]],
	"bed": [["bed", [1.6, 2.0, 0.55], ""], ["drawers", [1.0, 0.5, 1.0], "bedroom"], ["wardrobe", [1.2, 0.6, 2.0], "bedroom"]],
	"shop": [["shelf", [2.4, 0.6, 1.7], "stockroom"], ["shelf", [2.4, 0.6, 1.7], "stockroom"], ["counter", [2.0, 0.7, 1.0], "register"], ["fridge", [1.6, 0.7, 2.0], "stockroom"]],
	"stock": [["crates", [1.2, 1.0, 1.2], "stockroom"], ["shelf", [2.0, 0.6, 2.0], "stockroom"]],
	"work": [["bench", [2.0, 0.8, 0.95], "register"], ["crates", [1.2, 1.0, 1.2], "stockroom"], ["drums", [0.6, 0.6, 0.9], ""]],
}

static var _cache: Dictionary = {}

var id: StringName
var poly := PackedVector2Array()     # the footprint, map metres
var local := PackedVector2Array()    # the same in the frame
var base := Vector2.ZERO             # map point at the frame's origin
var angle := 0.0                     # the frame's turn
var rooms: Array[Rect2] = []         # in the frame
var kinds: Array[String] = []
var walls := PackedVector2Array()    # inner wall slabs, map pairs (a, b, a, b...)
var furniture: Array[Dictionary] = []   # {name, rect (frame), h, container}
var door_a := Vector2.ZERO           # the front door's two jambs, map
var door_b := Vector2.ZERO
var doors: Array[Vector2] = []       # doorway middles in the frame, front door too (kept clear of furniture)
var solid := PackedVector2Array()    # everything a body bumps into, map pairs (InteriorSolid)

## The layout of CityData building `b`.
static func of(b: Dictionary) -> InteriorLayout:
	var key: StringName = b["id"]
	if not _cache.has(key):
		if _cache.size() >= CACHE:
			_cache.erase(_cache.keys()[0])
		_cache[key] = _make(b)
	return _cache[key]

static func _make(b: Dictionary) -> InteriorLayout:
	var l := InteriorLayout.new()
	l.id = b["id"]
	l.poly = open(b["poly"])
	l._frame()
	InteriorSolid.front_door(l, b.get("door", Vector2.INF))
	var rng := RandomNumberGenerator.new()
	rng.seed = String(b["id"]).hash() + 7
	l.rooms = l._split(_box(l.local), rng, 0)
	l.kinds = _kinds(l.rooms, String(b["kind"]))
	for i in l.rooms.size():
		l._furnish(l.rooms[i], l.kinds[i], rng)
	l.solid = InteriorSolid.build(l)
	return l

static func open(p: PackedVector2Array) -> PackedVector2Array:
	return p.slice(0, p.size() - 1) if p.size() > 3 and p[0] == p[p.size() - 1] else p

static func _box(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r

func _frame() -> void:
	var best := 0.0
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best:
			best = e.length()
			angle = e.angle()
	base = poly[0]
	for p in poly:
		local.append(to_local(p))

func to_local(p: Vector2) -> Vector2:
	return (p - base).rotated(-angle)

func to_map(p: Vector2) -> Vector2:
	return base + p.rotated(angle)

## Rooms by splitting the footprint's box, longest side first; each split is an inner wall.
func _split(r: Rect2, rng: RandomNumberGenerator, depth: int) -> Array[Rect2]:
	var along_x := r.size.x >= r.size.y
	var length := r.size.x if along_x else r.size.y
	if r.get_area() < TARGET_M2 * 1.6 or length < MIN_ROOM * 2.0 or depth > 4:
		return [r]
	var cut := length * rng.randf_range(0.38, 0.62)
	var a := Rect2(r.position, Vector2(cut, r.size.y) if along_x else Vector2(r.size.x, cut))
	var b := Rect2(r.position + (Vector2(cut, 0) if along_x else Vector2(0, cut)), r.size - (Vector2(cut, 0) if along_x else Vector2(0, cut)))
	var from := a.end if not along_x else Vector2(a.end.x, r.position.y)
	var to := Vector2(r.position.x, a.end.y) if not along_x else a.end
	_wall(from, to, rng)
	var out: Array[Rect2] = []
	out.append_array(_split(a, rng, depth + 1))
	out.append_array(_split(b, rng, depth + 1))
	return out

## An inner wall along a-b, kept inside the footprint, with one doorway in its longest piece.
func _wall(a: Vector2, b: Vector2, rng: RandomNumberGenerator) -> void:
	var pieces := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), local)
	var longest := -1
	for i in pieces.size():
		if longest < 0 or pieces[i][0].distance_to(pieces[i][1]) > pieces[longest][0].distance_to(pieces[longest][1]):
			longest = i
	for i in pieces.size():
		var p: PackedVector2Array = pieces[i]
		var length := p[0].distance_to(p[1])
		if i == longest and length > DOOR_GAP + 0.6:
			var t := rng.randf_range(0.3 + DOOR_GAP * 0.5, length - 0.3 - DOOR_GAP * 0.5) / length
			var dir := (p[1] - p[0]) / length
			var mid := p[0].lerp(p[1], t)
			doors.append(mid)
			_slab(p[0], mid - dir * DOOR_GAP * 0.5)
			_slab(mid + dir * DOOR_GAP * 0.5, p[1])
		else:
			_slab(p[0], p[1])

func _slab(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) >= 0.05:
		walls.append(to_map(a))
		walls.append(to_map(b))

## What each room is: houses get living, kitchen, bath, bedrooms; shops a floor and a stock room.
static func _kinds(list: Array[Rect2], kind: String) -> Array[String]:
	var order := range(list.size())
	order.sort_custom(func(a: int, b: int) -> bool: return list[a].get_area() > list[b].get_area())
	var out: Array[String] = []
	out.resize(list.size())
	for rank in order.size():
		var i: int = order[rank]
		if kind in ["industrial", "garage"]:
			out[i] = "work"
		elif kind in ["commercial", "civic", "building"]:
			out[i] = "shop" if rank == 0 else "stock"
		elif rank == 0:
			out[i] = "living"
		elif rank == order.size() - 1 and order.size() > 2:
			out[i] = "bath"
		elif rank == 1:
			out[i] = "kitchen"
		else:
			out[i] = "bed"
	return out

## Furniture against the room's walls: inside the footprint, not on another piece, not in a doorway.
func _furnish(r: Rect2, kind: String, rng: RandomNumberGenerator) -> void:
	var placed: Array[Rect2] = []
	for item in FURNITURE[kind]:
		for attempt in 8:
			var spot := _against_wall(r.grow(-WALL_T), item[1], rng)
			if _fits(spot, placed):
				placed.append(spot)
				furniture.append({"name": item[0], "rect": spot, "h": item[1][2], "container": item[2]})
				break

static func _against_wall(r: Rect2, size: Array, rng: RandomNumberGenerator) -> Rect2:
	var side := rng.randi() % 4
	var ext := Vector2(size[0], size[1]) if side % 2 == 0 else Vector2(size[1], size[0])
	var free := r.size - ext
	if free.x < 0.0 or free.y < 0.0:
		return Rect2()
	var at := Vector2(rng.randf() * free.x, rng.randf() * free.y)
	match side:
		0: at.y = 0.0
		1: at.x = free.x
		2: at.y = free.y
		3: at.x = 0.0
	return Rect2(r.position + at, ext)

func _fits(spot: Rect2, placed: Array[Rect2]) -> bool:
	if not spot.has_area():
		return false
	for p in corners(spot):
		if not Geometry2D.is_point_in_polygon(p, local):
			return false
	for other in placed:
		if other.grow(0.1).intersects(spot):
			return false
	for door in doors:
		if spot.grow(0.8).has_point(door):
			return false
	return true

static func corners(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
