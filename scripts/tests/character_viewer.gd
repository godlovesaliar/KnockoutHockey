extends Node3D
## Close-up character check (M5). Lines up skaters doing different things in front of a
## perspective camera.  `-- shot=<png> wait=<s> view=front|side|back|goalie`
##   1 standing   2 skating a circle   3 slap-shot windup   4 knocked down
##   5 celebrating   6 stickhandling the puck   + a goalie behind them

const SKATER_SCENE := preload("res://scenes/actors/Skater.tscn")
const GOALIE_SCENE := preload("res://scenes/actors/Goalie.tscn")

var rink: Rink
var puck: Puck
var cam: Camera3D
var skaters: Array[Skater] = []
var goalie: Goalie


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.environment.ambient_light_energy = 0.45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	add_child(sun)
	rink = (load("res://scenes/match/Rink.tscn") as PackedScene).instantiate()
	add_child(rink)
	puck = (load("res://scenes/match/Puck.tscn") as PackedScene).instantiate()
	add_child(puck)

	var plans := [
		func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass,
		func(s: Skater, i: SkaterIntent, t: float) -> void:
			i.move = Vector3(cos(t * 0.9), 0, -sin(t * 0.9)) if t > 0.2 else Vector3.ZERO
			i.turbo = t > 1.0,
		func(_s: Skater, i: SkaterIntent, t: float) -> void:
			i.shoot_down = t > 0.3 and t < 0.3 + 1.0 / 120.0
			i.shoot_held = t > 0.3,
		func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass,
		func(_s: Skater, _i: SkaterIntent, _t: float) -> void: pass,
		func(_s: Skater, i: SkaterIntent, t: float) -> void:
			i.move = Vector3(sin(t * 1.3) * 0.4, 0, -0.3) if t > 0.3 else Vector3.ZERO,
	]
	for k in plans.size():
		var s: Skater = SKATER_SCENE.instantiate()
		s.team = k % 2
		s.number = [19, 4, 88, 27, 11, 91][k]
		_dress(s, int(_arg("home", "0")) if k % 2 == 0 else int(_arg("away", "2")))
		s.shoots_left = k % 3 == 0
		s.stats = PlayerStats.new()
		s.puck = puck
		s.rink = rink
		s.fatigue_enabled = false
		s.body_type = _arg("body", ["male", "female"][k % 2])
		s.skin_tone = SkaterVisual.SKIN_TONES[k % SkaterVisual.SKIN_TONES.size()]
		s.gear_style = int(_arg("style", str(k / 2)))
		add_child(s)
		s.brain = ScriptBrain.new(plans[k])
		s.place(Vector3(-5.0 + k * 2.0, 0, 2.0), Vector3.BACK)
		skaters.append(s)
	for s in skaters:
		s.teammates = skaters
	goalie = GOALIE_SCENE.instantiate()
	goalie.team = 1
	goalie.number = 31
	_dress(goalie, int(_arg("away", "2")))
	goalie.stats = PlayerStats.new()
	goalie.body_type = _arg("body", "female")
	goalie.gear_style = int(_arg("style", "0"))
	goalie.puck = puck
	goalie.rink = rink
	add_child(goalie)

	# Give the windup and stickhandling skaters a puck each (only one puck: the windup one).
	puck.place(skaters[2].puck_anchor())
	puck.attach(skaters[2])

	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	_set_view(_arg("view", "front"))
	_run()


func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _set_view(v: String) -> void:
	match v:
		"side":
			cam.look_at_from_position(Vector3(8, 1.6, 2.5), Vector3(0, 0.9, 2.0))
		"back":
			cam.look_at_from_position(Vector3(0, 1.8, -7.5), Vector3(0, 0.9, 2.0))
		"goalie":
			cam.look_at_from_position(Vector3(0, 1.4, 22.0), Vector3(0, 0.7, net_z()))
		"top":
			cam.look_at_from_position(Vector3(0, 18, 12), Vector3(0, 0, 2.0))
		_:
			cam.look_at_from_position(Vector3(0, 1.7, 10.5), Vector3(0, 0.9, 2.0))


func _process(_delta: float) -> void:
	if goalie and goalie.net:
		match _arg("save", ""):
			"glove":
				goalie.save_point = Vector2(0.6, 1.1)
				goalie.save_anim = 1.0
			"blocker":
				goalie.save_point = Vector2(-0.6, 0.9)
				goalie.save_anim = 1.0
			"butterfly":
				goalie.butterfly = true

	var f := int(_arg("focus", "-1"))
	if f < 0 or cam == null:
		return
	var s: Skater = goalie if f >= skaters.size() else skaters[f]
	var p := s.visual.global_position
	var off := Vector3(3.6, 1.2, 0.0)
	match _arg("view", "side"):
		"front":
			off = s.heading * 3.6 + Vector3(0, 1.0, 0)
		"back":
			off = -s.heading * 3.6 + Vector3(0, 1.4, 0)
		"high_back":
			off = -s.heading * 3.0 + Vector3(0, 6.0, 0)
		"quarter":
			off = (s.heading + s.right_dir()).normalized() * 3.6 + Vector3(0, 1.3, 0)
		_:
			off = s.right_dir() * 3.6 + Vector3(0, 1.0, 0)
	var look := p + Vector3(0, float(_arg("look_y", "0.85")), 0)
	off *= float(_arg("zoom", "1"))
	cam.look_at_from_position(look + off - Vector3(0, 0.85, 0) * (1.0 - float(_arg("zoom", "1"))), look)


func net_z() -> float:
	return goalie.net.global_position.z if goalie.net else 26.0


func _run() -> void:
	await get_tree().physics_frame
	goalie.net = rink.get_net(0)
	if goalie.has_method("reset_in_net"):
		goalie.reset_in_net()
	await get_tree().create_timer(0.3).timeout
	skaters[3].visual.play_clip("knocked_down", Vector3.ONE, -1.0, 1.7, 0.08)
	if _arg("clip", "") != "":
		skaters[4].visual.play_clip(_arg("clip", ""), Vector3(float(_arg("legs", "0")), 1, 1), -1.0)
	else:
		skaters[4].visual.celebrate()
	var shot := _arg("shot", "")
	if shot != "":
		await get_tree().create_timer(float(_arg("wait", "1.5"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


## Team uniform and crest (Teams.LIST index), as MatchDirector dresses players.
func _dress(s: Skater, team: int) -> void:
	var info := Teams.team(team)
	s.uniform = Teams.uniform_vs(team, team, false)
	s.team_color = info.colors.jersey
	if ResourceLoader.exists(info.get("logo", "")):
		s.crest = load(info.logo)
