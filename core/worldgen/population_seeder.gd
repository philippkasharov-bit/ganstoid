## Seeds initial NPC population onto an already-generated city (CityRoles
## must run first — this reads building_ids it produced). Kept separate from
## city layout so population density/employment can be retuned independently.
##
## Phase 2 batch 8 (locked): also calls GangSeeder (after cops, before
## dealers) so dealers can be handed real gang ids to affiliate with -- see
## GangSeeder's own doc comment for why gang entities are seeded here at
## all, and _seed_dealers' doc comment for how affiliation is assigned.
class_name PopulationSeeder
extends RefCounted

const JOB_OPENINGS_SEEN := 8   # openings a job-seeker compares; they take the nearest
const EMPLOYMENT_RATE := 0.7  # fraction of NPCs assigned a work_building_id
const UNEMPLOYED_STARTING_CASH := Vector2i(0, 50)
const EMPLOYED_CASH_MULTIPLIER := 3  # (unused since TUNE1; kept for old saves' readers)
const EMPLOYED_POCKET := Vector2i(20, 140)   # TUNE1: what a worker carries

## Fixed count, added ON TOP of population_count (not a fraction of it) --
## cops are a distinct population, not a civilian subtype, so tying their
## count to the civilian count would couple two things with no real
## relationship. CopAISystem drives them; NPCScheduleSystem skips them.
const COP_COUNT := 6

## Fixed count, same "on top of population_count, not a fraction of it"
## reasoning as COP_COUNT -- a dealer is a distinct, deliberately placed
## population, not a civilian subtype.
const DEALER_COUNT := 4

static func seed(world: World, seed: int, population_count: int, building_ids: Array[StringName]) -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var residences := _filter_by_type(world, building_ids, GanstoidEnums.BuildingType.RESIDENCE)
	var workplaces := _filter_by_type(world, building_ids, GanstoidEnums.BuildingType.LEGIT_BUSINESS)
	var illegal_fronts := _filter_by_type(world, building_ids, GanstoidEnums.BuildingType.ILLEGAL_FRONT)
	assert(not residences.is_empty(), "PopulationSeeder requires at least one RESIDENCE building")

	var npc_ids: Array[StringName] = []
	for i in population_count:
		var npc := _build_npc(rng, i, residences, workplaces, world)
		var entity := Entity.new(npc.id)
		entity.add_component(npc)
		world.register_entity(entity)
		npc_ids.append(npc.id)
	_seed_cops(rng, residences, world, npc_ids)
	var gang_ids := GangSeeder.seed(rng, illegal_fronts, world)
	_seed_dealers(rng, illegal_fronts, residences, gang_ids, world, npc_ids)
	return npc_ids

## Cops patrol out from a "depot" (just a residence lot, standing in for a
## precinct until Phase 4 adds real municipal buildings) rather than having
## a home/work routine of their own -- CopAISystem wanders them from there
## and responds to crime_witnessed, it doesn't commute them anywhere.
static func _seed_cops(rng: RandomNumberGenerator, residences: Array[StringName], world: World, npc_ids: Array[StringName]) -> void:
	for i in COP_COUNT:
		var npc := NPCData.new()
		npc.id = StringName("cop_%d" % i)
		npc.display_name = "Officer %d" % i
		npc.is_cop = true
		npc.home_building_id = residences[rng.randi() % residences.size()]
		var depot: BuildingData = world.entities[npc.home_building_id].get_component(ComponentNames.BUILDING)
		npc.position = depot.position
		var entity := Entity.new(npc.id)
		entity.add_component(npc)
		world.register_entity(entity)
		npc_ids.append(npc.id)

