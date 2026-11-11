## Needs (G2): hunger, thirst, tiredness for the player, Zomboid-style. 1.0 =
## fed / watered / rested, 0.0 = empty. Rates are per GAME day (1 real hour).
##   - About three meals and a few drinks a day keep you fine.
##   - Below LOW a need slows you and shakes your aim; at 0 hunger and thirst
##     cost health (thirst kills within about a day, hunger slower).
##   - Sleep (Z) is the only way to pass time faster: the world runs on at
##     SLEEP_SPEED while you are out. Your own bed rests you best.
##   - Fed, watered and not bleeding, you heal slowly.
class_name NeedsSystem
extends SystemBase

const HUNGER_PER_DAY := 0.6
const THIRST_PER_DAY := 1.0
const TIRED_PER_DAY := 1.5            # awake: empty after ~16 hours
const REST_PER_DAY_HOME := 3.0        # asleep in your own bed: full after ~8 hours
const REST_PER_DAY_ROUGH := 1.8       # asleep anywhere else
const STARVE_HEALTH_PER_DAY := 0.5
const THIRST_HEALTH_PER_DAY := 1.0
const HEAL_PER_DAY := 0.25
const LOW := 0.25
const SLEEP_SPEED := 60               # sim steps per frame while asleep
const BED_M := 6.0                    # this close to your own door counts as home

func _init() -> void:
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, delta: float, _tick: int) -> void:
	var days := delta / float(SimClock.day_ticks) * SimClock.TICKS_PER_SECOND
	for player in entities.values():
		var me: NPCData = player.get_component(ComponentNames.NPC)
		var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
		if not me.is_down:
			_drain(me, state, days)

func _drain(me: NPCData, state: PlayerStateData, days: float) -> void:
	me.hunger = maxf(0.0, me.hunger - HUNGER_PER_DAY * days)
	me.thirst = maxf(0.0, me.thirst - THIRST_PER_DAY * days)
	if state.sleeping:
		me.fatigue = minf(1.0, me.fatigue + (REST_PER_DAY_HOME if state.sleeping_home else REST_PER_DAY_ROUGH) * days)
	else:
		me.fatigue = maxf(0.0, me.fatigue - TIRED_PER_DAY * days)
	var hurt := 0.0
	if me.hunger <= 0.0:
		hurt += STARVE_HEALTH_PER_DAY * days
	if me.thirst <= 0.0:
		hurt += THIRST_HEALTH_PER_DAY * days
	if hurt > 0.0:
		me.health = maxf(0.0, me.health - hurt)
		if me.health <= 0.0:
			me.is_down = true
	elif me.hunger > 0.5 and me.thirst > 0.5 and not state.bleeding:
		me.health = minf(1.0, me.health + HEAL_PER_DAY * days)
	if state.sleeping and (me.fatigue >= 0.99 or me.health < state.health_at_sleep - 0.01 or me.hunger < 0.08 or me.thirst < 0.08):
		wake(state)   # rested, hurt, or too hungry or thirsty to sleep on

## Z: lie down (the world speeds up) or get up.
static func toggle_sleep(world: World, me: NPCData, state: PlayerStateData) -> Dictionary:
	if state.sleeping:
		wake(state)
		return {"ok": true, "effect": "woke"}
	if me.fatigue > 0.7:
		return {"ok": false, "reason": "not_tired"}
	state.sleeping = true
	state.health_at_sleep = me.health
	state.sleeping_home = _at_home(world, me)
	return {"ok": true, "effect": "sleep_home" if state.sleeping_home else "sleep_rough"}

static func wake(state: PlayerStateData) -> void:
	state.sleeping = false

static func _at_home(world: World, me: NPCData) -> bool:
	var home: Entity = world.entities.get(me.home_building_id)
	return home != null and home.get_component(ComponentNames.BUILDING).position.distance_to(me.position) <= BED_M

## Movement multiplier from the state of your body (tired, hungry, thirsty).
static func speed_factor(me: NPCData) -> float:
	var f := 1.0
	for need in [me.hunger, me.thirst]:
		if need < LOW:
			f *= 0.85
	if me.fatigue < LOW:
		f *= 0.7 if me.fatigue <= 0.0 else 0.85
	return f

## Aim spread multiplier: shaky hands when tired, hungry or thirsty.
static func spread_factor(me: NPCData) -> float:
	var f := 1.0
	for need in [me.hunger, me.thirst, me.fatigue]:
		if need < LOW:
			f *= 1.4
	return f

## Eats, drinks or applies one carried item. Returns {ok, effect|reason}.
static func use_item(me: NPCData, state: PlayerStateData, item_id: StringName) -> Dictionary:
	var it := ItemCatalog.item(item_id)
	if it.is_empty() or state.inventory.get(item_id, 0) <= 0:
		return {"ok": false, "reason": "dont_have"}
	if not it["kind"] in ["food", "drink", "medical"]:
		return {"ok": false, "reason": "cant_use"}
	me.hunger = minf(1.0, me.hunger + it.get("hunger", 0.0))
	me.thirst = minf(1.0, me.thirst + it.get("thirst", 0.0))
	me.fatigue = minf(1.0, me.fatigue + it.get("tired", 0.0))
	if it.has("heal"):
		me.health = minf(1.0, me.health + it["heal"])
		state.bleeding = false
	state.inventory[item_id] -= 1
	if state.inventory[item_id] <= 0:
		state.inventory.erase(item_id)
	return {"ok": true, "effect": "used_" + it["kind"]}
