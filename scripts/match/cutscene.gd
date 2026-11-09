class_name Cutscene
extends Node
## A short in-game cutscene: a run of camera shots while play is stopped (the game keeps
## running: players skate, doors swing). Each shot is a Dictionary:
##   len    seconds (game time)
##   frame  Callable(t: float) -> [camera position, look-at point] (t = seconds into the shot)
##   fov    lens (degrees), optional (default 46)
##   start  Callable(), optional: runs as the shot begins
## Shots cut from one to the next like a broadcast; within a shot the camera eases after
## its target. Accept / back / Start skips: `on_skip` runs, then the cutscene ends.
## `finished(skipped)` fires either way, after the previous camera is back.

signal finished(skipped: bool)

var shots: Array[Dictionary] = []
var on_skip := Callable()
var _i := -1
var _t := 0.0
var _cam: Camera3D
var _prev: Camera3D
var _input: MenuInput
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _done := false


func play() -> void:
	_cam = Camera3D.new()
	_cam.fov = 46.0
	add_child(_cam)
	_prev = get_viewport().get_camera_3d()
	_cam.current = true
	_input = MenuInput.new()
	add_child(_input)
	_input.accepted.connect(_skip)
	_input.back.connect(_skip)
	_input.started.connect(_skip)
	_next()


func _next() -> void:
	_i += 1
	_t = 0.0
	if _i >= shots.size():
		_end(false)
		return
	var sh := shots[_i]
	if sh.has("start") and (sh.start as Callable).is_valid():
		sh.start.call()
	_cam.fov = float(sh.get("fov", 46.0))
	_frame(true, 0.0)


func _process(delta: float) -> void:
	if _done or _i < 0 or _i >= shots.size():
		return
	_t += delta
	if _t >= float(shots[_i].len):
		_next()
		return
	_frame(false, delta)


func _frame(snap: bool, delta: float) -> void:
	var r: Array = (shots[_i].frame as Callable).call(_t)
	var pos: Vector3 = r[0]
	var look: Vector3 = r[1]
	if snap:
		_pos = pos
		_look = look
	else:
		var k := 1.0 - exp(-5.0 * delta)
		_pos = _pos.lerp(pos, k)
		_look = _look.lerp(look, 1.0 - exp(-8.0 * delta))
	if _pos.distance_to(_look) > 0.05:
		_cam.look_at_from_position(_pos, _look)


func _skip() -> void:
	if _done or _i < 0 or (_i == 0 and _t < 0.4):
		return   # (a button already down when it started doesn't count)
	if on_skip.is_valid():
		on_skip.call()
	_end(true)


func _end(skipped: bool) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_prev):
		_prev.current = true
	finished.emit(skipped)
	queue_free()
