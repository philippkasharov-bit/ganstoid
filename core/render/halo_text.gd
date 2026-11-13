## HT1: Project Zomboid's halo text: short lines float up from over your head
## and fade (green when something went your way, red when it did not, white
## for the rest). Big news still gets the pop-up (Toast). Read-only.
class_name HaloText
extends Control

const LIFE_S := 3.0
const FADE_S := 0.7
const RISE_PX := 22.0
const LIFT_PX := 46.0     # starts above the action bar
const LINE_PX := 15.0
const MAX_W := 260.0
const MAX_LINES := 3
const TONES := {1: Color("8fdc7a"), -1: Color("f08a7a"), 0: Color.WHITE, 2: UiTheme.ACCENT}   # 2: a level or rank gained, in gold

var _world: World
var _seen := 0
var _lines: Array = []   # [{text, colour, age}], oldest first
var _prev := {}          # A1: need values last frame, to say what eating or a bandage did
const GAINS := {"hunger": "Food", "thirst": "Water", "fatigue": "Energy", "health": "Health"}
const GAIN_MIN := 0.04   # a jump this big in one frame came from something you used

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var state: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	_gains(p.get_component(ComponentNames.NPC))
	if state.message_serial != _seen:
		_seen = state.message_serial
		if not state.message_alert and state.last_message != "":
			push(state.last_message, state.message_tone)
	for l in _lines:
		l["age"] += delta
	_lines = _lines.filter(func(l: Dictionary) -> bool: return l["age"] < LIFE_S)
	queue_redraw()

## A1: "+Food 50%" in green the moment a need jumps up (you ate, drank, bandaged).
func _gains(npc: NPCData) -> void:
	for field in GAINS:
		var now: float = npc.get(field)
		var before: float = _prev.get(field, now)
		if now - before >= GAIN_MIN:
			push("+%s %d%%" % [GAINS[field], roundi((now - before) * 100)], 1)
		_prev[field] = now

func push(text: String, tone: int) -> void:
	for part in split_lines(text):
		_lines.append({"text": part, "colour": TONES.get(tone, Color.WHITE), "age": 0.0})
	while _lines.size() > MAX_LINES * 2:
		_lines.pop_front()

## Splits a line into pieces no wider than MAX_W.
static func split_lines(text: String) -> PackedStringArray:
	var font := ThemeDB.fallback_font
	var out: PackedStringArray = []
	var line := ""
	for word in text.split(" "):
		var next := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > MAX_W:
			out.append(line)
			line = word
		else:
			line = next
	if line != "":
		out.append(line)
	return out

func _draw() -> void:
	if _lines.is_empty():
		return
	var npc: NPCData = _world.entities[PlayerFactory.PLAYER_ENTITY_ID].get_component(ComponentNames.NPC)
	var head := ScreenMap.to_screen(get_viewport(), npc.position, 2.0) + Vector2(0, -LIFT_PX)   # R3D12: over the head in either view
	var font := ThemeDB.fallback_font
	var n := _lines.size()
	for i in n:
		var l: Dictionary = _lines[i]
		var t: float = l["age"]
		var at := head + Vector2(-MAX_W * 0.5, -RISE_PX * (t / LIFE_S) - LINE_PX * (n - 1 - i))
		var col: Color = l["colour"]
		col.a = clampf((LIFE_S - t) / FADE_S, 0.0, 1.0)
		draw_string_outline(font, at, l["text"], HORIZONTAL_ALIGNMENT_CENTER, MAX_W, 12, 3, Color(0, 0, 0, col.a))
		draw_string(font, at, l["text"], HORIZONTAL_ALIGNMENT_CENTER, MAX_W, 12, col)
