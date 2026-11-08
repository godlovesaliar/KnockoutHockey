class_name MatchAudio
extends Node
## Hooks match events to Sfx: puck impacts, passes and shots, hits, saves, whistles,
## the goal horn and crowd reactions. Skates (strides, hockey stops) are played by the
## skater visuals themselves.
##
## The crowd is the home team's (team HOME): it cheers its goals, hits and saves, boos
## penalties against it, groans at goals against, chants "De-fense!" when pinned in its
## own zone, gets louder as its attack builds, and now and then chants the team's name.
## It groans when a home shot is saved by the visitors' goalie, rings a post or misses
## wide. The organ plays through whistles and breaks, and sounds the charge as a home
## attack builds.
##
## The booth (Sfx.announce) has two voices, one talking at a time: Steve Sheldon calls
## the play, Bobby Niedemyer reacts (after big saves, big hits, goals, the third period's
## call and the final horn) and fills quiet spells. Every line, its voice, what triggers
## it and the file names that count as its takes are listed in AnnouncerLines; a line with no
## recordings is simply skipped. Each line has a chance and a cooldown so the commentary
## stays occasional, and a priority (a line only cuts off a lower one). Every game opens
## with the matchup screen: the home team's "Tonight: a matchup between the <home>" and
## the away team's "and the <away>." (Teams `call`). As it closes, Steve and Bobby welcome
## everyone together (intro_duet; Steve's solo welcome only if no duet is recorded).
## Goals get a follow-up a moment later when the situation calls for one (tie, lead,
## insurance, hat trick, power play, short-handed, comeback). Duets (both voices in one
## clip) can be takes of any line, and the banter lines are duets only: quiet spells,
## intermissions, after penalties, fights, goals, big hits and the final horn, and in
## blowouts and close games.

const HOME := 0
const CHANT_EVERY := Vector2(55.0, 110.0)     ## seconds of live play between team chants
const DEFENSE_AFTER := 5.0                    ## seconds pinned in the home zone before "De-fense!"
const RISING_AFTER := 3.0                     ## seconds of home pressure before the crowd builds
const REACT_COOLDOWN := 25.0
const MOOD_WINDOW := 75.0                     ## seconds of crowd reactions the announcer weighs
const MOOD_COUNT := 3                         ## same-way reactions in the window before a remark
const GOOD_REACTIONS := ["cheer", "short_cheer", "goal_cheer", "chant_defense"]
const BAD_REACTIONS := ["boo", "big_boo", "outrage", "disappointed"]
const SHOT_WINDOW := 1.6                      ## seconds a home shot counts as "just taken"
const POINT_SHOT := 15.0                      ## a defender shooting from this far out: "from the point"
const TOP_SHELF := 0.75                       ## puck height (m) at the goal line for "top shelf"
const STREAK_SHOTS := 4                       ## shots in a row by one team for "hot streak"...
const STREAK_WINDOW := 45.0                   ## ...within this many seconds

## Reaction priorities (a reaction only interrupts one of equal or lower priority).
enum { P_AMBIENT = 1, P_REACT = 2, P_GOAL = 3 }

var director: MatchDirector
var home_chant := ""          ## the home team's chant (Teams.LIST)
var _goal_time := -100.0
var _prev_phase := -1
var _opened := false   ## the duet welcome played as the matchup screen closed
var _chant_in := 60.0
var _pinned := 0.0
var _pressure := 0.0
var _last_defense := -100.0
var _last_rising := -100.0
var _live := 0.0
var _said := {}                ## announcer line -> _now() when last said
var _carrier: Skater
var _carrier_since := 0.0      ## _now() when the current carrier got the puck
var _period_called := 0      ## the last period whose start was announced
var _idle_in := 25.0
var _breakaway_for: Skater     ## the carrier the breakaway was already called for
var _deke_called := false
var _moves_called := {}        ## this possession's carrier calls: blueline, behindnet, boards_carry, setup
var _rush_for: Skater          ## the defenseman whose rush was already called
var _prev_carrier: Skater
var _carrier_lost := -10.0     ## _now() when the last carrier lost the puck
var _flips: Array[float] = []  ## _now() of recent possession changes between teams
var _rush_called_for: Skater   ## carrier whose trip down the ice was already called
var _mood: Array[Vector2] = [] ## recent crowd reactions: (_now(), +1 good / -1 bad)
var _home_shot := -10.0        ## _live time of the last home shot still in the air
var _shot := {"time": -100.0, "team": -1}   ## the last shot on net: _now(), shooting team
var _save_time := -100.0
var _shots_log: Array[Vector2] = []   ## recent shots: (_now(), team)
var _low_passes: Array[float] = []    ## _now() of recent passes low in the offensive zone
var _goals_by := {}            ## scorer -> goals this game
var _worst := [0, 0]           ## per team: the most goals it has trailed by
var _state_called := {}        ## "close_game" / "blowout" -> the period it was last said in
var _last_clock := INF
var _fights_seen := 0


