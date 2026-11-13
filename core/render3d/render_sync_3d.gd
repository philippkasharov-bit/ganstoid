## R3D3: the simulation's people and cars, standing in the 3D city. The 3D
## twin of RenderSync: it only reads World. Everyone is drawn with a handful
## of MultiMeshes (legs, torso, head; car body, cabin), so a thousand people
## cost five draw calls. Only what is near the focus (the player) is drawn;
## indoor people and anyone riding in a car are hidden. People ease toward
## their sim position and face where they walk (the player faces the mouse);
## someone down lies flat. Shirts: role colours as in 2D (you, cops,
## dealers, fixers); everyone else picks a muted colour from their id.
## R3D4: it aims the Cutaway hole at the player each frame, and a faint
## silhouette of you shows through anything that still covers you.
class_name RenderSync3D
extends Node3D

const VIEW_M := 160.0         # people and cars drawn this far round the focus
const MAX_PEOPLE := 1500
const MAX_CARS := 600
const SMOOTH := 12.0
const SNAP_M := 6.0
const LEGS := Color(0.16, 0.17, 0.22)
const SKIN := [Color("f1c7a5"), Color("d9a77f"), Color("b07a52"), Color("8a5a3b"), Color("5e3d2a")]
const SHIRTS := [Color("4a5568"), Color("7b8794"), Color("9c4a3c"), Color("3e6a5a"), Color("b8a68a"), Color("2f3b52"), Color("e2ddd2"), Color("6b4f7a")]
const CABIN := Color(0.32, 0.4, 0.48)

var world: World
var origin := Vector2.ZERO    # map point at 3D (0, 0, 0)
var footprints: Footprints    # R3D5: set by the view, to open up the building you are in
var shown_people := 0
var shown_cars := 0

var _legs := _layer(Vector3(0.45, 0.85, 0.3), MAX_PEOPLE)
var _torso := _layer(Vector3(0.55, 0.7, 0.32), MAX_PEOPLE)
var _head := _layer(Vector3(0.3, 0.3, 0.3), MAX_PEOPLE)
var _body := _layer(Vector3.ONE, MAX_CARS)
var _cabin := _layer(Vector3.ONE, MAX_CARS)
var _eased: Dictionary = {}   # person id -> [shown position, facing]
var _ghost := _silhouette()
var _player_at := Vector2.INF
var _player_face := 0.0
var _riding := false
var _car_ticks: Dictionary = {}   # car id -> [was pos, was heading, now pos, now heading]
var player_shown := Vector2.INF   # Z-feel: where the player is drawn this frame (the camera locks on it)
var _tick_was := Vector2.ZERO
var _tick_now := Vector2.INF
var _seen_from := Vector2.INF   # R3D8: last frame's eye and facing: people out of sight are not drawn
var _seen_face := 0.0
var _room := Rect2()
var _sight := SightMap.new()    # R3D11: walls block sight
var _sight_inside := "-"
const SIGHT_RECAST_M := 0.15
var _inside: MeshInstance3D     # R3D9: rooms and furniture of the building you are in
var _inside_id := ""
var _inside_mat: ShaderMaterial            # map rect of the room you are in (empty outdoors)
const CONE_COS := 0.34          # matches the Cutaway shader
const NEAR_M := 3.5
var _delta := 0.016

func _ready() -> void:
	for layer in [_legs, _torso, _head, _body, _cabin, _ghost]:
		add_child(layer)

func _process(delta: float) -> void:
	_delta = delta
	if world != null:
		sync()

## One pass: place everyone near the focus. Public so checks can call it.
func sync() -> void:
	var focus := _focus()
	_player_at = Vector2.INF
	_riding = false
	_people(focus)
	_cars(focus)
	_see_player()

## R3D4: the cutaway hole and the see-through silhouette follow you.
func _see_player() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_ghost.visible = _player_at != Vector2.INF and cam != null
	if not _ghost.visible:
		Cutaway.aim(Vector3(0, -1000, 0), Vector3.DOWN)
		Cutaway.cut(PackedInt32Array())
		return
	var chest := Vector3(_player_at.x - origin.x, 1.0, _player_at.y - origin.y)
	var view := -cam.global_basis.z
	Cutaway.aim(chest, view)
	if footprints != null:
		Cutaway.cut(footprints.covering(_player_at, Vector2(view.x, view.z)))
	_ghost.position = chest
	_ghost.visible = not _riding   # no see-through figure over the car
	Cutaway.facing(_player_face)
	_seen_from = _player_at
	_seen_face = _player_face
	_open_room()
	_cast_sight()

