## Combat (C2): resolves one attack by the player toward the mouse. Pure rules on
## World data, no input and no drawing.
##
## - Fists: hits the nearest person in front within arm's reach; a wall between
##   blocks it.
## - Pistol: one round flies along the aim line, spread by how steady the aim is
##   (hip fire vs raised); the first body or wall on the line stops it.
## - A hit costs health; at 0 the person is down for good.
## - Witnesses see it like any other crime; a gunshot is heard far beyond sight.
class_name CombatSystem
extends RefCounted

const BODY_R := 0.35            # metres: a body's half-width, what a round must pass within
const RAY_STEP_M := 0.25        # wall test step along a shot
const WEAPONS := {
	&"fists": {"melee": true, "range": 1.3, "arc_deg": 80.0, "damage": 0.2, "cooldown_s": 0.55, "heard_m": 0.0},
	&"pistol": {"melee": false, "range": 35.0, "damage": 0.55, "cooldown_s": 0.3,
		"spread_hip_deg": 8.0, "spread_aim_deg": 2.0, "heard_m": 300.0},
}
const ORDER: Array[StringName] = [&"fists", &"pistol"]

## Next weapon in hand (Q).
static func cycle_weapon(state: PlayerStateData) -> StringName:
	state.weapon = ORDER[(ORDER.find(state.weapon) + 1) % ORDER.size()]
	return state.weapon

## One attack toward state.aim_point. Returns {ok, weapon, hit_id?, downed?, end, reason?}
## (`end` = where the blow or round stopped: for drawing).
static func attack(world: World, me: NPCData, state: PlayerStateData, tick: int, rng: RandomNumberGenerator) -> Dictionary:
	if tick < state.attack_ready_tick:
		return {"ok": false, "reason": "not_ready"}
	var w: Dictionary = WEAPONS[state.weapon]
	if not w["melee"] and state.ammo <= 0:
		return {"ok": false, "reason": "no_ammo", "weapon": state.weapon}
	state.attack_ready_tick = tick + int(w["cooldown_s"] * SimClock.TICKS_PER_SECOND)
	var dir := (state.aim_point - me.position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var result := _swing(world, me, dir, w) if w["melee"] else _shoot(world, me, state, dir, w, rng)
	result["ok"] = true
	result["weapon"] = state.weapon
	_witness(world, me.position, w, result)
	return result

static func _swing(world: World, me: NPCData, dir: Vector2, w: Dictionary) -> Dictionary:
	var best: NPCData = null
	var best_d: float = w["range"]
	var half_arc := deg_to_rad(w["arc_deg"]) * 0.5
	for npc in _people_near(world, me.position):
		var to := npc.position - me.position
		var d := to.length()
		if d <= best_d and absf(dir.angle_to(to)) <= half_arc and _clear(me.position, npc.position):
			best = npc
			best_d = d
	if best == null:
		return {"end": me.position + dir * w["range"]}
	return _hurt(best, w["damage"])

static func _shoot(world: World, me: NPCData, state: PlayerStateData, dir: Vector2, w: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	state.ammo -= 1
	state.shots_fired += 1
	var spread := deg_to_rad(w["spread_aim_deg"] if state.aiming else w["spread_hip_deg"])
	dir = dir.rotated(rng.randf_range(-spread, spread))
	var reach := _wall_distance(me.position, dir, w["range"])
	var best: NPCData = null
	var best_t := reach
	for npc in _people_near(world, me.position):
		var t := (npc.position - me.position).dot(dir)
		if t > 0.0 and t < best_t and (me.position + dir * t).distance_to(npc.position) <= BODY_R:
			best = npc
			best_t = t
	var out := {"end": me.position + dir * best_t}
	if best != null:
		out.merge(_hurt(best, w["damage"]))
	return out

static func _hurt(npc: NPCData, damage: float) -> Dictionary:
	npc.health = maxf(0.0, npc.health - damage)
	if npc.health <= 0.0:
		npc.is_down = true
		npc.is_busy = false
	return {"hit_id": npc.id, "downed": npc.is_down, "end": npc.position}

## Distance along `dir` to the first wall, or `reach` if none.
static func _wall_distance(from: Vector2, dir: Vector2, reach: float) -> float:
	var col := SimNav.active.collision if SimNav.active != null else null
	if col == null:
		return reach
	var t := RAY_STEP_M
	while t < reach:
		if col.blocked(from + dir * t, 0.0):
			return t
		t += RAY_STEP_M
	return reach

static func _clear(a: Vector2, b: Vector2) -> bool:
	return SimNav.active == null or SimNav.active.collision.line_clear(a, b, 0.0)

## Everyone on the street near `p` who can be hurt: not the player, not indoors, not already down.
static func _people_near(world: World, p: Vector2) -> Array[NPCData]:
	var out: Array[NPCData] = []
	for id in world.spatial_index.query_nearby(p):
		var entity: Entity = world.entities.get(id)
		if entity == null or entity.has_component(ComponentNames.PLAYER_STATE):
			continue
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc != null and not npc.indoors and not npc.is_down:
			out.append(npc)
	return out

## Seen like any crime: a blow that lands is assault, a body on the ground is
## murder. A shot is heard: everyone within earshot counts as a witness of it.
static func _witness(world: World, at: Vector2, w: Dictionary, result: Dictionary) -> void:
	var crime := GanstoidEnums.CrimeType.ASSAULT
	if result.get("downed", false):
		crime = GanstoidEnums.CrimeType.MURDER
	elif not result.has("hit_id") and w["heard_m"] <= 0.0:
		return   # a swing at the air is nothing anyone reports
	CrimeSystem.broadcast_witnesses(world, at, CrimeSystem.SEVERITY_BY_TYPE[crime])
	if w["heard_m"] > 0.0:
		world.event_bus.emit(GanstoidEvents.GUNSHOT, {"position": at, "heard_m": w["heard_m"], "tick": world.tick})
