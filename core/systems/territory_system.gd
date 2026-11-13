## Territory (TR1-TR3 + RG1). Influence per turf cell, updated once a game hour:
##   + crew you have working a cell (posted, dealing, muscle)   PLAYER_CREW_PER_HOUR
##   + a business you own in it                                  PLAYER_SHOP_PER_HOUR
##   + a gang's own people living and dealing there              GANG_MEMBER_PER_HOUR
##   + tags (T) and beating a gang's people in their cell        (instant)
##   - everyone fades back toward nothing                        DECAY_PER_HOUR
## Control = at least CONTROL influence and well ahead of the next gang.
## Every morning you collect street tax from each cell you control.
## A gang that sees you growing on its turf sends a crew after you (RG1).
class_name TerritorySystem
extends SystemBase

const ENTITY_ID := &"territory"
const PLAYER := &"player"
const CONTROL := 50.0
const LEAD := 1.5
const DECAY_PER_HOUR := 1.5
const HOME_FLOOR := 40.0                 # a gang never fades below this on its own fronts
const PLAYER_CREW_PER_HOUR := 4.0
const PLAYER_SHOP_PER_HOUR := 2.0
const GANG_MEMBER_PER_HOUR := 0.6
const TAG_GAIN := 8.0
const TAG_HIT_OTHERS := 4.0
const BEATING_GAIN := 6.0
const BEATING_LOSS := 10.0
const TAX_PER_CELL := 25
const TAX_HOUR := 6
const PROVOKE := 25.0                    # your influence on a gang's cell that gets you noticed
const SQUAD_SIZE := 3
const WAR_COOLDOWN_H := 3.0
const MEMBERS_PER_GANG := 10
const SPREAD_PER_HOUR := 1.2            # RG2: a held cell leaks influence into its neighbours
const CLASH_AT := 40.0                   # RG2: two gangs both this strong in one cell fight over it
const CLASH_CHANCE := 0.2
const CLASH_SHIFT := 12.0
const HIT_CHANCE := 0.15                 # RG3: a gang at war with you hits your shop or crew, per hour
const GANG_COLORS := {&"gang_0": Color(0.55, 0.2, 0.75), &"gang_1": Color(0.1, 0.55, 0.85), &"gang_2": Color(0.85, 0.7, 0.1), &"player": Color(0.1, 0.85, 0.3)}

var clashes := 0                         # gang-on-gang fights (checks)
var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

static func data(world: World) -> TerritoryData:
	var e: Entity = world.entities.get(ENTITY_ID)
	return e.get_component(&"TerritoryData") if e != null else null

## New game: the turf map, the gangs' home cells, and ten members a gang
## (people who live nearest its fronts).
static func seed(world: World) -> void:
	var t := TerritoryData.new()
	var e := Entity.new(ENTITY_ID)
	e.add_component(t)
	world.register_entity(e)
	for g in world.get_entities_with_component(ComponentNames.GANG).values():
		var gang: GangData = g.get_component(ComponentNames.GANG)
		for b_id in gang.territory_building_ids:
			var c := TerritoryData.turf_of(world.entities[b_id].get_component(ComponentNames.BUILDING).position)
			set_influence(t, c, gang.id, maxf(70.0, get_influence(t, c, gang.id)))
			for n in TerritoryData.neighbours(c):   # T1: their block, and the blocks round it
				set_influence(t, n, gang.id, maxf(35.0, get_influence(t, n, gang.id)))
		_recruit_members(world, gang)

static func _recruit_members(world: World, gang: GangData) -> void:
	if gang.territory_building_ids.is_empty():
		return
	var base: Vector2 = world.entities[gang.territory_building_ids[0]].get_component(ComponentNames.BUILDING).position
	var pool: Array = []
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if not (n.is_cop or n.is_dealer or n.is_crew or n.gang_id != &"" or e.has_component(ComponentNames.PLAYER_STATE)) and world.entities.has(n.home_building_id):
			pool.append([world.entities[n.home_building_id].get_component(ComponentNames.BUILDING).position.distance_to(base), n])
	pool.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and String(a[1].id) < String(b[1].id)))
	for i in mini(MEMBERS_PER_GANG, pool.size()):
		pool[i][1].gang_id = gang.id
		gang.member_npc_ids.append(pool[i][1].id)

static func get_influence(t: TerritoryData, c: Vector2i, gang: StringName) -> float:
	return t.cells.get(c, {}).get(gang, 0.0)

static func set_influence(t: TerritoryData, c: Vector2i, gang: StringName, v: float) -> void:
	if not t.cells.has(c):
		t.cells[c] = {}
	t.cells[c][gang] = clampf(v, 0.0, 100.0)

