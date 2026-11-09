extends Node3D
## M1 practice: you (#19) plus four teammates attacking the top net, with three
## stationary "pylon" defenders to deke around. No goalie yet (M2).
##
## Controls (pad / keyboard):
##   Left stick / WASD  skate          RT / Shift   turbo
##   A / J   pass (hold = saucer); without the puck = switch player
##   X / K   shoot (tap = wrist, hold = slap); hold while a pass comes = one-timer
##   Y / I   deke                      LT / Space   protect puck
##   R reset · C / Back camera · Esc / Start pause menu
##
## Command-line (after `--`): cam=…, shot=<png>, wait=<s>, demo=carry|windup|pass, pausemenu[=controls]

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")

const HOME_COLOR := Color(0.78, 0.1, 0.12)
const PYLON_COLOR := Color(0.15, 0.3, 0.75)
const ROSTER := [
	{"number": 19, "spot": Vector3(0, 0, 1.5), "left": true},
	{"number": 11, "spot": Vector3(-8, 0, -17), "left": true},
	{"number": 27, "spot": Vector3(8, 0, -17), "left": false},
	{"number": 4, "spot": Vector3(-6, 0, -8.5), "left": true},
	{"number": 44, "spot": Vector3(6, 0, -8.5), "left": false},
]
const PYLONS := [Vector3(-2.5, 0, -13.5), Vector3(3.0, 0, -19.5), Vector3(-1.0, 0, -4.0)]

@onready var rink: Rink = $Rink
@onready var puck: Puck = $Puck
@onready var cam: BroadcastCamera = $Camera
@onready var sun: DirectionalLight3D = $Sun

var home: Array[Skater] = []
var pylons: Array[Skater] = []
var control: TeamControl
var score := 0
var last_shot := "-"
var _info: Label
var _banner: Label
var _banner_time := 0.0
var _reset_in := -1.0
var _marked: Skater


## The play angle (pause menu / GameSettings); practice never turns with the ends.
var camera := "broadcast"
var camera_follow := false


func apply_camera(angle: String, _follow: bool) -> void:
	camera = angle
	cam.set_mode_name(angle)


func human_team() -> int:
	return -1


func _ready() -> void:
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	_build_hud()
	apply_camera(str(GameSettings.config.get("camera", "broadcast")), false)

	for entry in ROSTER:
		var s := _spawn(0, entry.number, HOME_COLOR, entry.left)
		s.ai_brain = HoldSpotBrain.new(entry.spot)
		s.shot_released.connect(_on_shot)
		home.append(s)
	for s in home:
		s.teammates = home
	for i in PYLONS.size():
		var p := _spawn(1, 90 + i, PYLON_COLOR, true)
		p.handles_puck = false
		p.ai_brain = HoldSpotBrain.new(PYLONS[i], false)
		p.brain = p.ai_brain
		pylons.append(p)

	control = TeamControl.new(0, home, home, [HumanBrain.new()] as Array[HumanBrain], puck)
	rink.goal_scored.connect(_on_goal)
	puck.left_play.connect(func() -> void:
		_show_banner("OUT OF PLAY")
		_reset_in = 1.0)
	_faceoff()
	_handle_cmdline()


func _spawn(team: int, number: int, color: Color, left: bool) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate()
	s.team = team
	s.number = number
	s.team_color = color
	s.shoots_left = left
	s.stats = PlayerStats.new()
	s.puck = puck
	s.rink = rink
	add_child(s)
	return s


func _faceoff() -> void:
	_reset_in = -1.0
	puck.place(Vector3.ZERO)
	for i in home.size():
		home[i].place(ROSTER[i].spot, Vector3.FORWARD)
		home[i].stamina = 1.0
	for i in pylons.size():
		pylons[i].place(PYLONS[i], Vector3.BACK)
	puck.place(home[0].puck_anchor())
	puck.attach(home[0])
	control.set_controlled(control.primary(), home[0])
	rink.rearm_nets()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_faceoff()
			KEY_ESCAPE:
				_open_pause()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		_open_pause()


var _pause: PauseMenu


