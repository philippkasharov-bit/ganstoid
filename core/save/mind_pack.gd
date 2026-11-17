## NB2d: an NPCMindData written small. Every person who chose their free time
## has a mind, so a save can hold 6,000 of them; written field by field with
## full-precision decimals each took about 540 bytes. Here the needs, mood and
## trait changes are whole numbers 0..254 in one base64 string (steps of 0.004
## precision, far below anything a person would notice), and empty parts are
## left out. unpack() reads untrusted text: NPCMind.sanitize runs after it.
class_name MindPack
extends RefCounted

const KEY := "z"          # a packed mind has this key; the old field-by-field form does not
const BASE64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
const STEPS := 254.0      # even, so 0 sits exactly in the middle of the trait-change range

static func pack(mind: NPCMindData) -> Dictionary:
	var bytes := PackedByteArray()
	_write(bytes, mind.drives, 0.0, 1.0)
	_write(bytes, mind.mood, 0.0, 1.0)
	_write(bytes, mind.trait_nudge, -NPCMind.NUDGE_MAX, NPCMind.NUDGE_MAX)
	var out := {KEY: Marshalls.raw_to_base64(bytes), "t": [mind.drives_tick, mind.mood_tick]}
	if mind.archetype != Archetypes.DEFAULT:
		out["a"] = String(mind.archetype)
	if not mind.habit_slots.is_empty():
		out["h"] = "|".join(mind.habit_slots)
	if not mind.mem_kind.is_empty():
		var weights := PackedByteArray()
		_write(weights, mind.mem_weight, 0.0, 1.0)
		out["m"] = [Marshalls.raw_to_base64(mind.mem_kind), mind.mem_who, mind.mem_where, mind.mem_tick, Marshalls.raw_to_base64(weights)]
	if not mind.friends.is_empty():
		out["f"] = mind.friends
	return out

## Lays a packed mind over `mind`. Anything malformed is left at its default.
static func unpack(mind: NPCMindData, data: Dictionary) -> void:
	var bytes := _raw(data.get(KEY))
	var at := _read(bytes, 0, NPCMind.DRIVES, 0.0, 1.0, mind, "drives")
	at = _read(bytes, at, NPCMind.MOODS, 0.0, 1.0, mind, "mood")
	_read(bytes, at, NPCMind.TRAITS, -NPCMind.NUDGE_MAX, NPCMind.NUDGE_MAX, mind, "trait_nudge")
	var ticks: Variant = data.get("t")
	if ticks is Array and ticks.size() == 2 and ticks[0] is int and ticks[1] is int:
		mind.drives_tick = ticks[0]
		mind.mood_tick = ticks[1]
	mind.archetype = StringName(str(data.get("a", Archetypes.DEFAULT)))
	if data.get("h") is String:
		mind.habit_slots = PackedStringArray(String(data["h"]).split("|"))
	if data.get("f") is PackedStringArray:
		mind.friends = data["f"]
	_unpack_memory(mind, data.get("m"))

static func _unpack_memory(mind: NPCMindData, m: Variant) -> void:
	if not (m is Array and m.size() == 5 and m[1] is PackedStringArray and m[2] is PackedVector2Array and m[3] is PackedInt64Array):
		return
	mind.mem_kind = _raw(m[0])
	mind.mem_who = m[1]
	mind.mem_where = m[2]
	mind.mem_tick = m[3]
	var weights := _raw(m[4])
	_read(weights, 0, weights.size(), 0.0, 1.0, mind, "mem_weight")

static func _write(bytes: PackedByteArray, values: PackedFloat32Array, lo: float, hi: float) -> void:
	for v in values:
		bytes.append(roundi(clampf((v - lo) / (hi - lo), 0.0, 1.0) * STEPS))

## Reads `count` values from `bytes` at `at` into mind[field]; returns where it stopped.
static func _read(bytes: PackedByteArray, at: int, count: int, lo: float, hi: float, mind: NPCMindData, field: String) -> int:
	if at + count > bytes.size():
		return at
	var values := PackedFloat32Array()
	values.resize(count)
	for i in count:
		values[i] = lo + float(bytes[at + i]) / STEPS * (hi - lo)
	mind.set(field, values)
	return at + count

## The bytes in a base64 string, or none if it is not one (checked first: the
## engine logs an error on bad input, and a broken save must load quietly).
static func _raw(text: Variant) -> PackedByteArray:
	if not text is String or text.length() % 4 != 0:
		return PackedByteArray()
	for c in text:
		if not BASE64.contains(c):
			return PackedByteArray()
	return Marshalls.base64_to_raw(text)
