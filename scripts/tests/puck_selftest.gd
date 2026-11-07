extends Node3D
## Headless puck/rink regression test. Run:
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/PuckSelfTest.tscn
## Exits with code 0 on pass, 1 on failure.

const RINK_SCENE := preload("res://scenes/match/Rink.tscn")
const PUCK_SCENE := preload("res://scenes/match/Puck.tscn")

var rink: Rink
var puck: Puck
var goals := []
var hits := {}
var failures := 0


func _ready() -> void:
	rink = RINK_SCENE.instantiate()
	add_child(rink)
	puck = PUCK_SCENE.instantiate()
	add_child(puck)
	rink.goal_scored.connect(func(side: int) -> void: goals.append(side))
	puck.hit_surface.connect(func(s: String, _v: float, _p: Vector3) -> void: hits[s] = hits.get(s, 0) + 1)
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


func _shoot(from: Vector3, v: Vector3, ticks: int) -> Dictionary:
	puck.place(from)
	rink.rearm_nets()
	goals.clear()
	hits.clear()
	await get_tree().physics_frame
	puck.launch(v)
	var max_sdf := -INF
	for i in ticks:
		await get_tree().physics_frame
		var p := puck.global_position
		if p.y < RinkSpec.BOARD_HEIGHT:
			max_sdf = maxf(max_sdf, RinkSpec.sdf(p.x, p.z))
	return {
		"max_sdf": max_sdf,
		"goals": goals.duplicate(),
		"hits": hits.duplicate(),
		"end": puck.global_position,
		"speed": puck.speed(),
	}


func _run() -> void:
	var gz := RinkSpec.GOAL_LINE_Z
	var half_w := RinkSpec.NET_WIDTH * 0.5

	print("Containment")
	var worst := -INF
	var bounced := 0
	for i in 72:
		var a := TAU * i / 72.0
		var r := await _shoot(Vector3.ZERO, Vector3(cos(a), 0.0, sin(a)) * 45.0, 360)
		worst = maxf(worst, r.max_sdf)
		if not r.hits.is_empty():
			bounced += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 100:
		var start := Vector3(rng.randf_range(-11.0, 11.0), 0.0, rng.randf_range(-25.0, 25.0))
		if RinkSpec.sdf(start.x, start.z) > -1.0:
			continue
		var a := rng.randf() * TAU
		var r := await _shoot(start, Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(20.0, 50.0), 300)
		worst = maxf(worst, r.max_sdf)
	_check(worst <= 0.0, "puck center never passes the board face (worst sdf %.4f, puck r %.4f)" % [worst, RinkSpec.PUCK_RADIUS])
	_check(bounced == 72, "all 72 radial 45 m/s shots hit something (%d)" % bounced)

	print("Goals")
	var slot := Vector3(0.0, 0.0, gz - 8.0)
	for spd in [8.0, 25.0, 45.0]:
		var r := await _shoot(slot, Vector3(0, 0, spd), 240)
		_check(r.goals == [0], "%.0f m/s center shot scores on +Z net (goals %s)" % [spd, r.goals])
		var e: Vector3 = r.end
		var trapped := e.z > gz and e.z < gz + RinkSpec.NET_DEPTH + 0.05 and absf(e.x) < half_w + 0.05
		_check(trapped, "  ...and the puck stays in the net (end %s, %.2f m/s)" % [e, r.speed])

	var corner := Vector3(half_w - 0.15, 0.0, gz)
	var r_corner := await _shoot(slot + Vector3(-2.0, 0, 0), (corner - (slot + Vector3(-2.0, 0, 0))).normalized() * 35.0, 240)
	_check(r_corner.goals == [0], "angled shot into the far side scores (goals %s)" % [r_corner.goals])

	var lifted := await _shoot(slot, Vector3(0.0, 3.0, 30.0), 240)
	_check(lifted.goals == [0], "lifted shot under the bar scores (goals %s)" % [lifted.goals])

	var other := await _shoot(Vector3(0, 0, -(gz - 8.0)), Vector3(0, 0, -30.0), 240)
	_check(other.goals == [1], "shot on the -Z net credits side 1 (goals %s)" % [other.goals])

	print("No-goals")
	for x in [-(half_w + 0.35), half_w + 0.35]:
		var target := Vector3(x, 0.0, gz)
		var r := await _shoot(slot, (target - slot).normalized() * 30.0, 240)
		_check(r.goals.is_empty(), "wide shot at x=%.2f misses (goals %s)" % [x, r.goals])

	var post_x := half_w + RinkSpec.POST_RADIUS
	var r_post := await _shoot(Vector3(post_x, 0, gz - 8.0), Vector3(0, 0, 30.0), 240)
	_check(r_post.hits.has("post") and r_post.goals.is_empty(), "dead-on post shot rings off the post (hits %s, goals %s)" % [r_post.hits, r_post.goals])

	var over := await _shoot(slot, Vector3(0.0, 6.0, 25.0), 240)
	_check(over.goals.is_empty(), "shot over the crossbar doesn't score (goals %s, hits %s)" % [over.goals, over.hits])

	var behind := await _shoot(Vector3(0, 0, gz + 2.3), Vector3(0, 0, -30.0), 240)
	_check(behind.goals.is_empty() and behind.hits.has("net"), "shot into the back of the net doesn't score (goals %s, hits %s)" % [behind.goals, behind.hits])

	print("Feel numbers (for tuning)")
	puck.place(Vector3(0, 0, -20.0))
	await get_tree().physics_frame
	puck.launch(Vector3(0, 0, 10.0))
	var start_z := puck.global_position.z
	var ticks := 0
	while puck.speed() > 0.01 and ticks < 2400:
		await get_tree().physics_frame
		ticks += 1
	print("  10 m/s pass glides %.1f m in %.1f s" % [puck.global_position.z - start_z, ticks / 120.0])
	var glass := await _shoot(Vector3.ZERO, Vector3(20.0, 5.0, 0.0), 240)
	print("  lifted shot at side glass hits: %s" % [glass.hits])
