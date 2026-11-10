## Render check: both map palettes (day and night) have a colour for every
## road tier, every casing edge, sidewalks, kerbs and every area/building kind
## the city uses -- a missing key is a script error that stops the map drawing.
extends SceneTree

func _initialize() -> void:
	var city := CityData.load_file()
	var missing: Array[String] = []
	for pal_name in ["DAY", "NIGHT"]:
		var pal: Dictionary = CityRenderer.DAY if pal_name == "DAY" else CityRenderer.NIGHT
		var need: Array = CityRenderer.TIERS_DRAWN() + ["walk", "kerb", "parkway", "well", "ramp_f", "bg", "river", "rail"]
		for tier in CityRenderer.CASING:
			need.append(tier + "_c")
		for key in need:
			if not pal.has(key):
				missing.append("%s.%s" % [pal_name, key])
	for b in city.buildings:
		if not CityRenderer.BUILDING_DAY.has(b["kind"]) or not CityRenderer.BUILDING_NIGHT.has(b["kind"]):
			missing.append("building kind %s" % b["kind"])
			break
	if not missing.is_empty():
		print("RENDER_PALETTE_VERIFY: FAIL - missing colours: ", missing)
		quit(1)
		return
	print("RENDER_PALETTE_VERIFY: PASS")
	quit()
