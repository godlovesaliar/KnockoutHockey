class_name Zamboni
extends Node3D
## The ice resurfacer: drives the between-periods pass (laps around the rink, each one a
## machine-width further in, until the middle is done), its wheels rolling and steering
## and the steering wheel turning, and lays fresh ice behind the conditioner (IceWear.sweep).
## The model: assets/zamboni/zamboni.glb (tools/blender/zamboni.py).

const SCENE := "res://assets/zamboni/zamboni.glb"
const WHEEL_R := 0.376
const WHEELBASE := 1.96
const SWEEP_HALF := 0.95         ## meters either side of the conditioner's middle
const CONDITIONER := 2.2         ## meters behind the machine's center
const LAP_STEP := 1.75           ## how much further in each lap runs
const FIRST_INSET := 1.0         ## the first lap's distance from the boards
const LAST_HALF_W := 0.9         ## the pass ends with the middle this narrow
const STEERING_RATIO := 7.0      ## steering-wheel turns per road-wheel angle
## The footprint (local x, z; front toward -z): the corners and side middles, for the boards.
const FOOTPRINT := [Vector2(-0.83, -1.7), Vector2(0.83, -1.7), Vector2(-0.83, 2.5), Vector2(0.83, 2.5),
		Vector2(-0.83, 0.4), Vector2(0.83, 0.4), Vector2(0.0, -1.75), Vector2(0.0, 2.55)]
## Where the driver sits: the Skater's origin (its seated hips are about Rink.SEAT_H over it).
const SEAT := Vector3(-0.36, 1.02, 2.12)

var wear: IceWear                ## lays fresh ice behind it (optional)
var driver: Skater               ## seated at the wheel (optional; see set_driver)
var sweep_half := SWEEP_HALF     ## the strip it lays (the fan contest widens it a little)
var distance := 0.0              ## meters along the pass
var length := 0.0                ## the whole pass

var _pts := PackedVector2Array()
var _cum := PackedFloat32Array()
var _wheels := {}                ## "FL" ... -> Node3D
var _steering: Node3D
var _steer_axis := Vector3(0.0, 0.616, 0.788).normalized()
var _steering_rest := Basis.IDENTITY
var _spin := 0.0
var _steer := 0.0
var _last_cond := Vector2.INF


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	for k: String in ["FL", "FR", "RL", "RR"]:
		_wheels[k] = model.find_child("Wheel" + k, true, false)
	_steering = model.find_child("Steering", true, false)
	if _steering:
		_steering_rest = _steering.basis
	_build_path()
	place(0.0)


## The trim (skirt, conditioner, footwell) in the home team's color.
func set_trim(c: Color) -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == "Trim" and m is StandardMaterial3D:
				var t: StandardMaterial3D = m.duplicate()
				t.albedo_color = c
				mi.set_surface_override_material(i, t)


## Seats `s` at the wheel (a Skater kept off the physics: it rides along, sitting).
func set_driver(s: Skater) -> void:
	driver = s
	s.frozen = true
	s.set_physics_process(false)
	s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if s.visual:
		s.visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		s.visual.bench_pose(true)
	_seat_driver()


func _seat_driver() -> void:
	if driver == null or not is_instance_valid(driver) or not is_inside_tree():
		return
	driver.global_position = global_transform * SEAT
	driver.heading = -global_basis.z
	driver.velocity = Vector3.ZERO


## Moves to `d` meters along the pass, rolling the wheels and steering the way there.
## With `lay` on, the conditioner sweeps the ice it passes over.
func place(d: float, lay := false) -> void:
	d = clampf(d, 0.0, length)
	var moved := d - distance
	distance = d
	var p := point_at(d)
	var ahead := point_at(minf(d + 0.6, length)) if d < length - 0.05 else p + (p - point_at(d - 0.6))
	var dir := (ahead - p).normalized() if ahead.distance_to(p) > 0.001 else Vector2(0, -1)
	# Steer by how the path bends a little way on.
	var far := point_at(minf(d + 2.5, length))
	var bend := 0.0
	if far.distance_to(p) > 0.5:
		var to := (far - p).normalized()
		bend = atan2(dir.x * to.y - dir.y * to.x, dir.dot(to))
	_steer = lerpf(_steer, clampf(-bend * 1.4, -0.6, 0.6), 0.25)
	pose(p, dir, moved, _steer, lay)


