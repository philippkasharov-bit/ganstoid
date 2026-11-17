## PH1/UI7: the phone (P), the hub for everything. UI7 (Phil: "a more
## modern phone, break the 90s a little so it's easy to read"): a dark
## screen that scrolls, a status bar, an app grid of coloured tiles with red
## badges for what needs you (messages, crew asks, a trial, the grow). Home screen
## of apps: Messages (the inbox), Contacts (fixers and dealers you have met:
## call a fixer for work from anywhere), Hustles, Bank, Rivals (who wants
## you and how badly), Paper. It only reads the world; a call or taking a
## job is a request (ui_phone) PhoneSystem carries out.
class_name PhoneWindow
extends UiWindow

const ACTION := &"phone"
const SCREEN := Color("10131a")
const INK := Color("e9edf2")
const SCREEN_H := 470.0
## UI7: each app's tile colour and its two-letter mark.
const TILES := {"Messages": ["4c9be8", "Ms"], "Contacts": ["5aa469", "Co"], "Hustles": ["e0a33a", "Hu"], "Bank": ["3fae8f", "$"],
	"Rivals": ["d0544b", "Rv"], "Score": ["8c62d6", "Sc"], "Crib": ["c98a4b", "Cr"], "Jobs": ["4f86c6", "Jb"], "Property": ["8a9aa8", "Pr"],
	"Gang": ["b2443e", "Gg"], "Crew": ["3f7fd0", "Cw"], "Grow": ["4caf50", "Gr"], "Business": ["2f9c9c", "Bz"], "Connect": ["9c6ad0", "Cn"],
	"Prices": ["d9a440", "Px"], "Loans": ["c0603a", "Ln"], "Empire": ["d4af37", "Em"], "Case": ["7a8592", "Cs"], "Paper": ["b8b0a0", "Pa"]}
const W := 300.0
const APPS := [["Messages", "Messages"], ["Contacts", "Contacts"], ["Hustles", "Hustles"], ["Bank", "Bank"], ["Rivals", "Rivals"], ["Score", "Score"], ["Crib", "Crib"], ["Jobs", "Jobs"], ["Property", "Property"], ["Gang", "Gang"], ["Crew", "Crew"], ["Grow", "Grow"], ["Empire", "Empire"], ["Business", "Business"], ["Connect", "Connect"], ["Prices", "Prices"], ["Loans", "Loans"], ["Case", "Case"], ["Paper", "Paper"]]

var paper: PaperWindow
var _world: World
var _screen := VBoxContainer.new()
var _hiring := ""   # BZ2/BZ3: the one job on the Business page whose candidates are listed
var _app := ""
var _key := ""
var _refresh := 0.0
var _seen_inbox := 0   # UI7: messages read (the badge counts the rest)

