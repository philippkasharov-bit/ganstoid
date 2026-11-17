## CW1: the corner war you can see. Blocks already change hands (TerritorySystem:
## spread, clashes, tags, crews); now you hear about it: a message and a stamp
## when you take or lose a block. And once a game day a gang next to your
## blocks makes a push on one: you have PUSH_H game hours (a few real minutes)
## to get there. Be on the block when they come and beat DEFEND_KO of them, or
## still be standing there when the time is up: the corner holds (influence,
## reputation). Not there: they take a big bite out of it.
class_name CornerWarSystem
extends SystemBase

const PHASE := 37
const EVERY := 120                # two real seconds
const PUSH_H := 2.0
const PUSH_CHANCE := 0.5          # per game day, if a gang borders your blocks
const PUSH_HOUR := [10.0, 22.0]   # pushes happen in waking hours
const BLOCK_M := 45.0             # "on the block": this close to its middle
const SQUAD := 3
const DEFEND_KO := 2
const HELD_GAIN := 18.0
const LOST_BITE := 30.0

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _owners: Dictionary = {}      # block -> holder last time we looked (not saved: rebuilt)

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	var t := TerritorySystem.data(_world)
	if t == null:
		return
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		_flips(t, state)
		if state.turf_push.is_empty():
			_maybe_push(t, state, tick)
		else:
			_run_push(t, state, me, tick)

## Blocks that changed hands to or from you since the last look.
func _flips(t: TerritoryData, state: PlayerStateData) -> void:
	var first := _owners.is_empty()
	for c in t.cells:
		var now := TerritorySystem.controller(t, c)
		var was: StringName = _owners.get(c, now)
		_owners[c] = now
		if first or now == was or not Hoods.is_block(c):
			continue
		var name := block_name(c)
		if now == TerritorySystem.PLAYER:
			PhoneSystem.push(_world, state, "Your crew", "%s is ours now." % name)
			StampView.put(state, "BLOCK TAKEN", name, UiTheme.GOOD)
			Rep.add(state, 3.0)
		elif was == TerritorySystem.PLAYER:
			PhoneSystem.push(_world, state, "Your crew", "We lost %s to %s." % [name, _gang(now)])
			StampView.put(state, "BLOCK LOST", name, UiTheme.BAD)

## Once a game day: a gang bordering your blocks moves on one of them.
func _maybe_push(t: TerritoryData, state: PlayerStateData, tick: int) -> void:
	var day := HustleSystem.day_of(tick)
	var hour := SimClock.day_fraction(tick) * 24.0
	if state.push_day == day or hour < PUSH_HOUR[0] or hour > PUSH_HOUR[1]:
		return
	state.push_day = day
	var rng := _world.runtime_rng
	if rng.randf() >= PUSH_CHANCE:
		return
	var options: Array = []
	for c in t.cells:
		if TerritorySystem.controller(t, c) != TerritorySystem.PLAYER or not Hoods.is_block(c):
			continue
		for n in TerritoryData.neighbours(c):
			var g := TerritorySystem.controller(t, n)
			if g != &"" and g != TerritorySystem.PLAYER:
				options.append([c, g])
	if options.is_empty():
		return
	var pick: Array = options[rng.randi() % options.size()]
	state.turf_push = {"cell": pick[0], "gang": pick[1], "until": tick + SimClock.hours(PUSH_H), "sent": false, "ko": 0, "seen_down": []}
	var name := block_name(pick[0])
	PhoneSystem.push(_world, state, "Your crew", "%s are moving on %s! Get there in %d hours or we lose it." % [_gang(pick[1]), name, int(PUSH_H)])
	StampView.put(state, "CORNER UNDER ATTACK", name, UiTheme.BAD)
	if state.waypoint == Vector2.INF:
		state.waypoint = TerritoryData.centre_of(pick[0])   # the GPS takes you there

func _run_push(t: TerritoryData, state: PlayerStateData, me: NPCData, tick: int) -> void:
	var push := state.turf_push
	var c: Vector2i = push["cell"]
	var g: StringName = push["gang"]
	var there: bool = not me.is_down and me.position.distance_to(TerritoryData.centre_of(c)) <= BLOCK_M
	var combat := _world.find_system(NPCCombatSystem) as NPCCombatSystem
	if there and not push["sent"] and combat != null:
		push["sent"] = true
		push["squad"] = _send(combat, g, TerritoryData.centre_of(c), tick)
	if push["sent"]:
		for id in push.get("squad", []):
			var e: Entity = _world.entities.get(id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n != null and n.is_down and not (push["seen_down"] as Array).has(id):
				(push["seen_down"] as Array).append(id)
				push["ko"] = int(push["ko"]) + 1
	var held: bool = int(push["ko"]) >= DEFEND_KO or (tick >= int(push["until"]) and there and push["sent"])
	if held:
		TerritorySystem.add_influence(t, c, TerritorySystem.PLAYER, HELD_GAIN)
		TerritorySystem.add_influence(t, c, g, -HELD_GAIN)
		Rep.add(state, 5.0)
		PhoneSystem.push(_world, state, "Your crew", "%s held. They won't try that again soon." % block_name(c))
		StampView.put(state, "CORNER HELD", block_name(c), UiTheme.GOOD)
		NewsSystem.note_story(state, "corner_held", _gang(g), TerritoryData.centre_of(c))
		_end(state, c)
	elif tick >= int(push["until"]):
		TerritorySystem.add_influence(t, c, g, LOST_BITE)
		TerritorySystem.add_influence(t, c, TerritorySystem.PLAYER, -LOST_BITE)
		PhoneSystem.push(_world, state, "Your crew", "Nobody showed up. %s walked all over %s." % [_gang(g), block_name(c)])
		_end(state, c)

func _end(state: PlayerStateData, c: Vector2i) -> void:
	if state.waypoint != Vector2.INF and state.waypoint.distance_to(TerritoryData.centre_of(c)) < 1.0:
		state.waypoint = Vector2.INF
	state.turf_push = {}

## SQUAD of the gang's people turn up on the block and go for you.
func _send(combat: NPCCombatSystem, g: StringName, at: Vector2, tick: int) -> Array:
	var gang_e: Entity = _world.entities.get(g)
	if gang_e == null:
		return []
	var out: Array = []
	var until := tick + int(NPCCombatSystem.HOSTILE_S * SimClock.TICKS_PER_SECOND)
	for m in gang_e.get_component(ComponentNames.GANG).member_npc_ids:
		var e: Entity = _world.entities.get(m)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null or n.is_down or n.is_crew or out.size() >= SQUAD:
			continue
		n.position = at + Vector2.from_angle(out.size() * 2.1) * 22.0   # they come round the corner
		n.indoors = false
		n.is_busy = true
		_world.reindex_position(m)
		combat.hostile[m] = until
		out.append(m)
	return out

static func block_name(c: Vector2i) -> String:
	var h := Hoods.data()
	return h.name_of(c) if h != null else "the block"

func _gang(g: StringName) -> String:
	var e: Entity = _world.entities.get(g)
	return e.get_component(ComponentNames.GANG).display_name if e != null else String(g)
