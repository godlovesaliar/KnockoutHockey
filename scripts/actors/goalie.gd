class_name Goalie
extends Skater
## AI goalie. Holds an angle in the crease, reacts to shots after a reflex delay,
## and resolves saves where the puck crosses the goalie's plane (glove, blocker,
## pads or body). Catches and covers hold the puck. When a human controls this team,
## they take the goalie while it holds the puck: A pass, X clear, Y cover.
##
## Works in the defended net's local frame: goal line at z = 0, +z out toward the ice.

signal save_made(goalie: Goalie, kind: StringName)   ## &"rebound", &"catch", &"cover"
signal froze_puck(goalie: Goalie)

enum G { POSITION, REACT, HOLD }

const BODY_HALF := 0.36           ## half-width covered by the body/pads without reaching
const SAVE_HEIGHT := 1.35
const HUMAN_HOLD_LIMIT := 3.0

var net: Net
var g := G.POSITION
var save_point := Vector2.ZERO    ## (x offset from goalie, height) of the last save, for the visual
var save_anim := 0.0              ## 1 right after a save, decays to 0
var butterfly := false

var _tracked_flight := -1
var _resolved_flight := -1
var _react_left := 0.0
var _hold_time := 0.0
var _frozen_sent := false


func _ready() -> void:
	super()
	collision_layer = 1 << 6      # goalies: skaters bump them, the puck doesn't (saves are resolved in code)
	collision_mask = 1 | (1 << 1) | (1 << 3)
	set_meta("surface", "body")


func _make_visual() -> SkaterVisual:
	return GoalieVisual.new()


func reset_in_net() -> void:
	g = G.POSITION
	_frozen_sent = false
	_hold_time = 0.0
	save_anim = 0.0
	if net:
		var out := net.global_basis.z
		place(net.global_position + out * 0.7, out)


func puck_anchor() -> Vector3:
	var p := global_position + heading * 0.55
	return Vector3(p.x, RinkSpec.PUCK_THICKNESS * 0.5, p.z)


func _physics_process(delta: float) -> void:
	intent.clear()
	if brain and g == G.HOLD:
		brain.update(self, intent, delta)
	save_anim = maxf(0.0, save_anim - delta * 2.2)
	if net == null or frozen:
		velocity = Vector3.ZERO
		return
	if g == G.HOLD:
		if not has_puck():
			g = G.POSITION
		else:
			velocity = Vector3.ZERO
			_hold(delta)
			return
	_track_puck(delta)
	_move_goalie(delta)
	_check_save()
	_try_cover()


# --- Positioning ---------------------------------------------------------------

func _local(p: Vector3) -> Vector3:
	return net.to_local(p)


func _local_vel(v: Vector3) -> Vector3:
	return net.global_basis.inverse() * v


func _angle_target() -> Vector3:
	var pl := _local(puck.global_position)
	var half := RinkSpec.NET_WIDTH * 0.5
	if pl.z < 0.25: # puck behind the goal line: hug the near post
		return Vector3(signf(pl.x) * (half - 0.3), 0.0, 0.35)
	var anchor := Vector3(0.0, 0.0, -1.2)
	var d := Vector3(pl.x, 0.0, pl.z) - anchor
	var depth := PlayerStats.lerp_stat(stats.positioning, 0.45, 1.0)
	var far := clampf(remap(pl.z, 3.0, 15.0, 0.6, 1.0), 0.6, 1.0)
	var t := anchor + d.normalized() * (1.2 + depth * far)
	t.x = clampf(t.x, -(half + 0.1), half + 0.1)
	t.z = clampf(t.z, 0.3, 1.4)
	return t


