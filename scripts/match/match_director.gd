class_name MatchDirector
extends Node3D
## Runs an exhibition game: rosters and lines, faceoffs, game clock, periods (teams switch
## ends), offsides/icing/penalties, overtime modes, the shootout, scoring and the HUD.
##
## Phase flow:  PREGAME → FACEOFF → LIVE → (goal / whistle) STOPPAGE → FACEOFF …
##              LIVE (clock 0) → PERIOD_END → next period … → [OT] → [SHOOTOUT] → FINAL
##
## Settings come from GameSettings (the setup screen) unless use_game_settings is false.
## Command-line (after `--`): ai, format=3|5, period=<s>, diff=<0..1>, ot=off|sudden_death|
## shootout|sd_so, norules, cam=…, shot=<png>, wait=<s>

signal phase_changed(phase: Phase)
signal goal(team: int, scorer: Skater)
signal whistle_blown(reason: StringName)
signal penalty_called(offender: Skater, kind: StringName)
signal match_finished(score: Array)

enum Phase { PREGAME, FACEOFF, LIVE, STOPPAGE, PERIOD_END, SHOOTOUT, FINAL, INTRO, FIGHT }

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

const F_NUMBERS := [[19, 11, 27, 9, 17, 22, 13, 8, 26, 14, 10, 16], [91, 88, 12, 15, 21, 24, 18, 23, 28, 29, 20, 63]]
const D_NUMBERS := [[4, 44, 2, 5, 7, 3], [55, 77, 33, 47, 6, 2]]
const G_NUMBERS := [1, 30]
const F_POS := ["C", "LW", "RW"]
const BENCH_GATES := [Vector3(-RinkSpec.HALF_W + 1.3, 0, 4.5), Vector3(-RinkSpec.HALF_W + 1.3, 0, -4.5)]
const BOX_GATE := Vector3(RinkSpec.HALF_W - 1.3, 0, 0)
const FOUL_CHANCE := {&"tripping": 0.65, &"interference": 0.4, &"boarding": 0.8}
const FOUL_NAMES := {&"tripping": "TRIPPING", &"interference": "INTERFERENCE", &"boarding": "BOARDING"}
const SHOOTOUT_NET := 1
const SHOOTOUT_TIME := 9.0
const INTERMISSION_AFTER := 2.5   ## seconds after the period ends before the stats screen
## Fights (DESIGN §5.1): hits on a team build its tension; at FIGHT_TENSION its toughest
## skater on the ice may drop the gloves with the hitter.
const FIGHT_TENSION := 1.0
const FORCED_TENSION := 1.25     ## an aggressive hitter starts it without asking from here
const FIGHT_GAP := 200.0         ## seconds of live play between fights, at least
const FIGHT_MAJOR := 300.0       ## 5:00 offsetting majors
const FIGHT_COOLDOWN := 60.0     ## sitting out instead, when penalties are off
const MOMENTUM_TIME := 75.0
const INTRO_MIN := 3.5            ## the matchup screen shows at least this long...
const INTRO_MAX := 9.0            ## ...and at most this long (the intro line normally ends it)

@export var use_game_settings := true
@export var format := 5
@export var period_length := 180.0
@export var periods := 3
@export var overtime_mode := "sd_so"
@export var ot_length := 180.0
@export var shootout_rounds := 3
@export var offsides := true
@export var icing := true
@export var penalties := true
@export var line_changes := true
@export var fighting := true
@export_range(0.0, 1.0) var difficulty := 0.5
@export var rng_seed := 0
@export var team_ids: Array[int] = [0, 1]   ## Teams.LIST index for home, away
@export var show_hud := true
var humans: Array = [{"kind": "any", "pad": 0, "team": 0}]

@onready var rink: Rink = $Rink
@onready var puck: Puck = $Puck
@onready var cam: BroadcastCamera = $Camera
@onready var sun: DirectionalLight3D = $Sun

var phase := Phase.PREGAME
var period := 1
var clock := 0.0
var score := [0, 0]
var stats := {"shots": [0, 0], "saves": [0, 0], "hits": [0, 0], "big_hits": [0, 0], "faceoffs": [0, 0],
		"penalties": [0, 0], "pp_goals": [0, 0], "offsides": 0, "icings": 0, "changes": [0, 0],
		"period_goals": [[0, 0, 0, 0], [0, 0, 0, 0]], "fights": 0}   ## per team: goals in periods 1-3 and OT
var teams: Array[Dictionary] = []    ## {lineup: Lineup, goalie: Goalie, ai: TeamAI, control: TeamControl}
var rules: MatchRules
var shootout := {}
var _intermission: Intermission
var _intro_stage: Node3D
var _pause: PauseMenu
var _fight: Fight
var tension := [0.0, 0.0]     ## per team: built by hits taken (see FIGHT_TENSION)
var momentum := [0.0, 0.0]    ## per team: seconds of momentum left after winning a fight
var _last_hitter: Array = [null, null]   ## per team: who last hit them
var _last_victim: Array = [null, null]
var _since_fight := 999.0
var _fight_spot := Vector3.ZERO
var _debug_fight := ""        ## `-- fight` / `fight=prompt`: start a fight at the first chance (testing)
var _showcase: Array[Skater] = []
var _no_intro := false

var _phase_time := 0.0
var _stoppage_len := 0.0
var _next_dot := Vector2.ZERO
var _fo := {}
var _last_in_play := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _hud: MatchHud