func setup(d: MatchDirector) -> void:
	director = d
	var puck := d.puck
	puck.hit_surface.connect(_on_surface)
	puck.possession_changed.connect(_on_possession)
	puck.possession_changed.connect(_on_carrier)
	d.goal.connect(_on_goal)
	d.phase_changed.connect(_on_phase)
	d.penalty_called.connect(_on_penalty)
	d.whistle_blown.connect(_on_whistle)
	d.faceoff_won.connect(_on_faceoff_won)
	d.penalty_expired.connect(_on_penalty_expired)
	var chant: String = Teams.team(d.team_ids[HOME]).get("chant", "")
	home_chant = chant if Sfx.has(chant) else ""
	_chant_in = randf_range(CHANT_EVERY.x * 0.5, CHANT_EVERY.y * 0.5)
	_play_intro.call_deferred()
	for t in 2:
		var lu: Lineup = d.lineup(t)
		for s in lu.all_skaters():
			_hook(s)
		if lu.goalie:
			_hook(lu.goalie)
			lu.goalie.save_made.connect(_on_save)
	Sfx.start_crowd()


func _hook(s: Skater) -> void:
	s.shot_released.connect(_on_shot)
	s.pass_released.connect(_on_pass)
	s.hit_landed.connect(_on_hit)
	s.poke_succeeded.connect(func(p: Skater, _v: Skater) -> void:
		Sfx.play("click", p.global_position, -4.0, 1.3)
		_say("pokecheck", 0.35, 1, 14.0))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	if director == null or director.puck == null:
		return
	Sfx.listener = director.puck.global_position
	if director.phase != MatchDirector.Phase.LIVE:
		_pinned = 0.0
		_pressure = 0.0
		return
	_live += delta
	# Home team pinned in its own zone, or pressing in the other one.
	_pinned = _pinned + delta if director._puck_in_defensive_zone(HOME) else 0.0
	_pressure = _pressure + delta if director._puck_in_defensive_zone(1 - HOME) else 0.0
	if _pinned > DEFENSE_AFTER and _live - _last_defense > REACT_COOLDOWN * 1.6:
		_last_defense = _live
		_react("chant_defense", -9.0, P_AMBIENT)
	if _pressure > RISING_AFTER and _live - _last_rising > REACT_COOLDOWN * 1.6:
		_last_rising = _live
		_react("rising", -8.0, P_AMBIENT)
		if not Sfx.organ_playing():
			Sfx.play_organ("organ_charge", -6.0)
	if _pressure <= 0.0 and _live - _last_rising < 20.0:
		Sfx.end_reaction(2.0, P_AMBIENT)   # the attack fizzled
	_check_breakaway()
	_check_carrier_moves()
	_check_final_minute()
	# Idle chatter after a long quiet spell in the booth.
	_idle_in -= delta
	if _idle_in <= 0.0 and Sfx.announcer_quiet_for() > 18.0:
		_idle_in = randf_range(30.0, 55.0)
		if not _banter("banter", 0.4):
			_say("idle", 1.0, 1, 0.0)
	_chant_in -= delta
	if _chant_in <= 0.0:
		_chant_in = randf_range(CHANT_EVERY.x, CHANT_EVERY.y)
		if home_chant != "" and not Sfx.reacting():
			_react(home_chant, -9.0, P_AMBIENT)