func _track_puck(delta: float) -> void:
	if puck.carrier != null or puck.dead:
		if g == G.REACT:
			g = G.POSITION
		return
	if puck.flight != _tracked_flight:
		_tracked_flight = puck.flight
		g = G.POSITION
		var pl := _local(puck.global_position)
		var vl := _local_vel(puck.velocity)
		if vl.z < -4.0 and pl.z > 0.3:
			var t := pl.z / -vl.z
			var cx := pl.x + vl.x * t
			var cy := pl.y + vl.y * t - (0.0 if puck.on_ice else 0.5 * Puck.GRAVITY * t * t)
			if absf(cx) < RinkSpec.NET_WIDTH * 0.5 + 0.6 and cy < RinkSpec.NET_HEIGHT + 0.5:
				g = G.REACT
				_react_left = PlayerStats.lerp_stat(stats.reflexes, 0.32, 0.12)
	if g == G.REACT:
		_react_left -= delta


func _move_goalie(delta: float) -> void:
	var gl := _local(global_position)
	var target := _angle_target()
	var speed := PlayerStats.lerp_stat(stats.positioning, 2.4, 3.6)
	# Go get a slow loose puck sitting in or near the crease.
	var pl0 := _local(puck.global_position)
	if puck.carrier == null and not puck.dead and puck.speed() < 4.0 and puck.can_pick(self) 			and pl0.z > -0.2 and pl0.z < 2.6 and absf(pl0.x) < 2.2:
		target = Vector3(pl0.x, 0.0, pl0.z) - Vector3(0, 0, 0.45)

	if g == G.REACT and _react_left <= 0.0:
		var pl := _local(puck.global_position)
		var vl := _local_vel(puck.velocity)
		if vl.z < -1.0:
			var t := maxf(0.0, (pl.z - gl.z) / -vl.z)
			target = Vector3(clampf(pl.x + vl.x * t, -1.4, 1.4), 0.0, gl.z)
			speed = PlayerStats.lerp_stat(stats.positioning, 5.0, 8.0)
	# Never behind the goal line: from there the net is in the way. A puck sitting on the
	# line or just in the net is still in reach (`_try_cover`) from out front.
	target.z = maxf(target.z, 0.3)
	var to := net.to_global(target) - global_position
	to.y = 0.0
	velocity = to / delta if to.length() < speed * delta else to.normalized() * speed
	move_and_slide()
	global_position.y = 0.0
	var face := puck.global_position - global_position
	face.y = 0.0
	if face.length() > 0.1:
		heading = Skater._rotate_toward(heading, face.normalized(), 10.0 * delta)
	butterfly = g == G.REACT and _react_left <= 0.0 and puck.on_ice


# --- Saves ---------------------------------------------------------------------

func _check_save() -> void:
	if puck.carrier != null or puck.dead or _resolved_flight == puck.flight:
		return
	var pl := _local(puck.global_position)
	var vl := _local_vel(puck.velocity)
	if vl.z > -2.0 or pl.z < 0.0:
		return
	var plane := _local(global_position).z
	var dt := get_physics_process_delta_time()
	var next_z := pl.z + vl.z * dt
	# Resolve when the puck reaches the goalie's plane this tick (or already slipped past it).
	if not ((pl.z > plane and next_z <= plane) or pl.z <= plane):
		return
	_resolved_flight = puck.flight
	var t := maxf(0.0, (pl.z - plane) / -vl.z)
	var px := pl.x + vl.x * t
	var py := maxf(pl.y + vl.y * t, 0.0)
	if absf(px) > RinkSpec.NET_WIDTH * 0.5 + 0.3 or py > RinkSpec.NET_HEIGHT + 0.3:
		return # wide or high: let it go
	var gx := _local(global_position).x
	var dx := px - gx
	var reacted := g == G.REACT and _react_left <= 0.0
	var glove_side := dx > 0.0 # the glove is on the goalie's left = +x in the net frame
	var reach: float
	if py < 0.45:
		reach = PlayerStats.lerp_stat(stats.pads, 0.22, 0.48)
	elif glove_side:
		reach = PlayerStats.lerp_stat(stats.glove, 0.25, 0.52)
	else:
		reach = PlayerStats.lerp_stat(stats.blocker, 0.25, 0.52)
	var chance := 0.0
	if absf(dx) < BODY_HALF and py < SAVE_HEIGHT:
		chance = 0.96 if reacted else 0.85
	elif reacted and absf(dx) < BODY_HALF + reach and py < SAVE_HEIGHT + 0.25:
		chance = lerpf(0.85, 0.35, (absf(dx) - BODY_HALF) / reach)
	chance -= clampf((puck.speed() - 25.0) * 0.006, 0.0, 0.12)
	if _rng.randf() >= chance:
		return
	_make_save(px, py, plane, dx, glove_side)


