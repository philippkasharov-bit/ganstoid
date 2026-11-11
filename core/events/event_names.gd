## Named constants for EventBus event names -- same reasoning as
## ComponentNames: a raw string literal typo at an emit() or a listener's
## own `if event_name != "..."` check fails silently (never fires, no
## error), so every event name gets a constant here instead.
class_name GanstoidEvents
extends RefCounted

## Emitted by CrimeSystem when a witness actually recognizes the player
## committing a crime (not on every crime -- only once a recognition roll
## succeeds). Payload: {position: Vector2, severity: float, tick: int,
## witness_id: StringName}. Consumed by EscalationTickSystem (raises
## law_tier) and CopAISystem (alerts nearby cops).
const CRIME_WITNESSED := &"crime_witnessed"

## Combat C2: a shot fired. Payload: {position: Vector2, heard_m: float, tick: int}.
## Consumed by NPCScheduleSystem (people in earshot run for cover).
const GUNSHOT := &"gunshot"

## Combat C6: the player's blow or round landed. Payload: {victim_id: StringName,
## position: Vector2 (the player's), tick: int}. Consumed by NPCCombatSystem
## (the victim's gang comes for you).
const ASSAULTED := &"assaulted"

## G3: someone took a hit (anyone, by anyone). Payload: {id: StringName}.
## Consumed by WoundSystem (bleeding, waking from a knockout).
const WOUNDED := &"wounded"
