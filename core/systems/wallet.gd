## Phase 4 batch 24: dirty vs clean money. NPCData.cash stays the player's
## TOTAL money (so every existing total-cash check keeps working);
## PlayerStateData.dirty_cash is how much of that total is dirty. Clean is
## simply cash - dirty_cash. Invariant: 0 <= dirty_cash <= cash.
##
##   - Crime income (pickpocket, robbery, gang jobs, drug sales, crew
##     collections) comes in dirty.
##   - Shop income comes in clean.
##   - Everyday spending (product, recruiting, crew cuts) burns dirty first.
##   - Buying a business needs CLEAN money.
##   - An arrest seizes part of your dirty money.
##   - Owned shops launder dirty into clean each day, for a fee.
class_name Wallet
extends RefCounted

static func _npc(world: World) -> NPCData:
	return world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)

static func _state(world: World) -> PlayerStateData:
	return world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.PLAYER_STATE)

static func earn_dirty(world: World, amount: int) -> void:
	amount = int(amount * GameRules.money(world))   # O1: play style
	_npc(world).cash += amount
	_state(world).dirty_cash += amount

static func earn_clean(world: World, amount: int) -> void:
	_npc(world).cash += int(amount * GameRules.money(world))

static func clean(world: World) -> int:
	return _npc(world).cash - _state(world).dirty_cash

## Everyday spending: dirty money goes first.
static func spend(world: World, amount: int) -> void:
	var state := _state(world)
	_npc(world).cash -= amount
	state.dirty_cash = maxi(0, state.dirty_cash - amount)

## Clean-only spending (businesses). Caller checks clean() first.
static func spend_clean(world: World, amount: int) -> void:
	_npc(world).cash -= amount

## Removes `fraction` of dirty money (arrest). Returns the amount seized.
static func seize_dirty(world: World, fraction: float) -> int:
	var state := _state(world)
	var seized := ceili(state.dirty_cash * fraction)
	_npc(world).cash -= seized
	state.dirty_cash -= seized
	return seized

## Turns up to `capacity` dirty into clean, keeping `fee_fraction` as the
## cost of washing it. Returns {"washed": int, "fee": int}.
static func launder(world: World, capacity: int, fee_fraction: float) -> Dictionary:
	var state := _state(world)
	var washed := mini(state.dirty_cash, capacity)
	var fee := ceili(washed * fee_fraction)
	state.dirty_cash -= washed
	_npc(world).cash -= fee
	return {"washed": washed, "fee": fee}
