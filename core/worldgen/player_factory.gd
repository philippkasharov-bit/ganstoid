## Composition point for the player entity: composes NPCData (shared
## physical/survival state -- position, hunger, cash) with PlayerStateData
## (escalation state only the player has) onto one Entity. See the Phase 0
## player-state-split hardening note in the roadmap for why these are two
## separate components rather than one.
class_name PlayerFactory
extends RefCounted

## Fixed id -- there is exactly one player ever, so a generated id would be
## pure indirection with no payoff. Code that's fine assuming a singleton
## player can use this constant directly; code that shouldn't assume that
## (or was written before this file existed) finds the player via
## World.get_entities_with_component(ComponentNames.PLAYER_STATE) instead --
## exactly one match, by construction, either way.
const PLAYER_ENTITY_ID := &"player"

## home_building_id matters now beyond flavor: CopAISystem sends the player
## there as the Phase 1 "short jail stint" stub on arrest (see roadmap
## Phase 1 lock). Defaulting it to &"" is still valid -- callers that don't
## care (tests, future non-residential starts) just won't get a jail
## destination, handled defensively where it's read.
static func spawn(world: World, spawn_position: Vector2, home_building_id: StringName = &"", starting_cash: int = 0) -> StringName:
	var npc := NPCData.new()
	npc.id = PLAYER_ENTITY_ID
	npc.display_name = "Player"
	npc.position = spawn_position
	npc.home_building_id = home_building_id
	npc.cash = starting_cash

	var player_state := PlayerStateData.new()

	var entity := Entity.new(PLAYER_ENTITY_ID)
	entity.add_component(npc)
	entity.add_component(player_state)
	world.register_entity(entity)
	return PLAYER_ENTITY_ID
