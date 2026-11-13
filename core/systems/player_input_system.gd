## Player movement + the actions wired to real input: walk with the arrow
## keys, approach an NPC, press Enter/Space (ui_accept, Godot's built-in
## action -- no custom input map entry needed) to pickpocket whoever's
## nearest, UNLESS they're a dealer, in which case it buys one unit of
## weed instead. Escape (ui_cancel, also built-in) sells one unit of weed
## back to the nearest dealer. Both built-ins exist already, so no
## project.godot input-map edits are needed for either.
##
## Hardcoded to &"weed" rather than whatever good is nearest/cheapest --
## there's no good-selection UI yet (see DealSystem's doc comment), and
## guessing which good the player wants would be worse than picking the
## one real option explicitly.
##
## Takes World in its constructor for the same reason NPCScheduleSystem
## does -- reindex_position after moving isn't something process_entities'
## entities dict alone can do. Stored as a WeakRef, same cycle-avoidance
## reasoning as NPCScheduleSystem's _world property.
class_name PlayerInputSystem
extends SystemBase

const MOVE_SPEED := SimUnits.WALK
const RUN_SPEED := SimUnits.JOG   # hold Shift

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

## Batch 15: R to recruit. Registered at runtime rather than in
## project.godot so no input-map file edit is needed.
const RECRUIT_ACTION := &"recruit"
## Batch 17: L posts the nearest crew member as a lookout / recalls them.
const POST_ACTION := &"post_lookout"
## Batch 18: G hands the nearest crew member a consignment / collects.
const DEAL_ACTION := &"crew_deal"
## Batch 19: M posts the nearest crew member as muscle / collects.
const MUSCLE_ACTION := &"crew_muscle"
## Batch 20: V makes the nearest crew member your driver / lets them out.
const DRIVER_ACTION := &"crew_driver"
## Batch 23: B buys the nearest business.
const BUY_BUSINESS_ACTION := &"buy_business"
## Combat C3: Zomboid-style mouse aim. Left button attacks toward the cursor,
## right button held raises the weapon, Q changes weapon.
const ATTACK_ACTION := &"attack"
const AIM_ACTION := &"aim"
const SWITCH_WEAPON_ACTION := &"switch_weapon"
const SHIFT_HOURS := 4          # O1: honest work at any open counter
const BOARD_UP_COST := 40   # DW2
const SHIFT_PAY_PER_HOUR := 15
const AIM_SPEED := SimUnits.WALK * 0.6   # weapon up: a careful step, no running
## G1: E opens the counter you stand at (shop, workshop, dealer); 1-9 buy.
const STORE_ACTION := &"store"
const INVENTORY_ACTION := &"inventory"   # G2: I
const SLEEP_ACTION := &"sleep"           # G2: Z
const CAR_ACTION := &"car_door"          # V1: F
const TAG_ACTION := &"tag"               # TR: T
const PRODUCT_ACTION := &"product"       # DR1: C at your safehouse
const SLOT_ACTIONS: Array[StringName] = [&"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5", &"slot_6", &"slot_7", &"slot_8", &"slot_9"]

func _init(world: World) -> void:
	_world_ref = weakref(world)
	if not InputMap.has_action(RECRUIT_ACTION):
		InputMap.add_action(RECRUIT_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_R
		InputMap.action_add_event(RECRUIT_ACTION, key)
	if not InputMap.has_action(POST_ACTION):
		InputMap.add_action(POST_ACTION)
		var post_key := InputEventKey.new()
		post_key.physical_keycode = KEY_L
		InputMap.action_add_event(POST_ACTION, post_key)
	if not InputMap.has_action(DEAL_ACTION):
		InputMap.add_action(DEAL_ACTION)
		var deal_key := InputEventKey.new()
		deal_key.physical_keycode = KEY_G
		InputMap.action_add_event(DEAL_ACTION, deal_key)
	if not InputMap.has_action(MUSCLE_ACTION):
		InputMap.add_action(MUSCLE_ACTION)
		var muscle_key := InputEventKey.new()
		muscle_key.physical_keycode = KEY_M
		InputMap.action_add_event(MUSCLE_ACTION, muscle_key)
	if not InputMap.has_action(DRIVER_ACTION):
		InputMap.add_action(DRIVER_ACTION)
		var driver_key := InputEventKey.new()
		driver_key.physical_keycode = KEY_V
		InputMap.action_add_event(DRIVER_ACTION, driver_key)
	if not InputMap.has_action(BUY_BUSINESS_ACTION):
		InputMap.add_action(BUY_BUSINESS_ACTION)
		var buy_key := InputEventKey.new()
		buy_key.physical_keycode = KEY_B
		InputMap.action_add_event(BUY_BUSINESS_ACTION, buy_key)
	_bind_key(STORE_ACTION, KEY_E)
	_bind_key(INVENTORY_ACTION, KEY_I)
	_bind_key(SLEEP_ACTION, KEY_Z)
	_bind_key(CAR_ACTION, KEY_F)
	_bind_key(TAG_ACTION, KEY_T)
	_bind_key(PRODUCT_ACTION, KEY_C)
	for i in SLOT_ACTIONS.size():
		_bind_key(SLOT_ACTIONS[i], KEY_1 + i)
	_bind_mouse(ATTACK_ACTION, MOUSE_BUTTON_LEFT)
	_bind_mouse(AIM_ACTION, MOUSE_BUTTON_RIGHT)
	if not InputMap.has_action(SWITCH_WEAPON_ACTION):
		InputMap.add_action(SWITCH_WEAPON_ACTION)
		var q_key := InputEventKey.new()
		q_key.physical_keycode = KEY_Q
		InputMap.action_add_event(SWITCH_WEAPON_ACTION, q_key)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

static func _bind_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

static func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)

