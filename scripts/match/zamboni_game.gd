class_name ZamboniGame
extends Node
## The intermission fan contest: a lucky fan drives the Zamboni and lays as much fresh ice
## as they can before time runs out. It turns slowly (a big machine on a small radius) but
## goes quicker than the real thing. Going over ice again costs nothing; hitting the boards
## costs points. Start / Esc skips (the crew finishes the sheet either way).
##
## Driven by one human's device: R2 gas, L2 brake (then reverse once stopped), both
## analog; the left stick or d-pad steers. Keyboard: W / S and A / D (keyboard 2: the
## arrows). In single player any pad or either keyboard works.
##
## Stages: the contest-winner card over a shot of the fan at the wheel, then driving with
## a chase camera and a minimap, then the results card. `finished(skipped)` at the end.

signal finished(skipped: bool)

const TIME_LIMIT := 75.0
const TARGET := 0.9              ## coverage that counts as a full sheet (ends early, time bonus)
const SWEEP_HALF := 1.3          ## a wider strip than the crew's: a sheet is doable in the time
const MAX_SPEED := 9.0           ## m/s (the real thing does about 4)
const MAX_REVERSE := 3.0
const ACCEL := 3.2
const BRAKE := 9.0
const DRAG := 1.4
const MAX_STEER := 0.34          ## rad at the front wheels: about a 5.5 m turning radius
const STEER_RATE := 0.9          ## rad/s the wheel turns (slow, like the real thing)
const CRASH_SPEED := 1.8         ## m/s into the boards that counts as a crash
const CRASH_POINTS := 100
const INTRO_LEN := 4.0
const RESULTS_LEN := 4.5

enum Stage { INTRO, DRIVE, RESULTS, DONE }

var zamboni: Zamboni
var wear: IceWear
var brain: HumanBrain
var fan_name := "A LUCKY FAN"
var fan_seat := ""
var team_color := Color(0.86, 0.09, 0.11)
var autopilot := false           ## (testing) drives the crew's pattern itself

var stage := Stage.INTRO
var time_left := TIME_LIMIT
var crashes := 0
var score := 0
var _t := 0.0
var _pos := Vector2.ZERO
var _dir := Vector2(0, -1)
var _v := 0.0
var _steer := 0.0
var _crash_cool := 0.0
var _said_crash := -100.0
var _shake := 0.0
var _cam: Camera3D
var _prev_cam: Camera3D
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _layer: CanvasLayer
var _hud: Control
var _map: TextureRect
var _input: MenuInput
var _skipped := false
var _pad := true
var _flash := ""                 ## a brief callout ("CRASH! -100")
var _flash_t := 0.0
var _rating := ""
var _bonus := 0
var _ap_d := 0.0


func start() -> void:
	zamboni.sweep_half = SWEEP_HALF
	_pos = Vector2(0.0, RinkSpec.HALF_L - 3.0)
	_dir = Vector2(0, -1)
	zamboni.pose(_pos, _dir, 0.0, 0.0)
	_pad = brain == null or brain.kind == HumanBrain.Kind.PAD or (brain.kind == HumanBrain.Kind.ANY and Input.get_connected_joypads().size() > 0)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 400.0
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cam)
	_prev_cam = get_viewport().get_camera_3d()
	_cam.current = true
	_build_hud()
	_input = MenuInput.new()
	add_child(_input)
	_input.started.connect(_skip)
	_input.back.connect(_skip)
	_intro_camera(0.0, true)
	# The arena makes a thing of it.
	Sfx.pa("pa_zamboni_fan", 2)
	Sfx.announce_after("zamboni_fan", 2.2, 2)
	Sfx.crowd_react("cheer", -4.0, 1)
	if Sfx.has("organ_upbeat"):
		Sfx.play_organ("organ_upbeat", -6.0, true)


