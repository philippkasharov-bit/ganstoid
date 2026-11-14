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

var world: World
var origin := Vector2.ZERO    # map point at 3D (0, 0, 0)
var footprints: Footprints    # R3D5: set by the view, to open up the building you are in
var shown_people := 0
var shown_cars := 0

var _rig := PersonRig3D.new(MAX_PEOPLE)   # D1: legs and arms that swing as people walk
var _car_rig := CarRig3D.new(MAX_CARS)   # D1: wheels that roll, lamps that light
var _eased: Dictionary = {}   # person id -> [shown position, facing]
var _ghost := PersonLook3D.silhouette()
var _player_at := Vector2.INF
var _player_face := 0.0
var _riding := false
var _attack_seen: Dictionary = {}   # D3: the last attack already shown
var _strike_left := 0.0
var _aim_amount := 0.0
const STRIKE_S := 0.22
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
var _indoor: Dictionary = {}    # R3D15: id -> [point, facing, lying] for people in your building
var _indoor_at := -1000000
const INDOOR_EVERY_TICKS := 60
var _inside_mat: ShaderMaterial            # map rect of the room you are in (empty outdoors)
const CONE_COS := 0.34          # matches the Cutaway shader
const NEAR_M := 3.5
var _delta := 0.016
var _cut_insides := CutInteriors3D.new()

func _ready() -> void:
	_rig.origin = origin
	_car_rig.origin = origin
	_cut_insides.origin = origin
	for layer in [_rig, _car_rig, _ghost, _cut_insides]:
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
		var tags := footprints.covering(_player_at, Vector2(view.x, view.z))
		Cutaway.cut(tags)
		_cut_insides.footprints = footprints
		_cut_insides.show_for(tags, _inside_id)   # A1b: a cut building shows its rooms
	_ghost.position = chest
	_ghost.visible = false   # P1: the clean cut already shows you; the see-through box only covered your figure
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
	var walls := footprints.edges_near(_player_at, SightMap.MAX_M, StringName(_inside_id))
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
	if not b.is_empty() and (id != _inside_id or world.tick >= _indoor_at + INDOOR_EVERY_TICKS):
		_indoor = IndoorPeople3D.place(world, b)   # R3D15: who is home, where in the rooms
		_indoor_at = world.tick
	elif b.is_empty():
		_indoor = {}
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

func _focus() -> Vector2:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	return (player.get_component(ComponentNames.NPC) as NPCData).position if player != null else origin

func _people(focus: Vector2) -> void:
	var n := 0
	var people := world.get_entities_with_component(ComponentNames.NPC)
	for id in people:
		var e: Entity = people[id]
		var npc: NPCData = e.get_component(ComponentNames.NPC)
		var home: Array = _indoor.get(id, [])   # R3D15: indoors, drawn only inside the building you are in
		if n >= MAX_PEOPLE or (npc.indoors and home.is_empty()) or npc.position.distance_squared_to(focus) > VIEW_M * VIEW_M:
			_eased.erase(id)
			_rig.forget(id)
			continue
		if npc.indoors:
			if _in_sight(home[0]):
				_rig.place(n, home[0], home[1], 0.0, 0.0, home[2], false, PersonLook3D.shirt(e, npc), PersonLook3D.skin(id))
				n += 1
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
		if ps != null:
			lit = maxf(lit, 0.65)   # P1: you can always see yourself
		var step := _rig.gait(id, pose[0], _delta)
		var arms := _arms(ps)   # D3: aiming and striking
		_rig.place(n, pose[0], pose[1], step[0], step[1], npc.is_down, ps != null and ps.sneaking, PersonLook3D.shirt(e, npc) * lit, PersonLook3D.skin(id) * lit, arms.x, arms.y)
		n += 1
	shown_people = n
	_rig.set_count(n)

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

## Cars: drawn by CarRig3D; a car you cannot see stays a dim grey shape.
func _cars(focus: Vector2) -> void:
	var n := 0
	var cars := world.get_entities_with_component(ComponentNames.VEHICLE)
	for id in cars:
		var car: VehicleData = cars[id].get_component(ComponentNames.VEHICLE)
		if n >= MAX_CARS or car.position.distance_squared_to(focus) > VIEW_M * VIEW_M:
			continue
		var paint := car.color.darkened(car.damage * 0.5)
		if not _in_sight(car.position):
			paint = Color(paint.get_luminance(), paint.get_luminance(), paint.get_luminance()).lerp(paint, 0.35) * Color(0.42, 0.42, 0.42)
		_car_rig.place(n, id, car, paint, DayNight3D.light_at(car.position), car.driver_id != &"" and DayNight3D.night > 0.3)
		n += 1
	shown_cars = n
	_car_rig.set_count(n)

## D3: the player's arms: up while aiming, the right one thrown on each attack (a quick out-and-back).
func _arms(ps: PlayerStateData) -> Vector2:
	if ps == null:
		return Vector2.ZERO
	if not is_same(ps.last_attack, _attack_seen) and not ps.last_attack.is_empty():
		_attack_seen = ps.last_attack
		_strike_left = STRIKE_S
	_strike_left = maxf(0.0, _strike_left - _delta)
	_aim_amount = lerpf(_aim_amount, 1.0 if ps.aiming else 0.0, minf(1.0, _delta * 12.0))
	return Vector2(_aim_amount, sin(_strike_left / STRIKE_S * PI))