func _ready() -> void:
	process_physics_priority = -10 # roles and phases update before skaters move
	if use_game_settings:
		_apply_settings(GameSettings.config, GameSettings.humans)
	_parse_cmdline()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	rules = MatchRules.new(self)
	rules.offsides = offsides
	rules.icing = icing
	rules.penalties = penalties
	_build_teams()
	var home_logo: String = Teams.team(team_ids[0]).get("logo", "")
	if ResourceLoader.exists(home_logo):
		rink.set_center_logo(load(home_logo))
	var audio := MatchAudio.new()
	add_child(audio)
	audio.setup(self)
	rink.goal_scored.connect(_on_goal)
	puck.left_play.connect(_on_left_play)
	puck.touched.connect(_on_puck_touched)
	puck.released.connect(func(by: Skater, at: Vector3) -> void: rules.on_released(by, at))
	clock = period_length
	if show_hud:
		_hud = MatchHud.new()
		add_child(_hud)
		_hud.setup(self)
	if show_hud and not _no_intro:
		_start_intro()
	else:
		_set_phase(Phase.PREGAME)
		_place_for_faceoff(Vector2.ZERO)


func _apply_settings(c: Dictionary, h: Array) -> void:
	format = int(c.get("format", format))
	period_length = float(c.get("period_length", period_length))
	periods = int(c.get("periods", periods))
	overtime_mode = str(c.get("overtime", overtime_mode))
	ot_length = float(c.get("ot_length", ot_length))
	shootout_rounds = int(c.get("shootout_rounds", shootout_rounds))
	offsides = bool(c.get("offsides", offsides))
	icing = bool(c.get("icing", icing))
	penalties = bool(c.get("penalties", penalties))
	line_changes = bool(c.get("line_changes", line_changes))
	fighting = bool(c.get("fighting", fighting))
	difficulty = float(c.get("difficulty", difficulty))
	team_ids = [int(c.get("home_team", team_ids[0])), int(c.get("away_team", team_ids[1]))]
	humans = h.duplicate(true)


func _parse_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("ai"):
		humans = []
	if args.has("format"):
		format = 3 if args["format"] == "3" else 5
	if args.has("period"):
		period_length = float(args["period"])
		ot_length = period_length
	if args.has("diff"):
		difficulty = clampf(float(args["diff"]), 0.0, 1.0)
	if args.has("home"):
		team_ids[0] = int(args["home"])
	if args.has("away"):
		team_ids[1] = int(args["away"])
	if args.has("ot"):
		overtime_mode = str(args["ot"])
	if args.has("norules"):
		offsides = false
		icing = false
		penalties = false
	if args.has("cam"):
		var idx := BroadcastCamera.Mode.keys().find(str(args["cam"]).to_upper())
		if idx >= 0:
			cam.call_deferred("set_mode", idx)
	if args.has("nointro"):
		_no_intro = true
	if args.has("fight"):
		_debug_fight = "prompt" if args["fight"] == "prompt" else "on"
	if args.has("pausemenu"):   # open the pause menu at once (screenshots); pausemenu=controls for that page
		_open_pause_for_shot.call_deferred(args["pausemenu"] == "controls")
	if args.has("statscreen"):   # open the stats screen at once (screenshots / layout checks)
		_open_intermission.call_deferred(args["statscreen"] == "final")
	if args.has("shot"):
		_screenshot.call_deferred(str(args["shot"]), float(args.get("wait", "3.0")))