## required_component = PLAYER_STATE means this dict has exactly one entry,
## by construction (PlayerFactory composes PLAYER_STATE onto exactly one
## entity) -- looping is just the idiomatic way to reach that one entity
## via SystemBase's dict-shaped contract, not a sign more than one is expected.
func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	for entity in entities.values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		var state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
		if not state.pending_deal.is_empty():
			_report(state, DealSystem.advance_handoff(_world, npc, state))
			continue  # rooted mid-handoff (batch 11) -- no movement, no new actions
		if npc.is_down:
			continue   # permadeath: nothing more to do
		if state.prison_until_tick > 0:
			continue   # CP1: inside; the days pass on their own
		if state.work_until_tick > 0:
			if tick >= state.work_until_tick:
				state.work_until_tick = 0
				Wallet.earn_clean(_world, SHIFT_PAY_PER_HOUR * SHIFT_HOURS)
				StreetTalk.say_key(_world, state, "shift_done", int(SHIFT_PAY_PER_HOUR * SHIFT_HOURS * GameRules.money(_world)))
			continue   # O1: at work; the hours pass fast
		if Input.is_action_just_pressed(SLEEP_ACTION):
			StreetTalk.say(_world, state, NeedsSystem.toggle_sleep(_world, npc, state))
		if state.sleeping:
			continue   # asleep: nothing else until you wake
		if Input.is_action_just_pressed(CAR_ACTION):
			StreetTalk.say(_world, state, VehicleSystem.use_door(_world, npc, state))
		var burgled := StreetCrime.advance_burglary(_world, npc, state)
		if not burgled.is_empty():
			StreetTalk.say(_world, state, burgled)
		var wired := VehicleSystem.advance_hotwire(_world, npc, state)
		if not wired.is_empty():
			StreetTalk.say(_world, state, wired)
		var busy := _move_input() != Vector2.ZERO or Input.is_action_just_pressed(ATTACK_ACTION)
		StreetTalk.say(_world, state, TimedAction.advance(_world, npc, state, busy))   # TA1
		if Input.is_action_just_pressed(TAG_ACTION) and state.vehicle_id == &"" and TerritorySystem.data(_world) != null:
			StreetTalk.say(_world, state, TerritorySystem.tag(_world, npc))
		if Input.is_action_just_pressed(PRODUCT_ACTION):
			var lab := _find_own_grow_house(npc.position)
			if lab != &"":
				StreetTalk.say(_world, state, ProductionSystem.switch_product(_world, lab))
		if state.vehicle_id != &"":
			_drive(npc, state, delta)
			continue   # at the wheel: WASD drive the car
		_combat_input(npc, state, tick)
		if _action_menu_input(npc, state) or _store_input(npc, state) or _inventory_input(npc, state):
			continue   # a menu is open: the number keys belong to it
		var input_dir := _move_input()
		if input_dir != Vector2.ZERO:
			var speed := RUN_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else MOVE_SPEED
			if state.aiming:
				speed = AIM_SPEED
			speed *= NeedsSystem.speed_factor(npc) * BodyParts.move_mult(state)   # HP1: hurt legs limp
			var step := input_dir.normalized() * speed * CrewSystem.player_speed_multiplier(_world, state) * delta
			npc.position = SimNav.active.slide(npc.position, step) if SimNav.active != null else npc.position + step   # walls are solid
			_world.reindex_position(npc.id)
		if Input.is_action_just_pressed("ui_accept"):
			_report(state, _attempt_interact(npc))
		if Input.is_action_just_pressed(RECRUIT_ACTION):
			var target_id := _find_nearest_npc(npc.position)
			if target_id != &"":
				StreetTalk.say(_world, state, CrewSystem.recruit(_world, target_id))
		if Input.is_action_just_pressed(POST_ACTION):
			var crew_id := _find_nearest_crew(npc.position, state)
			if crew_id != &"":
				StreetTalk.say(_world, state, CrewSystem.toggle_post(_world, crew_id))
		if Input.is_action_just_pressed(DEAL_ACTION):
			var crew_id := _find_nearest_crew(npc.position, state)
			if crew_id != &"":
				StreetTalk.say(_world, state, CrewDealerSystem.toggle(_world, crew_id))
		if Input.is_action_just_pressed(MUSCLE_ACTION):
			var crew_id := _find_nearest_crew(npc.position, state)
			if crew_id != &"":
				StreetTalk.say(_world, state, CrewMuscleSystem.toggle(_world, crew_id))
		if Input.is_action_just_pressed(DRIVER_ACTION):
			var crew_id := _find_nearest_crew(npc.position, state)
			if crew_id != &"":
				StreetTalk.say(_world, state, CrewSystem.toggle_driver(_world, crew_id))
		if Input.is_action_just_pressed(BUY_BUSINESS_ACTION):
			var building_id := _find_nearest_building(npc.position)
			if building_id != &"":
				StreetTalk.say(_world, state, _buy_building(building_id))

