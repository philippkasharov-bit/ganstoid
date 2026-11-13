## A5: an item's picture flies from where it was to where it went (Nearby to
## the bag on a pick-up, the bag to Nearby on a drop), 0.25 s, easing in. A
## free-floating Control that frees itself when it lands.
class_name ItemFlight
extends Control

const FLY_S := 0.25
const PX := 30.0

var _id: StringName
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0

## Starts one flight under `parent` between two screen points.
static func launch(parent: Node, id: StringName, from: Vector2, to: Vector2) -> void:
	var f := ItemFlight.new()
	f._id = id
	f._from = from - Vector2(PX, PX) * 0.5
	f._to = to - Vector2(PX, PX) * 0.5
	f.top_level = true
	f.z_index = 90
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.size = Vector2(PX, PX)
	f.position = f._from
	parent.add_child(f)

## Centre of each pile of a grid on screen, by item.
static func centres(view: BagGridView) -> Dictionary:
	var out := {}
	for p in view.piles:
		out[p["id"]] = view.global_position + view._pile_rect(p).get_center()
	return out

## What came into the bag flies in from Nearby; what left flies out to it.
static func between(parent: Node, had: Dictionary, now: Dictionary, near_before: Dictionary, bag_before: Dictionary, near_now: Dictionary, bag_now: Dictionary) -> void:
	for id in now:
		if int(now[id]) > int(had.get(id, 0)) and near_before.has(id) and bag_now.has(id):
			launch(parent, id, near_before[id], bag_now[id])
	for id in had:
		if int(now.get(id, 0)) < int(had[id]) and bag_before.has(id) and near_now.has(id):
			launch(parent, id, bag_before[id], near_now[id])

func _process(delta: float) -> void:
	_t += delta
	var k := ease(clampf(_t / FLY_S, 0.0, 1.0), 0.4)
	position = _from.lerp(_to, k) + Vector2(0, -18.0 * sin(k * PI))   # a small arc
	scale = Vector2.ONE * (1.0 + 0.15 * sin(k * PI))
	queue_redraw()
	if _t >= FLY_S:
		queue_free()

func _draw() -> void:
	var kind: String = ItemCatalog.item(_id).get("kind", "goods")
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	ItemArt.draw(self, _id, Rect2(Vector2(3, 3), size - Vector2(6, 6)), InventoryWindow.KIND_COLOURS.get(kind, UiTheme.DIM), false)
