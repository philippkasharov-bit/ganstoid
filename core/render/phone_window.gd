## PH1: the phone (P): a 90s brick phone, the hub for everything. Home screen
## of apps: Messages (the inbox), Contacts (fixers and dealers you have met:
## call a fixer for work from anywhere), Hustles, Bank, Rivals (who wants
## you and how badly), Paper. It only reads the world; a call or taking a
## job is a request (ui_phone) PhoneSystem carries out.
class_name PhoneWindow
extends UiWindow

const ACTION := &"phone"
const SCREEN := Color(0.62, 0.74, 0.47)
const INK := Color(0.08, 0.12, 0.06)
const W := 300.0
const APPS := [["Messages", "Messages"], ["Contacts", "Contacts"], ["Hustles", "Hustles"], ["Bank", "Bank"], ["Rivals", "Rivals"], ["Score", "Score"], ["Crib", "Crib"], ["Paper", "Paper"]]

var paper: PaperWindow
var _world: World
var _screen := VBoxContainer.new()
var _app := ""
var _key := ""
var _refresh := 0.0

func setup(world: World, at: Vector2) -> void:
	setup_window("phone", "Phone", at, Vector2(W + 24, 0))
	_world = world
	var lcd := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = SCREEN
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	lcd.add_theme_stylebox_override("panel", box)
	_screen.add_theme_constant_override("separation", 4)
	_screen.custom_minimum_size = Vector2(W, 360)
	lcd.add_child(_screen)
	body.add_child(lcd)
	body.add_child(UiTheme.label("P: phone   Esc: back / close", UiTheme.FONT_SMALL, UiTheme.DIM))
	CharacterWindow._bind(ACTION, KEY_P)
	visible = false

func _state() -> PlayerStateData:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	return p.get_component(ComponentNames.PLAYER_STATE) if p != null else null

func _process(delta: float) -> void:
	var state := _state()
	if state == null:
		return
	if Input.is_action_just_pressed(ACTION):
		if visible:
			close_window()
		else:
			_app = "Offers" if not state.job_offers.is_empty() else ""
			visible = true
			_key = ""
	elif visible and Input.is_action_just_pressed("ui_cancel"):
		if _app != "":
			_app = ""
			_key = ""
		else:
			close_window()
	if not visible:
		return
	if _app == "" and not state.job_offers.is_empty() and state.ui_phone.is_empty():
		_app = "Offers"
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.4
	var key := _app + str(state.inbox.size()) + str(state.job_offers.size()) + str(state.hustles) + str(state.rivals.size()) + str(state.known.size())
	if _app in ["Bank", "Rivals"]:
		key += str(_world.tick / 60)
	if key == _key:
		return
	_key = key
	_show(state)

