## AU1: the city you hear. Like RenderSync3D it only reads World (and hears
## its EventBus), then plays what fits:
##   ambience  day traffic or night crickets by the hour, a crowd murmur when
##             people are close, all muffled indoors
##   you       footsteps (quieter crouched), doors as you go in and out, your
##             swings, the car door, the engine by speed and the car radio
##   the city  gunshots (far ones duller), blows landing, cars passing, a
##             siren on the car chasing you, far-off dogs, horns and sirens
##   moments   cash in, stamps, a new rank, the phone, the pager tip, a hit
## Sounds sit where they happen (AudioStreamPlayer3D round a listener on the
## player, turned with the camera). Its own RNG: sound never touches the sim's.
class_name AudioDirector
extends Node3D

const STEP_M := 0.75        # a walking stride
const RUN_STEP_M := 1.15
const RUN_SPEED := 3.2      # m/s above which steps are running steps
const STEP_GAP_S := 0.16    # never faster than this, even at 20x
const CROWD_R := 28.0       # people this close make the murmur
const CROWD_FULL := 18      # this many make it full
const TRAFFIC_R := 70.0
const CAR_PASS_M := 8.0
const SCAN_S := 0.5
const POOL_3D := 16
const POOL_UI := 6
const SHOT_NEAR_M := 60.0   # further off, the dull far shot
const FADE_PER_S := 0.8     # ambience volume moves this much a second (0..1)
const SPOT_GAP := Vector2(6.0, 15.0)   # seconds between far-off city sounds
const DAY_SPOTS := ["bird", "bird", "distant_horn", "dog"]
const NIGHT_SPOTS := ["dog", "siren_far", "distant_horn"]
const SWING := {&"fists": "swing", &"knife": "slash", &"bat": "swing"}
## The sound for a StreetTalk line (by its key).
const KEY_SOUND := {
	"locked": "rattle", "breaking_in": "lockpick", "hotwiring": "lockpick",
	"car_in": "car_door", "car_out": "car_door", "car_wrecked": "crash",
	"jammed": "dry_fire", "no_ammo": "dry_fire", "unjammed": "equip", "repaired": "equip",
	"weapon_fists": "equip", "weapon_knife": "equip", "weapon_bat": "equip", "weapon_pistol": "equip",
	"weapon_broke": "bat_hit", "chase_on": "ui_alert", "chase_lost": "ui_good",
	"arrested": "ui_bad", "arrested_seized": "ui_bad", "sentenced": "ui_bad", "lift_caught": "ui_bad",
	"gang_coming": "ui_alert", "rival_coming": "ui_alert", "gang_warning": "ui_alert", "witness_running": "ui_alert",
	"job_failed": "ui_bad", "cant_afford": "ui_bad", "released": "ui_good", "licence_bought": "ui_good",
}

var world: World
var origin := Vector2.ZERO
var camera: Camera3D
var footprints: Footprints   # to know when you are indoors (null: never)
var played: Array[String] = []   # the last sounds, newest last (checks)

