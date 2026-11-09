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
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

## required_component = PLAYER_STATE means this dict has exactly one entry,
## by construction (PlayerFactory composes PLAYER_STATE onto exactly one
## entity) -- looping is just the idiomatic way to reach that one entity
## via SystemBase's dict-shaped contract, not a sign more than one is expected.
func process_entities(entities: Dictionary, delta: float, _tick: int) -> void:
	for entity in entities.values():
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		var state: PlayerStateData = entity.get_component(ComponentNames.PLAYER_STATE)
		if not state.pending_deal.is_empty():
			_report(state, DealSystem.advance_handoff(_world, npc, state))
			continue  # rooted mid-handoff (batch 11) -- no movement, no new actions
		var input_dir := Vector2(
			Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
			Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
		)
		if input_dir != Vector2.ZERO:
			var step := input_dir.normalized() * MOVE_SPEED * CrewSystem.player_speed_multiplier(_world, state) * delta
			npc.position = SimNav.active.slide(npc.position, step) if SimNav.active != null else npc.position + step   # walls are solid
			_world.reindex_position(npc.id)
		if Input.is_action_just_pressed("ui_accept"):
			_report(state, _attempt_interact(npc))
		if Input.is_action_just_pressed("ui_cancel"):
			_report(state, _attempt_sell(npc))
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
	var target_id := _find_nearest_npc(player_npc.position)
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
	return {}

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
	if target_id == &"" or not _is_dealer(target_id):
		return {}
	return DealSystem.start_handoff(_world, target_id, &"weed", "sell")

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
