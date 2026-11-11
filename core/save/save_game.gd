## Save/load (SL1), Zomboid-style: one save per city, written when you quit and
## every in-game hour, deleted when you die (permadeath).
##
## The city is rebuilt from the saved seed (world generation is deterministic,
## so every entity gets the same id), then every component's stored fields are
## laid back over it. Systems' working state (routes, the calendar) is not saved:
## after loading, everyone is settled where their routine puts them at that hour.
class_name SaveGame
extends RefCounted

const PATH := "user://ganstoid_save.txt"
const VERSION := 1
const SKIP := ["resource_local_to_scene", "resource_name", "resource_path", "resource_scene_unique_id", "script"]

static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)

static func delete(path: String = PATH) -> void:
	if exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Writes the whole world. Returns false if the file could not be written.
static func write(world: World, seed: int, path: String = PATH) -> bool:
	return _store(snapshot(world, seed), path)

## Autosave without a hitch: the snapshot is taken now (a copy), turning it into
## text and writing it happen on a worker thread. Returns the task id.
static func write_in_background(world: World, seed: int, path: String = PATH) -> int:
	var data := snapshot(world, seed)
	return WorkerThreadPool.add_task(func() -> void: _store(data, path))

## The whole world as plain data, detached from the live one.
static func snapshot(world: World, seed: int) -> Dictionary:
	var entities := {}
	for id in world.entities:
		var comps := {}
		var entity: Entity = world.entities[id]
		for name in entity.components:
			var comp: Resource = entity.components[name]
			if comp is VehicleData and not comp.touched:
				continue   # a parked car nobody touched is rebuilt as seeded
			comps[name] = _fields(comp)
		entities[id] = comps
	var goods := {}
	for good in world.economy_items:
		goods[good] = _fields(world.economy_items[good])
	return {"version": VERSION, "seed": seed, "tick": world.tick, "rng_state": world.runtime_rng.state,
		"entities": entities, "goods": goods}

static func _store(data: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)   # never leave a half-written save
	if file == null:
		push_error("SaveGame: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(var_to_str(data))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) == OK

## The saved data, or {} if there is none or it is unreadable / from another version.
static func read(path: String = PATH) -> Dictionary:
	if not exists(path):
		return {}
	var data: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != VERSION:
		push_warning("SaveGame: %s is not a usable save; starting a new game" % path)
		return {}
	return data

## Lays saved fields over a world freshly generated from data["seed"].
## Returns how many entities were restored.
static func apply(world: World, data: Dictionary) -> int:
	var restored := 0
	for id in data["entities"]:
		var entity: Entity = world.entities.get(id)
		if entity == null:
			continue   # the city changed since this save (a map update): skip what is gone
		for name in data["entities"][id]:
			var comp: Resource = entity.components.get(name)
			if comp != null:
				_restore(comp, data["entities"][id][name])
		world.reindex_position(id)
		restored += 1
	for good in data.get("goods", {}):
		if world.economy_items.has(good):
			_restore(world.economy_items[good], data["goods"][good])
	world.tick = data["tick"]
	world.runtime_rng.state = data["rng_state"]
	return restored

static var _names_by_script := {}   # Script -> its stored field names (asking each object costs ~40 us)

static func _fields(res: Resource) -> Dictionary:
	var script: Script = res.get_script()
	var names: Array = _names_by_script.get(script, [])
	if names.is_empty():
		for prop in res.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_STORAGE and not SKIP.has(prop["name"]):
				names.append(prop["name"])
		_names_by_script[script] = names
	var out := {}
	for name in names:
		var v: Variant = res.get(name)
		out[name] = v.duplicate(true) if v is Dictionary or v is Array else v
	return out

static func _restore(res: Resource, fields: Dictionary) -> void:
	for name in fields:
		if name in res:
			res.set(name, fields[name])