func _exit_tree() -> void:
	Sfx.stop_crowd()


func _on_surface(surface: String, speed: float, at: Vector3) -> void:
	if speed < 1.5:
		return
	var shot_live := _now() - float(_shot.time) < SHOT_WINDOW and _now() - _save_time > 0.3
	# A shot that misses the net and hits the end boards or glass behind it.
	if surface in ["boards", "glass"] and absf(at.z) > RinkSpec.GOAL_LINE_Z - 1.0 and shot_live:
		_shot.time = -100.0
		_say("miss", 0.5, 1, 10.0)
	if surface in ["boards", "glass"] and _home_shot_live() and absf(at.z) > RinkSpec.GOAL_LINE_Z - 1.0:
		_home_shot = -10.0
		_react("disappointed", -6.0, P_REACT)
	var loud := clampf(remap(speed, 1.5, 30.0, -18.0, 2.0), -18.0, 2.0)
	match surface:
		"boards":
			Sfx.play("boards", at, loud - 2.0)
		"glass":
			Sfx.play("glass", at, loud)
		"post":
			Sfx.play("post", at, loud + 2.0)
			if speed > 12.0:
				Sfx.play("ooh", Vector3.INF, -6.0)
			_shot.time = -100.0
			_say("post", 0.9, 2, 4.0)
			if _home_shot_live():
				_home_shot = -10.0
				_react("disappointed", -3.0, P_REACT)
		"net":
			Sfx.play("net", at, loud - 2.0)
		"body":
			Sfx.play("pad", at, loud - 4.0)
			# A skater (not the goalie) in the way of a fresh shot: blocked.
			if shot_live and speed > 8.0:
				var g := director.lineup(1 - int(_shot.team)).goalie
				if g and g.global_position.distance_to(at) > 2.5:
					_shot.time = -100.0
					_say("block", 0.6, 2, 12.0)


func _on_possession(c: Skater) -> void:
	if c and not (c is Goalie):
		Sfx.play("click", c.global_position, -9.0, 0.85)


## The team's attacking zone holds `p` (the zone in front of the other team's net).
func _in_attack_zone(t: int, p: Vector3) -> bool:
	return MatchRules.zone_of(p.z) == director.rink.defended_net(1 - t).index


func _on_pass(p: Skater, r: Skater) -> void:
	Sfx.play("click", p.global_position, -2.0)
	if r and r.is_defense and not p.is_defense and _in_attack_zone(p.team, r.global_position):
		_say("pass_point", 0.3, 1, 20.0)
		return
	# Quick passes low in the zone: cycling.
	if _in_attack_zone(p.team, p.global_position) and absf(p.global_position.z) > RinkSpec.END_DOT_Z:
		var now := _now()
		_low_passes.append(now)
		_low_passes = _low_passes.filter(func(t: float) -> bool: return now - t < 8.0)
		if _low_passes.size() >= 2:
			_low_passes.clear()
			_say("cycle", 0.5, 1, 30.0)
			return
	_say("pass", 0.12, 1, 14.0)


func _on_shot(s: Skater, kind: StringName, spd: float) -> void:
	if s.team == HOME:
		_home_shot = _live
	var slap := kind == &"slap" or kind == &"one_timer"
	Sfx.play("shot_slap" if slap else "shot_wrist", s.global_position, clampf(remap(spd, 10.0, 45.0, -6.0, 2.0), -8.0, 2.0))
	if s is Goalie:
		return
	# From outside the zone it's a dump-in, not a shot.
	if not _in_attack_zone(s.team, s.global_position):
		_say("dumpin", 0.3, 1, 20.0)
		return
	_shot = {"time": _now(), "team": s.team}
	_log_shot(s.team)
	var net := director.rink.defended_net(1 - s.team).global_position
	if kind == &"one_timer" and Sfx.has_line("onetimer"):
		_say("onetimer", 0.8, 2, 6.0)
	elif slap and spd > 34.0:
		_say("fullslapshot", 0.8, 2, 6.0)
	elif s.is_defense and s.global_position.distance_to(net) > POINT_SHOT and Sfx.has_line("shot_point"):
		_say("shot_point", 0.5, 1, 10.0)
	elif kind == &"wrist":
		_say_one_of(["shot", "shot_wrist"], 0.3, 1, 8.0)
	else:
		_say("shot", 0.3, 1, 8.0)


