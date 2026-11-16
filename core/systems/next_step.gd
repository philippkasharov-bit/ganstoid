## NX1: the one line at the top of the screen that always says what to do
## next, so a new player is never left wondering. Read-only: it only looks at
## the world. The first thing that applies wins:
##   a job under way   where to go and how long is left
##   an urgent need    bleeding, starving, parched, exhausted
##   the next rank     points still needed, and the best way to get them
##                     (a Street rat who has done no job is pointed at a fixer)
class_name NextStep
extends RefCounted

const URGENT := 0.15   # a need this low comes before everything but a job
const WHAT := {"debt": "Collect the debt (E by the mark)", "hit": "Put the mark down", "car": "Take the marked car",
	"heist": "Hit the store (watch it first: +50% pay)"}
const COMPASS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

static func line(world: World) -> String:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player == null:
		return ""
	var me: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	if me.is_down or state.sleeping:
		return ""
	if not state.job.is_empty():
		return _job(world, me, state)
	if me.bleeding:
		return "You're bleeding: press H and bandage the wound"
	if me.hunger < URGENT:
		return "You're starving: buy food at a shop counter (E), eat it from your bag (I)"
	if me.thirst < URGENT:
		return "You're parched: buy a drink at a shop counter (E), drink it from your bag (I)"
	if me.fatigue < URGENT:
		return "You're exhausted: press Z to sleep"
	if state.rank >= RankSystem.NAMES.size() - 1:
		return "You run this city. Keep it."
	var points := RankSystem.score(world, me, state)
	var next := state.rank + 1
	var head := "Next: %s at %d points (you have %d). " % [RankSystem.NAMES[next], RankSystem.THRESHOLDS[next], points]
	if state.jobs_done == 0:
		var fixer := nearest_fixer(world, me.position)
		if fixer != null:
			return head + "A fixer pays $120+ a job: purple jacket, %s" % where(me.position, fixer.position)
	if state.rank == 0:
		return head + "$50 cash = 1 point. Fixer jobs, crew (+8) and turf (+12) all count. K shows more"
	return head + "Crew +8 each, blocks held +12, a business +15. K shows more"

## The job you are on: what to do, where, and how long is left.
static func _job(world: World, me: NPCData, state: PlayerStateData) -> String:
	var left := maxf(0.0, float(state.job["deadline"] - world.tick) / SimClock.hours(1.0))
	var what: String = WHAT.get(state.job["kind"], "Finish the job")
	var at: Variant = JobSystem.target_point(world, state)
	if state.job["kind"] == "car" and state.vehicle_id == state.job["target"]:
		what = "Drop the car at the chop shop"
	var place := "" if at == null else ": " + where(me.position, at)
	return "Job: %s%s (%dh left, pays $%d)" % [what, place, ceili(left), state.job["pay"]]

static var _fixer_ids: Array = []   # the fixers of _fixers_of (JobSystem.seed picks them once per city)
static var _fixers_of := 0

## The closest fixer who is up and about, or null. Scanning 6000 people cost
## ~15 ms, so the fixers are found once per world and remembered.
static func nearest_fixer(world: World, from: Vector2) -> NPCData:
	if _fixers_of != world.get_instance_id():
		_fixers_of = world.get_instance_id()
		_fixer_ids = []
		for e in world.get_entities_with_component(ComponentNames.NPC).values():
			if (e.get_component(ComponentNames.NPC) as NPCData).is_fixer:
				_fixer_ids.append(e.id)
	var best: NPCData = null
	var best_d := INF
	for id in _fixer_ids:
		var e: Entity = world.entities.get(id)
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n != null and n.is_fixer and not n.is_down:
			var d := n.position.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = n
	return best

## "340 m north-east" (north is up on the N map), or "right here".
static func where(from: Vector2, to: Vector2) -> String:
	var d := from.distance_to(to)
	if d < 15.0:
		return "right here"
	var sector := posmod(roundi((to - from).angle() / (PI / 4.0)), 8)
	return "%d m %s" % [roundi(d / 10.0) * 10 if d >= 100.0 else roundi(d), COMPASS[sector]]