func _screenshot(path: String, wait: float) -> void:
	await get_tree().create_timer(wait, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# --- Teams -------------------------------------------------------------------

func _build_teams() -> void:
	for t in 2:
		var lu := Lineup.new()
		lu.team = t
		lu.format = format
		lu.line_changes = line_changes
		var roster := Rosters.for_team(str(Teams.team(team_ids[t]).abbr))
		if roster.is_empty():
			_generate_players(lu, t)
		else:
			_roster_players(lu, t, roster)
		var g: Goalie = lu.goalie
		g.fatigue_enabled = false
		lu.build_groups()
		teams.append({"lineup": lu, "goalie": g})
	for t in 2:
		var lu: Lineup = teams[t].lineup
		var other: Lineup = teams[1 - t].lineup
		var ai := TeamAI.new(t, lu.on_ice, other.on_ice, lu.goalie, puck, rink)
		ai.opp_goalie = other.goalie
		ai.difficulty = difficulty
		ai.offsides = offsides
		ai.bench_gate = BENCH_GATES[t]
		teams[t]["ai"] = ai
		for s in lu.all_skaters():
			s.teammates = lu.on_ice
			s.opponents = other.on_ice
			s.fatigue_enabled = line_changes
			s.ai_brain = AIBrain.new(ai, _rng.randi())
			s.brain = s.ai_brain
			s.shot_released.connect(_on_shot)
			s.hit_landed.connect(_on_hit)
			s.foul_committed.connect(_on_foul)
		var g: Goalie = lu.goalie
		g.teammates = lu.on_ice
		g.opponents = other.on_ice
		g.net = rink.defended_net(t)
		g.save_made.connect(_on_save)
		g.froze_puck.connect(_on_freeze)
		g.shot_released.connect(_on_shot)
		var brains: Array[HumanBrain] = []
		for i in humans.size():
			if int(humans[i].get("team", 0)) == t:
				brains.append(HumanBrain.from_spec(humans[i], i))
		teams[t]["control"] = TeamControl.new(t, lu.on_ice, lu.all_skaters(), brains, puck, g) if not brains.is_empty() else null


const FEMALE_SHARE := [0.5, 0.4]


## Generated players for a team without a roster in the sheet: 4 lines, 3 pairs.
func _generate_players(lu: Lineup, t: int) -> void:
	for i in 12:
		var s: Skater = SKATER_SCENE.instantiate()
		_setup_player(s, t, F_NUMBERS[t][i], i % 3 != 2)
		s.position_name = F_POS[i % 3]
		s.stats.shot_power = mini(99, s.stats.shot_power + 6)
		s.stats.shot_accuracy = mini(99, s.stats.shot_accuracy + 6)
		lu.forwards.append(s)
	for i in 6:
		var s: Skater = SKATER_SCENE.instantiate()
		_setup_player(s, t, D_NUMBERS[t][i], i % 2 == 0)
		s.position_name = "D"
		s.is_defense = true
		s.stats.defense = mini(99, s.stats.defense + 8)
		s.stats.checking = mini(99, s.stats.checking + 6)
		s.stats.strength = mini(99, s.stats.strength + 6)
		lu.defense.append(s)
	var g: Goalie = GOALIE_SCENE.instantiate()
	_setup_player(g, t, G_NUMBERS[t], true)
	lu.goalie = g


## The team's real roster (Rosters): forwards in lines, defense in pairs, best first;
## the higher-rated goalie starts.
func _roster_players(lu: Lineup, t: int, roster: Array) -> void:
	for p: Dictionary in Rosters.forward_lines(roster):
		var s: Skater = SKATER_SCENE.instantiate()
		_setup_player(s, t, int(p.number), p.hand == "L", p)
		lu.forwards.append(s)
	for p: Dictionary in Rosters.defense_pairs(roster):
		var s: Skater = SKATER_SCENE.instantiate()
		_setup_player(s, t, int(p.number), p.hand == "L", p)
		s.is_defense = true
		lu.defense.append(s)
	var gs := Rosters.goalies(roster)
	var g: Goalie = GOALIE_SCENE.instantiate()
	if gs.is_empty():
		_setup_player(g, t, G_NUMBERS[t], true)
	else:
		_setup_player(g, t, int(gs[0].number), gs[0].hand == "L", gs[0])
	lu.goalie = g


func _setup_player(s: Skater, t: int, number: int, left: bool, p := {}) -> void:
	s.team = t
	s.number = number
	var info := Teams.team(team_ids[t])
	var tc: Dictionary = Teams.uniform_vs(team_ids[t], team_ids[1 - t], t == 1)
	s.uniform = tc
	if ResourceLoader.exists(info.get("logo", "")):
		s.crest = load(info.logo)
	s.team_color = tc.jersey
	s.shoots_left = left
	if p.is_empty():
		s.stats = PlayerStats.random_around(_rng, 55, 10)
		# Generated rosters are mixed; body has no effect on stats.
		s.body_type = "female" if _rng.randf() < FEMALE_SHARE[t] else "male"
		s.skin_tone = SkaterVisual.SKIN_TONES[_rng.randi() % SkaterVisual.SKIN_TONES.size()]
		s.gear_style = _rng.randi() % 2
	else:
		s.stats = Rosters.stats(p)
		s.body_type = "female" if p.gender == "Female" else "male"
		s.first_name = p.first
		s.last_name = p.last
		s.nickname = p.nickname
		s.playstyle = p.playstyle
		s.position_name = p.position
		# Looks the sheet doesn't give: the same every game for the same player.
		var look := RandomNumberGenerator.new()
		look.seed = hash("%s %s %s" % [p.abbr, p.first, p.last])
		s.skin_tone = SkaterVisual.SKIN_TONES[look.randi() % SkaterVisual.SKIN_TONES.size()]
		s.gear_style = look.randi() % 2
	s.puck = puck
	s.rink = rink
	add_child(s)


func lineup(t: int) -> Lineup:
	return teams[t].lineup


func control(t: int) -> TeamControl:
	return teams[t].control


func on_ice_all() -> Array[Skater]:
	var out: Array[Skater] = []
	for t in teams:
		out.append_array(t.lineup.on_ice)
	return out


## Short team name for the HUD and banners (e.g. "WHALERS").
func team_name(t: int) -> String:
	return str(Teams.team(team_ids[t]).name).to_upper()


## Skaters a team can dress right now (3..5), after penalties.
func strength(t: int) -> int:
	var mine: int = teams[t].lineup.box_count()
	var theirs: int = teams[1 - t].lineup.box_count()
	if format == 5:
		return clampi(5 - mine, 3, 5)
	return clampi(3 + theirs, 3, 5) if mine == 0 else 3


# --- Phases --------------------------------------------------------------------

func _set_phase(p: Phase) -> void:
	phase = p
	_phase_time = 0.0
	phase_changed.emit(p)


func _physics_process(delta: float) -> void:
	_phase_time += delta
	for t in teams:
		t.ai.update()
		t.lineup.recover(delta)
	if puck.in_play and RinkSpec.sdf(puck.global_position.x, puck.global_position.z) < 0.0:
		_last_in_play = puck.global_position
	match phase:
		Phase.FIGHT:
			pass   # the Fight node runs itself
		Phase.INTRO:
			# The intro line ends the matchup screen (a silent booth gets INTRO_MIN).
			if _phase_time > INTRO_MAX or (_phase_time > INTRO_MIN and not Sfx.announcing()):
				_end_intro()
		Phase.PREGAME:
			if _phase_time > 1.2:
				_start_faceoff(Vector2.ZERO)
		Phase.FACEOFF:
			_update_faceoff()
		Phase.LIVE:
			clock = maxf(0.0, clock - delta)
			_tick_fight_state(delta)
			rules.tick()
			if phase == Phase.LIVE:
				_tick_box(delta)
				_tick_line_changes()
			if phase == Phase.LIVE and clock <= 0.0:
				_end_period()
		Phase.STOPPAGE:
			if _phase_time > _stoppage_len:
				_start_faceoff(_next_dot)
		Phase.PERIOD_END:
			# The stats screen opens once the horn and banner have had their moment;
			# the next period starts when it's clicked through (Intermission).
			if _phase_time > INTERMISSION_AFTER and _intermission == null:
				_open_intermission(false)
		Phase.SHOOTOUT:
			_tick_shootout(delta)
		Phase.FINAL:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if phase == Phase.INTRO and _phase_time > 0.6:
		var skip: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]) \
				or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START])
		if skip:
			get_viewport().set_input_as_handled()
			Sfx.stop_voice()
			_end_intro()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				get_tree().reload_current_scene()
			KEY_ESCAPE:
				_open_pause()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_open_pause()
	if Input.is_action_just_pressed("debug_camera"):
		cam.cycle_mode()


