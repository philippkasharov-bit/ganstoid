## Batch 14: action results map to the right street-voice line, amounts get
## filled in, and results with no voice post nothing.
extends SceneTree

func _initialize() -> void:
	var world := World.new()
	SystemRegistry.register_all(world)
	WorldGenerator.generate_new_game(world, 1, 26, 26, 130)
	var state: PlayerStateData = world.get_entities_with_component(ComponentNames.PLAYER_STATE).values()[0].get_component(ComponentNames.PLAYER_STATE)

	StreetTalk.say(world, state, {"ok": true, "effect": "buy", "cost": 37, "ripped_off": false})
	assert(state.message_serial == 1 and state.last_message in _filled("buy", 37), "clean buy -> buy line with cost")

	StreetTalk.say(world, state, {"ok": true, "effect": "buy", "cost": 37, "ripped_off": true})
	assert(state.last_message in _filled("buy_ripped", 37), "ripped buy -> ripoff line")

	StreetTalk.say(world, state, {"ok": true, "effect": "sell", "proceeds": 12, "ripped_off": true})
	assert(state.last_message in _filled("sell_ripped", 12), "ripped sell -> short-change line")

	StreetTalk.say(world, state, {"ok": true, "effect": "pickpocket", "stolen": 9})
	assert(state.last_message in _filled("pickpocket", 9), "pickpocket line with amount")

	StreetTalk.say(world, state, {"ok": false, "reason": "cant_afford"})
	assert(state.last_message in _filled("cant_afford", 0), "broke line")

	var serial := state.message_serial
	StreetTalk.say(world, state, {"ok": false, "reason": "too_far"})
	StreetTalk.say(world, state, {})
	assert(state.message_serial == serial, "results with no voice post nothing")

	StreetTalk.say_key(world, state, "arrested")
	assert(state.last_message in _filled("arrested", 0), "arrest line")

	for key in StreetTalk.LINES:
		for line in StreetTalk.LINES[key]:
			assert(not String(line).replace("{n}", "1").contains("{"), "every line formats cleanly")

	print("PHASE2_STREET_TALK_VERIFY: PASS")
	quit()

func _filled(key: String, amount: int) -> Array:
	var out := []
	for line in StreetTalk.LINES[key]:
		out.append(String(line).replace("{n}", str(amount)))
	return out