# --- Driving ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	_crash_cool = maxf(0.0, _crash_cool - delta)
	_shake = maxf(0.0, _shake - delta * 2.5)
	_flash_t = maxf(0.0, _flash_t - delta)
	match stage:
		Stage.INTRO:
			if _t >= INTRO_LEN:
				stage = Stage.DRIVE
				_t = 0.0
				_callout("GO!", 1.0)
		Stage.DRIVE:
			_drive(delta)
			time_left = maxf(0.0, time_left - delta)
			if time_left <= 0.0 or wear.coverage() >= TARGET:
				_results()
		Stage.RESULTS:
			_coast(delta)
			if _t >= RESULTS_LEN:
				_end()


func _process(delta: float) -> void:
	match stage:
		Stage.INTRO:
			_intro_camera(delta, false)
		Stage.DRIVE, Stage.RESULTS:
			_chase_camera(delta)
	if _hud:
		_hud.queue_redraw()


func _drive(delta: float) -> void:
	var c: Dictionary = _autopilot() if autopilot else _controls()
	var gas: float = c.gas
	var brake: float = c.brake
	# The wheel turns slowly toward where the stick points (right: steer right).
	var want := -clampf(c.steer, -1.0, 1.0) * MAX_STEER
	_steer = move_toward(_steer, want, STEER_RATE * delta)
	if gas > 0.05 and brake < 0.05:
		_v = minf(MAX_SPEED, _v + ACCEL * gas * delta) if _v >= 0.0 else _v + BRAKE * gas * delta
	elif brake > 0.05:
		_v = _v - BRAKE * brake * delta if _v > 0.3 else maxf(-MAX_REVERSE, _v - ACCEL * 0.6 * brake * delta)
	else:
		_v = move_toward(_v, 0.0, DRAG * delta)
	_move(delta)


## The driver's controls this frame: {gas, brake, steer} (gas and brake 0..1, steer -1
## left .. 1 right).
func _controls() -> Dictionary:
	var gas := 0.0
	var brake := 0.0
	var steer := 0.0
	var pads: Array = []
	var keys: Array = []   # [gas, brake, left, right] key lists
	var kind := brain.kind if brain else HumanBrain.Kind.ANY
	match kind:
		HumanBrain.Kind.PAD:
			pads = [brain.pad]
		HumanBrain.Kind.KB1:
			keys = [[KEY_W], [KEY_S], [KEY_A], [KEY_D]]
		HumanBrain.Kind.KB2:
			keys = [[KEY_UP], [KEY_DOWN], [KEY_LEFT], [KEY_RIGHT]]
		_:
			pads = Input.get_connected_joypads()
			keys = [[KEY_W, KEY_UP], [KEY_S, KEY_DOWN], [KEY_A, KEY_LEFT], [KEY_D, KEY_RIGHT]]
	for p: int in pads:
		gas = maxf(gas, _trigger(Input.get_joy_axis(p, JOY_AXIS_TRIGGER_RIGHT)))
		brake = maxf(brake, _trigger(Input.get_joy_axis(p, JOY_AXIS_TRIGGER_LEFT)))
		var x := Input.get_joy_axis(p, JOY_AXIS_LEFT_X)
		if absf(x) > 0.15 and absf(x) > absf(steer):
			steer = signf(x) * (absf(x) - 0.15) / 0.85
		if Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_LEFT):
			steer = -1.0
		elif Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_RIGHT):
			steer = 1.0
	if not keys.is_empty():
		if _any_key(keys[0]): gas = 1.0
		if _any_key(keys[1]): brake = 1.0
		if _any_key(keys[2]): steer = -1.0
		if _any_key(keys[3]): steer = 1.0
	return {"gas": gas, "brake": brake, "steer": steer}


static func _trigger(v: float) -> float:
	return clampf((v - 0.08) / 0.92, 0.0, 1.0)


static func _any_key(list: Array) -> bool:
	for k: Key in list:
		if Input.is_physical_key_pressed(k):
			return true
	return false


## Steers after a point a little way along the crew's laps, flat out; backs off the
## boards when it gets stuck.
var _ap_stuck := 0.0
var _ap_back := 0.0

