## E4: what crime and hard times do to a block, once a game day after the
## money has moved (EconomyFlow). A shop that keeps getting hit buys security
## (a camera, then a guard, then an armed guard), which leaves less in reach
## of a robber. A shop that cannot cover its wages or keep a day's trade in
## the bank goes downhill: after a few bad days it lets its best paid worker
## go, after a week it shuts. Its workers lose their pay; a household with
## no work that falls behind on rent is put out on the street. Each block's
## wealth drifts with how many of its shops are open and its people in work;
## the street market grows where both the money and the police are thin. A
## shop doing well hires someone out of work nearby.
class_name EconomyFallout
extends RefCounted

const HIT_DECAY := 0.75              # recent robberies fade by this each day
const BUY_SECURITY_AT := 1.5         # this many recent hits and they invest
const SECURITY_COST := [150, 400, 900]
const ROB_KEEP := [1.0, 0.75, 0.5, 0.3]   # share of the till a robber can get, by security
const MIN_RESERVE := 100          # a shop with less than this in the bank is on the edge
const STRUGGLE_DAYS := 3
const CLOSE_DAYS := 7
const EVICT_DAYS := 3
const HIRE_BANK_DAYS := 10           # money in the bank, in wage days, before they take someone on
const STAFF_CAP := 4
const HIRE_REACH_M := 600.0
const WEALTH_DRIFT := 0.05

## One day of consequences. `underpaid`: business ids that could not pay all wages;
## `behind`: home ids that could not pay all their rent.
static func day(world: World, data: BlockEconomyData, led: Dictionary, staff: Dictionary, homes: Dictionary, underpaid: Dictionary, behind: Dictionary) -> void:
	var changed := false
	for b in BusinessSystem.all_buildings(world):
		if b.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS or b.status >= 2:
			continue
		b.hits *= HIT_DECAY
		_security(b, led)
		changed = _health(world, b, staff.get(b.id, []), underpaid.has(b.id)) or changed
	changed = _evictions(world, homes, behind) or changed
	changed = _hiring(world, data, staff) or changed
	_blocks(world, data, homes)
	if changed:
		EconomyFlow.reindex()

## Robbed again and again: they spend money on keeping the next one out.
static func _security(b: BuildingData, led: Dictionary) -> void:
	if b.hits < BUY_SECURITY_AT or b.security >= SECURITY_COST.size():
		return
	var cost: int = SECURITY_COST[b.security]
	if b.bank >= cost * 2:
		b.bank -= cost
		led["outflow"] += cost   # the guard company and the camera shop are outside the district
		b.security += 1
		b.hits = 0.0

## Bad days pile up: cut staff, then close. Good days pull it back.
static func _health(world: World, b: BuildingData, people: Array, short: bool) -> bool:
	var strained := short or b.bank < maxi(b.daily_revenue, MIN_RESERVE) or b.last_sales <= 0   # short of wages, no cushion, or no customers
	b.bad_days = b.bad_days + 1 if strained else maxi(0, b.bad_days - 1)
	if b.bad_days >= CLOSE_DAYS:
		b.status = 2
		for n in people:
			_lay_off(n)
		return not people.is_empty()
	if b.bad_days >= STRUGGLE_DAYS and b.status == 0:
		b.status = 1
		var best: NPCData = null
		for n in people:
			if best == null or n.wage > best.wage:
				best = n
		if best != null:
			_lay_off(best)
			return true
	elif b.bad_days == 0 and b.status == 1:
		b.status = 0
	return false

static func _lay_off(n: NPCData) -> void:
	n.work_building_id = &""
	n.job = &""
	n.wage = 0

## No work, behind on rent for days: put out on the street, camping near the old door.
static func _evictions(world: World, homes: Dictionary, behind: Dictionary) -> bool:
	var any := false
	for home_id in homes:
		var home: BuildingData = world.entities[home_id].get_component(ComponentNames.BUILDING)
		home.bad_days = home.bad_days + 1 if behind.has(home_id) else 0
		if home.bad_days < EVICT_DAYS:
			continue
		var people: Array = homes[home_id]
		if people.any(func(n: NPCData) -> bool: return n.wage > 0):
			continue   # someone still earns: they scrape by
		for i in people.size():
			var n: NPCData = people[i]
			n.home_building_id = &""
			n.camp = home.position + Vector2.from_angle(float(hash(n.id) % 628) / 100.0) * 8.0
			n.position = n.camp
			n.indoors = false
			world.reindex_position(n.id)
		home.bad_days = 0
		any = true
	return any

## A shop with money to spare takes on someone out of work who lives nearby.
static func _hiring(world: World, data: BlockEconomyData, staff: Dictionary) -> bool:
	var jobless: Array = []
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.work_building_id == &"" and not (n.is_cop or n.is_dealer or n.is_fixer or n.is_crew or n.gang_id != &"" or e.has_component(ComponentNames.PLAYER_STATE)):
			jobless.append(n)
	var any := false
	for b in BusinessSystem.all_buildings(world):
		if b.building_type != GanstoidEnums.BuildingType.LEGIT_BUSINESS or b.status != 0 or b.bad_days > 0:
			continue
		var people: Array = staff.get(b.id, [])
		if people.size() >= STAFF_CAP or b.bank < Jobs.wage(90, 0.5) * HIRE_BANK_DAYS:
			continue
		for n in jobless:
			if n.position.distance_squared_to(b.position) <= HIRE_REACH_M * HIRE_REACH_M:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([n.id, b.id])
				var job := Jobs.pick(b.trade, rng)
				n.work_building_id = b.id
				n.job = job[0]
				n.wage = Jobs.wage(job[1], BlockEconomyData.block_at(world, b.position)["wealth"])
				jobless.erase(n)
				any = true
				break
	return any

## Blocks follow their people: open shops and jobs lift a block's wealth back
## toward what it was; closures and joblessness drag it down. The street
## market is strongest where money and police are both thin.
static func _blocks(world: World, data: BlockEconomyData, homes: Dictionary) -> void:
	if data == null:
		return
	var shops := {}   # cell -> [open, all]
	for b in BusinessSystem.all_buildings(world):
		if b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS:
			var c := TerritoryData.cell_of(b.position)
			var v: Vector2i = shops.get(c, Vector2i.ZERO)
			shops[c] = v + Vector2i(int(b.status == 0), 1)
	var work := {}    # cell -> [employed, people]
	for home_id in homes:
		var c := TerritoryData.cell_of(world.entities[home_id].get_component(ComponentNames.BUILDING).position)
		var v: Vector2i = work.get(c, Vector2i.ZERO)
		for n in homes[home_id]:
			v += Vector2i(int(n.wage > 0), 1)
		work[c] = v
	for c in data.blocks:
		var bl: Dictionary = data.blocks[c]
		if not bl.has("base"):
			bl["base"] = bl["wealth"]
		var s: Vector2i = shops.get(c, Vector2i(1, 1))
		var w: Vector2i = work.get(c, Vector2i(1, 1))
		var target := float(bl["base"]) * (0.5 + 0.5 * float(s.x) / maxi(1, s.y)) * (0.6 + 0.4 * float(w.x) / maxi(1, w.y) / 0.7)
		bl["wealth"] = clampf(float(bl["wealth"]) + (clampf(target, 0.02, 0.98) - float(bl["wealth"])) * WEALTH_DRIFT, 0.02, 0.98)
		bl["black"] = clampf(1.0 - 0.6 * float(bl["wealth"]) - 0.4 * float(bl["police"]), 0.0, 1.0)
