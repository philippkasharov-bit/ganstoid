## R3D11: what walls let you see, Zomboid-style. A polar depth map round the
## player: for each of BINS directions, how far you can see before a wall
## (building outlines nearby, and the inner walls of the building you are
## in; doorways are gaps). Each wall segment is drawn into the bins it spans
## (a polar z-buffer), so a cast costs a few thousand steps, not rays x walls.
## The Cutaway shader darkens ground, palms and rooms past the depth; people
## past it are not drawn.
class_name SightMap
extends RefCounted

const BINS := 360
const MAX_M := 90.0

var from := Vector2.INF
var depth := PackedFloat32Array()

## Cast from `eye` against `walls` (pairs of map points: a0, b0, a1, b1, ...).
func cast(eye: Vector2, walls: PackedVector2Array) -> void:
	from = eye
	depth.resize(BINS)
	depth.fill(MAX_M)
	for i in range(0, walls.size() - 1, 2):
		_segment(walls[i] - eye, walls[i + 1] - eye)

func _segment(a: Vector2, b: Vector2) -> void:
	var ia := _bin(a.angle())
	var ib := _bin(b.angle())
	var span := posmod(ib - ia, BINS)
	if span > BINS / 2:   # walk the short way round
		var t := ia
		ia = ib
		ib = t
		span = BINS - span
	var seg := b - a
	for k in span + 1:
		var bin := (ia + k) % BINS
		var dir := Vector2.from_angle((bin + 0.5) * TAU / BINS)
		var den := dir.cross(seg)
		if absf(den) < 0.0001:
			continue
		var t := a.cross(seg) / den   # distance along the ray to the wall's line
		if t > 0.0 and t < depth[bin]:
			depth[bin] = t

static func _bin(angle: float) -> int:
	return posmod(int(floor(angle / TAU * BINS)), BINS)

## How far you can see toward map point `p`.
func reach_toward(p: Vector2) -> float:
	if from == Vector2.INF or depth.is_empty():
		return MAX_M
	return depth[_bin((p - from).angle())]

func sees(p: Vector2) -> bool:
	return p.distance_to(from) <= reach_toward(p) + 0.3
