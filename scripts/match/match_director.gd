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
## shootout|sd_so, norules, cam=…, shot=<png>, wait=<s>, shots=<n>, every=<s>

signal phase_changed(phase: Phase)
signal goal(team: int, scorer: Skater)
signal whistle_blown(reason: StringName)
signal penalty_called(offender: Skater, kind: StringName)
signal match_finished(score: Array)
signal faceoff_won(team: int)
signal penalty_expired(team: int)   ## a minor ran out (not a goal against, not offsetting)

enum Phase { PREGAME, FACEOFF, LIVE, STOPPAGE, PERIOD_END, SHOOTOUT, FINAL, INTRO, FIGHT }

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

const F_NUMBERS := [[19, 11, 27, 9, 17, 22, 13, 8, 26, 14, 10, 16], [91, 88, 12, 15, 21, 24, 18, 23, 28, 29, 20, 63]]
const D_NUMBERS := [[4, 44, 2, 5, 7, 3], [55, 77, 33, 47, 6, 2]]
const G_NUMBERS := [1, 30]
const F_POS := ["C", "LW", "RW"]
const WALK_SPEED := 5.0      ## m/s for scripted walks through the bench and box doors
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
const INTRO_MAX := 20.0           ## ...and at most this long (the intro line normally ends it)

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
## Play angle (BroadcastCamera: "broadcast", "close", "side", "high") and whether it turns
## with the ends so the human team always attacks up the screen.
@export var camera := "broadcast"
@export var camera_follow := false
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
var box := BoxScore.new()     ## per-player stats (hot / cold players, three stars)
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
var _cmd_cam := false         ## `-- cam=…` picked the angle (it wins over the settings)
var _debug_fight := ""        ## `-- fight` / `fight=prompt`: start a fight at the first chance (testing)
var _showcase: Array[Skater] = []
var _no_intro := false
var knockout := false        ## Knockout Mode: a card of fights instead of a game (KnockoutMode)
var knockout_mode: KnockoutMode

var _phase_time := 0.0
var _stoppage_len := 0.0
var _next_dot := Vector2.ZERO
var _fo := {}
var _last_in_play := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _hud: MatchHud
var replay: Replay
var referee: Referee
var _ref_brain: RefBrain
var _pen_cut: Cutscene        ## the penalty call playing (null = none)
var _opener: Cutscene         ## the period opener playing (null = none)
const PENALTY_CALL := 1.5     ## s on the referee's call before the offender heads off


func _ready() -> void:
	process_physics_priority = -10 # roles and phases update before skaters move
	if use_game_settings:
		_apply_settings(GameSettings.config, GameSettings.humans)
		knockout = GameSettings.mode == "knockout"
	_parse_cmdline()
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	GameSettings.sun_shadow_mode(sun)
	rules = MatchRules.new(self)
	rules.offsides = offsides
	rules.icing = icing
	rules.penalties = penalties
	_build_teams()
	apply_camera(camera if not _cmd_cam else cam.mode_name(), camera_follow)
	var home_logo: String = Teams.team(team_ids[0]).get("logo", "")
	if ResourceLoader.exists(home_logo):
		rink.set_center_logo(load(home_logo))
	rink.set_bench_colors([MenuStyle.team_color(team_ids[0]), MenuStyle.team_color(team_ids[1])])
	if rink.arena:
		rink.arena.set_teams(team_ids[0], team_ids[1])
		rink.arena.bind_match(self)
	replay = Replay.new()
	replay.name = "Replay"
	add_child(replay)
	replay.setup(self)
	for t in 2:
		for s in lineup(t).all_skaters():
			replay.register(s)
		replay.register(lineup(t).goalie)
	_make_referee()
	replay.register(referee)
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
	if knockout:
		knockout_mode = KnockoutMode.new()
		add_child(knockout_mode)
		knockout_mode.setup(self)
	elif show_hud and not _no_intro:
		_start_intro()
	else:
		_set_phase(Phase.PREGAME)
		_place_for_faceoff(Vector2.ZERO)
		_period_opener.call_deferred()


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
	camera = str(c.get("camera", camera))
	camera_follow = bool(c.get("camera_follow", camera_follow))
	team_ids = [int(c.get("home_team", team_ids[0])), int(c.get("away_team", team_ids[1]))]
	humans = h.duplicate(true)


