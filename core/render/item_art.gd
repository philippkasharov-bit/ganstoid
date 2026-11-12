## INV2: item pictures drawn in code for the bag grid (no art files needed):
## simple marker-style silhouettes in the item's category colour, fitted to
## the cells the item covers. Swap point: art/ui/items/<id>.png, when present,
## is drawn instead.
class_name ItemArt
extends RefCounted

const ART_DIR := "res://art/ui/items/"
const INK := Color(0.07, 0.07, 0.08)

static var _cache := {}

## Draws `id` inside `rect`; `turned` when the pile lies rotated in the grid.
static func draw(ci: CanvasItem, id: StringName, rect: Rect2, colour: Color, turned: bool) -> void:
	var tex := _texture(id)
	if tex != null:
		ci.draw_texture_rect(tex, rect.grow(-3), false)
		return
	var c := rect.get_center()
	var long := maxf(rect.size.x, rect.size.y) * 0.42
	var short := minf(rect.size.x, rect.size.y) * 0.34
	var axis := Vector2.RIGHT if rect.size.x >= rect.size.y else Vector2.DOWN
	var side := Vector2(-axis.y, axis.x)
	var pts := _shape(id, c, axis * long, side * short)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, colour)
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), INK, 1.5, true)

static func _texture(id: StringName) -> Texture2D:
	if not _cache.has(id):
		var path := ART_DIR + String(id) + ".png"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]

## A rough outline per item, built along the item's long axis `a` and its
## short side `s` (both half-lengths from the centre `c`).
static func _shape(id: StringName, c: Vector2, a: Vector2, s: Vector2) -> PackedVector2Array:
	match ItemCatalog.item(id).get("kind", "goods"):
		"drink":
			return _bottle(c, a, s)
		"weapon":
			return _blade(c, a, s) if id == &"knife" else (_bat(c, a, s) if id == &"bat" else _gun(c, a, s))
		"medical":
			return _cross(c, a.length() * 0.8)
		"ammo":
			return _box(c, Vector2(a.length() * 0.8, a.length() * 0.6))
		"food":
			return _box(c, Vector2(a.length(), s.length() * 0.9)) if id == &"burrito" else _bag(c, a, s)
	return _bag(c, a * 0.8, s * 0.8)

static func _box(c: Vector2, half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([c - half, c + Vector2(half.x, -half.y), c + half, c + Vector2(-half.x, half.y)])

static func _bottle(c: Vector2, a: Vector2, s: Vector2) -> PackedVector2Array:
	var neck := s * 0.35
	return PackedVector2Array([c - a + s * 0.8, c + a * 0.3 + s * 0.8, c + a * 0.6 + neck, c + a + neck,
		c + a - neck, c + a * 0.6 - neck, c + a * 0.3 - s * 0.8, c - a - s * 0.8])

static func _bat(c: Vector2, a: Vector2, s: Vector2) -> PackedVector2Array:
	return PackedVector2Array([c - a + s * 0.2, c + a * 0.2 + s * 0.35, c + a + s * 0.6, c + a - s * 0.6,
		c + a * 0.2 - s * 0.35, c - a - s * 0.2])

static func _blade(c: Vector2, a: Vector2, s: Vector2) -> PackedVector2Array:
	return PackedVector2Array([c - a + s * 0.3, c - a * 0.2 + s * 0.3, c - a * 0.2 + s * 0.6, c + a, c - a * 0.2 - s * 0.4,
		c - a - s * 0.3])

static func _gun(c: Vector2, a: Vector2, s: Vector2) -> PackedVector2Array:
	return PackedVector2Array([c - a - s * 0.6, c + a - s * 0.6, c + a - s * 0.05, c - a * 0.3 - s * 0.05,
		c - a * 0.45 + s * 0.9, c - a * 0.85 + s * 0.9, c - a * 0.7 - s * 0.05, c - a - s * 0.05])

static func _cross(c: Vector2, r: float) -> PackedVector2Array:
	var t := r * 0.35
	return PackedVector2Array([c + Vector2(-t, -r), c + Vector2(t, -r), c + Vector2(t, -t), c + Vector2(r, -t),
		c + Vector2(r, t), c + Vector2(t, t), c + Vector2(t, r), c + Vector2(-t, r), c + Vector2(-t, t),
		c + Vector2(-r, t), c + Vector2(-r, -t), c + Vector2(-t, -t)])

static func _bag(c: Vector2, a: Vector2, s: Vector2) -> PackedVector2Array:
	var h := maxf(a.length(), s.length())
	return PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.75), c + Vector2(h * 0.55, -h * 0.75),
		c + Vector2(h * 0.7, h * 0.75), c + Vector2(-h * 0.7, h * 0.75)])