## Combat C3: aim is held, attacks fire toward state.aim_point (written each
## frame by AimView from the mouse), Q swaps weapons.
func _combat_input(npc: NPCData, state: PlayerStateData, tick: int) -> void:
	state.aiming = Input.is_action_pressed(AIM_ACTION)
	if state.inventory_open:
		return   # UI5: mouse clicks belong to the bag window while it is open
	if Input.is_action_just_pressed(SWITCH_WEAPON_ACTION):
		StreetTalk.say_key(_world, state, "weapon_" + String(CombatSystem.cycle_weapon(state)))
	var melee: bool = CombatSystem.WEAPONS[state.weapon]["melee"]
	if Input.is_action_just_pressed(ATTACK_ACTION) or (melee and Input.is_action_pressed(ATTACK_ACTION)):   # pistol: one shot a click
		var result := CombatSystem.attack(_world, npc, state, tick, _world.runtime_rng)
		if result.get("ok", false):
			state.last_attack = result
		elif result.get("reason", "") == "no_ammo" and Input.is_action_just_pressed(ATTACK_ACTION):
			StreetTalk.say(_world, state, result)

## G1: E opens / closes the nearest counter; 1-9 buy that line; Esc or walking
## off closes it. Returns true while a menu is open (other actions wait).
func _store_input(npc: NPCData, state: PlayerStateData) -> bool:
	if state.store_id == &"":
		return false
	if Input.is_action_just_pressed(STORE_ACTION):
		state.store_id = &""
		return true
	if state.store_id == &"":
		return false
	var counter: Entity = _world.entities.get(state.store_id)
	var at: Vector2 = _counter_position(counter)
	if Input.is_action_just_pressed("ui_cancel") or at.distance_to(npc.position) > CrimeSystem.INTERACT_RADIUS * 2.0:
		state.store_id = &""
		return true
	var stock := ItemCatalog.stock(ShopSystem.counter_kind(_world, state.store_id))
	for i in mini(stock.size(), SLOT_ACTIONS.size()):
		if Input.is_action_just_pressed(SLOT_ACTIONS[i]) or _picked(state, i):
			StreetTalk.say(_world, state, ShopSystem.buy(_world, npc, state, state.store_id, stock[i]))
	state.ui_pick = -1
	return true

## UIF1: was row `i` clicked in the open menu?
static func _picked(state: PlayerStateData, i: int) -> bool:
	return state.ui_pick == i

## V1: WASD drive; the player rides along.
func _drive(npc: NPCData, state: PlayerStateData, delta: float) -> void:
	var car: VehicleData = _world.entities[state.vehicle_id].get_component(ComponentNames.VEHICLE)
	var input := _move_input()
	var before := car.position
	var out := VehicleSystem.drive(_world, car, -input.y, input.x, delta, Skills.more(state, &"driving"))
	Skills.train(_world, state, &"driving", before.distance_to(car.position) * 0.01)   # 1 XP per 100 m
	npc.position = car.position
	_world.reindex_position(npc.id)
	if out.has("hit"):
		CombatSystem.report_hit(_world, car.position, out["hit"])
	if out.get("crash", 0.0) > 8.0:
		npc.health = maxf(0.0, npc.health - out["crash"] * 0.02)   # a hard crash shakes you up

