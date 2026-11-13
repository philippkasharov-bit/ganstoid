## IT1: Zomboid's item card: the kind, then bars for what matters (damage,
## reach and speed for a weapon; food, water, energy, health for the rest),
## then weight, size and price in one dim line. Used by the bag and hotbar.
class_name ItemCard
extends RefCounted

static func lines(id: StringName) -> Array:
	var it := ItemCatalog.item(id)
	var lines: Array = [[String(it["kind"]).capitalize(), InventoryWindow.KIND_COLOURS.get(it["kind"], UiTheme.TEXT)]]
	if it.has("weapon"):
		var w: Dictionary = CombatSystem.WEAPONS[it["weapon"]]
		lines.append(["bar", "Damage", w["damage"] / 0.6, UiTheme.BAD, str(roundi(w["damage"] * 100))])
		lines.append(["bar", "Reach", minf(1.0, w["range"] / 35.0) if not w["melee"] else w["range"] / 2.0, UiTheme.ACCENT, "%.1f m" % w["range"]])
		lines.append(["bar", "Speed", 0.25 / w["cooldown_s"], UiTheme.GOOD, "%.1f /s" % (1.0 / w["cooldown_s"])])
		if not w["melee"]:
			lines.append(["Loud: heard %d m away" % roundi(w["heard_m"]), UiTheme.DIM])
	for stat in ["hunger", "thirst", "tired", "heal"]:
		if it.has(stat):
			lines.append(["bar", {"hunger": "Food", "thirst": "Water", "tired": "Energy", "heal": "Health"}[stat], it[stat] / 0.5, UiTheme.GOOD, "+%d%%" % roundi(it[stat] * 100)])
	if it.has("rounds"):
		lines.append(["%d rounds" % it["rounds"], UiTheme.TEXT])
	var f := ItemCatalog.size_of(id)
	lines.append(["%.1f kg   ·   %dx%d   ·   $%d" % [it.get("weight", 0.0), f.x, f.y, it["price"]], UiTheme.DIM])
	return lines