static func add_influence(t: TerritoryData, c: Vector2i, gang: StringName, dv: float) -> void:
	set_influence(t, c, gang, get_influence(t, c, gang) + dv)

## Who holds a cell (&"" = nobody).
static func controller(t: TerritoryData, c: Vector2i) -> StringName:
	var best: StringName = &""
	var best_v := 0.0
	var second := 0.0
	for g in t.cells.get(c, {}):
		var v: float = t.cells[c][g]
		if v > best_v:
			second = best_v
			best_v = v
			best = g
		elif v > second:
			second = v
	return best if best_v >= CONTROL and best_v >= second * LEAD else &""

static func cells_held(t: TerritoryData, gang: StringName) -> int:
	var n := 0
	for c in t.cells:
		n += int(controller(t, c) == gang)
	return n

## T: spray your tag here. Raises your hold on the cell, dents everyone else's.
static func tag(world: World, me: NPCData) -> Dictionary:
	var t := data(world)
	var c := TerritoryData.turf_of(me.position)
	for g in t.cells.get(c, {}).keys():
		if g != PLAYER:
			add_influence(t, c, g, -TAG_HIT_OTHERS)
	add_influence(t, c, PLAYER, TAG_GAIN)
	CrimeSystem.broadcast_witnesses(world, me.position, CrimeSystem.SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.GRAFFITI])
	return {"ok": true, "effect": "tagged", "amount": roundi(get_influence(t, c, PLAYER))}