func _parse_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("ai"):
		humans = []
	if args.has("camfollow"):
		camera_follow = args["camfollow"] != "0"
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
			cam.set_mode(idx as BroadcastCamera.Mode)
			_cmd_cam = true
	if args.has("nointro"):
		_no_intro = true
	if args.has("knockout"):   # Knockout Mode straight away (testing)
		knockout = true
	if args.has("fight"):
		_debug_fight = str(args["fight"]) if args["fight"] in ["prompt", "ko"] else "on"
	if args.has("pausemenu"):   # open the pause menu at once (screenshots); pausemenu=controls for that page
		_open_pause_for_shot.call_deferred(args["pausemenu"] == "controls")
	if args.has("statscreen"):   # open the stats screen (screenshots / layout checks); statwait=<s> plays a while first
		_open_stats_for_shot.call_deferred(args["statscreen"] == "final", float(args.get("statwait", "0")))
	if args.has("look"):   # a fixed camera for layout checks: look=x,y,z,tx,ty,tz
		var v := str(args["look"]).split_floats(",")
		if v.size() == 6:
			_debug_look.call_deferred(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
	if args.has("goaltest"):   # a few seconds into live play: a home goal (celebration, replay)
		_goal_demo.call_deferred()
	if args.has("penaltytest"):   # a few seconds in: a delayed penalty, then the whistle and the call
		_penalty_demo.call_deferred()
	if args.has("replaytest"):   # after a few seconds of AI play: a goal-cam replay, then an orbit replay
		_replay_demo.call_deferred()
	if args.has("benchtest"):   # sends two to each box and cycles bench reactions (layout checks)
		_bench_demo.call_deferred()
	if args.has("doors"):   # swing every door open and shut in a loop (layout checks)
		_debug_doors.call_deferred()
	if args.has("hudtest"):   # fire the TV graphics on a timer (layout checks): banner + goal card, flash, penalty card
		_hud_demo.call_deferred()
	if args.has("shot"):
		_screenshot.call_deferred(str(args["shot"]), float(args.get("wait", "3.0")), int(args.get("shots", "1")), float(args.get("every", "0.5")))


## `shots` > 1: a burst, `every` seconds apart, saved as <path>_<n>.png.
func _screenshot(path: String, wait: float, shots := 1, every := 0.5) -> void:
	await get_tree().process_frame   # the first frame's delta is the whole load time
	await get_tree().create_timer(wait, true, false, true).timeout
	for n in shots:
		await RenderingServer.frame_post_draw
		var out := path if shots == 1 else path.get_basename() + "_%d.png" % n
		get_viewport().get_texture().get_image().save_png(out)
		if n < shots - 1:
			await get_tree().create_timer(every, true, false, true).timeout
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
		ai.bench_gate = rink.bench_gate(t)
		teams[t]["ai"] = ai
		# Everyone's spot on the bench (the backup... and the starter in a shootout, too).
		for s in lu.all_skaters():
			s.bench_claim = _claim_bench.bind(t)
		lu.goalie.bench_claim = _claim_bench.bind(t)
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
		_set_look(s, SkaterVisual.random_look(_rng, s.body_type, s.skin_tone))
		s.visor = Skater.visor_for("%s %d" % [info.get("abbr", ""), number])
	else:
		s.stats = Rosters.stats(p)
		s.body_type = "female" if p.gender == "Female" else "male"
		# Ring names (Luchadores) have no last name: the whole display name goes where a
		# last name would (jersey back, name tags, fight cards).
		s.first_name = p.first if str(p.last) != "" else ""
		s.last_name = p.last if str(p.last) != "" else Rosters.display_name(p)
		s.nickname = p.nickname
		s.playstyle = p.playstyle
		s.position_name = p.position
		Rosters.apply_size(s, p)
		# Looks the sheet doesn't give: the same every game for the same player.
		var look := RandomNumberGenerator.new()
		look.seed = hash("%s %s %s" % [p.abbr, p.first, p.last])
		s.skin_tone = SkaterVisual.SKIN_TONES[look.randi() % SkaterVisual.SKIN_TONES.size()]
		s.gear_style = look.randi() % 2
		_set_look(s, SkaterVisual.random_look(look, s.body_type, s.skin_tone))
		s.visor = Skater.visor_for("%s %s %s" % [p.abbr, p.first, p.last])
	s.puck = puck
	s.rink = rink
	add_child(s)



func _set_look(s: Skater, look: Dictionary) -> void:
	s.hair_style = look.hair_style
	s.facial_hair = look.facial_hair
	s.hair_color = look.hair_color
	s.eye_color = look.eye_color


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


## The play angle: `follow` turns it with the ends for the team the humans play
## (only when they're all on one team).
func apply_camera(angle: String, follow: bool) -> void:
	camera = angle
	camera_follow = follow
	cam.set_mode_name(angle)
	cam.follow_team = human_team() if follow else -1
	cam.set_mode(cam.mode)


## The team every human plays for, or -1 (nobody, or both teams).
func human_team() -> int:
	var t := -1
	for h: Dictionary in humans:
		var ht := int(h.get("team", 0))
		if t >= 0 and ht != t:
			return -1
		t = ht
	return t


func _process(_delta: float) -> void:
	# The close camera keeps the player you control in frame too.
	var t := human_team()
	var tc: TeamControl = teams[t].get("control") if t >= 0 and t < teams.size() else null
	cam.player = tc.controlled_skater() if tc else null


func _physics_process(delta: float) -> void:
	_phase_time += delta
	for t in teams:
		t.ai.update()
		t.lineup.recover(delta)
	if referee and _pen_cut == null:
		referee.signal_arm = "up" if rules.has_delayed_penalty() else ""
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
			if _phase_time > 1.2 and _opener == null:
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


## `team`: whose moment it is (the banner wears their colors), -1 for neither.
func _stoppage(seconds: float, dot: Vector2, text := "", team := -1) -> void:
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
		if _hud and referee and _pen_cut == null and not offender.benched:
			_penalty_cutscene(t, offender)
		else:
			_send_to_box(t, offender, Lineup.MINOR)
		stats.penalties[t] += 1
		box.add(offender, "pim", 2)
		_bench_react(1 - t, "laugh", 0.35)
		_bench_react(t, "groan", 0.4)
		penalty_called.emit(offender, pen.kind)
		_next_dot = rules.end_dot(t, puck.global_position.x)
		_stoppage_len = maxf(_stoppage_len, 2.4)
		text = ""
		if _hud:
			_hud.penalty_card(t, offender, FOUL_NAMES.get(pen.kind, str(pen.kind)), "2:00", 4.0)
	_set_phase(Phase.STOPPAGE)
	if replay and not replay.busy():
		replay.play_pending(1, ["hit", "ko"], Replay.STOPPAGE_MAX_AGE)
	if text != "" and _hud:
		_hud.banner(text, minf(_stoppage_len, 2.4), team)


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
	_period_highlights()


func _next_period() -> void:
	period += 1
	if replay:
		replay.forget()
	box.period_start()
	clock = ot_length if period > periods else period_length
	rink.ends_swapped = not rink.ends_swapped
	for t in teams.size():
		teams[t].goalie.net = rink.defended_net(t)
	_set_phase(Phase.PREGAME)
	_place_for_faceoff(Vector2.ZERO)
	_period_opener()
	if _hud:
		_hud.banner("OVERTIME" if period > periods else "%s PERIOD" % period_name(period), 2.0)


func _finish(text := "", team := -1) -> void:
	puck.dead = true
	rink.disarm_nets()
	_set_phase(Phase.FINAL)
	if _hud:
		if team < 0 and score[0] != score[1]:
			team = 0 if score[0] > score[1] else 1
		_hud.banner(text if text != "" else "FINAL", 9999.0, team)
	match_finished.emit(score)
	_period_highlights()
	if show_hud and not humans.is_empty():
		_open_final.call_deferred()


## Esc / Start: the pause menu (not over the matchup intro or a stats screen, which use
## those buttons to continue).
func _open_pause() -> void:
	if _pause != null or phase == Phase.INTRO or _intermission != null:
		return
	_pause = PauseMenu.new()
	_pause.camera_host = self
	if knockout:
		_pause.mode = "KNOCKOUT MODE"
		_pause.restart_text = "RESTART KNOCKOUT"
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
			if _debug_fight == "ko" and _fight:
				_fight.b.health = 4.0   # one good punch from going down (tests the knockout replay)
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
	_fight.knockout.connect(func(w: Skater, l: Skater) -> void:
		if replay and show_hud:
			replay.capture("ko", "KNOCKOUT  ·  %s" % MenuStyle.player_name(w), [w, l], 2.8, maxf(1.6, _fight.ko_fall + 0.8),
					{"play_now": true, "speed": 0.45, "cam": "orbit"}))
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
		_bench_react(winner.team, "cheer", 0.8)
		_bench_react(1 - winner.team, "groan", 0.5)
	for s in fighters:
		if not is_instance_valid(s):
			continue
		box.add(s, "fights")
		if penalties:
			box.add(s, "pim", 5)
		if s == winner:
			box.add(s, "fight_w")
		_send_to_box(s.team, s, FIGHT_MAJOR if penalties else FIGHT_COOLDOWN, false)
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
	if referee:
		referee.frozen = true
		referee.visual.visible = false
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
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	if referee:
		referee.frozen = false
		referee.visual.visible = true
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
	_period_opener()


func _open_intermission(final: bool) -> void:
	if _hud:
		_hud.visible = false
	_intermission = Intermission.new()
	add_child(_intermission)
	_intermission.open(self, final)
	if final:
		_intermission.continued.connect(func() -> void:
			if ResourceLoader.exists("res://scenes/ui/TeamSelect.tscn"):
				get_tree().change_scene_to_file("res://scenes/ui/TeamSelect.tscn"))
	else:
		_intermission.continued.connect(func() -> void:
			_intermission = null
			if _hud:
				_hud.visible = true
			_next_period())


func _debug_look(from: Vector3, at: Vector3) -> void:
	var c := Camera3D.new()
	c.fov = 50.0
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(c)
	c.look_at_from_position(from, at)
	c.current = true
	cam.set_process(false)


func _goal_demo() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(7.0, false).timeout
	while phase != Phase.LIVE:
		await get_tree().process_frame
	puck.last_touch = lineup(0).on_ice[0]
	_on_goal(rink.attacked_net(0).index)


func _penalty_demo() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(6.0, false).timeout
	var off: Skater = lineup(1).on_ice[0]
	rules.pending[1] = {"offender": off, "kind": &"tripping"}   # delayed: the arm goes up
	await get_tree().create_timer(0.8, false).timeout
	if rules.pending[1] == null:
		return   # (wiped out by a goal meanwhile)
	whistle(&"penalty", Vector2.ZERO, "")


func _replay_demo() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(9.0, false).timeout
	replay.capture("goal", "%s GOAL  ·  TEST" % team_name(0), [lineup(0).on_ice[0]], 6.0, 0.5,
			{"play_now": true, "speed": 0.8, "cam": "net", "net": rink.attacked_net(0).global_position})
	await replay.finished
	await get_tree().create_timer(3.0, false).timeout
	var a: Skater = lineup(0).on_ice[1]
	var b: Skater = lineup(1).on_ice[1]
	replay.capture("hit", "BIG HIT  ·  %s" % MenuStyle.player_name(a), [a, b], 3.0, 0.3, {"play_now": true, "speed": 0.4, "cam": "orbit"})


func _bench_demo() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.5, false).timeout
	for t in 2:
		for k in 2:
			_send_to_box(t, lineup(t).on_ice[0], 60.0)
	while is_inside_tree():
		await get_tree().create_timer(3.0, false).timeout
		_bench_react(0, "cheer")
		_bench_react(1, "groan")
		await get_tree().create_timer(4.0, false).timeout
		_bench_react(1, "laugh")


