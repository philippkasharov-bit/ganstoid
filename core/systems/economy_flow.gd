## E2: the city's daily money loop. Once a game day, in this order:
##   1. Households pay rent (to landlords outside the district: it leaves) and
##      spend on food and goods at the open shops near home (it goes into
##      their tills), from wallets, then the cash at home, then savings.
##   2. Each open business also sells to people from outside (the one steady
##      inflow, a fixed share of its trade).
##   3. Businesses pay their staff from the till, then the bank; short of
##      money, they pay part. Pay tops up the worker's wallet; the rest goes
##      home to the household's cash (a homeless worker keeps it all).
##   4. Businesses pay restock and rent (it leaves) and tax on the day's sales
##      to their block's budget; the till is banked down to a small float.
##   5. Households move spare cash to savings, or take some back out.
##   6. Each block's budget pays its police; their funding follows the budget.
## Workers pay income tax and shops pay sales tax to their block's budget.
## Money only moves between these accounts, comes in from outside sales, or
## leaves as rent, restock and police pay. Nothing is created from nothing:
## `last_day` records what came in and went out so a check can prove it.
class_name EconomyFlow
extends RefCounted

const SPEND_PER_PERSON := Vector2(16.0, 40.0)   # a day's food and goods, poor .. rich block
const RENT_PER_HOME := Vector2(12.0, 45.0)      # a day's rent, poor .. rich
const OUTSIDE_SHARE := 0.3      # of a business's trade (daily_revenue as seeded) bought by outsiders each day
const RESTOCK_SHARE := 0.35     # of the day's sales, paid to suppliers outside
const BIZ_RENT_SHARE := 0.08    # of its trade, a business's rent and bills
const TAX_RATE := 0.08          # of the day's sales, to the block budget
const TILL_FLOAT := 60          # what stays in the till overnight; the rest is banked
const POCKET := 150             # pay tops a wallet up to this; the rest goes home
const HOME_KEEP_DAYS := 3.0     # households keep this many days of spending at home
const INCOME_TAX := 0.06        # of each pay packet, to the block the worker lives on
const POLICE_SHARE := 0.1       # of its budget a block pays its police each day
const POLICE_FULL := 400        # a budget this big funds its police fully
const NEAR_SHOPS := 4
const SHOP_REACH_M := 450.0

static var _cache_for := 0
static var _homes: Dictionary = {}       # home id -> Array[NPCData] living there
static var _staff: Dictionary = {}       # business id -> Array[NPCData] working there
static var _near: Dictionary = {}        # home id -> Array[BuildingData] shops near it

## Runs one day. Returns the day's ledger {inflow, outflow, sales, wages, tax}.
static func run_day(world: World) -> Dictionary:
	_index(world)
	var data := BlockEconomyData.of(world)
	var led := {"inflow": 0, "outflow": 0, "sales": 0, "wages": 0, "tax": 0}
	var sold := {}   # business id -> today's sales
	_households_spend(world, data, led, sold)
	_outside_buyers(world, led, sold)
	_payday(world, data, led)
	_business_costs(world, data, led, sold)
	_household_savings(world, data)
	_police(data, led)
	if data != null:
		data.last_day = led
	return led

## Every dollar in the district outside the player's hands.
static func total_money(world: World) -> int:
	var total := 0
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		if not e.has_component(ComponentNames.PLAYER_STATE):
			total += e.get_component(ComponentNames.NPC).cash
	for b in BusinessSystem.all_buildings(world):
		total += b.cash_on_hand + b.bank
	var data := BlockEconomyData.of(world)
	if data != null:
		for c in data.blocks:
			total += int(data.blocks[c]["budget"])
	return total

static func _wealth(data: BlockEconomyData, p: Vector2) -> float:
	return float(data.blocks.get(TerritoryData.cell_of(p), {"wealth": 0.45})["wealth"]) if data != null else 0.45

static func _open_shop(b: BuildingData) -> bool:
	return b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and b.status < 2

## Who lives where, who works where, which shops are near each home (kept).
static func _index(world: World) -> void:
	var stamp := world.get_instance_id() * 100003 + world.entities.size()
	if stamp == _cache_for:
		return
	_cache_for = stamp
	_homes.clear()
	_staff.clear()
	_near.clear()
	for e in world.get_entities_with_component(ComponentNames.NPC).values():
		if e.has_component(ComponentNames.PLAYER_STATE):
			continue
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n.home_building_id != &"" and not n.is_cop:
			if not _homes.has(n.home_building_id):
				_homes[n.home_building_id] = []
			_homes[n.home_building_id].append(n)
		if n.work_building_id != &"" and n.wage > 0:
			if not _staff.has(n.work_building_id):
				_staff[n.work_building_id] = []
			_staff[n.work_building_id].append(n)
	var shops: Array = BusinessSystem.all_buildings(world).filter(func(b: BuildingData) -> bool: return b.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS)
	for home_id in _homes:
		var at: Vector2 = world.entities[home_id].get_component(ComponentNames.BUILDING).position
		var near: Array = shops.filter(func(b: BuildingData) -> bool: return b.position.distance_squared_to(at) <= SHOP_REACH_M * SHOP_REACH_M)
		near.sort_custom(func(a: BuildingData, b: BuildingData) -> bool: return a.position.distance_squared_to(at) < b.position.distance_squared_to(at))
		_near[home_id] = near.slice(0, NEAR_SHOPS)

