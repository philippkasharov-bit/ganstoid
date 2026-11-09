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

func _process(delta: float) -> void:
	if _world == null:
		return
	var player: Entity = _world.entities.get(&"player")
	if player == null:
		text = ""
		return
	var npc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	text = "\n".join([
		"Cash: $%d clean, $%d dirty" % [npc.cash - state.dirty_cash, state.dirty_cash],
		"Heat: %s" % GanstoidEnums.LawTier.keys()[state.law_tier],
		"Stash: %s" % _format_inventory(state.inventory),
		"Standing: %s" % _format_standing(state),
		"Businesses: %d   Grow houses: %d" % [BusinessSystem.count_owned(_world), ProductionSystem.count_grow_houses(_world)],
		"Crew (Tab): %d/%d (lookout %d, dealing %d, muscle %d%s)" % [state.crew_ids.size(), CrewSystem.MAX_CREW, CrewSystem.count_lookouts(_world, state), CrewSystem.count_role(_world, state, GanstoidEnums.CrewRole.DEALER), CrewSystem.count_role(_world, state, GanstoidEnums.CrewRole.MUSCLE), ", driver" if CrewSystem.count_role(_world, state, GanstoidEnums.CrewRole.DRIVER) > 0 else ""],
	])
	if not state.pending_deal.is_empty():
		text += "\nDealing... %ds" % ceili(state.pending_deal["ticks_left"] / 60.0)
	if state.message_serial != _seen_serial:
		_seen_serial = state.message_serial
		_message_time_left = MESSAGE_SECONDS
	if _message_time_left > 0.0:
		_message_time_left -= delta
		text += "\n\n\"%s\"" % state.last_message

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
