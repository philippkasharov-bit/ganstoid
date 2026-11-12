## RG (roads): the street network as a graph for driving (AStar2D, native).
## Every street vertex is a node; consecutive vertices are joined both ways,
## or one way along one-way streets. Freeways and ramps are left out for now
## (their junctions with the street grid are not mapped as shared points).
class_name RoadGraph
extends RefCounted

const TIERS := ["res", "art", "hill"]
const JOIN_M := 2.0
const LANE_M := 1.9             # cars keep this far right of the centre line

var astar := AStar2D.new()
var _ids := {}                  # quantised point -> node id

static func build(roads: Array) -> RoadGraph:
	var g := RoadGraph.new()
	for r in roads:
		if not TIERS.has(r["tier"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var oneway: int = r.get("oneway", 0)
		for i in pts.size() - 1:
			var a := g._node(pts[i])
			var b := g._node(pts[i + 1])
			if a == b:
				continue
			if oneway == 0:
				g.astar.connect_points(a, b, true)
			elif oneway > 0:
				g.astar.connect_points(a, b, false)
			else:
				g.astar.connect_points(b, a, false)
	return g

func _node(p: Vector2) -> int:
	var key := Vector2i((p / JOIN_M).round())
	if _ids.has(key):
		return _ids[key]
	var id := astar.get_available_point_id()
	astar.add_point(id, p)
	_ids[key] = id
	return id

## The driving line from near `from` to near `to`, in the right-hand lane.
## Empty when there is no way (one-way maze, off the network).
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if astar.get_point_count() == 0:
		return PackedVector2Array()
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	var line := astar.get_point_path(a, b)
	if line.size() < 2:
		return PackedVector2Array()
	return FreewayPainter._offset(line, LANE_M)