func _debug_doors() -> void:
	while is_inside_tree():
		for t in 2:
			rink.open_door(rink.bench_door_id(t, 0), 1.5)
			rink.open_door(rink.bench_door_id(t, 1), 1.5)
			rink.open_door(rink.box_door_id(t), 1.5)
		await get_tree().create_timer(3.5).timeout


func _hud_demo() -> void:
	if _hud == null:
		return
	var t := get_tree()
	await t.process_frame   # the first frame's delta is the whole load time
	await t.create_timer(3.0, true, false, true).timeout
	var a: Array[Skater] = lineup(0).all_skaters()
	box.add(a[0], "g")
	_hud.banner("POWER-PLAY GOAL!", 3.0, 0)
	_hud.goal_card(0, a[0], [a[1], a[3]], 3.0)
	await t.create_timer(3.6, true, false, true).timeout
	_hud.banner("BIG HIT!", 1.6, 1)
	_hud.flash("DELAYED PENALTY — %s" % team_name(1))
	await t.create_timer(2.2, true, false, true).timeout
	_hud.penalty_card(1, lineup(1).all_skaters()[2], "Tripping", "2:00", 3.0)
	lineup(1).send_to_box(lineup(1).all_skaters()[2])


func _open_stats_for_shot(final: bool, wait: float) -> void:
	if wait > 0.0:
		await get_tree().process_frame
		await get_tree().create_timer(wait, true, false, true).timeout
	if _intermission == null:
		_open_intermission(final)


