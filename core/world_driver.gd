## Thin scene-tree adapter: the only piece of the SIMULATION layer that
## touches Godot's process loop — everything else in core/ecs stays
## engine-agnostic and testable without this node. (core/render/render_sync.gd
## is its sibling on the rendering side, reading World through this node's
## `world` property.)
##
## MG1c: every new game runs on the REAL city (fixed LA map). A fresh seed per
## run reshuffles building roles and people; the map itself never changes.
## Street routes for the district sync in the background (Godot 4.7, ~2 s): the
## HUD shows a loading line and the sim waits until they are ready.
extends Node

const DISTRICT_RADIUS := 900.0   # metres around the spawn that are simulated
const GAME_POPULATION := 1500     # POP1: 1.4 ms a tick at rush hour on a 2-core box (was 600; verify_sim_perf)
const START_HOUR := 8.0           # a new game begins in the morning rush, with everyone where their routine puts them

var world: World = World.new()
var city: CityData
var seed_used := 0
var loaded_from_save := false
var choosing := false          # O1: new game: waiting for difficulty and style
var paused := false            # PM1: the Esc menu is up (or F2): the world stands still
var speed := 1                 # Z2: Zomboid's time controls: F3 1x, F4 5x, F5 20x, F6 40x
const SPEEDS := {KEY_F3: 1, KEY_F4: 5, KEY_F5: 20, KEY_F6: 40}
var _health_seen := -1.0
var slowed_because := ""       # Z2: why fast-forward dropped back to 1x (the HUD says it once)
var _saved_hour := 0
var _dead_handled := false

func _ready() -> void:
	UserDirMove.run()   # UI17: saves from before the rename to Tagged
	city = CityData.load_file()
	var saved := SaveGame.read()   # SL1: carry on where the last session ended, if alive
	seed_used = saved["seed"] if not saved.is_empty() else randi()
	SystemRegistry.register_all(world)
	TrafficSystem.roads = city.roads   # V2: traffic drives the real streets
	TrafficSystem.junctions = Junctions.load_file()   # MP3a: lights and stop signs
	DriveSystem.graph = RoadGraph.build(city.roads)   # V4: people drive the real streets
	WorldGenerator.generate_real_city_game(world, seed_used, city, city.spawn, DISTRICT_RADIUS, GAME_POPULATION)
	world.tick = SimClock.hours(START_HOUR)
	if not saved.is_empty():
		if saved["entities"].has(GameRules.ENTITY):
			GameRules.install(world, 1, 1)   # the saved fields go over it
		SaveGame.apply(world, saved)
		if GameRules.of(world) == null:
			GameRules.install(world, 1, 1)   # a save from before play modes: Normal / Street life
		loaded_from_save = true
	_saved_hour = world.tick / SimClock.hours(1.0)
	if saved.is_empty() and not Engine.has_meta("skip_new_game"):
		choosing = true   # O1: ask how to play before the world starts
		var panel := NewGamePanel.new()
		get_parent().get_node("HudLayer").add_child.call_deferred(panel)   # screen space, over the HUD
		panel.open(self)
	elif saved.is_empty():
		GameRules.install(world, 1, 1)
	(world.find_system(NPCScheduleSystem) as NPCScheduleSystem).settle_all(world.tick)
	_install_routes.call_deferred()

func _install_routes() -> void:
	await get_tree().process_frame   # let the loading line render first
	await get_tree().process_frame
	SimNav.install(city, city.spawn, DISTRICT_RADIUS)
	StreetLights.install(city, city.spawn, DISTRICT_RADIUS)   # R3D10b: who sees you at night depends on the lamps

## O1: the new-game choice made: the run starts.
func choose(difficulty: int, style: int) -> void:
	GameRules.install(world, difficulty, style)
	choosing = false

