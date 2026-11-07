extends Node3D
## M0 sandbox: fire the puck around the rink to tune bounces and check goal detection.
##
## Mouse:   left click = flat pass to the clicked spot, right click = lifted shot there,
##          wheel = power.
## Pad/kbd: aim with the left stick / WASD, A or J = flat pass, X or K = lifted shot.
## Keys:    T = random blast, G = drop from 2 m, R = reset, Q/E = power, C / Back = camera.
##
## Command-line (after `--`): cam=broadcast|overhead|end_zone, shot=<png path>,
##          fire=x,z[,lift] (fires once at start), wait=<seconds before the screenshot>.

const MIN_POWER := 5.0
const MAX_POWER := 45.0
const LIFT_RATIO := 0.18

@onready var rink: Rink = $Rink
@onready var puck: Puck = $Puck
@onready var cam: BroadcastCamera = $Camera
@onready var sun: DirectionalLight3D = $Sun

var power := 25.0
var score := [0, 0]
var last_hit := "-"
var _info: Label
var _banner: Label
var _banner_time := 0.0
var _reset_in := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	_build_hud()
	rink.goal_scored.connect(_on_goal)
	puck.hit_surface.connect(_on_hit)
	puck.left_play.connect(_on_left_play)
	_reset_puck()
	_handle_cmdline()


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.visible = _banner_time > 0.0
	if _reset_in > 0.0:
		_reset_in -= delta
		if _reset_in <= 0.0:
			_reset_puck()
	_info.text = "KNOCKOUT HOCKEY — M0 rink sandbox\n" \
			+ "Score  home %d : %d away\n" % [score[0], score[1]] \
			+ "Puck   %.1f m/s  %s  y=%.2f\n" % [puck.speed(), "ice" if puck.on_ice else "air", puck.global_position.y] \
			+ "Power  %.0f m/s   Last hit: %s\n" % [power, last_hit] \
			+ "Camera %s   FPS %d\n\n" % [cam.mode_name(), Engine.get_frames_per_second()] \
			+ "LMB pass · RMB lifted shot · wheel/Q/E power\n" \
			+ "Stick/WASD aim · A/J pass · X/K shot\n" \
			+ "T blast · G drop · R reset · C camera"


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_camera"):
		cam.cycle_mode()
	var aim := InputRouter.move_world()
	if aim.length() < 0.2:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	if Input.is_action_just_pressed("pass"):
		puck.launch(aim * power)
	elif Input.is_action_just_pressed("shoot"):
		puck.launch(aim * power + Vector3.UP * power * LIFT_RATIO)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				var hit: Variant = _mouse_on_ice(event.position)
				if hit != null:
					_fire_at(hit, event.button_index == MOUSE_BUTTON_RIGHT)
			MOUSE_BUTTON_WHEEL_UP:
				power = minf(power + 2.5, MAX_POWER)
			MOUSE_BUTTON_WHEEL_DOWN:
				power = maxf(power - 2.5, MIN_POWER)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_reset_puck()
			KEY_T:
				var a := _rng.randf() * TAU
				var v := Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(15.0, MAX_POWER)
				if _rng.randf() < 0.3:
					v.y = v.length() * _rng.randf_range(0.1, 0.3)
				puck.launch(v)
			KEY_G:
				var p := puck.global_position
				puck.place(Vector3(p.x, 2.0, p.z))
				puck.launch(Vector3(_rng.randf_range(-2, 2), 0.0, _rng.randf_range(-2, 2)))
			KEY_Q:
				power = maxf(power - 5.0, MIN_POWER)
			KEY_E:
				power = minf(power + 5.0, MAX_POWER)


func _fire_at(point: Vector3, lifted: bool) -> void:
	var to := point - puck.global_position
	to.y = 0.0
	if to.length() < 0.01:
		return
	var v := to.normalized() * power
	if lifted:
		v.y = power * LIFT_RATIO
	puck.launch(v)


func _mouse_on_ice(screen_pos: Vector2) -> Variant:
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-4:
		return null
	var t := -origin.y / dir.y
	return origin + dir * t if t > 0.0 else null


func _reset_puck() -> void:
	_reset_in = -1.0
	puck.place(Vector3.ZERO)
	rink.rearm_nets()


func _on_goal(defending_side: int) -> void:
	var scorer := 1 - defending_side
	score[scorer] += 1
	_show_banner("GOAL!  %s" % ("HOME" if scorer == 0 else "AWAY"))
	_reset_in = 2.0


func _on_hit(surface: String, impact_speed: float, _at: Vector3) -> void:
	if impact_speed > 0.5:
		last_hit = "%s (%.1f m/s)" % [surface, impact_speed]


func _on_left_play() -> void:
	_show_banner("PUCK OUT OF PLAY")
	_reset_in = 1.0


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_time = 1.8


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
	_banner.add_theme_font_size_override("font_size", 56)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.visible = false
	layer.add_child(_banner)


func _handle_cmdline() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("cam"):
		var idx := BroadcastCamera.Mode.keys().find(str(args["cam"]).to_upper())
		if idx >= 0:
			cam.set_mode(idx as BroadcastCamera.Mode)
	if args.has("fire"):
		var f := str(args["fire"]).split(",")
		if f.size() >= 2:
			_fire_at(Vector3(f[0].to_float(), 0.0, f[1].to_float()), f.size() > 2 and f[2] == "lift")
	if args.has("shot"):
		await get_tree().create_timer(float(args.get("wait", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(args["shot"]))
		get_tree().quit()