func _autopilot() -> Dictionary:
	while _ap_d < zamboni.length and zamboni.point_at(_ap_d).distance_to(_pos) < 6.0:
		_ap_d += 0.5
	var to := (zamboni.point_at(_ap_d) - _pos).normalized()
	var ang := atan2(_dir.x * to.y - _dir.y * to.x, _dir.dot(to))
	var dt := get_physics_process_delta_time()
	_ap_stuck = _ap_stuck + dt if absf(_v) < 0.6 and _t > 1.0 else 0.0
	if _ap_stuck > 0.8:
		_ap_back = 1.5
		_ap_stuck = 0.0
	if _ap_back > 0.0:
		_ap_back -= dt
		return {"gas": 0.0, "brake": 1.0, "steer": -clampf(ang * 2.5, -1.0, 1.0)}
	return {"gas": 1.0, "brake": 0.0, "steer": clampf(ang * 2.5, -1.0, 1.0)}


## After the horn: rolls to a stop, still steering where it was.
func _coast(delta: float) -> void:
	_v = move_toward(_v, 0.0, BRAKE * 0.5 * delta)
	_move(delta)


func _move(delta: float) -> void:
	# Bicycle model: turning rate from speed, wheelbase and the front wheels' angle.
	var yaw := _v / Zamboni.WHEELBASE * tan(_steer) * delta
	_dir = _dir.rotated(-yaw).normalized()
	var step := _dir * _v * delta
	_pos += step
	_boards()
	zamboni.pose(_pos, _dir, _v * delta, _steer, _v > 0.2 and stage == Stage.DRIVE)


## Keeps it inside the boards; a hard hit is a crash.
func _boards() -> void:
	var right := Vector2(-_dir.y, _dir.x)
	var worst := 0.0
	var at := Vector2.ZERO
	for f: Vector2 in Zamboni.FOOTPRINT:
		# Local x is the machine's right, local -z its front.
		var w := _pos + right * f.x - _dir * f.y
		var d := RinkSpec.sdf(w.x, w.y)
		if d > worst:
			worst = d
			at = w
	if worst <= 0.0:
		return
	var e := 0.05
	var n := Vector2(RinkSpec.sdf(at.x + e, at.y) - RinkSpec.sdf(at.x - e, at.y),
			RinkSpec.sdf(at.x, at.y + e) - RinkSpec.sdf(at.x, at.y - e)).normalized()
	_pos -= n * (worst + 0.02)
	# How hard it went in: the speed along the boards' normal.
	var into := (_dir * _v).dot(n)
	if into > CRASH_SPEED and _crash_cool <= 0.0 and stage == Stage.DRIVE:
		_crash(into, Vector3(at.x, 0.6, at.y))
	if into > CRASH_SPEED:
		_v *= -0.25           # bounces off
	elif into > 0.3:
		_v *= 0.6             # a scrape: slows, keeps going along the boards


func _crash(speed: float, at: Vector3) -> void:
	crashes += 1
	_crash_cool = 1.0
	_shake = clampf(speed / MAX_SPEED, 0.4, 1.0)
	Sfx.play("boards", at, 6.0, 0.7)
	Sfx.crowd_react("ooh", 0.0, 2)
	_callout("CRASH!  -%d" % CRASH_POINTS, 1.4)
	if Time.get_ticks_msec() / 1000.0 - _said_crash > 6.0:
		_said_crash = Time.get_ticks_msec() / 1000.0
		Sfx.announce("zamboni_crash", 2)


func _results() -> void:
	stage = Stage.RESULTS
	_t = 0.0
	var cov := wear.coverage()
	_bonus = int(round(time_left * 10.0)) if cov >= TARGET else 0
	score = maxi(0, int(round(cov * 1000.0)) + _bonus - crashes * CRASH_POINTS)
	if score >= 1000:
		_rating = "HIRE THIS FAN"
	elif score >= 800:
		_rating = "FRESH SHEET"
	elif score >= 600:
		_rating = "PATCHY BUT PROUD"
	elif score >= 300:
		_rating = "THE CREW WILL FINISH UP"
	else:
		_rating = "BANNED FROM THE RESURFACER"
	var good := score >= 800 and crashes <= 1
	Sfx.crowd_react("cheer" if good else "disappointed", -2.0, 2)
	Sfx.play("horn", Vector3.INF, -8.0)
	Sfx.announce_after("zamboni_good" if good else "zamboni_bad", 0.8, 2)


