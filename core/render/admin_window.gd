## AD1: the admin panel (F11, once "Admin" is on in the pause menu). Tabs:
##   Player   money, heal, god mode, items, reputation, rank, police, teleport
##   World    time of day, reveal the map, start a push / new hustles / the paper, angry rivals
##   Tests    the bug test (AdminTests): quick checks on the running game
##   Bugs & updates  open and fixed bugs (BUGS.md), what changed (CHANGELOG.md),
##            how many F12 reports wait, and your own notes (saved)
## Buttons only ask (ui_admin); AdminSystem does it.
class_name AdminWindow
extends UiWindow

const ACTION := &"admin"
const NOTES := "user://admin_notes.txt"
const TABS := ["Player", "World", "Tests", "Bugs & updates"]

var _world: World
var _tab := "Player"
var _page := VBoxContainer.new()
var _bar := HBoxContainer.new()

func setup(world: World, at: Vector2) -> void:
	setup_window("admin", "Admin", at, Vector2(520, 0))
	_world = world
	for t in TABS:
		var b := Button.new()
		b.text = t
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _show(t))
		_bar.add_child(b)
	body.add_child(_bar)
	body.add_child(UiTheme.divider())
	_page.add_theme_constant_override("separation", 6)
	body.add_child(_page)
	CharacterWindow._bind(ACTION, KEY_F11)
	visible = false

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION):
		if visible:
			close_window()
		elif UiSettings.admin():
			visible = true
			_show(_tab)
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		close_window()

func _show(tab: String) -> void:
	if tab == "Bugs":
		tab = "Bugs & updates"
	_tab = tab
	for i in _bar.get_child_count():
		(_bar.get_child(i) as Button).add_theme_color_override("font_color", UiTheme.ACCENT if TABS[i] == tab else UiTheme.TEXT)
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	match tab:
		"Player":
			_row([["+$1,000", "cash", 1000], ["+$10,000", "cash", 10000], ["Heal all", "heal", null], ["God mode", "god", null]])
			_row([["Crib up", "crib_up", null], ["Go to jail", "jail", null]])
			_row([["+10 rep", "fame", 10], ["Rank up", "rank_up", null], ["Police forget you", "wanted_clear", null], ["Teleport to waypoint", "teleport", null]])
			_page.add_child(UiTheme.label("Give an item:", UiTheme.FONT_SMALL, UiTheme.DIM))
			var items: Array = []
			for id in AdminSystem.ITEMS:
				items.append([String(id), "item", id])
			_row(items.slice(0, 4))
			_row(items.slice(4))
		"World":
			_row([["06:00", "hour", 6], ["12:00", "hour", 12], ["18:00", "hour", 18], ["23:00", "hour", 23]])
			_row([["Reveal the map", "reveal_map", null], ["Corner push now", "push_now", null], ["New hustles", "hustles_new", null]])
			_row([["Print the paper", "paper_now", null], ["Every rival angry", "rival_max", null]])
			_row([["Score: store", "heist_now", 1], ["Score: stash house", "heist_now", 2], ["Score: armoured van", "heist_now", 3]])
		"Tests":
			var results := AdminTests.run_all(_world)
			var fails := results.filter(func(r: Array) -> bool: return not r[1]).size()
			_page.add_child(UiTheme.label("%d checks, %d failed" % [results.size(), fails], UiTheme.FONT_TITLE, UiTheme.GOOD if fails == 0 else UiTheme.BAD))
			for r in results:
				var l := UiTheme.label("%s  %s   (%s)" % ["PASS" if r[1] else "FAIL", r[0], r[2]], UiTheme.FONT_SMALL, UiTheme.TEXT if r[1] else UiTheme.BAD)
				_page.add_child(l)
			_row([["Run again", "", null]])
			_page.add_child(UiTheme.label("Found something? F12 saves a bug report with a picture and the save.", UiTheme.FONT_SMALL, UiTheme.DIM))
		"Bugs & updates":
			var bugs := bug_lines(_read("res://BUGS.md"))
			_page.add_child(UiTheme.label("OPEN BUGS (%d)" % bugs[0].size(), UiTheme.FONT_TITLE, UiTheme.ACCENT))
			for b in bugs[0].slice(0, 8):
				_page.add_child(_wrap(b))
			_page.add_child(UiTheme.label("RECENTLY FIXED", UiTheme.FONT_TITLE, UiTheme.ACCENT))
			for b in bugs[1].slice(0, 3):
				_page.add_child(_wrap(b))
			_page.add_child(UiTheme.label("LATEST UPDATES", UiTheme.FONT_TITLE, UiTheme.ACCENT))
			for u in Array(_read("res://CHANGELOG.md").split("\n")).filter(func(l: String) -> bool: return l.begins_with("- ")).slice(0, 4):
				_page.add_child(_wrap(u.substr(2)))
			var reports := DirAccess.get_files_at("user://bugs/") if DirAccess.dir_exists_absolute("user://bugs/") else PackedStringArray()
			_page.add_child(UiTheme.label("F12 reports waiting to send: %d  (in your Ganstoid/bugs folder)" % reports.size(), UiTheme.FONT_SMALL, UiTheme.DIM))
			_page.add_child(UiTheme.label("YOUR NOTES (kept between games)", UiTheme.FONT_TITLE, UiTheme.ACCENT))
			var notes := TextEdit.new()
			notes.text = _read(NOTES)
			notes.custom_minimum_size = Vector2(500, 90)
			notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			_page.add_child(notes)
			var save := Button.new()
			save.text = "Save notes"
			save.pressed.connect(func() -> void:
				var f := FileAccess.open(NOTES, FileAccess.WRITE)
				if f != null:
					f.store_string(notes.text)
				save.text = "Saved")
			_page.add_child(save)
	reset_size()

func _row(buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		var cmd: String = b[1]
		var arg: Variant = b[2]
		btn.pressed.connect(func() -> void:
			if cmd == "":
				_show(_tab)
				return
			var st := _state()
			if st != null:
				st.ui_admin = [cmd, arg])
		row.add_child(btn)
	_page.add_child(row)

func _wrap(t: String) -> Label:
	var l := UiTheme.label(t, UiTheme.FONT_SMALL, UiTheme.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 500
	return l

static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

## [open, fixed] one-line summaries from BUGS.md's tables.
static func bug_lines(md: String) -> Array:
	var open: Array = []
	var fixed: Array = []
	var section := ""
	for line in md.split("\n"):
		if line.begins_with("## "):
			section = line.substr(3).to_lower()
		elif line.begins_with("| BUG-"):
			var cells := line.split("|")
			var text := "%s: %s" % [cells[1].strip_edges(), cells[3].strip_edges() if section.begins_with("open") else cells[2].strip_edges()]
			if text.length() > 150:
				text = text.left(147) + "..."
			(open if section.begins_with("open") else fixed).append(text)
	return [open, fixed]