## Final stats, after the final banner has shown for a few seconds.
func _open_final() -> void:
	await get_tree().create_timer(4.0, false).timeout   # (waits out any replay)
	while replay and replay.busy():
		await replay.finished
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
		var was := lineup(t).box_count()
		for s in lineup(t).tick_box(delta):
			_return_from_box(t, s)
		if lineup(t).box_count() < was:
			penalty_expired.emit(t)


func _return_from_box(t: int, s: Skater) -> void:
	var lu := lineup(t)
	s.in_box_spot = false
	if format == 5 and lu.on_ice.size() < strength(t):
		# Out the box door and back into play.
		var door := rink.box_door_id(t)
		lu.on_ice.append(s)
		s.set_benched(false)
		s.walk([rink.door_point(door, 0.7), rink.door_point(door, -0.8), rink.door_point(door, -2.0)],
				WALK_SPEED, -Vector3(RinkSpec.BOX_SIDE, 0, 0))
		rink.open_door(door, 1.0)
		return
	s.repark()   # not needed out there: back to the bench
	if format == 3:
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
		var gate: Vector3 = rink.bench_gate(t)
		for s in lu.on_ice.duplicate():
			if s.changing and not s.has_puck() and s.global_position.distance_to(gate) < 2.5:
				var from: Vector3 = s.global_position
				var inn := lu.swap_at_gate(s)
				if inn:
					_change_through_doors(t, s, from, inn)
					stats.changes[t] += 1


## A line change: the tired skater goes off through the bench door nearer them, the
## fresh one comes on through the other, each door swinging open as they reach it.
func _change_through_doors(t: int, out: Skater, from: Vector3, inn: Skater) -> void:
	var d0 := rink.bench_door_id(t, 0)
	var d1 := rink.bench_door_id(t, 1)
	var near := d0 if from.distance_to(rink.door_point(d0, 0.0)) < from.distance_to(rink.door_point(d1, 0.0)) else d1
	var other := d1 if near == d0 else d0
	out.global_position = from
	_walk_through(out, near, [rink.door_point(near, -0.7)], [rink.door_point(near, 0.7), out.bench_spot],
			Vector3(-RinkSpec.BENCH_SIDE, 0, 0))
	inn.global_position = inn.bench_spot
	_walk_through(inn, other, [rink.door_point(other, 0.7)], [rink.door_point(other, -0.8), rink.door_point(other, -2.2)],
			Vector3(-RinkSpec.BENCH_SIDE, 0, 0))


