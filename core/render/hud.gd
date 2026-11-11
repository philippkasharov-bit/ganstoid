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

func _ready() -> void:
	_world = get_node(world_driver_path).world
	position = Vector2(12, 8)
	add_theme_font_size_override("font_size", 16)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	var roster := CrewRoster.new()  # batch 22: Tab toggles it
	get_parent().add_child.call_deferred(roster)
	roster.setup(_world)
	var store := StorePanel.new()   # G1: E at a counter
	get_parent().add_child.call_deferred(store)
	store.setup(_world, Vector2(12, 290))
	var bag := InventoryPanel.new()   # G2: I
	get_parent().add_child.call_deferred(bag)
	bag.setup(_world, Vector2(12, 290))
	var menu := ActionMenu.new()      # UI1: E
	get_parent().add_child.call_deferred(menu)
	menu.setup(_world, Vector2(12, 290))

func _process(delta: float) -> void:
	if _world == null:
		return
	if SimNav.active == null or not SimNav.active.is_ready():
		text = "Loading the streets of the city..."
		return
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
	if npc.is_down:
		text = "You are dead. The city goes on without you.\n\nPress Enter to start a new life."
		return
	text = "\n".join([
		"Cash: $%d clean, $%d dirty" % [npc.cash - state.dirty_cash, state.dirty_cash],
		"Rank: %s (%d to next)   Heat: %s" % [RankSystem.name_of(state.rank), RankSystem.to_next(_world, npc, state), GanstoidEnums.LawTier.keys()[state.law_tier]],
		"Health: %d%%%s   In hand (Q): %s%s   (right mouse aim, left mouse attack)" % [roundi(npc.health * 100), "  BLEEDING (bandage: I)" if npc.bleeding else "", String(state.weapon), "  %d rounds" % state.ammo if state.weapon == &"pistol" else ""],
		"Food %s   Water %s   Rest %s%s   (E: actions, I: bag, Z: sleep, F: car)" % [_need(npc.hunger), _need(npc.thirst), _need(npc.fatigue), "   ASLEEP..." if state.sleeping else ""],
		"Stash: %s" % _format_inventory(state.inventory),
		_turf_line(npc),
		"Standing: %s" % _format_standing(state),
		"Businesses: %d   Grow houses: %d" % [BusinessSystem.count_owned(_world), ProductionSystem.count_grow_houses(_world)],
		"Crew (Tab): %d/%d (lookout %d, dealing %d, muscle %d%s)" % [state.crew_ids.size(), CrewSystem.MAX_CREW, CrewSystem.count_lookouts(_world, state), CrewSystem.count_role(_world, state, GanstoidEnums.CrewRole.DEALER), CrewSystem.count_role(_world, state, GanstoidEnums.CrewRole.MUSCLE), ", driver" if CrewSystem.count_role(_world, state, GanstoidEnums.CrewRole.DRIVER) > 0 else ""],
	])
	text += "\n%s   %d fps (%.0f ms)   people outdoors %d" % [_clock(), Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), _outdoors()]
	if not state.pending_deal.is_empty():
		text += "\nDealing... %ds" % ceili(state.pending_deal["ticks_left"] / 60.0)
	if state.message_serial != _seen_serial:
		_seen_serial = state.message_serial
		_message_time_left = MESSAGE_SECONDS
	if _message_time_left > 0.0:
		_message_time_left -= delta
		text += "\n\n\"%s\"" % state.last_message

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
