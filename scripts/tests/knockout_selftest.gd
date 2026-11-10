extends Node
## Knockout Mode self-test: a real match scene in Knockout Mode, computer vs computer.
## Checks the card: five different skaters a side, five bouts (plus any sudden death),
## the points add up, the series ends with a winner, and no hockey happens.
##   godot --headless --path . res://scenes/tests/KnockoutSelfTest.tscn

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
	m.rng_seed = 7
	m.show_hud = false
	m.knockout = true
	add_child(m)
	await get_tree().physics_frame
	var ko := m.knockout_mode
	_check(ko != null, "Knockout Mode starts")
	if ko == null:
		return
	for t in 2:
		var five: Array = ko._card[t]
		var uniq := {}
		for s in five:
			uniq[s] = true
		_check(five.size() == 5 and uniq.size() == 5, "team %d: five different skaters" % t)
		_check(m.lineup(t).on_ice.size() == 5, "team %d: they're the ones on the ice" % t)
	var winner := {}
	ko.series_over.connect(func(w: int) -> void: winner["w"] = w)
	var t := 0.0
	while t < 400.0 and winner.is_empty():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if m.phase != MatchDirector.Phase.FIGHT:
			_check(false, "left the fight phase (%s)" % MatchDirector.Phase.keys()[m.phase])
			return
	_check(not winner.is_empty(), "the series ends (%.0f s)" % t)
	if winner.is_empty():
		return
	_check(ko.results.size() >= KnockoutMode.BOUTS, "%d bouts fought" % ko.results.size())
	var pts := [0, 0]
	for k in ko.results.size():
		var r: Dictionary = ko.results[k]
		if k < KnockoutMode.BOUTS:
			_check(r.a == ko._card[0][k] and r.b == ko._card[1][k], "bout %d: the drawn pair" % (k + 1))
		if r.winner == null:
			pts[0] += KnockoutMode.PTS_DRAW
			pts[1] += KnockoutMode.PTS_DRAW
		else:
			pts[r.winner.team] += KnockoutMode.PTS_KO if r.ko else KnockoutMode.PTS_WIN
		print("        %d  %s vs %s  ->  %s%s" % [k + 1, MenuStyle.player_name(r.a), MenuStyle.player_name(r.b),
				"draw" if r.winner == null else MenuStyle.player_name(r.winner), " (KO)" if r.ko else ""])
	_check(pts == ko.score, "the points add up (%d — %d)" % [ko.score[0], ko.score[1]])
	_check(ko.score[winner.w] > ko.score[1 - winner.w], "the winner has more points")
	_check(m.score == [0, 0] and m.stats.shots == [0, 0], "no hockey was played")
	_check(m.stats.fights == ko.results.size(), "every bout counted in the stats")