## Walks `s` along `to_door` (ending at the door), through it and along `after`, opening
## the door just before they get there.
func _walk_through(s: Skater, door: String, to_door: Array, after: Array, face: Vector3, done := Callable()) -> void:
	var dist := 0.0
	var p := s.global_position
	for q: Vector3 in to_door:
		dist += p.distance_to(q)
		p = q
	var t_door := dist / WALK_SPEED
	s.walk(to_door + after, WALK_SPEED, face, done)
	if t_door < 0.35:
		rink.open_door(door, 1.1)
	else:
		get_tree().create_timer(t_door - 0.35, false).timeout.connect(func() -> void: rink.open_door(door, 1.1))


## A player headed to the box: they skate from where they are through the box door to
## their seat (the box keeps up to three).
func _send_to_box(t: int, s: Skater, seconds: float, counts := true, delay := 0.0) -> void:
	var from := s.global_position
	var on_ice := not s.benched
	s.box_spot = rink.box_spot(t, lineup(t).in_box.size())
	s.in_box_spot = true
	lineup(t).send_to_box(s, seconds, counts)
	if not on_ice:
		return
	s.global_position = from
	if delay > 0.0:
		# Waits on the ice for the referee's call (standing, not sitting down yet).
		s.heading = (s.heading if s.heading.length() > 0.1 else Vector3.FORWARD)
		if s.visual:
			s.visual.bench_off()
			s.visual.process_mode = Node.PROCESS_MODE_PAUSABLE
		get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			# (Skipped meanwhile: they're already on the box seat, off the ice.)
			if is_instance_valid(s) and s.benched and s.in_box_spot and not s.walking() 					and RinkSpec.sdf(s.global_position.x, s.global_position.z) < 0.0:
				_box_walk(t, s))
		return
	_box_walk(t, s)


func _box_walk(t: int, s: Skater) -> void:
	var door := rink.box_door_id(t)
	_walk_through(s, door, [rink.door_point(door, -0.8)], [rink.door_point(door, 0.7), s.box_spot],
			-Vector3(RinkSpec.BOX_SIDE, 0, 0), func() -> void:
				if is_instance_valid(s) and s.benched and s.visual:
					s.visual.bench_react("sulk"))


## Seconds `s` takes to skate from where they are into team `t`'s box.
func _box_walk_time(t: int, s: Skater) -> float:
	var door := rink.box_door_id(t)
	var pts := [s.global_position, rink.door_point(door, -0.8), rink.door_point(door, 0.7), rink.box_spot(t, lineup(t).in_box.size())]
	var d := 0.0
	for i in range(1, pts.size()):
		d += (pts[i] as Vector3).distance_to(pts[i - 1])
	return d / WALK_SPEED


## The penalty call: the referee points at the offender, then at the box, and the camera
## follows the offender into it. Holds the stoppage until it's done (or skipped).
func _penalty_cutscene(t: int, s: Skater) -> void:
	var walk := minf(_box_walk_time(t, s), 7.0)
	var door := rink.box_door_id(t)
	var off_at := s.global_position
	var cs := Cutscene.new()
	cs.name = "PenaltyCall"
	_pen_cut = cs
	referee.signal_arm = "point"
	referee.point_at = off_at
	# Stopped and squared up to the offender (the cut to this shot hides the snap).
	var to_off := off_at - referee.global_position
	to_off.y = 0.0
	referee.place(referee.global_position, to_off if to_off.length() > 0.2 else Vector3.RIGHT)
	_ref_brain.hold = referee.global_position
	_ref_brain.face_at = off_at
	_send_to_box(t, s, Lineup.MINOR, true, PENALTY_CALL)
	var ref := referee
	cs.shots.append({"len": PENALTY_CALL, "fov": 40.0, "frame": func(_t: float) -> Array:
		# On the referee, from the offender's side, a little off to one side.
		var to := off_at - ref.global_position
		to.y = 0.0
		var dir := to.normalized() if to.length() > 0.2 else Vector3.RIGHT
		var side := dir.cross(Vector3.UP)
		var pos := ref.global_position + dir * 3.4 + side * 1.4 + Vector3.UP * 1.55
		var c := RinkSpec.clamp_inside(pos.x, pos.z, 0.5)
		return [Vector3(c.x, pos.y, c.y), ref.global_position + Vector3.UP * 1.25]})
	cs.shots.append({"len": walk + 1.3, "fov": 44.0,
		"start": func() -> void:
			ref.point_at = rink.door_point(door, 0.0)
			_ref_brain.face_at = rink.door_point(door, 0.0),
		"frame": func(_t: float) -> Array:
			# Following the offender from the ice side, ahead of them toward the box.
			var p := s.global_position if is_instance_valid(s) else off_at
			var pos := p + Vector3(-RinkSpec.BOX_SIDE * 4.2, 2.5, 2.2 * (1.0 if p.z <= 0.0 else -1.0))
			var c := RinkSpec.clamp_inside(pos.x, pos.z, 0.6)
			return [Vector3(c.x, pos.y, c.y), p + Vector3.UP * 0.95]})
	cs.on_skip = func() -> void:
		if is_instance_valid(s) and s.benched and s.in_box_spot:
			s.place(s.global_position)   # cuts the walk short
			s.repark()                   # straight onto the box seat
	cs.finished.connect(func(skipped: bool) -> void:
		_pen_cut = null
		referee.signal_arm = ""
		_ref_brain.hold = Vector3.INF
		_ref_brain.face_at = Vector3.INF
		if phase == Phase.STOPPAGE:
			_stoppage_len = minf(_stoppage_len, _phase_time + (0.5 if skipped else 0.2)))
	add_child(cs)
	cs.play()
	_stoppage_len = maxf(_stoppage_len, PENALTY_CALL + walk + 1.3 + 0.5)


