## ST1: Project Zomboid's endurance. Running and swinging a weapon use it up;
## walking lets it come back, standing still brings it back fastest. Carry more
## than the bag allows and you walk slower, tire faster and recover slower.
## Below OUT_AT you are out of breath: no running, weaker blows, until it is
## back over CATCH_AT. Real seconds; pure rules, no input or UI here.
class_name Stamina
extends RefCounted

const RUN_COST_PER_S := 0.07       # about 14 s of running from full
const SWING_COST := 0.04           # one melee swing
const BACK_WALKING_PER_S := 0.03
const BACK_RESTING_PER_S := 0.08
const OUT_AT := 0.1
const CATCH_AT := 0.35
const HEAVY_SPEED := 0.75          # over the carry limit you walk at three quarters
const HEAVY_COST := 1.5            # and everything tires you half again as fast
const WINDED_DAMAGE := 0.7         # out of breath, blows land at 70%

## True while overloaded (more kg than the bag allows).
static func heavy(state: PlayerStateData) -> bool:
	return InventoryWindow.carried_kg(state) > ItemCatalog.CARRY_KG

## Can you run right now? (no while out of breath)
static func can_run(state: PlayerStateData) -> bool:
	return not state.winded

## One real-time step. moving: walking or running this frame.
static func update(state: PlayerStateData, running: bool, moving: bool, delta: float) -> void:
	var load := HEAVY_COST if heavy(state) else 1.0
	if running and moving:
		state.endurance -= RUN_COST_PER_S * load * delta
	else:
		var back := BACK_WALKING_PER_S if moving else BACK_RESTING_PER_S
		state.endurance += back / load * delta
	state.endurance = clampf(state.endurance, 0.0, 1.0)
	_breath(state)

## A melee swing costs breath.
static func swing(state: PlayerStateData) -> void:
	state.endurance = maxf(0.0, state.endurance - SWING_COST * (HEAVY_COST if heavy(state) else 1.0))
	_breath(state)

static func _breath(state: PlayerStateData) -> void:
	if state.endurance <= OUT_AT:
		state.winded = true
	elif state.endurance >= CATCH_AT:
		state.winded = false

## Speed multiplier from load (breath does its part by stopping the run).
static func speed_mult(state: PlayerStateData) -> float:
	return HEAVY_SPEED if heavy(state) else 1.0

## Damage multiplier for melee while out of breath.
static func damage_mult(state: PlayerStateData) -> float:
	return WINDED_DAMAGE if state.winded else 1.0