## One team taking shot after shot: "they're all over them".
func _log_shot(t: int) -> void:
	var now := _now()
	_shots_log.append(Vector2(now, t))
	_shots_log = _shots_log.filter(func(v: Vector2) -> bool: return now - v.x < STREAK_WINDOW)
	if _shots_log.size() < STREAK_SHOTS:
		return
	for v in _shots_log.slice(-STREAK_SHOTS):
		if int(v.y) != t:
			return
	_shots_log.clear()
	_say_later("hot_streak", 1.5, 1, 60.0)


func _on_hit(attacker: Skater, victim: Skater, power: float, kind: StringName, boards: bool) -> void:
	var at := victim.global_position
	var recorded := Sfx.has("board_hit") and Sfx.has("ice_hit")
	match kind:
		&"big_hit":
			if recorded:
				Sfx.play("board_hit" if boards else "ice_hit", at, 1.0)
			else:
				Sfx.play("big_hit", at, 2.0)
				if boards:
					Sfx.play("glass", at, 0.0)
			Sfx.play("ooh", Vector3.INF, -3.0)
			var lines := ["bighit"]
			if boards:
				lines.append("hit_boards")
			if _say_one_of(lines, 0.85, 2, 6.0):
				var heavy := attacker and (attacker.is_defense or attacker.stats.checking >= 70)
				if not _banter("banter_hit", 0.2, 1.6):
					_react_line("bighitenforcer" if heavy and Sfx.has_line("bighitenforcer") else "hit_react", 0.5, 1.6, 15.0)
			# The home crowd loves its own big hits and boos the visitors' on its players.
			if attacker and attacker.team == HOME:
				_react("cheer", -2.0, P_REACT)
			elif victim.team == HOME:
				_react("outrage" if Sfx.has("outrage") and randf() < 0.5 else "boo", -3.0, P_REACT)
		&"check":
			_say("check", 0.3, 1, 8.0)
			if recorded:
				Sfx.play("board_hit" if boards else "ice_hit", at, -7.0, 1.08)
			else:
				Sfx.play("body", at, -1.0)
				if boards:
					Sfx.play("boards", at, -3.0)
		_:
			Sfx.play("body", at, clampf(power - 14.0, -14.0, -6.0), 1.2)


func _on_save(g: Goalie, kind: StringName) -> void:
	_save_time = _now()
	_shot.time = -100.0
	Sfx.play("glove" if kind == &"catch" else "pad", g.global_position, -1.0)
	var big := false
	if _now() - float(_said.get("breakaway", -100.0)) < 4.0:
		big = _say("bigsave", 0.65, 2, 8.0)
	elif kind == &"catch":
		big = _say_one_of(["bigsave", "save_glove"], 0.65, 2, 8.0)
	if big:
		_react_line("save_react", 0.5, 1.4, 20.0)
	elif kind == &"rebound":
		_say_one_of(["save", "save_pad"], 0.35, 1, 8.0)
		_check_rebound(g)
	else:
		_say("save", 0.35, 1, 8.0)
	if g.team != HOME:
		_home_shot = -10.0
		_react("disappointed", -5.0, P_REACT)
		return
	# Glove saves get the bigger reaction.
	_react("cheer" if kind == &"catch" else "short_cheer", -4.0 if kind == &"catch" else -5.0, P_REACT)


## A save that leaves the puck loose in front of the net.
func _check_rebound(g: Goalie) -> void:
	await get_tree().create_timer(0.5).timeout
	if director == null or director.phase != MatchDirector.Phase.LIVE or not is_instance_valid(g):
		return
	var puck := director.puck
	if puck.carrier == null and puck.global_position.distance_to(g.net.global_position) < 4.0:
		_say("rebound", 0.6, 2, 12.0)


