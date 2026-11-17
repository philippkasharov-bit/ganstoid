## NB1: rolls, reads and writes NPCMindData. Pure functions, engine-free, no
## per-tick work: nothing calls this in play yet (NB2+ will), so the city runs
## exactly as before. Every roll is seeded from the person's id, never from a
## global random order, so the same city always has the same people.
class_name NPCMind
extends RefCounted

const TRAITS := 8          # GanstoidEnums.MindTrait
const DRIVES := 6          # GanstoidEnums.MindDrive
const MOODS := 5           # GanstoidEnums.MindMood
const MEMORY_CAP := 12     # kept memories; the least important goes first
const FRIENDS_CAP := 4
const HABIT_SLOTS := 6     # 4-hour slots of the day
const SALT_TRAIT := 9100   # salts kept clear of NPCRoutine's (1..31)
const SALT_DRIVE := 9200
const SALT_RATE := 9300
const RATE_NOISE := 0.2    # one person's needs run down up to 20% faster or slower
const START_DRIVE_MIN := 0.5   # a fresh mind starts its needs between this and full
const CALM_BASELINE := 0.6     # mood fades back to this calm, and 0 for the rest
const MOOD_HALF_LIFE_H := 1.0  # game hours for a feeling to fade halfway
const NUDGE_MAX := 0.5         # life can move a trait at most this far from birth

## 0..1 from a person's id and a salt; the same inputs always give the same number.
static func unit(npc_id: StringName, salt: int) -> float:
	return float(absi(hash([npc_id, salt])) % 10007) / 10007.0

## Which archetype a person is, from what NPCData already says about them.
static func archetype_of(npc: NPCData) -> StringName:
	if npc.is_cop:
		return &"cop_on_beat"
	if npc.gang_id != &"":
		return &"gang_member"
	if npc.home_building_id == &"" and npc.camp != Vector2.ZERO:
		return &"homeless"
	if npc.job != &"":
		for kind in Archetypes.TABLE:
			if Archetypes.TABLE[kind]["jobs"].has(npc.job):
				return kind
	return Archetypes.DEFAULT

static func _spec(archetype: StringName) -> Dictionary:
	return Archetypes.TABLE.get(archetype, Archetypes.TABLE[Archetypes.DEFAULT])

## The trait as rolled at birth: inside the archetype's range, the mean of two
## rolls so most people sit near the middle and few at the edges.
static func base_trait(npc_id: StringName, archetype: StringName, which: int) -> float:
	var span: Array = _spec(archetype)["traits"][which]
	var roll := (unit(npc_id, SALT_TRAIT + which * 2) + unit(npc_id, SALT_TRAIT + which * 2 + 1)) * 0.5
	return lerpf(span[0], span[1], roll)

## All traits now: as rolled, plus whatever life has nudged.
static func traits(npc_id: StringName, mind: NPCMindData) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(TRAITS)
	for i in TRAITS:
		out[i] = clampf(base_trait(npc_id, mind.archetype, i) + mind.trait_nudge[i], 0.0, 1.0)
	return out

## Life moves a trait slowly (a robbed shopkeeper grows more paranoid).
static func nudge_trait(mind: NPCMindData, which: int, amount: float) -> void:
	mind.trait_nudge[which] = clampf(mind.trait_nudge[which] + amount, -NUDGE_MAX, NUDGE_MAX)

## A fresh mind for this person, as of `tick`. Not added to the world.
static func make(npc: NPCData, tick: int) -> NPCMindData:
	var mind := NPCMindData.new()
	mind.archetype = archetype_of(npc)
	mind.trait_nudge.resize(TRAITS)
	mind.drives.resize(DRIVES)
	for i in DRIVES:
		mind.drives[i] = lerpf(START_DRIVE_MIN, 1.0, unit(npc.id, SALT_DRIVE + i))
	mind.drives_tick = tick
	mind.mood.resize(MOODS)
	mind.mood[GanstoidEnums.MindMood.CALM] = CALM_BASELINE
	mind.mood_tick = tick
	return mind

## The person's mind if they have one; otherwise a fresh one that is NOT added
## to the world (for reading: the inspector must not change the sim).
static func mind_of(entity: Entity, tick: int) -> NPCMindData:
	var mind: NPCMindData = entity.get_component(ComponentNames.NPC_MIND)
	if mind != null:
		return mind
	var npc: NPCData = entity.get_component(ComponentNames.NPC)
	return make(npc, tick) if npc != null else null

## For sim code that is about to write: makes and registers the mind if needed.
static func get_or_make(world: World, entity: Entity) -> NPCMindData:
	var mind: NPCMindData = entity.get_component(ComponentNames.NPC_MIND)
	if mind == null:
		mind = mind_of(entity, world.tick)
		if mind == null:
			return null
		entity.add_component(mind)
		world.reindex_components(entity.id)
	return mind

## How much one person's need for `which` runs down per game hour.
static func drive_fall(npc_id: StringName, archetype: StringName, which: int) -> float:
	var noise := lerpf(1.0 - RATE_NOISE, 1.0 + RATE_NOISE, unit(npc_id, SALT_RATE + which))
	return float(_spec(archetype)["drive_fall"][which]) * noise

