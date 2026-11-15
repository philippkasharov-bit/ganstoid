## QA2 on screen (needs a display: xvfb-run -a): presses F12 in the real game,
## checks the window opens and the game pauses, types a note, saves, and checks
## the zip arrived and the game runs again. Also saves a picture of the window.
## Run: xvfb-run -a godot --rendering-driver opengl3 --path . -s debug/shot_bug_report.gd -- --out=<png>
extends SceneTree

func _initialize() -> void:
	Engine.set_meta("skip_new_game", true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run(main)

func _run(main: Node) -> void:
	var out := "/tmp/bug_report.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var driver: Node = main.get_node("WorldDriver")
	while SimNav.active == null or not SimNav.active.is_ready():
		await process_frame
	for i in 10:
		await process_frame
	var before := _zips()
	await _press(KEY_F12)
	var win: BugReportWindow = null
	for n in main.get_node("HudLayer").get_children():
		if n is BugReportWindow:
			win = n
	if not _check(win != null and win.visible and driver.paused, "F12 opens the window and pauses the game"):
		return
	win.open_folder = false
	win._note.text = "test: the palm tree is floating"
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	win._save()
	await process_frame
	var after := _zips()
	if not _check(after.size() == before.size() + 1, "Save writes one zip (%d -> %d)" % [before.size(), after.size()]):
		return
	if not _check(not win.visible and not driver.paused, "the window closes and the game runs again"):
		return
	var newest := ""
	for f in after:
		if not before.has(f):
			newest = f
	var zip := ZIPReader.new()
	zip.open(ProjectSettings.globalize_path(BugReportWindow.DIR + newest))
	var pic := Image.new()
	pic.load_png_from_buffer(zip.read_file("screenshot.png"))
	var note := zip.read_file("note.txt").get_string_from_utf8()
	zip.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BugReportWindow.DIR + newest))
	if not _check(pic.get_width() > 300 and note.contains("palm tree is floating") and note.contains("renderer:"),
			"the zip has the real screen picture (%s) and the note" % pic.get_size()):
		return
	print("BUG_REPORT_UI_VERIFY: PASS")
	quit()

func _press(key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.keycode = key
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame
		await process_frame

func _zips() -> PackedStringArray:
	var found := PackedStringArray()
	for f in DirAccess.get_files_at(BugReportWindow.DIR):
		if f.ends_with(".zip"):
			found.append(f)
	return found

func _check(ok: bool, what: String) -> bool:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		print("BUG_REPORT_UI_VERIFY: FAIL - " + what)
		quit(1)
	return ok