## UI1: E opens one menu of everything you can do right here (shop, buy,
## sell, pickpocket, mug, recruit, rob, break in, take the car...); 1-9 picks,
## E or Esc closes. Replaces the old one-key-per-action scheme (Esc to sell).
var _menu_runs: Array[Callable] = []
var _menu_top: Array = []   # UIF3: the whole option list, for stepping back out of a category

func _action_menu_input(npc: NPCData, state: PlayerStateData) -> bool:
	if state.store_id != &"" or state.inventory_open:
		return false
	if Input.is_action_just_pressed(STORE_ACTION):
		if not state.menu_options.is_empty():
			state.menu_options = []
			return true
		_open_menu(npc, state, _options(npc, state))
		if state.menu_options.is_empty():
			StreetTalk.say_key(_world, state, "nothing_here")
		return true
	if state.menu_options.is_empty():
		return false
	if Input.is_action_just_pressed("ui_cancel"):
		if state.menu_title != "What now?" and not _menu_top.is_empty():
			_open_menu(npc, state, _menu_top)   # UIF3: Esc in a category steps back to the categories
		else:
			state.menu_options = []
		return true
	for i in mini(_menu_runs.size(), SLOT_ACTIONS.size()):
		if Input.is_action_just_pressed(SLOT_ACTIONS[i]) or _picked(state, i):
			state.ui_pick = -1
			state.menu_options = []
			var result: Variant = _menu_runs[i].call()
			if result is Dictionary and result.get("submenu", false):
				return true   # UIF3: a category opened its own list
			if result is Dictionary and not result.is_empty():
				_report(state, result)
			if not state.job_offers.is_empty():   # JB1: the fixer's offers become the next menu
				_open_menu(npc, state, _options(npc, state))
			return true
	return true

## UIF3: a short list opens flat; a long one opens on its categories.
func _open_menu(npc: NPCData, state: PlayerStateData, options: Array) -> void:
	_menu_top = options
	if options.size() <= ActionMenuModel.FLAT_UP_TO or not state.job_offers.is_empty():
		_show_list(npc, state, "What now?", options)
		return
	var groups := ActionMenuModel.group(options)
	var rows: Array = []
	for cat in groups:
		var picked: Array = groups[cat]
		rows.append(["%s  ›" % cat, func() -> Dictionary:
			_show_list(npc, state, cat, picked)
			return {"submenu": true}])
	_show_list(npc, state, "What now?", rows, false)

func _show_list(npc: NPCData, state: PlayerStateData, title: String, options: Array, notes := true) -> void:
	_menu_runs.clear()
	var labels: PackedStringArray = []
	var side: PackedStringArray = []
	for option in options.slice(0, SLOT_ACTIONS.size()):
		labels.append(option[0])
		_menu_runs.append(option[1])
		side.append(ActionMenuModel.note(_world, npc.position, option[0], state) if notes else "")
	state.menu_options = labels
	state.menu_notes = side
	state.menu_title = title

