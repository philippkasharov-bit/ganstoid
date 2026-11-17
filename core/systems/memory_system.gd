## ME1: the city remembers. Everyone you rob, hurt, threaten, catch your hand
## in their pocket, or who sees you do a crime, keeps it; so does anyone you
## help, pay or talk kindly to. A store you held up remembers too. One number
## each (feel: -1 hates and fears you, +1 owes you), kept in
## PlayerStateData.memories, only for people you have touched (cheap, saved).
## When one of them sees you again, twice a second, round you only:
##   robbed or hurt   they shout it ("That's him!") and run; the angry ones
##                    call the police on you, once
##   a bad feeling    they mutter and walk off quicker
##   they owe you     a hello; with police hunting you they tip you off,
##                    and they join your crew more readily (CrewSystem)
##   a store you hit  won't serve you ("Get out of my store")
## The line floats over their head (PlayerStateData.barks, BarkView). Feelings
## fade a little each day; a grudge lasts about a month, a favour a bit less.
class_name MemorySystem
extends SystemBase

const EVERY := 30
const PHASE := 26
const SEE_M := 9.0          # how close someone must be to know you again
const BARK_GAP_S := 40.0    # the same person speaks again after this long
const BARK_S := 3.5         # a line stays over a head this long
const REPORT_AT := -0.55    # this angry (and not too scared): they call it in, once
const RUN_AT := -0.45
const MUTTER_AT := -0.15
const FRIEND_AT := 0.25
const STORE_REFUSE := -0.5
const FADE := 0.93          # a day's fading (toward 0)
const GONE := 0.05          # weaker than this: forgotten
const MAX := 400            # kept memories (the weakest go first)
const TIP_M := 90.0         # a friend warns of police this close to you
const REPORT_SEVERITY := 0.25
const RECRUIT_PER_FEEL := 0.35   # a friend at +1 is this much more willing to join
## What each deed does to how someone feels about you.
const DEEDS := {
	"robbed": -0.7, "hurt": -0.6, "threatened": -0.4, "caught_lifting": -0.45, "saw_crime": -0.25,
	"store_robbed": -0.8, "helped": 0.35, "paid": 0.3, "talked": 0.1,
}
const LINES := {
	"robbed": ["That's him! He robbed me!", "You! You took my money!", "Stay away from me!"],
	"hurt": ["That's the one who hurt me!", "Get away from me!", "Somebody help!"],
	"threatened": ["You again...", "I don't want trouble.", "Leave me alone."],
	"caught_lifting": ["Watch it, pickpocket.", "Hands where I can see them.", "I know what you are."],
	"saw_crime": ["I saw what you did.", "I know your face.", "Keep walking."],
	"friend": ["Hey! Good to see you.", "Yo, what's good?", "Need anything, you let me know."],
	"report": ["I'm calling the cops!", "Police! It's him!", "Somebody call 911!"],
	"tip": ["Psst, cops %s. Go.", "Heads up: police %s.", "They're looking for you, %s."],
}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var reported := 0   # counters for the checks
var tipped := 0
var spoke := 0
var _last_day := -1

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE
	world.event_bus.subscribe(_on_event)

## Someone (or a store) keeps what you did to them.
static func remember(world: World, state: PlayerStateData, who_id: StringName, deed: String) -> void:
	if who_id == &"" or who_id == PlayerFactory.PLAYER_ENTITY_ID or not DEEDS.has(deed):
		return
	var m: Dictionary = state.memories.get(who_id, {})
	var feel := clampf(float(m.get("feel", 0.0)) + float(DEEDS[deed]), -1.0, 1.0)
	var worst: String = m.get("deed", deed)
	if DEEDS[deed] < 0.0 or float(m.get("feel", 0.0)) >= 0.0:
		worst = deed   # a fresh wrong replaces the story; a kindness only to a friend
	state.memories[who_id] = {"deed": worst, "feel": feel, "day": SimClock.day_number(world.tick), "n": int(m.get("n", 0)) + 1, "reported": bool(m.get("reported", false))}
	if state.memories.size() > MAX:
		_trim(state)

## How someone feels about you (-1..1), 0 if they don't know you.
static func feel_of(state: PlayerStateData, who_id: StringName) -> float:
	var m: Variant = state.memories.get(who_id)
	return clampf(float(m.get("feel", 0.0)), -1.0, 1.0) if m is Dictionary else 0.0

## A store you robbed won't serve you.
static func refuses(state: PlayerStateData, store_id: StringName) -> bool:
	return feel_of(state, store_id) <= STORE_REFUSE

## CrewSystem: someone who owes you is readier to join.
static func recruit_bonus(world: World, npc_id: StringName) -> float:
	var p: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return 0.0
	return maxf(0.0, feel_of(p.get_component(ComponentNames.PLAYER_STATE), npc_id)) * RECRUIT_PER_FEEL

