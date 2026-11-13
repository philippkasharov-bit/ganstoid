## E1: a new game's money, laid out once. Every block gets how rich it is
## (from where it sits in the city, give or take), its public budget, police
## funding and black-market strength. Every worker gets a job at their
## workplace and a day's pay that fits the block. Every home gets savings and
## cash in the drawers from what its people earn; every business a bank
## balance and, on richer blocks, some security. Deterministic from the seed.
class_name EconomySeeder
extends RefCounted

const ZONE_WEALTH := {GanstoidEnums.CityZone.DOWNTOWN: 0.7, GanstoidEnums.CityZone.SPRAWL: 0.45, GanstoidEnums.CityZone.EDGE: 0.25}
const WEALTH_SPREAD := 0.15         # blocks in the same zone differ by up to this
const BUDGET_PER_WEALTH := 3000     # a rich block starts with ~$2,100 of public money, a poor one ~$600
const HOME_CASH_DAYS := Vector2(0.5, 3.0)    # cash kept at home: this many days of the household's pay
const SAVINGS_DAYS := Vector2(5.0, 40.0)     # in the bank, scaled by wealth
const BIZ_BANK_DAYS := Vector2(3.0, 12.0)    # a business's bank: days of takings

static func seed(world: World, seed: int, building_ids: Array[StringName]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var data := BlockEconomyData.new()
	var e := Entity.new(BlockEconomyData.ENTITY_ID)
	e.add_component(data)
	world.register_entity(e)
	_blocks(data, world, building_ids, seed)
	_jobs(world, data, rng)
	_homes(world, data, building_ids, rng)
	_businesses(world, data, building_ids, rng)

## Wealth per block: the average of its buildings' zones, nudged per block.
static func _blocks(data: BlockEconomyData, world: World, building_ids: Array[StringName], seed: int) -> void:
	var sums := {}
	for id in building_ids:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		var c := TerritoryData.cell_of(b.position)
		var s: Vector2 = sums.get(c, Vector2.ZERO)
		sums[c] = s + Vector2(ZONE_WEALTH.get(b.zone, 0.45), 1.0)
	for c in sums:
		var nudge := (float(absi(hash([seed, c])) % 1000) / 999.0 - 0.5) * 2.0 * WEALTH_SPREAD
		var w := clampf(sums[c].x / sums[c].y + nudge, 0.05, 0.95)
		data.blocks[c] = {"wealth": w, "budget": roundi(BUDGET_PER_WEALTH * w), "police": clampf(0.2 + 0.8 * w, 0.0, 1.0), "black": clampf(1.0 - w, 0.0, 1.0)}

static func _wealth(data: BlockEconomyData, p: Vector2) -> float:
	return float(data.blocks.get(TerritoryData.cell_of(p), {"wealth": 0.45})["wealth"])

## Workers get a job title and a day's pay at their workplace.
static func _jobs(world: World, data: BlockEconomyData, rng: RandomNumberGenerator) -> void:
	for ent in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = ent.get_component(ComponentNames.NPC)
		if npc.work_building_id == &"" or not world.entities.has(npc.work_building_id):
			continue
		var work: BuildingData = world.entities[npc.work_building_id].get_component(ComponentNames.BUILDING)
		var job := Jobs.pick(work.business_kind, rng)
		npc.job = job[0]
		npc.wage = Jobs.wage(job[1], _wealth(data, work.position))

## Homes: cash in the drawers and savings, from what the people living there earn.
static func _homes(world: World, data: BlockEconomyData, building_ids: Array[StringName], rng: RandomNumberGenerator) -> void:
	var pay := {}
	for ent in world.get_entities_with_component(ComponentNames.NPC).values():
		var npc: NPCData = ent.get_component(ComponentNames.NPC)
		if npc.home_building_id != &"":
			pay[npc.home_building_id] = int(pay.get(npc.home_building_id, 0)) + npc.wage
	for id in building_ids:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b.building_type != GanstoidEnums.BuildingType.RESIDENCE:
			continue
		var day := int(pay.get(id, 0))
		var w := _wealth(data, b.position)
		b.cash_on_hand = roundi(day * rng.randf_range(HOME_CASH_DAYS.x, HOME_CASH_DAYS.y))
		b.bank = roundi(day * rng.randf_range(SAVINGS_DAYS.x, SAVINGS_DAYS.y) * w)

## Businesses: a bank balance from their takings, and security on richer blocks.
static func _businesses(world: World, data: BlockEconomyData, building_ids: Array[StringName], rng: RandomNumberGenerator) -> void:
	for id in building_ids:
		var b: BuildingData = world.entities[id].get_component(ComponentNames.BUILDING)
		if b.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			continue
		var w := _wealth(data, b.position)
		b.bank = roundi(b.daily_revenue * rng.randf_range(BIZ_BANK_DAYS.x, BIZ_BANK_DAYS.y))
		b.security = clampi(int(w * 3.0 + rng.randf_range(-0.5, 0.5)), 0, 2)