## Needs at `tick`: run down from the last time they were set.
static func drives_now(npc_id: StringName, mind: NPCMindData, tick: int) -> PackedFloat32Array:
	var hours := maxf(0.0, float(tick - mind.drives_tick) * 24.0 / float(SimClock.day_ticks))
	var out := PackedFloat32Array()
	out.resize(DRIVES)
	for i in DRIVES:
		out[i] = clampf(mind.drives[i] - drive_fall(npc_id, mind.archetype, i) * hours, 0.0, 1.0)
	return out

## Sets one need (eating fills FOOD); the others are brought up to date first.
static func set_drive(npc_id: StringName, mind: NPCMindData, which: int, value: float, tick: int) -> void:
	mind.drives = drives_now(npc_id, mind, tick)
	mind.drives[which] = clampf(value, 0.0, 1.0)
	mind.drives_tick = tick

## Mood at `tick`: every feeling fades halfway to its baseline each half-life.
static func mood_now(mind: NPCMindData, tick: int) -> PackedFloat32Array:
	var hours := maxf(0.0, float(tick - mind.mood_tick) * 24.0 / float(SimClock.day_ticks))
	var keep := pow(0.5, hours / MOOD_HALF_LIFE_H)
	var out := PackedFloat32Array()
	out.resize(MOODS)
	for i in MOODS:
		var base := CALM_BASELINE if i == GanstoidEnums.MindMood.CALM else 0.0
		out[i] = base + (mind.mood[i] - base) * keep
	return out

## A feeling rises (or falls) by `amount`; the rest are brought up to date first.
static func feel(mind: NPCMindData, which: int, amount: float, tick: int) -> void:
	mind.mood = mood_now(mind, tick)
	mind.mood[which] = clampf(mind.mood[which] + amount, 0.0, 1.0)
	mind.mood_tick = tick

## Adds a memory. When full, it replaces the least important one (oldest on a
## tie), or is dropped if it matters less than everything already kept.
static func remember(mind: NPCMindData, kind: int, who: StringName, where: Vector2, tick: int, weight: float) -> void:
	var slot := mind.mem_kind.size()
	if slot >= MEMORY_CAP:
		slot = _weakest_memory(mind)
		if mind.mem_weight[slot] > weight:
			return
	else:
		mind.mem_kind.append(0)
		mind.mem_who.append("")
		mind.mem_where.append(Vector2.ZERO)
		mind.mem_tick.append(0)
		mind.mem_weight.append(0.0)
	mind.mem_kind[slot] = kind
	mind.mem_who[slot] = String(who)
	mind.mem_where[slot] = where
	mind.mem_tick[slot] = tick
	mind.mem_weight[slot] = clampf(weight, 0.0, 1.0)

static func _weakest_memory(mind: NPCMindData) -> int:
	var best := 0
	for i in range(1, mind.mem_weight.size()):
		var w := mind.mem_weight[i]
		if w < mind.mem_weight[best] or (w == mind.mem_weight[best] and mind.mem_tick[i] < mind.mem_tick[best]):
			best = i
	return best

## Makes a loaded mind safe to use: the save file is untrusted, so every array
## gets its right length and range, and unknown values fall back to defaults.
static func sanitize(mind: NPCMindData) -> void:
	if not Archetypes.TABLE.has(mind.archetype):
		mind.archetype = Archetypes.DEFAULT
	mind.trait_nudge = _fit(mind.trait_nudge, TRAITS, -NUDGE_MAX, NUDGE_MAX, 0.0)
	mind.drives = _fit(mind.drives, DRIVES, 0.0, 1.0, 1.0)
	mind.mood = _fit(mind.mood, MOODS, 0.0, 1.0, 0.0)
	var n := mini(mini(mind.mem_kind.size(), mind.mem_who.size()), mind.mem_where.size())
	n = mini(mini(n, mind.mem_tick.size()), mini(mind.mem_weight.size(), MEMORY_CAP))
	mind.mem_kind.resize(n)
	mind.mem_who.resize(n)
	mind.mem_where.resize(n)
	mind.mem_tick.resize(n)
	mind.mem_weight = _fit(mind.mem_weight, n, 0.0, 1.0, 0.0)
	for i in n:
		if mind.mem_kind[i] >= GanstoidEnums.MindMemory.size():
			mind.mem_kind[i] = GanstoidEnums.MindMemory.MET_PLAYER
	if mind.friends.size() > FRIENDS_CAP:
		mind.friends.resize(FRIENDS_CAP)
	if not mind.habit_slots.is_empty():
		mind.habit_slots.resize(HABIT_SLOTS)
		for i in HABIT_SLOTS:
			if not Activities.TABLE.has(StringName(mind.habit_slots[i])):
				mind.habit_slots[i] = ""

## `values` cut or padded to `size`, NaN replaced, every entry clamped.
static func _fit(values: PackedFloat32Array, size: int, lo: float, hi: float, fill: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(size)
	for i in size:
		var v := values[i] if i < values.size() else fill
		out[i] = fill if is_nan(v) else clampf(v, lo, hi)
	return out
