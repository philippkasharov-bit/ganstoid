## OPT1: the city is only built where you are. Chunks within LOAD_M of the
## player are built (all at once at the start, then the nearest missing one
## at a time on a worker thread as you move, so walking never hitches; the
## finished nodes are added on the main thread) and chunks further than
## UNLOAD_M are freed. Each chunk brings its ground, roads, buildings,
## detail, trees, palms, power lines and lamp posts.
class_name CityStream3D
extends Node3D

const LOAD_M := 300.0
const UNLOAD_M := 480.0
const CHECK_S := 0.2

var origin := Vector2.ZERO
var index: ChunkIndex3D
var lights: StreetLights
var _loaded: Dictionary = {}   # Vector2i -> Array[Node3D]
var _want: Array[Vector2i] = []
var _left := 0.0
var built_ms := 0.0            # time spent building, for the checks

func setup(city: CityData, at_origin: Vector2, lamp_layout: StreetLights) -> void:
	origin = at_origin
	lights = lamp_layout
	index = ChunkIndex3D.build(city, CityReal.load_files(), origin)

## Build everything round `p` now (the start of a game, a teleport).
func prime(p: Vector2) -> void:
	_plan(p)
	while not _want.is_empty():
		_build(_want.pop_front())

func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 and focus != Vector2.INF:
		_left = CHECK_S
		_plan(focus)
	_collect()
	if _task < 0 and not _want.is_empty():
		var k: Vector2i = _want.pop_front()
		_task = WorkerThreadPool.add_task(func() -> void: _finished = [k, _make(k)])

var _task := -1
var _finished: Array = []   # [key, nodes] from the worker, picked up on the main thread

## A worker's chunk is done: put it in the world (unless it went out of range meanwhile).
func _collect() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var k: Vector2i = _finished[0]
	if _loaded.has(k) or index.rect_of(k).get_center().distance_to(focus) > UNLOAD_M + CityMesh3D.CHUNK_M * 0.7:
		for n in _finished[1]:
			n.free()
		return
	for n in _finished[1]:
		add_child(n)
	_loaded[k] = _finished[1]

var focus := Vector2.INF   # where the player is (set by the view each frame)

## What to build (nearest first) and what to drop round `p`.
func _plan(p: Vector2) -> void:
	_want.clear()
	var c := index.key_of(p)
	var span := ceili(LOAD_M / CityMesh3D.CHUNK_M) + 1
	for x in range(c.x - span, c.x + span + 1):
		for y in range(c.y - span, c.y + span + 1):
			var k := Vector2i(x, y)
			if not _loaded.has(k) and (_finished.is_empty() or _finished[0] != k or _task < 0) and index.rect_of(k).get_center().distance_to(p) < LOAD_M + CityMesh3D.CHUNK_M * 0.7:
				_want.append(k)
	_want.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return index.rect_of(a).get_center().distance_squared_to(p) < index.rect_of(b).get_center().distance_squared_to(p))
	for k in _loaded.keys():
		if index.rect_of(k).get_center().distance_to(p) > UNLOAD_M + CityMesh3D.CHUNK_M * 0.7:
			for n in _loaded[k]:
				n.queue_free()
			_loaded.erase(k)

func _build(k: Vector2i) -> void:
	var nodes := _make(k)
	for n in nodes:
		add_child(n)
	_loaded[k] = nodes

## Chunk `k`'s nodes, not yet in the tree (safe on a worker thread).
func _make(k: Vector2i) -> Array[Node3D]:
	var t0 := Time.get_ticks_usec()
	var slice := index.slice(k)
	var rect := index.rect_of(k)
	var nodes := CityMesh3D.build(slice[0], rect.get_center(), CityMesh3D.CHUNK_M * 3.0, origin, k, rect, slice[1])
	var lamps := PackedVector3Array()
	for l in lights.near(rect.get_center(), CityMesh3D.CHUNK_M):
		if rect.has_point(Vector2(l.x, l.y)):
			lamps.append(l)
	nodes.append(DayNight3D.posts(lamps, origin))
	built_ms += (Time.get_ticks_usec() - t0) / 1000.0
	return nodes

func loaded_count() -> int:
	return _loaded.size()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)   # never leave a worker writing into a freed stream