static func _trim(state: PlayerStateData) -> void:
	var ids := state.memories.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return absf(feel_of(state, a)) < absf(feel_of(state, b)))
	for i in ids.size() - MAX:
		state.memories.erase(ids[i])

func _on_event(event_name: StringName, payload: Dictionary) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	match event_name:
		GanstoidEvents.ASSAULTED:
			remember(_world, state, payload.get("victim_id", &""), "hurt")
		GanstoidEvents.CRIME_WITNESSED:
			var id: StringName = payload.get("witness_id", &"")
			if not (state.memories.has(id) and feel_of(state, id) < DEEDS["saw_crime"]):
				remember(_world, state, id, "saw_crime")   # a victim stays a victim, not just a witness

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	for p in entities.values():
		var me: NPCData = p.get_component(ComponentNames.NPC)
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		_fade(state, tick)
		state.barks = state.barks.filter(func(b: Dictionary) -> bool: return int(b["until"]) > tick)
		if me.is_down or state.sleeping or state.memories.is_empty():
			continue
		for id in _world.spatial_index.query_nearby(me.position):
			if not state.memories.has(id):
				continue
			var e: Entity = _world.entities.get(id)
			var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
			if n == null or n.is_down or n.indoors or n.is_crew or n.position.distance_to(me.position) > SEE_M:
				continue
			if not CrimeSystem.can_see(_world, n.position, me.position):
				continue
			_meet(n, me, state, tick)

## Someone who remembers you has seen you.
func _meet(n: NPCData, me: NPCData, state: PlayerStateData, tick: int) -> void:
	var m: Dictionary = state.memories[n.id]
	if tick < int(m.get("spoke", -1000000)) + SimClock.real_seconds(BARK_GAP_S):
		return
	m["spoke"] = tick
	var feel := float(m.get("feel", 0.0))
	var deed: String = m.get("deed", "")
	var schedule := _world.find_system(NPCScheduleSystem) as NPCScheduleSystem
	if feel <= REPORT_AT and not bool(m.get("reported", false)) and n.fear < 0.6 and not n.is_cop:
		m["reported"] = true
		reported += 1
		bark(_world, state, n.id, _pick("report"), -1)
		_world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {"position": me.position, "severity": REPORT_SEVERITY, "tick": tick, "witness_id": n.id})
		if schedule != null:
			schedule.flee(n)
	elif feel <= RUN_AT:
		bark(_world, state, n.id, _pick(deed if LINES.has(deed) else "threatened"), -1)
		if schedule != null:
			schedule.flee(n)
	elif feel <= MUTTER_AT:
		bark(_world, state, n.id, _pick(deed if LINES.has(deed) else "saw_crime"), 0)
		if schedule != null:
			schedule.street.hurry(n, SimUnits.JOG * 0.75)
	elif feel >= FRIEND_AT:
		var cop := _nearest_hunter(me.position)
		if cop != Vector2.INF:
			tipped += 1
			bark(_world, state, n.id, _pick("tip") % NextStep.where(me.position, cop), 1)
		else:
			bark(_world, state, n.id, _pick("friend"), 1)
	else:
		return
	spoke += 1

## A line over someone's head for a few seconds (BarkView draws it).
static func bark(world: World, state: PlayerStateData, who_id: StringName, text: String, tone: int) -> void:
	state.barks = state.barks.filter(func(b: Dictionary) -> bool: return b["id"] != who_id)   # one line a head
	state.barks.append({"id": who_id, "text": text, "tone": tone, "until": world.tick + SimClock.real_seconds(BARK_S)})

func _pick(kind: String) -> String:
	var options: Array = LINES[kind]
	return options[_world.runtime_rng.randi() % options.size()]

## The closest cop hunting you within TIP_M, or INF.
func _nearest_hunter(at: Vector2) -> Vector2:
	var cops := _world.find_system(CopAISystem) as CopAISystem
	var best := Vector2.INF
	if cops == null:
		return best
	for h in cops.hunters():
		var c: Vector2 = h[0]
		if c.distance_to(at) <= TIP_M and (best == Vector2.INF or c.distance_to(at) < best.distance_to(at)):
			best = c
	return best

## Once a game day: everyone's feelings drift back toward nothing; the dead
## and the faint are forgotten.
func _fade(state: PlayerStateData, tick: int) -> void:
	var day := SimClock.day_number(tick)
	if day == _last_day:
		return
	var first := _last_day == -1
	_last_day = day
	if first:
		return
	for id in state.memories.keys():
		var m: Variant = state.memories[id]
		if not m is Dictionary:
			state.memories.erase(id)
			continue
		var e: Entity = _world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		m["feel"] = float(m.get("feel", 0.0)) * FADE
		if e == null or (n != null and n.is_down and n.health <= 0.0) or absf(m["feel"]) < GONE:
			state.memories.erase(id)
