class_name Zamboni
extends Node3D
## The ice resurfacer: drives the between-periods pass (laps around the rink, each one a
## machine-width further in, until the middle is done), its wheels rolling and steering
## and the steering wheel turning, and lays fresh ice behind the conditioner (IceWear.sweep).
## The model is the project's own: assets/zamboni/zamboni.glb (tools/blender/zamboni.py
## builds it, to the numbers below).

const SCENE := "res://assets/zamboni/zamboni.glb"
const PLATE_SHADER := preload("res://scenes/match/logo_plate.gdshader")
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
## ...and a Fan's: a boot's sole is thinner than a skate's blade is tall, and it sits up to
## the wheel (the Skater sits back, hands on its knees).
const FAN_SEAT := SEAT + Vector3(0.0, 0.05, -0.1)
## The steering wheel's rim (tools/blender/zamboni.py STEER_R), and how a Fan drives: bent
## forward as far as its arms need (a short driver more), a hand each side of the rim (rad
## round it from the top, + to the driver's left). A hand turns with the wheel as far as its HAND_SWING either way, then lets go
## and takes it again further back (REGRIP seconds): one hand at a time while the wheel
## turns slowly, both if it spins (a hand never goes HAND_OVER past its swing).
const STEER_R := 0.19
const DRIVER_LEAN := 0.6         ## the most a driver bends forward to reach the wheel (rad)
const HAND_BASE := [1.25, -1.25]
const HAND_SWING := [0.65, 0.5]
const HAND_OVER := 0.3
const REGRIP := 0.2
const ENGINE_DB := -9.0          ## the engine at working speed (it idles 5 dB under that)
const ENGINE_TOP := 9.0          ## m/s at which it is flat out

var wear: IceWear                ## lays fresh ice behind it (optional)
var driver: Node3D               ## seated at the wheel: a Fan, or a Skater (optional; see set_driver)
var sweep_half := SWEEP_HALF     ## the strip it lays (the fan contest widens it a little)
var distance := 0.0              ## meters along the pass
var length := 0.0                ## the whole pass

var _pts := PackedVector2Array()
var _cum := PackedFloat32Array()
var _wheels := {}                ## "FL" ... -> Node3D
var _steering: Node3D
var _steer_axis := Vector3(0.0, 0.616, 0.788).normalized()
var _steering_rest := Basis.IDENTITY
var _steer_at := Vector3.ZERO    ## the middle of the wheel's rim (local)
var _hand_off := [0.0, 0.0]      ## where each hand has hold of the rim, from where it first took it (rad)
var _hand_ang := [1.25, -1.25]   ## where each hand is now, round the rim
var _hand_from := [0.0, 0.0]
var _regrip := [0.0, 0.0]        ## s left of a hand's move to a new hold
var _spin := 0.0
var _steer := 0.0
var _last_cond := Vector2.INF
var _engine: AudioStreamPlayer
var _sfx: Node                   ## the Sfx autoload (by path: tool scripts run without its global name)
var _engine_at := Vector3.INF    ## where the machine was a frame ago (its speed sets the engine's note)
var _revs := 0.0                 ## 0 idling .. 1 flat out


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	for k: String in ["FL", "FR", "RL", "RR"]:
		_wheels[k] = model.find_child("Wheel" + k, true, false)
	_steering = model.find_child("Steering", true, false)
	if _steering:
		_steering_rest = _steering.basis
		_steer_at = (global_transform.affine_inverse() * _steering.global_transform).origin
	_build_path()
	place(0.0)
	_start_engine()


## The engine: a loop (assets/sound/zamboni.mp3, cut by tools/cut_sounds.py) that idles low
## and climbs with the machine's speed, a little quieter far from the camera.
func _start_engine() -> void:
	_sfx = get_node_or_null("/root/Sfx")
	var stream: AudioStream = _sfx.stream_of("zamboni") if _sfx else null
	if stream == null:
		return
	_engine = AudioStreamPlayer.new()
	_engine.stream = stream
	_engine.bus = "Effects"
	_engine.volume_db = ENGINE_DB - 5.0
	_engine.pitch_scale = 0.8
	add_child(_engine)
	_engine.play()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_drive(delta)
	if _engine == null:
		return
	var speed := 0.0
	if _engine_at != Vector3.INF:
		speed = global_position.distance_to(_engine_at) / delta
	_engine_at = global_position
	_revs = lerpf(_revs, clampf(speed / ENGINE_TOP, 0.0, 1.0), clampf(delta * 3.0, 0.0, 1.0))
	_engine.pitch_scale = lerpf(0.8, 1.3, _revs)
	var far := clampf(global_position.distance_to(_sfx.listener) * 0.15, 0.0, 8.0)
	_engine.volume_db = ENGINE_DB - 5.0 * (1.0 - minf(_revs * 2.0, 1.0)) - far