func _show(state: PlayerStateData) -> void:
	for c in _screen.get_children():
		c.queue_free()
	_screen.modulate.a = 0.0   # UI6: each page slides and fades in
	_screen.position.x = 18.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_screen, "modulate:a", 1.0, 0.18)
	tw.tween_property(_screen, "position:x", 0.0, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var hours := SimClock.day_fraction(_world.tick) * 24.0
	_text("%s     %02d:%02d   ▮▮▮" % ["HOME" if _app == "" else _app.to_upper(), int(hours), int(fmod(hours, 1.0) * 60.0)], 16)
	_rule()
	match _app:
		"":
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			for a in APPS:
				var label: String = a[0]
				if a[0] == "Messages" and not state.inbox.is_empty():
					label += " (%d)" % state.inbox.size()
				grid.add_child(_button(label, func() -> void: _open(a[1]), Vector2(W * 0.5 - 4, 48)))
			_screen.add_child(grid)
		"Messages":
			if state.inbox.is_empty():
				_text("No messages.")
			for i in range(state.inbox.size() - 1, maxi(-1, state.inbox.size() - 9), -1):
				var m: Dictionary = state.inbox[i]
				var h := SimClock.day_fraction(int(m["at"])) * 24.0
				_text("%02d:%02d %s" % [int(h), int(fmod(h, 1.0) * 60.0), m["from"]], 14, true)
				_text(String(m["text"]), 15)
		"Contacts":
			var any := false
			var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			for id in state.known:
				var e: Entity = _world.entities.get(id)
				var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
				if n == null or n.is_down:
					continue
				any = true
				var kind: String = state.known[id]
				var row := HBoxContainer.new()
				var l := _label("%s  %s\n%s" % ["FIXER" if kind == "fixer" else "DEALER", n.display_name, NextStep.where(me.position, n.position)], 15)
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(l)
				if kind == "fixer":
					var who: StringName = id
					row.add_child(_button("Call", func() -> void: state.ui_phone = {"call": who}, Vector2(60, 34)))
				_screen.add_child(row)
			if not any:
				_text("No numbers yet. Meet a fixer or a dealer: their number goes in here.")
		"Offers":
			if state.job_offers.is_empty():
				_app = ""
				_key = ""
				return
			_text("Pick one:")
			for i in state.job_offers.size():
				var job: Dictionary = state.job_offers[i]
				var idx := i
				_screen.add_child(_button("%s  $%d" % [job["text"], job["pay"]], func() -> void: state.ui_phone = {"take": idx}, Vector2(W, 40)))
		"Hustles":
			if state.hustles.is_empty():
				_text("Nothing today. New ones come in at 07:00.")
			for h in state.hustles:
				_text(("[x] " if h["done"] else "[ ] ") + HustleSystem.line(_world, h), 15)
		"Bank":
			var me2: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			_text("CASH      $%d" % me2.cash, 20)
			_text("clean     $%d" % (me2.cash - state.dirty_cash), 16)
			_text("dirty     $%d" % state.dirty_cash, 16)
			_screen.add_child(_split_bar(float(me2.cash - state.dirty_cash), float(state.dirty_cash)))   # UI6
			_rule()
			_text("LAST 7 MORNINGS", 14, true)
			_screen.add_child(_spark(state.cash_history + [me2.cash]))
			_text("Dirty money draws the police when they search you. Clean it through a business you own.", 14)
		"Crib":   # CR1
			_text("YOUR CRIB: %s" % CribSystem.TIERS[state.crib].to_upper(), 17, true)
			for t in range(1, state.crib + 1):
				for perk in CribSystem.perks(t):
					_text("+ " + perk, 14)
			if state.crib + 1 < CribSystem.TIERS.size():
				var n := state.crib + 1
				_rule()
				_text("NEXT: %s  $%d%s" % [CribSystem.TIERS[n], CribSystem.COST[n], "  (needs %s)" % RankSystem.name_of(CribSystem.RANK[n]) if CribSystem.RANK[n] > state.rank else ""], 16, true)
				for perk in CribSystem.perks(n):
					_text("  " + perk, 14)
				_screen.add_child(_button("Upgrade", func() -> void: state.ui_crib = true, Vector2(W, 34)))
			if not state.trophies.is_empty():
				_rule()
				_text("TROPHIES", 15, true)
				for tr in state.trophies.slice(-5):
					_text("%s  $%d  (day %d)" % [tr["what"], tr["take"], int(tr["day"]) + 1], 14)
		"Score":   # HS1: the plan
			var h := state.heist
			if h.is_empty():
				_text("No score on. Word comes every couple of days once you're a Hustler.")
			else:
				var spec: Array = HeistSystem.KINDS[h["kind"]]
				_text("%s %s" % [String(spec[0]).to_upper(), h["where"]], 17, true)
				_text("take   about $%d" % int(h["take"]), 16)
				_text("window %s" % HeistSystem.window_text(h), 16)
				_text("guards %s" % (str(int(h["guards"])) if h["known"] else "? (case it)"), 16)
				_text("trouble %s" % (HeistSystem.COMPLICATIONS[h["complication"]] if h["known"] else "? (case it)"), 15)
				_rule()
				_text("crew: lookout %d (alarm later)  muscle %d (faster, fewer guards)  driver %d (shorter run)" % [HeistSystem._crew(_world, state, GanstoidEnums.CrewRole.LOOKOUT), HeistSystem._crew(_world, state, GanstoidEnums.CrewRole.MUSCLE), HeistSystem._crew(_world, state, GanstoidEnums.CrewRole.DRIVER)], 14)
				_rule()
				_text(HeistSystem.plan_line(_world, state), 16, true)
				_screen.add_child(_progress(clampf(float(h["work"]) / float(spec[2]), 0.0, 1.0) if h["stage"] in ["working", "getaway"] else clampf(float(h["cased"]) / HeistSystem.CASE_S, 0.0, 1.0)))
		"Rivals":
			if state.rivals.is_empty():
				_text("Nobody knows your name yet.")
			for g in state.rivals:
				var r: Dictionary = state.rivals[g]
				var bar := "#".repeat(int(float(r["grudge"]) / 10.0)) + "-".repeat(10 - int(float(r["grudge"]) / 10.0))
				_text("%s  (%s)" % [r["name"], _gang(g)], 16, true)
				_screen.add_child(_grudge(float(r["grudge"])))   # UI6: a real bar, the stages marked
				_text("%s  ·  %s%s" % [["calm", "talking", "hunting you", "watching your home", "coming for you"][int(r["stage"])], r["temper"], "  ·  scars %d" % int(r["scars"]) if int(r["scars"]) > 0 else ""], 14)
	if _app != "":
		_rule()
		_screen.add_child(_button("< Back", func() -> void: _open(""), Vector2(80, 30)))
	reset_size()

## HS1: a plain progress bar (casing, then the work).
func _progress(f: float) -> Control:
	var back := ColorRect.new()
	back.color = Color(INK, 0.15)
	back.custom_minimum_size = Vector2(W, 10)
	var fill := ColorRect.new()
	fill.color = INK
	fill.size = Vector2(W * f, 10)
	back.add_child(fill)
	return back

## UI6: clean (ink) against dirty (red) as one bar.
func _split_bar(clean: float, dirty: float) -> Control:
	var total := maxf(1.0, clean + dirty)
	var back := ColorRect.new()
	back.color = Color(INK, 0.15)
	back.custom_minimum_size = Vector2(W, 10)
	var a := ColorRect.new()
	a.color = INK
	a.size = Vector2(W * clean / total, 10)
	back.add_child(a)
	var b := ColorRect.new()
	b.color = Color(0.55, 0.12, 0.08)
	b.position = Vector2(W * clean / total, 0)
	b.size = Vector2(W * dirty / total, 10)
	back.add_child(b)
	return back

## UI6: grudge 0-100, the four stages ticked off.
func _grudge(v: float) -> Control:
	var back := ColorRect.new()
	back.color = Color(INK, 0.15)
	back.custom_minimum_size = Vector2(W, 9)
	var fill := ColorRect.new()
	fill.color = INK.lerp(Color(0.6, 0.1, 0.05), clampf(v / 100.0, 0.0, 1.0))
	fill.size = Vector2(W * clampf(v / 100.0, 0.0, 1.0), 9)
	back.add_child(fill)
	for s in [RivalSystem.THREAT, RivalSystem.HUNT, RivalSystem.AMBUSH]:
		var tick := ColorRect.new()
		tick.color = SCREEN
		tick.position = Vector2(W * s / 100.0, 0)
		tick.size = Vector2(2, 9)
		back.add_child(tick)
	return back

## UI6: a little line chart of the numbers (cash each morning, now last).
func _spark(values: Array) -> Control:
	var chart := Sparkline.new()
	chart.values = values
	chart.ink = INK
	chart.custom_minimum_size = Vector2(W, 60)
	return chart

func _open(app: String) -> void:
	if app == "Paper":
		var state := _state()
		if paper != null and state != null and not state.paper.is_empty():
			paper.show_paper(state.paper)
		return
	_app = app
	_key = ""

func _gang(g: StringName) -> String:
	var e: Entity = _world.entities.get(g)
	return e.get_component(ComponentNames.GANG).display_name if e != null else String(g)

func _label(t: String, size: int = 15, bold := false) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.add_theme_font_override("font", UiTheme.font("lcd"))
	l.add_theme_font_size_override("font_size", size + 3)
	l.add_theme_color_override("font_color", INK if not bold else Color(0.02, 0.05, 0.02))
	return l

func _text(t: String, size: int = 15, bold := false) -> void:
	var l := _label(t, size, bold)
	l.custom_minimum_size.x = W
	_screen.add_child(l)

func _rule() -> void:
	var r := ColorRect.new()
	r.color = Color(INK, 0.5)
	r.custom_minimum_size = Vector2(W, 1)
	_screen.add_child(r)

func _button(t: String, on: Callable, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiTheme.font("lcd"))
	b.add_theme_font_size_override("font_size", 18)
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(INK, 0.12)
	flat.border_color = Color(INK, 0.6)
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(3)
	var hover := flat.duplicate()
	hover.bg_color = Color(INK, 0.25)
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.pressed.connect(on)
	return b
