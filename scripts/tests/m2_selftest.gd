extends Node3D
## Headless goalie / checking / poke-check test. Run:
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/M2SelfTest.tscn

const RINK_SCENE := preload("res://scenes/match/Rink.tscn")
const PUCK_SCENE := preload("res://scenes/match/Puck.tscn")
const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")
const DT := 1.0 / 120.0

var rink: Rink
var puck: Puck
var goalie: Goalie
var failures := 0
var goals := []
var saves := []
var hits := []
var pokes := 0
var freezes := 0
var _seed := 100


func _ready() -> void:
	rink = RINK_SCENE.instantiate()
	add_child(rink)
	puck = PUCK_SCENE.instantiate()
	add_child(puck)
	rink.goal_scored.connect(func(i: int) -> void: goals.append(i))
	goalie = GOALIE_SCENE.instantiate()
	goalie.team = 1
	goalie.puck = puck
	goalie.rink = rink
	goalie.stats = PlayerStats.new()
	add_child(goalie)
	goalie.net = rink.defended_net(1)
	goalie.seed_rng(3)
	goalie.save_made.connect(func(_g: Goalie, k: StringName) -> void: saves.append(k))
	goalie.froze_puck.connect(func(_g: Goalie) -> void: freezes += 1)
	await get_tree().physics_frame
	await _run()
	print("SELFTEST %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		failures += 1


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
	s.brain = ScriptBrain.new(fn)
	_seed += 1
	s.seed_rng(_seed)
	s.hit_landed.connect(func(_a: Skater, v: Skater, _p: float, k: StringName, _b: bool) -> void: hits.append({"kind": k, "victim": v}))
	s.poke_succeeded.connect(func(_a: Skater, _v: Skater) -> void: pokes += 1)
	return s


func _clear_skaters() -> void:
	puck.place(Vector3(0, 0, 10))
	for c in get_children():
		if c is Skater and not (c is Goalie):
			c.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _trial_reset() -> void:
	puck.place(Vector3(0, 0, 10))
	goalie.reset_in_net()
	rink.rearm_nets()
	goals.clear()
	saves.clear()
	await _ticks(30)


func _run() -> void:
	var gz := -RinkSpec.GOAL_LINE_Z
	print("Goalie vs. straight shots from the slot")
	var shooter := _spawn(0, Vector3(0, 0, gz + 10.0), Vector3.FORWARD, func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass)
	var g_count := 0
	var s_count := 0
	for k in 30:
		await _trial_reset()
		shooter.seed_rng(500 + k)
		shooter.place(Vector3(0, 0, gz + 10.0), Vector3.FORWARD)
		shooter.brain = ScriptBrain.new(func(_s: Skater, i: SkaterIntent, t: float) -> void:
			i.shoot_down = edge(t, 0.1))
		puck.place(shooter.puck_anchor())
		puck.attach(shooter)
		await _ticks(160)
		g_count += goals.size()
		s_count += 1 if not saves.is_empty() else 0
	_check(s_count >= 20, "goalie stops most straight wrist shots (%d saved, %d goals of 30)" % [s_count, g_count])
	_check(g_count >= 1, "but not all of them (%d goals)" % g_count)
	await _clear_skaters()

	print("Goalie vs. cross-ice one-timers")
	g_count = 0
	s_count = 0
	for k in 20:
		await _trial_reset()
		var passer := _spawn(0, Vector3(-7, 0, gz + 8.0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, t: float) -> void:
			i.move = Vector3(12, 0, -1).normalized() * 0.2
			i.pass_down = edge(t, 0.5)
			i.pass_held = i.pass_down
			i.pass_up = i.pass_down)
		var rec := _spawn(0, Vector3(5, 0, gz + 7.0), Vector3.LEFT, func(sk: Skater, i: SkaterIntent, _t: float) -> void:
			i.face = sk.puck.global_position - sk.global_position
			i.shoot_held = true)
		passer.teammates = [passer, rec] as Array[Skater]
		rec.teammates = passer.teammates
		puck.place(passer.puck_anchor())
		puck.attach(passer)
		await _ticks(220)
		g_count += goals.size()
		s_count += 1 if not saves.is_empty() else 0
		await _clear_skaters()
	_check(g_count >= 3, "cross-ice one-timers beat the goalie sometimes (%d goals, %d saves of 20)" % [g_count, s_count])

	print("Goalie covers a slow puck in the crease")
	await _trial_reset()
	freezes = 0
	puck.place(Vector3(0.3, 0, gz + 4.0))
	puck.launch(Vector3(0, 0, -2.5))
	await _ticks(300)
	_check(goalie.has_puck() and freezes == 1, "goalie covers and freezes it (has puck %s, freezes %d)" % [goalie.has_puck(), freezes])

	print("Checking")
	await _trial_reset()
	puck.place(Vector3(0, 0, 25))
	var carrier := _spawn(1, Vector3(0, 0, 0), Vector3.BACK, func(_s: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.BACK * 0.3)
	var hitter := _spawn(0, Vector3(0, 0, 12), Vector3.FORWARD, func(sk: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.FORWARD
		i.turbo = true
		i.check_down = sk.global_position.distance_to(carrier.global_position) < 2.0)
	hitter.opponents = [carrier] as Array[Skater]
	puck.place(carrier.puck_anchor())
	puck.attach(carrier)
	hits.clear()
	await _ticks(200)
	var kinds := hits.map(func(h: Dictionary) -> StringName: return h.kind)
	_check(hits.size() >= 1 and (kinds[0] == &"check" or kinds[0] == &"big_hit"), "a full-speed check knocks the carrier down (%s)" % [kinds])
	_check(puck.carrier != carrier, "and knocks the puck loose")
	await _clear_skaters()

	hits.clear()
	var slow_c := _spawn(1, Vector3(0, 0, 0), Vector3.BACK, func(_s: Skater, i: SkaterIntent, _t: float) -> void: pass)
	var bumper := _spawn(0, Vector3(0, 0, 3.0), Vector3.FORWARD, func(sk: Skater, i: SkaterIntent, _t: float) -> void:
		i.move = Vector3.FORWARD * 0.35
		i.check_down = sk.global_position.distance_to(slow_c.global_position) < 1.6)
	bumper.opponents = [slow_c] as Array[Skater]
	await _ticks(150)
	kinds = hits.map(func(h: Dictionary) -> StringName: return h.kind)
	_check(hits.size() >= 1 and kinds[0] == &"bump", "a slow check is just a bump (%s)" % [kinds])
	await _clear_skaters()

	print("Poke checks")
	pokes = 0
	var victim := _spawn(1, Vector3(0, 0, 0), Vector3.FORWARD, func(_s: Skater, i: SkaterIntent, _t: float) -> void: pass)
	var poker := _spawn(0, Vector3(0, 0, -2.6), Vector3.BACK, func(_s: Skater, i: SkaterIntent, t: float) -> void:
		i.deke_down = fmod(t, 0.8) < DT)
	for k in 12:
		victim.place(Vector3(0, 0, 0), Vector3.FORWARD)
		poker.place(Vector3(0, 0, -2.6), Vector3.BACK)
		puck.place(victim.puck_anchor())
		puck.attach(victim)
		await _ticks(96)
	_check(pokes >= 2 and pokes <= 11, "poke checks strip the puck some of the time (%d of 12)" % pokes)
	await _clear_skaters()