func _skip() -> void:
	if stage == Stage.DONE or (stage == Stage.INTRO and _t < 0.4):
		return
	_skipped = true
	_end()


func _end() -> void:
	if stage == Stage.DONE:
		return
	stage = Stage.DONE
	if Sfx.organ_playing():
		Sfx.stop_organ(1.0)
	if is_instance_valid(_prev_cam):
		_prev_cam.current = true
	if _layer:
		_layer.queue_free()
	finished.emit(_skipped)
	queue_free()


# --- Cameras ---------------------------------------------------------------------------

## The fan at the wheel: slowly round the front of the machine.
func _intro_camera(delta: float, snap: bool) -> void:
	var z := zamboni.global_transform
	var seat := z * Zamboni.SEAT + Vector3(0, 0.9, 0)
	# The seat is at the back, behind the tank: come round from the left side toward the
	# rear quarter.
	var a := lerpf(0.15, 0.75, clampf(_t / INTRO_LEN, 0.0, 1.0))
	var off := Zamboni.SEAT + Vector3(-cos(a) * 3.4, 1.0, sin(a) * 3.4)
	var pos := z * off
	_place_camera(pos, seat, delta, snap)


## Behind and above, looking a little ahead; pulls back with speed.
func _chase_camera(delta: float) -> void:
	var p := Vector3(_pos.x, 0.0, _pos.y)
	var f := Vector3(_dir.x, 0.0, _dir.y)
	var back := 9.0 + absf(_v) * 0.3
	var pos := p - f * back + Vector3.UP * 6.8
	var look := p + f * 9.0
	_place_camera(pos, look, delta, false)


func _place_camera(pos: Vector3, look: Vector3, delta: float, snap: bool) -> void:
	if snap:
		_cam_pos = pos
		_cam_look = look
	else:
		_cam_pos = _cam_pos.lerp(pos, 1.0 - exp(-4.0 * delta))
		_cam_look = _cam_look.lerp(look, 1.0 - exp(-7.0 * delta))
	var jolt := Vector3.ZERO
	if _shake > 0.0:
		jolt = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
	_cam.look_at_from_position(_cam_pos + jolt, _cam_look)


# --- HUD -------------------------------------------------------------------------------

const MAP_SHADER := "
shader_type canvas_item;
// The rink on its side (length across): fresh ice from this pass in blue, the rest pale.
uniform sampler2D wear_map : filter_linear;
uniform vec2 ext = vec2(13.06, 30.6);
uniform vec2 half_size = vec2(12.954, 30.48);
uniform float corner_r = 8.5344;
void fragment() {
	vec2 muv = vec2(UV.y, UV.x);   // map u is across the rink (x), v along it (z)
	vec2 p = (muv * 2.0 - 1.0) * ext;
	vec2 q = abs(p) - (half_size - corner_r);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_r;
	float b = texture(wear_map, muv).b;
	vec3 col = mix(vec3(0.82, 0.85, 0.9), vec3(0.2, 0.55, 1.0), b);
	float edge = smoothstep(-0.6, -0.1, d);
	col = mix(col, vec3(0.1, 0.12, 0.18), edge);
	COLOR = vec4(col, (1.0 - smoothstep(0.0, 0.3, d)) * 0.92);
}
"
const MAP_SIZE := Vector2(270, 116)


## Bottom right of the (design-height) canvas, however wide the screen is.
func _map_rect() -> Rect2:
	return Rect2(Vector2(_hud.size.x - MAP_SIZE.x - 40.0, 690.0), MAP_SIZE)


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	_layer.add_child(_hud)
	MenuStyle.fit(_hud)
	get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(_hud):
			MenuStyle.fit(_hud))
	_map = TextureRect.new()
	_map.texture = wear.map_texture()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.size = MAP_SIZE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MAP_SHADER
	sm.shader = sh
	sm.set_shader_parameter("wear_map", wear.map_texture())
	sm.set_shader_parameter("ext", IceWear.EXT)
	sm.set_shader_parameter("half_size", Vector2(RinkSpec.HALF_W, RinkSpec.HALF_L))
	sm.set_shader_parameter("corner_r", RinkSpec.CORNER_RADIUS)
	_map.material = sm
	_map.visible = false
	_map.show_behind_parent = true   # (the position marker draws over it)
	_hud.add_child(_map)


