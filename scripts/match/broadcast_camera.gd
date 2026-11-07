class_name BroadcastCamera
extends Camera3D
## Vertical (end-to-end) broadcast camera that follows a target, plus debug views.
## Screen-up is world -Z.

enum Mode { BROADCAST, OVERHEAD, END_ZONE }

@export var target_path: NodePath
@export var height := 24.0
@export var distance := 8.5         ## how far the camera sits behind the focus (+Z)
@export var x_follow := 0.45        ## how much of the target's X the camera follows
@export var lead_time := 0.3        ## seconds of velocity look-ahead
@export var max_lead := 6.0
@export var smoothing := 4.0
@export var broadcast_fov := 40.0

var mode := Mode.BROADCAST
var target: Node3D
var _focus := Vector3.ZERO
var _shake := 0.0


func _ready() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path)
	make_current()
	set_mode(mode)


func set_mode(m: Mode) -> void:
	mode = m
	if mode == Mode.OVERHEAD:
		projection = PROJECTION_ORTHOGONAL
		size = RinkSpec.LENGTH + 4.0
	else:
		projection = PROJECTION_PERSPECTIVE
		fov = broadcast_fov
	_apply(true)


func cycle_mode() -> void:
	set_mode(((mode + 1) % Mode.size()) as Mode)


func mode_name() -> String:
	return Mode.keys()[mode]


## Kick the camera (big hits, glass, goals). Decays on its own.
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	_apply(false, delta)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.35


func _apply(snap: bool, delta := 0.0) -> void:
	var goal := Vector3.ZERO
	if target:
		var p := target.get_global_transform_interpolated().origin
		var v: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
		goal = p + (Vector3(v.x, 0.0, v.z) * lead_time).limit_length(max_lead)
	goal.x *= x_follow
	goal.y = 0.0
	goal.z = clampf(goal.z, -(RinkSpec.HALF_L - 9.0), RinkSpec.HALF_L - 9.0)
	_focus = goal if snap else _focus.lerp(goal, 1.0 - exp(-smoothing * delta))

	match mode:
		Mode.BROADCAST:
			global_position = _focus + Vector3(0.0, height, distance)
			look_at(_focus, Vector3.UP)
		Mode.OVERHEAD:
			global_position = Vector3(0.0, 60.0, 0.0)
			look_at(Vector3.ZERO, Vector3.FORWARD)
		Mode.END_ZONE:
			global_position = Vector3(0.0, 4.5, RinkSpec.HALF_L - 0.3)
			look_at(Vector3(0.0, 0.0, RinkSpec.GOAL_LINE_Z - 3.0), Vector3.UP)
