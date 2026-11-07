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
## The announcer (Sfx.announce) calls the play: faceoffs, passes, shots, big slap shots,
## saves and big saves, big hits, poke checks, breakaways, penalties and the power play
## that follows, offsides and icing, each period's start and end, goals, and idle
## chatter when the booth has been quiet a while. Every game opens with the intro: the
## home team's "Tonight: a matchup between the <home>" then the away team's "and the
## <away>." (Teams `call`; skipped when either half is missing). Also: posts, dekes,
## checks, one-timers, turnovers, puck battles where possession keeps flipping
## (checking: "they're really fighting for it!"), a carrier crossing center on a rush
## (downice: "heading down the ice"), a defenseman carrying into the zone ("defender
## up"), back to center ice after a goal, and big hits (bighit / flattened / gottahurt,
## plus bighitenforcer from heavy hitters). When the home crowd has reacted the same way
## a few times lately (cheers vs. boos and groans), he remarks on it (crowdreactgood /
## bad). Each line has a chance and a cooldown so the commentary stays occasional;
## missing lines are simply skipped.

const HOME := 0
const CHANT_EVERY := Vector2(55.0, 110.0)     ## seconds of live play between team chants
const DEFENSE_AFTER := 5.0                    ## seconds pinned in the home zone before "De-fense!"
const RISING_AFTER := 3.0                     ## seconds of home pressure before the crowd builds
const REACT_COOLDOWN := 25.0
const MOOD_WINDOW := 75.0                     ## seconds of crowd reactions the announcer weighs
const MOOD_COUNT := 3                         ## same-way reactions in the window before he remarks
const GOOD_REACTIONS := ["cheer", "short_cheer", "goal_cheer", "chant_defense"]
const BAD_REACTIONS := ["boo", "big_boo", "outrage", "disappointed"]
const SHOT_WINDOW := 1.6                      ## seconds a home shot counts as "just taken"

## Reaction priorities (a reaction only interrupts one of equal or lower priority).
enum { P_AMBIENT = 1, P_REACT = 2, P_GOAL = 3 }

var director: MatchDirector
var home_chant := ""          ## the home team's chant (Teams.LIST)
var _goal_time := -100.0
var _prev_phase := -1
var _chant_in := 60.0
var _pinned := 0.0
var _pressure := 0.0
var _last_defense := -100.0
var _last_rising := -100.0
var _live := 0.0
var _said := {}                ## announcer line -> _now() when last said
var _carrier: Skater
var _period_called := 0      ## the last period whose start was announced
var _idle_in := 25.0
var _breakaway_for: Skater     ## the carrier the breakaway was already called for
var _deke_called := false
var _rush_for: Skater          ## the defenseman whose rush was already called
var _prev_carrier: Skater
var _carrier_lost := -10.0     ## _now() when the last carrier lost the puck
var _flips: Array[float] = []  ## _now() of recent possession changes between teams
var _rush_called_for: Skater   ## carrier whose trip down the ice was already called
var _mood: Array[Vector2] = [] ## recent crowd reactions: (_now(), +1 good / -1 bad)
var _home_shot := -10.0        ## _live time of the last home shot still in the air


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
	s.pass_released.connect(func(p: Skater, _r: Skater) -> void:
		Sfx.play("click", p.global_position, -2.0)
		_say("pass", 0.12, 1, 14.0))
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
	# Idle chatter after a long quiet spell in the booth.
	_idle_in -= delta
	if _idle_in <= 0.0 and Sfx.announcer_quiet_for() > 18.0:
		_idle_in = randf_range(30.0, 55.0)
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
	# A home shot that misses the net and hits the end boards or glass behind it.
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
			_say("post", 0.9, 2, 4.0)
			if _home_shot_live():
				_home_shot = -10.0
				_react("disappointed", -3.0, P_REACT)
		"net":
			Sfx.play("net", at, loud - 2.0)
		"body":
			Sfx.play("pad", at, loud - 4.0)


func _on_possession(c: Skater) -> void:
	if c and not (c is Goalie):
		Sfx.play("click", c.global_position, -9.0, 0.85)


func _on_shot(s: Skater, kind: StringName, spd: float) -> void:
	if s.team == HOME:
		_home_shot = _live
	if kind == &"one_timer" and Sfx.has_line("onetimer"):
		_say("onetimer", 0.8, 2, 6.0)
	elif (kind == &"slap" or kind == &"one_timer") and spd > 34.0:
		_say("fullslapshot", 0.8, 2, 6.0)
	elif not (s is Goalie):
		_say("shot", 0.3, 1, 8.0)
	var slap := kind == &"slap" or kind == &"one_timer"
	Sfx.play("shot_slap" if slap else "shot_wrist", s.global_position, clampf(remap(spd, 10.0, 45.0, -6.0, 2.0), -8.0, 2.0))


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
			var lines := ["bighit", "flattened", "gottahurt"]
			if attacker and (attacker.is_defense or attacker.stats.checking >= 70):
				lines.append("bighitenforcer")
			_say_one_of(lines, 0.85, 2, 6.0)
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
	Sfx.play("glove" if kind == &"catch" else "pad", g.global_position, -1.0)
	if kind == &"catch" or _now() - float(_said.get("breakaway", -100.0)) < 4.0:
		_say("bigsave", 0.65, 2, 8.0)
	else:
		_say("save", 0.35, 1, 8.0)
	if g.team != HOME:
		_home_shot = -10.0
		_react("disappointed", -5.0, P_REACT)
		return
	if g.team == HOME:
		# Glove saves get the bigger reaction.
		_react("cheer" if kind == &"catch" else "short_cheer", -4.0 if kind == &"catch" else -5.0, P_REACT)


