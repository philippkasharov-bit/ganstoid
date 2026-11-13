## E5: casing a place gives rough words (well off / nearly broke, busy /
## struggling / closed, the security, hit lately), never the sums; a block
## reads as its wealth and street market; closures and evictions go into the
## news log, and you hear them as they happen when you are close.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	TestWorlds.real_city(world, 4242)
	var ok := true
	var home := BuildingData.new()
	home.building_type = GanstoidEnums.BuildingType.RESIDENCE
	home.cash_on_hand = 50
	ok = ok and EconomyRead.building(home) == "nearly broke"
	home.bank = 3000
	home.hits = 1.0
	ok = ok and EconomyRead.building(home) == "well off · hit lately"
	var shop := BuildingData.new()
	shop.building_type = GanstoidEnums.BuildingType.LEGIT_BUSINESS
	shop.daily_revenue = 400
	shop.last_sales = 300
	shop.security = 2
	ok = ok and EconomyRead.building(shop) == "busy · guard"
	shop.status = 2
	ok = ok and EconomyRead.building(shop) == "closed down"
	ok = ok and EconomyRead.block({"wealth": 0.2, "black": 0.8}) == "Poor · strong street"
	# A closure close to the player makes the news and is heard.
	var me: NPCData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var st: PlayerStateData = world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)
	var b: BuildingData = null
	for x in BusinessSystem.all_buildings(world):
		if x.building_type == GanstoidEnums.BuildingType.LEGIT_BUSINESS and x.status == 0:
			b = x
			break
	me.position = b.position
	var heard := st.message_serial
	b.bad_days = EconomyFallout.CLOSE_DAYS
	EconomyFallout._health(world, b, [], true)
	var data := BlockEconomyData.of(world)
	ok = ok and b.status == 2 and data.news.size() >= 1 and String(data.news[-1]["text"]).contains("shut down") and st.message_serial > heard
	print("news: %s" % data.news[-1]["text"])
	print("ECONOMY_READ_VERIFY: ", "PASS" if ok else "FAIL")
	quit()
