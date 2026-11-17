## RV1: rivals with names. Every gang has a lieutenant who runs its corners:
## a real member of the gang with a street name and a temper. Hurt his gang
## (beat or shoot his people, tag over his blocks, take his turf) and his
## grudge against you grows:
##   THREAT   word reaches you (a message)
##   HUNT     on or near his turf, he sends people at you
##   AMBUSH   at night they wait for you round your home
##   PERSONAL he comes himself, with everyone he has
## Put him down and it changes: knocked out, he gets up with a scar, a new
## name and a worse grudge; dead, someone hungrier takes his place (a bit
## tougher, a calmer start). It all makes the paper. Saved on PlayerStateData.rivals.
class_name RivalSystem
extends SystemBase

const PHASE := 29
const EVERY := 60
const THREAT := 25.0
const HUNT := 50.0
const AMBUSH := 75.0
const PERSONAL := 100.0
const HIT_GRUDGE := 12.0          # one of his people hurt by you
const TAG_GRUDGE := 6.0           # your tag on his block
const COOL_PER_DAY := 8.0         # grudges cool a little each game day
const HUNT_M := 160.0             # this close to his turf and he sends people
const HOME_M := 60.0
const SQUAD_EVERY_S := 90.0
const STREET_NAMES := ["Lil Dre", "Spider", "Smokey", "Big Tone", "Chino", "Ghost", "Joker", "Psycho", "Sleepy", "Shorty",
	"Droopy", "Huero", "Lefty", "Termite", "Casper", "Puppet", "Bones", "Whisper", "Trigger", "Diablo"]
const TEMPERS := ["hot-headed", "patient", "proud", "paranoid", "greedy"]
const SCARRED := ["Scar", "Cut", "Stitches", "One-Eye", "Busted"]

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()
var _squad_at: Dictionary = {}    # gang id -> tick of the last squad sent

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, delta: float, tick: int) -> void:
	if tick % EVERY != PHASE:
		return
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		var me: NPCData = p.get_component(ComponentNames.NPC)
		ensure(_world, state)
		for g in state.rivals:
			var r: Dictionary = state.rivals[g]
			_check_down(state, g, r)
			r["grudge"] = maxf(0.0, float(r["grudge"]) - COOL_PER_DAY * float(EVERY) / SimClock.day_ticks)
			if not me.is_down and not state.sleeping:
				_act(state, me, g, r, tick)

## One lieutenant per gang, picked from its members (seeded by the gang, so a reload picks the same).
static func ensure(world: World, state: PlayerStateData) -> void:
	for e in world.get_entities_with_component(ComponentNames.GANG).values():
		var gang: GangData = e.get_component(ComponentNames.GANG)
		if gang.is_destroyed or state.rivals.has(gang.id):
			continue
		var lt := _pick(world, gang, int(hash(String(gang.id))))
		if lt == null:
			continue
		state.rivals[gang.id] = _new_rival(lt, int(hash(String(gang.id))), 1)