## What you can do where you stand, in the order it reads best.
func _options(npc: NPCData, state: PlayerStateData) -> Array:
	var out: Array = []
	var pos := npc.position
	if not state.job_offers.is_empty():   # JB1: choosing a contract
		for job in state.job_offers:
			out.append(["%s  ($%d)" % [job["text"], job["pay"]], func() -> Dictionary:
				state.job_offers = []
				return JobSystem.take(_world, state, job)])
		return out
	if state.case_evidence > 0.0:
		out.append(["Call a lawyer ($%d, case -%d)" % [CaseSystem.LAWYER_FEE, int(CaseSystem.LAWYER_CUT)], func() -> Dictionary: return CaseSystem.lawyer(_world, npc, state)])
	var counter := _find_counter(pos)
	var person := _find_nearest_npc(pos)
	var p: NPCData = _world.entities[person].get_component(ComponentNames.NPC) if person != &"" else null
	if counter != &"":
		out.append(["Shop here", func() -> Dictionary:
			state.store_id = counter
			return {}])
		if ShopSystem.counter_kind(_world, counter) != "dealer" and ShopSystem.is_open(_world, counter):
			out.append(["Work a %d-hour shift ($%d/h, clean)" % [SHIFT_HOURS, SHIFT_PAY_PER_HOUR], func() -> Dictionary:
				state.work_until_tick = _world.tick + SimClock.hours(SHIFT_HOURS)
				return {"ok": true, "effect": "shift_start"}])
	if p != null and p.is_fixer and state.job.is_empty():
		out.append(["Ask for work", func() -> Dictionary:
			state.job_offers = JobSystem.offers(_world, state, npc)
			state.menu_options = []
			return {"ok": true, "effect": "job_offers"}])
	if not state.job.is_empty() and state.job["kind"] == "debt" and p != null and p.id == state.job["target"]:
		out.append(["Collect the debt", func() -> Dictionary: return JobSystem.collect_debt(_world, npc, state)])
	if p != null and p.is_dealer:
		out.append(["Buy a bag of weed", func() -> Dictionary: return _start_buy(person)])
		var good := _best_to_sell(state)
		if state.inventory.get(good, 0) > 0:
			out.append(["Sell %s" % String(good), func() -> Dictionary: return DealSystem.start_handoff(_world, person, good, "sell")])
	if p != null and not p.is_dealer and p.gang_id != &"" and ShopSystem.owned_weapons(state).has(&"pistol"):
		out.append(["Sell them a gun", func() -> Dictionary: return GunTrade.sell(_world, npc, state, p)])
	if p != null and p.is_cop:
		out.append(["Bribe the officer ($%d)" % TalkSystem.bribe_price(state), func() -> Dictionary: return TalkSystem.bribe_cop(_world, npc, state, p)])
	if p != null and not p.is_cop and not p.is_crew:
		out.append(["Talk", func() -> Dictionary: return TalkSystem.small_talk(_world, npc, p)])
		out.append(["Threaten them into silence", func() -> Dictionary: return TalkSystem.threaten(_world, npc, p)])
		out.append(["Pay them to forget you ($%d)" % TalkSystem.PAYOFF, func() -> Dictionary: return TalkSystem.pay_off(_world, npc, p)])
	if p != null and not p.is_dealer and not p.is_cop and not p.is_crew:
		if state.weapon != &"fists":
			out.append(["Mug them (%s out)" % String(state.weapon), func() -> Dictionary:
				state.aiming = true
				return StreetCrime.mug(_world, npc, state, p)])
		out.append(["Pickpocket", func() -> Dictionary: return CrimeSystem.commit_crime(_world, GanstoidEnums.CrimeType.PICKPOCKET, person)])
		out.append(["Recruit into your crew", func() -> Dictionary: return CrewSystem.recruit(_world, person)])
	var crew := _find_nearest_crew(pos, state)
	if crew != &"":
		out.append(["Crew: post as lookout", func() -> Dictionary: return CrewSystem.toggle_post(_world, crew)])
		out.append(["Crew: deal for you", func() -> Dictionary: return CrewDealerSystem.toggle(_world, crew)])
		out.append(["Crew: muscle", func() -> Dictionary: return CrewMuscleSystem.toggle(_world, crew)])
		out.append(["Crew: driver", func() -> Dictionary: return CrewSystem.toggle_driver(_world, crew)])
	var lab := _find_own_grow_house(pos)
	if lab != &"":
		out.append(["Collect the product", func() -> Dictionary: return ProductionSystem.collect(_world, lab)])
		out.append(["Switch what it makes", func() -> Dictionary: return ProductionSystem.switch_product(_world, lab)])
	var turf := _find_nearest_gang_territory_building(pos)
	if turf != &"":
		out.append(["Ask for a gang job", func() -> Dictionary: return CrimeSystem.do_gang_job(_world, turf)])
	var biz := _find_nearest_robbable_building(pos)
	if biz != &"":
		out.append(["Rob the place", func() -> Dictionary: return CrimeSystem.rob_building(_world, biz)])
	var house := _find_nearest_house(pos)
	if house != &"" and house != npc.home_building_id:
		var hb: BuildingData = _world.entities[house].get_component(ComponentNames.BUILDING)
		StreetCrime.fix_up(_world, hb)
		for way in StreetCrime.ways_in(hb):   # DW2: Zomboid's ways in
			var how: String = way[0]
			out.append([way[1], func() -> Dictionary: return StreetCrime.start_burglary(_world, npc, state, house, how)])
	var bld := _find_nearest_building(pos)
	if bld != &"":
		var owned: BuildingData = _world.entities[bld].get_component(ComponentNames.BUILDING)
		if owned.owner_npc_id == PlayerFactory.PLAYER_ENTITY_ID and not owned.windows_boarded:
			out.append(["Board up the windows ($%d)" % BOARD_UP_COST, func() -> Dictionary: return _board_up(npc, owned)])
		elif owned.owner_npc_id != PlayerFactory.PLAYER_ENTITY_ID:
			out.append(["Buy this property", func() -> Dictionary: return _buy_building(bld)])
	var traffic := TrafficSystem.traffic_car_near(_world, pos)
	if traffic != null:
		out.append(["Pull the driver out (carjack)", func() -> Dictionary: return TrafficSystem.carjack(_world, npc, state, traffic)])
	if VehicleSystem.nearest_car(_world, pos) != null:
		out.append(["Get in the car", func() -> Dictionary: return VehicleSystem.use_door(_world, npc, state)])
	if TerritorySystem.data(_world) != null:
		out.append(["Spray your tag", func() -> Dictionary: return TerritorySystem.tag(_world, npc)])
	return out