func _make_save(px: float, py: float, plane: float, dx: float, glove_side: bool) -> void:
	var spd := puck.speed()
	save_point = Vector2(dx, py)
	save_anim = 1.0
	var y := clampf(py, puck.rest_y, RinkSpec.NET_HEIGHT)
	puck.global_position = net.to_global(Vector3(px, y, plane + 0.1))
	var catch := py > 0.55 and glove_side and spd < 42.0 \
			and _rng.randf() < PlayerStats.lerp_stat(stats.glove, 0.35, 0.7)
	var cover := py < 0.3 and spd < 18.0 and _rng.randf() < 0.5
	if catch or cover:
		puck.velocity = Vector3.ZERO
		puck.attach(self)
		_begin_hold()
		save_made.emit(self, &"catch" if catch else &"cover")
		return
	var ctrl := PlayerStats.lerp_stat(stats.rebound_control, 0.45, 0.2)
	var out := Vector3(_rng.randf_range(-0.9, 0.9), 0.0, 1.0).normalized() * spd * ctrl
	out.y = 1.5 if py > 0.6 else 0.0
	puck.rebound(net.global_basis * out, self)
	save_made.emit(self, &"rebound")


func _try_cover() -> void:
	if puck.carrier != null or not puck.can_pick(self) or puck.speed() > 4.0:
		return
	var pl := _local(puck.global_position)
	if pl.z < -0.3 or pl.z > 2.2 or pl.y > 0.9:
		return
	if Vector2(puck.global_position.x - global_position.x, puck.global_position.z - global_position.z).length() > 0.9:
		return
	puck.attach(self)
	_begin_hold()
	save_made.emit(self, &"cover")


# --- Holding the puck ------------------------------------------------------------

func _begin_hold() -> void:
	g = G.HOLD
	_hold_time = 0.0
	_frozen_sent = false


func _hold(delta: float) -> void:
	_hold_time += delta
	if _frozen_sent:
		return
	if is_human:
		if intent.pass_down:
			_play_out(intent.move if intent.move.length() > 0.3 else net.global_basis.z, false)
		elif intent.shoot_down:
			_play_out(intent.move if intent.move.length() > 0.3 else net.global_basis.z, true)
		elif intent.deke_down or _hold_time > HUMAN_HOLD_LIMIT:
			_freeze()
		return
	if _hold_time < 0.7:
		return
	var threat := INF
	for o in opponents:
		threat = minf(threat, o.global_position.distance_to(global_position))
	var outlet := _best_outlet()
	if threat > 7.0 and outlet:
		var dir := outlet.global_position - global_position
		dir.y = 0.0
		_play_out(dir, false)
	else:
		_freeze()


func _best_outlet() -> Skater:
	var best: Skater = null
	var best_open := 3.0
	for m in teammates:
		if m == self or m.is_down():
			continue
		var open := INF
		for o in opponents:
			open = minf(open, o.global_position.distance_to(m.global_position))
		if open > best_open:
			best_open = open
			best = m
	return best


func _play_out(dir: Vector3, clear: bool) -> void:
	intent.move = dir.normalized()
	puck.global_position = puck_anchor()
	g = G.POSITION
	if clear:
		_fire_shot(&"wrist", 0.0)
	else:
		_fire_pass(false)


func _freeze() -> void:
	_frozen_sent = true
	froze_puck.emit(self)
