## T3: districts are the big prize. A district is held by whoever holds more
## than SHARE of its blocks (each block is its own capture point); holding one
## pays DISTRICT_TAX on top of the block taxes every morning.
class_name DistrictControl
extends RefCounted

const SHARE := 0.5
const DISTRICT_TAX := 400

static var _blocks: Dictionary = {}   # district name -> Array[Vector2i]

## Every block key in `district`.
static func blocks_in(district: String) -> Array:
	var h := Hoods.data()
	if h == null:
		return []
	if _blocks.is_empty():
		for i in h.blocks.size():
			var k := Vector2i(i, Hoods.BLOCK_Y)
			_blocks.get_or_add(h.district_of(k), []).append(k)
	return _blocks.get(district, [])

static func names() -> Array:
	blocks_in("")
	return _blocks.keys().filter(func(d: String) -> bool: return d != "")

## [holder (&"" = nobody), share of blocks the top gang holds] for `district`.
static func holder(t: TerritoryData, district: String) -> Array:
	var count := {}
	var all := blocks_in(district)
	for k in all:
		var g := TerritorySystem.controller(t, k)
		if g != &"":
			count[g] = count.get(g, 0) + 1
	var best: StringName = &""
	var best_n := 0
	for g in count:
		if count[g] > best_n:
			best_n = count[g]
			best = g
	var share := best_n / float(maxi(all.size(), 1))
	return [best if share > SHARE else &"", share]

## Districts `gang` holds.
static func held_by(t: TerritoryData, gang: StringName) -> Array:
	return names().filter(func(d: String) -> bool: return holder(t, d)[0] == gang)
