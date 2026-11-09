## Crime actions: the Phase 1 locked mechanics spec, made real. Not a
## SystemBase -- crimes are discrete player-triggered actions, not a
## per-tick process, so this is a static utility (same shape as
## CityRoles/PlayerFactory) called directly by whatever triggers a
## crime (PlayerInputSystem today; an NPC-vs-NPC crime, if ever added,
## would call the same entry point).
##
## Witnessing is generic across every crime type (severity lookup +
## broadcast); the ACTUAL EFFECT of a crime is type-specific and only
## PICKPOCKET has one implemented this phase. Adding a new crime type later
## means adding its severity (already has a slot) and its effect branch in
## commit_crime -- witnessing doesn't need to change.
class_name CrimeSystem
extends RefCounted

## How close the player must be to a potential pickpocket victim.
const INTERACT_RADIUS := 2.5   # metres: within arm's reach / at the counter
## How close a witness must be to roll an actual recognition (vs. just
## having their general recognition_chance nudged by the broadcast below).
const ENCOUNTER_RADIUS := 15.0   # metres: close enough to see your face clearly

const PICKPOCKET_MIN := 5
const PICKPOCKET_MAX := 25

## Batch 6 (locked): fraction of a building's cash_on_hand taken by a
## building-robbery action, same "diminishing swing" reasoning as
## PICKPOCKET_MIN/MAX -- a range, not a flat cut, so repeated robberies of
## the same building don't all look identical.
const ROBBERY_TAKE_MIN_FRACTION := 0.3
const ROBBERY_TAKE_MAX_FRACTION := 0.7

## Batch 9 (locked): the minimal gang-job action's payout shape -- a small
## flat base, scaled by standing with the owning gang using the exact same
## multiplier shape as DealSystem's relationship pricing (neutral standing
## = exactly base, better standing = more). Paid out of GangData.cash, a
## finite pool GangSeeder seeds once and nothing regenerates yet (see that
## file's doc comment) -- so a gang can and will run out of jobs to offer
## until a future gang-income system replenishes it. GANG_JOB_STANDING_GAIN
## is deliberately a bit higher than DealSystem.RELATIONSHIP_GAIN_PER_TRADE
## -- doing an actual job for a gang earns more trust than one purchase.
const GANG_JOB_BASE_PAYOUT := 40
const GANG_JOB_STANDING_SWING := 0.5
const GANG_JOB_STANDING_GAIN := 0.1

## Batch 10 (locked): how close a witnessed-and-recognized crime has to
## land to a building for it to count as evidence against THAT building
## (BuildingData.crime_heat), and how hard one such crime bumps it. Looser
## than ENCOUNTER_RADIUS -- a crime doesn't have to happen on a building's
## exact doorstep to read as "something's going on around here."
const CRIME_HEAT_RADIUS := 60.0   # roughly the block around the crime
const CRIME_HEAT_GAIN := 0.2

## Fixed per-crime-type severity (roadmap Phase 1 lock) -- feeds
## RecognitionSystem.register_witness, not the crime's gameplay effect.
const SEVERITY_BY_TYPE := {
	GanstoidEnums.CrimeType.PICKPOCKET: 0.15,
	GanstoidEnums.CrimeType.CAR_BREAK_IN: 0.2,
	GanstoidEnums.CrimeType.DRUG_DEAL_OBSERVED: 0.1,
	GanstoidEnums.CrimeType.ASSAULT: 0.5,
	GanstoidEnums.CrimeType.ARMED_ROBBERY: 0.6,
	GanstoidEnums.CrimeType.MURDER: 1.0,
	GanstoidEnums.CrimeType.GANG_JOB: 0.3,
	GanstoidEnums.CrimeType.EXTORTION: 0.35,
}

## victim_id is only consumed by crime types that need one (PICKPOCKET);
## ignored otherwise. Returns a result dict ({"ok": bool, ...}) rather than
## throwing -- "too far from victim" or "no player" are ordinary outcomes a
## caller (PlayerInputSystem) needs to branch on, not error conditions.
static func commit_crime(world: World, crime_type: GanstoidEnums.CrimeType, victim_id: StringName = &"") -> Dictionary:
	var player_entity := _get_player_entity(world)
	if player_entity == null:
		return {"ok": false, "reason": "no_player"}
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)

	var result: Dictionary
	match crime_type:
		GanstoidEnums.CrimeType.PICKPOCKET:
			result = _do_pickpocket(world, player_npc, victim_id)
		_:
			# Witnessing still fires below even without an effect -- a crime
			# type can be "live" for heat purposes before its effect is built.
			push_warning("CrimeSystem: crime_type %s has no gameplay effect yet -- witnessing only" % crime_type)
			result = {"ok": true, "effect": "none"}

	if result.get("ok", false):
		broadcast_witnesses(world, player_npc.position, SEVERITY_BY_TYPE[crime_type])
	return result

