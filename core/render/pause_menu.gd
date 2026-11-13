## PM1: Project Zomboid's Esc menu. Esc with nothing else open stops the game
## and shows: Resume, Controls (every key, as keycaps), Save and quit. Esc or
## Resume goes back. Only the pause flag and the save are touched here.
class_name PauseMenu
extends UiPanel

const CONTROLS := [["WASD", "move"], ["Shift", "run"], ["LMB", "attack"], ["RMB hold", "aim"], ["RMB tap", "actions here"],
	["E", "actions / shop"], ["1-9", "hotbar, or pick in a menu"], ["I", "bag"], ["K", "character"], ["H", "health"],
	["Z", "sleep"], ["C", "crouch / sneak"], ["F", "car door"], ["Tab", "crew"], ["U", "turf"], ["Esc", "back / pause"], ["F2", "pause"], ["F3", "1x"], ["F4 F5 F6", "5x 20x 40x"], ["F8", "fps"]]

var _driver: Node
var _showing_controls := false
var _clear_before := true   # nothing was open last frame: this Esc is for us
var _extra := VBoxContainer.new()
var _dim := ColorRect.new()   # the world darkens behind the menu, like Zomboid

func setup_pause(world: World, driver: Node) -> void:
	setup(world, Vector2.ZERO)
	_driver = driver
	_extra.add_theme_constant_override("separation", UiTheme.GAP)
	get_child(0).add_child(_extra)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.top_level = true
	_dim.z_index = -1   # under the menu panel
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # the game behind does not take clicks
	add_child(_dim)

func refresh() -> void:
	var esc := Input.is_action_just_pressed("ui_cancel")
	if visible:
		if esc:
			_resume()
			return
	elif esc and _clear_before and _can_pause():
		_open()
	_clear_before = _nothing_open()
	if not visible:
		return
	show_panel("Paused", [["1", "Resume", ""], ["2", "Hide controls" if _showing_controls else "Controls", ""], ["3", "Save and quit", "saved hourly too"]], [["Esc", "resume"]])
	var screen := get_viewport_rect().size
	position = ((screen - size) * 0.5).round()
	_dim.position = Vector2.ZERO
	_dim.size = screen
	for i in 3:
		if Input.is_action_just_pressed(PlayerInputSystem.SLOT_ACTIONS[i]):
			_on_row(i)

func _on_row(index: int) -> void:
	match index:
		0: _resume()
		1: _toggle_controls()
		2: _save_and_quit()

func _open() -> void:
	visible = true
	_driver.paused = true

func _resume() -> void:
	visible = false
	_showing_controls = false
	_toggle_controls(false)
	_driver.paused = false

func _toggle_controls(show: bool = not _showing_controls) -> void:
	_showing_controls = show
	for c in _extra.get_children():
		c.queue_free()
	if show:
		var k := UiTheme.key_hints(CONTROLS)
		k.custom_minimum_size.x = 300
		_extra.add_child(UiTheme.divider())
		_extra.add_child(k)
	reset_size()

func _save_and_quit() -> void:
	SaveGame.write(_driver.world, _driver.seed_used)
	get_tree().quit()

func _can_pause() -> bool:
	return _driver != null and not _driver.choosing and SimNav.active != null and SimNav.active.is_ready()

## True when no window, menu or counter is up (then Esc means pause).
func _nothing_open() -> bool:
	var st := player_state()
	if st == null or not st.menu_options.is_empty() or st.store_id != &"" or st.inventory_open:
		return false
	for n in get_parent().get_children():
		if n != self and (n is UiWindow or n is UiPanel or n is CrewRoster) and n.visible:
			return false
	return true
