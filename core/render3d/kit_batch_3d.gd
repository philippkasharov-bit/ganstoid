## K4: the house-kit parts of one chunk, drawn as one MultiMesh per part.
## Each copy carries its paint (instance colour: the house's trim) and,
## in its custom data, its building tag (the Cutaway cuts it with its
## house), whether its window is lit, and which door colour it has.
## Part meshes (Blender, art/models/kit) and the kit material are loaded
## once on the main thread (prime), never per chunk on a stream worker.
class_name KitBatch3D
extends RefCounted

const PARTS := ["kit_window_sash", "kit_window_wide", "kit_window_small", "kit_door_front", "kit_door_garage", "kit_trim_corner",
	"kit_porch", "kit_meter"]
const MODEL := "res://art/models/kit/%s.obj"
const ATLAS := "res://art/textures/kit_atlas.png"
const DOOR_PAINT := [   # the Cutaway shader holds the same eight as DOOR_PAINT; keep them in step
Color("2f4a3a"), Color("8a2a24"), Color("1f2d4a"), Color("1c1c1e"), Color("6b4a2e"), Color("efeae0"), Color("2a6b6b"), Color("b8892e")]

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial

var _items: Dictionary = {}   # part -> [[Transform3D, paint, custom], ...]

## Loads every part and makes the kit material (main thread, once).
static func prime() -> void:
	for part in PARTS:
		if not _meshes.has(part) and ResourceLoader.exists(MODEL % part):
			_meshes[part] = load(MODEL % part)
	material()

## The kit's Cutaway material: the baked sheet, paint by its alpha mask.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = Cutaway.material()
		_material.set_shader_parameter("kit_on", true)
		var img := Image.load_from_file(ATLAS) if FileAccess.file_exists(ATLAS) else null
		if img != null:
			img.generate_mipmaps()
			_material.set_shader_parameter("kit_atlas", ImageTexture.create_from_image(img))
	return _material

## A copy's custom data: its building tag in two base-256 digits (r, a), whether
## its window is lit (g) and its door colour (b). Every channel stays in 0..1, so
## it survives the 8-bit / half-float storage some renderers use.
static func custom(tag: int, lit: float, door: int) -> Color:
	return Color(float(tag % 256) / 255.0, lit, float(door) / 7.0, float(tag / 256) / 255.0)

## One copy of `part` at `xform`, painted `paint`, with its `custom` data.
func put(part: String, xform: Transform3D, paint: Color, custom: Color) -> void:
	_items.get_or_add(part, []).append([xform, paint, custom])

## The chunk's kit, as MultiMeshInstance3D nodes.
func commit() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for part in _items:
		if not _meshes.has(part):
			continue
		var list: Array = _items[part]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _meshes[part]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
			mm.set_instance_custom_data(i, list[i][2])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		out.append(mi)
	return out
