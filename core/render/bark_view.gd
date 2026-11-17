## ME1: what people say when they know you again, in a small speech bubble
## over their head (red when they hate or fear you, green when they owe you,
## white for the rest). Reads PlayerStateData.barks; MemorySystem writes them.
class_name BarkView
extends Control

const FONT_PX := 12
const PAD := Vector2(7, 4)
const LIFT := 2.3         # metres above the ground
const FADE_S := 0.6
const TAIL_PX := 6.0
const TONES := {1: Color("8fdc7a"), -1: Color("f08a7a"), 0: Color.WHITE}

var _world: World

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var font := ThemeDB.fallback_font
	for b in state.barks:
		var e: Entity = _world.entities.get(b["id"])
		var n: NPCData = e.get_component(ComponentNames.NPC) if e != null else null
		if n == null:
			continue
		var left := float(int(b["until"]) - _world.tick) / SimClock.TICKS_PER_SECOND
		var a := clampf(left / FADE_S, 0.0, 1.0)
		var tip := ScreenMap.to_screen(get_viewport(), n.position, LIFT)
		var text: String = b["text"]
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX) + PAD * 2.0
		var box := Rect2(tip - Vector2(size.x * 0.5, size.y + TAIL_PX), size)
		draw_rect(box, Color(0.05, 0.05, 0.06, 0.82 * a))
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -TAIL_PX), tip + Vector2(5, -TAIL_PX), tip]), Color(0.05, 0.05, 0.06, 0.82 * a))
		var col: Color = TONES.get(int(b["tone"]), Color.WHITE)
		col.a = a
		draw_string(font, box.position + Vector2(PAD.x, PAD.y + font.get_ascent(FONT_PX)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX, col)
