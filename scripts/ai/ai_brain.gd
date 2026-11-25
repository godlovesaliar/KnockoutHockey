class_name AIBrain
extends Brain
## Plays the role TeamAI assigns. Movement runs every tick; decisions (shoot, pass,
## deke, check, poke) only every think interval, which is shorter on higher difficulty.

var team_ai: TeamAI
var _think_left := 0.0
var _shoot_hold := -1.0         ## > 0 while holding shoot for a wrist/slap shot
var _shoot_aim := Vector3.ZERO
var _one_timer_flight := -1
var _rng := RandomNumberGenerator.new()
var _pin_hold := 0.0            ## > 0: staying on the check button (a check near the boards that may become a pin)
var _battle_wait := 0.0         ## board battle: s to the next push or dig
var _kick_at := -2.0            ## pinned: the battle time to try kicking the puck out (-1: won't; -2: not in one)


func _init(p_team_ai: TeamAI, seed_value := 0) -> void:
	team_ai = p_team_ai
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func update(s: Skater, i: SkaterIntent, delta: float) -> void:
	var diff := team_ai.sharpness()
	_think_left -= delta
	var think := _think_left <= 0.0
	if think:
		_think_left = lerpf(0.26, 0.08, diff) * _rng.randf_range(0.8, 1.2)

	if s.battle != null and (s.state == Skater.State.PIN or s.state == Skater.State.PINNED):
		_battle(s, i, delta)
		return
	_kick_at = -2.0
	if _pin_hold > 0.0:
		_pin_hold -= delta
		i.check_held = true

	# Finish a shot already in progress.
	if _shoot_hold >= 0.0:
		_shoot_hold -= delta
		i.move = _shoot_aim
		i.shoot_held = _shoot_hold > 0.0
		i.shoot_up = _shoot_hold <= 0.0
		if _shoot_hold <= 0.0:
			_shoot_hold = -1.0
		return
	if not s.can_act():
		return

	var puck := team_ai.puck
	i.face = puck.global_position - s.global_position
	i.face.y = 0.0
	match team_ai.role_of(s):
		TeamAI.Role.CARRIER:
			_carry(s, i, think)
		TeamAI.Role.RECEIVE:
			_receive(s, i)
		TeamAI.Role.SUPPORT_SLOT:
			_arrive(s, i, team_ai.onside(team_ai.slot_spot()), 3.0)
		TeamAI.Role.SUPPORT_POINT:
			_arrive(s, i, team_ai.onside(team_ai.point_spot()), 3.0)
		TeamAI.Role.SUPPORT_POINT2:
			_arrive(s, i, team_ai.onside(team_ai.point2_spot()), 3.0)
		TeamAI.Role.SUPPORT_NET:
			_arrive(s, i, team_ai.onside(team_ai.net_front_spot()), 2.0)
		TeamAI.Role.CHANGE:
			_arrive(s, i, team_ai.bench_gate, 1.0)
			i.turbo = true
		TeamAI.Role.CHASE:
			_chase(s, i)
		TeamAI.Role.PRESSURE:
			_pressure(s, i, think)
		TeamAI.Role.COVER_SLOT:
			_arrive(s, i, team_ai.defensive_slot(), 2.5)
		TeamAI.Role.COVER_MAN:
			_arrive(s, i, team_ai.mark_spot(s), 2.0)
			_maybe_hit_nearby(s, i, think)


func _arrive(s: Skater, i: SkaterIntent, target: Vector3, slow_radius: float) -> void:
	var c := RinkSpec.clamp_inside(target.x, target.z, 1.0)
	var goal := Vector3(c.x, 0.0, c.y)
	var d := Vector2(goal.x - s.global_position.x, goal.z - s.global_position.z).length()
	if d < 0.4:
		return
	var to := _route(s, goal) - s.global_position
	to.y = 0.0
	i.move = to.normalized() * clampf(d / slow_radius, 0.25, 1.0)
	i.turbo = d > 12.0 and s.stamina > 0.5


## Where to head for `target` without skating through a net: the target, or the corner
## of a net that's in the way.
func _route(s: Skater, target: Vector3) -> Vector3:
	if s.rink == null:
		return target
	for net in s.rink.nets:
		target = net.detour(s.global_position, target, 0.35)
	return target


func _chase(s: Skater, i: SkaterIntent) -> void:
	var puck := team_ai.puck
	var d := s.global_position.distance_to(puck.global_position)
	var t := minf(d / maxf(s.top_speed(), 1.0), 1.0)
	var target := puck.global_position + puck.velocity * t * 0.7
	var c := RinkSpec.clamp_inside(target.x, target.z, 0.5)
	var to := _route(s, Vector3(c.x, 0.0, c.y)) - s.global_position
	to.y = 0.0
	if to.length() > 0.05:
		i.move = to.normalized()
	i.turbo = d > 5.0 and s.stamina > 0.3