static func _do_pickpocket(world: World, player_npc: NPCData, victim_id: StringName) -> Dictionary:
	if victim_id == &"" or not world.entities.has(victim_id):
		return {"ok": false, "reason": "no_victim"}
	var victim_entity: Entity = world.entities[victim_id]
	var victim_npc: NPCData = victim_entity.get_component(ComponentNames.NPC)
	if victim_npc == null:
		return {"ok": false, "reason": "victim_not_npc"}
	if victim_npc.position.distance_to(player_npc.position) > INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	var stolen: int = mini(victim_npc.cash, world.runtime_rng.randi_range(PICKPOCKET_MIN, PICKPOCKET_MAX))
	victim_npc.cash -= stolen
	Wallet.earn_dirty(world, stolen)  # batch 24: crime money is dirty
	return {"ok": true, "effect": "pickpocket", "stolen": stolen}

## Batch 6 (locked): the building-robbery action -- the other half of the
## "robbed corners get poorer/more guarded" feedback loop EconomySystem's
## apply_robbery doc comment reserved this entry point for. Not folded into
## commit_crime's match because the "victim" here is a BuildingData, not an
## NPCData -- a separate entry point reads cleaner than overloading
## commit_crime's victim_id to sometimes mean "building instead of NPC".
## Still witnesses via the same broadcast_witnesses path, at the
## already-reserved ARMED_ROBBERY severity, so it escalates heat exactly
## like any other crime -- see the roadmap's "evidence-gated law response"
## constraint, unaffected by this addition.
static func rob_building(world: World, building_id: StringName) -> Dictionary:
	var player_entity := _get_player_entity(world)
	if player_entity == null:
		return {"ok": false, "reason": "no_player"}
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	if not world.entities.has(building_id):
		return {"ok": false, "reason": "no_building"}
	var building: BuildingData = world.entities[building_id].get_component(ComponentNames.BUILDING)
	if building == null:
		return {"ok": false, "reason": "not_a_building"}
	if building.position.distance_to(player_npc.position) > INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	if building.cash_on_hand <= 0:
		return {"ok": false, "reason": "nothing_to_take"}
	var fraction := world.runtime_rng.randf_range(ROBBERY_TAKE_MIN_FRACTION, ROBBERY_TAKE_MAX_FRACTION)
	var taken: int = maxi(1, int(round(building.cash_on_hand * fraction)))
	EconomySystem.apply_robbery(building, taken)
	Wallet.earn_dirty(world, taken)  # batch 24
	broadcast_witnesses(world, building.position, SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.ARMED_ROBBERY])
	return {"ok": true, "effect": "robbery", "taken": taken}

## Batch 9 (locked): the minimal gang-job action -- a small paid errand on
## a gang's own turf. Not gated on standing at all (a job is on offer
## whenever the gang can still afford one); standing only scales the
## PAYOUT, via _gang_job_multiplier, same "no hard gate, just a better
## deal" shape Batch 8 already uses for drug-deal pricing. Still witnesses
## through the same broadcast_witnesses path as every other action, at the
## reserved GANG_JOB severity -- no new trigger logic, same evidence-gated
## law response as always.
static func do_gang_job(world: World, building_id: StringName) -> Dictionary:
	var player_entity := _get_player_entity(world)
	if player_entity == null:
		return {"ok": false, "reason": "no_player"}
	var player_npc: NPCData = player_entity.get_component(ComponentNames.NPC)
	if not world.entities.has(building_id):
		return {"ok": false, "reason": "no_building"}
	var building: BuildingData = world.entities[building_id].get_component(ComponentNames.BUILDING)
	if building == null:
		return {"ok": false, "reason": "not_a_building"}
	if building.position.distance_to(player_npc.position) > INTERACT_RADIUS:
		return {"ok": false, "reason": "too_far"}
	var gang_entity := find_territory_gang(world, building_id)
	if gang_entity == null:
		return {"ok": false, "reason": "not_gang_territory"}
	var gang: GangData = gang_entity.get_component(ComponentNames.GANG)
	if gang.cash <= 0:
		return {"ok": false, "reason": "gang_broke"}

	var player_state: PlayerStateData = player_entity.get_component(ComponentNames.PLAYER_STATE)
	var standing: float = player_state.gang_standing.get(gang.id, 0.5)
	var payout: int = mini(gang.cash, maxi(1, int(round(GANG_JOB_BASE_PAYOUT * _gang_job_multiplier(standing)))))

	gang.cash -= payout
	Wallet.earn_dirty(world, payout)  # batch 24
	player_state.gang_standing[gang.id] = standing + (1.0 - standing) * GANG_JOB_STANDING_GAIN
	broadcast_witnesses(world, building.position, SEVERITY_BY_TYPE[GanstoidEnums.CrimeType.GANG_JOB])
	return {"ok": true, "effect": "gang_job", "gang_id": gang.id, "payout": payout}

