## Phase 2 batch 13: the first on-screen text in the game. Read-only view of
## the player's own state -- cash, inventory, law tier, gang/solo standing --
## same strictly-read-only relationship to World that RenderSync has, just
## drawing text into screen space instead of shapes into world space.
## Lives under a CanvasLayer so it stays pinned to the screen regardless of
## where the Camera2D is looking.
class_name Hud
extends Label

@export var world_driver_path: NodePath

var _world: World

## Batch 14: how long a StreetTalk line stays on screen, in real seconds.
const MESSAGE_SECONDS := 4.0
var _seen_serial := 0
var _refresh_in := 0.0
const REFRESH_SECONDS := 0.25
var _message_time_left := 0.0
var _title_art: TextureRect
var _show_fps := false
var _loaded := false

func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_F3:
		_show_fps = not _show_fps
func _ready() -> void:
	_world = get_node(world_driver_path).world
	position = Vector2(12, 8)
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	var roster := CrewRoster.new()  # batch 22: Tab toggles it
	get_parent().add_child.call_deferred(roster)
	roster.setup(_world)
	var store := StorePanel.new()   # G1: E at a counter
	get_parent().add_child.call_deferred(store)
	store.setup(_world, Vector2(68, 124))
	var bag := InventoryWindow.new()  # UI5: I
	get_parent().add_child.call_deferred(bag)
	bag.setup(_world, Vector2(68, 124))
	var menu := ActionMenu.new()      # UI1: E
	get_parent().add_child.call_deferred(menu)
	menu.setup(_world, Vector2(68, 124))
	var card := StatusCard.new()      # UI2: bars and status
	get_parent().add_child.call_deferred(card)
	card.setup(_world)
	var clock := ClockBox.new()       # UI6: Zomboid layout
	get_parent().add_child.call_deferred(clock)
	clock.setup(_world)
	var moodles := Moodles.new()
	get_parent().add_child.call_deferred(moodles)
	moodles.setup(_world)
	moodles.below = clock   # UI26: the column hangs under the clock, same right edge
	var skills := CharacterWindow.new()
	get_parent().add_child.call_deferred(skills)
	var right := get_viewport().get_visible_rect().size.x
	skills.setup(_world, Vector2(right - 340, 66))   # UIF2: docked right, like Zomboid
	var eye := DetectionEye.new()   # UIF4: who can see you, its own HUD piece
	get_parent().add_child.call_deferred(eye)
	eye.setup(_world)
	var health := HealthWindow.new()   # HP1: H
	get_parent().add_child.call_deferred(health)
	health.setup(_world, Vector2(right * 0.5 - 180, 80))   # UI26: opens mid-screen, fully visible
	var bar := SideBar.new()
	get_parent().add_child.call_deferred(bar)
	bar.setup(_world)
	_title_art = TextureRect.new()    # UI16: the title art while the streets load
	if ResourceLoader.exists(UiTheme.STREET + "title.jpg"):
		_title_art.texture = load(UiTheme.STREET + "title.jpg")
	_title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_title_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_parent().add_child.call_deferred(_title_art)
	var openings := OpeningsView.new()   # DW2: broken doors, smashed and boarded windows
	get_parent().add_child.call_deferred(openings)
	openings.setup(_world)
	get_parent().move_child.call_deferred(openings, 0)
	var ground := GroundView.new()          # INV4: dropped piles on the map
	get_parent().add_child.call_deferred(ground)
	ground.setup(_world)
	get_parent().move_child.call_deferred(ground, 0)
	var progress := ActionProgress.new()   # TA1: bar over the head
	get_parent().add_child.call_deferred(progress)
	progress.setup(_world)
	var toast := Toast.new()          # UI2: pop-up lines
	get_parent().add_child.call_deferred(toast)
	toast.setup(_world)
	position = Vector2(68, 124)