## Takes up to `amount` from the people, then the home's cash, then savings. Returns what was paid.
static func _pay_from_home(home: BuildingData, people: Array, amount: int) -> int:
	var left := amount
	for n in people:
		var take := mini(left, n.cash)
		n.cash -= take
		left -= take
	var cash := mini(left, home.cash_on_hand)
	home.cash_on_hand -= cash
	left -= cash
	var saved := mini(left, home.bank)
	home.bank -= saved
	left -= saved
	return amount - left

static func _households_spend(world: World, data: BlockEconomyData, led: Dictionary, sold: Dictionary) -> void:
	for home_id in _homes:
		var home: BuildingData = world.entities[home_id].get_component(ComponentNames.BUILDING)
		var people: Array = _homes[home_id]
		var w := _wealth(data, home.position)
		led["outflow"] += _pay_from_home(home, people, roundi(lerpf(RENT_PER_HOME.x, RENT_PER_HOME.y, w)))
		var spent := _pay_from_home(home, people, roundi(lerpf(SPEND_PER_PERSON.x, SPEND_PER_PERSON.y, w) * people.size()))
		var open: Array = _near.get(home_id, []).filter(_open_shop)
		if open.is_empty():
			led["outflow"] += spent   # nowhere to shop nearby: spent outside the district
			continue
		var each := spent / open.size()
		for i in open.size():
			var b: BuildingData = open[i]
			var part := each + (spent - each * open.size() if i == 0 else 0)
			b.cash_on_hand += part
			sold[b.id] = int(sold.get(b.id, 0)) + part

static func _outside_buyers(world: World, led: Dictionary, sold: Dictionary) -> void:
	for b in BusinessSystem.all_buildings(world):
		if _open_shop(b):
			var amount := roundi(b.daily_revenue * OUTSIDE_SHARE)
			b.cash_on_hand += amount
			sold[b.id] = int(sold.get(b.id, 0)) + amount
			led["inflow"] += amount

## Takes up to `amount` from the till, then the bank. Returns what was paid.
static func _pay_from_business(b: BuildingData, amount: int) -> int:
	var till := mini(amount, b.cash_on_hand)
	b.cash_on_hand -= till
	var bank := mini(amount - till, b.bank)
	b.bank -= bank
	return till + bank

## Income tax goes to the block the worker lives on (or, homeless, where they sleep).
static func _to_budget(data: BlockEconomyData, world: World, n: NPCData, tax: int, led: Dictionary) -> void:
	var at: Vector2 = world.entities[n.home_building_id].get_component(ComponentNames.BUILDING).position if world.entities.has(n.home_building_id) else n.camp
	var c := TerritoryData.cell_of(at)
	led["tax"] += tax
	if data != null and data.blocks.has(c):
		data.blocks[c]["budget"] = int(data.blocks[c]["budget"]) + tax
	else:
		led["outflow"] += tax

static func _payday(world: World, data: BlockEconomyData, led: Dictionary) -> void:
	for biz_id in _staff:
		var b: BuildingData = world.entities[biz_id].get_component(ComponentNames.BUILDING)
		if not _open_shop(b):
			continue
		for n in _staff[biz_id]:
			var pay := _pay_from_business(b, n.wage)
			led["wages"] += pay
			var tax := roundi(pay * INCOME_TAX)
			pay -= tax
			_to_budget(data, world, n, tax, led)
			var to_pocket := clampi(POCKET - n.cash, 0, pay)
			n.cash += to_pocket
			var rest := pay - to_pocket
			if rest > 0 and world.entities.has(n.home_building_id):
				world.entities[n.home_building_id].get_component(ComponentNames.BUILDING).cash_on_hand += rest
			else:
				n.cash += rest

static func _business_costs(world: World, data: BlockEconomyData, led: Dictionary, sold: Dictionary) -> void:
	for b in BusinessSystem.all_buildings(world):
		if not _open_shop(b):
			continue
		var sales := int(sold.get(b.id, 0))
		led["sales"] += sales
		led["outflow"] += _pay_from_business(b, roundi(sales * RESTOCK_SHARE) + roundi(b.daily_revenue * BIZ_RENT_SHARE))
		var tax := _pay_from_business(b, roundi(sales * TAX_RATE))
		led["tax"] += tax
		if data != null and data.blocks.has(TerritoryData.cell_of(b.position)):
			data.blocks[TerritoryData.cell_of(b.position)]["budget"] += tax
		else:
			led["outflow"] += tax
		if b.cash_on_hand > TILL_FLOAT:   # banked overnight: a robbery takes the float and today's takings, not the savings
			b.bank += b.cash_on_hand - TILL_FLOAT
			b.cash_on_hand = TILL_FLOAT
		b.last_sales = sales

static func _household_savings(world: World, data: BlockEconomyData) -> void:
	for home_id in _homes:
		var home: BuildingData = world.entities[home_id].get_component(ComponentNames.BUILDING)
		var keep := roundi(lerpf(SPEND_PER_PERSON.x, SPEND_PER_PERSON.y, _wealth(data, home.position)) * _homes[home_id].size() * HOME_KEEP_DAYS)
		if home.cash_on_hand > keep:
			home.bank += home.cash_on_hand - keep
			home.cash_on_hand = keep
		elif home.cash_on_hand < keep / 3:
			var take := mini(keep / 3 - home.cash_on_hand, home.bank)
			home.bank -= take
			home.cash_on_hand += take

static func _police(data: BlockEconomyData, led: Dictionary) -> void:
	if data == null:
		return
	for c in data.blocks:
		var bl: Dictionary = data.blocks[c]
		var pay := roundi(int(bl["budget"]) * POLICE_SHARE)
		bl["budget"] = int(bl["budget"]) - pay
		led["outflow"] += pay
		bl["police"] = clampf(float(bl["budget"]) / POLICE_FULL, 0.05, 1.0)
