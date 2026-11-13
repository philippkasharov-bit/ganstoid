## UIF3: E-menu options sort into categories in a fixed order; crimes and
## recruiting carry a note.
extends SceneTree

func _initialize() -> void:
	var noop := func() -> Dictionary: return {}
	var opts := [["Shop here", noop], ["Mug them (knife out)", noop], ["Talk", noop], ["Recruit into your crew", noop],
		["Get in the car", noop], ["Spray your tag", noop], ["Buy this property", noop], ["Bribe the officer ($80)", noop]]
	var g := ActionMenuModel.group(opts)
	var ok: bool = g.keys() == ["Shop & deals", "Talk", "Crime", "Crew", "Property", "Car"]
	ok = ok and g["Crime"].size() == 2 and g["Talk"].size() == 2
	ok = ok and ActionMenuModel.category("Crew: post as lookout") == "Crew" and ActionMenuModel.category("Pull the driver out (carjack)") == "Crime"
	print("ACTION_MENU_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