## G2: I opens what you carry; 1-9 eat, drink or apply that line.
func _inventory_input(npc: NPCData, state: PlayerStateData) -> bool:
	if not state.ui_move.is_empty():   # INV4: drop / stash / take from the vicinity panel
		StreetTalk.say(_world, state, _do_move(npc, state, state.ui_move))
		state.ui_move = {}
	if state.ui_use != &"":   # UI5/UI8: a bag line or a moodle was clicked
		_use_or_hold(npc, state, state.ui_use)
		state.ui_use = &""
	if Input.is_action_just_pressed(INVENTORY_ACTION):
		state.inventory_open = not state.inventory_open
		return true
	if not state.inventory_open:
		return false
	if Input.is_action_just_pressed("ui_cancel"):
		state.inventory_open = false
		return true
	var items := carried(state)
	for i in mini(items.size(), SLOT_ACTIONS.size()):
		if Input.is_action_just_pressed(SLOT_ACTIONS[i]):
			_use_or_hold(npc, state, items[i])
	return true

func _do_move(npc: NPCData, state: PlayerStateData, move: Dictionary) -> Dictionary:
	match move.get("op", ""):
		"drop":
			return Vicinity.drop(npc, state, move["id"], move["n"])
		"stash":
			return Vicinity.stash(_world, npc, state, move["id"], move["n"])
		"take":
			return Vicinity.take(_world, state, move["src"], move["n"])
	return {}

## UI5: a bag line is eaten/drunk/applied, or a weapon is taken in hand.
func _use_or_hold(npc: NPCData, state: PlayerStateData, item_id: StringName) -> void:
	StreetTalk.say(_world, state, TimedAction.start(_world, state, item_id))   # TA1: takes a few seconds

## What you carry, in catalogue order (the inventory menu's lines).
static func carried(state: PlayerStateData) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ItemCatalog.ITEMS:
		if state.inventory.get(id, 0) > 0:
			out.append(id)
	return out

