## QA2 validator: the F12 bug report is one zip holding Phil's words, where and
## when it happened, the picture, a save that loads back into the same moment,
## and the log.
extends SceneTree

const SEED := 5151

func _initialize() -> void:
	var a := World.new()
	SystemRegistry.register_all(a)
	TestWorlds.real_city(a, SEED)
	a.tick = SimClock.hours(30.5)
	var me: NPCData = a.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	me.cash = 4321
	var shot := Image.create(64, 36, false, Image.FORMAT_RGB8)
	shot.fill(Color(0.8, 0.2, 0.1))
	var path := BugReportWindow.save_report(a, SEED, "the car went through the wall", shot, {"speed": "5x"})
	if not _check(path != "" and FileAccess.file_exists(path), "the zip is written to the bugs folder (%s)" % path):
		return
	var zip := ZIPReader.new()
	zip.open(ProjectSettings.globalize_path(path))
	var files := zip.get_files()
	print("zip %s holds %s" % [path, files])
	if not _check(files.has("note.txt") and files.has("screenshot.png") and files.has("save.txt") and files.has("log.txt"),
			"it holds note, screenshot, save and log"):
		return
	var note := zip.read_file("note.txt").get_string_from_utf8()
	print(note)
	if not _check(note.contains("the car went through the wall") and note.contains("day 2, 06:30") and note.contains("cash $4321")
			and note.contains("seed: %d" % SEED) and note.contains("speed: 5x"), "the note has the words, the time, the player and the seed"):
		return
	var pic := Image.new()
	if not _check(pic.load_png_from_buffer(zip.read_file("screenshot.png")) == OK and pic.get_size() == Vector2i(64, 36),
			"the picture opens"):
		return
	var data: Variant = str_to_var(zip.read_file("save.txt").get_string_from_utf8())
	zip.close()
	if not _check(data is Dictionary and data.get("seed") == SEED, "the save inside reads back"):
		return
	var b := World.new()
	SystemRegistry.register_all(b)
	TestWorlds.real_city(b, SEED)
	SaveGame.apply(b, data)
	var me2: NPCData = b.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if not _check(b.tick == a.tick and me2.cash == 4321 and me2.position == me.position, "loading it gives the same moment"):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var empty := BugReportWindow.describe(a, SEED, "   ")
	if not _check(empty.contains("(no words given)"), "an empty note still makes a report"):
		return
	print("BUG_REPORT_VERIFY: PASS")
	quit()

func _check(ok: bool, what: String) -> bool:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		print("BUG_REPORT_VERIFY: FAIL - " + what)
		quit(1)
	return ok