func setup(world: World, at: Vector2) -> void:
	setup_window("phone", "Phone", at, Vector2(W + 24, 0))
	_world = world
	var lcd := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = SCREEN
	box.set_corner_radius_all(18)
	box.set_content_margin_all(12)
	box.border_color = Color("2a2f3a")
	box.set_border_width_all(2)
	lcd.add_theme_stylebox_override("panel", box)
	_screen.add_theme_constant_override("separation", 6)
	_screen.custom_minimum_size = Vector2(W, 0)
	var scroll := ScrollContainer.new()   # UI7: long pages scroll instead of running off the screen
	scroll.custom_minimum_size = Vector2(W + 10, SCREEN_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_screen)
	lcd.add_child(scroll)
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
	if _app in ["Bank", "Rivals", "Case", "Crew", "Grow", "Business", "Prices", "Loans", "Empire"]:
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
	_status_bar(hours)
	if _app != "":
		_app_title(_app)
	match _app:
		"":
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 10)
			grid.add_theme_constant_override("v_separation", 12)
			for a in APPS:
				grid.add_child(_tile(a[0], a[1], _badge(state, a[0])))
			_screen.add_child(grid)
		"Messages":
			_seen_inbox = state.inbox.size()
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
		"Gang":   # RP3
			if state.gang_member == &"":
				_text("You're on your own.", 16, true)
				_text("To join a gang: do business with them (deals, gun sales, gang jobs) until they like you, get known on the street, then E by one of theirs on their turf: Ask to join.", 14)
			else:
				_text("%s  ·  %s" % [GangLifeSystem.gang_name(_world, state.gang_member).to_upper(), GangLifeSystem.RANKS[state.gang_rank]], 17, true)
				var nxt := state.gang_rank + 1
				if nxt < GangLifeSystem.RANKS.size():
					_text("gang rep %d / %d to %s" % [state.gang_rep, GangLifeSystem.RANK_AT[nxt], GangLifeSystem.RANKS[nxt]], 15)
					_screen.add_child(_progress(clampf(float(state.gang_rep) / float(GangLifeSystem.RANK_AT[nxt]), 0.0, 1.0)))
				else:
					_text("You run their corners.", 15)
				_rule()
				_text("TODAY", 15, true)
				for m in state.gang_missions:
					_text(GangLifeSystem.mission_text(m), 14)
				_rule()
				_screen.add_child(_button("Leave the gang", func() -> void: state.ui_gang = "leave", Vector2(W, 34)))
		"Jobs":   # RP2
			if not state.gig.is_empty():
				_text(GigSystem.line(_world, state), 16, true)
				_rule()
			_text("TODAY'S GIGS (clean pay)", 15, true)
			if state.gigs.is_empty():
				_text("Nothing left today. New gigs every morning.", 14)
			for i in state.gigs.size():
				var g: Dictionary = state.gigs[i]
				var idx := i
				var tag := "  (car + licence)" if g["kind"] == "taxi" else ""
				_screen.add_child(_button("%s  $%d%s" % [GigSystem.KINDS[g["kind"]][0], int(g["pay"]), tag], func() -> void: state.ui_gig = {"take": idx}, Vector2(W, 34)))
			_rule()
			if state.licence:
				_text("Driving licence: yes", 15)
			else:
				_screen.add_child(_button("Get a driving licence  $%d" % GigSystem.LICENCE_COST, func() -> void: state.ui_gig = {"licence": true}, Vector2(W, 34)))
		"Property":   # RP2
			var me3: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			_text("YOU OWN %d" % state.properties.size(), 16, true)
			for id in state.properties:
				var pid: StringName = id
				var row := HBoxContainer.new()
				var home := me3.home_building_id == pid
				var l := _label("%s%s" % [CornerWarSystem.block_name(TerritoryData.turf_of(_bpos(pid))), "  (home)" if home else "  rent $%d/day" % int(float(state.property_prices.get(pid, 0)) * GigSystem.RENT_SHARE)], 14)
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(l)
				if not home:
					row.add_child(_button("Move in", func() -> void: state.ui_gig = {"move": pid}, Vector2(80, 30)))
				_screen.add_child(row)
			_rule()
			_text("FOR SALE NEAR YOU (clean money only)", 15, true)
			for lst in GigSystem.listings(_world, state, me3):
				var bid: StringName = lst[0]
				_screen.add_child(_button("%s  $%d  (%d m)" % [CornerWarSystem.block_name(TerritoryData.turf_of(_bpos(bid))), int(lst[1]), int(lst[2])], func() -> void: state.ui_gig = {"buy": bid}, Vector2(W, 34)))
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
		"Loans":   # BZ5: who wants money, who owes you
			var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			_text("WANT TO BORROW", 13, true)
			if state.loan_asks.is_empty():
				_text("Nobody today. People near you ask in the morning.", 13)
			for i in state.loan_asks.size():
				var a: Dictionary = state.loan_asks[i]
				var idx := i
				_screen.add_child(_button("%s · $%d at %d%% · %s" % [_who(a["who"]), int(a["amount"]), roundi(float(a["rate"]) * 100.0), "pays on time" if LoanSystem.reliability(a["who"]) >= 0.66 else ("usually pays" if LoanSystem.reliability(a["who"]) >= 0.33 else "a risk")], func() -> void: state.ui_loan = {"ask": idx}, Vector2(W, 30)))
			_rule()
			_text("THE BOOK", 13, true)
			if state.loans.is_empty():
				_text("Nobody owes you.", 13)
			for l in state.loans:
				var e: Entity = _world.entities.get(l["who"])
				var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
				var where := NextStep.where(me.position, n.position) if n != null and int(l["owed"]) > 0 else ""
				_text("%s · owes $%d of $%d · %s%s" % [_who(l["who"]), int(l["owed"]), int(l["total"]), l["status"], "  ·  " + where if where != "" else ""], 13, String(l["status"]) == "late")
			_text("Late? Find them and press E.", 12)
		"Prices":   # QL3: your asking price, what it's worth, how fast it'll move
			var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			_text("Your corners and door staff sell at your price: ask more, fewer bite.", 13)
			_rule()
			var any := false
			for good in [&"weed", &"pills", &"meth", &"coke", &"heroin"]:
				if int(state.inventory.get(good, 0)) <= 0 and not state.prices.has(good):
					continue
				any = true
				var worth := roundi(DrugLabSystem.value_each(_world, state, good, me.position, false))
				var ask := int(state.prices.get(good, 0))
				var now := ask if ask > 0 else worth
				_text("%s %s · worth $%d · ask $%d · %d%% bite" % [String(good), Grades.drug(good, DrugLabSystem.stars(state, good)), worth, now, roundi(DrugLabSystem.accept(now, worth) * 100.0)], 13, ask > 0)
				var row := HBoxContainer.new()
				for d in [-5, -1, 1, 5]:
					var to := maxi(1, now + d)
					var gd: StringName = good
					row.add_child(_button(("%+d" % d), func() -> void: state.ui_lab = {"price": gd, "set": to}, Vector2(46, 24)))
				var gd2: StringName = good
				row.add_child(_button("fair", func() -> void: state.ui_lab = {"price": gd2, "set": 0}, Vector2(52, 24)))
				_screen.add_child(row)
			if not any:
				_text("Nothing to price. Grow, cook, press or import something first.")
		"Connect":   # BZ4: imports, and what you carry
			if state.rank < DrugLabSystem.IMPORT_RANK:
				_text("Nobody big will sell to you until you're a %s." % RankSystem.NAMES[DrugLabSystem.IMPORT_RANK])
			elif not state.shipment.is_empty():
				_text("A %s shipment is on its way: %d units." % [String(state.shipment["good"]), int(state.shipment["units"])], 15, true)
				_text(NextStep.line(_world), 14)
			else:
				_text("A load, cash up front. It waits at a warehouse tomorrow night. Some loads are a setup.", 14)
				for good in DrugLabSystem.IMPORTS:
					var spec: Array = DrugLabSystem.IMPORTS[good]
					var gd: StringName = good
					_screen.add_child(_button("%d %s for $%d" % [int(spec[0]), String(good), int(spec[1])], func() -> void: state.ui_lab = {"order": gd}, Vector2(W, 30)))
			_rule()
			for good in [&"weed", &"pills", &"meth", &"coke", &"heroin"]:
				if int(state.inventory.get(good, 0)) > 0:
					_text("%s  %d  %s" % [String(good), int(state.inventory[good]), Grades.drug_text(good, DrugLabSystem.stars(state, good))], 14)
					var about := Grades.about(state, good)
					if about != "":
						_text("  " + about, 13)
		"Empire":   # BZ7: the whole thing at a glance
			var ins := {"Shops": int(state.biz_day.get("shops", 0)), "Night spots": 0, "Back rooms": 0, "Ring": 0, "Dens": 0, "Loans": int(state.biz_day.get("loans", 0))}
			for id in state.venues:
				ins["Night spots"] += int(state.venues[id].get("last", 0))
				ins["Back rooms"] += int(state.venues[id].get("back", 0))
			for id in state.rings:
				ins["Ring"] += int(state.rings[id].get("last", 0))
			for id in state.dens:
				ins["Dens"] += int(state.dens[id].get("last", 0))
			var total_in := 0
			for k in ins:
				total_in += int(ins[k])
			var crew_pay := 0
			for id in state.crew_wages:
				crew_pay += int(state.crew_wages[id])
			var out := int(state.biz_day.get("wages", 0)) + crew_pay
			_text("Yesterday: in $%d · out $%d · net $%d" % [total_in, out, total_in - out], 16, true)
			for k in ins:
				if int(ins[k]) > 0:
					_text("%s  $%d" % [k, int(ins[k])], 13)
					_screen.add_child(_progress(float(ins[k]) / float(maxi(total_in, 1))))
			_text("Wages: staff $%d · crew $%d a day" % [int(state.biz_day.get("wages", 0)), crew_pay], 13)
			_rule()
			_text("HEAT", 13, true)
			var hunting := []
			for g in state.rivals:
				if float(state.rivals[g].get("grudge", 0.0)) >= RivalSystem.HUNT:
					hunting.append(String(state.rivals[g]["name"]))
			_text("Case file %d · audit risk %s · %s" % [int(state.case_evidence), "low" if FrontSystem.audit_chance(state) < 0.15 else ("medium" if FrontSystem.audit_chance(state) < 0.4 else "HIGH"), "hunting you: " + ", ".join(hunting) if not hunting.is_empty() else "no rival is after your places"], 13, not hunting.is_empty())
			_rule()
			_text("PLACES", 13, true)
			var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			var mine := EmpireSystem.places(_world, state)
			if mine.is_empty():
				_text("Nothing yet. Buy a shop (B at its door) or a flat (Phone > Property).", 13)
			for id in mine:
				var e: Entity = _world.entities.get(id)
				var b: BuildingData = e.get_component(ComponentNames.BUILDING) if e != null else null
				if b == null:
					continue
				var d := EmpireSystem.describe(_world, state, b)
				var guard := EmpireSystem.exposure(_world, state, b)
				_text("%s · %s · %s" % [d[2], NextStep.where(me.position, b.position), "well guarded" if guard <= 0.34 else ("guarded" if guard < 1.0 else "unguarded")], 13, String(d[2]).contains("hit by"))
		"Business":   # BZ2: your places, your staff, who you could hire
			var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
			_text("Yesterday: shops paid $%d · wages $%d" % [int(state.biz_day.get("shops", 0)), int(state.biz_day.get("wages", 0))], 15, true)
			var risk := FrontSystem.audit_chance(state)   # BZ6: the books
			_text("This week: earned $%d · washed $%d · tax %d%% on Sunday · audit risk %s%s" % [int(state.books.get("earned", 0)), int(state.books.get("washed", 0)), roundi(FrontSystem.TAX * 100.0), "low" if risk < 0.15 else ("medium" if risk < 0.4 else "HIGH"), " · washing frozen" if FrontSystem.frozen(_world, state) else ""], 13, risk >= 0.4)
			_rule()
			var places: Array = []   # [label, place id, role, where]
			var home: Entity = _world.entities.get(me.home_building_id)
			if int(state.grow.get("tents", 0)) > 0 and home != null:
				var st: Dictionary = state.grow.get("stash", {})
				places.append(["Grow at home · stash %d bags · stock %d seeds" % [int(st.get("units", 0)), _seeds(state)], &"grow", "grower", home.get_component(ComponentNames.BUILDING).position])
			for b in BusinessSystem.player_owned(_world):
				var v: Dictionary = state.venues.get(b.id, {})
				if v.is_empty():
					var label: String = FrontSystem.KINDS[state.fronts[b.id]][0] if state.fronts.has(b.id) else String(b.trade if b.trade != &"" else &"shop").capitalize()
					var extra := ""
					if int(state.upgrades.get(b.id, 0)) > 0:
						extra += " · upgraded x%d" % int(state.upgrades[b.id])
					var rv := 0 if state.fronts.has(b.id) else FrontSystem.rivals(_world, b)   # a front has no rivals of its old trade
					if rv > 0:
						extra += " · %d rival%s nearby" % [rv, "" if rv == 1 else "s"]
					places.append(["%s · %s%s" % [label, NextStep.where(me.position, b.position), extra], b.id, "manager", b.position])
					continue
				var night := "last night $%d%s%s" % [int(v.get("last", 0)), " + back room $%d" % int(v.get("back", 0)) if int(v.get("back", 0)) > 0 else "", " · a fight" if v.get("fight", false) else ""]
				places.append(["%s (%s) · %s · %s" % [VenueSystem.KINDS[v["kind"]][0], Grades.venue(VenueSystem.stars(state, b.id)), NextStep.where(me.position, b.position), night], b.id, "manager", b.position])
				places.append(["  door", b.id, "bouncer", b.position])
			for id in state.rings:   # BZ5b
				var r: Dictionary = state.rings[id]
				_text("Stolen-goods ring · %s" % ("last night $%d" % int(r.get("last", 0)) if r.get("open", false) else "shut by the police"), 14, true)
			for id in state.dens:
				var d: Dictionary = state.dens[id]
				_text("Gambling den · %s" % ("last night $%d" % int(d.get("last", 0)) if d.get("open", false) else "shut by the police"), 14, true)
				var db: Entity = _world.entities.get(id)
				if db != null and d.get("open", false):
					places.append(["  den door", id, "bouncer", (db.get_component(ComponentNames.BUILDING) as BuildingData).position])
			if places.is_empty():
				_text("Nothing to staff yet. Set up a grow at home, or buy a shop (B by its door).")
			for pl in places:
				_text(pl[0], 15, true)
				var hired := ""
				for id in state.staff:
					if state.staff[id].get("at", &"") == pl[1] and state.staff[id].get("role", "") == pl[2]:
						hired = id
				if hired != "":
					var s: Dictionary = state.staff[hired]
					_text("%s %s · %s · $%d/day" % [StaffSystem.ROLES[s["role"]], _who(hired), Grades.staff(float(s["skill"])), int(s["wage"])], 14)
					var fire_id: StringName = hired
					_screen.add_child(_button("Let go ($%d, quietly)" % (int(s["wage"]) * StaffSystem.FIRE_DAYS), func() -> void: state.ui_biz = {"fire": fire_id}, Vector2(W, 28)))
				elif _hiring != "%s|%s" % [pl[1], pl[2]]:
					var slot := "%s|%s" % [pl[1], pl[2]]
					_screen.add_child(_button("Hire a %s..." % String(pl[2]), func() -> void:
						_hiring = slot
						_key = ""
						_refresh = 0.0, Vector2(W, 28)))
				else:
					_text("hire a %s ($ a day):" % String(pl[2]), 14)
					for c in StaffSystem.candidates(_world, state, pl[3]):
						var t := StaffSystem.traits_of(c)
						var ask := {"hire": c, "at": pl[1], "role": pl[2]}
						_screen.add_child(_button("%s · %s · %s · $%d" % [_who(c), Grades.staff(t.x), StaffSystem.read_honesty(t.y), StaffSystem.wage_of(t.x)], func() -> void: state.ui_biz = ask, Vector2(W, 28)))
				_rule()
		"Grow":   # BZ1: the grow at home and your brand
			var g := state.grow
			if int(g.get("tents", 0)) == 0:
				_text("No grow yet. A hardware counter sells tents, lights, fans, filters and plant food; a dealer has seeds. Set it up at your home door (E).")
			else:
				_text("%d tent%s · %s%s%s" % [int(g["tents"]), "" if int(g["tents"]) == 1 else "s", ["no light", "shop light", "HPS lamp"][int(g.get("lamp", 0))], " · fan" if g.get("fan", false) else "", " · filter" if g.get("filter", false) else " · no filter (smell!)"], 15, true)
				for pl in g.get("plants", []):
					var age := float(_world.tick - int(pl["at"])) / SimClock.day_ticks
					var status := "dead" if pl.get("dead", false) else ("READY" if GrowSystem.ripe(_world, pl) else ("thirsty!" if GrowSystem.thirsty(_world, pl) else "growing %.1f d" % age))
					_text("%s  ·  %s  ·  %s" % [GrowSystem._strain(pl)["name"], status, GrowSystem.stars_text(GrowSystem.quality(state, pl))], 14, status in ["thirsty!", "READY"])
				for d in g.get("drying", []):
					_text("drying: %d bags %s%s" % [int(d["units"]), GrowSystem.STRAINS.get(StringName(d["strain"]), {}).get("name", d["strain"]), "  · dry now" if _world.tick >= int(d["ready"]) else ""], 14)
			_rule()
			var carried: int = state.inventory.get(GrowSystem.GOOD_ID, 0)
			if carried > 0:
				_text("You carry %d bags  %s" % [carried, GrowSystem.stars_text(GrowSystem.stars_carried(state))], 15)
				var about := Grades.about(state, &"weed")
				_text("  " + (about if about != "" else "mixed strains: no name on it"), 13)
			if state.brand != "":
				_text("Your stamp: '%s'  ·  known %d%%" % [state.brand, roundi(state.brand_rep * 100.0)], 15, true)
				var edit := LineEdit.new()
				edit.placeholder_text = "new name for your stamp"
				edit.custom_minimum_size = Vector2(W, 30)
				edit.text_submitted.connect(func(t: String) -> void: state.ui_grow = {"brand": t})
				_screen.add_child(edit)
		"Crew":   # CA1: who they are, what they want
			if state.crew_ids.is_empty():
				_text("No crew yet. Recruit people (E by them) once you can pay them.")
			for a in state.crew_asks:
				_text(CrewAmbitionSystem.ask_text(_world, state, a), 16, true)
				for ch in CrewAmbitionSystem.CHOICES.get(String(a["kind"]), []):
					var pick := {"id": a["id"], "choice": ch[0]}
					_screen.add_child(_button(CrewAmbitionSystem.choice_text(a, ch), func() -> void: state.ui_crew = pick, Vector2(W, 30)))
				_rule()
			for id in state.crew_ids:
				var e: Entity = _world.entities.get(id)
				var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
				if n == null:
					continue
				var nature: String = {&"": "new", &"loyal": "loyal", &"greedy": "greedy", &"climber": "wants more", &"rat": "hard to read"}.get(n.ambition, "?")
				_text("%s%s  ·  %s  ·  loyalty %d%%%s" % [n.display_name, "  (lieutenant)" if n.crew_rank >= 1 else "", nature, roundi(n.loyalty * 100.0), "  ·  $%d/day" % int(state.crew_wages[id]) if state.crew_wages.has(id) else ""], 14)
		"Case":   # CT1: the trial and its witnesses
			var t := state.trial
			if t.is_empty():
				_text("No trial coming. Keep it that way." if state.case_evidence < CaseSystem.PRISON_FROM else "Case file: %d. Get arrested now and you'll stand trial." % int(state.case_evidence))
			else:
				var me: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
				var h := maxf(0.0, float(int(t.get("at", 0)) - _world.tick) / SimClock.hours(1.0))
				_text("TRIAL IN %dh" % ceili(h), 17, true)
				var s := CourtSystem.score(_world, state)
				_text("the case %d  ·  guilty from %d  ·  %s" % [int(s), int(CourtSystem.GUILTY_AT), "you'd go down" if s >= CourtSystem.GUILTY_AT else "you'd walk"], 15)
				_rule()
				for id in t.get("witnesses", []):
					var e: Entity = _world.entities.get(id)
					var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
					var stand := CourtSystem.stand_of(_world, state, id)
					var where := NextStep.where(me.position, n.position) if n != null and stand != "dead" else ""
					_text("%s  ·  %s%s" % [n.display_name if n != null else "?", {"talks": "will talk", "scared": "too scared", "bought": "forgot you", "dead": "dead", "gone": "gone"}[stand], "  ·  " + where if where != "" else ""], 14, stand == "talks")
				_rule()
				_text("Scare them or pay them (E by them), or hire a lawyer (E anywhere, $%d)." % CourtSystem.LAWYER_FEE, 14)
		"Rivals":
			if state.rivals.is_empty():
				_text("Nobody knows your name yet.")
			for g in state.rivals:
				var r: Dictionary = state.rivals[g]
				var bar := "#".repeat(int(float(r["grudge"]) / 10.0)) + "-".repeat(10 - int(float(r["grudge"]) / 10.0))
				_text("%s  (%s)" % [r["name"], _gang(g)], 16, true)
				_screen.add_child(_grudge(float(r["grudge"])))   # UI6: a real bar, the stages marked
				_text("%s  ·  %s%s" % [["calm", "talking", "hunting you", "watching your home", "coming for you"][int(r["stage"])], r["temper"], "  ·  scars %d" % int(r["scars"]) if int(r["scars"]) > 0 else ""], 14)
	reset_size()