func _process(delta: float) -> void:
	if _world == null:
		return
	var loading := not _loaded and (SimNav.active == null or not SimNav.active.is_ready())
	_loaded = _loaded or not loading   # the title art is for the first load only; later nav rebuilds (night) stay invisible
	_title_art.visible = loading
	if loading:
		text = "Loading the streets of the city..."
		move_to_front()   # the loading line sits on the title art, bottom-left
		position = Vector2(28, get_viewport_rect().size.y - 56)
		add_theme_font_override("font", UiTheme.font("marker"))
		add_theme_font_size_override("font_size", 24)
		return
	if has_theme_font_override("font"):
		remove_theme_font_override("font")
		add_theme_font_size_override("font_size", 11)
	position = Vector2(6, get_viewport_rect().size.y - size.y - 4)   # UI18: fps and deal timers bottom-left, off the panels
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return   # the text walks every building twice: four times a second is plenty
	_refresh_in = REFRESH_SECONDS
	delta = REFRESH_SECONDS
	var player: Entity = _world.entities.get(&"player")
	if player == null:
		text = ""
		return
	var npc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	if npc.is_down and npc.ko_until_tick >= 0:
		text = "Knocked out..."
		return
	if npc.is_down and not HallOfFame.read().is_empty():
		var lines: PackedStringArray = ["You are dead. You lasted %s." % SimClock.lasted(float(_world.tick) / SimClock.day_ticks), "The city goes on without you.", "", "HALL OF FAME"]
		for r in HallOfFame.top(5):
			lines.append("%s  ·  lasted %s  ·  $%d  ·  %s  ·  %s" % [r["rank_name"], SimClock.lasted(r["days"]), r["cash"], r["traits"], r["mode"]])
		lines.append("")
		lines.append("Press Enter to start a new life.")
		text = "\n".join(lines)
		return
	if npc.is_down:
		text = "You are dead. You lasted %s.\nThe city goes on without you.\n\nPress Enter to start a new life." % SimClock.lasted(float(_world.tick) / SimClock.day_ticks)
		return
	# UI2: the status card and toasts carry the game state; this line only
	# keeps what has no home yet (a deal in progress) and a small fps readout.
	var parts: PackedStringArray = []
	if _show_fps:   # UIF1: F3 toggles the fps readout
		parts.append("%d fps" % Engine.get_frames_per_second())
	if not state.pending_deal.is_empty():
		parts.append("Dealing... %ds" % ceili(state.pending_deal["ticks_left"] / 60.0))
	if state.hotwire_id != &"" or state.burglary_id != &"":
		parts.append("Working... stay put")
	text = "   ·   ".join(parts)

func _clock() -> String:
	var hours := SimClock.day_fraction(_world.tick) * 24.0
	return "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60.0)]

## People on the street right now (indoors ones are not drawn).
func _turf_line(npc: NPCData) -> String:
	var t := TerritorySystem.data(_world)
	if t == null:
		return ""
	var c := TerritoryData.cell_of(npc.position)
	var owner := TerritorySystem.controller(t, c)
	var who := "nobody's" if owner == &"" else ("YOURS" if owner == TerritorySystem.PLAYER else _gang_name(owner))
	return "Turf: %s block (you %d)   blocks held %d   (T: tag, U: turf map)" % [who, roundi(TerritorySystem.get_influence(t, c, TerritorySystem.PLAYER)), TerritorySystem.cells_held(t, TerritorySystem.PLAYER)]

static func _need(v: float) -> String:
	if v < NeedsSystem.LOW:
		return "LOW %d%%" % roundi(v * 100)
	return "%d%%" % roundi(v * 100)

func _outdoors() -> int:
	var n := 0
	for e in _world.get_entities_with_component(ComponentNames.NPC).values():
		n += int(not e.get_component(ComponentNames.NPC).indoors)
	return n

func _format_inventory(inventory: Dictionary) -> String:
	var parts: PackedStringArray = []
	for good_id in inventory:
		if inventory[good_id] > 0:
			parts.append("%s x%d" % [good_id, inventory[good_id]])
	return "empty" if parts.is_empty() else ", ".join(parts)

## Only relationships the player has actually touched are listed -- an
## untouched gang/solo is neutral by definition and not worth screen space.
func _format_standing(state: PlayerStateData) -> String:
	var parts: PackedStringArray = []
	for gang_id in state.gang_standing:
		parts.append("%s %d%%" % [_gang_name(gang_id), roundi(state.gang_standing[gang_id] * 100.0)])
	for npc_id in state.solo_standing:
		parts.append("%s %d%%" % [npc_id, roundi(state.solo_standing[npc_id] * 100.0)])
	return "none yet" if parts.is_empty() else ", ".join(parts)

func _gang_name(gang_id: StringName) -> String:
	var gang_entity: Entity = _world.entities.get(gang_id)
	if gang_entity == null:
		return String(gang_id)
	var gang: GangData = gang_entity.get_component(ComponentNames.GANG)
	return gang.display_name