## Called by the rules (and events) to stop play.
func whistle(reason: StringName, dot: Vector2, text: String) -> void:
	if phase != Phase.LIVE:
		return
	match reason:
		&"offside":
			stats.offsides += 1
		&"icing":
			stats.icings += 1
	whistle_blown.emit(reason)
	_stoppage(1.6, dot, text)


func _stoppage(seconds: float, dot: Vector2, text := "") -> void:
	puck.dead = true
	rink.disarm_nets()
	_stoppage_len = seconds
	_next_dot = dot
	# Any called penalty is served now, and the faceoff moves to the penalized team's end.
	for t in 2:
		var pen = rules.pending[t]
		if pen == null:
			continue
		rules.pending[t] = null
		var offender: Skater = pen.offender
		lineup(t).send_to_box(offender)
		stats.penalties[t] += 1
		penalty_called.emit(offender, pen.kind)
		_next_dot = rules.end_dot(t, puck.global_position.x)
		_stoppage_len = maxf(_stoppage_len, 2.4)
		text = "PENALTY  #%d %s — %s  2:00" % [offender.number, team_name(t), FOUL_NAMES.get(pen.kind, str(pen.kind))]
	_set_phase(Phase.STOPPAGE)
	if text != "" and _hud:
		_hud.banner(text, minf(_stoppage_len, 2.4))


func _end_period() -> void:
	puck.dead = true
	rink.disarm_nets()
	var tied: bool = score[0] == score[1]
	var in_ot := period > periods
	if period >= periods and not tied:
		_finish()
		return
	if in_ot:
		if overtime_mode == "sd_so":
			_start_shootout()
		else:
			_finish()
		return
	if period >= periods:
		match overtime_mode:
			"off":
				_finish()
				return
			"shootout":
				_start_shootout()
				return
	_set_phase(Phase.PERIOD_END)
	if _hud:
		_hud.banner("END OF %s" % period_name(period), 3.0)


func _next_period() -> void:
	period += 1
	clock = ot_length if period > periods else period_length
	rink.ends_swapped = not rink.ends_swapped
	for t in teams.size():
		teams[t].goalie.net = rink.defended_net(t)
	_start_faceoff(Vector2.ZERO)
	if _hud:
		_hud.banner("OVERTIME" if period > periods else "%s PERIOD" % period_name(period), 2.0)


func _finish(text := "") -> void:
	puck.dead = true
	rink.disarm_nets()
	_set_phase(Phase.FINAL)
	if _hud:
		_hud.banner(text if text != "" else "FINAL   %s %d – %d %s" % [team_name(0), score[0], score[1], team_name(1)], 9999.0)
	match_finished.emit(score)
	if show_hud and not humans.is_empty():
		_open_final.call_deferred()


## Esc / Start: the pause menu (not over the matchup intro or a stats screen, which use
## those buttons to continue).
func _open_pause() -> void:
	if _pause != null or phase == Phase.INTRO or _intermission != null:
		return
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.closed.connect(func() -> void: _pause = null)


func _open_pause_for_shot(controls: bool) -> void:
	if phase == Phase.INTRO:
		_end_intro()
	_open_pause()
	if controls and _pause:
		_pause._show_controls()


# --- Fights ----------------------------------------------------------------------------

func _tick_fight_state(delta: float) -> void:
	_since_fight += delta
	for t in 2:
		tension[t] = maxf(0.0, tension[t] - 0.0015 * delta)
		momentum[t] = maxf(0.0, momentum[t] - delta)
		for s in lineup(t).on_ice:
			s.momentum = momentum[t] > 0.0
	if _debug_fight != "" and _fight == null:
		var ta := _toughest(0, null)
		var tb := _toughest(1, null)
		if ta and tb:
			var c := control(0)
			_start_fight(ta, tb, c.primary() if c and _debug_fight == "prompt" else null)
			_debug_fight = ""
			return
	if not fighting or _fight != null or _since_fight < FIGHT_GAP:
		return
	for t in 2:
		if tension[t] >= FIGHT_TENSION:
			_try_fight(t)
			return


## Team `t` took the hits. Its toughest skater on the ice squares off with the hitter
## (or the hitter's toughest teammate, if the hitter won't).
func _try_fight(t: int) -> void:
	var mine := _toughest(t, _last_victim[t])
	var hitter: Skater = _last_hitter[t]
	var theirs: Skater = hitter if _fightable(hitter) and hitter.stats.fighting >= 40 else _toughest(1 - t, null)
	if mine == null or theirs == null:
		tension[t] = FIGHT_TENSION * 0.6
		return
	var forced: bool = theirs.stats.aggression >= 70 and tension[t] >= FORCED_TENSION
	var c := control(t)
	var human: HumanBrain = c.primary() if c and not forced else null
	if human == null and not forced:
		# The computer decides for its team: tough, angry players say yes.
		var p := 0.35 + (mine.stats.fighting - 50) / 100.0 + (mine.stats.aggression - 50) / 150.0
		if _rng.randf() > p:
			tension[t] = FIGHT_TENSION * 0.5
			return
	_start_fight(mine, theirs, human)