## Dealers run the SAME work/home two-state cycle NPCScheduleSystem already
## gives every civilian -- deliberately not a special case. "work" is an
## ILLEGAL_FRONT lot (where the zone weight tables already concentrate that
## building type -- EDGE zone mostly): out on the street, visible, and
## easy to find, same as any other crowd a crime gets witnessed in. "home"
## is an ordinary residence: off the street during the home fraction of the
## cycle, so a buyer has to come find them there instead -- fewer
## bystanders around a residence at that hour, but also a longer walk and
## no guarantee which dealer is even awake. Two legitimate strategies fall
## out of that for free (no separate "risk" stat needed): deal in public
## during work hours for convenience at the cost of more potential
## witnesses, or track a dealer down at home for a quieter buy. Falls back
## to a residence for "work" too if a city seed happens to produce zero
## illegal fronts (possible but unlikely at this phase's city size).
## Phase 2 batch 8 (locked): each dealer is handed either a gang affiliation
## or left a "solo," round-robin across gang_ids.size() + 1 slots (the "+1"
## being "no gang") so every seed deterministically produces at least one
## of each case to deal with, rather than leaving solos a rare accident of
## randomness. Affiliated dealers get appended to their gang's
## member_npc_ids -- DealSystem's relationship pricing reads gang_id off
## the NPC at trade time, member_npc_ids is for any future system (odd
## jobs, Phase 4's gang logic) that needs to go the other way, from gang to
## its people.
static func _seed_dealers(rng: RandomNumberGenerator, illegal_fronts: Array[StringName], residences: Array[StringName], gang_ids: Array[StringName], world: World, npc_ids: Array[StringName]) -> void:
	var work_spots := illegal_fronts if not illegal_fronts.is_empty() else residences
	var slots := gang_ids.size() + 1
	for i in DEALER_COUNT:
		var npc := NPCData.new()
		npc.id = StringName("dealer_%d" % i)
		npc.display_name = "Dealer %d" % i
		npc.is_dealer = true
		npc.home_building_id = residences[rng.randi() % residences.size()]
		npc.work_building_id = work_spots[rng.randi() % work_spots.size()]
		var home: BuildingData = world.entities[npc.home_building_id].get_component(ComponentNames.BUILDING)
		npc.position = home.position  # NPCScheduleSystem walks them to "work" once the sim starts ticking

		var slot := i % slots
		if slot < gang_ids.size():
			npc.gang_id = gang_ids[slot]
			var gang: GangData = world.entities[npc.gang_id].get_component(ComponentNames.GANG)
			gang.member_npc_ids.append(npc.id)
		# else: slot == gang_ids.size() -> stays solo (gang_id left at its &"" default)

		var entity := Entity.new(npc.id)
		entity.add_component(npc)
		world.register_entity(entity)
		npc_ids.append(npc.id)

static func _build_npc(
	rng: RandomNumberGenerator,
	index: int,
	residences: Array[StringName],
	workplaces: Array[StringName],
	world: World
) -> NPCData:
	var npc := NPCData.new()
	npc.id = StringName("npc_%d" % index)
	npc.display_name = civilian_name(index)
	npc.home_building_id = residences[rng.randi() % residences.size()]
	# Start at home. Was missing since Phase 0 -- every civilian spawned at the
	# world origin (0,0) and the whole population marched out of the map's
	# corner in one wave. Dealers/cops already did this; civilians didn't.
	npc.position = world.entities[npc.home_building_id].get_component(ComponentNames.BUILDING).position

	var is_employed := not workplaces.is_empty() and rng.randf() < EMPLOYMENT_RATE
	if is_employed:
		npc.work_building_id = _job_near(rng, npc.position, workplaces, world)
		var workplace: BuildingData = world.entities[npc.work_building_id].get_component(ComponentNames.BUILDING)
		npc.cash = rng.randi_range(EMPLOYED_POCKET.x, EMPLOYED_POCKET.y)   # TUNE: a wallet, not three days of the shop's takings
	else:
		npc.cash = rng.randi_range(UNEMPLOYED_STARTING_CASH.x, UNEMPLOYED_STARTING_CASH.y)

	return npc

## People on foot work near home: the closest of a handful of openings, not a
## random building across the district (which made every commute a long march).
static func _job_near(rng: RandomNumberGenerator, home: Vector2, workplaces: Array[StringName], world: World) -> StringName:
	var best: StringName = workplaces[rng.randi() % workplaces.size()]
	var best_d := INF
	for i in JOB_OPENINGS_SEEN:
		var id: StringName = workplaces[rng.randi() % workplaces.size()]
		var d: float = world.entities[id].get_component(ComponentNames.BUILDING).position.distance_squared_to(home)
		if d < best_d:
			best_d = d
			best = id
	return best

static func _filter_by_type(
	world: World, building_ids: Array[StringName], target_type: GanstoidEnums.BuildingType
) -> Array[StringName]:
	var matches: Array[StringName] = []
	for id in building_ids:
		var building: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if building.building_type == target_type:
			matches.append(id)
	return matches

## Batch 22: street names for civilians so the crew roster can show who's
## who. Derived from the index alone (no rng draw), so adding names doesn't
## shift the seeded worldgen sequence -- same seed, same city as before.
const FIRST_NAMES := ["Marcus", "Dre", "Tasha", "Lil Rico", "Nina", "Jay", "Keisha", "Tony", "Darnell", "Lexi", "Big Mike", "Vic", "Shay", "Rome", "Cee", "Manny", "Tre", "Jojo", "Kev", "Yolanda"]
const LAST_NAMES := ["Banks", "Rivers", "Cole", "Ortiz", "Grant", "Mason", "Price", "Reyes", "Hayes", "Stone", "Wells", "Cruz", "Bishop", "Vega"]

static func civilian_name(index: int) -> String:
	return "%s %s" % [FIRST_NAMES[index % FIRST_NAMES.size()], LAST_NAMES[(index / FIRST_NAMES.size()) % LAST_NAMES.size()]]
