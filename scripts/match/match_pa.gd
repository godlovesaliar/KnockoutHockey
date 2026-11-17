class_name MatchPA
extends Node
## The arena's PA announcer (Sfx.pa_chain): the home building's own voice, heard through
## the arena under the booth. It works for the home team (team HOME): a big "<home> goal!"
## with the scorer's number shouted, a flat "Visitors' goal" for the other side.
##
##   goals       a few seconds after (over the replay): team, scorer's number, assists
##   penalties   "<team> penalty. Number 4. Two minutes, for tripping."; fight majors
##   the clock   last minute of every period; end of the period; overtime and shootout
##   the arena   intermission notes, and now and then at a stoppage the 50/50, birthdays,
##               lost keys, headlights, the dog in the restroom... or "Make some noise!"
##               when the home team needs it late
##   bookends    "Welcome to <home> hockey!" as the game opens; "Your <home> win!" and
##               drive home safely at the end
##
## Every piece is a line in AnnouncerLines ("PA announcer" groups); pieces that aren't
## recorded are skipped, so a call shrinks to what exists.

const HOME := 0
const GOAL_CALL_AFTER := 6.0      ## seconds after a goal: the booth has had its say
const PENALTY_CALL_AFTER := 4.5
const AMBIENT_EVERY := Vector2(110.0, 200.0)   ## seconds of live play between arena notes
const NOISE_COOLDOWN := 90.0

var director: MatchDirector
var _home_call := ""
var _away_call := ""
var _prev_phase := -1
var _ambient_in := 0.0
var _last_clock := INF
var _noise_at := -100.0
var _goals_by := {}               ## home scorer -> goals this game (hat tricks)


func setup(d: MatchDirector) -> void:
	director = d
	_home_call = Teams.team(d.team_ids[HOME]).get("call", "")
	_away_call = Teams.team(d.team_ids[1 - HOME]).get("call", "")
	_ambient_in = randf_range(AMBIENT_EVERY.x * 0.6, AMBIENT_EVERY.y * 0.6)
	d.goal.connect(_on_goal)
	d.penalty_called.connect(_on_penalty)
	d.penalty_expired.connect(_on_penalty_expired)
	d.phase_changed.connect(_on_phase)
	d.glass_broken.connect(func(_at: Vector3) -> void: _later(["pa_glass"], 3.5, 1))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	if director == null or director.phase != MatchDirector.Phase.LIVE:
		return
	_ambient_in -= delta
	# "Last minute of play in the period": every period long enough to have one.
	var c := director.clock
	if _last_clock >= 60.0 and c < 60.0 and director.period_length > 90.0:
		Sfx.pa("pa_last_minute", 2)
	_last_clock = c


func _team_call(t: int) -> String:
	return _home_call if t == HOME else _away_call


## "pa_n17_big" / "pa_n17_flat" for a player's number ("" when the number has no line).
## Every Pine Barrens Camper wears a number with 13 in it (113, 1313...): the PA just calls
## them all "Number thirteen".
func _num(s: Skater, big := false) -> String:
	if s == null:
		return ""
	var n := 13 if _team_call(s.team) == "campers" else s.number
	if n < 0 or n >= AnnouncerLines.NUMBERS:
		return ""
	return "pa_n%d_%s" % [n, "big" if big else "flat"]


func _on_goal(team: int, scorer: Skater) -> void:
	var own := scorer != null and scorer.team == team
	var call: Array = []
	if team == HOME:
		call.append("pa_goal_" + _home_call)
		if own:
			call.append_array(["pa_scored_by", _num(scorer, true)])
	else:
		call.append("pa_goal_visitors")
		if own:
			call.append(_num(scorer))
	var assists: Array = director.last_assists.duplicate() if own else []
	if not assists.is_empty():
		call.append_array(["pa_assist", _num(assists[0])])
		if assists.size() > 1:
			call.append_array(["pa_and", _num(assists[1])])
	call = call.filter(func(l: String) -> bool: return l != "")
	var hattrick := false
	if team == HOME and own:
		var n := int(_goals_by.get(scorer, 0)) + 1
		_goals_by[scorer] = n
		hattrick = n == 3
	_later(call, GOAL_CALL_AFTER, 3, [MatchDirector.Phase.FINAL])
	if hattrick:
		_after_current(["pa_hattrick"], 0.8, 3, GOAL_CALL_AFTER + 1.0)