func _fightable(s: Skater) -> bool:
	return s != null and is_instance_valid(s) and not (s is Goalie) and not s.benched and not s.changing


func _toughest(t: int, prefer: Skater) -> Skater:
	var best: Skater = null
	var best_v := -INF
	for s in lineup(t).on_ice:
		if not _fightable(s):
			continue
		var v := s.stats.fighting + s.stats.aggression * 0.5 + (10.0 if s == prefer else 0.0)
		if v > best_v:
			best_v = v
			best = s
	return best


func _start_fight(a: Skater, b: Skater, prompt: HumanBrain) -> void:
	_set_phase(Phase.FIGHT)
	puck.dead = true
	if puck.carrier:
		puck.strip(puck.carrier, Vector3.ZERO)
	rink.disarm_nets()
	for t in 2:
		for s in lineup(t).on_ice:
			s.frozen = true
	_fight_spot = (a.global_position + b.global_position) * 0.5
	_fight = Fight.new()
	add_child(_fight)
	_fight.finished.connect(_on_fight_over)
	_fight.declined.connect(_on_fight_declined)
	_fight.setup(self, a, b, prompt)
	if _hud:
		_hud.visible = false   # the fight has its own overlay


func _on_fight_declined() -> void:
	_fight = null
	if _hud:
		_hud.visible = true
	tension = [0.0, 0.0]
	_since_fight = FIGHT_GAP * 0.5
	_stoppage(0.8, nearest_dot(_fight_spot))


func _on_fight_over(winner: Skater, loser: Skater) -> void:
	var fighters: Array[Skater] = [_fight.a.s, _fight.b.s]
	_fight = null
	if _hud:
		_hud.visible = true
	tension = [0.0, 0.0]
	_since_fight = 0.0
	stats.fights += 1
	if winner:
		momentum[winner.team] = MOMENTUM_TIME
	for s in fighters:
		if not is_instance_valid(s):
			continue
		lineup(s.team).send_to_box(s, FIGHT_MAJOR if penalties else FIGHT_COOLDOWN, false)
		_reassign_control(s.team, s)
	var text := "FIGHTING — 5:00 MAJORS" if penalties else "BOTH FIGHTERS SIT"
	_stoppage(2.0, nearest_dot(_fight_spot), text)
	if loser and _hud:
		_hud.flash("%s WINS THE FIGHT" % team_name(winner.team))


# --- Matchup intro ---------------------------------------------------------------

## The matchup screen: at center ice, each team's logo on a board with one of its
## players standing in front of it in uniform, while the announcer reads the intro.
## Everyone else is hidden. Enter / A skips it.
func _start_intro() -> void:
	_set_phase(Phase.INTRO)
	_intro_stage = Node3D.new()
	_intro_stage.name = "IntroStage"
	add_child(_intro_stage)
	_showcase.clear()
	for t in 2:
		var lu := lineup(t)
		for s in lu.all_skaters():
			s.frozen = true
			s.visual.visible = false
		if lu.goalie:
			lu.goalie.frozen = true
			lu.goalie.visual.visible = false
		# Home on the left of the screen (camera looks down -Z, so left is -X).
		var side := -1.0 if t == 0 else 1.0
		var star: Skater = lu.forwards[0] if not lu.forwards.is_empty() else lu.all_skaters()[0]
		star.place(Vector3(side * 1.55, 0, 0.6), Vector3.BACK)
		star.visual.visible = true
		star.visual.snap()
		star.visual.play_clip("idle", Vector3.ONE, -1.0, 1.0, 0.05)
		_showcase.append(star)
		var info := Teams.team(team_ids[t])
		if ResourceLoader.exists(info.get("logo", "")):
			var logo := Sprite3D.new()
			logo.texture = load(info.logo)
			logo.pixel_size = 3.0 / float(logo.texture.get_width())   # 3 m wide
			logo.shaded = false
			logo.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			logo.position = Vector3(side * 1.9, 2.35, -1.6)
			_intro_stage.add_child(logo)
	var vs := Label3D.new()
	vs.text = "VS"
	vs.font_size = 160
	vs.pixel_size = 0.006
	vs.outline_size = 36
	vs.modulate = Color(1.0, 0.85, 0.2)
	vs.outline_modulate = Color(0.05, 0.05, 0.08)
	vs.position = Vector3(0, 2.35, -1.4)
	_intro_stage.add_child(vs)
	var c := Camera3D.new()
	c.fov = 52.0
	_intro_stage.add_child(c)
	c.look_at_from_position(Vector3(0, 1.75, 6.4), Vector3(0, 1.55, -0.6))
	c.make_current()
	if _hud:
		_hud.visible = false


func _end_intro() -> void:
	if phase != Phase.INTRO:
		return
	for s in _showcase:
		s.visual.stop_clip(0.2)
	_showcase.clear()
	for t in 2:
		var lu := lineup(t)
		for s in lu.all_skaters():
			s.frozen = false
			s.visual.visible = true
		if lu.goalie:
			lu.goalie.frozen = false
			lu.goalie.visual.visible = true
	if _intro_stage:
		_intro_stage.queue_free()
		_intro_stage = null
	cam.make_current()
	if _hud:
		_hud.visible = true
	_set_phase(Phase.PREGAME)
	_place_for_faceoff(Vector2.ZERO)
	for t in teams:
		for s in (t.lineup as Lineup).all_skaters():
			s.visual.snap()


