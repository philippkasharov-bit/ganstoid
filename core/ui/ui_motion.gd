## UI6: the HUD's motion. Panels fade and slide in when they appear and out
## when they go, instead of popping; a bar fills smoothly toward its value.
class_name UiMotion
extends RefCounted

const FADE_PER_S := 6.0
const SLIDE_PX := 14.0

## Eases `c` toward shown (want) or gone; returns the 0..1 amount shown.
## Call every frame instead of setting `visible`. `from` is where it slides from.
static func fade(c: Control, want: bool, delta: float, from := Vector2(0, -1)) -> float:
	var a: float = c.get_meta("motion", 0.0)
	a = move_toward(a, 1.0 if want else 0.0, FADE_PER_S * delta)
	c.set_meta("motion", a)
	c.visible = a > 0.01
	c.modulate.a = a
	var e := ease(a, 0.4)
	c.set_meta("motion_shift", from * SLIDE_PX * (1.0 - e))
	return a

## The slide offset fade() asks for this frame (add it to the position).
static func shift(c: Control) -> Vector2:
	return c.get_meta("motion_shift", Vector2.ZERO)

## A number eased toward its target (bars, counters).
static func toward(now: float, target: float, delta: float, speed: float = 5.0) -> float:
	return lerpf(now, target, minf(1.0, speed * delta))
