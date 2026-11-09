## Batch 16: crew cut + loyalty gain, neglect fade, arrest hit, snitching
## only ever with heat, and what a snitch actually does.
extends SceneTree

var _witnessed := 0

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)
	world.event_bus.subscribe(_on_event)
	var player: Entity = world.entities[PlayerFactory.PLAYER_ENTITY_ID]
	var pnpc: NPCData = player.get_component(ComponentNames.NPC)
	var state: PlayerStateData = player.get_component(ComponentNames.PLAYER_STATE)
	for id in world.entities:
		var n: NPCData = world.entities[id].get_component(ComponentNames.NPC)
		if n != null and n.is_cop:
			n.position = Vector2(-100000, -100000)
			world.reindex_position(id)
	var a := _make_crew(world, state, 0)
	var b := _make_crew(world, state, 1)

	# Formula landmarks.
	assert(CrewLoyaltySystem.snitch_chance(1.0) == 0.0, "fully loyal never snitches")
	assert(is_equal_approx(CrewLoyaltySystem.snitch_chance(0.0), CrewLoyaltySystem.SNITCH_RISK_COEFFICIENT), "max risk at zero loyalty")

	# Cut: 10% of a $100 score split two ways, paid from the player's cash.
	pnpc.cash = 1000
	var la := a.loyalty
	var cut := CrewLoyaltySystem.take_cut(world, state, {"ok": true, "effect": "gang_job", "payout": 100})
	assert(cut == 10 and pnpc.cash == 990 and a.cash == 5 and b.cash == 5, "crew split the cut")
	assert(a.loyalty > la, "getting paid raises loyalty")
	assert(CrewLoyaltySystem.take_cut(world, state, {"ok": true, "effect": "buy", "cost": 100}) == 0, "no cut on spending")
	assert(CrewLoyaltySystem.take_cut(world, state, {"ok": false, "reason": "too_far"}) == 0, "no cut on failures")

	# Arrest hit.
	var before := a.loyalty
	CrewLoyaltySystem.on_player_arrested(world, state)
	assert(is_equal_approx(a.loyalty, before * CrewLoyaltySystem.ARREST_LOYALTY_KEEP), "arrest costs loyalty")

	# Neglect + no heat: loyalty fades, nobody snitches even at zero loyalty.
	b.loyalty = 0.0
	before = a.loyalty
	for i in 6000:
		state.law_tier = GanstoidEnums.LawTier.CLEAN
		world.step(1.0 / 60.0)
	assert(a.loyalty < before, "unpaid crew lose loyalty")
	assert(state.crew_ids.size() == 2 and _witnessed == 0, "no heat = no snitching, ever")

	# Snitch effects.
	CrewLoyaltySystem.snitch(world, state, b.id)
	assert(not state.crew_ids.has(b.id) and not b.is_crew and b.recruit_refused, "snitch leaves the crew for good")
	assert(_witnessed == 1, "snitch feeds exactly one CRIME_WITNESSED")
	assert(state.law_tier != GanstoidEnums.LawTier.CLEAN, "and that raises heat through the normal ladder")

	# Statistical: zero-loyalty crew with heat does eventually snitch (rate sanity).
	world.runtime_rng.seed = 99
	var rolls := 0
	var hits := 0
	for i in 200000:
		rolls += 1
		if world.runtime_rng.randf() < CrewLoyaltySystem.snitch_chance(0.5):
			hits += 1
	var per_episode := float(hits) / rolls * 60.0
	print("neutral-loyalty snitch chance per heat episode: %.3f" % per_episode)
	assert(per_episode > 0.005 and per_episode < 0.04, "neutral loyalty: very rare (~2% per heat episode)")

	print("PHASE3_CREW_LOYALTY_VERIFY: PASS")
	quit()

func _on_event(event_name: StringName, _payload: Dictionary) -> void:
	if event_name == GanstoidEvents.CRIME_WITNESSED:
		_witnessed += 1

func _make_crew(world: World, state: PlayerStateData, index: int) -> NPCData:
	var found := 0
	for id in world.entities:
		var e: Entity = world.entities[id]
		var n: NPCData = e.get_component(ComponentNames.NPC)
		if n == null or n.is_cop or n.is_dealer or n.is_crew or e.has_component(ComponentNames.PLAYER_STATE):
			continue
		if found == index:
			n.is_crew = true
			n.cash = 0
			state.crew_ids.append(id)
			return n
		found += 1
	return null