func _open_intermission(final: bool) -> void:
	_intermission = Intermission.new()
	add_child(_intermission)
	_intermission.open(self, final)
	if final:
		_intermission.continued.connect(func() -> void:
			if ResourceLoader.exists("res://scenes/ui/MatchSetup.tscn"):
				get_tree().change_scene_to_file("res://scenes/ui/MatchSetup.tscn"))
	else:
		_intermission.continued.connect(func() -> void:
			_intermission = null
			_next_period())


## Final stats, after the final banner has shown for a few seconds.
func _open_final() -> void:
	await get_tree().create_timer(4.0).timeout
	if is_inside_tree() and phase == Phase.FINAL and _intermission == null:
		_open_intermission(true)


func period_name(p: int) -> String:
	if phase == Phase.SHOOTOUT or (phase == Phase.FINAL and not shootout.is_empty()):
		return "SO"
	if p > periods:
		return "OT"
	return ["1ST", "2ND", "3RD"][p - 1] if p <= 3 else "%dTH" % p


# --- Penalties, box, line changes -------------------------------------------------

func _on_foul(offender: Skater, _victim: Skater, kind: StringName) -> void:
	if not penalties or phase != Phase.LIVE:
		return
	if _rng.randf() >= FOUL_CHANCE.get(kind, 0.5):
		return
	var delayed := rules.call_penalty(offender, kind)
	if delayed and _hud:
		_hud.flash("DELAYED PENALTY — %s" % team_name(offender.team))


func _tick_box(delta: float) -> void:
	for t in 2:
		for s in lineup(t).tick_box(delta):
			_return_from_box(t, s)


func _return_from_box(t: int, s: Skater) -> void:
	var lu := lineup(t)
	if format == 5 and lu.on_ice.size() < strength(t):
		s.set_benched(false)
		s.place(BOX_GATE + Vector3(0, 0, 1.5 * (lu.on_ice.size() % 2)), Vector3.LEFT)
		lu.on_ice.append(s)
	elif format == 3:
		# 3-on-3: the other team loses its power-play skater.
		var other := lineup(1 - t)
		while other.on_ice.size() > strength(1 - t):
			var drop := _least_needed(other)
			if drop == null:
				break
			other.on_ice.erase(drop)
			drop.set_benched(true)
			_reassign_control(1 - t, drop)


func _least_needed(lu: Lineup) -> Skater:
	var best: Skater = null
	var best_d := -1.0
	for s in lu.on_ice:
		if s.is_human or s.has_puck():
			continue
		var d := s.global_position.distance_to(puck.global_position)
		if d > best_d:
			best_d = d
			best = s
	return best


func _tick_line_changes() -> void:
	if not line_changes:
		return
	for t in 2:
		var lu := lineup(t)
		if not _puck_in_defensive_zone(t):
			if lu.avg_energy(lu.forwards_on_ice()) < 0.5:
				lu.plan_change(false)
			if lu.avg_energy(lu.defense_on_ice()) < 0.45:
				lu.plan_change(true)
		var gate: Vector3 = BENCH_GATES[t]
		for s in lu.on_ice.duplicate():
			if s.changing and not s.has_puck() and s.global_position.distance_to(gate) < 2.5:
				var inn := lu.swap_at_gate(s)
				if inn:
					inn.place(gate + Vector3(0.8, 0, 0), Vector3.RIGHT)
					stats.changes[t] += 1


func _puck_in_defensive_zone(t: int) -> bool:
	var z := MatchRules.zone_of(puck.global_position.z)
	return z == rink.defended_net(t).index


func _reassign_control(t: int, removed: Skater) -> void:
	var c := control(t)
	if c:
		c.on_skater_removed(removed)


# --- Faceoffs ------------------------------------------------------------------

## The nine faceoff dots as (x, z).
static func faceoff_dots() -> Array[Vector2]:
	var dots: Array[Vector2] = [Vector2.ZERO]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			dots.append(Vector2(sx * RinkSpec.END_DOT_X, sz * RinkSpec.NEUTRAL_DOT_Z))
			dots.append(Vector2(sx * RinkSpec.END_DOT_X, sz * RinkSpec.END_DOT_Z))
	return dots


static func nearest_dot(p: Vector3, end_zone_only := false) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for d in faceoff_dots():
		if end_zone_only and absf(d.y) < RinkSpec.END_DOT_Z - 0.1:
			continue
		var dist := d.distance_squared_to(Vector2(p.x, p.z))
		if dist < best_d:
			best_d = dist
			best = d
	return best


## Unit Z direction toward this team's own net.
func own_goal_dir(t: int) -> Vector3:
	return Vector3(0, 0, signf(rink.defended_net(t).global_position.z))


func _faceoff_spots(t: int, dot: Vector2) -> Dictionary:
	var og := own_goal_dir(t)
	var d := Vector3(dot.x, 0, dot.y)
	var wx := -signf(dot.x) if absf(dot.x) > 0.5 else 1.0
	var f := [d + og * 0.9, d + og * 2.4 + Vector3(wx * 3.6, 0, 0), d + og * 2.4 - Vector3(wx * 3.6, 0, 0)]
	var dd := [d + og * 8.0 + Vector3(wx * 3.0 - dot.x * 0.5, 0, 0), d + og * 8.0 + Vector3(-wx * 3.0 - dot.x * 0.5, 0, 0)]
	return {"f": f.map(_clamp_spot), "d": dd.map(_clamp_spot)}


func _clamp_spot(p: Vector3) -> Vector3:
	var c := RinkSpec.clamp_inside(p.x, p.z, 1.0)
	return Vector3(c.x, 0, c.y)