var _listener := AudioListener3D.new()
var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _radio: AudioStreamPlayer
var _siren: AudioStreamPlayer3D
var _pool: Array[AudioStreamPlayer3D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _next := 0
var _next_ui := 0
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _scan_at := 0.0
var _crowd_k := 0.0
var _traffic := 0.0
var _pass_at := 0.0
var _spot_at := 4.0
var _far_siren_at := 0.0
var _hunted := false
var _last := Vector2.INF
var _walked := 0.0
var _step_t := 0.0
var _step_i := 0
var _inside := false
var _in_car := false
var _station := -1
var _cash := -1
var _stamp := -1
var _inbox := -1
var _tip := -1
var _hurt := -1
var _said := -1
var _attack: Dictionary = {}

func _ready() -> void:
	AudioBank.ensure_buses()
	_rng.seed = 9091
	add_child(_listener)
	_listener.make_current()
	_day = _loop("amb_day")
	_night = _loop("amb_night")
	_crowd = _loop("amb_crowd")
	_engine = _loop("engine", false)
	_radio = _loop("", false, &"Music")
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = AudioBank.stream("siren")
	_siren.bus = &"Effects"
	_siren.unit_size = 25.0
	_siren.max_distance = 600.0
	add_child(_siren)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Effects"
		p.unit_size = 8.0
		p.max_distance = 400.0
		add_child(p)
		_pool.append(p)
	for i in POOL_UI:
		var u := AudioStreamPlayer.new()
		u.bus = &"Effects"
		add_child(u)
		_ui_pool.append(u)
	if world != null:
		world.event_bus.subscribe(_on_event)
	get_tree().node_added.connect(_hook)
	for n in get_tree().root.find_children("*", "", true, false):
		_hook(n)

## A looping player, silent until the ambience fades it in.
func _loop(name: String, start := true, bus := &"Effects") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	if name != "":
		p.stream = AudioBank.stream(name)
	add_child(p)
	if start and p.stream != null:
		p.play()
	return p

func _process(delta: float) -> void:
	_t += delta
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if world != null else null
	if player == null:
		return
	var me: NPCData = player.get_component(ComponentNames.NPC)
	var st: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var basis := camera.global_transform.basis if camera != null and camera.is_inside_tree() else Basis.IDENTITY
	_listener.global_transform = Transform3D(basis, to_3d(me.position) + Vector3(0, 1.6, 0))
	if _t >= _scan_at:
		_scan_at = _t + SCAN_S
		_scan(me, st)
	_ambience(delta)
	_steps(delta, me, st)
	_car(st)
	_moments(me, st)
	_spots(me)

## Map metres to the 3D view's space (GameView3D: x east, z south, round origin).
func to_3d(p: Vector2) -> Vector3:
	return Vector3(p.x - origin.x, 0.0, p.y - origin.y)

## Plays `name` where it happens in the city.
func play_at(name: String, at: Vector2, db := 0.0, pitch := 1.0) -> void:
	_log(name)
	var s := AudioBank.stream(name)
	if s == null or _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.position = to_3d(at) + Vector3(0, 1.0, 0)
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()

## Plays `name` flat (interface sounds, your own moments).
func ui(name: String, db := 0.0) -> void:
	_log(name)
	var s := AudioBank.stream(name)
	if s == null or _ui_pool.is_empty():
		return
	var p := _ui_pool[_next_ui]
	_next_ui = (_next_ui + 1) % _ui_pool.size()
	p.stream = s
	p.volume_db = db
	p.play()

func _log(name: String) -> void:
	played.append(name)
	if played.size() > 60:
		played.pop_front()

## Who and what is round you, twice a second: the crowd, the traffic, a car
## going by, indoors or out, the police.
func _scan(me: NPCData, st: PlayerStateData) -> void:
	var people := 0
	var cars := 0
	for id in world.spatial_index.query_nearby(me.position):
		var e: Entity = world.entities.get(id)
		if e == null or id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n != null:
			if not n.is_down and n.position.distance_squared_to(me.position) < CROWD_R * CROWD_R:
				people += 1
			continue
		var c: VehicleData = e.get_component(ComponentNames.VEHICLE)
		if c == null or absf(c.speed) < 2.0 or id == st.vehicle_id:
			continue
		var d := c.position.distance_to(me.position)
		if d < TRAFFIC_R:
			cars += 1
		if d < CAR_PASS_M and absf(c.speed) > 6.0 and _t >= _pass_at:
			_pass_at = _t + 1.5
			play_at("car_pass", c.position, -4.0, _rng.randf_range(0.9, 1.1))
	_crowd_k = clampf(float(people - 2) / CROWD_FULL, 0.0, 1.0)
	_traffic = clampf(cars / 6.0, 0.0, 1.0)
	var inside := footprints != null and not footprints.at(me.position).is_empty()
	if inside != _inside and _last != Vector2.INF and st.vehicle_id == &"":
		play_at("door_open", me.position, -6.0)
	_inside = inside
	_police(me)

func _police(me: NPCData) -> void:
	var traffic := world.find_system(TrafficSystem) as TrafficSystem
	var chaser := traffic.chaser_at() if traffic != null else Vector2.INF
	if chaser != Vector2.INF:
		_siren.position = to_3d(chaser) + Vector3(0, 1.5, 0)
		if not _siren.playing:
			_siren.play()
			_log("siren")
	elif _siren.playing:
		_siren.stop()
	var cops := world.find_system(CopAISystem) as CopAISystem
	_hunted = cops != null and not cops.hunters().is_empty()
	if _hunted and _t >= _far_siren_at and chaser == Vector2.INF:
		_far_siren_at = _t + _rng.randf_range(7.0, 14.0)
		play_at("siren_far", me.position + Vector2.from_angle(_rng.randf() * TAU) * 120.0)

## 0 by day, 1 at night, easing at dusk (19-21) and dawn (5-7).
static func night_of(hour: float) -> float:
	if hour >= 21.0 or hour < 5.0:
		return 1.0
	if hour < 7.0:
		return 1.0 - (hour - 5.0) / 2.0
	if hour >= 19.0:
		return (hour - 19.0) / 2.0
	return 0.0

func _ambience(delta: float) -> void:
	var night := night_of(SimClock.day_fraction(world.tick) * 24.0)
	var walls := 0.3 if _inside else 1.0
	_fade(_day, (1.0 - night) * (0.5 + 0.5 * _traffic) * walls, delta)
	_fade(_night, (night * 0.8 + night * _traffic * 0.2) * walls, delta)
	_fade(_crowd, _crowd_k * (1.0 - night * 0.4) * (0.25 if _inside else 1.0), delta)

## Eases a loop toward `level` (0..1).
func _fade(p: AudioStreamPlayer, level: float, delta: float) -> void:
	var now := db_to_linear(p.volume_db)
	var to := move_toward(now, level, FADE_PER_S * delta)
	p.volume_db = linear_to_db(maxf(to, 0.0001))

func ambience_level(which: String) -> float:
	var p: AudioStreamPlayer = {"day": _day, "night": _night, "crowd": _crowd}.get(which)
	return db_to_linear(p.volume_db) if p != null else 0.0

func _steps(delta: float, me: NPCData, st: PlayerStateData) -> void:
	if st.vehicle_id != &"" or me.is_down or st.sleeping or _last == Vector2.INF:
		_last = me.position
		return
	var moved := me.position.distance_to(_last)
	_last = me.position
	if moved > 5.0:
		return   # a teleport or a skipped hour, not a step
	_walked += moved
	var running := moved / maxf(delta, 0.001) > RUN_SPEED
	if _walked >= (RUN_STEP_M if running else STEP_M) and _t - _step_t >= STEP_GAP_S:
		_walked = 0.0
		_step_t = _t
		_step_i += 1
		var db := -4.0 if running else -9.0
		if st.sneaking:
			db -= 12.0
		play_at("step_%d" % (1 + _step_i % 4), me.position, db, _rng.randf_range(0.92, 1.08))

## In a car: the engine by speed, and the radio (the next station each time you get in).
func _car(st: PlayerStateData) -> void:
	var in_car := st.vehicle_id != &""
	if in_car != _in_car:
		_in_car = in_car
		if in_car:
			_station = (_station + 1) % AudioBank.STATIONS.size()
			_radio.stream = AudioBank.stream(AudioBank.STATIONS[_station])
			_radio.volume_db = -6.0
			_engine.volume_db = -14.0
			if _radio.stream != null:
				_radio.play()
			if _engine.stream != null:
				_engine.play()
			_log(AudioBank.STATIONS[_station])
		else:
			_radio.stop()
			_engine.stop()
	if in_car:
		var e: Entity = world.entities.get(st.vehicle_id)
		var c: VehicleData = e.get_component(ComponentNames.VEHICLE) if e != null else null
		var speed := absf(c.speed) if c != null else 0.0
		_engine.pitch_scale = clampf(0.7 + speed / 16.0, 0.7, 2.4)
		_engine.volume_db = -14.0 + minf(speed, 20.0) * 0.35

## The moments that are yours: cash, stamps, the phone, tips, hits, your lines.
func _moments(me: NPCData, st: PlayerStateData) -> void:
	if _cash >= 0 and me.cash > _cash:
		ui("ui_cash", -2.0)
	_cash = me.cash
	if _stamp >= 0 and st.stamp_serial != _stamp:
		var sub: String = st.stamp.get("sub", "")
		var bad: bool = st.stamp.get("color", Color.WHITE) == UiTheme.BAD
		ui("ui_rank" if sub == "NEW RANK" else "ui_stamp")
		if bad:
			ui("ui_bad", -4.0)
	_stamp = st.stamp_serial
	if _inbox >= 0 and st.inbox.size() > _inbox:
		ui("phone_buzz", -3.0)
	_inbox = st.inbox.size()
	if _tip >= 0 and st.tip_serial != _tip:
		ui("pager", -6.0)
	_tip = st.tip_serial
	if _hurt >= 0 and st.hurt_serial != _hurt:
		ui("punch", -2.0)
	_hurt = st.hurt_serial
	if _said >= 0 and st.message_serial != _said and KEY_SOUND.has(st.message_key):
		play_at(KEY_SOUND[st.message_key], me.position, -3.0)
	_said = st.message_serial
	if not is_same(st.last_attack, _attack):
		_attack = st.last_attack
		var weapon: StringName = _attack.get("weapon", &"")
		if SWING.has(weapon):
			play_at(SWING[weapon], me.position, -6.0, _rng.randf_range(0.9, 1.1))
			if weapon == &"bat" and _attack.has("hit_id"):
				play_at("bat_hit", me.position, -2.0)

## Now and then something far off: birds and horns by day, dogs and sirens by night.
func _spots(me: NPCData) -> void:
	if _t < _spot_at:
		return
	_spot_at = _t + _rng.randf_range(SPOT_GAP.x, SPOT_GAP.y)
	if _inside or _in_car:
		return
	var night := night_of(SimClock.day_fraction(world.tick) * 24.0) > 0.5
	var list: Array = NIGHT_SPOTS if night else DAY_SPOTS
	var far := me.position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40.0, 110.0)
	play_at(list[_rng.randi() % list.size()], far, -8.0, _rng.randf_range(0.9, 1.1))

func _on_event(event_name: StringName, payload: Dictionary) -> void:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null:
		return
	var you: Vector2 = (player.get_component(ComponentNames.NPC) as NPCData).position
	match event_name:
		GanstoidEvents.GUNSHOT:
			var at: Vector2 = payload.get("position", you)
			play_at("shot" if at.distance_to(you) < SHOT_NEAR_M else "shot_far", at, 0.0, _rng.randf_range(0.95, 1.05))
		GanstoidEvents.WOUNDED:
			var e: Entity = world.entities.get(payload.get("id", &""))
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n != null and e.id != PlayerFactory.PLAYER_ENTITY_ID:
				play_at("punch", n.position, -3.0, _rng.randf_range(0.9, 1.1))

## Buttons click; windows make a sound opening and closing.
func _hook(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_click):
		n.pressed.connect(_click)
	elif n is UiWindow and not n.visibility_changed.is_connected(_window):
		n.visibility_changed.connect(_window.bind(n))

func _click() -> void:
	ui("ui_click", -4.0)

func _window(w: UiWindow) -> void:
	if _t > 1.0:
		ui("ui_open" if w.visible else "ui_close", -6.0)

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_hook):
		get_tree().node_added.disconnect(_hook)