func _on_goal(team: int, _scorer: Skater) -> void:
	_goal_time = _now()
	_say("goal", 1.0, 4, 0.0)
	if team == HOME:
		Sfx.play("horn", Vector3.INF, -2.0)
		_react("goal_cheer" if Sfx.has("goal_cheer") else "cheer", 0.0, P_GOAL)
	else:
		# The arena goes quiet but for a groan; no horn for the visitors.
		_react("big_boo", -6.0, P_GOAL)


func _on_penalty(offender: Skater, kind: StringName) -> void:
	var line := "penalty"
	if kind == &"tripping" and Sfx.has_line("trippingcall"):
		line = "trippingcall"
	elif kind == &"boarding" and Sfx.has_line("bigpenalty"):
		line = "bigpenalty"
	elif kind == &"interference" and Sfx.has_line("interference"):
		line = "interference"
	_say(line, 1.0, 3, 0.0)
	_say_later("powerplay", 3.2, 2)
	if offender.team == HOME:
		_react("boo", -4.0, P_REACT)
	else:
		_react("cheer", -6.0, P_REACT)


func _on_phase(phase: MatchDirector.Phase) -> void:
	var was := _prev_phase
	_prev_phase = phase
	match phase:
		MatchDirector.Phase.STOPPAGE:
			Sfx.end_reaction(1.5, P_AMBIENT)
			if _now() - _goal_time > 0.5:
				Sfx.play("whistle", Vector3.INF, -4.0)
				_organ_later(1.2)
		MatchDirector.Phase.FACEOFF:
			if _now() - _goal_time < 12.0:
				_say("centerice", 0.8, 2, 10.0)
			if director.period != _period_called:
				_period_called = director.period
				_say_period_start.call_deferred()
		MatchDirector.Phase.PERIOD_END, MatchDirector.Phase.FINAL:
			if phase == MatchDirector.Phase.PERIOD_END:
				_say("periodend", 1.0, 3, 0.0)
				_organ_later(3.5)
			if _now() - _goal_time > 0.5:
				Sfx.play("horn", Vector3.INF, -5.0)
		MatchDirector.Phase.LIVE:
			Sfx.stop_organ(1.2)
			if was == MatchDirector.Phase.FACEOFF and _now() - _goal_time > 12.0:
				_say("faceoff", 0.35, 1, 20.0)
				Sfx.play("click", director.puck.global_position, -3.0, 0.8)


func _home_shot_live() -> bool:
	return _live - _home_shot < SHOT_WINDOW


## Organ over a stoppage, once the whistle has had its moment.
func _organ_later(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if director and director.phase in [MatchDirector.Phase.STOPPAGE, MatchDirector.Phase.FACEOFF, MatchDirector.Phase.PERIOD_END]:
		Sfx.play_organ("organ_upbeat", -9.0, true)


# --- Announcer -------------------------------------------------------------------

## Says `line` with probability `chance`, if it hasn't been said in `cooldown` seconds.
func _say(line: String, chance: float, priority: int, cooldown: float) -> void:
	var now := _now()
	if now - float(_said.get(line, -100.0)) < cooldown or randf() > chance:
		return
	if Sfx.announce(line, priority):
		_said[line] = now


func _say_later(line: String, delay: float, priority: int) -> void:
	await get_tree().create_timer(delay).timeout
	if director and director.phase != MatchDirector.Phase.FINAL:
		_say(line, 1.0, priority, 0.0)


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


## Start of a period: its own line (period2, period3, ...) if there is one, else
## "newperiod" (the first period, overtime, or periods without their own line).
func _say_period_start() -> void:
	# Let the end-of-period call finish first (up to a few seconds).
	var waited := 0.0
	while Sfx.announcing() and waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var own := "period%d" % director.period
	if Sfx.has_file(own) and Sfx.announce_file(own, 3):
		_said["newperiod"] = _now()
		return
	_say("newperiod", 1.0, 3, 0.0)


## One of several lines (only those that exist), sharing the first one's cooldown.
func _say_one_of(lines: Array, chance: float, priority: int, cooldown: float) -> void:
	var have := lines.filter(func(l: String) -> bool: return Sfx.has_line(l))
	if have.is_empty():
		return
	var key: String = lines[0]
	var now := _now()
	if now - float(_said.get(key, -100.0)) < cooldown or randf() > chance:
		return
	if Sfx.announce(have[randi() % have.size()], priority):
		_said[key] = now


## "Tonight: a matchup between the <home>" + "and the <away>."
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
	_carrier = c
	_deke_called = false


## Dekes, rushes across center, and a defenseman carrying into the offensive zone.
func _check_carrier_moves() -> void:
	var c := _carrier
	if c == null or c is Goalie or director.puck.carrier != c:
		return
	if c.state == Skater.State.DEKE:
		if not _deke_called:
			_deke_called = true
			_say("deke", 0.45, 1, 10.0)
	# Heading down the ice: crossing center toward the other net, with speed.
	var toward := director.rink.defended_net(1 - c.team).global_position.z - c.global_position.z
	if c != _rush_called_for and absf(c.global_position.z) < 1.5 and c.velocity.z * signf(toward) > 6.0:
		_rush_called_for = c
		_say("downice", 0.3, 1, 20.0)
	if c.is_defense and c != _rush_for and director._puck_in_defensive_zone(1 - c.team):
		_rush_for = c
		_say("defenderup", 0.6, 2, 20.0)


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
