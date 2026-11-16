## QA2: the bug button. F12 takes a picture of the screen at that moment,
## pauses the game and asks "what went wrong?". Save packs one zip into the
## game's bugs folder (user://bugs/) and opens that folder: the picture, the
## save (the exact moment, loadable), the log of this run and a note with the
## time, place and settings. Phil sends that one zip; nothing is uploaded.
class_name BugReportWindow
extends UiWindow

const ACTION := &"bug_report"
const DIR := "user://bugs/"
const LOG_PATH := "user://logs/godot.log"
const LOG_TAIL_BYTES := 2_000_000   # the end of a long run's log is the part that matters

var _world: World
var _driver: Node
var _shot: Image
var _note := TextEdit.new()
var _status: Label
var _was_paused := false
var open_folder := true   # the screen test turns this off: a server has no file manager

func setup(world: World, driver: Node, at: Vector2) -> void:
	setup_window("bug_report", "Report a bug", at, Vector2(460, 0))
	_world = world
	_driver = driver
	body.add_child(UiTheme.label("What went wrong? What did you expect instead?", UiTheme.FONT_BODY))
	_note.custom_minimum_size = Vector2(440, 110)
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.placeholder_text = "e.g. the car drove through a wall on the corner by the shop"
	body.add_child(_note)
	_status = UiTheme.label("The picture was taken when you pressed F12.", UiTheme.FONT_SMALL, UiTheme.DIM)
	body.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE)
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close_window)
	row.add_child(cancel)
	var save := Button.new()
	save.text = "Save bug report"
	save.pressed.connect(_save)
	row.add_child(save)
	body.add_child(row)
	closed.connect(_on_closed)
	CharacterWindow._bind(ACTION, KEY_F12)
	visible = false

func _process(_delta: float) -> void:
	if not visible and Input.is_action_just_pressed(ACTION):
		_open()
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close_window()

func _open() -> void:
	_shot = get_viewport().get_texture().get_image()   # before the window is on it
	_was_paused = _driver.paused
	_driver.paused = true
	_note.text = ""
	visible = true
	_note.grab_focus()

func _on_closed() -> void:
	_driver.paused = _was_paused
	_note.release_focus()

func _save() -> void:
	var path := save_report(_world, int(_driver.seed_used), _note.text, _shot, {
		"speed": "%dx" % int(_driver.speed),
		"fps": "%d" % Engine.get_frames_per_second(),
		"window": "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"gpu": RenderingServer.get_video_adapter_name(),
	})
	if path == "":
		_status.text = "Could not save the report (see the log)."
		return
	if open_folder:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))
	close_window()

## Writes one bug zip and returns its user:// path ("" on failure). Static and
## screen-free so verify_bug_report can call it headless with a made-up picture.
static func save_report(world: World, seed: int, note: String, shot: Image, extra: Dictionary = {}) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := DIR + "bug_%s.zip" % stamp
	var zip := ZIPPacker.new()
	if zip.open(ProjectSettings.globalize_path(path)) != OK:
		push_error("BugReport: cannot write %s" % path)
		return ""
	_add(zip, "note.txt", describe(world, seed, note, extra).to_utf8_buffer())
	if shot != null and not shot.is_empty():
		_add(zip, "screenshot.png", shot.save_png_to_buffer())
	_add(zip, "save.txt", var_to_str(SaveGame.snapshot(world, seed)).to_utf8_buffer())
	_add(zip, "log.txt", _log_tail())
	zip.close()
	return path

## The note: Phil's words first, then where and when it happened.
static func describe(world: World, seed: int, note: String, extra: Dictionary = {}) -> String:
	var lines := PackedStringArray(["WHAT WENT WRONG", note.strip_edges() if note.strip_edges() != "" else "(no words given)", "", "WHERE AND WHEN"])
	var hour := SimClock.day_fraction(world.tick) * 24.0
	lines.append("game time: day %d, %02d:%02d (%s), tick %d" % [SimClock.day_number(world.tick), int(hour), int(fmod(hour, 1.0) * 60.0), SimClock.year_month(world.tick), world.tick])
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null:
		var npc: NPCData = player.get_component(ComponentNames.NPC)
		lines.append("player at: %.1f, %.1f   health %.2f   cash $%d" % [npc.position.x, npc.position.y, npc.health, int(npc.cash)])
	lines.append("seed: %d   entities: %d" % [seed, world.entities.size()])
	var version := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	lines.append("game version: %s" % (version if version != "" else "(not installed by the updater)"))
	lines.append("reported: %s   os: %s" % [Time.get_datetime_string_from_system(), OS.get_name()])
	for key in extra:
		lines.append("%s: %s" % [key, extra[key]])
	return "\n".join(lines) + "\n"

static func _log_tail() -> PackedByteArray:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return "(no log file: file logging is off or this is a headless run)\n".to_utf8_buffer()
	var length := file.get_length()
	file.seek(maxi(0, length - LOG_TAIL_BYTES))
	return file.get_buffer(mini(length, LOG_TAIL_BYTES))

static func _add(zip: ZIPPacker, name: String, data: PackedByteArray) -> void:
	zip.start_file(name)
	zip.write_file(data)
	zip.close_file()