## Same neutral-at-0.5 shape as DealSystem's _relationship_buy_multiplier --
## exactly 1.0 (base payout) at neutral standing, up to 1.0 +
## GANG_JOB_STANDING_SWING at max standing. Underscore-prefixed like
## DealSystem's multiplier helpers, but still a real static func a
## verification harness can call directly -- GDScript doesn't enforce the
## naming convention as actual privacy.
static func _gang_job_multiplier(standing: float) -> float:
	return 1.0 + GANG_JOB_STANDING_SWING * (standing - 0.5) * 2.0

## Shared by do_gang_job and PlayerInputSystem's target-finding -- which
## gang (if any) claims this building as territory. Linear scan over GANG
## entities, same "fine at this phase's city/gang-count scale" reasoning as
## CopAISystem's guard-bias building scan. Returns the owning gang's Entity
## (not just its id) since both callers want the GangData component anyway.
static func find_territory_gang(world: World, building_id: StringName) -> Entity:
	for entity in world.get_entities_with_component(ComponentNames.GANG).values():
		var gang: GangData = entity.get_component(ComponentNames.GANG)
		if building_id in gang.territory_building_ids:
			return entity
	return null

static func _get_player_entity(world: World) -> Entity:
	var matches := world.get_entities_with_component(ComponentNames.PLAYER_STATE)
	for entity in matches.values():
		return entity
	return null

## Public (not just commit_crime's internal step) so any other player
## action that should be witnessable -- DealSystem's drug deals, which
## aren't a "crime" in the commit_crime sense but still carry the
## DRUG_DEAL_OBSERVED severity -- can reuse the same witness-broadcast
## logic instead of a second copy of it.
##
## Nudges every nearby NPC's recognition_chance (the general "does this
## area remember something happened" layer), then separately rolls actual
## recognition for anyone close enough -- the first NPC whose roll succeeds
## reports it (emits CRIME_WITNESSED once, not once per witness; a mob of
## witnesses shouldn't multiply the heat gain, only make a report more
## likely to happen at all).
##
## Batch 18: reports_player = false is for crimes the PLAYER wasn't at (a
## crew dealer's corner sale). A recognition there still heats the corner
## (crime_heat -> tighter patrols, eventual raids) but never fires
## CRIME_WITNESSED, so it can't raise the player's law tier.
static func broadcast_witnesses(world: World, position: Vector2, severity: float, reports_player: bool = true) -> void:
	var covered := CrewSystem.lookout_covers(world, position)  # batch 17
	for id in world.spatial_index.query_nearby(position):
		var entity: Entity = world.entities.get(id)
		if entity == null or entity.has_component(ComponentNames.PLAYER_STATE):
			continue
		var npc: NPCData = entity.get_component(ComponentNames.NPC)
		if npc == null:
			continue
		if npc.is_crew:
			continue  # batch 15: your own crew don't report you (snitching is its own, rarer path)
		RecognitionSystem.register_witness(npc, severity)
		if npc.position.distance_to(position) <= ENCOUNTER_RADIUS and RecognitionSystem.roll_recognized(npc, world.runtime_rng):
			if covered and world.runtime_rng.randf() < CrewSystem.LOOKOUT_SUPPRESS_CHANCE:
				_lookout_saved_you(world)
				continue  # batch 17: your lookout gave the signal -- this witness didn't clock you
			_bump_crime_heat(world, position)
			if not reports_player:
				return
			world.event_bus.emit(GanstoidEvents.CRIME_WITNESSED, {
				"position": position,
				"severity": severity,
				"tick": world.tick,
				"witness_id": id,
			})
			return

## Batch 10 (locked): the only place BuildingData.crime_heat ever gets
## written -- inside the same witnessed-and-recognized branch that fires
## CRIME_WITNESSED, so "cops patrol high crime places" is built on exactly
## the same evidence gate as every other law consequence, not a second,
## looser trigger. Finds the single nearest building within
## CRIME_HEAT_RADIUS (a crime with no building nearby heats nothing --
## fine, not every street corner needs to be one); linear scan over all
## buildings, same "fine at this phase's scale" reasoning as CopAISystem's
## own building scans.
static func _bump_crime_heat(world: World, position: Vector2) -> void:
	var nearest: BuildingData = null
	var best_dist := CRIME_HEAT_RADIUS
	for entity in world.get_entities_with_component(ComponentNames.BUILDING).values():
		var building: BuildingData = entity.get_component(ComponentNames.BUILDING)
		var d := building.position.distance_to(position)
		if d <= best_dist:
			best_dist = d
			nearest = building
	if nearest != null:
		nearest.crime_heat += (1.0 - nearest.crime_heat) * CRIME_HEAT_GAIN

static func _lookout_saved_you(world: World) -> void:
	var player: Entity = world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if player != null:
		StreetTalk.say_key(world, player.get_component(ComponentNames.PLAYER_STATE), "lookout_saved")
