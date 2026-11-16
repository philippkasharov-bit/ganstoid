## NP1: the morning paper. What you do that the papers would print (a mugging,
## a store hit, a break-in, a job done, an arrest...) is noted with the hood it
## happened in (StreetTalk passes every result here). At DAY_START the day's
## notes become a front page: the worst one the headline, a few more stories,
## city news when your night was quiet, and "word on the street": today's
## hustles. Saved on PlayerStateData (paper, news_today).
class_name NewsSystem
extends SystemBase

const PAPER_NAME := "The Downtown Courier"
## key -> [weight (the biggest is the headline), headline, story ({hood}, {n})]
const STORIES := {
	"robbery": [9, "STORE HELD UP IN {HOOD}", "A clerk in {hood} was robbed at the register. ${n} taken; police have no suspect."],
	"job_done": [7, "{HOOD}: 'A PROFESSIONAL JOB'", "Police in {hood} believe a hired hand was behind last night's trouble."],
	"burgled": [6, "BREAK-IN WAVE HITS {HOOD}", "Another home in {hood} broken into. Neighbours ask where the patrols are."],
	"mugged": [5, "MUGGER STRIKES IN {HOOD}", "A resident of {hood} was held up and robbed of ${n}. The attacker fled on foot."],
	"arrested": [8, "LOCAL HOOD ARRESTED", "Officers picked up a suspect wanted for a string of street crimes."],
	"arrested_seized": [8, "ARREST, CASH SEIZED", "Police seized ${n} in cash from a suspect arrested in {hood}."],
	"gang_job": [4, "GANG ACTIVITY IN {HOOD}", "Residents of {hood} report a rise in gang activity on their corners."],
	"tagged": [2, "NEW TAGS ON {HOOD} WALLS", "Fresh graffiti in {hood}. The city's clean-up crews can't keep up."],
	"pickpocket": [2, "PICKPOCKETS ON THE BUS LINES", "Riders in {hood} warned to watch their wallets: ${n} lifted in one theft."],
	"sell": [3, "DRUG TRADE ON {HOOD} CORNERS", "Residents say deals happen in broad daylight in {hood}."],
	"grow_house_raided": [8, "GROW HOUSE BUSTED", "Police raided a house full of plants and lamps in {hood}."],
	"business_bought": [3, "NEW OWNER FOR {HOOD} BUSINESS", "A {hood} business changed hands for ${n}. The buyer paid cash."],
}
const CITY_NEWS := [
	"Heat wave: 98 degrees downtown, no relief before the weekend.",
	"City council argues over the bus fare hike again.",
	"Freeway closed overnight after a big-rig spill.",
	"Power cut leaves six blocks dark for an hour.",
	"Rent up again: families squeezed out of downtown flats.",
	"Police chief promises more patrols 'where it counts'.",
	"Swap meet draws record crowds on Sunday.",
	"Water main bursts, floods a downtown intersection.",
	"Local boxing gym sends two kids to the state finals.",
	"Late-night taco stand voted best in the city.",
]
const STORIES_MAX := 3

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
	var day := HustleSystem.day_of(tick)
	for p in entities.values():
		var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
		if state.paper_day == day:
			continue
		var first := state.paper_day == -1000000 or day < state.paper_day   # a new life, or the clock set back: no paper
		state.paper_day = day
		if first:
			continue   # a new life: no paper before the first morning
		state.paper = print_paper(state, day)
		state.news_today = []
		state.paper_serial += 1

## A result came in (StreetTalk): note it if the papers would print it.
static func note(world: World, state: PlayerStateData, key: String, amount: int) -> void:
	if not STORIES.has(key):
		return
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	state.news_today.append([key, amount, hood_at(me.position)])

static func hood_at(p: Vector2) -> String:
	var h := Hoods.data()
	if h == null:
		return "downtown"
	var place := h.place(TerritoryData.turf_of(p))
	return String(place.get("hood", "downtown"))

## The front page: {name, day, headline, lead, stories: [[title, text]], city: [..], street: [..]}.
static func print_paper(state: PlayerStateData, day: int) -> Dictionary:
	var notes: Array = state.news_today.duplicate()
	notes.sort_custom(func(a: Array, b: Array) -> bool: return STORIES[a[0]][0] > STORIES[b[0]][0])
	var stories: Array = []
	var seen := {}
	for n in notes:
		var k: String = n[0] + "|" + n[2]
		if seen.has(k):
			continue   # one story per kind per hood
		seen[k] = true
		stories.append([_fill(STORIES[n[0]][1], n), _fill(STORIES[n[0]][2], n)])
		if stories.size() > STORIES_MAX:
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("paper" + str(day))
	var city: Array = []
	var pool := CITY_NEWS.duplicate()
	for i in (2 if stories.is_empty() else 1):
		city.append(pool.pop_at(rng.randi() % pool.size()))
	var head: Array = stories.pop_front() if not stories.is_empty() else ["QUIET NIGHT IN THE CITY", city.pop_front()]
	var street: Array = []
	for h in state.hustles:
		street.append(HustleSystem.text_of(h) + "  ($%d)" % int(h["pay"]))
	return {"name": PAPER_NAME, "day": day + 1, "headline": head[0], "lead": head[1], "stories": stories, "city": city, "street": street}

static func _fill(t: String, n: Array) -> String:
	return t.replace("{HOOD}", String(n[2]).to_upper()).replace("{hood}", n[2]).replace("{n}", str(n[1]))