func _on_penalty(offender: Skater, kind: StringName) -> void:
	var call: Array = ["pa_penalty_" + _team_call(offender.team), _num(offender), "pa_pen_" + str(kind)]
	_later(call.filter(func(l: String) -> bool: return l != ""), PENALTY_CALL_AFTER, 2)


func _on_penalty_expired(t: int) -> void:
	if director.lineup(t).box_count() == 0 and director.lineup(1 - t).box_count() == 0 and randf() < 0.6:
		_later(["pa_full_strength"], 1.5, 1)


func _on_phase(phase: MatchDirector.Phase) -> void:
	var was := _prev_phase
	_prev_phase = phase
	match phase:
		MatchDirector.Phase.PREGAME:
			if was == MatchDirector.Phase.INTRO:
				_later(["pa_welcome_" + _home_call], 0.4, 3)
		MatchDirector.Phase.STOPPAGE:
			_last_clock = INF if director.clock >= 60.0 else director.clock
			if was == MatchDirector.Phase.FIGHT and director.last_fight_majors and director.last_fighters.size() == 2:
				var f := director.last_fighters
				var call: Array = [_num(f[0]), "pa_and", _num(f[1]), "pa_pen_fighting"]
				_later(call.filter(func(l: String) -> bool: return l != ""), 4.0, 2)
			else:
				_stoppage_note()
		MatchDirector.Phase.PERIOD_END:
			_last_clock = INF
			var p := director.period
			var to_ot := p >= director.periods
			var end: String = "pa_end_third" if to_ot else {1: "pa_end_first", 2: "pa_end_second"}.get(p, "")
			var call: Array = [end] if end != "" else []
			if to_ot:
				call.append("pa_overtime")
			_later(call, 2.5, 2)
			var notes := ["pa_intermission"] if randf() < 0.6 else ["pa_ambient"]
			_after_current(notes, 2.0, 1, 3.0, [MatchDirector.Phase.PERIOD_END])
		MatchDirector.Phase.SHOOTOUT:
			_later(["pa_shootout"], 3.5, 2)
		MatchDirector.Phase.FINAL:
			var home_won: bool = director.score[HOME] > director.score[1 - HOME]   # (a shootout win counts as a goal)
			var call: Array = (["pa_win_" + _home_call] if home_won else []) + ["pa_thanks"]
			_after_current(call, 1.0, 3, 5.0, [MatchDirector.Phase.FINAL])
		MatchDirector.Phase.FACEOFF:
			_last_clock = INF if director.clock >= 60.0 else director.clock


## At a stoppage: the crowd needs a lift late in a game the home team needs, or it's
## time for one of the arena's notes.
func _stoppage_note() -> void:
	var diff: int = int(director.score[HOME]) - int(director.score[1 - HOME])
	var late := director.period >= director.periods and director.clock < director.period_length * 0.5
	if late and diff <= 0 and diff >= -2 and _now() - _noise_at > NOISE_COOLDOWN and randf() < 0.5:
		_noise_at = _now()
		_later(["pa_noise"], 1.2, 1)
		return
	if _ambient_in <= 0.0 and not Sfx.pa_playing():
		_ambient_in = randf_range(AMBIENT_EVERY.x, AMBIENT_EVERY.y)
		_later(["pa_ambient"], 1.5, 1)


## A PA call after `delay` seconds, unless the game has moved into one of `skip_phases`.
func _later(call: Array, delay: float, priority: int, skip_phases: Array = []) -> void:
	if call.is_empty():
		return
	await get_tree().create_timer(delay).timeout
	if director == null or director.phase in skip_phases:
		return
	Sfx.pa_chain(call, priority)


## After `delay` s, waits (up to `wait` s) for the PA's current call to finish, then
## `gap` s more, then makes this one. Only while the game is in one of `phases` (any if empty).
func _after_current(call: Array, gap: float, priority: int, delay: float, phases: Array = [], wait := 20.0) -> void:
	await get_tree().create_timer(delay).timeout
	var waited := 0.0
	while Sfx.pa_playing() and waited < wait:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	await get_tree().create_timer(gap).timeout
	if director == null or (not phases.is_empty() and not director.phase in phases):
		return
	Sfx.pa_chain(call, priority)
