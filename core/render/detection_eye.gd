## UIF4: the detection eye, its own HUD piece at the top of the screen (the
## stealth meter of Hitman / Splinter Cell). An eye and a word: "Unseen" when
## nobody who would call the police can see you, "2 see you" otherwise, and
## "Police see you" when a cop has you in sight. Same rule as the witness
## system: in light range, no wall between. Read-only.
class_name DetectionEye
extends PanelContainer

const REFRESH_S := 0.3
const UNSEEN := Color("8fbf7e")
const SEEN := Color("e8c547")
const COPS := Color("e0533d")

var _world: World
var _icon: Control
var _text := UiTheme.label("", UiTheme.FONT_SMALL)
var _left := 0.0

func setup(world: World) -> void:
	_world = world
	add_theme_stylebox_override("panel", UiTheme.window_box(4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_icon = Moodles.icon_or_glyph("eye", "o", 18.0)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	row.add_child(_text)
	tooltip_text = "Who can see you right now. Only people who see a crime can report it."
	visible = false

func _process(delta: float) -> void:
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = REFRESH_S
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	visible = p != null and GameRules.of(_world) != null and not p.get_component(ComponentNames.NPC).is_down
	if not visible:
		return
	var at: Vector2 = p.get_component(ComponentNames.NPC).position
	var cops := cops_seeing(_world, at)
	var eyes := ActionMenuModel.eyes_on(_world, at)
	var colour := COPS if cops > 0 else (SEEN if eyes > 0 else UNSEEN)
	_text.text = "Police see you" if cops > 0 else ("Unseen" if eyes == 0 else "%d see you" % eyes)
	if p.get_component(ComponentNames.PLAYER_STATE).sneaking:
		_text.text = "Sneaking · " + _text.text   # B3
	_text.add_theme_color_override("font_color", colour)
	_icon.modulate = colour
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, UiTheme.MARGIN)

## Officers with you in sight.
static func cops_seeing(world: World, at: Vector2) -> int:
	var n := 0
	for id in world.spatial_index.query_nearby(at):
		var e: Entity = world.entities.get(id)
		var npc: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if npc != null and npc.is_cop and not npc.is_down and CrimeSystem.can_see(world, npc.position, at):
			n += 1
	return n