## The period opener: the starting lines (goalies first) file out of the bench doors and
## skate to their faceoff spots while the camera takes in each bench and then sweeps the
## rink. PREGAME waits for it; skipping puts everyone straight on their spots.
func _period_opener() -> void:
	if not show_hud:
		return
	var targets := {}       # Skater -> [spot, facing]
	var walks := []         # [skater, door, start delay]
	var t_end := 0.0
	for t in 2:
		var lu := lineup(t)
		var list: Array[Skater] = []
		if lu.goalie:
			list.append(lu.goalie)
		list.append_array(lu.on_ice)
		var per_door := [0, 0]
		for k in list.size():
			var s := list[k]
			targets[s] = [s.global_position, s.heading]
			var di := k % 2
			var door := rink.bench_door_id(t, di)
			var q: int = per_door[di]
			per_door[di] += 1
			# Waiting in the doorway, one behind the other, facing the ice.
			var start := rink.door_point(door, 0.8 + 0.55 * q)
			s.velocity = Vector3.ZERO
			s.process_mode = Node.PROCESS_MODE_DISABLED
			s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			s.global_position = start
			s.heading = Vector3(-RinkSpec.BENCH_SIDE, 0, 0)
			if s.visual:
				s.visual.process_mode = Node.PROCESS_MODE_PAUSABLE
				s.visual.snap()
			var delay := 0.5 + 0.55 * q + 1.6 * t
			walks.append([s, door, delay])
			var path_len: float = start.distance_to(rink.door_point(door, -1.2)) + rink.door_point(door, -1.2).distance_to(targets[s][0])
			t_end = maxf(t_end, delay + path_len / WALK_SPEED)
	var cs := Cutscene.new()
	cs.name = "PeriodOpener"
	_opener = cs
	var done := {"skipped": false}
	for w in walks:
		var s: Skater = w[0]
		var door: String = w[1]
		get_tree().create_timer(w[2], false).timeout.connect(func() -> void:
			if done.skipped or not is_instance_valid(s):
				return
			_walk_through(s, door, [rink.door_point(door, 0.7)], [rink.door_point(door, -1.2), targets[s][0]],
					targets[s][1], func() -> void:
						if s is Goalie:
							(s as Goalie).reset_in_net()))
	for t in 2:
		var z: Vector2 = RinkSpec.BENCH_Z[t]
		var zmid := (z.x + z.y) * 0.5
		var sg := signf(zmid)
		cs.shots.append({"len": 2.6, "fov": 40.0, "frame": func(tt: float) -> Array:
			# Down the boards at the bench, the team filing out of its doors.
			var pos := Vector3(RinkSpec.BENCH_SIDE * (RinkSpec.HALF_W - 7.5), 2.3, zmid + sg * (7.5 + tt * 0.5))
			return [pos, Vector3(RinkSpec.BENCH_SIDE * (RinkSpec.HALF_W - 2.0), 0.9, zmid)]})
	var sweep := maxf(2.5, t_end - 5.2 + 0.8)
	cs.shots.append({"len": sweep, "fov": 50.0,
		"start": func() -> void:
			if _hud:
				_hud.banner("OVERTIME" if period > periods else "%s PERIOD" % period_name(period), 2.2),
		"frame": func(tt: float) -> Array:
			# High and wide, sweeping around center ice as the lines settle in.
			var ang := 0.9 + tt * 0.22
			return [Vector3(sin(ang) * 14.0, 6.5, cos(ang) * 14.0), Vector3(0, 0.4, 0)]})
	var settle := func() -> void:
		for s: Skater in targets:
			if not is_instance_valid(s):
				continue
			if s.walking() or s.process_mode == Node.PROCESS_MODE_DISABLED:
				s.place(targets[s][0], targets[s][1])
				s._resume_live()
			if s is Goalie:
				(s as Goalie).reset_in_net()
	cs.on_skip = func() -> void:
		done.skipped = true
		settle.call()
	cs.finished.connect(func(_skipped: bool) -> void:
		settle.call()   # (anyone still on the way: on their spot)
		_opener = null)
	add_child(cs)
	cs.play()