func _place_for_faceoff(dot: Vector2) -> void:
	puck.place(Vector3(dot.x, 0, dot.y))
	puck.dead = true
	rules.reset()
	for t in teams.size():
		var lu := lineup(t)
		lu.choose_fresh()
		lu.fill(strength(t))
		var spots := _faceoff_spots(t, dot)
		var face := -own_goal_dir(t)
		var fi := 0
		var di := 0
		var taker := faceoff_taker(t)
		for s in lu.on_ice:
			var p: Vector3
			if s.is_defense and di < 2:
				p = spots.d[di]
				di += 1
			elif not s.is_defense and fi < 3:
				p = spots.f[fi]
				fi += 1
			else:
				p = spots.d[di % 2] + Vector3(1.5, 0, 0)
				di += 1
			var f := face
			if s == taker:
				f = (Vector3(dot.x, 0, dot.y) - p).normalized()
			s.place(p, f)
			s.frozen = true
		var g: Goalie = teams[t].goalie
		g.set_benched(false)
		g.net = rink.defended_net(t)
		g.reset_in_net()
		if control(t):
			control(t).reset_to(lu.on_ice)


func faceoff_taker(t: int) -> Skater:
	var lu := lineup(t)
	for s in lu.on_ice:
		if not s.is_defense:
			return s
	return lu.on_ice[0] if not lu.on_ice.is_empty() else null


func _start_faceoff(dot: Vector2) -> void:
	_place_for_faceoff(dot)
	rink.rearm_nets()
	_set_phase(Phase.FACEOFF)
	var drop_at := 0.9 + _rng.randf_range(0.0, 0.4)
	var ai_press := [INF, INF]
	for t in 2:
		ai_press[t] = drop_at + lerpf(0.45, 0.12, difficulty) * _rng.randf_range(0.75, 1.3)
	_fo = {"dot": dot, "drop_at": drop_at, "dropped": false, "press": [INF, INF], "early": [false, false], "ai_press": ai_press}


func _update_faceoff() -> void:
	var dropped: bool = _phase_time >= _fo.drop_at
	if dropped and not _fo.dropped:
		_fo.dropped = true
		if _hud:
			_hud.flash("DROP!")
	for t in 2:
		var c := faceoff_taker(t)
		if c == null:
			continue
		if c.is_human:
			if (c.intent.pass_down or c.intent.shoot_down) and _fo.press[t] == INF:
				if not dropped:
					_fo.early[t] = true  # jumped the drop: your next press is penalized
				else:
					_fo.press[t] = _phase_time + (0.25 if _fo.early[t] else 0.0)
		elif dropped and _phase_time >= _fo.ai_press[t] and _fo.press[t] == INF:
			_fo.press[t] = _fo.ai_press[t]
	if not dropped:
		return
	var both: bool = _fo.press[0] < INF and _fo.press[1] < INF
	if both or _phase_time > _fo.drop_at + 1.0:
		_resolve_faceoff()


func _resolve_faceoff() -> void:
	var p: Array = _fo.press
	var winner: int
	if absf(p[0] - p[1]) < 0.03 or (p[0] == INF and p[1] == INF):
		var a: int = faceoff_taker(0).stats.puck_handling
		var b: int = faceoff_taker(1).stats.puck_handling
		winner = 0 if _rng.randf() < float(a) / float(a + b) else 1
	else:
		winner = 0 if p[0] < p[1] else 1
	stats.faceoffs[winner] += 1
	for s in on_ice_all():
		s.frozen = false
	var dot: Vector2 = _fo.dot
	var spots := _faceoff_spots(winner, dot)
	var target: Vector3 = spots.d[0] if _rng.randf() < 0.5 else spots.f[1]
	var dir := target - Vector3(dot.x, 0, dot.y)
	dir.y = 0.0
	puck.dead = false
	puck.place(Vector3(dot.x, 0, dot.y))
	puck.launch(dir.normalized().rotated(Vector3.UP, _rng.randf_range(-0.25, 0.25)) * 7.0)
	rules.reset()
	_set_phase(Phase.LIVE)


# --- Shootout ---------------------------------------------------------------------

func _start_shootout() -> void:
	_set_phase(Phase.SHOOTOUT)
	puck.dead = true
	rink.disarm_nets()
	rules.pending = [null, null]
	for t in 2:
		var lu := lineup(t)
		lu.in_box.clear()
		lu.on_ice.clear()
		for s in lu.all_skaters():
			s.set_benched(true)
		teams[t].ai.shootout = true
		var order := lu.forwards.duplicate()
		order.sort_custom(func(a: Skater, b: Skater) -> bool:
			return a.stats.shot_accuracy + a.stats.puck_handling > b.stats.shot_accuracy + b.stats.puck_handling)
		shootout[t] = order
	shootout.results = [[], []]
	shootout.turn = 1          # the away team shoots first
	shootout.active = false
	shootout.wait = 2.0
	shootout.time = 0.0
	if _hud:
		_hud.banner("SHOOTOUT", 2.0)


func _tick_shootout(delta: float) -> void:
	if not shootout.active:
		shootout.wait -= delta
		if shootout.wait <= 0.0:
			if _shootout_decided():
				_end_shootout()
			else:
				_shootout_attempt()
		return
	shootout.time += delta
	var shooter: Skater = shootout.shooter
	var p := puck.global_position
	var behind := absf(p.z) > RinkSpec.GOAL_LINE_Z + 0.3
	var dead_puck: bool = puck.carrier == null and puck.speed() < 1.5 and shootout.time > 1.0
	if shootout.time > SHOOTOUT_TIME or behind or dead_puck or (puck.carrier != null and puck.carrier != shooter):
		_shootout_result(false)


