extends Node3D
## Animation check: stages one moment in game conditions and saves a contact sheet of
## frames (left to right, top to bottom) to look at the motion.
##   `-- scene=skate|check|save sheet=<png>`
##   skate: a skater sprinting past, side on (`puck=1` carrying the puck, `coast=1` gliding)
##   check: a skater runs a check on another crossing in front (`big=1` harder)
##   save:  shots on the goalie at `at=<x>,<y>` (net frame: +x the goalie's left / glove
##          side, y up; m), `view=front|side`
## `every=<s>` between frames (default 0.07, game time), `frames=<n>` (default 16), `cols=<n>`,
## `slow=<scale>` slow motion while capturing, `trace=1` prints the goalie's save state.

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

var rink: Rink
var puck: Puck
var cam: Camera3D
var follow: Node3D
var cam_off := Vector3(0, 0.6, 6.0)
var look_off := Vector3(0, 0.9, 0)
var frames: Array[Image] = []
var _goalie: Goalie


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	add_child(sun)
	rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	add_child(rink)
	puck = (load("res://scenes/match/Puck.tscn") as PackedScene).instantiate()
	add_child(puck)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	match _arg("scene", "skate"):
		"skate":
			_skate()
		"check":
			_check()
		"save":
			_save()


func _skater(team: int, num: int, body: String, plan: Callable) -> Skater:
	var s: Skater = SKATER_SCENE.instantiate()
	s.team = team
	s.number = num
	s.body_type = body
	var info := Teams.team(team * 2)
	s.uniform = Teams.uniform_vs(team * 2, team * 2, false)
	s.team_color = info.colors.jersey
	s.puck = puck
	s.rink = rink
	s.brain = ScriptBrain.new(plan)
	add_child(s)
	return s


func _skate() -> void:
	var coast := _arg("coast", "") != ""
	var s := _skater(0, 19, _arg("body", "male"), func(_s: Skater, i: SkaterIntent, tt: float) -> void:
		i.move = Vector3.BACK if not (coast and tt > 2.2) else Vector3.ZERO
		i.turbo = _arg("turbo", "1") != "0")
	s.place(Vector3(0, 0, -20), Vector3.BACK)
	if _arg("puck", "") != "":
		puck.place(s.puck_anchor())
		puck.attach(s)
	follow = s
	cam_off = Vector3(3.0, 0.2, 0.3) if _arg("view", "side") == "side" else Vector3(4.0, 0.6, 4.0)
	_capture(float(_arg("start", "2.0")))


func _check() -> void:
	var big := _arg("big", "") != ""
	var victim := _skater(1, 4, "male", func(_s: Skater, i: SkaterIntent, _tt: float) -> void:
		i.move = Vector3(-0.5, 0, 0))
	victim.place(Vector3(3.0, 0, 0), Vector3.LEFT)
	var hitter := _skater(0, 27, _arg("body", "male"), func(sk: Skater, i: SkaterIntent, _tt: float) -> void:
		var to := victim.global_position - sk.global_position
		to.y = 0.0
		i.move = to.normalized()
		i.turbo = big
		i.check_down = to.length() < 2.4 and sk.state == Skater.State.SKATE and sk.since_check_landed > 2.0)
	hitter.place(Vector3(1.0, 0, -14), Vector3.BACK)
	hitter.opponents = [victim]
	victim.opponents = [hitter]
	follow = victim
	cam_off = Vector3(4.2, 0.5, -0.6)
	look_off = Vector3(0, 0.7, -1.0)
	# Start the sheet a little before the check lands.
	var start := 0.0
	while start < 8.0:
		await get_tree().physics_frame
		start += get_physics_process_delta_time()
		if hitter.state == Skater.State.CHECK:
			break
	_capture(0.0)


func _save() -> void:
	var g: Goalie = GOALIE_SCENE.instantiate()
	g.team = 1
	g.number = 31
	g.body_type = _arg("body", "male")
	g.stats = PlayerStats.new()
	var info := Teams.team(2)
	g.uniform = Teams.uniform_vs(2, 2, false)
	g.team_color = info.colors.jersey
	g.puck = puck
	g.rink = rink
	add_child(g)
	_goalie = g
	await get_tree().physics_frame
	g.net = rink.get_net(0)
	g.reset_in_net()
	var net := g.net
	var at := _arg("at", "0.9,1.1").split(",")
	var aim := Vector3(float(at[0]), float(at[1]), 0.0)
	# Settle in, then shoot from the slot.
	# `prep=<x>,<z>`: where the puck sits while the goalie settles (out of position for a
	# cross-crease shot), net frame.
	var prep := _arg("prep", "0,9").split(",")
	puck.place(net.to_global(Vector3(float(prep[0]), 0.03, float(prep[1]))))
	await get_tree().create_timer(1.2).timeout
	var from := net.to_global(Vector3(float(_arg("from", str(aim.x * 0.3))), 0.05, float(_arg("dist", "9"))))
	puck.place(from)
	var to := net.to_global(aim)
	var spd := float(_arg("speed", "28"))
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	var tt := d.length() / spd
	var v := d / tt
	v.y = (to.y - from.y + 0.5 * Puck.GRAVITY * tt * tt) / tt
	puck.launch(v)
	follow = net   # a fixed camera on the net: the goalie moves in it
	var side := _arg("view", "front") == "side"
	var out := net.global_basis.z
	cam_off = (out * 3.6 + Vector3(0, 0.3, 0)) if not side else (net.global_basis.x * 5.0 + out * 2.5)
	look_off = Vector3(0, 0.7, 0)
	_capture(maxf(0.0, tt - 0.25))


func _process(_delta: float) -> void:
	if follow != null and _arg("scene", "") != "save":
		var p := follow.global_position
		cam.look_at_from_position(p + cam_off, p + look_off)
	elif follow != null:
		var p2 := follow.global_position
		cam.look_at_from_position(p2 + cam_off, p2 + look_off)


func _capture(wait: float) -> void:
	await get_tree().create_timer(wait).timeout
	# `slow=<scale>`: slow motion while the frames are taken (timers run in game time,
	# so `every` stays in game seconds).
	Engine.time_scale = float(_arg("slow", "1"))
	var n := int(_arg("frames", "16"))
	var every := float(_arg("every", "0.07"))
	for k in n:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		frames.append(img)
		await get_tree().create_timer(every).timeout
	var cols := int(_arg("cols", "4"))
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var rows := ceili(float(n) / cols)
	var sheet := Image.create(w * cols, h * rows, false, frames[0].get_format())
	for k in n:
		sheet.blit_rect(frames[k], Rect2i(0, 0, w, h), Vector2i((k % cols) * w, (k / cols) * h))
	sheet.save_png(_arg("sheet", "user://anim_check.png"))
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _arg("trace", "") == "" or _goalie == null:
		return
	var g := _goalie
	var v := g.visual as GoalieVisual
	print("%.2f g=%d eta=%.2f saves=%d act=%s %s w=%.2f off=%s dx=%.2f puckz=%.2f" % [Time.get_ticks_msec() / 1000.0, g.g, g.read_eta, g.save_count,
		v._act_on, v._act_kind, v._act_w, v._save_offset() if v._act_on else Vector2.ZERO, g.net.to_local(g.global_position).x, g.net.to_local(puck.global_position).z])