## The goal celebration: the scorer peels off to the corner glass by the net and the
## linemates pile in around them, cheering, while the camera follows; then the replay.
func _goal_celebration(t: int, scorer: Skater, net: Vector3) -> void:
	var nz := signf(net.z) if absf(net.z) > 0.1 else 1.0
	var sx := signf(scorer.global_position.x) if absf(scorer.global_position.x) > 0.5 else 1.0
	var raw := Vector3(sx * (RinkSpec.HALF_W - 1.1), 0.0, nz * (RinkSpec.GOAL_LINE_Z - 4.0))
	var c := RinkSpec.clamp_inside(raw.x, raw.z, 1.1)
	var spot := Vector3(c.x, 0.0, c.y)
	# Toward the ice from the boards there, and along them.
	var inward := -Vector3(spot.x, 0.0, spot.z * 0.35).normalized()
	var along := inward.cross(Vector3.UP)
	var offsets := [inward * 1.0 + along * 0.85, inward * 1.0 - along * 0.85, inward * 1.9, along * 1.5, -along * 1.5]
	var saved := {}
	var mates: Array[Skater] = [scorer]
	for s in lineup(t).on_ice:
		if s != scorer and not s.benched and mates.size() < 5:
			mates.append(s)
	for i in mates.size():
		var s := mates[i]
		var target: Vector3 = spot if i == 0 else spot + offsets[(i - 1) % offsets.size()]
		var cl := RinkSpec.clamp_inside(target.x, target.z, 0.9)
		var b := CelebrateBrain.new(Vector3(cl.x, 0.0, cl.y), spot, true)
		b.arrived.connect(func(who: Skater) -> void:
			if is_instance_valid(who) and who.visual:
				who.visual.celebrate())
		saved[s] = s.brain
		s.brain = b
	var cs := Cutscene.new()
	cs.name = "GoalCelebration"
	cs.shots.append({"len": 1.8, "fov": 42.0, "frame": func(_t: float) -> Array:
		# Out in front of the scorer as they peel away, looking back at them.
		var p := scorer.global_position if is_instance_valid(scorer) else spot
		var dir := spot - p
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.5 else inward * -1.0
		var pos := p + dir * 5.5 + dir.cross(Vector3.UP) * 1.4 + Vector3.UP * 1.6
		var cc := RinkSpec.clamp_inside(pos.x, pos.z, 0.5)
		return [Vector3(cc.x, pos.y, cc.y), p + Vector3.UP * 1.1]})
	cs.shots.append({"len": 2.5, "fov": 38.0, "frame": func(_t: float) -> Array:
		# The huddle against the glass, from the ice.
		# A little high, so skaters passing in front don't block the huddle.
		var pos := spot + inward * 5.2 + along * 1.6 + Vector3.UP * 2.6
		return [pos, spot + inward * 0.9 + Vector3.UP * 1.0]})
	cs.finished.connect(func(_skipped: bool) -> void:
		for s: Skater in saved:
			if is_instance_valid(s) and s.brain is CelebrateBrain:
				s.brain = saved[s]
		if replay:
			replay.play_soon("goal")
		if phase == Phase.STOPPAGE:
			_stoppage_len = minf(_stoppage_len, _phase_time + 0.8))
	add_child(cs)
	cs.play()
	if phase == Phase.STOPPAGE:
		_stoppage_len = maxf(_stoppage_len, 1.8 + 2.5 + 0.6)


## The referee: a striped Skater (Referee) skated by a RefBrain, outside both teams.
func _make_referee() -> void:
	var r: Skater = SKATER_SCENE.instantiate()
	r.set_script(Referee)
	referee = r as Referee
	referee.name = "Referee"
	referee.number = 27
	referee.body_type = "male"
	referee.skin_tone = SkaterVisual.SKIN_TONES[_rng.randi() % SkaterVisual.SKIN_TONES.size()]
	referee.gear_style = 0
	_set_look(referee, SkaterVisual.random_look(_rng, "male", referee.skin_tone))
	referee.stats = PlayerStats.new()
	referee.puck = puck
	referee.rink = rink
	_ref_brain = RefBrain.new(self)
	referee.brain = _ref_brain
	add_child(referee)
	referee.place(Vector3(-RinkSpec.HALF_W + 2.2, 0, 3.0), Vector3.RIGHT)


## A bench spot for `s` (parking now): their current one if no one else has it, else the
## first free seat, else the first free place standing at the boards. [spot, seated]
func _claim_bench(s: Skater, t: int) -> Array:
	var lu := lineup(t)
	var taken := {}
	var who: Array = lu.all_skaters()
	who.append(lu.goalie)
	for o: Skater in who:
		if o != s and is_instance_valid(o) and o.benched and not o.in_box_spot and o.bench_spot != Vector3.INF:
			taken[o.bench_spot] = true
	var seats := rink.bench_seats(t)
	var i := 0
	while true:
		var p := rink.bench_spot(t, i)
		if i < 40 and taken.has(p):
			i += 1
			continue
		if s.bench_spot != Vector3.INF and not taken.has(s.bench_spot) and s.bench_sit == (i < seats):
			return [s.bench_spot, s.bench_sit]   # keep their place if it's as good
		return [p, i < seats]
	return [rink.bench_spot(t, 0), true]


