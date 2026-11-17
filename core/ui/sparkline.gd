## UI6: a small line chart (the phone's Bank app: cash each morning). The
## last point is now and gets a dot; the lowest and highest are labelled.
class_name Sparkline
extends Control

var values: Array = []
var ink := Color.WHITE

func _draw() -> void:
	if values.size() < 2:
		draw_string(UiTheme.font("lcd"), Vector2(0, size.y * 0.6), "a chart appears after a few mornings", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ink, 0.6))
		return
	var lo := float(values.min())
	var hi := maxf(float(values.max()), lo + 1.0)
	var pts := PackedVector2Array()
	for i in values.size():
		pts.append(Vector2(size.x * i / float(values.size() - 1), size.y - 14.0 - (size.y - 22.0) * (float(values[i]) - lo) / (hi - lo)))
	var fill := pts.duplicate()
	fill.append(Vector2(size.x, size.y - 14.0))
	fill.append(Vector2(0, size.y - 14.0))
	draw_colored_polygon(fill, Color(ink, 0.12))
	draw_polyline(pts, ink, 2.0, true)
	draw_circle(pts[-1], 3.5, ink)
	var f := UiTheme.font("lcd")
	draw_string(f, Vector2(0, size.y), "$%d" % int(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(ink, 0.7))
	draw_string(f, Vector2(size.x - 60, 10), "$%d" % int(hi), HORIZONTAL_ALIGNMENT_RIGHT, 60, 15, Color(ink, 0.7))