## Beating a gang's people on their own turf costs them their grip there.
func on_assaulted(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.ASSAULTED:
		return
	var victim: Entity = _world.entities.get(payload["victim_id"])
	var npc: NPCData = victim.get_component(ComponentNames.NPC) if victim != null else null
	var t := data(_world)
	if npc == null or npc.gang_id == &"" or t == null:
		return
	var c := TerritoryData.turf_of(npc.position)
	add_influence(t, c, npc.gang_id, -BEATING_LOSS)
	add_influence(t, c, PLAYER, BEATING_GAIN)

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	var t := data(_world)
	if t == null:
		return
	var hour := tick / SimClock.hours(1.0)
	if hour == t.last_hour:
		return
	t.last_hour = hour
	_hourly(t)
	for player in entities.values():
		_tax(t, player, tick)
		_rivals_react(t, player.get_component(ComponentNames.NPC), tick)

func _hourly(t: TerritoryData) -> void:
	var homes := {}
	for g in _world.get_entities_with_component(ComponentNames.GANG).values():
		var gang: GangData = g.get_component(ComponentNames.GANG)
		for b_id in gang.territory_building_ids:
			homes[[TerritoryData.turf_of(_world.entities[b_id].get_component(ComponentNames.BUILDING).position), gang.id]] = true
		for m in gang.member_npc_ids:
			var me: Entity = _world.entities.get(m)
			var n: NPCData = me.get_component(ComponentNames.NPC) if me != null else null
			if n != null and not n.is_down:
				add_influence(t, TerritoryData.turf_of(n.position), gang.id, GANG_MEMBER_PER_HOUR)
	for c in t.cells:
		for g in t.cells[c].keys():
			var floor_v := HOME_FLOOR if homes.has([c, g]) else 0.0
			t.cells[c][g] = maxf(floor_v, t.cells[c][g] - DECAY_PER_HOUR)
	_player_sources(t)
	_spread(t)
	_clashes(t)
	_retaliate(t)

## RG2: gangs grow out from what they hold.
func _spread(t: TerritoryData) -> void:
	var adds: Array = []
	for c in t.cells:
		var g := controller(t, c)
		if g == &"" or g == PLAYER:
			continue
		for n in TerritoryData.neighbours(c):   # T1: into the next blocks over
			adds.append([n, g])
	for a in adds:
		add_influence(t, a[0], a[1], SPREAD_PER_HOUR)

## RG2: where two gangs are both strong they fight; someone gets hurt, the
## stronger crew pushes the other back.
func _clashes(t: TerritoryData) -> void:
	var rng := _world.runtime_rng
	for c in t.cells:
		var strong: Array = []
		for g in t.cells[c]:
			if g != PLAYER and t.cells[c][g] >= CLASH_AT:
				strong.append(g)
		if strong.size() < 2 or rng.randf() > CLASH_CHANCE:
			continue
		var w := _world
		strong.sort_custom(func(a: StringName, b: StringName) -> bool: return t.cells[c][a] * GunTrade.armed_edge(w, a) > t.cells[c][b] * GunTrade.armed_edge(w, b))   # WP1: better armed, stronger
		var winner: StringName = strong[0]
		var loser: StringName = strong[1]
		add_influence(t, c, winner, CLASH_SHIFT * 0.5)
		add_influence(t, c, loser, -CLASH_SHIFT)
		_wound_member(loser)
		clashes += 1

## RG3: a gang at war with you hits back where it hurts: your shop's till, or
## one of your crew working its streets.
func _retaliate(t: TerritoryData) -> void:
	var rng := _world.runtime_rng
	for g in t.war_until:
		if _world.tick >= t.war_until[g] + SimClock.hours(WAR_COOLDOWN_H) or rng.randf() > HIT_CHANCE:
			continue
		var player: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
		if player == null:
			return
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		for crew_id in state.crew_ids:
			var e: Entity = _world.entities.get(crew_id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n != null and not n.is_down and get_influence(t, TerritoryData.turf_of(n.position), g) >= PROVOKE:
				n.health = maxf(0.0, n.health - 0.5)
				n.bleeding = true
				_world.event_bus.emit(GanstoidEvents.WOUNDED, {"id": crew_id})
				StreetTalk.say_key(_world, state, "crew_hit")
				break
		for b in _world.get_entities_with_component(ComponentNames.BUILDING).values():
			var bd: BuildingData = b.get_component(ComponentNames.BUILDING)
			if BusinessSystem.owned_by_player(bd) and bd.cash_on_hand > 0 and get_influence(t, TerritoryData.turf_of(bd.position), g) >= PROVOKE:
				bd.cash_on_hand = 0
				bd.has_been_hit = true
				StreetTalk.say_key(_world, state, "shop_hit")
				break

func _wound_member(gang_id: StringName) -> void:
	var gang_e: Entity = _world.entities.get(gang_id)
	if gang_e == null:
		return
	for m in gang_e.get_component(ComponentNames.GANG).member_npc_ids:
		var e: Entity = _world.entities.get(m)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and not n.is_down:
			n.health = maxf(0.0, n.health - 0.6)
			n.bleeding = true
			_world.event_bus.emit(GanstoidEvents.WOUNDED, {"id": m})
			return

func _player_sources(t: TerritoryData) -> void:
	for player in _world.get_entities_with_component(ComponentNames.PLAYER_STATE).values():
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		for crew_id in state.crew_ids:
			var e: Entity = _world.entities.get(crew_id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n != null and not n.is_down and n.crew_role in [GanstoidEnums.CrewRole.LOOKOUT, GanstoidEnums.CrewRole.DEALER, GanstoidEnums.CrewRole.MUSCLE]:
				add_influence(t, TerritoryData.turf_of(n.position), PLAYER, PLAYER_CREW_PER_HOUR)
	for b in _world.get_entities_with_component(ComponentNames.BUILDING).values():
		var bd: BuildingData = b.get_component(ComponentNames.BUILDING)
		if BusinessSystem.owned_by_player(bd):
			add_influence(t, TerritoryData.turf_of(bd.position), PLAYER, PLAYER_SHOP_PER_HOUR)

## Each morning: street tax from every cell you hold (dirty money).
func _tax(t: TerritoryData, player: Entity, tick: int) -> void:
	var day := tick / SimClock.day_ticks
	if day == t.taxed_day or posmod(tick, SimClock.day_ticks) < SimClock.hours(TAX_HOUR):
		return
	t.taxed_day = day
	var held := cells_held(t, PLAYER)
	if held > 0:
		Wallet.earn_dirty(_world, held * TAX_PER_CELL)
		StreetTalk.say_key(_world, player.get_component(ComponentNames.PLAYER_STATE), "street_tax", held * TAX_PER_CELL)

## RG1: a gang whose cell you are muscling into sends SQUAD_SIZE of its people.
func _rivals_react(t: TerritoryData, me: NPCData, tick: int) -> void:
	var combat := _world.find_system(NPCCombatSystem) as NPCCombatSystem
	if combat == null or me.is_down:
		return
	for c in t.cells:
		if get_influence(t, c, PLAYER) < PROVOKE:
			continue
		for g in t.cells[c]:
			if g == PLAYER or t.cells[c][g] < PROVOKE or tick < t.war_until.get(g, 0):
				continue
			t.war_until[g] = tick + SimClock.hours(WAR_COOLDOWN_H)
			var sent := combat.send_squad(g, SQUAD_SIZE, tick)
			if sent > 0:
				StreetTalk.say_key(_world, _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE), "gang_coming")
