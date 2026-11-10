extends Node3D
## Headless skater regression test (skating feel, possession, passing, shooting). Run:
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/SkaterSelfTest.tscn
## Exits with code 0 on pass, 1 on failure.

const RINK_SCENE := preload("res://scenes/match/Rink.tscn")
const PUCK_SCENE := preload("res://scenes/match/Puck.tscn")
const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const DT := 1.0 / 120.0

var rink: Rink
var puck: Puck
var failures := 0
var shots := []
var goals := []
var passes := []


func _ready() -> void:
	rink = RINK_SCENE.instantiate()
	add_child(rink)
	puck = PUCK_SCENE.instantiate()
	add_child(puck)
	rink.goal_scored.connect(func(side: int) -> void: goals.append(side))
	await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	await _run()
	print("SELFTEST %s — %d failure(s), %.1f s" % ["PASS" if failures == 0 else "FAIL", failures, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok    ", msg)
	else:
		failures += 1
		print("  FAIL  ", msg)


static func edge(t: float, at: float) -> bool:
	return t >= at and t - DT < at


func _spawn(team: int, pos: Vector3, face: Vector3, fn: Callable) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate()
	s.team = team
	s.stats = PlayerStats.new()
	s.puck = puck
	s.rink = rink
	add_child(s)
	s.place(pos, face)
	s.seed_rng(7)
	s.brain = ScriptBrain.new(fn)
	s.shot_released.connect(func(sk: Skater, kind: StringName, spd: float) -> void:
		shots.append({"by": sk, "kind": kind, "speed": spd}))
	s.pass_released.connect(func(sk: Skater, rec: Skater) -> void: passes.append({"by": sk, "to": rec}))
	return s


func _reset() -> void:
	puck.place(Vector3(0, 0, 0))
	for c in get_children():
		if c is Skater:
			c.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	puck.place(Vector3(0, 0, 0))
	rink.rearm_nets()
	shots.clear()
	goals.clear()
	passes.clear()


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _give_puck(s: Skater) -> void:
	puck.place(s.puck_anchor())
	puck.attach(s)


func _link(list: Array[Skater]) -> void:
	for s in list:
		s.teammates = list


func _run() -> void:
	print("Skating")
	var s := _spawn(0, Vector3(0, 0, 20), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.FORWARD)
	var top := s.top_speed()
	var t90 := -1.0
	for k in 240:
		await get_tree().physics_frame
		if t90 < 0.0 and s.flat_speed() >= 0.9 * top:
			t90 = (k + 1) * DT
	_check(t90 > 0.3 and t90 < 1.2, "reaches 90%% of top speed in %.2f s (top %.1f m/s)" % [t90, top])
	_check(absf(s.flat_speed() - top) < 0.25, "settles at top speed (%.2f m/s)" % s.flat_speed())
	await _reset()

	s = _spawn(0, Vector3(0, 0, 25), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.FORWARD
		i.turbo = true)
	await _ticks(180)
	_check(s.flat_speed() > top * 1.15, "turbo raises top speed (%.2f vs %.2f m/s)" % [s.flat_speed(), top])
	_check(s.stamina < 0.6, "turbo drains stamina (%.2f)" % s.stamina)
	await _reset()

	s = _spawn(0, Vector3(0, 0, 25), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3.FORWARD if t < 1.3 else Vector3.BACK)
	await _ticks(156)
	var saw_stop := false
	var t_stop := -1.0
	for k in 120:
		await get_tree().physics_frame
		saw_stop = saw_stop or s.stopping
		if t_stop < 0.0 and s.flat_speed() < 1.0:
			t_stop = (k + 1) * DT
	_check(saw_stop and t_stop > 0.0 and t_stop < 0.6, "hockey stop from top speed in %.2f s" % t_stop)
	_check(s.velocity.z > 2.0, "then skates the other way (vz %.1f)" % s.velocity.z)
	await _reset()

	# Caught mid hockey stop by a whistle and walked to the box: the spray mustn't follow.
	s = _spawn(0, Vector3(0, 0, 25), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3.FORWARD if t < 1.3 else Vector3.BACK)
	await _ticks(156)
	var caught := false
	for k in 30:
		await get_tree().physics_frame
		if s.stopping:
			caught = true
			break
	s.walk([s.global_position + Vector3(4, 0, 0)], 3.0, Vector3.LEFT)
	await _ticks(10)
	_check(caught and not s.stopping and not s.visual.spray.emitting, "a scripted walk ends the hockey stop's spray")
	await _reset()

	s = _spawn(0, Vector3(-6, 0, 25), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3.FORWARD if t < 1.3 else Vector3.RIGHT)
	await _ticks(156)
	var t_turn := -1.0
	for k in 120:
		await get_tree().physics_frame
		if t_turn < 0.0 and s.heading.angle_to(Vector3.RIGHT) < deg_to_rad(10.0):
			t_turn = (k + 1) * DT
	_check(t_turn > 0.0 and t_turn < 0.7, "90-degree turn at speed in %.2f s (keeps %.1f m/s)" % [t_turn, s.flat_speed()])
	await _reset()

	print("Possession")
	s = _spawn(0, Vector3(0, 0, 10), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.FORWARD)
	puck.place(Vector3(0, 0, 5))
	await _ticks(180)
	_check(s.has_puck(), "skating onto a loose puck picks it up")
	await _reset()

	s = _spawn(0, Vector3(8, 0, 0), Vector3.RIGHT, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3(1, 0, -0.3).normalized())
	_give_puck(s)
	var worst := -INF
	for k in 240:
		await get_tree().physics_frame
		worst = maxf(worst, RinkSpec.sdf(puck.global_position.x, puck.global_position.z))
	_check(worst < 0.0, "carrying the puck into the boards keeps it in the rink (worst sdf %.3f)" % worst)
	_check(RinkSpec.sdf(s.global_position.x, s.global_position.z) < 0.0, "skater stays inside the boards")
	await _reset()

	s = _spawn(0, Vector3(0, 0, 15), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3.FORWARD
		i.deke_down = edge(t, 0.5))
	_give_puck(s)
	await _ticks(60)
	var x0 := s.global_position.x
	await _ticks(48)
	_check(absf(s.global_position.x - x0) > 0.4 and s.has_puck(), "deke jukes sideways (%.2f m) and keeps the puck" % absf(s.global_position.x - x0))
	await _reset()

	print("Passing")
	var idle := func(sk: Skater, i: SkaterIntent, _t: float) -> void:
		i.face = sk.puck.global_position - sk.global_position
	var passer := _spawn(0, Vector3(0, 0, 0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3(6, 0, -8).normalized() * 0.2
		i.pass_down = edge(t, 0.3)
		i.pass_held = i.pass_down
		i.pass_up = i.pass_down)
	var rec := _spawn(0, Vector3(6, 0, -8), Vector3.BACK, idle)
	_link([passer, rec])
	_give_puck(passer)
	await _ticks(300)
	_check(passes.size() == 1 and passes[0].to == rec, "tap pass targets the teammate in the stick direction")
	_check(rec.has_puck(), "teammate receives the pass")
	await _reset()

	passer = _spawn(0, Vector3(0, 0, 0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3(-5, 0, -12).normalized() * 0.2
		i.pass_down = edge(t, 0.3)
		i.pass_held = t >= 0.3 and t < 0.6
		i.pass_up = edge(t, 0.6))
	rec = _spawn(0, Vector3(-5, 0, -12), Vector3.BACK, idle)
	_link([passer, rec])
	_give_puck(passer)
	var max_y := 0.0
	for k in 360:
		await get_tree().physics_frame
		max_y = maxf(max_y, puck.global_position.y)
	_check(max_y > 0.2, "held pass is a saucer (peak %.2f m)" % max_y)
	_check(rec.has_puck(), "saucer pass is received")
	await _reset()

	# The stick comes back to center a moment before the pass button: the pass still
	# goes where the stick pointed, not straight ahead.
	passer = _spawn(0, Vector3(0, 0, 0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3.FORWARD if t < 0.6 else (Vector3.LEFT if t < 0.8 else Vector3.ZERO)
		i.pass_down = edge(t, 0.9)
		i.pass_held = i.pass_down
		i.pass_up = i.pass_down)
	var ahead := _spawn(0, Vector3(0, 0, -16), Vector3.BACK, idle)
	rec = _spawn(0, Vector3(-9, 0, -4), Vector3.RIGHT, idle)
	_link([passer, ahead, rec])
	_give_puck(passer)
	await _ticks(300)
	_check(passes.size() == 1 and passes[0].to == rec, "stick released before the pass button: still passes to the side")
	_check(rec.has_puck(), "the side teammate receives it")
	await _reset()

	# A sideways pass to a teammate skating up ice is led a little and caught.
	passer = _spawn(0, Vector3(0, 0, 0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3.LEFT * 0.4 if t < 0.5 else Vector3.ZERO
		i.pass_down = edge(t, 0.5)
		i.pass_held = i.pass_down
		i.pass_up = i.pass_down)
	rec = _spawn(0, Vector3(-9, 0, 4), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.FORWARD)
	_link([passer, rec])
	_give_puck(passer)
	await _ticks(240)
	_check(rec.has_puck(), "a pass to a teammate skating up ice is caught")
	await _reset()

	print("Skating backwards")
	s = _spawn(0, Vector3(0, 0, 0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.BACK
		i.backward = true)
	await _ticks(150)
	_check(s.velocity.z > 3.0, "holding backwards moves toward the stick (vz %.1f)" % s.velocity.z)
	_check(s.heading.z < -0.8, "while still facing up ice (heading z %.2f)" % s.heading.z)
	_check(s.flat_speed() < s.top_speed() + 0.1 and s.top_speed() < PlayerStats.lerp_stat(s.stats.speed, 7.3, 9.7) * 0.8, "and slower than skating forward (%.1f m/s)" % s.flat_speed())
	await _reset()

	print("Shooting (empty net)")
	s = _spawn(0, Vector3(0, 0, -17), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.shoot_down = edge(t, 0.2)
		i.shoot_held = t >= 0.2 and t < 0.25
		i.shoot_up = edge(t, 0.25))
	_give_puck(s)
	await _ticks(300)
	_check(shots.size() == 1 and shots[0].kind == &"wrist", "tap = wrist shot (%s)" % [shots])
	_check(shots.size() == 1 and shots[0].speed > 21.0 and shots[0].speed < 33.0, "wrist shot speed %.1f m/s" % (shots[0].speed if shots else 0.0))
	_check(goals == [1], "wrist shot from the slot scores on the -Z net (goals %s)" % [goals])
	await _reset()

	s = _spawn(0, Vector3(3, 0, -12), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.shoot_down = edge(t, 0.2)
		i.shoot_held = t >= 0.2 and t < 1.0
		i.shoot_up = edge(t, 1.0))
	_give_puck(s)
	await _ticks(300)
	_check(shots.size() == 1 and shots[0].kind == &"slap" and shots[0].speed > 33.0, "held shot = full slap shot (%s)" % [shots])
	_check(goals == [1], "slap shot scores (goals %s)" % [goals])
	await _reset()

	passer = _spawn(0, Vector3(-8, 0, -14), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.move = Vector3(12, 0, -4).normalized() * 0.2
		i.pass_down = edge(t, 0.3)
		i.pass_held = i.pass_down
		i.pass_up = i.pass_down)
	rec = _spawn(0, Vector3(4, 0, -18), Vector3.LEFT, func(sk: Skater, i: SkaterIntent, t: float) -> void:
		i.face = sk.puck.global_position - sk.global_position
		i.shoot_down = edge(t, 0.1)
		i.shoot_held = t >= 0.1)
	_link([passer, rec])
	_give_puck(passer)
	await _ticks(360)
	var one_timer := shots.filter(func(e: Dictionary) -> bool: return e.kind == &"one_timer" and e.by == rec)
	_check(one_timer.size() == 1, "holding shoot as a pass arrives fires a one-timer (%s)" % [shots])
	_check(goals == [1], "one-timer scores (goals %s)" % [goals])
	await _reset()

	print("Control switching")
	var a := _spawn(0, Vector3(0, 0, 10), Vector3.FORWARD, idle)
	var b := _spawn(0, Vector3(5, 0, -5), Vector3.FORWARD, idle)
	a.ai_brain = a.brain
	b.ai_brain = b.brain
	var both: Array[Skater] = [a, b]
	var control := TeamControl.new(0, both, both, [HumanBrain.new()] as Array[HumanBrain], puck)
	control.set_controlled(control.primary(), a)
	puck.place(Vector3(5, 0, -3))
	await get_tree().physics_frame
	a.switch_requested.emit(a)
	_check(control.controlled_skater() == b and b.is_human and not a.is_human, "switch picks the skater nearest the loose puck")
	_give_puck(a)
	_check(control.controlled_skater() == a, "gaining the puck takes control")

	print("Two humans on one team")
	var c3 := _spawn(0, Vector3(-5, 0, 0), Vector3.FORWARD, idle)
	c3.ai_brain = c3.brain
	var trio: Array[Skater] = [a, b, c3]
	var h1 := HumanBrain.new(HumanBrain.Kind.KB1, 0, 0)
	var h2 := HumanBrain.new(HumanBrain.Kind.KB2, 0, 1)
	var duo := TeamControl.new(0, trio, trio, [h1, h2] as Array[HumanBrain], puck)
	duo.reset_to(trio)
	_check(duo.skater_of(h1) != duo.skater_of(h2) and duo.skater_of(h1) != null and duo.skater_of(h2) != null, "each human gets their own skater")
	var p2_skater := duo.skater_of(h2)
	duo.set_controlled(h1, p2_skater)
	_check(duo.skater_of(h1) != p2_skater, "a human can't take another human's skater")
	var free_one: Skater = trio.filter(func(x: Skater) -> bool: return duo.human_of(x) == null)[0]
	var p1_skater := duo.skater_of(h1)
	p1_skater.pass_released.emit(p1_skater, free_one)
	_check(duo.skater_of(h1) == free_one and duo.skater_of(h2) == p2_skater, "passing hands the receiver to the passer's human only")
	_check(p2_skater.human_index == 1 and free_one.human_index == 0, "skaters know which player controls them")
	await _reset()