## R3D11: recast what walls let you see when you move or go in or out.
func _cast_sight() -> void:
	if footprints == null:
		return
	if _player_at.distance_to(_sight.from) < SIGHT_RECAST_M and _inside_id == _sight_inside:
		return
	var walls := footprints.edges_near(_player_at, SightMap.MAX_M)
	if _inside != null:
		walls.append_array(_inside.get_meta("walls", PackedVector2Array()))
	_sight.cast(_player_at, walls)
	_sight_inside = _inside_id
	Cutaway.sight(_sight.depth)

## R3D8: in your field of view (or right by you), and indoors only in your room.
func _in_sight(p: Vector2) -> bool:
	if _seen_from == Vector2.INF:
		return true
	if not _sight.sees(p):
		return false   # R3D11: behind a wall
	var d := p - _seen_from
	if d.length() < NEAR_M:
		return true
	if _room.has_area() and not _room.grow(0.4).has_point(p):
		return false
	return d.normalized().dot(Vector2.from_angle(_seen_face)) > CONE_COS

## R3D5: standing inside a footprint: that building opens up round you.
func _open_room() -> void:
	var b := footprints.building_at(_player_at) if footprints != null else {}
	_room = Rect2()
	_show_inside(b)
	if b.is_empty():
		Cutaway.room(Rect2(), false)
		return
	_room = Footprints._box(b["poly"])
	Cutaway.room(Rect2(_room.position - origin, _room.size), true)

## R3D9: the inside of the building you are in, built as you enter, dropped as you leave.
func _show_inside(b: Dictionary) -> void:
	var id: String = String(b.get("id", ""))
	if id == _inside_id:
		return
	_inside_id = id
	if _inside != null:
		_inside.queue_free()
		_inside = null
	if b.is_empty():
		return
	if _inside_mat == null:
		_inside_mat = Cutaway.material()
	_inside = InteriorMesh3D.build(b, origin, _inside_mat)
	add_child(_inside)

static func _silhouette() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 1.85, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true   # drawn over whatever stands in front
	mat.albedo_color = Color(EntityVisualFactory.PLAYER_COLOR, 0.28)
	mat.render_priority = 1
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

static func _layer(size: Vector3, count: int) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # standing rule: no shadows
	return mi

func _focus() -> Vector2:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	return (player.get_component(ComponentNames.NPC) as NPCData).position if player != null else origin

func _people(focus: Vector2) -> void:
	var n := 0
	var people := world.get_entities_with_component(ComponentNames.NPC)
	for id in people:
		var e: Entity = people[id]
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		if n >= MAX_PEOPLE or npc.indoors or npc.position.distance_squared_to(focus) > VIEW_M * VIEW_M:
			_eased.erase(id)
			continue
		var ps: PlayerStateData = e.get_component(ComponentNames.PLAYER_STATE)
		if ps != null and ps.vehicle_id != &"":
			_player_at = _player_between(npc.position)   # riding: the car is what you see; the view still follows you
			_riding = true
			continue
		var pose := _ease(id, npc, ps)
		if ps != null and not npc.is_down:
			_player_at = pose[0]
			_player_face = pose[1]
		elif not _in_sight(pose[0]):
			continue   # Zomboid: who you cannot see is not drawn
		var lit := DayNight3D.light_at(pose[0])   # R3D10: people are as dark as where they stand
		_place_person(n, pose[0], pose[1], npc.is_down, ps != null and ps.sneaking, _shirt(e, npc) * lit, SKIN[absi(String(id).hash()) % SKIN.size()] * lit)
		n += 1
	shown_people = n
	for layer in [_legs, _torso, _head]:
		layer.multimesh.visible_instance_count = n

## Shown position eases toward the sim's (the player snaps); facing follows the walk.
func _ease(id: StringName, npc: NPCData, ps: PlayerStateData) -> Array:
	var was: Array = _eased.get(id, [npc.position, 0.0])
	var at: Vector2 = was[0]
	var face: float = was[1]
	var gap := npc.position - at
	if ps != null:
		at = _player_between(npc.position)   # Z-feel: you glide between sim ticks, no stutter
	else:
		at = npc.position if gap.length() > SNAP_M else at + gap * minf(1.0, _delta * SMOOTH)
	if ps != null and ps.aim_point != npc.position:
		face = (ps.aim_point - npc.position).angle()   # you face the mouse
	elif gap.length_squared() > 0.0004 and gap.length_squared() < 25.0:
		face = lerp_angle(face, gap.angle(), 0.3)
	_eased[id] = [at, face]
	return [at, face]

