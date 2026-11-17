## NB1b: the F11 People tab. Middle-click someone in the street (left click is
## attack), or press "Nearest to me", to see who they are: kind of person,
## character, needs, mood, memory, links, detail tier and what they think of
## you. Read only: NPCInspectorModel never changes the game.
class_name NPCInspectorView
extends VBoxContainer

const PICK_M := 3.0        # how close to the click a person must be
const NEAR_ME_M := 25.0    # "Nearest to me" looks this far
const REFRESH_S := 0.5     # needs and mood are redrawn this often
const LOW := 0.25          # a need or trait under this shows in red (the number shows too)
const COLUMNS := 4

static var pinned := &""   # kept when you switch tabs

var _world: World
var _resize: Callable
var _content := VBoxContainer.new()
var _links: Array = []     # the links scan walks everyone: done once per person
var _links_for := &""
var _wait := 0.0

func _init(world: World, resize: Callable) -> void:
	_world = world
	_resize = resize
	add_theme_constant_override("separation", 6)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.add_child(UiTheme.label("Middle-click a person in the street.", UiTheme.FONT_SMALL, UiTheme.DIM))
	bar.add_child(_button("Nearest to me", _pick_near_me))
	bar.add_child(_button("Clear", func() -> void: _pin(&"")))
	add_child(bar)
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)
	_redraw()

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b

func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not is_visible_in_tree() or not click.pressed or click.button_index != MOUSE_BUTTON_MIDDLE:
		return
	var id := NPCInspectorModel.person_at(_world, ScreenMap.to_map(get_viewport(), click.position), PICK_M)
	if id != &"":
		_pin(id)
		get_viewport().set_input_as_handled()

func _pick_near_me() -> void:
	var me: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	var npc: NPCData = me.get_component(ComponentNames.NPC) if me != null else null
	if npc != null:
		_pin(NPCInspectorModel.person_at(_world, npc.position, NEAR_ME_M))

func _pin(id: StringName) -> void:
	pinned = id
	_redraw()
	_resize.call()

func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0 and pinned != &"" and is_visible_in_tree():
		_redraw()

func _redraw() -> void:
	_wait = REFRESH_S
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var info := NPCInspectorModel.describe(_world, pinned, pinned != _links_for) if pinned != &"" else {}
	if info.is_empty():
		_content.add_child(UiTheme.label("Nobody picked.", UiTheme.FONT_BODY, UiTheme.DIM))
		return
	if info.has("links"):
		_links = info["links"]
		_links_for = pinned
	_content.add_child(UiTheme.label("%s  ·  %s" % [info["name"], info["title"]], UiTheme.FONT_TITLE, UiTheme.ACCENT))
	_content.add_child(UiTheme.label("%s  ·  %s" % [info["tier"], "mind stored" if info["stored"] else "untouched (rolled from their id)"], UiTheme.FONT_SMALL, UiTheme.DIM))
	_content.add_child(UiTheme.label("About you: " + info["about_you"], UiTheme.FONT_SMALL))
	_grid("CHARACTER", info["traits"], false)
	_grid("NEEDS (1 = fine)", info["drives"], true)
	_grid("MOOD", info["mood"], false)
	_lines("MEMORY", info["memories"], "nothing yet")
	var link_lines := _links.map(func(l: Array) -> String: return "%s: %s" % [l[0], l[1]])
	_lines("LINKS", link_lines, "")

func _grid(title: String, values: Array, warn_low: bool) -> void:
	_content.add_child(UiTheme.label(title, UiTheme.FONT_SMALL, UiTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 14)
	for v in values:
		var low: bool = warn_low and float(v[1]) < LOW
		grid.add_child(UiTheme.label("%s %.2f" % [v[0], v[1]], UiTheme.FONT_SMALL, UiTheme.BAD if low else UiTheme.TEXT))
	_content.add_child(grid)

func _lines(title: String, lines: Array, empty: String) -> void:
	_content.add_child(UiTheme.label(title, UiTheme.FONT_SMALL, UiTheme.ACCENT))
	if lines.is_empty():
		_content.add_child(UiTheme.label(empty, UiTheme.FONT_SMALL, UiTheme.DIM))
	for l in lines:
		_content.add_child(UiTheme.label(l, UiTheme.FONT_SMALL))
