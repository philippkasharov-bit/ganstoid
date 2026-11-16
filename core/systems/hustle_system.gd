## DH1: daily hustles. Every morning at DAY_START three short jobs come in on
## the pager ("move 3 bags before 22:00, $120"). They are done by playing:
## progress is counted from the results of what you do (StreetTalk passes every
## result here), so no extra steps. Finishing one pays at once; at the deadline
## an unfinished one is gone. Saved on PlayerStateData.hustles.
class_name HustleSystem
extends SystemBase

const DAY_START := 7.0
const PER_DAY := 3
## kind -> [text ("{n}" = how many), result keys that count, how many, pay, deadline hour, min rank, counts money?]
const KINDS := {
	"sell": ["Move {n} bags of product", ["sell"], 3, 120, 22.0, 0, false],
	"street": ["Take ${n} off people on the street", ["mugged", "pickpocket"], 60, 90, 22.0, 0, true],
	"burgle": ["Get into a house or flat", ["burgled"], 1, 140, 28.0, 0, false],
	"tag": ["Put your tag up on {n} blocks", ["tagged"], 2, 70, 22.0, 0, false],
	"rob": ["Hit a store", ["robbery"], 1, 200, 28.0, 1, false],
	"fixer": ["Finish a fixer's job", ["job_done"], 1, 100, 28.0, 0, false],
	"shift": ["Work an honest shift", ["shift_done"], 1, 60, 20.0, 0, false],
	"gang": ["Do a job for a gang", ["gang_job"], 1, 110, 22.0, 1, false],
}

var _world_ref: WeakRef
var _world: World:
	get:
		return _world_ref.get_ref()

func _init(world: World) -> void:
	_world_ref = weakref(world)
	tick_rate = GanstoidEnums.TickRate.HOT
	required_component = ComponentNames.PLAYER_STATE

func process_entities(entities: Dictionary, _delta: float, tick: int) -> void:
	if tick % SimClock.TICKS_PER_SECOND != 0:
		return
	var day := day_of(tick)
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.hustle_day != day:
			roll(_world, state, day)
		for h in state.hustles.duplicate():
			if not h["done"] and tick > int(h["deadline"]):
				state.hustles.erase(h)   # missed it

## The hustle day a tick belongs to (it turns over at DAY_START, not midnight).
static func day_of(tick: int) -> int:
	return int(floor((float(tick) / SimClock.day_ticks) - DAY_START / 24.0))

## Today's three, seeded by the day (the same after a reload).
static func roll(world: World, state: PlayerStateData, day: int) -> void:
	state.hustle_day = day
	state.hustles = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hustles" + str(day))
	var pool: Array = []
	for k in KINDS:
		if state.rank >= int(KINDS[k][5]):
			pool.append(k)
	var start := (float(day) + DAY_START / 24.0) * SimClock.day_ticks
	while state.hustles.size() < PER_DAY and not pool.is_empty():
		var k: String = pool.pop_at(rng.randi() % pool.size())
		var spec: Array = KINDS[k]
		var pay := int(spec[3] * (1.0 + 0.25 * state.rank))
		state.hustles.append({"kind": k, "need": spec[2], "got": 0, "pay": pay, "done": false,
			"deadline": int(start + (float(spec[4]) - DAY_START) / 24.0 * SimClock.day_ticks)})

## A result came in (StreetTalk): moves any hustle it counts for; pays the finished ones.
static func progress(world: World, state: PlayerStateData, key: String, amount: int) -> void:
	for h in state.hustles:
		var spec: Array = KINDS.get(h["kind"], [])
		if h["done"] or spec.is_empty() or not (spec[1] as Array).has(key):
			continue
		h["got"] = int(h["got"]) + (amount if spec[6] else 1)
		if int(h["got"]) >= int(h["need"]):
			h["done"] = true
			if h["kind"] == "shift":
				Wallet.earn_clean(world, int(h["pay"]))
			else:
				Wallet.earn_dirty(world, int(h["pay"]))
			state.last_message = "Hustle done: %s. +$%d" % [text_of(h), int(h["pay"])]
			state.message_alert = true
			state.message_tone = 1
			state.message_serial += 1

static func text_of(h: Dictionary) -> String:
	return String(KINDS[h["kind"]][0]).replace("{n}", str(h["need"]))

## "Move 3 bags of product  1/3  $120  until 22:00" for the pager.
static func line(world: World, h: Dictionary) -> String:
	var hours := SimClock.day_fraction(int(h["deadline"])) * 24.0
	var status := "DONE" if h["done"] else "%d/%d" % [mini(int(h["got"]), int(h["need"])), int(h["need"])]
	if KINDS[h["kind"]][6] and not h["done"]:
		status = "$%d/$%d" % [int(h["got"]), int(h["need"])]
	return "%s   %s   $%d   until %02d:00" % [text_of(h), status, int(h["pay"]), int(hours) % 24]