func _callout(text: String, seconds: float) -> void:
	_flash = text
	_flash_t = seconds


func _draw_hud() -> void:
	var ci := _hud
	var f := MenuStyle.font(0.12)
	var w := _hud.size.x
	_map.position = _map_rect().position
	match stage:
		Stage.INTRO:
			_draw_winner_card(ci, f)
		Stage.DRIVE, Stage.RESULTS:
			_map.visible = true
			_draw_bar(ci, f, w)
			_draw_map_marker(ci)
			_draw_prompts(ci, f)
			if stage == Stage.RESULTS:
				_draw_results(ci, f)
	if _flash_t > 0.0 and _flash != "":
		var a := clampf(_flash_t * 2.0, 0.0, 1.0)
		var fs := 64
		var tw := f.get_string_size(_flash, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string_outline(f, Vector2((w - tw) * 0.5, 330), _flash, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0, 0, 0, a))
		ci.draw_string(f, Vector2((w - tw) * 0.5, 330), _flash, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))


func _panel(ci: CanvasItem, r: Rect2, accent: Color) -> void:
	ci.draw_rect(r, Color(0.04, 0.06, 0.12, 0.88))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), accent)


func _draw_winner_card(ci: CanvasItem, f: Font) -> void:
	var a := clampf(_t * 3.0, 0.0, 1.0) * clampf((INTRO_LEN - _t) * 3.0, 0.0, 1.0)
	var r := Rect2(90, 600, 760, 190)
	ci.draw_rect(r, Color(0.04, 0.06, 0.12, 0.9 * a))
	ci.draw_rect(Rect2(r.position, Vector2(14, r.size.y)), Color(team_color, a))
	ci.draw_string(f, r.position + Vector2(40, 46), "FAN CONTEST WINNER", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(MenuStyle.DIM, a))
	ci.draw_string(f, r.position + Vector2(40, 108), fan_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1, 1, 1, a))
	ci.draw_string(f, r.position + Vector2(40, 152), "%s  ·  DRIVES THE RESURFACER" % fan_seat, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(MenuStyle.ICE, a))
	# Get-ready line, and the goal.
	var g := "LAY FRESH ICE BEFORE TIME RUNS OUT. DON'T HIT THE BOARDS."
	var tw := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	ci.draw_string_outline(f, Vector2((_hud.size.x - tw) * 0.5, 120), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, Color(0, 0, 0, a))
	ci.draw_string(f, Vector2((_hud.size.x - tw) * 0.5, 120), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, a))
	_draw_prompts(ci, f)


