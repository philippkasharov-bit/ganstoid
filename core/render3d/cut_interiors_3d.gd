## A1b: Zomboid shows what is inside a building when its walls are cut away
## in front of you: floors, inner walls and furniture, cut low with the rest
## of it. The insides of the buildings the Cutaway is cutting are built
## when they start hiding you and dropped when they stop (the building you
## are in has its own, RenderSync3D._show_inside).
class_name CutInteriors3D
extends Node3D

const MAX_AREA := 1500.0   # bigger footprints (malls, warehouses) stay empty: their layout is not worth the build

var origin := Vector2.ZERO
var footprints: Footprints
var _shown: Dictionary = {}   # tag -> MeshInstance3D
var _material: ShaderMaterial

## Shows the insides of the buildings with these Cutaway `tags`, except building `skip` (the one you are in).
func show_for(tags: PackedInt32Array, skip: String) -> void:
	if footprints == null:
		return
	for tag in _shown.keys():
		if not tags.has(tag):
			_shown[tag].queue_free()
			_shown.erase(tag)
	for tag in tags:
		var b := footprints.building_of(tag)
		if _shown.has(tag) or b.is_empty() or String(b.get("id", "")) == skip or absf(_area(b["poly"])) > MAX_AREA:
			continue
		if _material == null:
			_material = Cutaway.material()
		_shown[tag] = InteriorMesh3D.build(b, origin, _material, tag)
		add_child(_shown[tag])

static func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		sum += poly[i].cross(poly[(i + 1) % poly.size()])
	return sum * 0.5
