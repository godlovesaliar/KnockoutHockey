extends Node
## Checks for pucks: what a game pays (Pucks), that it's banked in the profile at the
## final horn (Profile, on a throwaway save), and that the payout screen follows the final
## stats screen.
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/PayoutCheck.tscn
## Exits 0 on pass, 1 on failure.

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")
const AWAY := 5

var failures := 0
var m: MatchDirector


func _ready() -> void:
	Profile.use_fresh("check")
	_numbers()
	await _game()
	_other_receipts()
	_knockout()
	await _screens()
	print("PAYOUT CHECK %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		failures += 1


func _until(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds and not cond.call():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return cond.call()


func _amount(r: Dictionary, label: String) -> int:
	for l: Dictionary in r.lines:
		if str(l.label).begins_with(label):
			return int(l.amount)
	return 0


func _has(r: Dictionary, label: String) -> bool:
	return r.lines.any(func(l: Dictionary) -> bool: return str(l.label).begins_with(label))


func _numbers() -> void:
	_check(Pucks.fmt(0) == "0" and Pucks.fmt(999) == "999" and Pucks.fmt(1000) == "1,000" and Pucks.fmt(1234567) == "1,234,567",
			"numbers get their commas")
	var mults := [Pucks.difficulty_mult(0.2), Pucks.difficulty_mult(0.5), Pucks.difficulty_mult(0.75), Pucks.difficulty_mult(0.95)]
	_check(is_equal_approx(mults[0], 0.5) and is_equal_approx(mults[1], 1.0) and is_equal_approx(mults[2], 1.3) and is_equal_approx(mults[3], 1.5),
			"difficulty pays x0.5 / x1 / x1.3 / x1.5 (%s)" % str(mults))
	_check(Profile.pucks() == 0 and not Profile.spend(1), "a new profile has no pucks to spend")


## A one-period game with a human on the home team, rigged to a 3-0 win on All-Star.
func _game() -> void:
	m = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = [{"kind": "any", "pad": 0, "team": 0}]
	m.team_ids = [0, AWAY]
	m.periods = 1
	m.period_length = 540.0
	m.overtime_mode = "off"
	m.difficulty = 0.75
	m.fighting = false
	m.rng_seed = 99
	m._no_intro = true
	add_child(m)
	_check(await _until(func() -> bool: return m.phase == MatchDirector.Phase.LIVE, 40.0), "the game goes live")
	m.score = [3, 0]
	m.stats.period_goals = [[3, 0, 0, 0], [0, 0, 0, 0]]
	m.stats.big_hits = [12, 0]
	m.stats.fight_wins = [1, 0]
	m.stats.fight_kos = [1, 0]
	m.box.add(m.lineup(0).all_skaters()[0], "g", 3)
	m.clock = 0.05
	_check(await _until(func() -> bool: return m.phase == MatchDirector.Phase.FINAL, 10.0), "the final horn")
	var r := m.payout
	_check(not r.is_empty(), "the game paid")
	if r.is_empty():
		return
	for l: Dictionary in r.lines:
		print("        %-28s %-18s %+d" % [l.label, l.detail, l.amount])
	# 50 + 100 + 50 + 3 goals 30 + hat trick 50 + big hits 50 (10 of 12) + fight 40 + KO 20 = 390
	_check(_amount(r, "GAME FINISHED") == 50 and _amount(r, "WIN") == 100 and _amount(r, "SHUTOUT") == 50, "finish, win and shutout pay")
	_check(_amount(r, "GOALS") == 30 and _amount(r, "HAT TRICK") == 50, "goals and the hat trick pay")
	_check(_amount(r, "BIG HITS") == 50, "big hits pay up to the cap")
	_check(_amount(r, "FIGHTS WON") == 40 and _amount(r, "KNOCKOUTS") == 20, "the fight and its knockout pay")
	_check(_amount(r, "CPU DIFFICULTY") == 117, "All-Star adds 30%% (%d)" % _amount(r, "CPU DIFFICULTY"))
	_check(_amount(r, "FIRST WIN") == 100, "the first win over the team pays")
	_check(int(r.total) == 607, "the total is 607 (%d)" % int(r.total))
	_check(int(r.before) == 0 and int(r.after) == 607 and Profile.pucks() == 607 and Profile.earned() == 607, "banked in the profile")
	_check(Profile.has_beaten(str(Teams.team(AWAY).abbr)), "the team is marked as beaten")
	_check(FileAccess.file_exists("user://profile_check.json"), "the save file is written")
	_check(Profile.spend(107) and Profile.pucks() == 500 and Profile.earned() == 607 and not Profile.spend(501), "spending takes from the balance only")


## The same finished game read other ways: a second win, a loss on Rookie, versus.
func _other_receipts() -> void:
	if m.payout.is_empty():
		return
	var again := Pucks.game_receipt(m)
	_check(not _has(again, "FIRST WIN") and int(again.total) == 507, "a second win over the same team: no first-win bonus (%d)" % int(again.total))
	m.score = [0, 2]
	m.difficulty = 0.2
	var loss := Pucks.game_receipt(m)
	_check(not _has(loss, "WIN") and not _has(loss, "SHUTOUT") and _amount(loss, "GAME FINISHED") == 50, "a loss still pays for finishing")
	_check(_amount(loss, "CPU DIFFICULTY") < 0, "Rookie halves it (%d)" % _amount(loss, "CPU DIFFICULTY"))
	m.humans = [{"kind": "kb1", "pad": 0, "team": 0}, {"kind": "kb2", "pad": 0, "team": 1}]
	var versus := Pucks.game_receipt(m)
	_check(_has(versus, "WIN") and not _has(versus, "CPU DIFFICULTY") and not _has(versus, "FIRST WIN"),
			"versus: the winner's game pays, with no difficulty or first-win bonus")
	m.period_length = 60.0
	var short := Pucks.game_receipt(m)
	_check(_amount(short, "GAME FINISHED") == 17 and _amount(short, "WIN") == 33, "a 1:00 game pays a third of the flat bonuses")
	m.period_length = 540.0
	m.humans = [{"kind": "any", "pad": 0, "team": 0}]
	m.score = [3, 0]
	m.difficulty = 0.75


func _knockout() -> void:
	var km := KnockoutMode.new()
	km.director = m
	var a: Skater = m.lineup(0).all_skaters()[0]
	var b: Skater = m.lineup(1).all_skaters()[0]
	km.results = [{"a": a, "b": b, "winner": a, "ko": true}, {"a": a, "b": b, "winner": a, "ko": false},
			{"a": a, "b": b, "winner": b, "ko": true}, {"a": a, "b": b, "winner": null, "ko": false},
			{"a": a, "b": b, "winner": a, "ko": false}]
	km.score = [8, 4]
	var r := Pucks.knockout_receipt(km)
	# 25 + 3 bouts 75 + 1 KO 15 + series 100
	_check(int(r.total) == 215 and _amount(r, "SERIES WON") == 100, "a Knockout Mode card pays (%d)" % int(r.total))
	km.score = [4, 8]
	_check(int(Pucks.knockout_receipt(km).total) == 115, "a lost card pays its bouts")
	km.free()


## After the final stats screen: the payout screen, with this game's receipt.
func _screens() -> void:
	if m.payout.is_empty():
		return
	_check(await _until(func() -> bool: return m._intermission != null, 40.0), "the final stats screen opens")
	if m._intermission == null:
		return
	_check(not m._intermission.cut, "it leaves the cut to the payout screen")
	await _until(func() -> bool: return m._intermission._age > Intermission.INPUT_DELAY + 0.1, 5.0)
	m._intermission._try_continue()
	_check(await _until(func() -> bool: return m._payout_screen != null, 3.0), "then the payout screen")
	var ps := m._payout_screen
	if ps == null:
		return
	_check(ps.receipt == m.payout and int(ps.receipt.total) == 607, "showing this game's receipt")
	await _until(func() -> bool: return ps._age > PayoutScreen.INPUT_DELAY + 0.1, 5.0)
	ps._on_accept()
	_check(ps._age >= ps._count_end() and not ps._done, "the first press finishes the count")