func _draw_bar(ci: CanvasItem, f: Font, w: float) -> void:
	var r := Rect2((w - 900) * 0.5, 24, 900, 70)
	_panel(ci, r, team_color)
	var cov := wear.coverage()
	var cols := [
		["TIME", "%d:%02d" % [int(ceil(time_left)) / 60, int(ceil(time_left)) % 60]],
		["FRESH ICE", "%d%%" % int(floor(cov * 100.0))],
		["CRASHES", str(crashes)],
		["SCORE", str(maxi(0, int(round(cov * 1000.0)) - crashes * CRASH_POINTS) if stage == Stage.DRIVE else score)],
	]
	var cw := r.size.x / cols.size()
	for i in cols.size():
		var x: float = r.position.x + cw * i
		var label: String = cols[i][0]
		var value: String = cols[i][1]
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		ci.draw_string(f, Vector2(x + (cw - lw) * 0.5, r.position.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MenuStyle.DIM)
		var vw := f.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		var vc := Color(1, 0.45, 0.4) if (i == 0 and time_left < 10.0) or (i == 2 and crashes > 0) else Color.WHITE
		ci.draw_string(f, Vector2(x + (cw - vw) * 0.5, r.position.y + 60), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, vc)
	# Progress toward a full sheet.
	var pb := Rect2(r.position.x, r.end.y, r.size.x, 6)
	ci.draw_rect(pb, Color(0.1, 0.12, 0.18, 0.9))
	ci.draw_rect(Rect2(pb.position, Vector2(pb.size.x * clampf(cov / TARGET, 0.0, 1.0), pb.size.y)), Color(0.2, 0.55, 1.0))


func _draw_map_marker(ci: CanvasItem) -> void:
	var m := _map_rect()
	var u := Vector2(_pos.y / IceWear.EXT.y * 0.5 + 0.5, _pos.x / IceWear.EXT.x * 0.5 + 0.5)
	var c := m.position + u * m.size
	var fwd := Vector2(_dir.y, _dir.x).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	ci.draw_colored_polygon(PackedVector2Array([c + fwd * 9.0, c - fwd * 6.0 + side * 6.0, c - fwd * 6.0 - side * 6.0]), Color(1.0, 0.85, 0.15))


func _draw_prompts(ci: CanvasItem, f: Font) -> void:
	var items := []
	if _pad:
		items = [["R2", "GAS"], ["L2", "BRAKE"], ["START", "SKIP"]]
	else:
		var kb2 := brain != null and brain.kind == HumanBrain.Kind.KB2
		items = [["UP" if kb2 else "W", "GAS"], ["DOWN" if kb2 else "S", "BRAKE"], ["ESC", "SKIP"]]
	var x := 60.0
	var y := 830.0
	var steer := "STICK  STEER" if _pad else ("LEFT / RIGHT  STEER" if brain != null and brain.kind == HumanBrain.Kind.KB2 else "A / D  STEER")
	ci.draw_string_outline(f, Vector2(x, y + 24), steer, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
	ci.draw_string(f, Vector2(x, y + 24), steer, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	x += f.get_string_size(steer, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 34.0
	for it: Array in items:
		x += MenuStyle.draw_glyph(ci, Vector2(x, y), it[0], _pad, 32.0) + 10.0
		ci.draw_string_outline(f, Vector2(x, y + 24), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
		ci.draw_string(f, Vector2(x, y + 24), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
		x += f.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 30.0


func _draw_results(ci: CanvasItem, f: Font) -> void:
	var a := clampf(_t * 3.0, 0.0, 1.0)
	var r := Rect2((_hud.size.x - 600.0) * 0.5, 260, 600, 330)
	ci.draw_rect(r, Color(0.04, 0.06, 0.12, 0.92 * a))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), Color(team_color, a))
	var lines := [
		["FRESH ICE", "%d%%" % int(floor(wear.coverage() * 100.0))],
		["TIME BONUS", "+%d" % _bonus],
		["CRASHES", "%d  (-%d)" % [crashes, crashes * CRASH_POINTS]],
	]
	var title := fan_name.to_upper()
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	ci.draw_string(f, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + 56), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, a))
	for i in lines.size():
		var y: float = r.position.y + 112 + i * 42
		ci.draw_string(f, Vector2(r.position.x + 60, y), lines[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(MenuStyle.DIM, a))
		var vw := f.get_string_size(lines[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		ci.draw_string(f, Vector2(r.end.x - 60 - vw, y), lines[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, a))
	ci.draw_rect(Rect2(r.position.x + 60, r.position.y + 228, r.size.x - 120, 2), Color(1, 1, 1, 0.3 * a))
	var sc := "SCORE  %d" % score
	var sw := f.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
	ci.draw_string(f, Vector2(r.position.x + (r.size.x - sw) * 0.5, r.position.y + 278), sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1, 1, 1, a))
	var rw := f.get_string_size(_rating, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	ci.draw_string(f, Vector2(r.position.x + (r.size.x - rw) * 0.5, r.position.y + 314), _rating, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.85, 0.15, a))
