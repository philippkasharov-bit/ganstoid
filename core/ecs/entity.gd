## Entity = id + a bag of data-contract components (NPCData, BuildingData, etc).
## No behavior lives here — systems read/write components, entities just hold them.
class_name Entity
extends RefCounted

var id: StringName
var components: Dictionary = {}  # component class name (String) -> Resource

func _init(p_id: StringName) -> void:
	id = p_id

## CAUTION: see remove_component's note below if this entity is already
## registered with a World — the same reindex_components contract applies.
func add_component(component: Resource) -> void:
	# Explicit StringName cast, not whatever type get_global_name() happens to
	# return: ComponentNames.* constants are StringName literals, and every
	# indexed lookup (World._component_index, required_component filtering)
	# depends on this dict's keys hashing identically to those constants. If
	# the two ever mismatched (String vs StringName), lookups would fail
	# silently -- empty result, not an error -- which is exactly the bug
	# class ComponentNames was introduced to close. Don't leave it to chance.
	components[StringName(component.get_script().get_global_name())] = component

func get_component(component_class_name: StringName) -> Resource:
	return components.get(component_class_name)

func has_component(component_class_name: StringName) -> bool:
	return components.has(component_class_name)

## CAUTION if this entity is already registered with a World: add/remove
## here only touch this entity's own component bag, not World's
## _component_index. Call World.reindex_components(id) right after, or the
## entity goes stale in the index (present under a component it no longer
## has, or missing from one it just gained) — the same staleness problem
## position has, with reindex_position as its fix. Safe to call freely
## before registration, since there's no index yet to desync.
func remove_component(component_class_name: StringName) -> void:
	components.erase(component_class_name)