func _shootout_attempt() -> void:
	var t: int = shootout.turn
	var results: Array = shootout.results[t]
	var order: Array = shootout[t]
	var shooter: Skater = order[results.size() % order.size()]
	for s in lineup(0).on_ice + lineup(1).on_ice:
		s.set_benched(true)
	lineup(0).on_ice.clear()
	lineup(1).on_ice.clear()
	# Shooters always attack the -Z net: pick the end orientation that makes that true.
	rink.ends_swapped = t == 1
	var g: Goalie = teams[1 - t].goalie
	teams[t].goalie.set_benched(true)
	g.set_benched(false)
	g.net = rink.get_net(SHOOTOUT_NET)
	g.reset_in_net()
	lineup(t).on_ice.append(shooter)
	shooter.set_benched(false)
	shooter.place(Vector3(0, 0, 1.5), Vector3.FORWARD)
	shooter.energy = 1.0
	puck.dead = false
	puck.place(shooter.puck_anchor())
	puck.attach(shooter)
	if control(t):
		control(t).reset_to(lineup(t).on_ice)
	rink.rearm_nets()
	shootout.shooter = shooter
	shootout.active = true
	shootout.time = 0.0
	if _hud:
		_hud.flash("%s  #%d" % [team_name(t), shooter.number])


func _shootout_result(scored: bool) -> void:
	if not shootout.get("active", false):
		return
	shootout.active = false
	var t: int = shootout.turn
	shootout.results[t].append(scored)
	puck.dead = true
	rink.disarm_nets()
	if _hud:
		_hud.banner("SCORES!" if scored else "NO GOAL", 1.4)
	shootout.turn = 1 - t
	shootout.wait = 1.8


func _shootout_decided() -> bool:
	var a: Array = shootout.results[0]
	var b: Array = shootout.results[1]
	var ga := a.count(true)
	var gb := b.count(true)
	var r := shootout_rounds
	if a.size() <= r and b.size() <= r:
		return ga + (r - a.size()) < gb or gb + (r - b.size()) < ga
	return a.size() == b.size() and ga != gb


func _end_shootout() -> void:
	var a: int = shootout.results[0].count(true)
	var b: int = shootout.results[1].count(true)
	var w := 0 if a > b else 1
	score[w] += 1
	_finish("%s WINS THE SHOOTOUT   %d – %d" % [team_name(w), score[0], score[1]])


## Debug / test hook.
func debug_start_shootout() -> void:
	_start_shootout()


# --- Events ----------------------------------------------------------------------

func _on_goal(net_index: int) -> void:
	if phase == Phase.SHOOTOUT:
		_shootout_result(true)
		return
	if phase != Phase.LIVE:
		return
	var scoring := 1 - rink.team_defending(net_index)
	var other := 1 - scoring
	score[scoring] += 1
	stats.period_goals[scoring][mini(period, 4) - 1] += 1
	var scorer := puck.last_touch
	goal.emit(scoring, scorer)
	cam.shake(0.6)
	# Horn and crowd: MatchAudio (on the goal signal).
	for s in lineup(scoring).on_ice:
		s.visual.celebrate()
	var beaten := lineup(other).goalie
	if beaten and randf() < 0.6:
		beaten.visual.play_clip("angry_gesture", Vector3(0.0, 0.7, 1.0), 2.0, 1.1, 0.25)
	# A delayed penalty against the team scored on is wiped out by the goal.
	rules.pending[other] = null
	var pp := strength(scoring) > strength(other) and lineup(other).box_count() > 0
	if pp:
		stats.pp_goals[scoring] += 1
		lineup(other).release_earliest()
	var who := "  #%d" % scorer.number if scorer and scorer.team == scoring else ""
	if period > periods:
		_finish("%s WINS IN OT!%s" % [team_name(scoring), who])
		return
	_stoppage(3.0, Vector2.ZERO, "%s %sGOAL!%s" % [team_name(scoring), "POWER-PLAY " if pp else "", who])


func _on_puck_touched(s: Skater) -> void:
	rules.on_touched(s)


func _on_shot(s: Skater, _kind: StringName, _spd: float) -> void:
	if phase == Phase.LIVE and not (s is Goalie):
		stats.shots[s.team] += 1


## Shots on goal = the other goalie's saves + goals.
func shots_on_goal(t: int) -> int:
	return stats.saves[1 - t] + score[t]


func _on_save(g: Goalie, _kind: StringName) -> void:
	if phase == Phase.LIVE:
		stats.saves[g.team] += 1
	elif phase == Phase.SHOOTOUT:
		_shootout_result(false)


func _on_freeze(g: Goalie) -> void:
	if phase == Phase.SHOOTOUT:
		_shootout_result(false)
		return
	if phase != Phase.LIVE:
		return
	_stoppage(1.3, nearest_dot(g.global_position, true), "WHISTLE")


func _on_left_play() -> void:
	if phase == Phase.SHOOTOUT:
		_shootout_result(false)
		return
	if phase != Phase.LIVE:
		return
	_stoppage(1.3, nearest_dot(_last_in_play), "OUT OF PLAY")


func _on_hit(attacker: Skater, victim: Skater, _power: float, kind: StringName, boards: bool) -> void:
	if victim and attacker:
		var t := victim.team
		tension[t] += {&"big_hit": 0.7, &"check": 0.22}.get(kind, 0.06) + (0.2 if boards and kind == &"big_hit" else 0.0)
		_last_hitter[t] = attacker
		_last_victim[t] = victim
	stats.hits[attacker.team] += 1
	if kind == &"big_hit":
		stats.big_hits[attacker.team] += 1
		cam.shake(0.9)
		_slowmo(0.45)
		if _hud:
			_hud.banner("BIG HIT!" if not boards else "CRUSHED INTO THE BOARDS!", 1.4)
	elif kind == &"check":
		cam.shake(0.35)


func _slowmo(real_seconds: float) -> void:
	Engine.time_scale = 0.35
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0
