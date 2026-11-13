## R3D14: what you bump into in and around a building you can walk into:
## its outer walls with the front door left open, its inner walls (doorways
## open) and its furniture. A body is a circle; slide() moves it and slides
## along whatever it touches, the way CityCollision does outside.
class_name InteriorSolid
extends RefCounted

const RADIUS := 0.3

## The front door: the gap in the wall nearest the city's door point, kept a
## door's width from the corners (BuildingMesh3D draws the door here too).
static func front_door(l: InteriorLayout, door: Vector2) -> void:
	var span := door_span(l.poly, door)
	if span.x < 0:
		return   # a shed too small for a door
	var edge := int(span.x)
	var t := span.y
	var a := l.poly[edge]
	var c := l.poly[(edge + 1) % l.poly.size()]
	var dir := (c - a).normalized()
	var mid := a.lerp(c, t)
	l.door_a = mid - dir * InteriorLayout.FRONT_DOOR * 0.5
	l.door_b = mid + dir * InteriorLayout.FRONT_DOOR * 0.5
	l.doors.append(l.to_local(mid))

## Which wall the front door is in and where along it (0..1): by the city's
## door point, or the middle of the longest wall when that wall is too short;
## (-1, -1) for a shed too small for a door. The 3D view draws it here too.
static func door_span(poly: PackedVector2Array, door: Vector2) -> Vector2:
	var edge := door_edge(poly, door)
	var t := -1.0
	if edge >= 0:
		t = door_t(poly[edge], poly[(edge + 1) % poly.size()], door, InteriorLayout.FRONT_DOOR)
	if t < 0.0:
		edge = _longest(poly)
		t = 0.5
	if poly[edge].distance_to(poly[(edge + 1) % poly.size()]) < InteriorLayout.FRONT_DOOR * 1.3:
		return Vector2(-1, -1)
	return Vector2(edge, t)

static func _longest(poly: PackedVector2Array) -> int:
	var best := 0
	for i in poly.size():
		if poly[i].distance_to(poly[(i + 1) % poly.size()]) > poly[best].distance_to(poly[(best + 1) % poly.size()]):
			best = i
	return best

static func door_edge(poly: PackedVector2Array, door: Vector2) -> int:
	if door == Vector2.INF:
		return -1
	var best := -1
	var best_d := INF
	for i in poly.size():
		var d := Geometry2D.get_closest_point_to_segment(door, poly[i], poly[(i + 1) % poly.size()]).distance_squared_to(door)
		if d < best_d:
			best_d = d
			best = i
	return best

## Where along a-c the door's middle sits (0..1), or -1 when the wall is too short.
static func door_t(a: Vector2, c: Vector2, door: Vector2, width: float) -> float:
	var length := a.distance_to(c)
	if length < width * 1.6:
		return -1.0
	var margin := width / length
	return clampf((door - a).dot(c - a) / (length * length), margin, 1.0 - margin)

## Every solid segment as map pairs: outer walls (door open), inner walls,
## and furniture sides (left out for what blocks sight: you see over a sofa).
static func build(l: InteriorLayout, with_furniture: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in l.poly.size():
		var a := l.poly[i]
		var c := l.poly[(i + 1) % l.poly.size()]
		if l.door_a != l.door_b and Geometry2D.get_closest_point_to_segment(l.door_a.lerp(l.door_b, 0.5), a, c).distance_to(l.door_a.lerp(l.door_b, 0.5)) < 0.01:
			var near_a := a.distance_to(l.door_a) < a.distance_to(l.door_b)
			out.append_array([a, l.door_a if near_a else l.door_b, l.door_b if near_a else l.door_a, c])
		else:
			out.append_array([a, c])
	out.append_array(l.walls)
	for f in (l.furniture if with_furniture else []):
		var c4 := InteriorLayout.corners(f["rect"])
		for k in 4:
			out.append_array([l.to_map(c4[k]), l.to_map(c4[(k + 1) % 4])])
	return out

## How far `p` is from the nearest wall or piece of furniture.
static func clearance(l: InteriorLayout, p: Vector2) -> float:
	var best := INF
	for i in range(0, l.solid.size() - 1, 2):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, l.solid[i], l.solid[i + 1]).distance_to(p))
	return best

## Move from `from` by `delta`, sliding along walls and furniture. Already
## touching one (stepped in at an angle), only a step that backs off is allowed.
static func slide(l: InteriorLayout, from: Vector2, delta: Vector2, r: float = RADIUS) -> Vector2:
	var now := clearance(l, from)
	for step in [delta, Vector2(delta.x, 0), Vector2(0, delta.y)]:
		var room := clearance(l, from + step)
		if room >= r or (now < r and room > now):
			return from + step
	return from

## Is `p` at the front door (in the gap, or just in front of or behind it)?
static func at_door(l: InteriorLayout, p: Vector2, reach: float = 0.9) -> bool:
	return l.door_a != l.door_b and Geometry2D.get_closest_point_to_segment(p, l.door_a, l.door_b).distance_to(p) < reach
