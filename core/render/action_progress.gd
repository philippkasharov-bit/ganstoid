## TA1: the Zomboid bar over your head while a timed action runs: a small
## marker-white bar filling left to right, the verb above it. Read-only.
class_name ActionProgress
extends Control

const W := 46.0
const H := 5.0
const LIFT_PX := 30.0   # screen pixels above the player, the same at any zoom

var _world: World

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if _world == null:
		return
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID)
	if p == null:
		return
	var info := TimedAction.progress(_world, p.get_component(ComponentNames.PLAYER_STATE))
	if info.is_empty():
		return
	var npc: NPCData = p.get_component(ComponentNames.NPC)
	var at := get_viewport().get_canvas_transform() * npc.position + Vector2(0, -LIFT_PX)
	var bar := Rect2(at - Vector2(W * 0.5, 0), Vector2(W, H))
	draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(bar.position, Vector2(W * info["f"], H)), UiTheme.ACCENT)
	var font := UiTheme.font("marker")
	draw_string_outline(font, at + Vector2(-W * 0.5, -4), info["text"], HORIZONTAL_ALIGNMENT_CENTER, W, 11, 3, Color.BLACK)
	draw_string(font, at + Vector2(-W * 0.5, -4), info["text"], HORIZONTAL_ALIGNMENT_CENTER, W, 11, Color.WHITE)