static func _new_rival(lt: NPCData, seed: int, level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + level * 7919
	return {"npc": lt.id, "name": STREET_NAMES[rng.randi() % STREET_NAMES.size()], "real": lt.display_name if not lt.display_name.begins_with("Dealer") else PopulationSeeder.civilian_name(absi(seed) % 997),
		"temper": TEMPERS[rng.randi() % TEMPERS.size()], "grudge": 0.0, "level": level, "scars": 0, "stage": 0, "down_seen": false}

static func _pick(world: World, gang: GangData, seed: int) -> NPCData:
	var alive: Array = []
	for m in gang.member_npc_ids:
		var e: Entity = world.entities.get(m)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and not n.is_down and not n.is_crew:
			alive.append(n)
	if alive.is_empty():
		return null
	alive.sort_custom(func(a: NPCData, b: NPCData) -> bool: return String(a.id) < String(b.id))
	return alive[absi(seed) % alive.size()]

## Grudge from what you did (CombatSystem's ASSAULTED, a tag on his block).
func on_assaulted(event_name: StringName, payload: Dictionary) -> void:
	if event_name != GanstoidEvents.ASSAULTED:
		return
	var e: Entity = _world.entities.get(payload.get("victim_id", &""))
	var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if n == null or n.gang_id == &"" or p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	ensure(_world, state)
	grow(_world, state, n.gang_id, HIT_GRUDGE * (2.0 if n.id == state.rivals.get(n.gang_id, {}).get("npc", &"") else 1.0))

## A result came in (StreetTalk): a tag on a rival's block.
static func note(world: World, state: PlayerStateData, key: String) -> void:
	if key != "tagged":
		return
	var t := TerritorySystem.data(world)
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	if t == null:
		return
	var owner := TerritorySystem.controller(t, TerritoryData.turf_of(me.position))
	if owner != &"" and owner != TerritorySystem.PLAYER:
		ensure(world, state)
		grow(world, state, owner, TAG_GRUDGE)

static func grow(world: World, state: PlayerStateData, gang: StringName, by: float) -> void:
	if not state.rivals.has(gang):
		return
	var r: Dictionary = state.rivals[gang]
	var mult := 1.4 if r["temper"] == "hot-headed" else (0.7 if r["temper"] == "patient" else 1.0)
	r["grudge"] = minf(PERSONAL, float(r["grudge"]) + by * mult)

## What his grudge makes him do now.
func _act(state: PlayerStateData, me: NPCData, g: StringName, r: Dictionary, tick: int) -> void:
	var grudge := float(r["grudge"])
	var stage := 0
	for s in [THREAT, HUNT, AMBUSH, PERSONAL]:
		stage += int(grudge >= s)
	if stage > int(r["stage"]):
		r["stage"] = stage
		_message(state, r, stage)
	elif stage < int(r["stage"]):
		r["stage"] = stage
	if stage < 2 or tick - int(_squad_at.get(g, -1000000)) < int(SQUAD_EVERY_S * SimClock.TICKS_PER_SECOND):
		return
	var combat := _world.find_system(NPCCombatSystem) as NPCCombatSystem
	if combat == null:
		return
	var near_turf := _near_turf(g, me.position)
	var near_home := false
	if me.home_building_id != &"" and _world.entities.has(me.home_building_id):
		var home: BuildingData = _world.entities[me.home_building_id].get_component(ComponentNames.BUILDING)
		near_home = home.position.distance_to(me.position) <= HOME_M and StreetLights.darkness(SimClock.day_fraction(tick) * 24.0) > 0.5
	var send := 0
	if stage >= 2 and near_turf:
		send = 2
	if stage >= 3 and near_home:
		send = 3
	if stage >= 4:
		send = 5
	if send == 0:
		return
	_squad_at[g] = tick
	var sent := combat.send_squad(g, send + int(r["level"]) - 1, tick)
	if stage >= 4:
		var lt := _npc(r["npc"])
		if lt != null and not lt.is_down:
			combat.hostile[lt.id] = tick + int(NPCCombatSystem.HOSTILE_S * SimClock.TICKS_PER_SECOND)
			lt.is_busy = true
	if sent > 0:
		StreetTalk.say_key(_world, state, "rival_coming", sent)
		StampView.put(state, "%s'S PEOPLE" % String(r["name"]).to_upper(), "they're coming for you", UiTheme.BAD)

func _near_turf(g: StringName, at: Vector2) -> bool:
	var t := TerritorySystem.data(_world)
	if t == null:
		return false
	for c in TerritoryData.neighbours(TerritoryData.turf_of(at)) + [TerritoryData.turf_of(at)]:
		if TerritorySystem.controller(t, c) == g and TerritoryData.centre_of(c).distance_to(at) <= HUNT_M:
			return true
	return false

## He went down since we last looked: a scar and a new name, or a successor.
func _check_down(state: PlayerStateData, g: StringName, r: Dictionary) -> void:
	var lt := _npc(r["npc"])
	if lt == null:
		return
	if not lt.is_down:
		r["down_seen"] = false
		return
	if r["down_seen"]:
		return
	r["down_seen"] = true
	if lt.ko_until_tick >= 0:   # knocked out: he will get up, scarred and angrier
		r["scars"] = int(r["scars"]) + 1
		Rep.add(state, 8.0)   # RP1
		var old: String = r["name"]
		r["name"] = "%s %s" % [SCARRED[(int(r["scars"]) - 1) % SCARRED.size()], old.split(" ")[-1]]
		r["grudge"] = minf(PERSONAL, float(r["grudge"]) + 25.0)
		NewsSystem.note_story(state, "rival_scarred", r["name"], lt.position)
		StampView.put(state, "%s WENT DOWN" % old.to_upper(), "they'll be back: \"%s\" now" % r["name"])
		return
	var gang_e: Entity = _world.entities.get(g)
	var next := _pick(_world, gang_e.get_component(ComponentNames.GANG), int(hash(String(g))) + int(r["level"])) if gang_e != null else null
	NewsSystem.note_story(state, "rival_killed", r["name"], lt.position)
	Rep.add(state, 12.0)   # RP1
	StampView.put(state, "%s IS DEAD" % String(r["name"]).to_upper(), "someone will take those corners")
	if next != null:
		var lvl := int(r["level"]) + 1
		var nr := _new_rival(next, int(hash(String(g))), lvl)
		nr["grudge"] = 30.0   # the new man knows who did it
		state.rivals[g] = nr
		StreetTalk.say_key(_world, state, "rival_new")
	else:
		state.rivals.erase(g)

func _message(state: PlayerStateData, r: Dictionary, stage: int) -> void:
	var lines := ["", "Word on the street: %s from %s has your name in their mouth.", "%s put the word out: you're not welcome near %s corners.",
		"%s knows where you sleep. %s were seen round your place.", "%s is done talking. All of %s is coming."]
	var gang_name := _gang_name(r)
	state.last_message = lines[stage] % [r["name"], gang_name]
	PhoneSystem.push(_world, state, "Unknown number", state.last_message)   # PH1
	state.message_alert = true
	state.message_tone = -1
	state.message_serial += 1

func _gang_name(r: Dictionary) -> String:
	var n := _npc(r["npc"])
	if n == null:
		return "their crew"
	var e: Entity = _world.entities.get(n.gang_id)
	return e.get_component(ComponentNames.GANG).display_name if e != null else "their crew"

func _npc(id: StringName) -> NPCData:
	var e: Entity = _world.entities.get(id)
	return e.get_component(ComponentNames.NPC) if e != null else null
