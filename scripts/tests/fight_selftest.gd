extends Node
## Fight self-test: a real match (AI vs AI) with a fight started at the first chance
## (`fight` debug flag). Checks the whole flow: fight starts, ends on a knockdown or
## decision, both fighters serve offsetting majors (no power play), play resumes with a
## faceoff, the winner's team gets momentum, tension resets.
##   godot --headless --path . res://scenes/tests/FightSelfTest.tscn

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")

var failures := 0


func _ready() -> void:
	await _run()
	print("SELFTEST %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		failures += 1


func _run() -> void:
	var m: MatchDirector = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = []
	m.rng_seed = 5
	m.show_hud = false
	m.period_length = 120.0
	m._debug_fight = "on"
	add_child(m)
	var started := false
	var fighters: Array[Skater] = []
	var t := 0.0
	while t < 15.0 and not started:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if m.phase == MatchDirector.Phase.FIGHT and m._fight:
			started = true
			fighters = [m._fight.a.s, m._fight.b.s]
	_check(started, "a fight starts (%.1f s)" % t)
	if not started:
		return
	_check(fighters[0].team != fighters[1].team, "between the two teams")
	var result := {}
	m._fight.finished.connect(func(w: Skater, l: Skater) -> void:
		result["w"] = w
		result["l"] = l)
	t = 0.0
	while t < 60.0 and result.is_empty():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	_check(not result.is_empty(), "the fight ends (%.1f s)" % t)
	_check(t > 6.0, "and isn't over in a flash (%.1f s)" % t)
	await get_tree().physics_frame
	for s in fighters:
		var lu := m.lineup(s.team)
		_check(lu.in_box.has(s) and lu.offsetting.has(s), "#%d serves an offsetting major" % s.number)
		_check(absf(float(lu.in_box.get(s, 0.0)) - MatchDirector.FIGHT_MAJOR) < 1.0, "5:00 (%.0f s)" % float(lu.in_box.get(s, 0.0)))
	_check(m.strength(0) == 5 and m.strength(1) == 5, "no power play (%d on %d)" % [m.strength(0), m.strength(1)])
	_check(m.tension == [0.0, 0.0], "tension resets")
	_check(m.stats.fights == 1, "counted in the stats")
	var w: Skater = result.get("w")
	if w:
		_check(m.momentum[w.team] > 0.0, "the winner's team gets momentum")
	var live := false
	t = 0.0
	while t < 15.0 and not live:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		live = m.phase == MatchDirector.Phase.LIVE
	_check(live, "play resumes with a faceoff (%.1f s)" % t)
	for s in fighters:
		_check(not (s in m.lineup(s.team).on_ice), "#%d isn't on the ice" % s.number)
	_check(m.lineup(0).on_ice.size() == 5 and m.lineup(1).on_ice.size() == 5, "both teams back at full strength on the ice")