func _on_goal(team: int, scorer: Skater) -> void:
	_goal_time = _now()
	var other := 1 - team
	var score: Array = director.score
	var diff: int = score[team] - score[other]
	# The call itself: calm when it's already lopsided, "top shelf" when it went in high.
	if diff > 3 and Sfx.has_line("goal_calm"):
		_say("goal_calm", 1.0, 4, 0.0)
	elif director.puck.global_position.y > TOP_SHELF and Sfx.has_line("goal_topshelf") and randf() < 0.6:
		_say("goal_topshelf", 1.0, 4, 0.0)
	else:
		_say("goal", 1.0, 4, 0.0)
	# The follow-up, most remarkable first.
	var goals := 0
	if scorer and scorer.team == team:
		goals = int(_goals_by.get(scorer, 0)) + 1
		_goals_by[scorer] = goals
	var pp_for := director.strength(team) > director.strength(other) and director.lineup(other).box_count() > 0
	var short := director.strength(team) < director.strength(other)
	var last := director.period >= director.periods
	var follow := []
	if goals == 3:
		follow.append("goal_hattrick")
	if short:
		follow.append("goal_shorthanded")
	if pp_for:
		follow.append("goal_powerplay")
	if _worst[team] >= 2 and diff >= 0:
		follow.append("goal_comeback")
		_worst[team] = 0
	if diff == 0:
		follow.append("goal_tie")
	elif diff == 1:
		follow.append("goal_lead")
	elif diff == 2 and last:
		follow.append("goal_insurance")
	_worst[other] = maxi(_worst[other], diff)
	var picked := ""
	for line: String in follow:
		if Sfx.has_line(line) or Sfx.log_events:
			picked = line
			break
	if picked != "":
		_say_later(picked, 2.4, 3, 0.0)
	elif not _banter("banter_goal", 0.35, 2.4) and randf() < 0.5:
		# Nothing remarkable: a reaction, the crowd's for home goals when there is one.
		var reacts := ["goal_react_home", "goal_react"] if team == HOME else ["goal_react"]
		for line: String in reacts:
			if Sfx.has_line(line):
				_say_later(line, 2.4, 3, 0.0)
				break
	if team == HOME:
		Sfx.play("horn", Vector3.INF, -2.0)
		_react("goal_cheer" if Sfx.has("goal_cheer") else "cheer", 0.0, P_GOAL)
	else:
		# The arena goes quiet but for a groan; no horn for the visitors.
		_react("big_boo", -6.0, P_GOAL)


func _on_penalty(offender: Skater, kind: StringName) -> void:
	var line: String = {&"tripping": "trippingcall", &"boarding": "bigpenalty", &"interference": "interference"}.get(kind, "penalty")
	if not Sfx.has_line(line):
		line = "penalty"
	_say(line, 1.0, 3, 0.0)
	if not _banter("banter_penalty", 0.35, 3.2):
		_say_later("powerplay", 3.2, 2)
	if offender.team == HOME:
		_react("boo", -4.0, P_REACT)
	else:
		_react("cheer", -6.0, P_REACT)


func _on_penalty_expired(t: int) -> void:
	if director.lineup(t).box_count() == 0:
		_say("pk_success", 0.7, 2, 0.0)


func _on_faceoff_won(team: int) -> void:
	if _now() - _goal_time < 12.0:
		return
	# From the player's side: their team's losses get called too.
	var human_lost := director.control(1 - team) != null and Sfx.has_line("faceoff_loss")
	if human_lost and randf() < 0.5:
		_say("faceoff_loss", 0.3, 1, 25.0)
	else:
		_say("faceoff_win", 0.3, 1, 25.0)


