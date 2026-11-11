## MF1: freeways and ramps drawn like the real thing seen from above:
## a soft shadow on the ground below (they are elevated), a dark concrete
## barrier along each edge, a lighter concrete deck, and the striping —
## solid white right edge, solid yellow left edge, dashed white lane lines
## (LA: 10 ft dash, 30 ft gap, 12 ft lanes). Ramps first, mainline over them.
## Each OSM freeway way is one carriageway, drawn in its direction of travel.
class_name FreewayPainter
extends RefCounted

const LANE_M := 3.65
const BARRIER_M := 0.6
const SHOULDER_M := 0.9           # edge line this far in from the barrier
const LINE_M := 0.15
const DASH_M := 3.0
const GAP_M := 9.0
const SHADOW_OFFSET := Vector2(2.5, 3.5)
const DAY := {"deck": Color("a9a69e"), "barrier": Color("6c6a64"), "shadow": Color("cfc9ba"), "white": Color("f2f1ec"), "yellow": Color("e8c547")}
const NIGHT := {"deck": Color("3a3c44"), "barrier": Color("24252b"), "shadow": Color("121317"), "white": Color("8c8f99"), "yellow": Color("8f7a33")}

static func paint(ci: CanvasItem, roads: Array, widths: Dictionary, night: bool, markings: bool) -> void:
	var pal: Dictionary = NIGHT if night else DAY
	var ordered := roads.filter(func(r: Dictionary) -> bool: return r["tier"] == "ramp") + roads.filter(func(r: Dictionary) -> bool: return r["tier"] == "fwy")
	for road in ordered:
		ci.draw_polyline(_shifted(road["pts"], SHADOW_OFFSET), pal["shadow"], _w(road, widths) + 1.0)   # opaque: overlapping shadows must not stack darker
	for road in ordered:
		var w := _w(road, widths)
		_band(ci, road["pts"], pal["barrier"], w)
		_band(ci, road["pts"], pal["deck"], w - BARRIER_M * 2.0)
		if markings:
			_stripes(ci, road["pts"], w, pal)

static func _w(road: Dictionary, widths: Dictionary) -> float:
	return road.get("w", widths[road["tier"]])

## A wide line with mitred-looking joints: each bend gets a disc of the same width.
static func _band(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	ci.draw_polyline(pts, col, w)
	for i in range(1, pts.size() - 1):
		ci.draw_circle(pts[i], w * 0.5, col)

static func _stripes(ci: CanvasItem, pts: PackedVector2Array, w: float, pal: Dictionary) -> void:
	var half := w * 0.5 - BARRIER_M - SHOULDER_M
	if half <= LANE_M * 0.4:
		return   # a narrow ramp: edge lines only would crowd it
	ci.draw_polyline(_offset(pts, half), pal["white"], LINE_M)        # right edge
	ci.draw_polyline(_offset(pts, -half), pal["yellow"], LINE_M)      # left edge (median side)
	var lanes := maxi(1, roundi(half * 2.0 / LANE_M))
	for k in range(1, lanes):
		_dashed(ci, _offset(pts, -half + half * 2.0 * k / lanes), pal["white"])

static func _dashed(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var carry := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var seg := a.distance_to(pts[i + 1])
		if seg <= 0.0:
			continue
		var d := (pts[i + 1] - a) / seg
		var t := carry
		while t < seg:
			ci.draw_line(a + d * t, a + d * minf(t + DASH_M, seg), col, LINE_M)
			t += DASH_M + GAP_M
		carry = t - seg

## The line moved sideways by `by` metres (+ = right of travel).
static func _offset(pts: PackedVector2Array, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(0, i - 1)]
		var b := pts[mini(pts.size() - 1, i + 1)]
		var dir := (b - a).normalized()
		out.append(pts[i] + Vector2(-dir.y, dir.x) * by)
	return out

static func _shifted(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out
