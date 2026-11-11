## Every script in the game compiles (the checks only load what they use; a
## broken HUD or panel would otherwise only show up when Phil presses Play).
extends SceneTree

func _initialize() -> void:
	var bad: PackedStringArray = []
	var n := 0
	for dir in ["res://core", "res://data", "res://scenes"]:
		for path in _scripts(dir):
			n += 1
			var s := load(path) as GDScript
			if s == null or not s.can_instantiate():
				bad.append(path)
	print("scripts compiled: %d, broken: %s" % [n, bad])
	if bad.is_empty():
		print("SCRIPTS_PARSE_VERIFY: PASS")
		quit()
	else:
		print("SCRIPTS_PARSE_VERIFY: FAIL - scripts that do not compile")
		quit(1)

func _scripts(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scripts(dir + "/" + sub))
	return out