## Esc / Start: the pause menu (resume, controls, restart, quit to the main menu).
func _open_pause() -> void:
	if _pause != null:
		return
	_pause = PauseMenu.new()
	_pause.mode = "PRACTICE"
	_pause.restart_text = "RESTART PRACTICE"
	_pause.camera_host = self
	add_child(_pause)
	_pause.closed.connect(func() -> void: _pause = null)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_camera"):
		cam.cycle_mode()
	# Show who a pass would go to right now.
	var target: Skater = null
	var c := control.controlled_skater()
	if c and c.has_puck():
		target = c.choose_pass_target(c.pass_aim_dir())
	if target != _marked:
		if _marked:
			_marked.visual.set_marker(false)
		if target:
			target.visual.set_marker(true)
		_marked = target


func _process(delta: float) -> void:
	cam.player = control.controlled_skater() if control else null
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.visible = _banner_time > 0.0
	if _reset_in > 0.0:
		_reset_in -= delta
		if _reset_in <= 0.0:
			_faceoff()
	var c := control.controlled_skater()
	var stamina_bar := "■".repeat(int(round(c.stamina * 10))) + "□".repeat(10 - int(round(c.stamina * 10)))
	_info.text = "KNOCKOUT HOCKEY — M1 practice   Goals %d\n" % score \
			+ "#%d  %3.0f km/h  %s  stamina %s\n" % [c.number, c.flat_speed() * 3.6, "TURBO" if c.turbo_active else "     ", stamina_bar] \
			+ "Puck %s   Last shot: %s\n" % ["carried" if puck.carrier else "%.0f km/h" % (puck.speed() * 3.6), last_shot] \
			+ "Camera %s   FPS %d\n\n" % [cam.mode_name(), Engine.get_frames_per_second()] \
			+ "Stick/WASD skate · RT/Shift turbo · LT/Space protect\n" \
			+ "A/J pass (hold = saucer) · no puck: switch player\n" \
			+ "X/K shoot (tap wrist, hold slap) · hold X for a pass = one-timer\n" \
			+ "Y/I deke · R reset · C camera · Esc pause"


func _on_shot(s: Skater, kind: StringName, spd: float) -> void:
	var names := {&"wrist": "Wrist", &"slap": "Slapper", &"one_timer": "ONE-TIMER"}
	last_shot = "%s #%d %.0f km/h" % [names.get(kind, str(kind)), s.number, spd * 3.6]


func _on_goal(_defending_side: int) -> void:
	score += 1
	_show_banner("GOAL!")
	_reset_in = 2.2


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_time = 2.0


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 5)
	layer.add_child(_info)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = 90
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 64)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.visible = false
	layer.add_child(_banner)


# --- Screenshot / demo hooks -------------------------------------------------

func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("cam"):
		var idx := BroadcastCamera.Mode.keys().find(str(args["cam"]).to_upper())
		if idx >= 0:
			cam.set_mode(idx as BroadcastCamera.Mode)
	match str(args.get("demo", "")):
		"carry":
			home[0].brain = ScriptBrain.new(func(_s: Skater, i: SkaterIntent, _t: float) -> void:
				i.move = Vector3(0.35, 0, -1).normalized()
				i.turbo = true)
		"windup":
			home[0].brain = ScriptBrain.new(func(_s: Skater, i: SkaterIntent, t: float) -> void:
				i.move = Vector3(0, 0, -1) if t < 1.2 else Vector3.ZERO
				i.shoot_down = t >= 1.2 and t - 1.0 / 120.0 < 1.2
				i.shoot_held = t >= 1.2)
		"pass":
			home[0].brain = ScriptBrain.new(func(_s: Skater, i: SkaterIntent, t: float) -> void:
				i.move = Vector3(-0.6, 0, -1).normalized() if t < 1.0 else Vector3.ZERO
				i.pass_down = t >= 1.0 and t - 1.0 / 120.0 < 1.0
				i.pass_up = i.pass_down)
	if args.has("trace"):
		for k in 6:
			await get_tree().create_timer(0.4).timeout
			var c := control.controlled_skater()
			print("t=%.1f  #%d pos=%s heading=%s  puck=%s carrier=%s  vis_puck=%s" % [
				0.4 * (k + 1), c.number, c.global_position, c.heading, puck.global_position,
				puck.carrier.number if puck.carrier else -1, puck.get_node("Visual").global_position])
		get_tree().quit()
	if args.has("pausemenu"):   # open the pause menu at once (screenshots); pausemenu=controls for that page
		_open_pause()
		if args["pausemenu"] == "controls":
			_pause._show_controls()
	if args.has("shot"):
		await get_tree().create_timer(float(args.get("wait", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(args["shot"]))
		get_tree().quit()
