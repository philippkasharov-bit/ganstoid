## SL1: lane markings on city streets, from the real OSM lane count and
## one-way tag (LA/MUTCD): two-way streets get a yellow centre line (double
## solid on arterials, dashed on small streets), a centre turn lane where the
## lane count is odd on an arterial; white dashed lines between lanes going
## the same way. Markings stop short of each end so junctions stay clear.
class_name StreetPainter
extends RefCounted

const LINE_M := 0.15
const GAP_PAIR_M := 0.25          # between the two lines of a double yellow
const DASH_M := 3.0
const GAP_M := 9.0
const END_CLEAR_M := 7.0
const YELLOW := Color("e8c547")
const WHITE := Color("eeede8")
const YELLOW_N := Color("8f7a33")
const WHITE_N := Color("8c8f99")

static func paint(ci: CanvasItem, roads: Array, night: bool) -> void:
	var y: Color = YELLOW_N if night else YELLOW
	var w: Color = WHITE_N if night else WHITE
	for road in roads:
		if not road["tier"] in ["art", "res"] or not road.has("w"):
			continue
		var pts := _trimmed(road["pts"], END_CLEAR_M)
		if pts.size() < 2:
			continue
		var width: float = road["w"]
		var lanes: int = int(road.get("lanes", 2 if road["tier"] == "art" else 0))
		if lanes <= 0:
			lanes = 2 if width >= 9.0 else 0
		if lanes <= 0:
			continue   # a narrow residential street with no lanes mapped: no paint, like most of them
		var lane_w := width / lanes
		if road.get("oneway", 0) != 0:
			for k in range(1, lanes):
				_dashed(ci, FreewayPainter._offset(pts, -width * 0.5 + lane_w * k), w)
			continue
		var turn: bool = road["tier"] == "art" and lanes % 2 == 1 and lanes >= 3
		var each: int = (lanes - (1 if turn else 0)) / 2
		if turn:   # centre turn lane: solid outside, dashed inside, both yellow
			for side in [-1.0, 1.0]:
				ci.draw_polyline(FreewayPainter._offset(pts, side * (lane_w * 0.5 + GAP_PAIR_M)), y, LINE_M)
				_dashed(ci, FreewayPainter._offset(pts, side * lane_w * 0.5), y)
		elif road["tier"] == "art":
			ci.draw_polyline(FreewayPainter._offset(pts, -GAP_PAIR_M * 0.5), y, LINE_M)
			ci.draw_polyline(FreewayPainter._offset(pts, GAP_PAIR_M * 0.5), y, LINE_M)
		else:
			_dashed(ci, pts, y)
		var mid := lane_w * 0.5 if turn else 0.0
		for side in [-1.0, 1.0]:
			for k in range(1, each):
				_dashed(ci, FreewayPainter._offset(pts, side * (mid + lane_w * k)), w)

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

## The line with `cut` metres taken off each end.
static func _trimmed(pts: PackedVector2Array, cut: float) -> PackedVector2Array:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	if total <= cut * 2.0 + 2.0:
		return PackedVector2Array()
	var out := PackedVector2Array()
	var run := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var s0 := clampf(cut - run, 0.0, seg)
		var s1 := clampf(total - cut - run, 0.0, seg)
		if s1 > s0:
			var d := (b - a) / seg
			if out.is_empty():
				out.append(a + d * s0)
			out.append(a + d * s1)
		run += seg
	return out