## Players parked on team `t`'s bench and in its box react ("cheer", "groan", "laugh"),
## each with a chance and a moment's delay, so it ripples instead of moving as one.
func _bench_react(t: int, kind: String, chance := 1.0) -> void:
	var lu := lineup(t)
	var who: Array = lu.all_skaters()
	who.append(lu.goalie)
	for s: Skater in who:
		if not is_instance_valid(s) or not s.benched or s.walking() or s.visual == null:
			continue
		if randf() > chance:
			continue
		var k := kind
		if s.in_box_spot and kind == "cheer":
			k = "cheer" if randf() < 0.5 else "sulk"   # happy, but still in the box
		get_tree().create_timer(randf_range(0.0, 0.5), false).timeout.connect(func() -> void:
			if is_instance_valid(s) and s.benched and not s.walking():
				s.visual.bench_react(k))


## End of a period or the game: up to two saved highlights nobody has seen yet.
func _period_highlights() -> void:
	if replay == null or not show_hud:
		return
	if replay.busy():
		await replay.finished
	replay.play_pending(2)


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
		# Anyone off the ice who isn't on their way somewhere stands at their spot.
		for s in lu.all_skaters():
			if s.benched and not s.walking():
				s.repark()
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
	faceoff_won.emit(winner)
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
			s.in_box_spot = false
			s.repark()
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
	if rink.arena:
		rink.arena.goal(scoring)
	var scorer := puck.last_touch
	var beaten := lineup(other).goalie
	var pp := strength(scoring) > strength(other) and lineup(other).box_count() > 0
	var assists := box.on_goal(scorer, scoring, lineup(scoring).on_ice, lineup(other).on_ice, beaten, pp)
	goal.emit(scoring, scorer)
	_bench_react(scoring, "cheer")
	_bench_react(other, "groan", 0.8)
	cam.shake(0.6)
	# Horn and crowd: MatchAudio (on the goal signal).
	for s in lineup(scoring).on_ice:
		s.visual.celebrate()
	if beaten and randf() < 0.6:
		beaten.visual.play_clip("angry_gesture", Vector3(0.0, 0.7, 1.0), 2.0, 1.1, 0.25)
	# A delayed penalty against the team scored on is wiped out by the goal.
	rules.pending[other] = null
	if pp:
		stats.pp_goals[scoring] += 1
		var freed := lineup(other).release_earliest()
		if freed:
			freed.in_box_spot = false
			freed.repark()
	if _hud and scorer and scorer.team == scoring:
		_hud.goal_card(scoring, scorer, assists, 3.4)
	# With a scorer to follow, the celebration plays first and the replay after it.
	var celebrate := show_hud and scorer != null and scorer.team == scoring and not scorer.benched
	if replay and show_hud:
		var who := ("  ·  " + MenuStyle.player_name(scorer)) if scorer and scorer.team == scoring else ""
		replay.capture("goal", "%s GOAL%s" % [team_name(scoring), who], [scorer], 5.0, 1.2,
				{"play_now": not celebrate, "speed": 0.8, "cam": "net", "net": rink.get_net(net_index).global_position})
	if period > periods:
		_finish("%s WIN IN OT!" % team_name(scoring), scoring)
	else:
		_stoppage(3.0, Vector2.ZERO, "%sGOAL!" % ("POWER-PLAY " if pp else ""), scoring)
	if celebrate:
		_goal_celebration(scoring, scorer, rink.get_net(net_index).global_position)


func _on_puck_touched(s: Skater) -> void:
	rules.on_touched(s)
	if phase == Phase.LIVE:
		box.on_touch(s)


func _on_shot(s: Skater, _kind: StringName, _spd: float) -> void:
	if phase == Phase.LIVE and not (s is Goalie):
		stats.shots[s.team] += 1
		box.add(s, "shots")


## Shots on goal = the other goalie's saves + goals.
func shots_on_goal(t: int) -> int:
	return stats.saves[1 - t] + score[t]


func _on_save(g: Goalie, _kind: StringName) -> void:
	if phase == Phase.LIVE:
		stats.saves[g.team] += 1
		box.add(g, "sv")
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
	box.add(attacker, "hits")
	if kind == &"big_hit":
		stats.big_hits[attacker.team] += 1
		box.add(attacker, "big_hits")
		if replay and show_hud:
			replay.capture("hit", "BIG HIT  ·  %s" % MenuStyle.player_name(attacker), [attacker, victim], 1.8, 1.2,
					{"speed": 0.4, "cam": "orbit"})
		_bench_react(attacker.team, "cheer", 0.5)
		cam.shake(0.9)
		_slowmo(0.45)
		if _hud:
			_hud.banner("BIG HIT!" if not boards else "CRUSHED INTO THE BOARDS!", 1.4, attacker.team)
	elif kind == &"check":
		cam.shake(0.35)


func _slowmo(real_seconds: float) -> void:
	Engine.time_scale = 0.35
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0