func _on_phase(phase: MatchDirector.Phase) -> void:
	var was := _prev_phase
	_prev_phase = phase
	match phase:
		MatchDirector.Phase.STOPPAGE:
			Sfx.end_reaction(1.5, P_AMBIENT)
			if _now() - _goal_time > 0.5:
				Sfx.play("whistle", Vector3.INF, -4.0)
				_organ_later(1.2)
			if was == MatchDirector.Phase.FIGHT and director.stats.fights > _fights_seen:
				_fights_seen = director.stats.fights
				_banter("banter_fight", 0.8, 1.2)
			elif _now() - _goal_time > 0.5:
				# Offside, icing and penalty calls (higher priority) talk over this.
				_say.call_deferred("whistle", 0.35, 1, 20.0)
		MatchDirector.Phase.FACEOFF:
			if director.period != _period_called:
				_period_called = director.period
				_say_period_start.call_deferred()
			elif _now() - _goal_time < 12.0:
				_say("centerice", 0.8, 2, 10.0)
			elif not _say_game_state():
				_say("faceoff", 0.35, 1, 20.0)
		MatchDirector.Phase.PERIOD_END:
			_say("periodend", 1.0, 3, 0.0)
			_banter("banter_intermission", 0.8, 3.5)
			_organ_later(3.5)
			if _now() - _goal_time > 0.5:
				Sfx.play("horn", Vector3.INF, -5.0)
		MatchDirector.Phase.SHOOTOUT:
			if _now() - _goal_time > 0.5:
				Sfx.play("horn", Vector3.INF, -5.0)
			_say_later("shootout", 1.5, 3, 0.0, true)
		MatchDirector.Phase.FINAL:
			if was != MatchDirector.Phase.SHOOTOUT and _now() - _goal_time > 0.5:
				Sfx.play("horn", Vector3.INF, -5.0)
			# After an overtime winner, let the goal call finish first.
			var at := 2.6 if _now() - _goal_time < 3.0 else 0.4
			_say_later("final_horn", at, 3, 0.0, true)
			if not _banter("banter_final", 0.5, at + 2.2, true):
				_react_line("final_react", 0.8, at + 2.2, 0.0, true)
		MatchDirector.Phase.PREGAME:
			# Leaving the matchup screen: Steve and Bobby open the broadcast together.
			if was == MatchDirector.Phase.INTRO:
				_opened = _say("intro_duet" if Sfx.has_line("intro_duet") else "intro", 1.0, 3, 0.0)
		MatchDirector.Phase.LIVE:
			Sfx.stop_organ(1.2)
			if was == MatchDirector.Phase.FACEOFF:
				Sfx.play("click", director.puck.global_position, -3.0, 0.8)


## Late in a close game, or a lopsided one: once a period, at a faceoff. True if said.
func _say_game_state() -> bool:
	var diff := absi(int(director.score[0]) - int(director.score[1]))
	var p := director.period
	var line := ""
	if diff >= 4:
		line = "blowout"
	elif diff <= 1 and p >= director.periods and director.clock < director.period_length * 0.6:
		line = "close_game"
	if line == "" or int(_state_called.get(line, 0)) == p or randf() > 0.6:
		return false
	var duet := "banter_blowout" if line == "blowout" else "banter_close"
	if not (Sfx.has_line(line) or Sfx.has_line(duet)):
		return false
	_state_called[line] = p
	if Sfx.has_line(duet) and (not Sfx.has_line(line) or randf() < 0.4):
		_say(duet, 1.0, 2, 0.0)
	else:
		_say(line, 1.0, 1, 0.0)
	return true


## One minute left in the last period of regulation (or overtime).
func _check_final_minute() -> void:
	var c := director.clock
	if director.period >= director.periods and _last_clock >= 60.0 and c < 60.0 and director.period_length > 90.0:
		_say("final_minute", 1.0, 3, 0.0)
	_last_clock = c


func _home_shot_live() -> bool:
	return _live - _home_shot < SHOT_WINDOW


