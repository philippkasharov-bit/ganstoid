## A3: a hit you take flashes the screen edges red, Zomboid-style: strong at
## the border, clear in the middle, gone in about half a second. Harder hits
## flash stronger. Read-only.
class_name DamageFlash
extends Control

const FADE_S := 0.8
const EDGE := 0.22   # how far in from each edge the red reaches, as a share of the screen

var _world: World
var _seen := -1
var _health := -1.0
var _strength := 0.0

func setup(world: World) -> void:
	_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	var p: Entity = _world.entities.get(PlayerFactory.PLAYER_ENTITY_ID) if _world != null else null
	if p == null:
		return
	var st: PlayerStateData = p.get_component(ComponentNames.PLAYER_STATE)
	var npc: NPCData = p.get_component(ComponentNames.NPC)
	if st.hurt_serial != _seen:
		if _seen >= 0:
			_strength = clampf(0.5 + (_health - npc.health) * 2.0, 0.5, 0.85)
		_seen = st.hurt_serial
	_health = npc.health
	if _strength > 0.0:
		_strength = maxf(0.0, _strength - delta / FADE_S * 0.8)
		size = get_viewport_rect().size
		queue_redraw()

func _draw() -> void:
	if _strength <= 0.0:
		return
	var s := size
	var red := Color(0.75, 0.05, 0.05, _strength)
	var clear := Color(0.75, 0.05, 0.05, 0.0)
	var e := s * EDGE
	var outer := [Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]
	var inner := [e, Vector2(s.x - e.x, e.y), s - e, Vector2(e.x, s.y - e.y)]
	for i in 4:   # four trapezoids, red outside fading to clear inside
		var j := (i + 1) % 4
		draw_polygon(PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]), PackedColorArray([red, red, clear, clear]))
