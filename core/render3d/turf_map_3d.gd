## T3: the turf and money maps laid over the 3D city (U cycles: turf, money,
## off), the way Zomboid's map overlays sit on the world. Turf: every
## street someone holds, its blocks washed in the holder's colour and the
## street itself drawn bold; money: every block by how well off it is.
## Hood names float over their hoods. Drawn over everything (no depth), round
## the player only, rebuilt a few times a second while it is up.
class_name TurfMap3D
extends Node3D

const RANGE_M := 700.0
const LIFT := 0.08
const REFRESH_S := 0.5
const POOR := Color("c0392b")
const MIDDLE := Color("d4ac0d")
const RICH := Color("27ae60")

var world: World
var origin := Vector2.ZERO
var mode := 0                  # 0 off, 1 turf, 2 money
var focus := Vector2.ZERO
var _mesh := MeshInstance3D.new()
var _labels: Array[Label3D] = []
var _left := 0.0

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true   # A2b: right in Mobile too
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_names()

func cycle() -> void:
	mode = (mode + 1) % 3
	_left = 0.0
	visible = mode != 0

func _process(delta: float) -> void:
	if mode == 0 or world == null:
		return
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH_S
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if mode == 1:
		_turf(st)
	else:
		_money(st)
	_mesh.mesh = st.commit()

func _turf(st: SurfaceTool) -> void:
	var t := TerritorySystem.data(world)
	var h := Hoods.data()
	if t == null or h == null:
		return
	for c in t.cells:
		if not Hoods.is_street(c) or h.street(c).is_empty() or (h.street(c)["c"] as Vector2).distance_to(focus) > RANGE_M:
			continue
		var top := _top(t, c)
		if top[0] == &"" or top[1] < 5.0:
			continue
		var owner := TerritorySystem.controller(t, c)
		var col: Color = TerritorySystem.GANG_COLORS.get(top[0], Color.GRAY)
		for poly in h.blocks_of(c):
			_fill(st, poly, Color(col, 0.32 if owner != &"" else 0.08 + top[1] / 100.0 * 0.15))
		_line(st, h.street(c)["pts"], 2.2 if owner != &"" else 1.0, Color(col, 0.9))

static func _top(t: TerritoryData, c: Vector2i) -> Array:
	var top: StringName = &""
	var v := 0.0
	for g in t.cells[c]:
		if t.cells[c][g] > v:
			v = t.cells[c][g]
			top = g
	return [top, v]

func _money(st: SurfaceTool) -> void:
	var data := BlockEconomyData.of(world)
	var h := Hoods.data()
	if data == null or h == null:
		return
	for c in data.blocks:
		var b := h.block(c)
		if b.is_empty() or (b["c"] as Vector2).distance_to(focus) > RANGE_M:
			continue
		var w: float = data.blocks[c]["wealth"]
		var col := POOR.lerp(MIDDLE, w * 2.0) if w < 0.5 else MIDDLE.lerp(RICH, (w - 0.5) * 2.0)
		_fill(st, b["poly"], Color(col, 0.38))

func _fill(st: SurfaceTool, poly: PackedVector2Array, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	st.set_color(col)
	for k in tris:
		st.add_vertex(Vector3(poly[k].x - origin.x, LIFT, poly[k].y - origin.y))

## A bold flat line along `pts`, `w` metres wide.
func _line(st: SurfaceTool, pts: PackedVector2Array, w: float, col: Color) -> void:
	st.set_color(col)
	for i in pts.size() - 1:
		var n := (pts[i + 1] - pts[i]).normalized().orthogonal() * w * 0.5
		var q := [pts[i] - n, pts[i + 1] - n, pts[i + 1] + n, pts[i] + n]
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(Vector3(q[k].x - origin.x, LIFT + 0.01, q[k].y - origin.y))

## Hood names over their hoods (big, always facing you), districts under them.
func _names() -> void:
	var h := Hoods.data()
	if h == null:
		return
	var centres := h.hood_centres()
	for name in centres:
		var l := Label3D.new()
		l.text = "%s\n%s" % [String(name).to_upper(), h.districts.get(name, "")]
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.pixel_size = 0.25
		l.font_size = 64
		l.outline_size = 12
		l.modulate = Color(1, 1, 1, 0.9)
		var at: Vector2 = centres[name]
		l.position = Vector3(at.x - origin.x, 30.0, at.y - origin.y)
		add_child(l)
		_labels.append(l)
