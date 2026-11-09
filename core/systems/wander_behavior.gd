## Reusable "drift within a radius of an anchor, pausing between moves"
## behavior -- the shared shape behind NPCScheduleSystem's idle wander and
## CopAISystem's patrol wander, factored out here the moment a second
## system needed the exact same thing, rather than re-derived a third time
## whenever the next one does (crew loiter, rival gang turf-walking, a
## future lookout's "watch this corner" behavior, etc.).
##
## Static utility, same shape as CrimeSystem/DealSystem -- not a SystemBase,
## because "advance one mover's wander state by one tick" isn't itself a
## per-tick process over a component set, it's a step a caller's own
## per-tick system invokes once per mover it owns.
##
## Deliberately stateless: all per-mover state (current drift target,
## dwell-until tick) lives in Dictionaries the CALLER owns and passes in by
## reference -- GDScript Dictionaries are reference types, so mutations
## made in here are visible to the caller without this needing to return
## them. This means:
##   - no WanderBehavior instance to construct, store, or leak -- it's
##     never anything but a namespace for these static funcs
##   - no coupling to World/WeakRef at all -- it only ever reads/returns
##     Vector2 positions; the caller is the one that knows about World and
##     is responsible for calling World.reindex_position after applying
##     the returned position
##   - each caller's own per-tick Dictionary bookkeeping stays in its own
##     file (its own `_targets`/`_dwell_until` dicts), not split across two
##     classes just because the stepping logic is shared
class_name WanderBehavior
extends RefCounted

const DEFAULT_ARRIVE_EPSILON := SimUnits.ARRIVE_M

## Advances `mover_id`'s wander state by one tick and returns their new
## position. `anchor` is the point being wandered around (a depot, a
## destination building, a patrol post) -- every new drift target is
## picked relative to `anchor`, never relative to the mover's own current
## position, so this can never drift away from the actual anchor over time
## the way an unleashed random walk would.
##
## `targets`/`dwell_until` are the caller's own per-mover Dictionaries
## (StringName -> Vector2 / StringName -> int respectively) -- pass the
## same two dictionaries in every call for a given mover so its wander
## state persists tick to tick.
static func advance(
	mover_id: StringName,
	position: Vector2,
	anchor: Vector2,
	radius: float,
	speed: float,
	dwell_min_ticks: int,
	dwell_max_ticks: int,
	delta: float,
	tick: int,
	targets: Dictionary,
	dwell_until: Dictionary,
	arrive_epsilon: float = DEFAULT_ARRIVE_EPSILON,
	layer: String = "full"
) -> Vector2:
	if dwell_until.has(mover_id) and tick < dwell_until[mover_id]:
		return position  # paused -- a wandering mover shouldn't be in constant motion
	if not targets.has(mover_id) or position.distance_to(targets[mover_id]) <= arrive_epsilon:
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		if offset == Vector2.ZERO:
			offset = Vector2.RIGHT
		var spot := anchor + offset.normalized() * randf_range(0.0, radius)
		if SimNav.active != null:
			spot = SimNav.active.snap(spot, layer)   # never a spot inside a building or off the mover's ground
		targets[mover_id] = spot
		dwell_until[mover_id] = tick + randi_range(dwell_min_ticks, dwell_max_ticks)
		return position
	return step_toward(position, targets[mover_id], speed, delta, arrive_epsilon, mover_id, layer)

## Plain straight-line walk toward `target` at `speed`, clamped so a single
## step never overshoots. The one piece of movement math every mover in
## the game needs regardless of what decided the target (a commute
## destination, a wander drift point, a cop's live chase target) --
## callers that aren't wandering (NPCScheduleSystem's commute,
## CopAISystem's alert chase) use this directly instead of `advance`.
## With a SimNav installed and a mover_id given, the walk follows the real
## city's routes on `layer` instead of a straight line.
static func step_toward(position: Vector2, target: Vector2, speed: float, delta: float, arrive_epsilon: float = DEFAULT_ARRIVE_EPSILON, mover_id: StringName = &"", layer: String = "full") -> Vector2:
	var to_target := target - position
	var dist := to_target.length()
	if dist <= arrive_epsilon:
		return position
	if SimNav.active != null and mover_id != &"":
		return SimNav.active.step(mover_id, position, target, speed, delta, layer)
	var step := speed * delta
	return target if step >= dist else position + to_target / dist * step

## Drops `mover_id`'s wander state entirely. Call this when a mover leaves
## wander behavior for something else (a civilian starting a new commute,
## a cop going from patrol to an active alert) so stale state from the
## *previous* anchor doesn't linger -- one call instead of the two
## `.erase()`s this used to take at every such call site.
static func clear(mover_id: StringName, targets: Dictionary, dwell_until: Dictionary) -> void:
	targets.erase(mover_id)
	dwell_until.erase(mover_id)
	if SimNav.active != null:
		SimNav.active.forget(mover_id)