func _physics_process(delta: float) -> void:
	if SimNav.active == null or not SimNav.active.usable() or choosing or paused:
		return   # routes still loading, or the new-game choice not made: nobody moves yet
	_check_speed()
	var steps := NeedsSystem.SLEEP_SPEED if _asleep() else speed   # G2 sleep / Z2 time controls
	for i in steps:
		world.step(delta)
	_keep_save()

func _asleep() -> bool:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null:
		return false
	var st: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	return st.sleeping or st.prison_until_tick > 0 or st.work_until_tick > 0   # CP1/O1: prison and shifts pass fast too

## SL1: save every in-game hour (2.5 real minutes); a dead player's save is gone.
func _keep_save() -> void:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null and _dead(player.get_component(ComponentNames.NPC)):
		var rules := GameRules.of(world)
		if rules != null and rules.rescue():
			_rescue(player)   # O1 Casual: you wake up at home instead
			return
		if not _dead_handled:
			_dead_handled = true
			HallOfFame.record(world, seed_used)
			SaveGame.delete()
		return
	var hour := world.tick / SimClock.hours(1.0)
	if hour != _saved_hour:
		_saved_hour = hour
		SaveGame.write_in_background(world, seed_used)

## O1 Casual: someone found you and got you home. It cost you half your cash.
func _rescue(player: Entity) -> void:
	var me: NPCData = player.get_component(ComponentNames.NPC)
	var st: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	me.is_down = false
	me.bleeding = false
	me.health = 0.3
	me.cash /= 2
	st.dirty_cash = mini(st.dirty_cash, me.cash)
	var home: Entity = world.entities.get(me.home_building_id)
	if home != null:
		me.position = home.get_component(ComponentNames.BUILDING).position
		world.reindex_position(me.id)
	GameRules.of(world).rescues += 1
	StreetTalk.say_key(world, st, "rescued")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _dead_handled and SimNav.active != null:
		SaveGame.write(world, seed_used)   # quitting saves, like Zomboid

## Z2: F2 pauses (no menu), F3-F6 set the speed, like Zomboid's single player.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or choosing:
		return
	if event.keycode == KEY_F2:
		paused = not paused
	elif SPEEDS.has(event.keycode):
		speed = SPEEDS[event.keycode]
		paused = false
		slowed_because = ""

## Z2: fast-forward is for quiet moments. It drops back to 1x the moment you
## are hurt, bleeding, wanted, aiming, or in a menu, and says why.
func _check_speed() -> void:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null:
		return
	var npc: NPCData = player.get_component(ComponentNames.NPC)
	var st: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	var why := fast_forward_blocker(npc, st, _health_seen)
	_health_seen = npc.health
	if speed > 1 and why != "":
		speed = 1
		slowed_because = why
		_slowed_at = Time.get_ticks_msec()

var _slowed_at := 0
const SLOWED_SHOWN_MS := 5000

func _process(_delta: float) -> void:
	if slowed_because != "" and Time.get_ticks_msec() - _slowed_at > SLOWED_SHOWN_MS:
		slowed_because = ""   # the "why" line on the clock has been read

## Why fast-forward must stop right now ("" when it may run).
static func fast_forward_blocker(npc: NPCData, st: PlayerStateData, health_before: float) -> String:
	if health_before >= 0.0 and npc.health < health_before - 0.0001:
		return "you're hurt"
	if npc.bleeding:
		return "you're bleeding"
	if st.law_tier > 0:
		return "the police are looking"
	if st.aiming:
		return "weapon up"
	if not st.menu_options.is_empty() or st.store_id != &"" or st.inventory_open:
		return "a menu is open"
	return ""

## C6 permadeath: once the player is down, Enter starts a new run (new seed).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept"):
		return
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null and _dead(player.get_component(ComponentNames.NPC)):
		get_tree().reload_current_scene()

func _exit_tree() -> void:
	SimNav.uninstall()

static func _dead(npc: NPCData) -> bool:
	return npc.is_down and npc.ko_until_tick < 0   # out cold is not dead
