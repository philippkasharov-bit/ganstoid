## M2: the player as the Blender character (assets/models/player_character.glb):
## a skinned figure in a hoodie, baggy pants, sneakers and a cap, playing its
## baked Walk while you move (faster when you run), Idle when you stand, and
## Punch once on each attack (if the model has it).
## Everyone else stays on PersonRig3D's MultiMeshes: a thousand skinned
## figures would cost a thousand draw calls and skeletons.
class_name PlayerModel3D
extends Node3D

const PATH := "res://assets/models/player_character.glb"
const WALK_STRIDE := 0.7    # the Walk action's own speed: one loop covers about this many metres x2
const BLEND_S := 0.2

var _player: AnimationPlayer
var _ok := false
var _punch := false   # the model carries a Punch clip

func _ready() -> void:
	if not ResourceLoader.exists(PATH):
		return
	var model: Node3D = (load(PATH) as PackedScene).instantiate()
	add_child(model)
	_player = model.find_child("AnimationPlayer", true, false)
	_ok = _player != null and _player.has_animation("Walk") and _player.has_animation("Idle")
	if _ok:
		for anim in ["Walk", "Idle"]:
			_player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
		_punch = _player.has_animation("Punch")
		if _punch:
			_player.get_animation("Punch").loop_mode = Animation.LOOP_NONE
		_player.play("Idle")
	visible = false

## True when the model loaded (else the player stays a MultiMesh figure).
func usable() -> bool:
	return _ok

## Stands the figure at 3D point `at`, facing map angle `face`; `swing` > 0 while walking (bigger when running);
## `struck` is true on the frame an attack lands.
func pose(at: Vector3, face: float, swing: float, struck: bool = false) -> void:
	visible = true
	position = at
	basis = Basis(Vector3.UP, -face)
	if _punch and struck:
		_player.play("Punch", 0.05)
		_player.seek(0.0, true)
		_player.speed_scale = 1.0
	if _player.current_animation == "Punch" and _player.is_playing():
		return   # let the punch finish
	var anim := "Walk" if swing > 0.15 else "Idle"
	if _player.current_animation != anim:
		_player.play(anim, BLEND_S)
	_player.speed_scale = clampf(swing * 1.6, 0.8, 1.8) if anim == "Walk" else 1.0

func hide_figure() -> void:
	visible = false
