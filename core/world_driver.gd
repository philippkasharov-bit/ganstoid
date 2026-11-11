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
const GAME_POPULATION := 600      # S1: the sim costs about 0.5 ms a tick at this size (verify_sim_perf)
const START_HOUR := 8.0           # a new game begins in the morning rush, with everyone where their routine puts them

var world: World = World.new()
var city: CityData
var seed_used := 0
var loaded_from_save := false
var choosing := false          # O1: new game: waiting for difficulty and style
var _saved_hour := 0
var _dead_handled := false

func _ready() -> void:
	city = CityData.load_file()
	var saved := SaveGame.read()   # SL1: carry on where the last session ended, if alive
	seed_used = saved["seed"] if not saved.is_empty() else randi()
	SystemRegistry.register_all(world)
	TrafficSystem.roads = city.roads   # V2: traffic drives the real streets
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

## O1: the new-game choice made: the run starts.
func choose(difficulty: int, style: int) -> void:
	GameRules.install(world, difficulty, style)
	choosing = false

func _physics_process(delta: float) -> void:
	if SimNav.active == null or not SimNav.active.is_ready() or choosing:
		return   # routes still loading, or the new-game choice not made: nobody moves yet
	var steps := NeedsSystem.SLEEP_SPEED if _asleep() else 1   # G2: sleep is the only fast-forward
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
