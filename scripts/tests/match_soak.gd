extends Node
## Plays full AI-vs-AI games headlessly and checks the game loop holds together. Run:
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/MatchSoak.tscn [-- games=3 period=45]
## Exits 0 on pass, 1 on failure.

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")

var failures := 0


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var games := int(args.get("games", "3"))
	var period := float(args.get("period", "45"))
	var t0 := Time.get_ticks_msec()
	var totals := {"goals": 0, "shots": 0, "saves": 0, "hits": 0, "big": 0, "faceoffs": 0,
			"penalties": 0, "offsides": 0, "icings": 0, "changes": 0, "shootouts": 0, "fights": 0}
	for g in games:
		await _play(g + 1, period, totals)
	print("TOTAL over %d games: %s" % [games, totals])
	_check(totals.shots >= games * 6, "AI generates shots (%d)" % totals.shots)
	_check(totals.saves > 0, "goalies make saves (%d)" % totals.saves)
	_check(totals.goals > 0, "somebody scores (%d)" % totals.goals)
	_check(totals.hits > 0, "AI throws checks (%d)" % totals.hits)
	_check(totals.offsides > 0, "offsides get called (%d)" % totals.offsides)
	_check(totals.penalties > 0, "penalties get called (%d)" % totals.penalties)
	_check(totals.changes > 0, "lines change on the fly (%d)" % totals.changes)
	await _shootout_test()
	var pct := float(totals.saves) / maxf(1.0, totals.saves + totals.goals)
	_check(pct > 0.6 and pct < 0.97, "save percentage is hockey-like (%.3f)" % pct)
	print("SOAK %s — %d failure(s), %.1f s" % ["PASS" if failures == 0 else "FAIL", failures, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		failures += 1


func _play(n: int, period: float, totals: Dictionary) -> void:
	var m: MatchDirector = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = []
	m.format = int(OS.get_cmdline_user_args().has("format=3")) * -2 + 5
	m.overtime_mode = "sd_so"
	m.period_length = period
	m.ot_length = period
	m.rng_seed = 1000 + n
	m.show_hud = false
	add_child(m)
	var done := {"finished": false} # lambdas capture locals by value, so use a container
	m.match_finished.connect(func(_s: Array) -> void: done.finished = true)
	if OS.get_cmdline_user_args().has("trace"):
		m.phase_changed.connect(func(ph: int) -> void:
			print("  [%.1fs] phase %s  P%d clock %.1f  score %s" % [Time.get_ticks_msec() / 1000.0, MatchDirector.Phase.keys()[ph], m.period, m.clock, m.score]))
	var limit := int((period * 4 + 240) * 120)
	var escapes := 0
	var carried_ticks := 0
	var longest_carry := 0
	var phases_seen := {}
	var ticks := 0
	while not done.finished and ticks < limit:
		await get_tree().physics_frame
		ticks += 1
		phases_seen[m.phase] = true
		var p := m.puck.global_position
		if m.puck.in_play and RinkSpec.sdf(p.x, p.z) > 0.5:
			escapes += 1
		if m.puck.carrier:
			carried_ticks += 1
			longest_carry = maxi(longest_carry, carried_ticks)
		else:
			carried_ticks = 0
	var st: Dictionary = m.stats
	print("Game %d (%dv%d): %s %d – %d %s  (%s)  SOG %d–%d  hits %d (big %d)  pen %d–%d (PPG %d–%d)  offside %d  icing %d  changes %d–%d  sim %.0fs" % [
		n, m.format, m.format, m.team_name(0), m.score[0], m.score[1], m.team_name(1), m.period_name(m.period),
		m.shots_on_goal(0), m.shots_on_goal(1), st.hits[0] + st.hits[1], st.big_hits[0] + st.big_hits[1],
		st.penalties[0], st.penalties[1], st.pp_goals[0], st.pp_goals[1], st.offsides, st.icings,
		st.changes[0], st.changes[1], ticks / 120.0])
	_check(done.finished, "game %d reaches FINAL" % n)
	_check(escapes == 0, "game %d: puck never escapes the rink (%d ticks)" % [n, escapes])
	_check(longest_carry < 120 * 25, "game %d: nobody holds the puck forever (longest %.1fs)" % [n, longest_carry / 120.0])
	_check(phases_seen.has(MatchDirector.Phase.PERIOD_END), "game %d: periods advance" % n)
	totals.goals += m.score[0] + m.score[1]
	totals.shots += st.shots[0] + st.shots[1]
	totals.saves += st.saves[0] + st.saves[1]
	totals.hits += st.hits[0] + st.hits[1]
	totals.big += st.big_hits[0] + st.big_hits[1]
	totals.faceoffs += st.faceoffs[0] + st.faceoffs[1]
	totals.penalties += st.penalties[0] + st.penalties[1]
	totals.offsides += st.offsides
	totals.icings += st.icings
	totals.changes += st.changes[0] + st.changes[1]
	totals.fights += st.get("fights", 0)
	m.queue_free()
	await get_tree().process_frame
	Engine.time_scale = 1.0


func _shootout_test() -> void:
	var m: MatchDirector = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = []
	m.rng_seed = 77
	m.show_hud = false
	add_child(m)
	var done := {"finished": false}
	m.match_finished.connect(func(_s: Array) -> void: done.finished = true)
	await get_tree().physics_frame
	m.debug_start_shootout()
	var ticks := 0
	while not done.finished and ticks < 120 * 240:
		await get_tree().physics_frame
		ticks += 1
	var r: Array = m.shootout.get("results", [[], []])
	print("Shootout: %s %s – %s %s  final %s  (%.0fs)" % [m.team_name(0), r[0], m.team_name(1), r[1], m.score, ticks / 120.0])
	_check(done.finished, "shootout reaches a result")
	_check(m.score[0] != m.score[1], "shootout produces a winner")
	_check(r[0].size() >= 1 and r[1].size() >= 1, "both teams shoot")
	m.queue_free()
	await get_tree().process_frame
