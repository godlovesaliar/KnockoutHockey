extends Node
## Checks for the locked teams: they can't be picked until their challenge is bought and
## won (Store, Profile on a throwaway save), and a challenge game the player wins unlocks
## the team, pays its bonus and shows on the payout screen.
##   godot --headless --fixed-fps 120 --path . res://scenes/tests/ChallengeCheck.tscn
## Exits 0 on pass, 1 on failure.

const MATCH_SCENE := preload("res://scenes/match/Match.tscn")
const LOCKED := ["whalers", "campers", "sweettea", "geese", "luchadores", "floridaman", "grays", "stuntmen", "chupacabras", "beacon", "anchor", "boxcar", "copper", "clipper", "jalopy"]

var failures := 0
var m: MatchDirector
var boss := -1    ## the Sweet Tea
var mine := -1    ## the first team anyone can play as


func _ready() -> void:
	Profile.use_fresh("check")
	_locks()
	await _game()
	_after()
	await _screens()
	print("CHALLENGE CHECK %s — %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
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


func _has(r: Dictionary, label: String) -> bool:
	return r.lines.any(func(l: Dictionary) -> bool: return str(l.label).begins_with(label))


func _locks() -> void:
	var team_items := Store.in_category("teams")
	_check(team_items.size() == LOCKED.size() and team_items.all(func(it: Dictionary) -> bool: return it.team in LOCKED),
			"the %d locked teams are on the shelf" % LOCKED.size())
	_check(team_items.all(func(it: Dictionary) -> bool: return Store.team_index(str(it.id)) >= 0 and Store.team_item(Store.team_index(str(it.id))) == it.id),
			"each is a league team")
	var open := Store.open_teams()
	_check(open.size() == Teams.menu_order().size() - LOCKED.size(), "a new profile can play as %d of %d teams" % [open.size(), Teams.menu_order().size()])
	_check(open.all(func(i: int) -> bool: return not (str(Teams.base_team(i).get("call", "")) in LOCKED)), "none of them a locked team")
	boss = Store.team_index("team_sweettea")
	mine = Store.open_team(0)
	_check(not Store.team_open(0) and mine != 0 and Store.team_open(mine), "a locked default team falls back to one that's open (%s)" % Teams.full_name(mine))
	_check(Store.open_team(mine, mine) != mine and Store.team_open(Store.open_team(mine, mine)), "and never the other side's team")
	_check(not Store.challenge_ready("team_sweettea") and not Store.team_unlocked("team_sweettea"), "no challenge before it's bought")
	Profile.add_pucks(500)
	_check(Store.buy("team_sweettea") and Profile.pucks() == 0, "500 pucks buy the Sweet Tea's challenge")
	_check(Store.challenge_ready("team_sweettea") and not Store.team_open(boss) and not (boss in Store.open_teams()), "bought isn't unlocked: they still can't be picked")
	_check(not Store.challenge_ready("rink_outdoor") and not Store.team_unlocked("rink_outdoor"), "a rink is no challenge")


## The challenge: the Sweet Tea at home, a human on the away team, rigged to a 2-0 away win.
func _game() -> void:
	m = MATCH_SCENE.instantiate()
	m.use_game_settings = false
	m.humans = [{"kind": "any", "pad": 0, "team": 1}]
	m.team_ids = [boss, mine]
	m.challenge = boss
	m.periods = 1
	m.period_length = 540.0
	m.overtime_mode = "off"
	m.difficulty = 0.5
	m.fighting = false
	m.rng_seed = 31
	m._no_intro = true
	add_child(m)
	_check(await _until(func() -> bool: return m.phase == MatchDirector.Phase.LIVE, 40.0), "the challenge game goes live")
	# Losing it unlocks nothing.
	m.score = [1, 0]
	var lost := Pucks.game_receipt(m)
	_check(not m.challenge_won() and str(lost.unlock) == "" and not _has(lost, "CHALLENGE WON") and str(lost.mode) == "CHALLENGE", "a loss unlocks nothing")
	m.score = [0, 2]
	m.stats.period_goals = [[0, 0, 0, 0], [2, 0, 0, 0]]
	m.clock = 0.05
	_check(await _until(func() -> bool: return m.phase == MatchDirector.Phase.FINAL, 10.0), "the final horn")
	var r := m.payout
	_check(not r.is_empty() and m.challenge_won(), "the player won it")
	if r.is_empty():
		return
	for l: Dictionary in r.lines:
		print("        %-34s %-10s %+d" % [l.label, l.detail, l.amount])
	_check(_has(r, "CHALLENGE WON") and str(r.unlock) == "sweettea" and int(r.unlock_team) == boss, "the receipt unlocks the Sweet Tea")
	# 50 + 100 + 50 shutout + 2 goals 20 = 220 on Pro, + first win 100 + challenge 200
	_check(int(r.total) == 520, "it pays 520 with the first-win and challenge bonuses (%d)" % int(r.total))


func _after() -> void:
	if m.payout.is_empty():
		return
	_check(Profile.team_unlocked("sweettea") and Store.team_unlocked("team_sweettea") and not Store.challenge_ready("team_sweettea"), "the team is unlocked in the profile")
	_check(Store.team_open(boss) and boss in Store.open_teams() and Store.open_team(boss) == boss, "and can be picked from now on")
	_check(not Store.team_open(0), "the other locked teams stay locked")
	var again := Pucks.game_receipt(m)
	_check(not _has(again, "CHALLENGE WON") and str(again.unlock) == "", "beating them again pays no second challenge bonus")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profile_check.json"))
	_check(saved is Dictionary and "sweettea" in saved.get("teams", []), "it's in the save file")


func _screens() -> void:
	if m.payout.is_empty():
		return
	_check(await _until(func() -> bool: return m._intermission != null, 40.0), "the final stats screen opens")
	if m._intermission == null:
		return
	await _until(func() -> bool: return m._intermission._age > Intermission.INPUT_DELAY + 0.1, 5.0)
	m._intermission._try_continue()
	_check(await _until(func() -> bool: return m._payout_screen != null, 3.0), "then the payout screen")
	if m._payout_screen != null:
		_check(int(m._payout_screen.receipt.get("unlock_team", -1)) == boss and m._payout_screen.hint == "Back to the Pro Shop.",
				"showing the unlocked team, on the way back to the shop")