## BZ2: someone's name.
func _who(id: StringName) -> String:
	var e: Entity = _world.entities.get(id)
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	return n.display_name if n != null else "?"

## BZ2: seeds left at the grow for the grower.
func _seeds(state: PlayerStateData) -> int:
	var stock: Dictionary = state.grow.get("stock", {})
	return int(stock.get(&"seeds_mids", 0)) + int(stock.get(&"seeds_kush", 0)) + int(stock.get(&"seeds_haze", 0))

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

func _bpos(id: StringName) -> Vector2:
	var e: Entity = _world.entities.get(id)
	return (e.get_component(ComponentNames.BUILDING) as BuildingData).position if e != null else Vector2.ZERO

func _gang(g: StringName) -> String:
	var e: Entity = _world.entities.get(g)
	return e.get_component(ComponentNames.GANG).display_name if e != null else String(g)

## UI7: time on the left, signal and battery on the right.
func _status_bar(hours: float) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = W
	var t := _label("%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60.0)], 12, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	row.add_child(_label("▂▄▆█  ■■■▢", 11))
	_screen.add_child(row)

## UI7: the open app's name with a way back.
func _app_title(app: String) -> void:
	var row := HBoxContainer.new()
	var back := _button("‹", func() -> void: _open(""), Vector2(30, 28))
	row.add_child(back)
	var l := _label(app, 18, true)
	l.add_theme_color_override("font_color", Color(TILES.get(app, ["e9edf2"])[0]).lightened(0.35))
	row.add_child(l)
	_screen.add_child(row)

## UI7: what needs you in an app: a count, "!" or "".
func _badge(state: PlayerStateData, app: String) -> String:
	match app:
		"Messages":
			var n := state.inbox.size() - _seen_inbox
			return str(n) if n > 0 else ""
		"Crew":
			return str(state.crew_asks.size()) if not state.crew_asks.is_empty() else ""
		"Loans":
			var late := state.loans.filter(func(l: Dictionary) -> bool: return String(l["status"]) == "late").size()
			return str(late) if late > 0 else (str(state.loan_asks.size()) if not state.loan_asks.is_empty() else "")
		"Case":
			return "!" if not state.trial.is_empty() else ""
		"Grow":
			return "!" if GrowSystem.need_line(_world, state) != "" else ""
		"Connect":
			return "!" if not state.shipment.is_empty() else ""
		"Jobs":
			return str(state.job_offers.size()) if not state.job_offers.is_empty() else ""
	return ""

## UI7: an app tile: a coloured rounded square with its mark, the name under it, a red badge.
func _tile(name: String, app: String, badge: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var spec: Array = TILES.get(name, ["5a6472", name.left(2)])
	var b := Button.new()
	b.text = spec[1]
	b.custom_minimum_size = Vector2(60, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var face := StyleBoxFlat.new()
	face.bg_color = Color(spec[0])
	face.set_corner_radius_all(16)
	var hover := face.duplicate()
	hover.bg_color = Color(spec[0]).lightened(0.15)
	b.add_theme_stylebox_override("normal", face)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.pressed.connect(func() -> void: _open(app))
	if badge != "":
		var dot := Label.new()
		dot.text = badge
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.add_theme_font_size_override("font_size", 11)
		dot.add_theme_color_override("font_color", Color.WHITE)
		var red := StyleBoxFlat.new()
		red.bg_color = Color("e5483e")
		red.set_corner_radius_all(9)
		red.set_content_margin_all(2)
		dot.add_theme_stylebox_override("normal", red)
		dot.custom_minimum_size = Vector2(18, 18)
		dot.position = Vector2(46, -6)
		b.add_child(dot)
	col.add_child(b)
	var l := Label.new()
	l.text = name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(INK, 0.85))
	l.custom_minimum_size.x = 60
	col.add_child(l)
	return col

func _label(t: String, size: int = 15, bold := false) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.add_theme_font_size_override("font_size", size - 1)
	l.add_theme_color_override("font_color", INK if bold else Color(INK, 0.78))
	return l

func _text(t: String, size: int = 15, bold := false) -> void:
	var l := _label(t, size, bold)
	l.custom_minimum_size.x = W
	_screen.add_child(l)

func _rule() -> void:
	var r := ColorRect.new()
	r.color = Color(INK, 0.12)
	r.custom_minimum_size = Vector2(W, 1)
	_screen.add_child(r)

func _button(t: String, on: Callable, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	var flat := StyleBoxFlat.new()   # UI7: soft cards, not LCD boxes
	flat.bg_color = Color(INK, 0.08)
	flat.set_corner_radius_all(10)
	flat.set_content_margin_all(6)
	var hover := flat.duplicate()
	hover.bg_color = Color(INK, 0.16)
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.pressed.connect(on)
	return b