## Z-feel: the player drawn between the last two sim positions, by how far
## into the next physics tick this frame is (a jump > SNAP_M just snaps).
func _player_between(sim: Vector2) -> Vector2:
	if sim != _tick_now:
		_tick_was = _tick_now if _tick_now.distance_to(sim) < SNAP_M else sim
		_tick_now = sim
	player_shown = _tick_was.lerp(_tick_now, Engine.get_physics_interpolation_fraction())
	return player_shown

## Legs, torso and head stacked; turned to face `face` (map radians). Down: flat on the ground.
func _place_person(i: int, at: Vector2, face: float, down: bool, crouched: bool, shirt: Color, skin: Color) -> void:
	var turn := Basis(Vector3.UP, -face)
	var squat := 0.8 if crouched else 1.0
	var parts := [[_legs, 0.425, LEGS], [_torso, 1.2, shirt], [_head, 1.7, skin]]
	for p in parts:
		var basis := turn.scaled(Vector3(1, squat, 1))
		var lift: float = p[1] * squat
		var pos := Vector3(at.x - origin.x, lift, at.y - origin.y)
		if down:   # lying along the way they faced
			basis = turn * Basis(Vector3.BACK, PI * 0.5)
			pos = Vector3(at.x - origin.x, 0.18, at.y - origin.y) + turn * Vector3(lift - 0.9, 0, 0)
		var mm: MultiMesh = p[0].multimesh
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_color(i, p[2])

static func _shirt(e: Entity, npc: NPCData) -> Color:
	if e.has_component(ComponentNames.PLAYER_STATE):
		return EntityVisualFactory.PLAYER_COLOR
	if npc.is_cop:
		return Color("2c3e66")   # navy uniform
	if npc.is_dealer:
		return EntityVisualFactory.DEALER_COLOR
	if npc.is_fixer:
		return Color(0.75, 0.5, 0.95)
	return SHIRTS[absi(String(npc.id).hash()) % SHIRTS.size()]

## Cars: a body box and a smaller cabin box, both the length and width the sim gives.
## A car drawn between its last two sim poses (position, heading).
func _car_between(id: StringName, car: VehicleData) -> Array:
	var t: Array = _car_ticks.get(id, [car.position, car.heading, car.position, car.heading])
	if car.position != t[2] or car.heading != t[3]:
		var jump: bool = car.position.distance_to(t[2]) > SNAP_M
		t = [car.position if jump else t[2], car.heading if jump else t[3], car.position, car.heading]
		_car_ticks[id] = t
	var f := Engine.get_physics_interpolation_fraction()
	return [(t[0] as Vector2).lerp(t[2], f), lerp_angle(t[1], t[3], f)]

func _cars(focus: Vector2) -> void:
	var n := 0
	var cars := world.get_entities_with_component(ComponentNames.VEHICLE)
	for id in cars:
		var car: VehicleData = cars[id].get_component(ComponentNames.VEHICLE)
		if n >= MAX_CARS or car.position.distance_squared_to(focus) > VIEW_M * VIEW_M:
			continue
		var pose := _car_between(id, car)   # Z-feel: a moving car glides between sim ticks too
		var turn := Basis(Vector3.UP, -pose[1])
		var at := Vector3(pose[0].x - origin.x, 0, pose[0].y - origin.y)
		_body.multimesh.set_instance_transform(n, Transform3D(turn.scaled(Vector3(car.length_m, 0.75, car.width_m)), at + Vector3(0, 0.62, 0)))
		var paint := car.color.darkened(car.damage * 0.5)
		if not _in_sight(car.position):   # R3D8: a car you cannot see stays as a dim grey shape
			paint = Color(paint.get_luminance(), paint.get_luminance(), paint.get_luminance()).lerp(paint, 0.35) * Color(0.42, 0.42, 0.42)
		_body.multimesh.set_instance_color(n, paint * DayNight3D.light_at(car.position))
		var back := turn * Vector3(-car.length_m * 0.08, 0, 0)   # cabin sits a little behind the middle
		_cabin.multimesh.set_instance_transform(n, Transform3D(turn.scaled(Vector3(car.length_m * 0.5, 0.55, car.width_m * 0.9)), at + back + Vector3(0, 1.27, 0)))
		_cabin.multimesh.set_instance_color(n, CABIN * DayNight3D.light_at(car.position))
		n += 1
	shown_cars = n
	_body.multimesh.visible_instance_count = n
	_cabin.multimesh.visible_instance_count = n
