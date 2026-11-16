class_name Cutscene
extends Node
## A short in-game cutscene: a run of camera shots while play is stopped (the game keeps
## running: players skate, doors swing). Each shot is a Dictionary:
##   len    seconds (game time)
##   frame  Callable(t: float) -> [camera position, look-at point] (t = seconds into the shot)
##   fov    lens (degrees), optional (default 46)
##   start  Callable(), optional: runs as the shot begins
##   steady true for a locked-off shot (no handheld drift)
## Shots cut from one to the next like a broadcast; within a shot the camera eases after
## its target, with a little handheld drift (see `handheld`). Accept / back / Start skips: `on_skip` runs, then the cutscene ends.
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
var _sway := randf() * 100.0       ## the handheld drift's clock (a random start per cutscene)


func play() -> void:
	_cam = Camera3D.new()
	_cam.fov = 46.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # placed every frame
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
	_sway += delta
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
		if not shots[_i].get("steady", false):
			handheld(_cam, _sway)


## A camera operator's slow drift: layered slow sines on yaw, pitch and a little roll,
## applied after the camera is aimed. Scaled with the lens so the drift on screen stays
## about the same on a long lens as a wide one. `t`: a running clock (seconds).
static func handheld(cam: Camera3D, t: float, amount := 1.0) -> void:
	var k := amount * clampf(cam.fov / 46.0, 0.35, 1.2)
	var yaw := (sin(t * 0.53) * 0.6 + sin(t * 1.31 + 1.7) * 0.3 + sin(t * 2.9 + 0.4) * 0.1) * 0.55 * k
	var pitch := (sin(t * 0.71 + 2.1) * 0.6 + sin(t * 1.67 + 0.3) * 0.3 + sin(t * 3.3 + 1.1) * 0.1) * 0.4 * k
	var roll := (sin(t * 0.37 + 0.9) * 0.7 + sin(t * 1.13) * 0.3) * 0.3 * k
	cam.rotate_object_local(Vector3.UP, deg_to_rad(yaw))
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch))
	cam.rotate_object_local(Vector3.BACK, deg_to_rad(roll))


## Ends it now, as if the last shot ran out (for a shot held open with a long `len`).
func stop() -> void:
	_end(false)


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
