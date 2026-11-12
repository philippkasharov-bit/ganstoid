## UI6: Zomboid-style moodles: a column of square icons down the right edge,
## one per problem, coloured by how bad it is (1 mild .. 4 critical). Hover
## for what it means. Read-only: derives everything from the player's state.
class_name Moodles
extends VBoxContainer

const SIZE := 44.0
const LEVEL_COLOURS := [Color("8a7a3a"), Color("a3632b"), Color("a83a2c"), Color("7d1420")]
const REFRESH_S := 0.25
const NEED_EDGES := [0.5, 0.7, 0.85, 0.95]
const HURT_EDGES := [0.15, 0.35, 0.6, 0.8]   # wounds matter sooner than an empty stomach

var _world: World
var _left := 0.0
var _key := ""

func setup(world: World) -> void:
	_world = world
	add_theme_constant_override("separation", 6)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	position = Vector2(get_viewport_rect().size.x - SIZE - 14, 70)

## [glyph, name, level 1-4, what it means] for every moodle showing now.
static func list(world: World, npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	_need(out, "H", "Hungry", 1.0 - npc.hunger, "Eat something. Starving hurts.")
	_need(out, "W", "Thirsty", 1.0 - npc.thirst, "Drink. Stores sell water.")
	_need(out, "Z", "Tired", 1.0 - npc.fatigue, "Sleep (Z) somewhere safe.")
	_need(out, "+", "Hurt", 1.0 - npc.health, "Bandages heal. Lie low.", HURT_EDGES)
	_need(out, "S", "Stressed", npc.stress, "Stress spoils aim and talk.")
	if npc.bleeding:
		out.append(["B", "Bleeding", 4, "Apply a bandage now."])
	if state.law_tier > 0:
		out.append(["!", "Wanted", clampi(state.law_tier, 1, 4), "Police want you. Get out of sight."])
	if state.case_evidence >= CaseSystem.WARRANT_AT:
		out.append(["C", "Warrant", 3, "There is a warrant out. Cops will arrest on sight."])
	if InventoryWindow.carried_kg(state) > ItemCatalog.CARRY_KG:
		out.append(["K", "Heavy load", 1, "You carry more than %.0f kg." % ItemCatalog.CARRY_KG])
	return out

## Needs read as 0 fine .. 1 empty; Zomboid shows them from about half way.
static func _need(out: Array, glyph: String, name: String, lack: float, why: String, edges: Array = NEED_EDGES) -> void:
	var lvl := 0
	for edge in edges:
		if lack >= edge:
			lvl += 1
	if lvl > 0:
		out.append([glyph, name, lvl, why])

func _process(delta: float) -> void:
	_left -= delta
	if _world == null or _left > 0.0:
		return
	_left = REFRESH_S
	position.x = get_viewport_rect().size.x - SIZE - 14
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null or GameRules.of(_world) == null:
		visible = false
		return
	visible = true
	var shown := list(_world, p.get_component(ComponentNames.NPC), p.get_component(ComponentNames.PLAYER_STATE))
	var key := str(shown)
	if key != _key:
		_key = key
		_rebuild(shown)

func _rebuild(shown: Array) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for m in shown:
		add_child(_icon(m))

func _icon(m: Array) -> PanelContainer:
	var box := PanelContainer.new()
	var style := UiTheme.box(LEVEL_COLOURS[m[2] - 1], Color(0, 0, 0, 0.7), 2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(0)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(SIZE, SIZE)
	box.tooltip_text = "%s (%s)\n%s" % [m[1], ["mild", "moderate", "severe", "critical"][m[2] - 1], m[3]]
	var glyph := UiTheme.label(m[0], 22, Color(1, 1, 1, 0.92))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_color_override("font_outline_color", Color.BLACK)
	glyph.add_theme_constant_override("outline_size", 4)
	box.add_child(glyph)
	return box
