## B1: where the carriageways are. Every drivable road's segments in a grid,
## so anything that stands up beside a road (lamps, signal and sign posts,
## power poles, meters, trees) can be kept out of the traffic, and paint
## (lane dashes, centre lines) can stop where another road crosses. One per
## city, built once (a lock: the 3D stream builds chunks on worker threads).
class_name RoadSpace
extends RefCounted

const CELL_M := 24.0
const REACH_M := 16.0      # widest half-road plus margin: one cell lookup sees it
const JOINT := 1.42        # CityMesh3D squares each joint: its corner is this far out
const DRIVEN := ["fwy", "ramp", "art", "res", "svc", "alley", "aisle", "drive", "hill"]

static var _cache: Dictionary = {}   # city instance id -> RoadSpace
static var _lock := Mutex.new()

var _grid: Dictionary = {}   # Vector2i -> [[a, b, half, road index], ...]

## The road space of `city` (built on first use).
static func of(city: CityData) -> RoadSpace:
	_lock.lock()
	var id := city.get_instance_id()
	if not _cache.has(id):
		_cache[id] = RoadSpace.new()
		_cache[id]._build(city)
	var space: RoadSpace = _cache[id]
	_lock.unlock()
	return space

func _build(city: CityData) -> void:
	for i in city.roads.size():
		var r: Dictionary = city.roads[i]
		if not r["tier"] in DRIVEN:
			continue
		var half: float = float(r.get("w", CityMesh3D.ROAD_W.get(r["tier"], 6.0))) * 0.5
		var pts: PackedVector2Array = r["pts"]
		for k in pts.size() - 1:
			var grow := Vector2.ONE * minf(half + 2.0, REACH_M)
			var lo := Vector2i(((pts[k].min(pts[k + 1]) - grow) / CELL_M).floor())
			var hi := Vector2i(((pts[k].max(pts[k + 1]) + grow) / CELL_M).floor())
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					_grid.get_or_add(Vector2i(x, y), []).append([pts[k], pts[k + 1], half, i])

## Is `p` on a carriageway (within `margin` of its edge), other than road `skip`?
func inside(p: Vector2, margin: float = 0.0, skip: int = -1) -> bool:
	for s in _grid.get(Vector2i((p / CELL_M).floor()), []):
		if s[3] != skip and Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) < float(s[2]) + margin:
			return true
	return false

## `p` pushed out of any carriageway to `margin` past its edge (a few passes for corners).
func clear(p: Vector2, margin: float = 0.6) -> Vector2:
	for pass_n in 4:
		var moved := false
		for s in _grid.get(Vector2i((p / CELL_M).floor()), []):
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
			var want := float(s[2]) + margin
			if near.distance_to(p) < want:
				var away: Vector2 = (p - near).normalized() if p != near else (s[1] - s[0]).normalized().orthogonal()
				p = near + away * want
				moved = true
			for end: Vector2 in [s[0], s[1]]:   # the square under each joint reaches out at its corners
				var corner := float(s[2]) * JOINT + margin
				if end.distance_to(p) < corner:
					p = end + ((p - end).normalized() if p != end else Vector2.RIGHT) * corner
					moved = true
		if not moved:
			break
	return p
