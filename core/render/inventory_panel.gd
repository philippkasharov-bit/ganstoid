## G2/UI1: what you carry (I).
class_name InventoryPanel
extends UiPanel

func refresh() -> void:
	var state := player_state()
	if state == null or not state.inventory_open or state.store_id != &"":
		visible = false
		return
	var rows: Array = []
	var items := PlayerInputSystem.carried(state)
	for i in items.size():
		var it := ItemCatalog.item(items[i])
		var how: String = {"food": "eat", "drink": "drink", "medical": "apply"}.get(it["kind"], "Q to hold")
		rows.append([str(i + 1), "%s  x%d" % [it["name"], state.inventory[items[i]]], how])
	for good in state.inventory:
		if not ItemCatalog.ITEMS.has(good) and state.inventory[good] > 0:
			rows.append(["", "%s  x%d" % [String(good).capitalize(), state.inventory[good]], "sell to a dealer"])
	if state.ammo > 0:
		rows.append(["", "9 mm rounds  x%d" % state.ammo, ""])
	if rows.is_empty():
		rows.append(["", "Nothing. Stores sell food and water.", ""])
	rows.append(["", "Skills: " + Skills.summary(state), ""])
	show_panel("Bag", rows, "1-9 use    I / Esc close")