## Organ over a stoppage, once the whistle has had its moment.
func _organ_later(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if director and director.phase in [MatchDirector.Phase.STOPPAGE, MatchDirector.Phase.FACEOFF, MatchDirector.Phase.PERIOD_END]:
		Sfx.play_organ("organ_upbeat", -9.0, true)


# --- Announcer -------------------------------------------------------------------

## Says `line` with probability `chance`, if it hasn't been said in `cooldown` seconds.
func _say(line: String, chance: float, priority: int, cooldown: float) -> bool:
	var now := _now()
	if now - float(_said.get(line, -100.0)) < cooldown or randf() > chance:
		return false
	if Sfx.announce(line, priority):
		_said[line] = now
		return true
	if Sfx.log_events and not Sfx.has_line(line):
		_said[line] = now   # as if said, so the log shows the real rate
		print("[audio] %.1f announcer %s (not recorded)" % [now, line])
		return true
	return false


## Steve and Bobby going back and forth (a "both" line), with probability `chance`, now
## or after `delay` seconds. False when it isn't recorded or the chance says no, so the
## caller can fall back to a solo line. Banter outranks routine calls (priority 2) and
## each piece waits 45 s before it can come up again.
func _banter(line: String, chance: float, delay := 0.0, after_final := false) -> bool:
	if randf() > chance or _now() - float(_said.get(line, -100.0)) < 45.0:
		return false
	if not Sfx.has_line(line):
		if Sfx.log_events:
			_said[line] = _now()
			print("[audio] %.1f announcer %s (not recorded)" % [_now(), line])
		return false
	if delay > 0.0:
		_say_later(line, delay, 2, 45.0, after_final)
	else:
		_say(line, 1.0, 2, 45.0)
	return true


## The color commentator's reaction once the play-by-play call is done: `line` after
## `delay` seconds, with probability `chance`.
func _react_line(line: String, chance: float, delay: float, cooldown := 0.0, after_final := false) -> void:
	if randf() < chance:
		_say_later(line, delay, 1, cooldown, after_final)


func _say_later(line: String, delay: float, priority: int, cooldown := 0.0, after_final := false) -> void:
	await get_tree().create_timer(delay).timeout
	if director and (after_final or director.phase != MatchDirector.Phase.FINAL):
		_say(line, 1.0, priority, cooldown)


## A carrier racing at the net with no defender between them and it (the goalie
## doesn't count): called once per rush.
func _check_breakaway() -> void:
	var c := _carrier
	if c == null or c is Goalie or c == _breakaway_for or not director.puck.carrier == c:
		return
	var net := director.rink.defended_net(1 - c.team)
	var to_net := net.global_position - c.global_position
	to_net.y = 0.0
	var dist := to_net.length()
	if dist > 26.0 or dist < 6.0 or c.velocity.dot(to_net / dist) < 5.0:
		return
	for o: Skater in director.lineup(1 - c.team).on_ice:
		if o is Goalie:
			continue
		var od := Vector2(net.global_position.x - o.global_position.x, net.global_position.z - o.global_position.z).length()
		if od < dist + 1.0:
			return
	_breakaway_for = c
	_say("breakaway", 0.9, 3, 10.0)


func _on_whistle(reason: StringName) -> void:
	match reason:
		&"offside":
			_say("offsides", 0.85, 2, 0.0)
		&"icing":
			_say("icing", 0.85, 2, 0.0)


## Start of a period: overtime, the second or third period's own line, else "newperiod".
func _say_period_start() -> void:
	# Let the end-of-period call finish first (up to a few seconds).
	var waited := 0.0
	while Sfx.announcing() and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var p := director.period
	if p == 1 and _opened:
		return   # the duet welcome already opened the game
	var own: String = "overtime" if p > director.periods else {2: "second_period", 3: "third_period"}.get(p, "")
	_say(own if Sfx.has_line(own) else "newperiod", 1.0, 3, 0.0)
	if p == 3:
		_react_line("third_stakes", 0.7, 2.6)


## One of several lines (only those that exist), sharing the first one's cooldown.
func _say_one_of(lines: Array, chance: float, priority: int, cooldown: float) -> bool:
	var have := lines.filter(func(l: String) -> bool: return Sfx.has_line(l))
	var key: String = lines[0]
	var now := _now()
	if now - float(_said.get(key, -100.0)) < cooldown or randf() > chance:
		return false
	if have.is_empty():
		if Sfx.log_events:
			_said[key] = now
			print("[audio] %.1f announcer %s (not recorded)" % [now, key])
			return true
		return false
	if Sfx.announce(have[randi() % have.size()], priority):
		_said[key] = now
		return true
	return false


## The matchup screen: "Tonight: a matchup between the <home>" + "and the <away>."
## (The welcome follows as the screen closes: _on_phase, PREGAME.)
func _play_intro() -> void:
	var home: String = Teams.team(director.team_ids[HOME]).get("call", "")
	var away: String = Teams.team(director.team_ids[1 - HOME]).get("call", "")
	if home == "" or away == "":
		return
	Sfx.announce_chain(["intro_home_" + home, "intro_away_" + away], 4)


func _on_carrier(c: Skater) -> void:
	# A turnover: the puck goes straight from one team's carrier to the other's.
	if c and _prev_carrier and not (c is Goalie) and not (_prev_carrier is Goalie) \
			and c.team != _prev_carrier.team and _now() - _carrier_lost < 0.8:
		_say("turnover", 0.35, 1, 15.0)
	# A puck battle: possession flipping between the teams again and again.
	if c and _prev_carrier and c.team != _prev_carrier.team:
		var now := _now()
		_flips.append(now)
		_flips = _flips.filter(func(t: float) -> bool: return now - t < 5.0)
		if _flips.size() >= 3:
			_flips.clear()
			_say("checking", 0.8, 2, 25.0)
	if c == null and _carrier:
		_carrier_lost = _now()
	if c:
		_prev_carrier = c
		if c != _carrier:
			_carrier_since = _now()
			_moves_called.clear()
	_carrier = c
	_deke_called = false


## What the carrier is doing: dekes, rushes across center, zone entries, trips behind
## the net and along the boards, and holding the puck up looking for an opening.
func _check_carrier_moves() -> void:
	var c := _carrier
	if c == null or c is Goalie or director.puck.carrier != c:
		return
	var pos := c.global_position
	var speed := Vector2(c.velocity.x, c.velocity.z).length()
	if c.state == Skater.State.DEKE:
		if not _deke_called:
			_deke_called = true
			_say("deke", 0.45, 1, 10.0)
	# Heading down the ice: crossing center toward the other net, with speed.
	var net_z := director.rink.defended_net(1 - c.team).global_position.z
	var toward := net_z - pos.z
	if c != _rush_called_for and absf(pos.z) < 1.5 and c.velocity.z * signf(toward) > 6.0:
		_rush_called_for = c
		_say("downice", 0.3, 1, 20.0)
	var in_zone := _in_attack_zone(c.team, pos)
	if in_zone and not _moves_called.has("entry"):
		_moves_called["entry"] = true
		if c.is_defense and c != _rush_for:
			_rush_for = c
			_say("defenderup", 0.6, 2, 20.0)
		elif not c.is_defense and _now() - _carrier_since > 0.5:
			_say("blueline", 0.25, 1, 20.0)
	if in_zone and absf(pos.z) > RinkSpec.GOAL_LINE_Z + 0.5 and signf(pos.z) == signf(net_z) and not _moves_called.has("behindnet"):
		_moves_called["behindnet"] = true
		_say("behindnet", 0.35, 1, 20.0)
	if -RinkSpec.sdf(pos.x, pos.z) < 1.5 and speed > 4.0 and not _moves_called.has("boards"):
		_moves_called["boards"] = true
		_say("boards_carry", 0.12, 1, 30.0)
	if in_zone and speed < 3.0 and _now() - _carrier_since > 2.5 and not _moves_called.has("setup"):
		_moves_called["setup"] = true
		_say("setup", 0.4, 1, 25.0)


## A crowd reaction (Sfx.crowd_react), remembered for the announcer's read on the crowd.
func _react(sound: String, volume_db := 0.0, priority := 1) -> void:
	Sfx.crowd_react(sound, volume_db, priority)
	var feel := 1.0 if (sound in GOOD_REACTIONS or sound.begins_with("chant_")) else (-1.0 if sound in BAD_REACTIONS else 0.0)
	if feel == 0.0:
		return
	var now := _now()
	_mood.append(Vector2(now, feel))
	_mood = _mood.filter(func(m: Vector2) -> bool: return now - m.x < MOOD_WINDOW)
	var same := _mood.filter(func(m: Vector2) -> bool: return m.y == feel).size()
	if same >= MOOD_COUNT:
		var line := "crowdreactgood" if feel > 0.0 else "crowdreactbad"
		if now - float(_said.get("crowdreact", -100.0)) > 90.0 and Sfx.has_line(line):
			_said["crowdreact"] = now
			_mood.clear()
			_say_later(line, 2.5, 1)
