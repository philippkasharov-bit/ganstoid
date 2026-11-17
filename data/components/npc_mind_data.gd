## NB1: who a person is inside, next to NPCData. Pure data, no behaviour:
## NPCMind (core/systems/npc_mind.gd) rolls, reads and writes it.
## Made lazily, only for people something has happened to, so 6,000 untouched
## people cost nothing and are not in the save. Traits are not stored: they are
## rolled from the person's id and archetype every time, and only the change
## since then (trait_nudge) is kept. Needs and mood are stored with the tick
## they were last set, and NPCMind works out their value at any later tick.
class_name NPCMindData
extends Resource

@export var archetype: StringName = Archetypes.DEFAULT
@export var trait_nudge: PackedFloat32Array = PackedFloat32Array()   # per MindTrait, added to the rolled value
@export var drives: PackedFloat32Array = PackedFloat32Array()        # per MindDrive, 1 = satisfied, as of drives_tick
@export var drives_tick: int = 0
@export var mood: PackedFloat32Array = PackedFloat32Array()          # per MindMood, 0..1, as of mood_tick
@export var mood_tick: int = 0

## --- Memory: a small ring of what they lived through, parallel arrays ---
@export var mem_kind: PackedByteArray = PackedByteArray()        # GanstoidEnums.MindMemory
@export var mem_who: PackedStringArray = PackedStringArray()     # entity id involved ("" for none)
@export var mem_where: PackedVector2Array = PackedVector2Array()
@export var mem_tick: PackedInt64Array = PackedInt64Array()
@export var mem_weight: PackedFloat32Array = PackedFloat32Array()   # how much it mattered, 0..1

## --- Relationships beyond home, work and gang (those come from NPCData) ---
@export var friends: PackedStringArray = PackedStringArray()