func _receive(s: Skater, i: SkaterIntent) -> void:
	var puck := team_ai.puck
	# In shooting range? Maybe wind up for a one-timer.
	if _one_timer_flight != puck.flight:
		_one_timer_flight = puck.flight
		var net := s.attacking_net()
		var in_range := s.global_position.distance_to(net.global_position) < 12.0
		s.set_meta("ai_one_timer", in_range and _rng.randf() < lerpf(0.3, 0.8, team_ai.sharpness()))
	if s.get_meta("ai_one_timer", false):
		i.shoot_held = true
		i.move = (s.attacking_net().global_position - s.global_position).normalized() * 0.01


func _carry(s: Skater, i: SkaterIntent, think: bool) -> void:
	var net := s.attacking_net()
	var out := net.global_basis.z
	var to_net := net.global_position - s.global_position
	to_net.y = 0.0
	var dist := to_net.length()
	var target := _route(s, net.global_position + out * (2.5 if dist < 9.0 else 6.0))
	var desired := (target - s.global_position)
	desired.y = 0.0
	desired = desired.normalized()
	var nearest := INF
	var ahead := INF
	for o in team_ai.opponents:
		var r := o.global_position - s.global_position
		r.y = 0.0
		var d := r.length()
		nearest = minf(nearest, d)
		if d > 0.01 and d < 4.5 and desired.dot(r / d) > 0.3:
			ahead = minf(ahead, d)
			var side := signf(desired.cross(r).y)
			if side == 0.0:
				side = 1.0
			desired += desired.cross(Vector3.UP) * side * (4.5 - d) / 4.5 * 1.4
	i.move = desired.normalized()
	i.turbo = nearest > 3.0 and s.stamina > 0.4 and dist > 12.0

	if not think:
		return
	var from_net := s.global_position - net.global_position
	from_net.y = 0.0
	var angle_ok := out.angle_to(from_net) < deg_to_rad(65.0)
	var diff := team_ai.sharpness()
	if team_ai.shootout:
		if dist < 7.5 and dist > 4.0 and _rng.randf() < 0.25:
			i.deke_down = true
			return
		if dist < 6.0 or (dist < 11.0 and _rng.randf() < 0.12):
			_shoot(s, i, net, dist < 8.0)
		return
	if team_ai.net_empty() and dist < 30.0 and ahead > 2.0 and (angle_ok or dist < 12.0):
		_shoot(s, i, net, dist < 9.0)   # an empty net: let it go from anywhere with a lane
		return
	if dist < 14.0 and angle_ok and (dist < 9.0 or ahead > 3.0 or _rng.randf() < 0.3):
		_shoot(s, i, net, dist < 9.0 or nearest < 3.0)
		return
	var outlet := _best_outlet(s)
	if ahead < 2.6 and outlet and _rng.randf() < lerpf(0.4, 0.8, diff):
		_pass_to(s, i, outlet)
		return
	if ahead < 2.2 and _rng.randf() < lerpf(0.2, 0.6, diff):
		i.deke_down = true
		return
	if outlet and dist > 10.0 and _rng.randf() < 0.08:
		var od := outlet.global_position.distance_to(net.global_position)
		if od < dist - 3.0:
			_pass_to(s, i, outlet)


func _shoot(s: Skater, i: SkaterIntent, net: Net, quick: bool) -> void:
	# Aim away from the goalie.
	var gx := 0.0
	if team_ai.opp_goalie:
		gx = team_ai.opp_goalie.global_position.x - net.global_position.x
	var to_net := net.global_position - s.global_position
	to_net.y = 0.0
	var side := -signf(gx) if absf(gx) > 0.1 else (1.0 if _rng.randf() < 0.5 else -1.0)
	if team_ai.net_empty():
		side = 0.0   # nobody home: straight at the middle
	# Up the ice (toward the net) aims high, back aims low: mix it up.
	var up := _rng.randf_range(-0.9, 0.45) * signf(to_net.z)
	_shoot_aim = to_net.normalized() * 0.5 + Vector3(side * 0.85, 0, up)
	i.move = _shoot_aim
	i.shoot_down = true
	i.shoot_held = true
	_shoot_hold = 0.05 if quick else _rng.randf_range(0.3, 0.6)


func _pass_to(s: Skater, i: SkaterIntent, mate: Skater) -> void:
	var dir := mate.global_position - s.global_position
	dir.y = 0.0
	i.move = dir.normalized()
	i.pass_down = true
	i.pass_held = true
	i.pass_up = true


