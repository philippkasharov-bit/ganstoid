## Named constants for component class-name lookups. Entity.get_component()
## keys on get_global_name() string output — a typo'd raw literal ("NCPData")
## fails silently (returns null, not an error). Centralizing the strings here
## means a typo is a compile-time unresolved-identifier error instead.
class_name ComponentNames
extends RefCounted

const NPC := &"NPCData"
const BUILDING := &"BuildingData"
const GANG := &"GangData"
const ECONOMY_ITEM := &"EconomyItemData"
const ECONOMY_TRANSACTION := &"EconomyTransactionData"