## Nearest dealer or open-for-business counter within reach.
func _find_counter(position: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS
	for id in _world.spatial_index.query_nearby(position):
		if ShopSystem.counter_kind(_world, id) == "":
			continue
		var d := _counter_position(_world.entities[id]).distance_to(position)
		if d <= best_dist:
			best_dist = d
			best_id = id
	return best_id

static func _counter_position(entity: Entity) -> Vector2:
	if entity == null:
		return Vector2.INF
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	return npc.position if npc != null else entity.get_component(ComponentNames.BUILDING).position

## Batch 16: every action result goes through here -- crew take their cut
## of any score, then the street-voice line is posted.
func _report(state: PlayerStateData, result: Dictionary) -> void:
	CrewLoyaltySystem.take_cut(_world, state, result)
	StreetTalk.say(_world, state, result)

## Branches on what/who is nearest: a dealer gets bought from, anyone else
## gets pickpocketed. One interact button rather than a separate "talk to
## dealer" button -- there's exactly one dealer-specific action this phase
## (buy), so a mode switch per-target is simpler than a second input.
##
## Batch 6 (locked): when no NPC is in range at all, the same button robs
## the nearest building with cash on hand instead -- still one interact
## button, now with a building fallback rather than a third input action.
## An NPC in range always wins over a building (same spot can't be both
## "pickpocket someone" and "rob the business" in one press).
##
## Batch 9 (locked): a gang-territory building is checked before the
## robbery fallback and, if found, offers a paid job instead of a robbery
## -- standing on a gang's own turf always means "work a job here," never
## "rob this corner" (robbing gang turf itself stays unbuilt/future scope).
## _find_nearest_robbable_building excludes territory buildings outright so
## the two finders can never disagree about the same building.
func _attempt_interact(player_npc: NPCData) -> Dictionary:
	var grow_id := _find_own_grow_house(player_npc.position)
	if grow_id != &"":
		return ProductionSystem.collect(_world, grow_id)  # batch 25: at your own grow house, Enter picks up
	var state: PlayerStateData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var target_id := _find_nearest_npc(player_npc.position)
	if state.aiming and state.weapon != &"fists":   # X2: weapon up = a mugging, not a lift
		var mark := _find_npc_within(player_npc.position, StreetCrime.MUG_REACH_M)
		if mark != &"":
			return StreetCrime.mug(_world, player_npc, state, _world.entities[mark].get_component(ComponentNames.NPC))
	if target_id != &"":
		if _is_dealer(target_id):
			return _start_buy(target_id)
		return CrimeSystem.commit_crime(_world, GanstoidEnums.CrimeType.PICKPOCKET, target_id)
	var gang_building_id := _find_nearest_gang_territory_building(player_npc.position)
	if gang_building_id != &"":
		return CrimeSystem.do_gang_job(_world, gang_building_id)
	var building_id := _find_nearest_robbable_building(player_npc.position)
	if building_id != &"":
		return CrimeSystem.rob_building(_world, building_id)
	var house_id := _find_nearest_house(player_npc.position)
	if house_id != &"":
		return StreetCrime.start_burglary(_world, player_npc, state, house_id)   # X2
	return {}

## X2: the nearest residence door within reach.
func _find_nearest_house(position: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS
	for id in _world.spatial_index.query_nearby(position):
		var entity: Entity = _world.entities.get(id)
		var b: BuildingData = entity.get_component(ComponentNames.BUILDING) if entity != null else null
		if b != null and b.building_type == GanstoidEnums.BuildingType.RESIDENCE and b.position.distance_to(position) <= best_dist:
			best_dist = b.position.distance_to(position)
			best_id = id
	return best_id

func _find_npc_within(position: Vector2, reach: float) -> StringName:
	var best_id: StringName = &""
	var best_dist := reach
	for id in _world.spatial_index.query_nearby(position):
		var entity: Entity = _world.entities.get(id)
		var npc: NPCData = entity.get_component(ComponentNames.NPC) if entity != null else null
		if npc == null or npc.is_crew or npc.is_down or npc.indoors or id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		if npc.position.distance_to(position) <= best_dist:
			best_dist = npc.position.distance_to(position)
			best_id = id
	return best_id

## Batch 14: refuse a buy up front when the player can't cover the current
## street price, so they hear "you broke" instead of waiting out a 3s
## handoff that DealSystem.buy would refuse at the end anyway.
func _start_buy(dealer_id: StringName) -> Dictionary:
	var player_npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var item: EconomyItemData = _world.economy_items.get(&"weed")
	if item != null and player_npc.cash < item.current_price:
		return {"ok": false, "reason": "cant_afford"}
	return DealSystem.start_handoff(_world, dealer_id, &"weed", "buy")

func _attempt_sell(player_npc: NPCData) -> Dictionary:
	var target_id := _find_nearest_npc(player_npc.position)
	if target_id == &"":
		return {}
	var buyer: NPCData = _world.entities[target_id].get_component(ComponentNames.NPC)
	if not buyer.is_dealer and buyer.gang_id != &"":   # WP1: a gang member buys your gun
		return GunTrade.sell(_world, player_npc, _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE), buyer)
	if not _is_dealer(target_id):
		return {}
	var state: PlayerStateData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	return DealSystem.start_handoff(_world, target_id, _best_to_sell(state), "sell")

## DR1: Esc sells the most valuable drug you carry (weed if none).
func _best_to_sell(state: PlayerStateData) -> StringName:
	var best: StringName = &"weed"
	var best_price := -1
	for good in _world.economy_items:
		var item: EconomyItemData = _world.economy_items[good]
		if state.inventory.get(good, 0) >= DealSystem.TRADE_QUANTITY and item.current_price > best_price:
			best_price = item.current_price
			best = good
	return best

func _is_dealer(npc_id: StringName) -> bool:
	var entity: Entity = _world.entities.get(npc_id)
	if entity == null:
		return false
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	return npc != null and npc.is_dealer

func _find_nearest_npc(position: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS
	for id in _world.spatial_index.query_nearby(position):
		if id == PlayerFactory.PLAYER_ENTITY_ID:
			continue
		var entity: Entity = _world.entities.get(id)
		if entity == null:
			continue
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc == null or npc.is_crew:
			continue  # batch 15: your own crew aren't pickpocket/recruit targets
		var d := npc.position.distance_to(position)
		if d <= best_dist:
			best_dist = d
			best_id = id
	return best_id

## Batch 6 (locked): mirrors _find_nearest_npc's shape, over buildings with
## cash_on_hand > 0 instead of NPCs -- a building with nothing left to take
## (robbed dry, or a residence/safehouse with no revenue line at all) is
## never a valid target, so this never offers a robbery that would fail on
## "nothing_to_take".
func _find_nearest_robbable_building(position: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS
	for id in _world.spatial_index.query_nearby(position):
		var entity: Entity = _world.entities.get(id)
		if entity == null:
			continue
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building == null or building.cash_on_hand <= 0:
			continue
		if CrimeSystem.find_territory_gang(_world, id) != null:
			continue  # gang turf is a job opportunity, not a robbery target -- see _find_nearest_gang_territory_building
		if BusinessSystem.owned_by_player(building):
			continue  # batch 23: you don't rob your own shop
		var d := building.position.distance_to(position)
		if d <= best_dist:
			best_dist = d
			best_id = id
	return best_id

## Batch 9 (locked): same shape as _find_nearest_robbable_building, over
## any building listed as territory for some gang (regardless of
## cash_on_hand -- a job offer isn't about draining the building's own
## till, it's paid from the gang's own GangData.cash pool). Checked before
## the robbery fallback in _attempt_interact so standing on gang turf
## always offers a job, never a robbery.
func _find_nearest_gang_territory_building(position: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS
	for id in _world.spatial_index.query_nearby(position):
		var entity: Entity = _world.entities.get(id)
		if entity == null:
			continue
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building == null:
			continue
		if CrimeSystem.find_territory_gang(_world, id) == null:
			continue
		var d := building.position.distance_to(position)
		if d <= best_dist:
			best_dist = d
			best_id = id
	return best_id

## Batch 17: nearest of the player's own crew within reach (for L).
func _find_nearest_crew(position: Vector2, state: PlayerStateData) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS * 2.0
	for crew_id in state.crew_ids:
		var entity: Entity = _world.entities.get(crew_id)
		if entity == null:
			continue
		var d: float = entity.get_component(ComponentNames.NPC).position.distance_to(position)
		if d <= best_dist:
			best_dist = d
			best_id = crew_id
	return best_id

## Batch 23: nearest building of any kind within reach (for B).
func _find_nearest_building(position: Vector2) -> StringName:
	var best_id: StringName = &""
	var best_dist := CrimeSystem.INTERACT_RADIUS
	for id in _world.spatial_index.query_nearby(position):
		var entity: Entity = _world.entities.get(id)
		if entity == null:
			continue
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building == null:
			continue
		var d := building.position.distance_to(position)
		if d <= best_dist:
			best_dist = d
			best_id = id
	return best_id

## Batch 25: B on a safehouse buys a grow house; on anything else, a shop.
## DW2: boards on your own windows: nobody smashes their way in.
func _board_up(npc: NPCData, building: BuildingData) -> Dictionary:
	if npc.cash < BOARD_UP_COST:
		return {"ok": false, "reason": "cant_afford"}
	npc.cash -= BOARD_UP_COST
	building.windows_boarded = true
	building.windows_broken = 0
	return {"ok": true, "effect": "boarded_up"}

func _buy_building(building_id: StringName) -> Dictionary:
	var building: BuildingData = _world.entities[building_id].get_component(ComponentNames.BUILDING)
	if building.building_type == GanstoidEnums.BuildingType.SAFEHOUSE:
		return ProductionSystem.buy(_world, building_id)
	return BusinessSystem.buy(_world, building_id)

## Batch 25: your own grow house within reach (for Enter).
func _find_own_grow_house(position: Vector2) -> StringName:
	for id in _world.spatial_index.query_nearby(position):
		var entity: Entity = _world.entities.get(id)
		if entity == null:
			continue
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		if building != null and ProductionSystem.is_grow_house(building) and building.position.distance_to(position) <= CrimeSystem.INTERACT_RADIUS:
			return id
	return &""

## WASD or arrow keys (arrows also come through the ui_* actions for gamepads).
static func _move_input() -> Vector2:
	var d := Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up"))
	if Input.is_physical_key_pressed(KEY_D): d.x += 1.0
	if Input.is_physical_key_pressed(KEY_A): d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S): d.y += 1.0
	if Input.is_physical_key_pressed(KEY_W): d.y -= 1.0
	return d.limit_length(1.0) if d.length() > 0.0 else d