## Puts it at `p` (rink x, z) facing `dir`, having rolled `moved` meters (negative:
## backing up), the front wheels at `steer` (rad, + to the left). `lay`: the conditioner
## sweeps where it passed (going forward).
func pose(p: Vector2, dir: Vector2, moved: float, steer: float, lay := false) -> void:
	_steer = steer
	position = Vector3(p.x, 0.0, p.y)
	basis = Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)
	_spin -= moved / WHEEL_R
	for k: String in _wheels:
		var w: Node3D = _wheels[k]
		if w == null:
			continue
		var yaw := _steer if k.begins_with("F") else 0.0
		w.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _spin)
	if _steering:
		_steering.basis = Basis(_steer_axis, _steer * STEERING_RATIO) * _steering_rest
	var cond := p - dir * CONDITIONER
	if lay and wear:
		wear.sweep(_last_cond if _last_cond != Vector2.INF else cond, cond, sweep_half)
	_last_cond = cond if lay else Vector2.INF
	_seat_driver()


## Where the pass is `d` meters in (rink x, z).
func point_at(d: float) -> Vector2:
	if _pts.is_empty():
		return Vector2.ZERO
	d = clampf(d, 0.0, length)
	var lo := 0
	var hi := _cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := _cum[hi] - _cum[lo]
	return _pts[lo].lerp(_pts[hi], (d - _cum[lo]) / seg if seg > 0.0 else 0.0)


## The spiral: rounded-rectangle laps, each one LAP_STEP further in, starting at the
## middle of the +z end and running until the middle strip is done.
func _build_path() -> void:
	_pts.clear()
	_cum.clear()
	var laps := (RinkSpec.HALF_W - LAST_HALF_W - FIRST_INSET) / LAP_STEP
	var u := 0.0
	var du := 0.0025
	var total := 0.0
	while u <= laps:
		var inset := FIRST_INSET + LAP_STEP * u
		var q := _lap_point(RinkSpec.HALF_W - inset, RinkSpec.HALF_L - inset, RinkSpec.CORNER_RADIUS - inset, fposmod(u, 1.0))
		if not _pts.is_empty():
			total += q.distance_to(_pts[_pts.size() - 1])
		_pts.append(q)
		_cum.append(total)
		u += du
	# Then straight up the middle to the far end.
	var last := _pts[_pts.size() - 1]
	var end := Vector2(0.0, -(RinkSpec.HALF_L - FIRST_INSET - 2.0))
	if last.y > end.y:
		total += last.distance_to(end)
		_pts.append(end)
		_cum.append(total)
	length = total


## A point `u` (0..1) of the way around a rounded rectangle (half sizes a, b; corner
## radius r), starting at (0, b) and heading +x.
static func _lap_point(a: float, b: float, r: float, u: float) -> Vector2:
	a = maxf(a, 0.05)
	r = clampf(r, minf(2.5, a), minf(a, b))
	var sx := a - r
	var sz := b - r
	var arc := r * PI * 0.5
	var legs := [sx, arc, 2.0 * sz, arc, 2.0 * sx, arc, 2.0 * sz, arc, sx]
	var per := 0.0
	for l: float in legs:
		per += l
	var s := u * per
	for i in legs.size():
		var l: float = legs[i]
		if s > l and i < legs.size() - 1:
			s -= l
			continue
		var f := s / l if l > 0.0 else 0.0
		match i:
			0: return Vector2(lerpf(0.0, sx, f), b)
			1: return Vector2(sx, sz) + Vector2.from_angle(lerpf(PI * 0.5, 0.0, f)) * r
			2: return Vector2(a, lerpf(sz, -sz, f))
			3: return Vector2(sx, -sz) + Vector2.from_angle(lerpf(0.0, -PI * 0.5, f)) * r
			4: return Vector2(lerpf(sx, -sx, f), -b)
			5: return Vector2(-sx, -sz) + Vector2.from_angle(lerpf(-PI * 0.5, -PI, f)) * r
			6: return Vector2(-a, lerpf(-sz, sz, f))
			7: return Vector2(-sx, sz) + Vector2.from_angle(lerpf(PI, PI * 0.5, f)) * r
			_: return Vector2(lerpf(-sx, 0.0, f), b)
	return Vector2(0.0, b)