func _best_outlet(s: Skater) -> Skater:
	var best: Skater = null
	var best_score := -INF
	var net := s.attacking_net().global_position
	for m in s.teammates:
		if m == s or m.is_down():
			continue
		var open := team_ai.pass_openness(s, m)
		if open < 2.5:
			continue
		var score := open - m.global_position.distance_to(net) * 0.15
		if score > best_score:
			best_score = score
			best = m
	return best


func _pressure(s: Skater, i: SkaterIntent, think: bool) -> void:
	var c := team_ai.puck.carrier
	if c == null:
		return
	# A carrier on the boards: all but the most aggressive come at their open-ice shoulder
	# and ease up on the way in, to pin them there instead of running them (speed decides
	# which it is).
	var cp := c.global_position
	var on_boards := not (c is Goalie) and RinkSpec.sdf(cp.x, cp.z) > -BoardBattle.BOARD_DIST + 0.1
	var wall := BoardBattle.wall_out(cp) if on_boards else Vector3.ZERO
	var to_pin := on_boards and s.stats.aggression < 75.0 and s._pin_cooldown <= 0.0
	var target := cp + c.velocity * 0.25
	if to_pin:
		target -= wall * 0.7
	var to := target - s.global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.05:
		var way := _route(s, target) - s.global_position
		way.y = 0.0
		i.move = way.normalized() if way.length() > 0.05 else to / d
	i.turbo = d > 6.0 and s.stamina > 0.3
	if to_pin and d < 3.5:
		i.move *= 0.55
		i.turbo = false
	if not think:
		return
	var dir := to / maxf(d, 0.01)
	var closing := (s.velocity - c.velocity).dot(dir)
	var aggression := s.stats.aggression / 99.0
	var at_c := cp - s.global_position
	at_c.y = 0.0
	var dc := at_c.length()
	var dir_c := at_c / maxf(dc, 0.01)
	var closing_c := (s.velocity - c.velocity).dot(dir_c)
	if to_pin and dc < 1.6 and dir_c.dot(wall) > BoardBattle.INTO_BOARDS + 0.1 and closing_c > 0.0 			and closing_c < BoardBattle.MAX_CLOSING - 0.5 and _rng.randf() < 0.5:
		# On their open-ice side and not making a run at them: lean in (straight at them,
		# staying on the button through the contact).
		i.move = dir_c
		i.check_down = true
		i.check_held = true
		_pin_hold = 0.7
	elif d < 1.9 and closing > 2.0 and _rng.randf() < lerpf(0.25, 0.7, aggression):
		i.check_down = true
	elif d < 1.8 and _rng.randf() < lerpf(0.35, 0.75, team_ai.sharpness()):
		i.deke_down = true # poke check (deke button without the puck)


func _maybe_hit_nearby(s: Skater, i: SkaterIntent, think: bool) -> void:
	if not think:
		return
	var c := team_ai.puck.carrier
	if c == null or c.team == s.team or c is Goalie:
		return
	var to := c.global_position - s.global_position
	to.y = 0.0
	if to.length() < 1.8 and _rng.randf() < 0.3:
		i.move = to.normalized()
		i.check_down = true


## In a board battle (BoardBattle). Pinning: stays on the button and digs for the puck
## now and then. Pinned: pushes back at a rate set by strength, and sometimes kicks the
## puck up the boards toward the nearest teammate.
func _battle(s: Skater, i: SkaterIntent, delta: float) -> void:
	var b := s.battle
	_battle_wait -= delta
	if s.state == Skater.State.PIN:
		i.check_held = true
		if _battle_wait <= 0.0:
			_battle_wait = lerpf(0.9, 0.6, team_ai.sharpness()) * _rng.randf_range(0.8, 1.3)
			i.deke_down = true
		return
	if _kick_at < -1.5:
		_kick_at = _rng.randf_range(0.5, 1.6) if _rng.randf() < 0.4 else -1.0
	if _kick_at >= 0.0 and b.time >= _kick_at:
		_kick_at = -1.0
		i.pass_down = true
		var best := INF
		for m in s.teammates:
			if not is_instance_valid(m) or m == s or m is Goalie or m.is_down():
				continue
			var to := m.global_position - s.global_position
			to.y = 0.0
			if to.length() < best:
				best = to.length()
				i.move = to.normalized()
	elif _battle_wait <= 0.0:
		_battle_wait = lerpf(0.4, 0.22, s.stats.strength / 99.0) * _rng.randf_range(0.8, 1.3)
		i.check_down = true
