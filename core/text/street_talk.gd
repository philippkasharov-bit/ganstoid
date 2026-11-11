## Phase 2 batch 14: turns an action's result Dictionary into one line of
## street voice for the HUD. Pure presentation -- reads results, never
## changes game state beyond PlayerStateData's two message fields. Lines are
## picked with World.runtime_rng so repeats vary. Add a new action's voice
## by adding its key to LINES and a case to _key_for.
class_name StreetTalk
extends RefCounted

const LINES := {
	"used_food": ["That hit the spot.", "Better. Stomach's quiet."],
	"used_drink": ["Cold. Good.", "Throat's not dry anymore."],
	"used_medical": ["Wrapped tight. Bleeding stopped.", "Patched up. It'll hold."],
	"dont_have": ["You don't have that."],
	"cant_use": ["Can't use that here."],
	"not_tired": ["Not tired. Can't sleep now."],
	"sleep_home": ["Your own bed. Lights out.", "Home. Sleep."],
	"sleep_rough": ["Sleeping rough. Keep one eye open.", "Lying down where you are. Risky."],
	"woke": ["Up. Back to it.", "Awake."],
	"witness_running": ["Somebody saw that. They're running for a phone.", "A witness is booking it. Phone in hand soon.", "Eyes on you. They're calling it in."],
	"bought": ["Paid ${n}.", "${n}, bagged.", "Done. ${n} lighter."],
	"closed": ["Shutters down. Opens at seven.", "Closed for the night."],
	"not_sold_here": ["They don't carry that here."],
	"no_counter": ["Nobody selling anything here."],
	"no_ammo": ["Click. Empty.", "Out of rounds.", "Nothing left in the clip."],
	"weapon_fists": ["Hands up. Old school.", "Fists it is."],
	"weapon_knife": ["Blade out.", "Knife in hand."],
	"weapon_bat": ["Batter up.", "Bat on the shoulder."],
	"weapon_pistol": ["Strapped.", "Pistol out. Careful now."],
	"handoff_started": ["Aight, hold up... lemme see the paper.", "Keep it low. Hand it over slow.", "Eyes open. We doin' this quick."],
	"buy": ["Good lookin'. That's ${n}.", "Pleasure doin' business. ${n}, we square.", "Fresh pack for ${n}. Don't say I never looked out."],
	"buy_ripped": ["Bag's empty. He took ${n} and dipped.", "You just got finessed. ${n} gone, no pack.", "That's air in the bag. ${n} down the drain."],
	"sell": ["${n} in pocket. Pleasure.", "Clean flip, ${n}.", "He took it, no questions. ${n}."],
	"sell_ripped": ["He short-changed you. Only ${n}.", "Half price? He played you. ${n}.", "${n}?? That's disrespect."],
	"pickpocket": ["Lifted ${n}. Smooth.", "Five-finger discount: ${n}.", "Light fingers. ${n} richer."],
	"robbery": ["Register cleaned out, ${n}. Move!", "${n} bagged. Don't run, walk.", "Took ${n}. Get ghost."],
	"gang_job": ["Job's done. The set paid ${n}.", "Handled. ${n} for your trouble.", "Word gets around. ${n} earned."],
	"cant_afford": ["You broke, fam. Come back with paper.", "No money, no product."],
	"nothing_to_sell": ["You holdin' nothin'. Stop wastin' my time."],
	"nothing_to_take": ["Register's empty. Somebody beat you to it."],
	"gang_broke": ["Set's dry right now. No work today."],
	"recruit": ["You rollin' with me now. ${n} up front.", "Welcome to the crew. Here's ${n}, don't spend it dumb.", "${n} says you're family now."],
	"recruit_refused": ["Nah, I'm good. Not my life.", "You crazy? Get outta my face.", "I got a kid at home. Find somebody else."],
	"already_refused": ["I already told you no."],
	"crew_full": ["Crew's deep enough. Can't feed more mouths."],
	"snitched": ["Word is somebody in your crew been talkin' to five-oh.", "One of yours flipped. Cops know where you at.", "Snitch in the crew. He's gone, and so's your cover."],
	"posted": ["I got eyes on the block.", "Corner's covered. I'll holler if five-oh roll up.", "Go handle yours, I'm watchin'."],
	"recalled": ["Aight, I'm rollin' with you.", "Leavin' the corner. Right behind you."],
	"lookout_saved": ["Your lookout whistled. Somebody looked away just in time.", "Lookout gave the signal. They didn't clock you.", "Eyes on the corner paid off. Nobody made you."],
	"dealer_posted": ["Gimme the pack. I'll move it.", "Corner's mine. Come back later for your paper.", "I got this. Go do you."],
	"dealer_collected": ["Here's your cut of the corner: ${n}.", "Moved what I could. ${n} for you.", "${n}, all there. Count it."],
	"muscle_posted": ["Shops round here 'bout to start payin' rent.", "I'll go have a word with the neighbors.", "Protection ain't free. I'll explain it to 'em."],
	"muscle_collected": ["Block paid up: ${n}.", "${n} in protection. Nobody argued.", "Neighbors been generous. ${n}."],
	"crew_busy": ["He's already on a job. Pull him off first."],
	"driver_assigned": ["Hop in. I know every back road.", "Keys in hand. Where we goin'?", "I drive, you handle business."],
	"driver_dismissed": ["Aight, I'll park it.", "Walkin' again? Your call."],
	"crew_busted": ["Five-oh scooped up one of yours. Whatever he was holdin' is gone.", "Corner got too hot. Your boy's in cuffs.", "They raided the spot. One of your crew got took."],
	"business_bought": ["Keys are yours. ${n} well spent.", "Signed, sealed. You own the place now. ${n}.", "Legit businessman now. Cost you ${n}."],
	"business_paid": ["Your shops cashed out: ${n}.", "Clean money in: ${n}.", "Day's take from the businesses: ${n}."],
	"already_yours": ["You already own this spot."],
	"not_for_sale": ["This place ain't for sale."],
	"cant_afford_business": ["You need more paper to buy this place."],
	"need_clean_cash": ["Can't buy legit with dirty paper. Wash it first.", "Seller wants clean money. Yours ain't."],
	"laundered": ["Your fronts washed ${n} clean today.", "${n} came out the wash clean.", "Books balanced. ${n} cleaned up."],
	"arrested_seized": ["Cuffed. They took ${n} in dirty money off you.", "Booked. ${n} of your dirty paper is evidence now.", "Five-oh seized ${n}. Should've washed it."],
	"grow_house_bought": ["Lights, soil, fans. Grow house is yours. ${n}.", "Spot's set up. ${n} well spent.", "Your own supply now. Cost you ${n}."],
	"harvest_collected": ["Harvest's in: {n} packs.", "Picked up {n} packs from the grow.", "{n} fresh packs, straight from your own spot."],
	"nothing_grown": ["Nothin' ready yet. Come back tomorrow."],
	"grow_house_raided": ["Cops hit your grow house. {n} packs gone.", "Raid on the grow. Lost {n} packs.", "Five-oh tore up the spot. {n} packs seized."],
	"arrested": ["Cuffed. Back on the block with nothin'.", "Five-oh got you. Heat's off, so's the deal.", "Booked and kicked loose. Watch your back."],
}

## Posts the line for an action result, if that result has a voice.
static func say(world: World, player_state: PlayerStateData, result: Dictionary) -> void:
	var key := _key_for(result)
	if key != "":
		say_key(world, player_state, key, _amount_for(result))

static func say_key(world: World, player_state: PlayerStateData, key: String, amount: int = 0) -> void:
	var options: Array = LINES[key]
	var line: String = options[world.runtime_rng.randi() % options.size()]
	player_state.last_message = line.replace("{n}", str(amount))
	player_state.message_serial += 1

static func _key_for(result: Dictionary) -> String:
	if result.is_empty():
		return ""
	if not result.get("ok", false):
		var reason: String = result.get("reason", "")
		return reason if LINES.has(reason) else ""
	var effect: String = result.get("effect", "")
	if result.get("ripped_off", false):
		effect += "_ripped"
	return effect if LINES.has(effect) else ""

static func _amount_for(result: Dictionary) -> int:
	for field in ["cost", "proceeds", "stolen", "taken", "payout", "quantity"]:
		if result.has(field):
			return result[field]
	return 0