## The driver at work (a Fan): hands on the wheel, turning it and taking new holds as it
## goes round, leaning and looking into the turns.
func _drive(delta: float) -> void:
	var f := driver as Fan
	if f == null or not is_instance_valid(f) or _steering == null:
		return
	var turn := _steer * STEERING_RATIO
	var n := _steer_axis
	var up := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
	var left := n.cross(up)
	var grips := []
	for h in 2:
		var base: float = HAND_BASE[h]
		var want: float = base + turn + _hand_off[h]
		var swing: float = HAND_SWING[h]
		var past := absf(want - base) - swing
		if _regrip[h] <= 0.0 and ((past > 0.0 and _regrip[1 - h] <= 0.0) or past > HAND_OVER):
			# (to the far side of its swing, wherever the wheel has carried it)
			_hand_off[h] -= signf(want - base) * (absf(want - base) + swing * 0.7)
			_hand_from[h] = _hand_ang[h]
			_regrip[h] = REGRIP
			want = base + turn + _hand_off[h]
		var lift := 0.0
		if _regrip[h] > 0.0:
			_regrip[h] = maxf(_regrip[h] - delta, 0.0)
			var u: float = 1.0 - _regrip[h] / REGRIP
			u = u * u * (3.0 - 2.0 * u)
			_hand_ang[h] = lerpf(_hand_from[h], want, u)
			lift = sin(u * PI) * 0.04
		else:
			_hand_ang[h] = want
		var radial := up * cos(_hand_ang[h]) + left * sin(_hand_ang[h])
		# The wrist behind the rim and a little outside it; the fingers go forward past its
		# outside and close round the front, the palm in toward the wheel's middle.
		grips.append([_steer_at + radial * (STEER_R + 0.03) + n * (0.075 + lift), (-n - radial * 0.2).normalized(), -radial])
	f.hold(self, grips[0], grips[1])
	f.lean = clampf(f.lean + f.reach_short * 5.0 * delta, 0.0, DRIVER_LEAN)
	f.sway = lerpf(f.sway, clampf(_steer * 0.3, -0.14, 0.14), clampf(delta * 4.0, 0.0, 1.0))
	f.head_turn = lerpf(f.head_turn, clampf(_steer * 1.1, -0.55, 0.55), clampf(delta * 3.0, 0.0, 1.0))


## The trim (the skirt, the stripe round the tank, the conditioner) in the home team's color.
func set_trim(c: Color) -> void:
	var t: StandardMaterial3D = null
	for at: Array in _surfaces("Trim"):
		var m: Material = at[0].mesh.surface_get_material(at[1])
		if t == null and m is StandardMaterial3D:
			t = m.duplicate()
			t.albedo_color = c
		if t:
			at[0].set_surface_override_material(at[1], t)


## The home team's crest on the plates on the tank's sides (none: they stay plain).
func set_logo(tex: Texture2D) -> void:
	if tex == null:
		return
	var m := ShaderMaterial.new()
	m.shader = PLATE_SHADER
	m.set_shader_parameter("logo", tex)
	m.set_shader_parameter("logo_aspect", float(tex.get_width()) / maxf(float(tex.get_height()), 1.0))
	for at: Array in _surfaces("Panel"):
		at[0].set_surface_override_material(at[1], m)


## Every [mesh instance, surface] of the model that wears the material named `mat`.
func _surfaces(mat: String) -> Array:
	var out := []
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m and m.resource_name == mat:
				out.append([mi, i])
	return out


## Seats `who` at the wheel: a Fan (it rides on the machine), or a Skater (kept off the
## physics, and carried along sitting).
func set_driver(who: Node3D) -> void:
	driver = who
	if who is Fan:
		if who.get_parent() == null:
			add_child(who)
		who.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		who.transform = Transform3D(Basis.IDENTITY, FAN_SEAT)
		(who as Fan).sit(Fan.DRIVE_LOOPS)
		(who as Fan).head_lift = 0.8
		return
	var s := who as Skater
	s.frozen = true
	s.set_physics_process(false)
	s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if s.visual:
		s.visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		s.visual.bench_pose(true)
	_seat_driver()


func _seat_driver() -> void:
	var s := driver as Skater
	if s == null or not is_instance_valid(s) or not is_inside_tree():
		return
	s.global_position = global_transform * SEAT
	s.heading = -global_basis.z
	s.velocity = Vector3.ZERO


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
