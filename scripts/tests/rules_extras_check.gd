extends Node
## Headless checks for the game's extra rules: pulling the goalie (by hand and the
## computer's late pull), injuries, glass breaks, catch-up AI and referee strictness.
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/RulesExtrasCheck.tscn
## Exits 0 on pass, 1 on failure.

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")

var failures := 0
var m: MatchDirector
var _stops := 0


func _ready() -> void:
	m = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = []
	m.period_length = 600.0
	m.rng_seed = 4242
	m.show_hud = false
	m.offsides = false
	m.icing = false
	m.penalties = false
	m.fighting = false
	add_child(m)
	await _until(func() -> bool: return m.phase == MatchDirector.Phase.LIVE, 30.0)

	_check(m.ref_strictness >= 0.65 and m.ref_strictness <= 1.35, "referee strictness rolled in range (%.2f)" % m.ref_strictness)
	await _catch_up()
	await _manual_pull()
	await _late_pull()
	await _injury()
	await _glass()
	print("RULES EXTRAS %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _catch_up() -> void:
	m.catch_up = true
	m.score = [0, 3]
	await _frames(5)
	var s0: Skater = m.lineup(0).on_ice[0]
	var s1: Skater = m.lineup(1).on_ice[0]
	_check(m.teams[0].ai.catch_up == 1.0 and s0.catch_up == 1.0 and s1.catch_up == 0.0,
			"catch-up: three down gets the full boost, the leader none (%.1f / %.1f)" % [s0.catch_up, s1.catch_up])
	m.score = [1, 3]
	await _frames(5)
	_check(is_equal_approx(s0.catch_up, 0.6), "catch-up: two down gets part of it (%.1f)" % s0.catch_up)
	m.catch_up = false
	await _frames(5)
	_check(s0.catch_up == 0.0, "catch-up: off means no boost")
	m.score = [0, 0]


func _manual_pull() -> void:
	await _live()
	var g: Goalie = m.teams[1].goalie
	m.phase_changed.connect(func(ph: int) -> void:
		if ph == MatchDirector.Phase.STOPPAGE:
			_stops += 1)
	# A whistle while the goalie skates off can (rightly) undo the pull: try again.
	var ok := false
	for attempt in 3:
		await _live()
		await _until(func() -> bool: return not g.has_puck(), 10.0)
		_stops = 0
		if not m.pulled[1] and not m.pull_goalie(1, "manual"):
			continue
		ok = await _until(func() -> bool:
			return g.benched and m.lineup(1).on_ice.size() == m.strength(1) + 1, 12.0)
		if ok or _stops == 0:
			break
	_check(ok, "pull: goalie reaches the bench and an extra attacker comes on (%d on, strength %d; pulled %s, benched %s, walking %s, %s, stoppages %d)" % [
			m.lineup(1).on_ice.size(), m.strength(1), m.pulled[1], g.benched, g.walking(), MatchDirector.Phase.keys()[m.phase], _stops])
	_check(m.teams[0].ai.net_empty(), "pull: the other team's AI sees the empty net")
	m.return_goalie(1)
	ok = await _until(func() -> bool:
		return not g.benched and not g.walking() and m.lineup(1).on_ice.size() == m.strength(1) \
				and g.global_position.distance_to(g.net.global_position) < 2.5, 20.0)
	_check(ok, "pull: goalie back in the net and the extra attacker off (%d on, goalie benched %s, %.1f m from net)" % [
			m.lineup(1).on_ice.size(), g.benched, g.global_position.distance_to(g.net.global_position)])


func _late_pull() -> void:
	await _live()
	m.period = m.periods
	m.clock = 15.0
	m.score = [1, 0]
	var ok := await _until(func() -> bool: return m.pulled[1], 25.0)
	_check(ok, "late pull: the CPU pulls its goalie down one late")
	m.clock = 15.0
	m.score = [1, 1]
	ok = await _until(func() -> bool: return not m.pulled[1] and not m.goalie_out(1), 20.0)
	_check(ok, "late pull: tied up, the goalie goes back in")
	m.period = 1
	m.clock = 500.0
	m.score = [0, 0]


func _injury() -> void:
	await _live()
	var lu := m.lineup(0)
	var s: Skater = null
	for o in lu.on_ice:
		if not o.is_defense:
			s = o
			break
	var forwards := lu.forwards.size()
	s.receive_hit(14.0, Vector3.RIGHT, null)
	m._hurt_in_play(s)
	var ok := await _until(func() -> bool: return m.phase != MatchDirector.Phase.LIVE, 6.0)
	_check(ok, "injury: the whistle goes for a hurt player")
	_check(s.injured and s.benched and not (s in lu.forwards) and lu.forwards.size() == forwards - 1 and s in lu.injured,
			"injury: off the lines and to the bench (%d forwards left)" % lu.forwards.size())
	await _live()
	_check(not (s in lu.on_ice), "injury: doesn't come back out")


func _glass() -> void:
	await _live()
	var bench := RinkSpec.BENCH_Z[0] as Vector2
	_check(m.rink.shatter_glass(Vector3(RinkSpec.BENCH_SIDE * (RinkSpec.HALF_W - 0.3), 0, (bench.x + bench.y) * 0.5)) == Vector3.INF,
			"glass: no glass to break at the open bench front")
	_check(m._break_glass(Vector3(RinkSpec.HALF_W - 0.4, 0, -14.0)), "glass: a pane breaks along the side boards")
	_check(m.rink.glass_broken(), "glass: the hole is there")
	var ok := await _until(func() -> bool: return m.phase != MatchDirector.Phase.LIVE, 4.0)
	_check(ok, "glass: the whistle goes")
	ok = await _until(func() -> bool: return not m.rink.glass_broken(), 10.0)
	_check(ok, "glass: repaired at the stoppage")


func _live() -> void:
	await _until(func() -> bool: return m.phase == MatchDirector.Phase.LIVE, 30.0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _until(cond: Callable, seconds: float) -> bool:
	var ticks := int(seconds * 120)
	for i in ticks:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		failures += 1
