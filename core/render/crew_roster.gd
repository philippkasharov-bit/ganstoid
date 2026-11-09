## Phase 3 batch 22: crew roster panel, toggled with Tab (Godot's built-in
## ui_focus_next, so no input-map edit). Read-only view, same relationship
## to World as Hud: one line per crew member -- name, job, loyalty, what
## they're holding -- plus a controls reminder. Created by Hud._ready, so
## main.tscn needs no change.
class_name CrewRoster
extends Label

var _world: World

func setup(world: World) -> void:
	_world = world
	position = Vector2(12, 230)
	visible = false
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_focus_next"):
		visible = not visible
	if not visible or _world == null:
		return
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null:
		text = format_roster(_world, player.get_component(ComponentNames.PLAYER_STATE))

const CONTROLS := "Enter: hustle   Esc: sell   R: recruit   L: lookout   G: dealer   M: muscle   V: driver   B: buy business   Tab: close"

static func format_roster(world: World, state: PlayerStateData) -> String:
	var lines: PackedStringArray = ["-- CREW (%d/%d) --" % [state.crew_ids.size(), CrewSystem.MAX_CREW]]
	if state.crew_ids.is_empty():
		lines.append("No crew yet. Stand next to someone and press R.")
	var n := 1
	for crew_id in state.crew_ids:
		var entity: Entity = world.entities.get(crew_id)
		if entity == null:
			continue
		lines.append("%d. %s" % [n, _describe(entity.get_component(ComponentNames.NPC))])
		n += 1
	lines.append("")
	lines.append(CONTROLS)
	return "\n".join(lines)

static func _describe(npc: NPCData) -> String:
	var name := npc.display_name if npc.display_name != "" else String(npc.id)
	var line := "%s - %s - loyalty %d%%" % [name, _job(npc.crew_role), roundi(npc.loyalty * 100.0)]
	var held: PackedStringArray = []
	if npc.crew_stash > 0:
		held.append("%d weed" % npc.crew_stash)
	if npc.crew_earnings > 0:
		held.append("$%d" % npc.crew_earnings)
	if not held.is_empty():
		line += " - holding " + ", ".join(held)
	return line

static func _job(role: GanstoidEnums.CrewRole) -> String:
	match role:
		GanstoidEnums.CrewRole.LOOKOUT: return "on lookout"
		GanstoidEnums.CrewRole.DEALER: return "dealing"
		GanstoidEnums.CrewRole.MUSCLE: return "muscle"
		GanstoidEnums.CrewRole.DRIVER: return "driving"
		_: return "with you"
