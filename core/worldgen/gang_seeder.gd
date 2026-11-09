## Phase 2 batch 8 (locked): the minimal gang-entity seed Phase 2's "odd
## jobs for gangs" and Phase 4's whole Beef Ladder track have been blocked
## on since Phase 0 -- GangData's schema existed, nothing ever placed any
## on the board. Deliberately a SEED, not a behavior system: a gang here
## is a name, a cash pile, some turf, and a membership list, with nothing
## yet that gives it jobs, retaliation, or any other logic. That's exactly
## the shape PlayerFactory/PopulationSeeder already take -- data onto the
## board first, behavior layered on once there's something to drive.
##
## Called from PopulationSeeder.seed, before _seed_dealers, so dealers can
## be handed real gang ids to affiliate with (or left solo) as they're
## built, rather than wiring gang membership on as a second pass.
class_name GangSeeder
extends RefCounted

## Fixed count, same "a distinct population, not a fraction of anything
## else" reasoning as PopulationSeeder's COP_COUNT/DEALER_COUNT. Three
## gangs is enough to make "which gang are you dealing with" a real
## question without needing more turf than a 26x26 dev city's handful of
## ILLEGAL_FRONT lots can actually back.
const GANG_COUNT := 3

const GANG_NAMES := ["The Sable Rows", "Pier 9 Outfit", "Carver Street"]

## Registers GANG_COUNT GangData entities (component GANG, keyed by their
## own id) and returns their ids. Each gang claims up to
## TERRITORY_PER_GANG illegal-front lots as territory_building_ids --
## membership (member_npc_ids) is filled in later, by
## PopulationSeeder._seed_dealers, once dealer ids actually exist to add.
## Degrades gracefully (empty territory) if a city seed happens to produce
## fewer illegal fronts than gangs want, rather than crashing.
const TERRITORY_PER_GANG := 2

## Batch 9 (locked): a finite starting cash pool CrimeSystem.do_gang_job
## pays out of -- GangData.cash had been reserved since Phase 0 with
## nothing ever setting it, same "reserve the field, build a minimal
## consumer later" arc as has_been_hit (batch 6) and player_market_
## reputation (batch 7). Deliberately NOT regenerated this batch -- no
## gang-income system exists yet (Phase 3/4 scope) -- so a gang's jobs run
## dry after enough of them and stay dry until that system exists. That's
## an intentional constraint, not an oversight: a gang with more jobs to
## offer is a Phase 3/4 feature, not something to fake here with a regen
## tick that has no real income behind it.
const STARTING_GANG_CASH := 400

static func seed(rng: RandomNumberGenerator, illegal_fronts: Array[StringName], world: World) -> Array[StringName]:
	var gang_ids: Array[StringName] = []
	var available := illegal_fronts.duplicate()
	_shuffle_deterministic(available, rng)  # a manual Fisher-Yates driven by the passed-in rng, NOT Array.shuffle() -- that uses Godot's global RNG and would silently break "same seed -> same city"
	var cursor := 0

	for i in GANG_COUNT:
		var gang := GangData.new()
		gang.id = StringName("gang_%d" % i)
		gang.display_name = GANG_NAMES[i % GANG_NAMES.size()]
		gang.cash = STARTING_GANG_CASH
		for _j in TERRITORY_PER_GANG:
			if cursor >= available.size():
				break
			gang.territory_building_ids.append(available[cursor])
			cursor += 1
		var entity := Entity.new(gang.id)
		entity.add_component(gang)
		world.register_entity(entity)
		gang_ids.append(gang.id)
	return gang_ids

## In-place Fisher-Yates using the SAME seeded rng every other piece of
## worldgen uses, so which lots a given gang claims is reproducible per
## city seed -- Array.shuffle() would use Godot's unseeded global RNG and
## quietly break that guarantee.
static func _shuffle_deterministic(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
