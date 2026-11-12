## UI17: the game is now called Tagged. Its saves live in the "Ganstoid" user
## folder (project setting), which is a new place, so on first start this
## copies the save and hall of fame over from Godot's old default folder.
## Never overwrites: a file already in the new folder wins.
class_name UserDirMove
extends RefCounted

const FILES := ["ganstoid_save.txt", "hall_of_fame.txt"]

static func run() -> void:
	var old_dir := OS.get_data_dir().path_join("godot/app_userdata/Ganstoid")
	if OS.get_name() == "Windows" or OS.get_name() == "macOS":
		old_dir = OS.get_data_dir().path_join("Godot/app_userdata/Ganstoid")
	for name in FILES:
		var from: String = old_dir.path_join(name)
		var to: String = "user://" + name
		if FileAccess.file_exists(from) and not FileAccess.file_exists(to):
			var err := DirAccess.copy_absolute(from, ProjectSettings.globalize_path(to))
			if err != OK:
				push_warning("Could not move %s from the old save folder (error %d)" % [name, err])
