## Entity = id + a bag of data-contract components (NPCData, BuildingData, etc).
## No behavior lives here — systems read/write components, entities just hold them.
class_name Entity
extends RefCounted

var id: StringName
var components: Dictionary = {}  # component class name (String) -> Resource

func _init(p_id: StringName) -> void:
	id = p_id

func add_component(component: Resource) -> void:
	components[component.get_script().get_global_name()] = component

func get_component(component_class_name: StringName) -> Resource:
	return components.get(component_class_name)

func has_component(component_class_name: StringName) -> bool:
	return components.has(component_class_name)

func remove_component(component_class_name: StringName) -> void:
	components.erase(component_class_name)
