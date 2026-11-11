## G2: what you carry (I). Read-only view; PlayerInputSystem uses the items.
class_name InventoryPanel
extends Label

var _world: World

func setup(world: World) -> void:
	_world = world
	position = Vector2(12, 230)
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)

func _process(_delta: float) -> void:
	var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE) if player != null else null
	visible = state != null and state.inventory_open and state.store_id == &""
	if visible:
		text = format(state)

static func format(state: PlayerStateData) -> String:
	var lines: PackedStringArray = ["-- CARRYING --"]
	var items := PlayerInputSystem.carried(state)
	if items.is_empty():
		lines.append("Nothing. Shops sell food and water (E at the door).")
	for i in items.size():
		var it := ItemCatalog.item(items[i])
		var how: String = {"food": "eat", "drink": "drink", "medical": "apply"}.get(it["kind"], "Q to hold")
		lines.append("%d. %s x%d   (%s)" % [i + 1, it["name"], state.inventory[items[i]], how])
	if state.ammo > 0:
		lines.append("   9 mm rounds: %d" % state.ammo)
	lines.append("")
	lines.append("Skills: " + Skills.summary(state))
	lines.append("1-9: use   I or Esc: close")
	return "\n".join(lines)
